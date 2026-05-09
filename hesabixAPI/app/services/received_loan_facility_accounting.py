"""ثبت اسناد حسابداری برای تسهیلات دریافتی (نوع سند manual — قابل حذف و ویرایش مثل اسناد دستی)."""
from __future__ import annotations

import logging
from datetime import datetime, date, timezone
from decimal import Decimal
from typing import Any, Dict, List

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError
from app.services.document_monetization_service import (
	ensure_document_policy_allows_creation,
	process_document_usage_for_document,
)
from app.services.document_numbering_service import generate_document_code
from app.services.document_service import invalidate_documents_cache
from app.core.received_loan_facility_accounts import (
	RECEIVED_LOAN_PRINCIPAL_PAYABLE_CODE,
	LOAN_BANKING_INTEREST_EXPENSE_CODE,
	LOAN_BANKING_LATE_FEE_EXPENSE_CODE,
)

logger = logging.getLogger(__name__)

DOCUMENT_TYPE_MANUAL = "manual"
BANK_LEDGER_ACCOUNT_CODE = "10203"

DOCUMENT_SOURCE_RECEIVED_LOAN_FACILITY = "received_loan_facility"


def _append_loan_document_fx_extra(
	db: Session,
	business_id: int,
	*,
	document_currency_id: int,
	document_date: date,
	extra_info: Dict[str, Any],
	registered_at_utc: datetime,
) -> Dict[str, Any]:
	"""همان کلید fx فاکتور روی سند تسهیلات برای ماندهٔ پایه و بستن سال."""
	base = dict(extra_info) if extra_info else {}
	business = db.get(Business, int(business_id))
	if not business:
		return base
	from app.services.invoice_fx_revaluation import apply_fx_revaluation_to_invoice_extra

	return apply_fx_revaluation_to_invoice_extra(
		db,
		business,
		document_currency_id=int(document_currency_id),
		document_date=document_date,
		extra_info=base,
		data={},
		user_can_select_fx_rate=False,
		registered_at_utc=registered_at_utc,
	)


def _get_fixed_chart_account(db: Session, account_code: str) -> Account:
	row = db.query(Account).filter(
		Account.business_id.is_(None),  # noqa: E711
		Account.code == str(account_code),
	).first()
	if not row:
		raise ApiError(
			"LOAN_CHART_ACCOUNT_NOT_FOUND",
			f"Chart account code {account_code} not found for loan posting",
			http_status=500,
		)
	return row


def _resolve_fiscal_year(db: Session, business_id: int, ref_date: date) -> FiscalYear:
	fy = (
		db.query(FiscalYear)
		.filter(
			FiscalYear.business_id == business_id,
			FiscalYear.start_date <= ref_date,
			FiscalYear.end_date >= ref_date,
		)
		.first()
	)
	if not fy:
		raise ApiError("NO_FISCAL_YEAR", "No fiscal year covers this transaction date", http_status=400)
	return fy


def _assert_fiscal_year_open_for_posting(fy: FiscalYear) -> None:
	"""فقط سال مالی جاری (دارای پرچم آخرین) می‌پذیرد ثبت؛ قفل از دیدگاه عملیاتی شبیه اسناد فاکتور."""
	if getattr(fy, "is_last", False) is not True:
		raise ApiError(
			"FISCAL_YEAR_LOCKED",
			"سال مالی شامل این تاریخ بسته شده یا غیرفعال است؛ تنها برای سال مالی جاری می‌توانید سند ثبت کنید",
			http_status=409,
		)


def _create_balanced_manual_document(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	currency_id: int,
	document_date: date,
	description: str | None,
	extra_info: Dict[str, Any],
	lines_payload: List[Dict[str, Any]],
) -> Document:
	registered_at_utc = datetime.now(timezone.utc)
	fiscal_year = _resolve_fiscal_year(db, business_id, document_date)
	_assert_fiscal_year_open_for_posting(fiscal_year)
	final_extra_info = _append_loan_document_fx_extra(
		db,
		business_id,
		document_currency_id=int(currency_id),
		document_date=document_date,
		extra_info=extra_info,
		registered_at_utc=registered_at_utc,
	)
	td = sum(Decimal(str(x.get("debit", 0) or 0)) for x in lines_payload).quantize(Decimal("0.01"))
	tc = sum(Decimal(str(x.get("credit", 0) or 0)) for x in lines_payload).quantize(Decimal("0.01"))
	if td != tc or td <= 0:
		raise ApiError(
			"LOAN_ACCOUNTING_LINES_UNBALANCED",
			"Loan accounting lines not balanced",
			http_status=400,
		)
	ensure_document_policy_allows_creation(
		db,
		business_id,
		document_type=DOCUMENT_TYPE_MANUAL,
		document_date=document_date,
		amount=td,
	)

	document: Document | None = None
	for _attempt in range(8):
		doc_code = generate_document_code(db, business_id, DOCUMENT_TYPE_MANUAL, document_date)
		candidate = Document(
			business_id=business_id,
			fiscal_year_id=fiscal_year.id,
			code=doc_code,
			document_type=DOCUMENT_TYPE_MANUAL,
			document_date=document_date,
			currency_id=int(currency_id),
			created_by_user_id=user_id,
			registered_at=datetime.utcnow(),
			is_proforma=False,
			description=description,
			extra_info=final_extra_info,
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
		raise ApiError("DOCUMENT_CODE_RACE", "Failed to allocate document code", http_status=409)

	for ln in lines_payload:
		db.add(DocumentLine(document_id=document.id, **ln))
	db.flush()

	try:
		process_document_usage_for_document(db, document.id)
	except Exception as e:
		logger.warning("loan_doc_monetization_skip", extra={"error": str(e), "document_id": document.id})
	return document


def post_disbursement_document(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	title: str,
	principal_amount: Decimal,
	facility_currency_id: int,
	bank_account_id: int,
	contract_date: date,
	facility_id: int,
) -> Document:
	bank_ledger = _get_fixed_chart_account(db, BANK_LEDGER_ACCOUNT_CODE)
	principal_acc = _get_fixed_chart_account(db, RECEIVED_LOAN_PRINCIPAL_PAYABLE_CODE)
	p_amt = Decimal(str(principal_amount)).quantize(Decimal("0.01"))
	if p_amt <= 0:
		raise ApiError("INVALID_AMOUNT", "Disbursement amount must be positive", http_status=400)
	desc = f"دریافت تسهیلات — {title}"
	extra = {
		"source": DOCUMENT_SOURCE_RECEIVED_LOAN_FACILITY,
		"facility_id": facility_id,
		"kind": "disbursement",
	}
	return _create_balanced_manual_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(facility_currency_id),
		document_date=contract_date,
		description=desc,
		extra_info=extra,
		lines_payload=[
			{
				"account_id": bank_ledger.id,
				"debit": p_amt,
				"credit": Decimal("0"),
				"bank_account_id": int(bank_account_id),
				"description": "واریز نقد از محل دریافت تسهیلات",
			},
			{
				"account_id": principal_acc.id,
				"debit": Decimal("0"),
				"credit": p_amt,
				"description": "اصل بدهی تسهیلات دریافتی",
			},
		],
	)


def post_installment_payment_document(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	title: str,
	facility_currency_id: int,
	facility_id: int,
	installment_id: int,
	payment_id: int,
	payment_date: date,
	principal_part: Decimal,
	interest_part: Decimal,
	penalty_part: Decimal,
	bank_account_id: int | None,
) -> Document | None:
	pri = Decimal(str(principal_part)).quantize(Decimal("0.01"))
	inte = Decimal(str(interest_part)).quantize(Decimal("0.01"))
	pen = Decimal(str(penalty_part)).quantize(Decimal("0.01"))
	total = (pri + inte + pen).quantize(Decimal("0.01"))
	if total <= 0:
		return None
	if bank_account_id is None:
		raise ApiError(
			"LOAN_BANK_REQUIRED_FOR_PAYMENT_DOCUMENT",
			"Bank account required for installment payment accounting",
			http_status=400,
		)

	bank_ledger = _get_fixed_chart_account(db, BANK_LEDGER_ACCOUNT_CODE)
	principal_acc = _get_fixed_chart_account(db, RECEIVED_LOAN_PRINCIPAL_PAYABLE_CODE)
	interest_exp = _get_fixed_chart_account(db, LOAN_BANKING_INTEREST_EXPENSE_CODE)
	penalty_exp = _get_fixed_chart_account(db, LOAN_BANKING_LATE_FEE_EXPENSE_CODE)

	lines_payload: List[Dict[str, Any]] = []

	if pri > 0:
		lines_payload.append(
			{
				"account_id": principal_acc.id,
				"debit": pri,
				"credit": Decimal("0"),
				"description": "پرداخت اصل قسط",
			},
		)
	if inte > 0:
		lines_payload.append(
			{
				"account_id": interest_exp.id,
				"debit": inte,
				"credit": Decimal("0"),
				"description": "بهره تسهیلات",
			},
		)
	if pen > 0:
		lines_payload.append(
			{
				"account_id": penalty_exp.id,
				"debit": pen,
				"credit": Decimal("0"),
				"description": "جریمه دیرکرد / وجه التزام",
			},
		)
	lines_payload.append(
		{
			"account_id": bank_ledger.id,
			"debit": Decimal("0"),
			"credit": total,
			"bank_account_id": int(bank_account_id),
			"description": f"پرداخت قسط — {title}",
		},
	)

	extra = {
		"source": DOCUMENT_SOURCE_RECEIVED_LOAN_FACILITY,
		"facility_id": facility_id,
		"installment_id": installment_id,
		"payment_id": payment_id,
		"kind": "installment_payment",
	}
	return _create_balanced_manual_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(facility_currency_id),
		document_date=payment_date,
		description=f"پرداخت قسط تسهیلات — {title}",
		extra_info=extra,
		lines_payload=lines_payload,
	)


def notify_document_cache_manual(db: Session, document: Document) -> None:
	try:
		invalidate_documents_cache(
			business_id=document.business_id,
			fiscal_year_id=document.fiscal_year_id,
			document_id=document.id,
			document_type=DOCUMENT_TYPE_MANUAL,
		)
	except Exception as e:
		logger.warning("loan_doc_cache_invalidate_failed", extra={"error": str(e)})
