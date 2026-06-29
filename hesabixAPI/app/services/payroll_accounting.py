"""
پل حسابداری افزونه حقوق و دستمزد.

صدور سند تعهدی (accrual) و سند پرداخت (payment) با پیوند در payroll_document_links.
"""
from __future__ import annotations

import logging
from collections import defaultdict
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.payroll import (
	PayrollDocumentLink,
	PayrollItemDefinition,
	PayrollRun,
	PayrollRunLine,
	PayrollRunLineItem,
	PayrollSettings,
)
from app.core.responses import ApiError
from app.services.document_monetization_service import (
	ensure_document_policy_allows_creation,
	process_document_usage_for_document,
)
from app.services.document_numbering_service import generate_document_code
from app.services.document_service import invalidate_documents_cache

logger = logging.getLogger(__name__)

DOCUMENT_TYPE_PAYROLL = "manual"
PAYROLL_SOURCE = "payroll"
LINK_TYPE_ACCRUAL = "accrual"
LINK_TYPE_PAYMENT = "payment"

CHART_PAYROLL_EXPENSE = "702"
CHART_WAGES_PAYABLE = "20305"
CHART_TAX_PAYABLE = "20303"

_ITEM_DEDUCTION_ACCOUNT_CODES = {
	"tax": CHART_TAX_PAYABLE,
	"insurance_employee": None,  # از تنظیمات
	"loan": CHART_WAGES_PAYABLE,
}


def _quantize(amount: Decimal, decimals: int = 0) -> Decimal:
	if decimals <= 0:
		return amount.quantize(Decimal("1"))
	step = Decimal(10) ** (-int(decimals))
	return amount.quantize(step)


def _get_chart_account(db: Session, code: str) -> Account:
	row = (
		db.query(Account)
		.filter(Account.business_id.is_(None), Account.code == str(code))  # noqa: E711
		.first()
	)
	if not row:
		raise ApiError(
			"PAYROLL_CHART_ACCOUNT_NOT_FOUND",
			f"حساب استاندارد {code} در دفتر کل یافت نشد.",
			http_status=500,
		)
	return row


def _resolve_account(
	db: Session,
	business_id: int,
	*,
	account_id: Optional[int],
	settings: PayrollSettings,
	settings_attr: Optional[str],
	chart_code: str,
) -> Account:
	if account_id is not None:
		row = (
			db.query(Account)
			.filter(
				Account.id == int(account_id),
				(Account.business_id == business_id) | (Account.business_id.is_(None)),  # noqa: E711
			)
			.first()
		)
		if row:
			return row
	if settings_attr:
		sid = getattr(settings, settings_attr, None)
		if sid is not None:
			row = (
				db.query(Account)
				.filter(
					Account.id == int(sid),
					(Account.business_id == business_id) | (Account.business_id.is_(None)),  # noqa: E711
				)
				.first()
			)
			if row:
				return row
	return _get_chart_account(db, chart_code)


def _resolve_earning_account(db: Session, business_id: int, item: PayrollItemDefinition, settings: PayrollSettings) -> Account:
	return _resolve_account(
		db,
		business_id,
		account_id=item.account_id,
		settings=settings,
		settings_attr="payroll_expense_account_id",
		chart_code=CHART_PAYROLL_EXPENSE,
	)


def _resolve_deduction_account(db: Session, business_id: int, item: PayrollItemDefinition, settings: PayrollSettings) -> Account:
	if item.account_id:
		row = (
			db.query(Account)
			.filter(
				Account.id == int(item.account_id),
				(Account.business_id == business_id) | (Account.business_id.is_(None)),  # noqa: E711
			)
			.first()
		)
		if row:
			return row
	code = _ITEM_DEDUCTION_ACCOUNT_CODES.get(item.code)
	if code:
		return _get_chart_account(db, code)
	if item.code == "insurance_employee":
		return _resolve_account(
			db,
			business_id,
			account_id=None,
			settings=settings,
			settings_attr="insurance_payable_account_id",
			chart_code=CHART_WAGES_PAYABLE,
		)
	if item.code == "tax":
		return _resolve_account(
			db,
			business_id,
			account_id=None,
			settings=settings,
			settings_attr="tax_payable_account_id",
			chart_code=CHART_TAX_PAYABLE,
		)
	return _resolve_account(
		db,
		business_id,
		account_id=item.counter_account_id,
		settings=settings,
		settings_attr="wages_payable_account_id",
		chart_code=CHART_WAGES_PAYABLE,
	)


def _resolve_employer_cost_accounts(
	db: Session, business_id: int, item: PayrollItemDefinition, settings: PayrollSettings
) -> Tuple[Account, Account]:
	debit_acc = _resolve_account(
		db,
		business_id,
		account_id=item.account_id,
		settings=settings,
		settings_attr="payroll_expense_account_id",
		chart_code=CHART_PAYROLL_EXPENSE,
	)
	credit_acc = _resolve_account(
		db,
		business_id,
		account_id=item.counter_account_id,
		settings=settings,
		settings_attr="insurance_payable_account_id",
		chart_code=CHART_WAGES_PAYABLE,
	)
	return debit_acc, credit_acc


def _get_active_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	fy = (
		db.query(FiscalYear)
		.filter(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
		.order_by(FiscalYear.start_date.desc())
		.first()
	)
	if not fy:
		raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی جاری یافت نشد.", http_status=400)
	return fy


def _aggregate_item_amounts(db: Session, run_id: int) -> List[Tuple[PayrollItemDefinition, Decimal]]:
	rows = (
		db.query(PayrollItemDefinition, func.coalesce(func.sum(PayrollRunLineItem.amount), 0))
		.join(PayrollRunLineItem, PayrollRunLineItem.item_definition_id == PayrollItemDefinition.id)
		.join(PayrollRunLine, PayrollRunLine.id == PayrollRunLineItem.run_line_id)
		.filter(PayrollRunLine.run_id == int(run_id))
		.group_by(PayrollItemDefinition.id)
		.all()
	)
	out: List[Tuple[PayrollItemDefinition, Decimal]] = []
	for item_def, total in rows:
		amt = _quantize(Decimal(str(total or 0)))
		if amt != 0:
			out.append((item_def, amt))
	return out


def _build_accrual_lines(
	db: Session,
	business_id: int,
	run: PayrollRun,
	settings: PayrollSettings,
) -> List[Dict[str, Any]]:
	rt = int(settings.round_amounts_to or 0)
	lines: List[Dict[str, Any]] = []
	desc_base = f"حقوق {run.code}"

	for item_def, amount in _aggregate_item_amounts(db, run.id):
		kind = item_def.item_kind
		label = item_def.name or item_def.code
		if kind == "earning":
			acc = _resolve_earning_account(db, business_id, item_def, settings)
			lines.append(
				{
					"account_id": acc.id,
					"debit": float(amount),
					"credit": 0,
					"description": f"{desc_base} — {label}",
				}
			)
		elif kind == "deduction":
			acc = _resolve_deduction_account(db, business_id, item_def, settings)
			lines.append(
				{
					"account_id": acc.id,
					"debit": 0,
					"credit": float(amount),
					"description": f"{desc_base} — کسور {label}",
				}
			)
		elif kind == "employer_cost":
			debit_acc, credit_acc = _resolve_employer_cost_accounts(db, business_id, item_def, settings)
			lines.append(
				{
					"account_id": debit_acc.id,
					"debit": float(amount),
					"credit": 0,
					"description": f"{desc_base} — هزینه کارفرما {label}",
				}
			)
			lines.append(
				{
					"account_id": credit_acc.id,
					"debit": 0,
					"credit": float(amount),
					"description": f"{desc_base} — بدهی کارفرما {label}",
				}
			)

	net = _quantize(Decimal(str(run.net_total or 0)), rt)
	if net > 0:
		wages_acc = _resolve_account(
			db,
			business_id,
			account_id=None,
			settings=settings,
			settings_attr="wages_payable_account_id",
			chart_code=CHART_WAGES_PAYABLE,
		)
		lines.append(
			{
				"account_id": wages_acc.id,
				"debit": 0,
				"credit": float(net),
				"description": f"{desc_base} — حقوق پرداختنی",
			}
		)

	merged: Dict[Tuple[int, str], Dict[str, Any]] = defaultdict(
		lambda: {"account_id": 0, "debit": Decimal("0"), "credit": Decimal("0"), "description": ""}
	)
	for ln in lines:
		key = (int(ln["account_id"]), str(ln.get("description") or ""))
		merged[key]["account_id"] = int(ln["account_id"])
		merged[key]["debit"] += Decimal(str(ln.get("debit") or 0))
		merged[key]["credit"] += Decimal(str(ln.get("credit") or 0))
		if not merged[key]["description"]:
			merged[key]["description"] = ln.get("description")

	out_lines: List[Dict[str, Any]] = []
	for row in merged.values():
		debit = _quantize(row["debit"], rt)
		credit = _quantize(row["credit"], rt)
		if debit == 0 and credit == 0:
			continue
		out_lines.append(
			{
				"account_id": row["account_id"],
				"debit": float(debit),
				"credit": float(credit),
				"description": row["description"],
			}
		)

	if not out_lines:
		raise ApiError("NO_ACCOUNTING_LINES", "مبلغی برای ثبت سند حسابداری وجود ندارد.", http_status=400)

	total_debit = sum(Decimal(str(x["debit"])) for x in out_lines)
	total_credit = sum(Decimal(str(x["credit"])) for x in out_lines)
	if total_debit != total_credit:
		raise ApiError(
			"UNBALANCED_PAYROLL_ENTRY",
			f"سند حقوق متوازن نیست (بدهکار={total_debit}, بستانکار={total_credit}).",
			http_status=400,
		)
	return out_lines


def _create_balanced_document(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	currency_id: int,
	document_date: date,
	description: str,
	extra_info: Dict[str, Any],
	lines_payload: List[Dict[str, Any]],
) -> Document:
	fiscal_year = _get_active_fiscal_year(db, business_id)
	total_debit = sum(Decimal(str(x.get("debit", 0) or 0)) for x in lines_payload)
	total_credit = sum(Decimal(str(x.get("credit", 0) or 0)) for x in lines_payload)
	if total_debit != total_credit or total_debit <= 0:
		raise ApiError("UNBALANCED_DOCUMENT", "سطرهای سند متوازن نیستند.", http_status=400)

	ensure_document_policy_allows_creation(
		db,
		business_id,
		document_type=DOCUMENT_TYPE_PAYROLL,
		document_date=document_date,
		amount=total_debit,
	)

	document: Document | None = None
	for _attempt in range(8):
		doc_code = generate_document_code(db, business_id, DOCUMENT_TYPE_PAYROLL, document_date)
		candidate = Document(
			business_id=business_id,
			fiscal_year_id=fiscal_year.id,
			code=doc_code,
			document_type=DOCUMENT_TYPE_PAYROLL,
			document_date=document_date,
			currency_id=int(currency_id),
			created_by_user_id=user_id,
			registered_at=datetime.utcnow(),
			is_proforma=False,
			description=description,
			extra_info=extra_info,
		)
		try:
			with db.begin_nested():
				db.add(candidate)
				db.flush()
		except IntegrityError as exc:
			msg = str(getattr(exc.orig, "args", exc))
			if "uq_documents_business_code" in msg or "Duplicate entry" in msg:
				continue
			raise
		else:
			document = candidate
			break

	if document is None:
		raise ApiError("DOCUMENT_CODE_RACE", "تولید شماره سند ناموفق بود.", http_status=409)

	for ln in lines_payload:
		db.add(
			DocumentLine(
				document_id=document.id,
				account_id=int(ln["account_id"]),
				debit=Decimal(str(ln.get("debit", 0) or 0)),
				credit=Decimal(str(ln.get("credit", 0) or 0)),
				description=ln.get("description"),
			)
		)
	db.flush()

	try:
		process_document_usage_for_document(db, document.id)
	except Exception as exc:
		logger.warning("payroll_doc_monetization_skip", extra={"error": str(exc), "document_id": document.id})

	try:
		invalidate_documents_cache(business_id)
	except Exception:
		pass

	return document


def _existing_link(db: Session, run_id: int, link_type: str) -> Optional[PayrollDocumentLink]:
	return (
		db.query(PayrollDocumentLink)
		.filter(PayrollDocumentLink.run_id == run_id, PayrollDocumentLink.link_type == link_type)
		.first()
	)


def post_payroll_accrual_document(
	db: Session,
	business_id: int,
	user_id: int,
	run: PayrollRun,
	settings: PayrollSettings,
) -> Dict[str, Any]:
	if _existing_link(db, run.id, LINK_TYPE_ACCRUAL):
		raise ApiError("ACCRUAL_ALREADY_POSTED", "سند تعهدی این اجرای حقوق قبلاً ثبت شده است.", http_status=409)

	currency_id = settings.default_currency_id
	if not currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض حقوق تنظیم نشده است.", http_status=400)

	lines_payload = _build_accrual_lines(db, business_id, run, settings)
	description = f"سند تعهدی حقوق — {run.title or run.code}"
	extra_info = {
		"source": PAYROLL_SOURCE,
		"payroll_link_type": LINK_TYPE_ACCRUAL,
		"payroll_run_id": run.id,
		"payroll_run_code": run.code,
	}

	document = _create_balanced_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(currency_id),
		document_date=run.run_date,
		description=description,
		extra_info=extra_info,
		lines_payload=lines_payload,
	)

	link = PayrollDocumentLink(run_id=run.id, document_id=document.id, link_type=LINK_TYPE_ACCRUAL)
	db.add(link)
	db.flush()

	return {
		"document_id": document.id,
		"document_code": document.code,
		"link_type": LINK_TYPE_ACCRUAL,
		"line_count": len(lines_payload),
	}


def post_payroll_payment_document(
	db: Session,
	business_id: int,
	user_id: int,
	run: PayrollRun,
	settings: PayrollSettings,
	payment_account_id: int,
) -> Dict[str, Any]:
	if not _existing_link(db, run.id, LINK_TYPE_ACCRUAL):
		raise ApiError("ACCRUAL_REQUIRED", "ابتدا سند تعهدی حقوق را ثبت کنید.", http_status=400)
	if _existing_link(db, run.id, LINK_TYPE_PAYMENT):
		raise ApiError("PAYMENT_ALREADY_POSTED", "سند پرداخت این اجرای حقوق قبلاً ثبت شده است.", http_status=409)

	payment_acc = (
		db.query(Account)
		.filter(
			Account.id == int(payment_account_id),
			(Account.business_id == business_id) | (Account.business_id.is_(None)),  # noqa: E711
		)
		.first()
	)
	if not payment_acc:
		raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "حساب پرداخت یافت نشد.", http_status=404)

	rt = int(settings.round_amounts_to or 0)
	net = _quantize(Decimal(str(run.net_total or 0)), rt)
	if net <= 0:
		raise ApiError("INVALID_NET_AMOUNT", "مبلغ خالص پرداختی برای ثبت سند پرداخت نامعتبر است.", http_status=400)

	wages_acc = _resolve_account(
		db,
		business_id,
		account_id=None,
		settings=settings,
		settings_attr="wages_payable_account_id",
		chart_code=CHART_WAGES_PAYABLE,
	)

	currency_id = settings.default_currency_id
	if not currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض حقوق تنظیم نشده است.", http_status=400)

	desc_base = f"پرداخت حقوق {run.code}"
	lines_payload = [
		{
			"account_id": wages_acc.id,
			"debit": float(net),
			"credit": 0,
			"description": desc_base,
		},
		{
			"account_id": payment_acc.id,
			"debit": 0,
			"credit": float(net),
			"description": desc_base,
		},
	]

	document = _create_balanced_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(currency_id),
		document_date=run.run_date,
		description=desc_base,
		extra_info={
			"source": PAYROLL_SOURCE,
			"payroll_link_type": LINK_TYPE_PAYMENT,
			"payroll_run_id": run.id,
			"payroll_run_code": run.code,
			"payment_account_id": payment_acc.id,
		},
		lines_payload=lines_payload,
	)

	link = PayrollDocumentLink(run_id=run.id, document_id=document.id, link_type=LINK_TYPE_PAYMENT)
	db.add(link)
	db.flush()

	return {
		"document_id": document.id,
		"document_code": document.code,
		"link_type": LINK_TYPE_PAYMENT,
		"amount": float(net),
	}
