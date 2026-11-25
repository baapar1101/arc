"""
صدور اسناد دفتر کل برای تحصیل، استهلاک، خروج و مخارج بعدی دارایی ثابت.
"""
from __future__ import annotations

import logging
from decimal import Decimal, ROUND_HALF_UP
from datetime import date
from typing import Any, Dict, List, Optional

from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.fixed_asset import (
	FixedAsset,
	FixedAssetClass,
	FixedAssetDepreciationRun,
	FixedAssetDocumentLink,
	FixedAssetSettings,
)
from app.core.datetime_utils import utc_now_aware
from app.core.responses import ApiError
from app.core.fixed_asset_accounts import (
	GAIN_DISPOSAL,
	LOSS_DISPOSAL,
	REPAIR_EXPENSE,
	VAT_OUTPUT,
)
from app.services.fixed_asset_acquisition_plan import AcquisitionPlanError, build_acquisition_line_plan
from app.services.fixed_asset_disposal_plan import (
	DisposalPlanError,
	build_disposal_line_plan,
	build_subsequent_expenditure_plan,
)
from app.services.document_monetization_service import (
	ensure_document_policy_allows_creation,
	process_document_usage_for_document,
)
from app.services.document_numbering_service import generate_document_code
from app.services.document_service import invalidate_documents_cache

logger = logging.getLogger(__name__)

DOCUMENT_TYPE_ACQUISITION = "fixed_asset_acquisition"
DOCUMENT_TYPE_DEPRECIATION = "fixed_asset_depreciation"
DOCUMENT_TYPE_DISPOSAL = "fixed_asset_disposal"
DOCUMENT_TYPE_SUBSEQUENT = "fixed_asset_subsequent"
FA_SOURCE = "fixed_assets"
LINK_ACQUISITION = "acquisition"
LINK_DEPRECIATION = "depreciation"
LINK_DISPOSAL = "disposal"
LINK_SUBSEQUENT = "subsequent"

VAT_ACCOUNT_CODE = "10104"
VAT_OUTPUT_ACCOUNT_CODE = VAT_OUTPUT
GAIN_ACCOUNT_CODE = GAIN_DISPOSAL
LOSS_ACCOUNT_CODE = LOSS_DISPOSAL
REPAIR_ACCOUNT_CODE = REPAIR_EXPENSE
BANK_ACCOUNT_CODE = "10203"
CASH_ACCOUNT_CODE = "10202"
PETTY_ACCOUNT_CODE = "10201"
AP_ACCOUNT_CODE = "20201"

COUNTERPARTY_TYPES = frozenset({"person", "bank", "cash_register", "petty_cash", "opening", "account"})


def q_amount(amount: Decimal, quant: Decimal) -> Decimal:
	return amount.quantize(quant, rounding=ROUND_HALF_UP)


def get_active_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	fy = (
		db.query(FiscalYear)
		.filter(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
		.order_by(FiscalYear.start_date.desc())
		.first()
	)
	if not fy:
		raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی جاری یافت نشد.", http_status=400)
	return fy


def assert_date_in_fiscal_year(fy: FiscalYear, document_date: date) -> None:
	if fy.start_date and document_date < fy.start_date:
		raise ApiError("DATE_OUTSIDE_FISCAL_YEAR", "تاریخ سند خارج از سال مالی جاری است.", http_status=400)
	if fy.end_date and document_date > fy.end_date:
		raise ApiError("DATE_OUTSIDE_FISCAL_YEAR", "تاریخ سند خارج از سال مالی جاری است.", http_status=400)


def resolve_account(
	db: Session,
	business_id: int,
	*,
	account_id: Optional[int] = None,
	code: Optional[str] = None,
) -> Account:
	if account_id is not None:
		row = (
			db.query(Account)
			.filter(
				Account.id == int(account_id),
				or_(Account.business_id == business_id, Account.business_id.is_(None)),  # noqa: E711
			)
			.first()
		)
		if not row:
			raise ApiError("ACCOUNT_NOT_FOUND", "حساب یافت نشد یا متعلق به این کسب‌وکار نیست.", http_status=404)
		_assert_leaf(db, row, business_id)
		return row
	code_s = str(code or "").strip()
	if not code_s:
		raise ApiError("ACCOUNT_REQUIRED", "حساب الزامی است.", http_status=400)
	row = (
		db.query(Account)
		.filter(Account.code == code_s, Account.business_id == business_id)
		.first()
	)
	if not row:
		row = (
			db.query(Account)
			.filter(Account.code == code_s, Account.business_id.is_(None))  # noqa: E711
			.first()
		)
	if not row:
		raise ApiError(
			"ACCOUNT_NOT_FOUND",
			f"حساب با کد {code_s} در دفتر کل یافت نشد. آن را در جدول حساب‌ها بسازید یا در طبقه دارایی نگاشت کنید.",
			http_status=404,
		)
	_assert_leaf(db, row, business_id)
	return row


def _assert_leaf(db: Session, account: Account, business_id: int) -> None:
	q = db.query(Account.id).filter(Account.parent_id == account.id)
	q = q.filter(or_(Account.business_id.is_(None), Account.business_id == int(business_id)))
	if q.limit(1).first():
		raise ApiError(
			"ACCOUNT_NOT_LEAF",
			f"حساب «{account.code} - {account.name}» گروه است و قابل ثبت نیست؛ یک حساب برگ انتخاب کنید.",
			http_status=400,
		)


def class_cost_account(db: Session, business_id: int, cls: FixedAssetClass) -> Account:
	return resolve_account(
		db, business_id, account_id=cls.cost_account_id, code=cls.cost_account_code
	)


def class_accum_account(db: Session, business_id: int, cls: FixedAssetClass) -> Account:
	if not cls.depreciable:
		raise ApiError("CLASS_NOT_DEPRECIABLE", "این طبقه استهلاک‌پذیر نیست.", http_status=400)
	return resolve_account(
		db, business_id, account_id=cls.accum_dep_account_id, code=cls.accum_dep_account_code
	)


def class_expense_account(db: Session, business_id: int, cls: FixedAssetClass) -> Account:
	if not cls.depreciable:
		raise ApiError("CLASS_NOT_DEPRECIABLE", "این طبقه استهلاک‌پذیر نیست.", http_status=400)
	return resolve_account(
		db, business_id, account_id=cls.dep_expense_account_id, code=cls.dep_expense_account_code
	)


def _create_balanced_document(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	currency_id: int,
	document_type: str,
	document_date: date,
	description: str,
	extra_info: Dict[str, Any],
	lines: List[Dict[str, Any]],
	project_id: Optional[int] = None,
) -> Document:
	fiscal_year = get_active_fiscal_year(db, business_id)
	assert_date_in_fiscal_year(fiscal_year, document_date)
	total_debit = sum(Decimal(str(x.get("debit", 0) or 0)) for x in lines)
	total_credit = sum(Decimal(str(x.get("credit", 0) or 0)) for x in lines)
	if total_debit != total_credit or total_debit <= 0:
		raise ApiError("UNBALANCED_DOCUMENT", "سطرهای سند متوازن نیستند.", http_status=400)

	ensure_document_policy_allows_creation(
		db,
		business_id,
		document_type=document_type,
		document_date=document_date,
		amount=total_debit,
	)

	document: Optional[Document] = None
	for _attempt in range(8):
		doc_code = generate_document_code(db, business_id, document_type, document_date)
		candidate = Document(
			business_id=business_id,
			fiscal_year_id=fiscal_year.id,
			code=doc_code,
			document_type=document_type,
			document_date=document_date,
			currency_id=int(currency_id),
			created_by_user_id=user_id,
			registered_at=utc_now_aware(),
			is_proforma=False,
			description=description,
			extra_info=extra_info,
			project_id=project_id,
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

	for ln in lines:
		db.add(
			DocumentLine(
				document_id=document.id,
				account_id=int(ln["account_id"]),
				debit=Decimal(str(ln.get("debit", 0) or 0)),
				credit=Decimal(str(ln.get("credit", 0) or 0)),
				description=ln.get("description"),
				person_id=ln.get("person_id"),
				bank_account_id=ln.get("bank_account_id"),
				cash_register_id=ln.get("cash_register_id"),
				petty_cash_id=ln.get("petty_cash_id"),
				extra_info=ln.get("extra_info"),
			)
		)
	db.flush()
	try:
		process_document_usage_for_document(db, document.id)
	except Exception as exc:
		logger.warning("fa_doc_monetization_skip", extra={"error": str(exc), "document_id": document.id})
	try:
		invalidate_documents_cache(business_id)
	except Exception:
		pass
	return document


def resolve_counterparty(
	db: Session,
	business_id: int,
	settings: FixedAssetSettings,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	kind = str(payload.get("counterparty_type") or "").strip()
	if kind not in COUNTERPARTY_TYPES:
		raise ApiError(
			"COUNTERPARTY_REQUIRED",
			"نوع طرف حساب باید person، bank، cash_register، petty_cash، opening یا account باشد.",
			http_status=400,
		)
	out: Dict[str, Any] = {"type": kind}
	if kind == "person":
		from adapters.db.models.person import Person

		pid = payload.get("person_id")
		if not pid:
			raise ApiError("PERSON_REQUIRED", "برای طرف حساب شخص، person_id الزامی است.", http_status=400)
		person = (
			db.query(Person)
			.filter(Person.id == int(pid), Person.business_id == business_id)
			.first()
		)
		if not person:
			raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد.", http_status=404)
		out["account"] = resolve_account(db, business_id, code=AP_ACCOUNT_CODE)
		out["person_id"] = int(pid)
	elif kind == "bank":
		from adapters.db.models.bank_account import BankAccount

		bid = payload.get("bank_account_id") or payload.get("bank_id")
		if not bid:
			raise ApiError("BANK_REQUIRED", "حساب بانکی الزامی است.", http_status=400)
		bank = (
			db.query(BankAccount)
			.filter(BankAccount.id == int(bid), BankAccount.business_id == business_id)
			.first()
		)
		if not bank:
			raise ApiError("BANK_NOT_FOUND", "حساب بانکی یافت نشد.", http_status=404)
		out["account"] = resolve_account(db, business_id, code=BANK_ACCOUNT_CODE)
		out["bank_account_id"] = int(bid)
	elif kind == "cash_register":
		from adapters.db.models.cash_register import CashRegister

		cid = payload.get("cash_register_id")
		if not cid:
			raise ApiError("CASH_REGISTER_REQUIRED", "صندوق الزامی است.", http_status=400)
		row = (
			db.query(CashRegister)
			.filter(CashRegister.id == int(cid), CashRegister.business_id == business_id)
			.first()
		)
		if not row:
			raise ApiError("CASH_REGISTER_NOT_FOUND", "صندوق یافت نشد.", http_status=404)
		out["account"] = resolve_account(db, business_id, code=CASH_ACCOUNT_CODE)
		out["cash_register_id"] = int(cid)
	elif kind == "petty_cash":
		from adapters.db.models.petty_cash import PettyCash

		pid = payload.get("petty_cash_id")
		if not pid:
			raise ApiError("PETTY_CASH_REQUIRED", "تنخواه الزامی است.", http_status=400)
		row = (
			db.query(PettyCash)
			.filter(PettyCash.id == int(pid), PettyCash.business_id == business_id)
			.first()
		)
		if not row:
			raise ApiError("PETTY_CASH_NOT_FOUND", "تنخواه یافت نشد.", http_status=404)
		out["account"] = resolve_account(db, business_id, code=PETTY_ACCOUNT_CODE)
		out["petty_cash_id"] = int(pid)
	elif kind == "opening":
		if not settings.opening_equity_account_id:
			raise ApiError(
				"OPENING_ACCOUNT_REQUIRED",
				"برای تحصیل افتتاحیه، حساب حقوق صاحبان سهام/افتتاحیه را در تنظیمات اموال مشخص کنید.",
				http_status=400,
			)
		out["account"] = resolve_account(db, business_id, account_id=settings.opening_equity_account_id)
	else:
		aid = payload.get("account_id")
		if not aid:
			raise ApiError("ACCOUNT_REQUIRED", "account_id برای طرف حساب الزامی است.", http_status=400)
		out["account"] = resolve_account(db, business_id, account_id=int(aid))
	return out


def post_acquisition_document(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	asset: FixedAsset,
	cls: FixedAssetClass,
	settings: FixedAssetSettings,
	counterparty: Dict[str, Any],
	quant: Decimal,
) -> Document:
	if asset.acquisition_document_id:
		raise ApiError("ALREADY_CAPITALIZED", "این دارایی قبلاً سرمایه شده است.", http_status=409)
	cost = q_amount(Decimal(str(asset.cost)), quant)
	vat = q_amount(Decimal(str(asset.vat_amount or 0)), quant)
	opening_accum = q_amount(Decimal(str(asset.opening_accum_depreciation or 0)), quant)
	kind = str(asset.acquisition_kind or "purchase")
	if kind not in ("purchase", "opening"):
		raise ApiError("INVALID_ACQUISITION_KIND", "نوع تحصیل باید purchase یا opening باشد.", http_status=400)
	if kind == "purchase" and opening_accum > 0:
		raise ApiError(
			"OPENING_ACCUM_NOT_ALLOWED",
			"استهلاک انباشته افتتاحیه فقط برای تحصیل از نوع opening مجاز است.",
			http_status=400,
		)

	try:
		build_acquisition_line_plan(kind=kind, cost=cost, vat=vat, opening_accum=opening_accum)
	except AcquisitionPlanError as exc:
		raise ApiError(exc.code, exc.message, http_status=400) from exc
	cost_acc = class_cost_account(db, business_id, cls)
	cp_acc = counterparty["account"]
	currency_id = settings.default_currency_id
	if not currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض اموال در تنظیمات مشخص نشده است.", http_status=400)

	lines: List[Dict[str, Any]] = [
		{
			"account_id": cost_acc.id,
			"debit": cost,
			"credit": Decimal("0"),
			"description": f"تحصیل دارایی {asset.code} — {asset.name}",
			"extra_info": {"side": "cost", "asset_id": asset.id},
		}
	]
	if vat > 0:
		vat_acc = resolve_account(
			db, business_id, account_id=settings.vat_account_id, code=VAT_ACCOUNT_CODE
		)
		lines.append(
			{
				"account_id": vat_acc.id,
				"debit": vat,
				"credit": Decimal("0"),
				"description": f"مالیات ورودی تحصیل دارایی {asset.code}",
				"extra_info": {"side": "vat", "asset_id": asset.id},
			}
		)
	if kind == "opening" and opening_accum > 0:
		accum_acc = class_accum_account(db, business_id, cls)
		lines.append(
			{
				"account_id": accum_acc.id,
				"debit": Decimal("0"),
				"credit": opening_accum,
				"description": f"استهلاک انباشته افتتاحیه {asset.code}",
				"extra_info": {"side": "opening_accum", "asset_id": asset.id},
			}
		)
	credit_rest = cost + vat - (opening_accum if kind == "opening" else Decimal("0"))
	cp_line: Dict[str, Any] = {
		"account_id": cp_acc.id,
		"debit": Decimal("0"),
		"credit": credit_rest,
		"description": f"طرف تحصیل دارایی {asset.code}",
		"person_id": counterparty.get("person_id"),
		"bank_account_id": counterparty.get("bank_account_id"),
		"cash_register_id": counterparty.get("cash_register_id"),
		"petty_cash_id": counterparty.get("petty_cash_id"),
		"extra_info": {"side": "counterparty", "asset_id": asset.id, "counterparty_type": counterparty.get("type")},
	}
	lines.append(cp_line)

	document = _create_balanced_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(currency_id),
		document_type=DOCUMENT_TYPE_ACQUISITION,
		document_date=asset.acquisition_date,
		description=f"تحصیل دارایی ثابت {asset.code} — {asset.name}",
		extra_info={
			"source": FA_SOURCE,
			"link_type": LINK_ACQUISITION,
			"asset_id": asset.id,
			"asset_code": asset.code,
		},
		lines=lines,
		project_id=asset.project_id,
	)
	db.add(
		FixedAssetDocumentLink(
			business_id=business_id,
			asset_id=asset.id,
			document_id=document.id,
			link_type=LINK_ACQUISITION,
		)
	)
	return document


def post_depreciation_run_document(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	run: FixedAssetDepreciationRun,
	settings: FixedAssetSettings,
) -> Document:
	if run.document_id:
		raise ApiError("DEPRECIATION_ALREADY_POSTED", "سند استهلاک این دوره قبلاً ثبت شده است.", http_status=409)
	if run.status != "draft":
		raise ApiError("RUN_NOT_DRAFT", "فقط اجرای پیش‌نویس قابل ثبت سند است.", http_status=400)
	lines_src = list(run.lines or [])
	if not lines_src:
		raise ApiError("NO_DEPRECIATION_LINES", "سطری برای استهلاک این دوره وجود ندارد.", http_status=400)
	currency_id = settings.default_currency_id
	if not currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض اموال در تنظیمات مشخص نشده است.", http_status=400)

	gl_lines: List[Dict[str, Any]] = []
	total = Decimal("0")
	for ln in lines_src:
		amt = Decimal(str(ln.amount))
		if amt <= 0:
			continue
		total += amt
		gl_lines.append(
			{
				"account_id": ln.expense_account_id,
				"debit": amt,
				"credit": Decimal("0"),
				"description": f"هزینه استهلاک دارایی #{ln.asset_id} — {run.period_year}/{run.period_month:02d}",
				"extra_info": {"side": "dep_expense", "asset_id": ln.asset_id, "run_id": run.id},
			}
		)
		gl_lines.append(
			{
				"account_id": ln.accum_account_id,
				"debit": Decimal("0"),
				"credit": amt,
				"description": f"استهلاک انباشته دارایی #{ln.asset_id} — {run.period_year}/{run.period_month:02d}",
				"extra_info": {"side": "accum_dep", "asset_id": ln.asset_id, "run_id": run.id},
			}
		)
	if not gl_lines:
		raise ApiError("NO_DEPRECIATION_AMOUNT", "مبلغ استهلاک این دوره صفر است.", http_status=400)

	document = _create_balanced_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(currency_id),
		document_type=DOCUMENT_TYPE_DEPRECIATION,
		document_date=run.period_end,
		description=f"استهلاک دارایی ثابت {run.period_year}/{run.period_month:02d}",
		extra_info={
			"source": FA_SOURCE,
			"link_type": LINK_DEPRECIATION,
			"run_id": run.id,
			"period_year": run.period_year,
			"period_month": run.period_month,
		},
		lines=gl_lines,
	)
	db.add(
		FixedAssetDocumentLink(
			business_id=business_id,
			run_id=run.id,
			document_id=document.id,
			link_type=LINK_DEPRECIATION,
		)
	)
	run.total_amount = total
	return document


def settings_gain_account(db: Session, business_id: int, settings: FixedAssetSettings) -> Account:
	return resolve_account(
		db, business_id, account_id=settings.disposal_gain_account_id, code=GAIN_ACCOUNT_CODE
	)


def settings_loss_account(db: Session, business_id: int, settings: FixedAssetSettings) -> Account:
	return resolve_account(
		db, business_id, account_id=settings.disposal_loss_account_id, code=LOSS_ACCOUNT_CODE
	)


def settings_repair_account(db: Session, business_id: int, settings: FixedAssetSettings) -> Account:
	return resolve_account(
		db, business_id, account_id=settings.repair_expense_account_id, code=REPAIR_ACCOUNT_CODE
	)


def settings_vat_output_account(db: Session, business_id: int, settings: FixedAssetSettings) -> Account:
	return resolve_account(
		db, business_id, account_id=settings.vat_output_account_id, code=VAT_OUTPUT_ACCOUNT_CODE
	)


def post_disposal_document(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	asset: FixedAsset,
	cls: FixedAssetClass,
	settings: FixedAssetSettings,
	counterparty: Dict[str, Any],
	kind: str,
	proceeds: Decimal,
	vat_output: Decimal,
	catch_up_amount: Decimal,
	quant: Decimal,
	document_date: date,
) -> Document:
	if asset.disposal_document_id:
		raise ApiError("ALREADY_DISPOSED", "این دارایی قبلاً خارج شده است.", http_status=409)
	cost = q_amount(Decimal(str(asset.cost)), quant)
	accum = q_amount(Decimal(str(asset.accum_depreciation or 0)), quant)
	proceeds_q = q_amount(proceeds, quant)
	vat_q = q_amount(vat_output, quant)
	catch_up = q_amount(catch_up_amount, quant)
	if catch_up < 0:
		raise ApiError("INVALID_AMOUNT", "استهلاک تا تاریخ خروج نمی‌تواند منفی باشد.", http_status=400)
	accum_for_plan = accum + catch_up
	try:
		plan = build_disposal_line_plan(
			kind=kind,
			cost=cost,
			accum=accum_for_plan,
			proceeds=proceeds_q,
			vat_output=vat_q,
		)
	except DisposalPlanError as exc:
		raise ApiError(exc.code, exc.message, http_status=400) from exc

	cost_acc = class_cost_account(db, business_id, cls)
	cp_acc = counterparty["account"]
	currency_id = settings.default_currency_id
	if not currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض اموال در تنظیمات مشخص نشده است.", http_status=400)

	role_accounts: Dict[str, Account] = {"cost": cost_acc, "proceeds": cp_acc}
	need_accum = catch_up > 0 or any(r == "accum" for _s, _a, r in plan)
	if need_accum:
		if not cls.depreciable:
			raise ApiError(
				"CLASS_NOT_DEPRECIABLE",
				"این طبقه استهلاک‌پذیر نیست ولی استهلاک انباشته دارد.",
				http_status=400,
			)
		accum_acc = class_accum_account(db, business_id, cls)
		role_accounts["accum"] = accum_acc
	if any(r == "gain" for _s, _a, r in plan):
		role_accounts["gain"] = settings_gain_account(db, business_id, settings)
	if any(r == "loss" for _s, _a, r in plan):
		role_accounts["loss"] = settings_loss_account(db, business_id, settings)
	if any(r == "vat_out" for _s, _a, r in plan):
		role_accounts["vat_out"] = settings_vat_output_account(db, business_id, settings)

	lines: List[Dict[str, Any]] = []
	if catch_up > 0:
		expense_acc = class_expense_account(db, business_id, cls)
		lines.append(
			{
				"account_id": expense_acc.id,
				"debit": catch_up,
				"credit": Decimal("0"),
				"description": f"استهلاک تا تاریخ خروج {asset.code}",
				"extra_info": {"side": "dep_expense_catch_up", "asset_id": asset.id},
			}
		)
		lines.append(
			{
				"account_id": role_accounts["accum"].id,
				"debit": Decimal("0"),
				"credit": catch_up,
				"description": f"استهلاک انباشته تا تاریخ خروج {asset.code}",
				"extra_info": {"side": "accum_dep_catch_up", "asset_id": asset.id},
			}
		)

	for side, amount, role in plan:
		acc = role_accounts.get(role)
		if acc is None:
			raise ApiError("ACCOUNT_REQUIRED", f"حساب نقش {role} در خروج دارایی مشخص نیست.", http_status=400)
		line: Dict[str, Any] = {
			"account_id": acc.id,
			"debit": amount if side == "debit" else Decimal("0"),
			"credit": amount if side == "credit" else Decimal("0"),
			"description": f"خروج دارایی {asset.code} — {role}",
			"extra_info": {"side": role, "asset_id": asset.id, "disposal_kind": kind},
		}
		if role == "proceeds":
			line["person_id"] = counterparty.get("person_id")
			line["bank_account_id"] = counterparty.get("bank_account_id")
			line["cash_register_id"] = counterparty.get("cash_register_id")
			line["petty_cash_id"] = counterparty.get("petty_cash_id")
		lines.append(line)

	document = _create_balanced_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(currency_id),
		document_type=DOCUMENT_TYPE_DISPOSAL,
		document_date=document_date,
		description=f"خروج دارایی ثابت {asset.code} — {asset.name}",
		extra_info={
			"source": FA_SOURCE,
			"link_type": LINK_DISPOSAL,
			"asset_id": asset.id,
			"asset_code": asset.code,
			"disposal_kind": kind,
			"catch_up_amount": str(catch_up),
		},
		lines=lines,
		project_id=asset.project_id,
	)
	db.add(
		FixedAssetDocumentLink(
			business_id=business_id,
			asset_id=asset.id,
			document_id=document.id,
			link_type=LINK_DISPOSAL,
		)
	)
	return document


def post_subsequent_expenditure_document(
	db: Session,
	*,
	business_id: int,
	user_id: int,
	asset: FixedAsset,
	cls: FixedAssetClass,
	settings: FixedAssetSettings,
	counterparty: Dict[str, Any],
	kind: str,
	amount: Decimal,
	vat: Decimal,
	quant: Decimal,
	document_date: date,
	description: Optional[str] = None,
) -> Document:
	amount_q = q_amount(amount, quant)
	vat_q = q_amount(vat, quant)
	try:
		plan = build_subsequent_expenditure_plan(kind=kind, amount=amount_q, vat=vat_q)
	except DisposalPlanError as exc:
		raise ApiError(exc.code, exc.message, http_status=400) from exc

	currency_id = settings.default_currency_id
	if not currency_id:
		raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض اموال در تنظیمات مشخص نشده است.", http_status=400)

	role_accounts: Dict[str, Account] = {
		"counterparty": counterparty["account"],
		"cost": class_cost_account(db, business_id, cls),
		"repair_expense": settings_repair_account(db, business_id, settings),
	}
	if vat_q > 0:
		role_accounts["vat"] = resolve_account(
			db, business_id, account_id=settings.vat_account_id, code=VAT_ACCOUNT_CODE
		)

	lines: List[Dict[str, Any]] = []
	for side, amt, role in plan:
		acc = role_accounts.get(role)
		if acc is None:
			raise ApiError("ACCOUNT_REQUIRED", f"حساب نقش {role} در مخارج بعدی مشخص نیست.", http_status=400)
		line: Dict[str, Any] = {
			"account_id": acc.id,
			"debit": amt if side == "debit" else Decimal("0"),
			"credit": amt if side == "credit" else Decimal("0"),
			"description": description or f"مخارج بعدی دارایی {asset.code} — {role}",
			"extra_info": {"side": role, "asset_id": asset.id, "expenditure_kind": kind},
		}
		if role == "counterparty":
			line["person_id"] = counterparty.get("person_id")
			line["bank_account_id"] = counterparty.get("bank_account_id")
			line["cash_register_id"] = counterparty.get("cash_register_id")
			line["petty_cash_id"] = counterparty.get("petty_cash_id")
		lines.append(line)

	document = _create_balanced_document(
		db,
		business_id=business_id,
		user_id=user_id,
		currency_id=int(currency_id),
		document_type=DOCUMENT_TYPE_SUBSEQUENT,
		document_date=document_date,
		description=description or f"مخارج بعدی دارایی ثابت {asset.code} — {asset.name}",
		extra_info={
			"source": FA_SOURCE,
			"link_type": LINK_SUBSEQUENT,
			"asset_id": asset.id,
			"asset_code": asset.code,
			"expenditure_kind": kind,
		},
		lines=lines,
		project_id=asset.project_id,
	)
	db.add(
		FixedAssetDocumentLink(
			business_id=business_id,
			asset_id=asset.id,
			document_id=document.id,
			link_type=LINK_SUBSEQUENT,
		)
	)
	return document
