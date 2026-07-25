"""P8: تسعیر پایان دوره — سند تعدیلی سود/زیان تحقق‌نیافته برای مانده‌های پولی ارزی."""
from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.account import Account
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.check import Check, CheckStatus, CheckType
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.petty_cash import PettyCash
from app.core.responses import ApiError
from app.services.account_native_balance import line_native_signed_amount_for_account
from app.services.business_currency_rate_service import resolve_rate_to_base
from app.services.cross_currency_settlement_service import FX_GAIN_ACCOUNT_CODE, FX_LOSS_ACCOUNT_CODE
from app.services.currency_quant import get_currency_quant_and_round
from app.services.document_line_fx_service import quantize_money
from app.services.document_service import create_manual_document
from app.services.fx_rate_provider_service import assert_multi_currency

# چک‌های باز پولی برای تسعیر پایان دوره (E4)
_OPEN_RECEIVED_CHECK_STATUSES = {
	CheckStatus.RECEIVED_ON_HAND,
	CheckStatus.DEPOSITED,
	CheckStatus.BOUNCED,
}
_OPEN_ISSUED_CHECK_STATUSES = {
	CheckStatus.TRANSFERRED_ISSUED,
}


def _d(v: Any) -> Decimal:
	try:
		return Decimal(str(v if v is not None else 0))
	except Exception:
		return Decimal(0)


def _get_account_by_code(db: Session, code: str) -> Account:
	from sqlalchemy import and_

	acc = db.query(Account).filter(
		and_(Account.business_id == None, Account.code == str(code))  # noqa: E711
	).first()
	if not acc:
		raise ApiError(
			"FX_ACCOUNT_MISSING",
			f"حساب تسعیر با کد {code} در درخت حساب‌ها یافت نشد",
			http_status=400,
		)
	return acc


def _book_and_native_for_account_lines(
	db: Session,
	*,
	business_id: int,
	fiscal_year_id: int,
	account_currency_id: int,
	bank_account_id: Optional[int] = None,
	cash_register_id: Optional[int] = None,
	petty_cash_id: Optional[int] = None,
) -> Dict[str, Decimal]:
	q = (
		db.query(DocumentLine, Document)
		.join(Document, DocumentLine.document_id == Document.id)
		.filter(
			Document.business_id == int(business_id),
			Document.fiscal_year_id == int(fiscal_year_id),
			Document.is_proforma == False,  # noqa: E712
		)
	)
	if bank_account_id is not None:
		q = q.filter(DocumentLine.bank_account_id == int(bank_account_id))
	elif cash_register_id is not None:
		q = q.filter(DocumentLine.cash_register_id == int(cash_register_id))
	elif petty_cash_id is not None:
		q = q.filter(DocumentLine.petty_cash_id == int(petty_cash_id))
	else:
		return {"native": Decimal(0), "book_base": Decimal(0)}

	native = Decimal(0)
	book_base = Decimal(0)
	for line, doc in q.all():
		native += line_native_signed_amount_for_account(
			line, doc, account_currency_id=int(account_currency_id)
		)
		# ارزش دفتری پایه
		dbase = line.debit_base
		cbase = line.credit_base
		if dbase is not None or cbase is not None:
			book_base += _d(dbase) - _d(cbase)
		else:
			# fallback: مبلغ سند اگر هم‌ارز پایه باشد؛ وگرنه از native بعداً با نرخ بسته می‌شود
			pass
	return {"native": native, "book_base": book_base}


def _person_line_base_amounts(
	db: Session,
	doc: Document,
	line: DocumentLine,
	*,
	rate_cache: Dict[int, Decimal],
	base_currency_by_business: Dict[int, Optional[int]],
) -> tuple[Decimal, Decimal]:
	from app.services.person_service import _person_line_amount_to_base

	debit_base = _person_line_amount_to_base(
		db,
		doc,
		line.debit,
		rate_cache=rate_cache,
		base_currency_by_business=base_currency_by_business,
		line=line,
		side="debit",
	)
	credit_base = _person_line_amount_to_base(
		db,
		doc,
		line.credit,
		rate_cache=rate_cache,
		base_currency_by_business=base_currency_by_business,
		line=line,
		side="credit",
	)
	return debit_base, credit_base


def _book_and_native_for_persons(
	db: Session,
	*,
	business_id: int,
	fiscal_year_id: int,
	base_currency_id: int,
) -> Dict[tuple[int, int], Dict[str, Decimal]]:
	"""
	مانده بومی و ارزش دفتری پایه به ازای (person_id, currency_id).

	قرارداد علامت مثل دارایی/بدهی پولی:
	native_signed = debit − credit  (مثبت = دریافتنی، منفی = پرداختنی)
	book_base همان علامت با debit_base − credit_base
	"""
	rows = (
		db.query(DocumentLine, Document)
		.join(Document, DocumentLine.document_id == Document.id)
		.filter(
			Document.business_id == int(business_id),
			Document.fiscal_year_id == int(fiscal_year_id),
			Document.is_proforma == False,  # noqa: E712
			DocumentLine.person_id.isnot(None),
		)
		.all()
	)

	buckets: Dict[tuple[int, int], Dict[str, Decimal]] = {}
	rate_cache: Dict[int, Decimal] = {}
	base_currency_by_business: Dict[int, Optional[int]] = {}

	def _b(key: tuple[int, int]) -> Dict[str, Decimal]:
		if key not in buckets:
			buckets[key] = {"native": Decimal(0), "book_base": Decimal(0)}
		return buckets[key]

	for line, doc in rows:
		extra = line.extra_info if isinstance(line.extra_info, dict) else {}
		person_id = int(line.person_id)

		# خط تسعیر پایان دوره: فقط ارزش پایه ارز هدف را جابه‌جا می‌کند
		if extra.get("fx_period_revaluation") and extra.get("account_currency_id") is not None:
			try:
				cid = int(extra["account_currency_id"])
			except Exception:
				continue
			if cid == int(base_currency_id):
				continue
			dbase, cbase = _person_line_base_amounts(
				db,
				doc,
				line,
				rate_cache=rate_cache,
				base_currency_by_business=base_currency_by_business,
			)
			b = _b((person_id, cid))
			b["book_base"] += dbase - cbase
			continue

		dbase, cbase = _person_line_base_amounts(
			db,
			doc,
			line,
			rate_cache=rate_cache,
			base_currency_by_business=base_currency_by_business,
		)

		fx_set = extra.get("fx_settlement") if isinstance(extra, dict) else None
		if (
			isinstance(fx_set, dict)
			and fx_set.get("settles_amount") is not None
			and fx_set.get("settles_currency_id") is not None
		):
			try:
				settles_cid = int(fx_set["settles_currency_id"])
				settles_amt = Decimal(str(fx_set["settles_amount"]))
			except Exception:
				continue
			if settles_amt < 0:
				settles_amt = Decimal(0)
			if settles_cid == int(base_currency_id):
				continue
			b = _b((person_id, settles_cid))
			# دریافت (credit روی خط شخص) مانده بدهی را کم می‌کند → credit native
			if _d(line.credit) > 0:
				b["native"] -= settles_amt  # debit−credit: credit افزایش → native کمتر
				b["book_base"] -= cbase
			elif _d(line.debit) > 0:
				b["native"] += settles_amt
				b["book_base"] += dbase
			else:
				b["native"] -= settles_amt
				b["book_base"] -= cbase
			continue

		cid = int(doc.currency_id or 0)
		if cid <= 0 or cid == int(base_currency_id):
			continue
		b = _b((person_id, cid))
		b["native"] += _d(line.debit) - _d(line.credit)
		b["book_base"] += dbase - cbase

	return buckets


def _book_and_native_for_check(
	db: Session,
	*,
	business_id: int,
	fiscal_year_id: int,
	check_obj: Check,
	notes_account_code: str,
) -> Dict[str, Decimal]:
	"""مانده بومی چک و ارزش دفتری پایه روی حساب اسناد (10403/20202)."""
	acc = _get_account_by_code(db, notes_account_code)
	rows = (
		db.query(DocumentLine, Document)
		.join(Document, DocumentLine.document_id == Document.id)
		.filter(
			Document.business_id == int(business_id),
			Document.fiscal_year_id == int(fiscal_year_id),
			Document.is_proforma == False,  # noqa: E712
			DocumentLine.check_id == int(check_obj.id),
			DocumentLine.account_id == int(acc.id),
		)
		.all()
	)
	native_mag = abs(_d(check_obj.amount))
	# دریافتنی: دارایی مثبت؛ پرداختنی: بدهی منفی
	if check_obj.type == CheckType.RECEIVED:
		native = native_mag
	else:
		native = -native_mag

	book_base = Decimal(0)
	for line, _doc in rows:
		dbase = line.debit_base
		cbase = line.credit_base
		if dbase is not None or cbase is not None:
			book_base += _d(dbase) - _d(cbase)
	return {"native": native, "book_base": book_base}


def preview_period_end_fx_revaluation(
	db: Session,
	business_id: int,
	*,
	fiscal_year_id: Optional[int] = None,
	as_of: Optional[datetime] = None,
) -> Dict[str, Any]:
	"""پیش‌نمایش اقلام تسعیر پایان دوره برای حساب‌های پولی (بانک/صندوق/تنخواه/شخص/چک)."""
	assert_multi_currency(db, int(business_id))
	biz = db.get(Business, int(business_id))
	if not biz or not biz.default_currency_id:
		raise ApiError("NO_DEFAULT_CURRENCY", "ارز پایه تنظیم نشده", http_status=400)
	base_id = int(biz.default_currency_id)

	fy = None
	if fiscal_year_id:
		fy = db.get(FiscalYear, int(fiscal_year_id))
	else:
		fy = (
			db.query(FiscalYear)
			.filter(FiscalYear.business_id == int(business_id), FiscalYear.is_last == True)  # noqa: E712
			.first()
		)
	if not fy or int(fy.business_id) != int(business_id):
		raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی یافت نشد", http_status=404)

	when = as_of or datetime.now(timezone.utc)
	base_quant, round_on = get_currency_quant_and_round(db, base_id)
	base_cur = db.get(Currency, base_id)

	positions: List[Dict[str, Any]] = []

	def _finalize_position(
		*,
		kind: str,
		ref_id: int,
		name: str,
		currency_id: int,
		coa_account_code: str,
		native: Decimal,
		book_base: Decimal,
		bank_account_id: Optional[int] = None,
		cash_register_id: Optional[int] = None,
		petty_cash_id: Optional[int] = None,
		person_id: Optional[int] = None,
		check_id: Optional[int] = None,
	) -> None:
		if int(currency_id) == base_id:
			return
		if native == 0:
			return
		try:
			rate_info = resolve_rate_to_base(db, int(business_id), int(currency_id), when)
			rate = Decimal(str(rate_info["rate"]))
		except ApiError:
			positions.append(
				{
					"kind": kind,
					"ref_id": ref_id,
					"name": name,
					"currency_id": int(currency_id),
					"native_balance": str(native),
					"error": "RATE_NOT_FOUND",
					"skipped": True,
					"person_id": person_id,
					"check_id": check_id,
					"bank_account_id": bank_account_id,
					"cash_register_id": cash_register_id,
					"petty_cash_id": petty_cash_id,
					"coa_account_code": coa_account_code,
				}
			)
			return
		revalued = quantize_money(native * rate, base_quant, round_on=round_on)
		book = book_base
		if book == 0:
			# بدون ارزش دفتری ذخیره‌شده: تعدیل نساز تا backfill کامل شود (E5)
			book = revalued
			needs_backfill = True
		else:
			needs_backfill = False
		adj = quantize_money(revalued - book, base_quant, round_on=round_on)
		cur = db.get(Currency, int(currency_id))
		positions.append(
			{
				"kind": kind,
				"ref_id": ref_id,
				"name": name,
				"currency_id": int(currency_id),
				"currency_code": cur.code if cur else None,
				"coa_account_code": coa_account_code,
				"bank_account_id": bank_account_id,
				"cash_register_id": cash_register_id,
				"petty_cash_id": petty_cash_id,
				"person_id": person_id,
				"check_id": check_id,
				"native_balance": str(native),
				"book_base": str(book),
				"closing_rate": str(rate),
				"revalued_base": str(revalued),
				"adjustment_base": str(adj),
				"needs_backfill_warning": needs_backfill,
				"skipped": adj == 0,
			}
		)

	def _add_cash_position(
		*,
		kind: str,
		ref_id: int,
		name: str,
		currency_id: int,
		coa_account_code: str,
		bank_account_id: Optional[int] = None,
		cash_register_id: Optional[int] = None,
		petty_cash_id: Optional[int] = None,
	) -> None:
		if int(currency_id) == base_id:
			return
		bal = _book_and_native_for_account_lines(
			db,
			business_id=int(business_id),
			fiscal_year_id=int(fy.id),
			account_currency_id=int(currency_id),
			bank_account_id=bank_account_id,
			cash_register_id=cash_register_id,
			petty_cash_id=petty_cash_id,
		)
		_finalize_position(
			kind=kind,
			ref_id=ref_id,
			name=name,
			currency_id=int(currency_id),
			coa_account_code=coa_account_code,
			native=bal["native"],
			book_base=bal["book_base"],
			bank_account_id=bank_account_id,
			cash_register_id=cash_register_id,
			petty_cash_id=petty_cash_id,
		)

	for bank in db.query(BankAccount).filter(BankAccount.business_id == int(business_id)).all():
		if not bank.currency_id:
			continue
		_add_cash_position(
			kind="bank",
			ref_id=int(bank.id),
			name=str(bank.name or bank.id),
			currency_id=int(bank.currency_id),
			coa_account_code="10203",
			bank_account_id=int(bank.id),
		)
	for cr in db.query(CashRegister).filter(CashRegister.business_id == int(business_id)).all():
		if not cr.currency_id:
			continue
		_add_cash_position(
			kind="cash_register",
			ref_id=int(cr.id),
			name=str(cr.name or cr.id),
			currency_id=int(cr.currency_id),
			coa_account_code="10202",
			cash_register_id=int(cr.id),
		)
	for pc in db.query(PettyCash).filter(PettyCash.business_id == int(business_id)).all():
		if not pc.currency_id:
			continue
		_add_cash_position(
			kind="petty_cash",
			ref_id=int(pc.id),
			name=str(pc.name or pc.id),
			currency_id=int(pc.currency_id),
			coa_account_code="10201",
			petty_cash_id=int(pc.id),
		)

	# اشخاص — مانده per ارز غیرپایه
	person_buckets = _book_and_native_for_persons(
		db,
		business_id=int(business_id),
		fiscal_year_id=int(fy.id),
		base_currency_id=base_id,
	)
	person_ids = {pid for (pid, _cid) in person_buckets.keys()}
	persons_map: Dict[int, Person] = {}
	if person_ids:
		persons_map = {
			int(p.id): p
			for p in db.query(Person).filter(
				Person.business_id == int(business_id),
				Person.id.in_(list(person_ids)),
			).all()
		}
	for (person_id, currency_id), bal in sorted(person_buckets.items()):
		pers = persons_map.get(int(person_id))
		name = (pers.alias_name if pers else None) or f"شخص {person_id}"
		native = bal["native"]
		# دریافتنی → 10401 ؛ پرداختنی → 20201
		coa = "10401" if native > 0 else "20201"
		_finalize_position(
			kind="person",
			ref_id=int(person_id),
			name=str(name),
			currency_id=int(currency_id),
			coa_account_code=coa,
			native=native,
			book_base=bal["book_base"],
			person_id=int(person_id),
		)

	# چک‌های باز ارزی
	open_checks = (
		db.query(Check)
		.filter(
			Check.business_id == int(business_id),
			Check.currency_id != base_id,
		)
		.all()
	)
	for chk in open_checks:
		st = chk.status
		if chk.type == CheckType.RECEIVED:
			if st not in _OPEN_RECEIVED_CHECK_STATUSES:
				continue
			coa = "10403"
		elif chk.type == CheckType.TRANSFERRED:
			if st not in _OPEN_ISSUED_CHECK_STATUSES:
				continue
			coa = "20202"
		else:
			continue
		bal = _book_and_native_for_check(
			db,
			business_id=int(business_id),
			fiscal_year_id=int(fy.id),
			check_obj=chk,
			notes_account_code=coa,
		)
		label = f"چک {chk.check_number}"
		_finalize_position(
			kind="check",
			ref_id=int(chk.id),
			name=label,
			currency_id=int(chk.currency_id),
			coa_account_code=coa,
			native=bal["native"],
			book_base=bal["book_base"],
			check_id=int(chk.id),
			person_id=int(chk.person_id) if chk.person_id else None,
		)

	adjustable = [p for p in positions if not p.get("skipped") and not p.get("error")]
	total_gain = sum((_d(p["adjustment_base"]) for p in adjustable if _d(p["adjustment_base"]) > 0), Decimal(0))
	total_loss = sum((-_d(p["adjustment_base"]) for p in adjustable if _d(p["adjustment_base"]) < 0), Decimal(0))

	by_kind: Dict[str, int] = {}
	for p in positions:
		k = str(p.get("kind") or "other")
		by_kind[k] = by_kind.get(k, 0) + 1

	return {
		"business_id": int(business_id),
		"fiscal_year_id": int(fy.id),
		"as_of": when.isoformat(),
		"base_currency": {
			"id": base_id,
			"code": base_cur.code if base_cur else None,
			"title": base_cur.title if base_cur else None,
		},
		"positions": positions,
		"positions_by_kind_count": by_kind,
		"adjustable_count": len(adjustable),
		"total_unrealized_gain_base": str(total_gain),
		"total_unrealized_loss_base": str(total_loss),
	}


def create_period_end_fx_revaluation_document(
	db: Session,
	business_id: int,
	user_id: int,
	*,
	fiscal_year_id: Optional[int] = None,
	as_of: Optional[datetime] = None,
	document_date: Optional[date] = None,
	description: Optional[str] = None,
) -> Dict[str, Any]:
	"""ایجاد سند دستی تسعیر پایان دوره (قابل‌بازبینی)."""
	preview = preview_period_end_fx_revaluation(
		db, business_id, fiscal_year_id=fiscal_year_id, as_of=as_of
	)
	adjustable = [
		p
		for p in preview["positions"]
		if not p.get("skipped") and not p.get("error") and _d(p.get("adjustment_base")) != 0
	]
	if not adjustable:
		raise ApiError(
			"NO_FX_ADJUSTMENTS",
			"هیچ ماندهٔ ارزی نیازمند تسعیر یافت نشد (یا ارزش دفتری با نرخ روز یکی است)",
			http_status=400,
		)

	base_id = int(preview["base_currency"]["id"])
	fy_id = int(preview["fiscal_year_id"])
	gain_acc = _get_account_by_code(db, FX_GAIN_ACCOUNT_CODE)
	loss_acc = _get_account_by_code(db, FX_LOSS_ACCOUNT_CODE)

	# نقشه کد حساب CoA → Account
	coa_cache: Dict[str, Account] = {}

	def coa(code: str) -> Account:
		if code not in coa_cache:
			coa_cache[code] = _get_account_by_code(db, code)
		return coa_cache[code]

	lines: List[Dict[str, Any]] = []
	doc_date = document_date or date.today()
	desc = description or f"تسعیر پایان دوره — {preview['as_of'][:10]}"

	for p in adjustable:
		adj = _d(p["adjustment_base"])
		acc = coa(str(p["coa_account_code"]))
		rate = _d(p["closing_rate"])
		# سند به ارز پایه؛ موجودی بومی حساب تغییر نکند
		extra = {
			"fx_period_revaluation": True,
			"account_currency_amount": "0",
			"account_currency_id": int(p["currency_id"]),
			"native_balance": p["native_balance"],
			"closing_rate": str(rate),
			"book_base": p["book_base"],
			"revalued_base": p["revalued_base"],
		}
		line_common = {
			"account_id": acc.id,
			"bank_account_id": p.get("bank_account_id"),
			"cash_register_id": p.get("cash_register_id"),
			"petty_cash_id": p.get("petty_cash_id"),
			"person_id": p.get("person_id"),
			"check_id": p.get("check_id"),
			"description": f"تسعیر {p['name']} ({p.get('currency_code') or p['currency_id']})",
			"extra_info": extra,
			"exchange_rate": rate,
		}
		if adj > 0:
			# افزایش ارزش دارایی ارزی → بدهکار حساب پولی، بستانکار درآمد تسعیر
			lines.append(
				{
					**line_common,
					"debit": adj,
					"credit": 0,
					"debit_base": adj,
					"credit_base": 0,
				}
			)
			lines.append(
				{
					"account_id": gain_acc.id,
					"debit": 0,
					"credit": adj,
					"debit_base": 0,
					"credit_base": adj,
					"description": f"سود تسعیر تحقق‌نیافته — {p['name']}",
					"extra_info": {"fx_period_revaluation": True, "side": "gain"},
					"exchange_rate": Decimal(1),
				}
			)
		else:
			loss_amt = abs(adj)
			lines.append(
				{
					**line_common,
					"debit": 0,
					"credit": loss_amt,
					"debit_base": 0,
					"credit_base": loss_amt,
				}
			)
			lines.append(
				{
					"account_id": loss_acc.id,
					"debit": loss_amt,
					"credit": 0,
					"debit_base": loss_amt,
					"credit_base": 0,
					"description": f"زیان تسعیر تحقق‌نیافته — {p['name']}",
					"extra_info": {"fx_period_revaluation": True, "side": "loss"},
					"exchange_rate": Decimal(1),
				}
			)

	doc_data = {
		"document_date": doc_date,
		"currency_id": base_id,
		"description": desc,
		"lines": lines,
		"extra_info": {
			"fx_period_revaluation": True,
			"as_of": preview["as_of"],
			"preview_summary": {
				"adjustable_count": preview["adjustable_count"],
				"total_unrealized_gain_base": preview["total_unrealized_gain_base"],
				"total_unrealized_loss_base": preview["total_unrealized_loss_base"],
			},
		},
	}

	created = create_manual_document(
		db,
		business_id=int(business_id),
		fiscal_year_id=fy_id,
		user_id=int(user_id),
		data=doc_data,
	)

	# stamp base on lines if create_manual didn't
	try:
		from app.services.document_line_fx_service import stamp_document_lines_fx_base

		doc_id = created.get("id") if isinstance(created, dict) else None
		if doc_id:
			doc = db.get(Document, int(doc_id))
			if doc:
				stamp_document_lines_fx_base(db, doc, commit=True)
	except Exception:
		pass

	return {
		"preview": preview,
		"document": created,
	}
