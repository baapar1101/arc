from __future__ import annotations

import calendar
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session, joinedload, selectinload

from adapters.db.models.bank_account import BankAccount
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.received_loan_facility import (
	ReceivedLoanFacility,
	ReceivedLoanInstallment,
	ReceivedLoanInstallmentPayment,
)

from app.services import document_service
from app.services.received_loan_facility_accounting import (
	DOCUMENT_SOURCE_RECEIVED_LOAN_FACILITY,
	DOCUMENT_TYPE_RECEIVED_LOAN_FACILITY,
	notify_document_cache_manual,
	post_disbursement_document,
	post_installment_payment_document,
)


def _count_facility_installments(db: Session, facility_id: int) -> int:
	return int(
		db.query(func.count())
		.select_from(ReceivedLoanInstallment)
		.where(ReceivedLoanInstallment.facility_id == facility_id)
		.scalar()
		or 0
	)


def _detach_disbursement_document(db: Session, obj: ReceivedLoanFacility) -> Optional[Dict[str, Any]]:
	"""حذف سند تنخواص و قطع ارجاع.FK را قبل از بازسازی اقساط انجام می‌دهد.
	بازیابی کش پس از commit خارجی با دیکشنری برگردانده‌شده انجام شود."""
	if not obj.disbursement_document_id:
		return None
	doc_id = int(obj.disbursement_document_id)
	doc_prev = db.get(Document, doc_id)
	cache_kw: Optional[Dict[str, Any]] = None
	if doc_prev:
		current_fy = _current_fiscal_year(db, int(obj.business_id))
		_assert_loan_document_deletable(
			db,
			doc_prev,
			facility_id=int(obj.id),
			current_fiscal_year=current_fy,
		)
	obj.disbursement_document_id = None
	db.flush()
	if doc_prev:
		cache_kw = _delete_loan_document_row(db, doc_prev)
	return cache_kw


def _validate_bank_currency(db: Session, facility_currency_id: int, bank_account_id: int | None) -> None:
	from app.core.responses import ApiError

	if bank_account_id is None:
		return
	ba = db.query(BankAccount).filter(BankAccount.id == bank_account_id).first()
	if not ba or int(ba.currency_id) != int(facility_currency_id):
		raise ApiError(
			"BANK_CURRENCY_MISMATCH",
			"Bank account currency must match facility currency",
			http_status=400,
		)


class LoanFacilityStatuses:
	draft = "draft"
	active = "active"
	closed = "closed"


class LoanScheduleMethods:
	annuity = "annuity"
	equal_principal = "equal_principal"


def _money(x: Decimal | float | int | str) -> Decimal:
	return Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def _add_months(d: date, months: int) -> date:
	m0 = d.month - 1 + months
	y = d.year + m0 // 12
	m = m0 % 12 + 1
	day = min(d.day, calendar.monthrange(y, m)[1])
	return date(y, m, day)


def _monthly_rate_percent(annual_percent: Decimal | None) -> Decimal:
	if annual_percent is None:
		return Decimal("0")
	return annual_percent / Decimal("100") / Decimal("12")


def _facility_has_payments(db: Session, facility_id: int) -> bool:
	stmt = (
		select(func.count())
		.select_from(ReceivedLoanInstallmentPayment)
		.join(ReceivedLoanInstallment, ReceivedLoanInstallmentPayment.installment_id == ReceivedLoanInstallment.id)
		.where(ReceivedLoanInstallment.facility_id == facility_id)
	)
	cnt = db.execute(stmt).scalar()
	return bool(cnt or 0) > 0


def _validate_bank_same_business(db: Session, business_id: int, bank_account_id: int | None) -> None:
	if bank_account_id is None:
		return
	row = db.query(BankAccount).filter(BankAccount.id == bank_account_id).first()
	if not row or row.business_id != business_id:
		from app.core.responses import ApiError

		raise ApiError("INVALID_BANK_ACCOUNT", "Bank account not found or not in this business", http_status=400)


def _current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	from app.core.responses import ApiError

	fy = (
		db.query(FiscalYear)
		.filter(
			FiscalYear.business_id == int(business_id),
			FiscalYear.is_last == True,  # noqa: E712
		)
		.first()
	)
	if not fy:
		raise ApiError("FISCAL_YEAR_NOT_FOUND", "Active fiscal year not found", http_status=404)
	return fy


def _date_in_fiscal_year(ref_date: date, fiscal_year: FiscalYear) -> bool:
	return fiscal_year.start_date <= ref_date <= fiscal_year.end_date


def _loan_document_cache_kw(doc: Document) -> Dict[str, Any]:
	return {
		"business_id": int(doc.business_id),
		"fiscal_year_id": int(doc.fiscal_year_id),
		"document_id": int(doc.id),
		"document_type": str(doc.document_type),
	}


def _is_loan_document_for_facility(doc: Document, facility_id: int) -> bool:
	extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
	if doc.document_type == DOCUMENT_TYPE_RECEIVED_LOAN_FACILITY:
		try:
			return int(extra.get("facility_id")) == int(facility_id)
		except Exception:
			return False
	if extra.get("source") != DOCUMENT_SOURCE_RECEIVED_LOAN_FACILITY:
		return False
	try:
		return int(extra.get("facility_id")) == int(facility_id)
	except Exception:
		return False


def _collect_loan_documents(db: Session, facility: ReceivedLoanFacility) -> Dict[int, Document]:
	from app.core.responses import ApiError

	docs: Dict[int, Document] = {}
	referenced_ids: set[int] = set()
	if facility.disbursement_document_id:
		referenced_ids.add(int(facility.disbursement_document_id))
	for inst in facility.installments or []:
		for pay in inst.payments or []:
			if pay.document_id:
				referenced_ids.add(int(pay.document_id))

	if referenced_ids:
		for doc in db.query(Document).filter(Document.id.in_(referenced_ids)).all():
			docs[int(doc.id)] = doc
		missing = referenced_ids.difference(docs.keys())
		if missing:
			raise ApiError(
				"LOAN_DOCUMENT_MISSING",
				"Linked loan document is missing; repair loan accounting links before deleting the facility",
				http_status=409,
			)

	possible_docs = (
		db.query(Document)
		.filter(
			Document.business_id == int(facility.business_id),
			Document.document_type.in_((DOCUMENT_TYPE_RECEIVED_LOAN_FACILITY, "manual")),
		)
		.all()
	)
	for doc in possible_docs:
		if _is_loan_document_for_facility(doc, int(facility.id)):
			docs[int(doc.id)] = doc
	return docs


def _assert_loan_document_deletable(
	db: Session,
	doc: Document,
	*,
	facility_id: int,
	current_fiscal_year: FiscalYear,
) -> None:
	from app.core.responses import ApiError

	if not _is_loan_document_for_facility(doc, facility_id):
		raise ApiError(
			"LOAN_DOCUMENT_MISMATCH",
			"Linked document does not belong to this loan facility",
			http_status=409,
		)
	if int(doc.fiscal_year_id) != int(current_fiscal_year.id):
		raise ApiError(
			"FISCAL_YEAR_LOCKED",
			"Loan facility has linked accounting documents outside the active fiscal year",
			http_status=409,
		)
	if doc.document_type not in (DOCUMENT_TYPE_RECEIVED_LOAN_FACILITY, "manual"):
		raise ApiError(
			"LOAN_DOCUMENT_TYPE_UNSUPPORTED",
			"Linked loan document type is not supported for automatic deletion",
			http_status=409,
		)
	extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
	dev = doc.developer_settings if isinstance(doc.developer_settings, dict) else {}
	if any(bool(x.get("locked")) or bool(x.get("is_locked")) for x in (extra, dev)):
		raise ApiError("DOCUMENT_LOCKED", "Linked loan document is locked", http_status=409)
	has_related_checks = (
		db.query(DocumentLine.id)
		.filter(DocumentLine.document_id == int(doc.id), DocumentLine.check_id.isnot(None))
		.first()
		is not None
	)
	if has_related_checks:
		raise ApiError(
			"DOCUMENT_REFERENCED",
			"Linked loan document has check-related lines and cannot be deleted automatically",
			http_status=409,
		)
	try:
		from app.services.wallet_service import check_document_has_wallet_transactions

		wallet_check = check_document_has_wallet_transactions(db, int(doc.id))
		if wallet_check["has_wallet_transactions"] and wallet_check.get("has_protected_transactions", False):
			raise ApiError(
				"DOCUMENT_HAS_WALLET_TRANSACTIONS",
				wallet_check["message"],
				http_status=409,
			)
	except ApiError:
		raise
	except Exception:
		pass


def _assert_loan_payments_deletable(
	facility: ReceivedLoanFacility,
	*,
	current_fiscal_year: FiscalYear,
) -> None:
	from app.core.responses import ApiError

	for inst in facility.installments or []:
		for pay in inst.payments or []:
			if not _date_in_fiscal_year(pay.payment_date, current_fiscal_year):
				raise ApiError(
					"FISCAL_YEAR_LOCKED",
					"Loan facility has installment payments outside the active fiscal year",
					http_status=409,
				)


def _delete_loan_document_row(db: Session, doc: Document) -> Dict[str, Any]:
	cache_kw = _loan_document_cache_kw(doc)
	db.delete(doc)
	db.flush()
	return cache_kw


def installment_remaining(inst: ReceivedLoanInstallment) -> Tuple[Decimal, Decimal, Decimal]:
	rm_pen = max(_money(inst.penalty_due) - _money(inst.penalty_paid), Decimal("0"))
	rm_int = max(_money(inst.interest_due) - _money(inst.interest_paid), Decimal("0"))
	rm_pri = max(_money(inst.principal_due) - _money(inst.principal_paid), Decimal("0"))
	return rm_pen, rm_int, rm_pri


def _allocate_payment(amount: Decimal, inst: ReceivedLoanInstallment) -> Tuple[Decimal, Decimal, Decimal, Decimal]:
	"""اول جریمه، سپس بهره، سپس اصل. ماندهٔ اختصاص‌نخورده را برمی‌گرداند (باید 0 باشد برای پرداخت کامل قطعه؛ بیش‌پرداخت مجاز نیست)."""
	rm_pen, rm_int, rm_pri = installment_remaining(inst)
	max_total = rm_pen + rm_int + rm_pri
	amt = _money(amount)
	if amt <= Decimal("0"):
		from app.core.responses import ApiError

		raise ApiError("INVALID_AMOUNT", "Payment amount must be positive", http_status=400)
	if amt > max_total + Decimal("0.000001"):
		from app.core.responses import ApiError

		raise ApiError(
			"PAYMENT_EXCEEDS_BALANCE",
			"Payment amount exceeds remaining installment balance",
			http_status=400,
		)
	rest = amt
	ppen = min(rest, rm_pen)
	rest -= ppen
	pint = min(rest, rm_int)
	rest -= pint
	ppri = min(rest, rm_pri)
	rest -= ppri
	rest_rounded = _money(rest)
	if rest_rounded != Decimal("0"):
		from app.core.responses import ApiError

		raise ApiError("ALLOCATION_ERROR", "Could not allocate full payment across components", http_status=500)
	return ppen, pint, ppri, Decimal("0")


def generate_installment_schedule(
	method: str,
	principal_amount: Decimal,
	annual_percent: Decimal | None,
	n: int,
	first_due: date,
) -> List[Tuple[date, Decimal, Decimal]]:
	if n < 1:
		from app.core.responses import ApiError

		raise ApiError("INVALID_INSTALLMENT_COUNT", "Installment count must be at least 1", http_status=400)
	if annual_percent is not None and annual_percent < Decimal("0"):
		from app.core.responses import ApiError

		raise ApiError("INVALID_RATE", "annual_interest_rate_percent must be zero or positive", http_status=400)

	P = _money(principal_amount)
	i_m = _monthly_rate_percent(annual_percent)

	rows: List[Tuple[date, Decimal, Decimal]] = []

	if method == LoanScheduleMethods.equal_principal:
		pp_each = _money(P / n)
		balance = P
		for period in range(1, n + 1):
			int_part = _money(balance * i_m)
			if period < n:
				principal_part = pp_each
			else:
				principal_part = _money(balance)
			balance = _money(balance - principal_part)
			due = _add_months(first_due, period - 1)
			rows.append((due, principal_part, int_part))

	elif method == LoanScheduleMethods.annuity:
		if i_m == Decimal("0"):
			pp_each = _money(P / n)
			balance = P
			for period in range(1, n + 1):
				int_part = _money(balance * i_m)
				if period < n:
					principal_part = pp_each
				else:
					principal_part = _money(balance)
				balance = _money(balance - principal_part)
				due = _add_months(first_due, period - 1)
				rows.append((due, principal_part, int_part))
		else:
			one_plus = (Decimal("1") + i_m) ** n
			try:
				emi = _money(P * i_m * one_plus / (one_plus - Decimal("1")))
			except Exception:
				from app.core.responses import ApiError

				raise ApiError("SCHEDULE_ERROR", "Unable to calculate annuity installments", http_status=400)
			balance = P
			for period in range(1, n + 1):
				int_part = _money(balance * i_m)
				if period < n:
					principal_part = _money(min(max(emi - int_part, Decimal("0")), balance))
				else:
					principal_part = _money(balance)
					int_part = _money(balance * i_m)
				balance = _money(balance - principal_part)
				due = _add_months(first_due, period - 1)
				rows.append((due, principal_part, int_part))
	else:
		from app.core.responses import ApiError

		raise ApiError("INVALID_SCHEDULE_METHOD", "Unsupported schedule method", http_status=400)

	return rows


def facility_to_dict(
	obj: ReceivedLoanFacility,
	*,
	include_installments: bool = False,
) -> Dict[str, Any]:
	data: Dict[str, Any] = {
		"id": obj.id,
		"business_id": obj.business_id,
		"currency_id": obj.currency_id,
		"created_by_user_id": obj.created_by_user_id,
		"title": obj.title,
		"notes": obj.notes,
		"lender_bank_account_id": obj.lender_bank_account_id,
		"principal_amount": float(_money(obj.principal_amount)),
		"annual_interest_rate_percent": float(obj.annual_interest_rate_percent)
		if obj.annual_interest_rate_percent is not None
		else None,
		"contract_date": obj.contract_date.isoformat() if obj.contract_date else None,
		"first_installment_date": obj.first_installment_date.isoformat() if obj.first_installment_date else None,
		"installment_count": obj.installment_count,
		"status": obj.status,
		"schedule_method": obj.schedule_method,
		"disbursement_document_id": obj.disbursement_document_id,
		"extra_info": obj.extra_info,
		"created_at": obj.created_at.isoformat() if obj.created_at else None,
		"updated_at": obj.updated_at.isoformat() if obj.updated_at else None,
	}
	if include_installments:
		installs = sorted(obj.installments or [], key=lambda x: x.sequence_no)
		data["installments"] = [installment_to_dict(i, include_payments=True) for i in installs]
	return data


def payment_to_dict(pay: ReceivedLoanInstallmentPayment) -> Dict[str, Any]:
	return {
		"id": pay.id,
		"installment_id": pay.installment_id,
		"payment_date": pay.payment_date.isoformat() if pay.payment_date else None,
		"amount_total": float(_money(pay.amount_total)),
		"principal_part": float(_money(pay.principal_part)),
		"interest_part": float(_money(pay.interest_part)),
		"penalty_part": float(_money(pay.penalty_part)),
		"bank_account_id": pay.bank_account_id,
		"document_id": pay.document_id,
		"description": pay.description,
		"created_at": pay.created_at.isoformat() if pay.created_at else None,
	}


def installment_to_dict(inst: ReceivedLoanInstallment, *, include_payments: bool = False) -> Dict[str, Any]:
	rm_pen, rm_int, rm_pri = installment_remaining(inst)
	out = {
		"id": inst.id,
		"facility_id": inst.facility_id,
		"sequence_no": inst.sequence_no,
		"due_date": inst.due_date.isoformat() if inst.due_date else None,
		"principal_due": float(_money(inst.principal_due)),
		"interest_due": float(_money(inst.interest_due)),
		"penalty_due": float(_money(inst.penalty_due)),
		"principal_paid": float(_money(inst.principal_paid)),
		"interest_paid": float(_money(inst.interest_paid)),
		"penalty_paid": float(_money(inst.penalty_paid)),
		"remaining_penalty": float(rm_pen),
		"remaining_interest": float(rm_int),
		"remaining_principal": float(rm_pri),
		"is_fully_paid": rm_pri <= Decimal("0") and rm_int <= Decimal("0") and rm_pen <= Decimal("0"),
		"extra_info": inst.extra_info,
		"updated_at": inst.updated_at.isoformat() if inst.updated_at else None,
	}
	if include_payments:
		pays = sorted(getattr(inst, "payments", None) or [], key=lambda p: (p.payment_date, p.id))
		out["payments"] = [payment_to_dict(x) for x in pays]
	return out


def list_facilities(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
	q = db.query(ReceivedLoanFacility).filter(ReceivedLoanFacility.business_id == business_id)

	search = (query.get("search") or "").strip()
	if search:
		pat = f"%{search}%"
		q = q.filter(ReceivedLoanFacility.title.like(pat))

	take = int(query.get("take") or 20)
	skip = int(query.get("skip") or 0)
	take = max(1, min(take, 200))

	total = q.count()

	sort_desc = query.get("sort_desc", True)
	col = ReceivedLoanFacility.created_at
	items = (
		q.order_by(col.desc() if sort_desc else col.asc()).offset(skip).limit(take).all()
	)
	return {
		"items": [facility_to_dict(x) for x in items],
		"pagination": {"total": total, "take": take, "skip": skip},
	}


def create_facility(
	db: Session,
	business_id: int,
	user_id: int,
	data: Dict[str, Any],
) -> Dict[str, Any]:
	from app.core.responses import ApiError

	title = (data.get("title") or "").strip()
	if title == "":
		raise ApiError("TITLE_REQUIRED", "Title is required", http_status=400)

	lender_bank_account_id = data.get("lender_bank_account_id")
	if lender_bank_account_id is not None:
		try:
			lender_bank_account_id = int(lender_bank_account_id)
		except Exception:
			raise ApiError("INVALID_BANK_ACCOUNT", "Invalid lender bank account", http_status=400)

	_validate_bank_same_business(db, business_id, lender_bank_account_id)

	try:
		currency_id = int(data["currency_id"])
	except Exception:
		raise ApiError("INVALID_CURRENCY", "currency_id is required", http_status=400)
	_validate_bank_currency(db, currency_id, lender_bank_account_id)

	try:
		principal_amount = data.get("principal_amount")
		if principal_amount is None:
			raise ValueError()
		P = _money(principal_amount)
		if P <= Decimal("0"):
			raise ValueError()
	except Exception:
		raise ApiError("INVALID_PRINCIPAL", "principal_amount must be a positive decimal", http_status=400)

	annual = data.get("annual_interest_rate_percent")
	annual_decimal: Decimal | None
	if annual is None or annual == "":
		annual_decimal = None
	else:
		try:
			annual_decimal = Decimal(str(annual))
		except Exception:
			raise ApiError("INVALID_RATE", "Invalid annual_interest_rate_percent", http_status=400)
		if annual_decimal < Decimal("0"):
			raise ApiError("INVALID_RATE", "annual_interest_rate_percent must be zero or positive", http_status=400)

	cd_raw = data.get("contract_date")
	if not cd_raw:
		raise ApiError("CONTRACT_DATE_REQUIRED", "contract_date is required", http_status=400)
	try:
		contract_date = date.fromisoformat(str(cd_raw)[:10])
	except Exception:
		raise ApiError("INVALID_CONTRACT_DATE", "contract_date must be ISO date YYYY-MM-DD", http_status=400)

	fi_raw = data.get("first_installment_date")
	first_inst: Optional[date] = None
	if fi_raw:
		try:
			first_inst = date.fromisoformat(str(fi_raw)[:10])
		except Exception:
			raise ApiError("INVALID_FIRST_INSTALLMENT_DATE", "first_installment_date must be ISO date", http_status=400)
		if first_inst < contract_date:
			raise ApiError(
				"INVALID_FIRST_INSTALLMENT_DATE",
				"first_installment_date must be on or after contract_date",
				http_status=400,
			)

	ic_raw = data.get("installment_count")
	install_count: Optional[int]
	if ic_raw is None:
		install_count = None
	else:
		try:
			install_count = int(ic_raw)
		except Exception:
			raise ApiError("INVALID_INSTALLMENT_COUNT", "installment_count invalid", http_status=400)
		if install_count < 1:
			raise ApiError("INVALID_INSTALLMENT_COUNT", "installment_count must be at least 1", http_status=400)

	obj = ReceivedLoanFacility(
		business_id=business_id,
		currency_id=currency_id,
		created_by_user_id=user_id,
		title=title,
		notes=data.get("notes"),
		lender_bank_account_id=lender_bank_account_id,
		principal_amount=P,
		annual_interest_rate_percent=annual_decimal,
		contract_date=contract_date,
		first_installment_date=first_inst,
		installment_count=install_count,
		status=LoanFacilityStatuses.draft,
		extra_info=data.get("extra_info") if isinstance(data.get("extra_info"), dict) else None,
	)
	db.add(obj)
	db.commit()
	db.refresh(obj)
	return facility_to_dict(obj)


def get_facility_by_id(db: Session, facility_id: int, *, with_installments: bool = False) -> Optional[Dict[str, Any]]:
	q = db.query(ReceivedLoanFacility).filter(ReceivedLoanFacility.id == facility_id)
	if with_installments:
		q = q.options(
			selectinload(ReceivedLoanFacility.installments).selectinload(
				ReceivedLoanInstallment.payments
			),
		)
	obj = q.first()
	return facility_to_dict(obj, include_installments=with_installments) if obj else None


def update_facility(db: Session, facility_id: int, data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
	from app.core.responses import ApiError

	obj = db.query(ReceivedLoanFacility).filter(ReceivedLoanFacility.id == facility_id).first()
	if not obj:
		return None

	fin_locked = obj.status != LoanFacilityStatuses.draft or _count_facility_installments(db, facility_id) > 0
	if fin_locked:
		forbidden_keys = (
			"lender_bank_account_id",
			"currency_id",
			"principal_amount",
			"annual_interest_rate_percent",
			"contract_date",
			"first_installment_date",
			"installment_count",
			"extra_info",
		)
		for k in forbidden_keys:
			if k in data:
				raise ApiError(
					"FACILITY_FINANCIAL_LOCKED",
					"Cannot change facility financial fields after scheduling or activating the contract",
					http_status=409,
				)

	if "title" in data:
		title = (data.get("title") or "").strip()
		if title == "":
			raise ApiError("TITLE_REQUIRED", "Title is required", http_status=400)
		obj.title = title
	if "notes" in data:
		obj.notes = data.get("notes")
	if not fin_locked:
		if "currency_id" in data:
			obj.currency_id = int(data["currency_id"])
		if "lender_bank_account_id" in data:
			j = data["lender_bank_account_id"]
			bid = int(j) if j is not None else None
			_validate_bank_same_business(db, obj.business_id, bid)
			obj.lender_bank_account_id = bid
		_validate_bank_currency(db, obj.currency_id, obj.lender_bank_account_id)
		if "principal_amount" in data:
			P = _money(data["principal_amount"])
			if P <= Decimal("0"):
				raise ApiError("INVALID_PRINCIPAL", "principal_amount invalid", http_status=400)
			obj.principal_amount = P
		if "annual_interest_rate_percent" in data:
			ap = data.get("annual_interest_rate_percent")
			if ap is None or ap == "":
				obj.annual_interest_rate_percent = None
			else:
				annual_decimal = Decimal(str(ap))
				if annual_decimal < Decimal("0"):
					raise ApiError("INVALID_RATE", "annual_interest_rate_percent must be zero or positive", http_status=400)
				obj.annual_interest_rate_percent = annual_decimal
		if "contract_date" in data:
			cd = data["contract_date"]
			obj.contract_date = date.fromisoformat(str(cd)[:10])
		if "first_installment_date" in data:
			fi = data.get("first_installment_date")
			obj.first_installment_date = (
				date.fromisoformat(str(fi)[:10]) if fi is not None else None
			)
		if "installment_count" in data:
			ic = data.get("installment_count")
			if ic is None:
				obj.installment_count = None
			else:
				install_count = int(ic)
				if install_count < 1:
					raise ApiError("INVALID_INSTALLMENT_COUNT", "installment_count must be at least 1", http_status=400)
				obj.installment_count = install_count
		if "extra_info" in data and isinstance(data["extra_info"], dict):
			obj.extra_info = data["extra_info"]
		if obj.first_installment_date is not None and obj.first_installment_date < obj.contract_date:
			raise ApiError(
				"INVALID_FIRST_INSTALLMENT_DATE",
				"first_installment_date must be on or after contract_date",
				http_status=400,
			)

	obj.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(obj)
	return facility_to_dict(obj)


def delete_facility(db: Session, facility_id: int, business_id: int) -> bool:
	from app.core.responses import ApiError

	obj = (
		db.query(ReceivedLoanFacility)
		.options(
			selectinload(ReceivedLoanFacility.installments).selectinload(
				ReceivedLoanInstallment.payments
			),
		)
		.filter(and_(ReceivedLoanFacility.id == facility_id, ReceivedLoanFacility.business_id == business_id))
		.first()
	)
	if not obj:
		return False
	current_fy = _current_fiscal_year(db, business_id)
	_assert_loan_payments_deletable(obj, current_fiscal_year=current_fy)
	related_docs = _collect_loan_documents(db, obj)
	for doc in related_docs.values():
		_assert_loan_document_deletable(
			db,
			doc,
			facility_id=int(obj.id),
			current_fiscal_year=current_fy,
		)

	cache_items = []
	for doc in related_docs.values():
		cache_items.append(_delete_loan_document_row(db, doc))
	db.delete(obj)
	db.commit()
	for cache_kw in cache_items:
		document_service.invalidate_documents_cache(**cache_kw)
	return True


def regenerate_schedule(db: Session, facility_id: int, data: Dict[str, Any], acting_user_id: int) -> Dict[str, Any]:
	from app.core.responses import ApiError

	obj = db.query(ReceivedLoanFacility).filter(ReceivedLoanFacility.id == facility_id).first()
	if not obj:
		raise ApiError("LOAN_FACILITY_NOT_FOUND", "Facility not found", http_status=404)

	if _facility_has_payments(db, facility_id):
		raise ApiError("HAS_PAYMENTS", "Cannot regenerate schedule after payments exist", http_status=409)

	detached_disburse_cache_kw = _detach_disbursement_document(db, obj)

	method = data.get("schedule_method") or obj.schedule_method
	if method not in (LoanScheduleMethods.annuity, LoanScheduleMethods.equal_principal):
		raise ApiError("INVALID_SCHEDULE_METHOD", "schedule_method must be annuity or equal_principal", http_status=400)

	n_c = data.get("installment_count", obj.installment_count)
	fd_raw = data.get("first_installment_date", obj.first_installment_date)
	if n_c is None or int(n_c) < 1:
		raise ApiError("INVALID_INSTALLMENT_COUNT", "installment_count required", http_status=400)
	if fd_raw is None:
		raise ApiError("FIRST_DUE_REQUIRED", "first_installment_date required", http_status=400)
	try:
		n = int(n_c)
		fd = date.fromisoformat(str(fd_raw)[:10])
	except Exception:
		raise ApiError("BAD_SCHEDULE_PAYLOAD", "Invalid installment_count or date", http_status=400)
	if fd < obj.contract_date:
		raise ApiError(
			"INVALID_FIRST_INSTALLMENT_DATE",
			"first_installment_date must be on or after contract_date",
			http_status=400,
		)

	rows = generate_installment_schedule(
		method,
		obj.principal_amount,
		obj.annual_interest_rate_percent,
		n,
		fd,
	)
	db.query(ReceivedLoanInstallment).filter(ReceivedLoanInstallment.facility_id == facility_id).delete()
	for idx, (due, princ, inte) in enumerate(rows, start=1):
		inst = ReceivedLoanInstallment(
			facility_id=facility_id,
			sequence_no=idx,
			due_date=due,
			principal_due=princ,
			interest_due=inte,
			penalty_due=Decimal("0"),
		)
		db.add(inst)
	obj.installment_count = n
	obj.first_installment_date = fd
	obj.schedule_method = method
	obj.status = LoanFacilityStatuses.active
	obj.updated_at = datetime.utcnow()

	post_disburse = bool(data.get("post_accounting_disbursement", True))
	ddoc: Document | None = None
	if post_disburse:
		disburse_bank = data.get("disbursement_bank_account_id")
		if disburse_bank is not None:
			disburse_bank = int(disburse_bank)
			_validate_bank_same_business(db, obj.business_id, disburse_bank)
		effective_bank = disburse_bank if disburse_bank is not None else obj.lender_bank_account_id
		if effective_bank is None:
			raise ApiError(
				"BANK_REQUIRED_FOR_ACCOUNTING",
				"lender_bank_account_id or disbursement_bank_account_id required to post disbursement accounting",
				http_status=400,
			)
		_validate_bank_currency(db, obj.currency_id, int(effective_bank))
		ddoc = post_disbursement_document(
			db,
			obj.business_id,
			acting_user_id,
			title=str(obj.title or ""),
			principal_amount=_money(obj.principal_amount),
			facility_currency_id=int(obj.currency_id),
			bank_account_id=int(effective_bank),
			contract_date=obj.contract_date,
			facility_id=int(obj.id),
		)
		obj.disbursement_document_id = ddoc.id

	db.commit()

	if detached_disburse_cache_kw:
		document_service.invalidate_documents_cache(**detached_disburse_cache_kw)

	if ddoc:
		ddoc_refresh = db.get(Document, ddoc.id)
		if ddoc_refresh:
			notify_document_cache_manual(db, ddoc_refresh)

	obj = (
		db.query(ReceivedLoanFacility)
		.options(
			selectinload(ReceivedLoanFacility.installments).selectinload(
				ReceivedLoanInstallment.payments
			),
		)
		.filter(ReceivedLoanFacility.id == facility_id)
		.one_or_none()
	)
	if obj is None:
		raise ApiError(
			"LOAN_FACILITY_MISSING_AFTER_COMMIT",
			"Facility not found after schedule",
			http_status=500,
		)
	return facility_to_dict(obj, include_installments=True)


def record_payment(
	db: Session,
	business_id: int,
	user_id: int,
	facility_id: int,
	installment_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	from app.core.responses import ApiError

	inst = (
		db.query(ReceivedLoanInstallment)
		.options(joinedload(ReceivedLoanInstallment.facility))
		.join(ReceivedLoanFacility, ReceivedLoanInstallment.facility_id == ReceivedLoanFacility.id)
		.filter(
			and_(
				ReceivedLoanInstallment.id == installment_id,
				ReceivedLoanInstallment.facility_id == facility_id,
				ReceivedLoanFacility.business_id == business_id,
			)
		)
		.first()
	)
	if not inst:
		raise ApiError("LOAN_INSTALLMENT_NOT_FOUND", "Installment not found", http_status=404)

	if inst.facility.status == LoanFacilityStatuses.draft:
		raise ApiError("FACILITY_DRAFT", "Activate schedule before recording payments", http_status=409)

	try:
		amount_total = _money(payload["amount"])
	except Exception:
		raise ApiError("INVALID_AMOUNT", "amount required", http_status=400)

	pd_raw = payload.get("payment_date")
	try:
		payment_date = date.fromisoformat(str(pd_raw)[:10]) if pd_raw else datetime.utcnow().date()
	except Exception:
		raise ApiError("INVALID_PAYMENT_DATE", "payment_date ISO required", http_status=400)

	bank_account_id = payload.get("bank_account_id")
	if bank_account_id is not None:
		bank_account_id = int(bank_account_id)
		_validate_bank_same_business(db, business_id, bank_account_id)
		_validate_bank_currency(db, inst.facility.currency_id, bank_account_id)

	ppen, pint, ppri, _ = _allocate_payment(amount_total, inst)

	post_ac = bool(payload.get("post_accounting_payment", True))
	if post_ac and bank_account_id is None:
		raise ApiError(
			"BANK_REQUIRED_FOR_ACCOUNTING",
			"bank_account_id is required when post_accounting_payment is true",
			http_status=400,
		)

	pay_row = ReceivedLoanInstallmentPayment(
		installment_id=inst.id,
		payment_date=payment_date,
		amount_total=amount_total,
		principal_part=ppri,
		interest_part=pint,
		penalty_part=ppen,
		bank_account_id=bank_account_id if not post_ac else int(bank_account_id),
		document_id=None,
		description=payload.get("description"),
		created_by_user_id=user_id,
	)

	payment_doc: Document | None = None
	with db.begin_nested():
		db.add(pay_row)
		db.flush()
		if post_ac:
			assert bank_account_id is not None  # narrowed by validator
			payment_doc = post_installment_payment_document(
				db,
				business_id,
				user_id,
				title=str(inst.facility.title or ""),
				facility_currency_id=int(inst.facility.currency_id),
				facility_id=int(inst.facility.id),
				installment_id=int(inst.id),
				payment_id=int(pay_row.id),
				payment_date=payment_date,
				principal_part=ppri,
				interest_part=pint,
				penalty_part=ppen,
				bank_account_id=int(bank_account_id),
			)
			if not payment_doc:
				raise ApiError(
					"PAYMENT_ACCOUNTING_FAILED",
					"Could not create accounting document for installment payment",
					http_status=500,
				)
			pay_row.document_id = payment_doc.id
			db.flush()

	inst.principal_paid = _money(inst.principal_paid) + ppri
	inst.interest_paid = _money(inst.interest_paid) + pint
	inst.penalty_paid = _money(inst.penalty_paid) + ppen
	inst.updated_at = datetime.utcnow()

	all_inst = db.query(ReceivedLoanInstallment).filter(ReceivedLoanInstallment.facility_id == facility_id).all()
	all_paid = bool(all_inst) and all(not any(installment_remaining(x)) for x in all_inst)
	if all_paid:
		inst.facility.status = LoanFacilityStatuses.closed

	inst.facility.updated_at = datetime.utcnow()
	db.commit()

	if payment_doc:
		p_dr = db.get(Document, payment_doc.id)
		if p_dr:
			notify_document_cache_manual(db, p_dr)

	db.refresh(inst)
	db.refresh(pay_row)
	out_payment = {
		"id": pay_row.id,
		"installment_id": pay_row.installment_id,
		"amount_total": float(_money(pay_row.amount_total)),
		"principal_part": float(ppri),
		"interest_part": float(pint),
		"penalty_part": float(ppen),
		"payment_date": pay_row.payment_date.isoformat(),
		"document_id": pay_row.document_id,
	}
	return {
		"payment": out_payment,
		"installment": installment_to_dict(inst),
		"facility_status": inst.facility.status,
	}


def delete_loan_payment(
	db: Session,
	business_id: int,
	facility_id: int,
	installment_id: int,
	payment_id: int,
) -> Dict[str, Any]:
	from app.core.responses import ApiError

	pay_row = (
		db.query(ReceivedLoanInstallmentPayment)
		.options(
			joinedload(ReceivedLoanInstallmentPayment.installment).joinedload(ReceivedLoanInstallment.facility),
		)
		.filter(ReceivedLoanInstallmentPayment.id == payment_id)
		.first()
	)
	if (
		not pay_row
		or pay_row.installment_id != installment_id
		or pay_row.installment.facility_id != facility_id
		or pay_row.installment.facility.business_id != business_id
	):
		raise ApiError("LOAN_PAYMENT_NOT_FOUND", "Payment not found", http_status=404)

	inst = pay_row.installment
	fac = inst.facility
	current_fy = _current_fiscal_year(db, business_id)
	if not _date_in_fiscal_year(pay_row.payment_date, current_fy):
		raise ApiError(
			"FISCAL_YEAR_LOCKED",
			"Loan installment payment is outside the active fiscal year",
			http_status=409,
		)

	cache_kw: Dict[str, Any] | None = None
	doc_id = pay_row.document_id
	if doc_id:
		doc_prev = db.get(Document, int(doc_id))
		if doc_prev:
			_assert_loan_document_deletable(
				db,
				doc_prev,
				facility_id=int(fac.id),
				current_fiscal_year=current_fy,
			)
			cache_kw = _delete_loan_document_row(db, doc_prev)
		else:
			raise ApiError(
				"LOAN_DOCUMENT_MISSING",
				"Linked loan payment document is missing; repair loan accounting links before deleting the payment",
				http_status=409,
			)

	ppri = _money(pay_row.principal_part)
	pint = _money(pay_row.interest_part)
	ppen = _money(pay_row.penalty_part)

	inst.principal_paid = max(_money(inst.principal_paid) - ppri, Decimal("0"))
	inst.interest_paid = max(_money(inst.interest_paid) - pint, Decimal("0"))
	inst.penalty_paid = max(_money(inst.penalty_paid) - ppen, Decimal("0"))
	inst.updated_at = datetime.utcnow()

	fac.updated_at = datetime.utcnow()

	all_inst = db.query(ReceivedLoanInstallment).filter(ReceivedLoanInstallment.facility_id == facility_id).all()
	all_paid = bool(all_inst) and all(not any(installment_remaining(x)) for x in all_inst)
	if all_paid:
		fac.status = LoanFacilityStatuses.closed
	elif fac.status == LoanFacilityStatuses.closed:
		fac.status = LoanFacilityStatuses.active

	db.delete(pay_row)
	db.commit()

	if cache_kw:
		document_service.invalidate_documents_cache(**cache_kw)

	db.refresh(inst)
	return {
		"deleted_payment_id": payment_id,
		"installment": installment_to_dict(inst),
		"facility_status": fac.status,
	}
