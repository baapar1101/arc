"""
تسویه و انتقال بین‌ارزی با رعایت تراز سند و مانده حساب‌ها.

قواعد v2 (E1/E2/E3):
- فقط وقتی کسب‌وکار چندارزی است
- E1: نرخ جفت فرعی↔فرعی = متقاطع از دو نرخ به پایه (بدون جدول جفت)
- E2: ارز سند حسابداری برای مسیر بین‌ارزی همیشه ارز پایه است
- E3: سود/زیان تسعیر تحقق‌یافته در 60204 / 70801
- نرخ: ۱ واحد ارز غیرپایه = rate × ارز پایه (هم‌معنا با business_currency_rates)
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.check import Check
from adapters.db.models.document import Document
from adapters.db.models.petty_cash import PettyCash
from app.core.responses import ApiError
from app.services.business_currency_rate_service import resolve_rate_to_base
from app.services.currency_quant import get_currency_quant_and_round
from app.services.document_line_fx_service import parse_fx_rate_from_extra, quantize_money
from app.services.fx_rate_provider_service import business_is_multi_currency


FX_GAIN_ACCOUNT_CODE = "60204"  # درآمد تسعیر ارز
FX_LOSS_ACCOUNT_CODE = "70801"  # هزینه تسعیر ارز


def get_payment_item_account_currency_id(db: Session, payment_item: Dict[str, Any]) -> Optional[int]:
	ttype = (payment_item.get("transaction_type") or payment_item.get("type") or "").strip().lower()
	if ttype == "bank":
		ref_id = payment_item.get("bank_id")
		if not ref_id:
			return None
		acct = db.query(BankAccount).filter(BankAccount.id == int(ref_id)).first()
		return int(acct.currency_id) if acct else None
	if ttype == "cash_register":
		ref_id = payment_item.get("cash_register_id")
		if not ref_id:
			return None
		acct = db.query(CashRegister).filter(CashRegister.id == int(ref_id)).first()
		return int(acct.currency_id) if acct else None
	if ttype == "petty_cash":
		ref_id = payment_item.get("petty_cash_id")
		if not ref_id:
			return None
		acct = db.query(PettyCash).filter(PettyCash.id == int(ref_id)).first()
		return int(acct.currency_id) if acct else None
	if ttype == "check":
		ref_id = payment_item.get("check_id")
		if not ref_id:
			return None
		chk = db.query(Check).filter(Check.id == int(ref_id)).first()
		return int(chk.currency_id) if chk else None
	return None


def _d(v: Any) -> Decimal:
	try:
		return Decimal(str(v if v is not None else 0))
	except Exception:
		return Decimal(0)


def _as_of_from_document(document: Document) -> datetime:
	try:
		dd = document.document_date
		if dd is None:
			return datetime.now(timezone.utc)
		if isinstance(dd, datetime):
			return dd if dd.tzinfo else dd.replace(tzinfo=timezone.utc)
		return datetime(dd.year, dd.month, dd.day, tzinfo=timezone.utc)
	except Exception:
		return datetime.now(timezone.utc)


def _resolve_rate_to_base_required(
	db: Session,
	*,
	business_id: int,
	currency_id: int,
	base_id: int,
	as_of: datetime,
	override: Optional[Any] = None,
	label: str = "ارز",
) -> Decimal:
	if int(currency_id) == int(base_id):
		return Decimal(1)
	if override is not None:
		rate = _d(override)
		if rate <= 0:
			raise ApiError("INVALID_FX_RATE", f"نرخ تبدیل {label} نامعتبر است", http_status=400)
		return rate
	try:
		info = resolve_rate_to_base(db, int(business_id), int(currency_id), as_of)
		rate = _d(info.get("rate"))
		if rate <= 0:
			raise ApiError(
				"FX_RATE_REQUIRED",
				f"نرخ تبدیل معتبر برای {label} یافت نشد",
				http_status=400,
			)
		return rate
	except ApiError:
		raise
	except Exception as exc:
		raise ApiError(
			"FX_RATE_REQUIRED",
			f"نرخ تبدیل برای {label} الزامی است: {exc}",
			http_status=400,
		) from exc


def resolve_cross_currency_settlement_plan(
	db: Session,
	*,
	business_id: int,
	settles_currency_id: int,
	payment_item: Dict[str, Any],
	as_of: Optional[datetime] = None,
	settles_rate_snapshot: Optional[Decimal] = None,
) -> Optional[Dict[str, Any]]:
	"""
	طرح تسویه بین‌ارزی عمومی (فاکتور یا دریافت/پرداخت مستقل).
	اگر ارز پرداخت == ارز تسویه → None.
	"""
	payment_currency_id = get_payment_item_account_currency_id(db, payment_item)
	if payment_currency_id is None:
		return None
	if int(payment_currency_id) == int(settles_currency_id):
		return None

	if not business_is_multi_currency(db, int(business_id)):
		raise ApiError(
			"PAYMENT_CURRENCY_MISMATCH",
			"ارز حساب پرداخت با ارز تسویه یکسان نیست",
			http_status=400,
		)

	biz = db.get(Business, int(business_id))
	if not biz or not biz.default_currency_id:
		raise ApiError("NO_DEFAULT_CURRENCY", "ارز پایه کسب‌وکار تنظیم نشده است", http_status=400)
	base_id = int(biz.default_currency_id)

	payment_amount = _d(payment_item.get("amount"))
	if payment_amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ پرداخت نامعتبر است", http_status=400)

	settles_raw = payment_item.get("settles_amount")
	if settles_raw is None:
		raise ApiError(
			"SETTLES_AMOUNT_REQUIRED",
			"برای پرداخت با ارز متفاوت، settles_amount (مبلغ تسویه) الزامی است",
			http_status=400,
		)
	settles_amount = _d(settles_raw)
	if settles_amount <= 0:
		raise ApiError("INVALID_SETTLES_AMOUNT", "مبلغ تسویه ارزی نامعتبر است", http_status=400)

	fx_meta = payment_item.get("fx") if isinstance(payment_item.get("fx"), dict) else {}
	legacy_fx = payment_item.get("fx_rate") or payment_item.get("exchange_rate")
	if legacy_fx is None and fx_meta.get("rate") is not None:
		legacy_fx = fx_meta.get("rate")

	when = as_of or datetime.now(timezone.utc)
	settle_id = int(settles_currency_id)

	inv_override = payment_item.get("invoice_rate_to_base") or payment_item.get("settles_rate_to_base")
	pay_override = payment_item.get("payment_rate_to_base")
	if inv_override is None and settle_id != base_id and int(payment_currency_id) == base_id:
		inv_override = legacy_fx if legacy_fx is not None else settles_rate_snapshot
	if pay_override is None and settle_id == base_id and int(payment_currency_id) != base_id:
		pay_override = legacy_fx
	if (
		settle_id != base_id
		and int(payment_currency_id) != base_id
		and inv_override is None
		and legacy_fx is not None
	):
		inv_override = legacy_fx
	if inv_override is None and settles_rate_snapshot and settle_id != base_id:
		inv_override = settles_rate_snapshot

	r_settle = _resolve_rate_to_base_required(
		db,
		business_id=int(business_id),
		currency_id=settle_id,
		base_id=base_id,
		as_of=when,
		override=inv_override,
		label="ارز تسویه",
	)
	r_pay = _resolve_rate_to_base_required(
		db,
		business_id=int(business_id),
		currency_id=int(payment_currency_id),
		base_id=base_id,
		as_of=when,
		override=pay_override,
		label="ارز پرداخت",
	)

	base_quant, round_on = get_currency_quant_and_round(db, base_id)
	ar_base = quantize_money(settles_amount * r_settle, base_quant, round_on=round_on)
	cash_base = quantize_money(payment_amount * r_pay, base_quant, round_on=round_on)
	fx_diff = ar_base - cash_base
	cross_rate = None
	if r_pay > 0:
		cross_rate = quantize_money(r_settle / r_pay, Decimal("0.00000001"), round_on=False)

	return {
		"invoice_currency_id": settle_id,  # سازگاری با build_fx_settlement_extra
		"settles_currency_id": settle_id,
		"payment_currency_id": int(payment_currency_id),
		"base_currency_id": base_id,
		"document_currency_id": base_id,
		"settles_amount": settles_amount,
		"payment_amount": payment_amount,
		"tx_rate": cross_rate if cross_rate is not None else r_settle,
		"invoice_rate_to_base": r_settle,
		"payment_rate_to_base": r_pay,
		"invoice_ref_rate": settles_rate_snapshot,
		"ar_base": ar_base,
		"cash_base": cash_base,
		"fx_diff": fx_diff,
		"mode": str(fx_meta.get("mode") or payment_item.get("fx_mode") or "manual"),
	}


def resolve_cross_currency_payment_plan(
	db: Session,
	*,
	business_id: int,
	invoice: Document,
	payment_item: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
	"""Wrapper فاکتور روی طرح عمومی تسویه."""
	return resolve_cross_currency_settlement_plan(
		db,
		business_id=business_id,
		settles_currency_id=int(invoice.currency_id),
		payment_item=payment_item,
		as_of=_as_of_from_document(invoice),
		settles_rate_snapshot=parse_fx_rate_from_extra(invoice.extra_info),
	)


def build_fx_settlement_extra(plan: Dict[str, Any]) -> Dict[str, Any]:
	return {
		"settles_amount": str(plan["settles_amount"]),
		"settles_currency_id": int(plan["invoice_currency_id"]),
		"payment_amount": str(plan["payment_amount"]),
		"payment_currency_id": int(plan["payment_currency_id"]),
		"rate": str(plan["tx_rate"]),
		"invoice_rate_to_base": str(plan.get("invoice_rate_to_base") or plan["tx_rate"]),
		"payment_rate_to_base": str(plan.get("payment_rate_to_base") or 1),
		"ar_base": str(plan["ar_base"]),
		"cash_base": str(plan["cash_base"]),
		"fx_diff": str(plan["fx_diff"]),
		"mode": plan.get("mode") or "manual",
		"base_currency_id": int(plan["base_currency_id"]),
	}


def prepare_standalone_receipt_payment_cross_currency(
	db: Session,
	business_id: int,
	data: Dict[str, Any],
	*,
	is_receipt: bool,
) -> Dict[str, Any]:
	"""
	V2-P4: اگر حساب‌ها با ارز سند (تسویه) فرق دارند، سند را به پایه (E2) بازنویسی می‌کند.
	اگر از قبل fx_adjustment_lines / account_currency_amount از مسیر فاکتور آمده باشد، دست نمی‌زند.
	"""
	if data.get("extra_info") and isinstance(data["extra_info"], dict):
		if data["extra_info"].get("cross_currency") and data.get("fx_adjustment_lines"):
			# مسیر فاکتور از قبل آماده شده
			return data

	settle_cur = int(data.get("currency_id") or 0)
	if settle_cur <= 0:
		return data

	account_lines = list(data.get("account_lines") or [])
	person_lines = list(data.get("person_lines") or [])
	if not account_lines or not person_lines:
		return data

	# آیا بین‌ارزی هست؟
	needs = False
	for al in account_lines:
		if not isinstance(al, dict):
			continue
		# اگر قبلاً stamp شده، احتمالاً مسیر فاکتور است
		if al.get("account_currency_amount") is not None:
			return data
		pay_cur = get_payment_item_account_currency_id(db, al)
		if pay_cur is not None and int(pay_cur) != settle_cur:
			needs = True
			break
	if not needs:
		return data

	biz = db.get(Business, int(business_id))
	if not biz or not biz.default_currency_id:
		raise ApiError("NO_DEFAULT_CURRENCY", "ارز پایه کسب‌وکار تنظیم نشده است", http_status=400)
	base_id = int(biz.default_currency_id)

	doc_date_raw = data.get("document_date")
	try:
		if isinstance(doc_date_raw, datetime):
			as_of = doc_date_raw if doc_date_raw.tzinfo else doc_date_raw.replace(tzinfo=timezone.utc)
		elif isinstance(doc_date_raw, date):
			as_of = datetime(doc_date_raw.year, doc_date_raw.month, doc_date_raw.day, tzinfo=timezone.utc)
		else:
			as_of = datetime.now(timezone.utc)
	except Exception:
		as_of = datetime.now(timezone.utc)

	base_quant, round_on = get_currency_quant_and_round(db, base_id)
	r_settle = _resolve_rate_to_base_required(
		db,
		business_id=int(business_id),
		currency_id=settle_cur,
		base_id=base_id,
		as_of=as_of,
		label="ارز سند/تسویه",
	)

	new_account_lines: List[Dict[str, Any]] = []
	fx_adj: List[Dict[str, Any]] = list(data.get("fx_adjustment_lines") or [])
	settlement_extras: List[Dict[str, Any]] = []

	for al in account_lines:
		if not isinstance(al, dict):
			continue
		pay_cur = get_payment_item_account_currency_id(db, al)
		native_amt = _d(al.get("amount"))
		if pay_cur is None or int(pay_cur) == settle_cur:
			# هم‌ارز با تسویه → فقط تبدیل به پایه
			cash_base = quantize_money(native_amt * r_settle, base_quant, round_on=round_on)
			rewritten = {**al, "amount": float(cash_base)}
			if settle_cur != base_id:
				rewritten["account_currency_amount"] = float(native_amt)
				rewritten["account_currency_id"] = settle_cur
			new_account_lines.append(rewritten)
			continue

		# بین‌ارزی: settles_amount الزامی
		plan = resolve_cross_currency_settlement_plan(
			db,
			business_id=int(business_id),
			settles_currency_id=settle_cur,
			payment_item=al,
			as_of=as_of,
		)
		if plan is None:
			new_account_lines.append(al)
			continue

		fx_settlement = build_fx_settlement_extra(plan)
		settlement_extras.append(fx_settlement)
		rewritten = {
			**al,
			"amount": float(plan["cash_base"]),
			"account_currency_amount": float(plan["payment_amount"]),
			"account_currency_id": int(plan["payment_currency_id"]),
		}
		new_account_lines.append(rewritten)

		fx_diff = _d(plan["fx_diff"])
		if abs(fx_diff) > 0:
			if is_receipt:
				if fx_diff > 0:
					fx_adj.append({
						"account_code": FX_LOSS_ACCOUNT_CODE,
						"amount": float(fx_diff),
						"description": "زیان تسعیر ارز دریافت/پرداخت",
						"side": "debit",
					})
				else:
					fx_adj.append({
						"account_code": FX_GAIN_ACCOUNT_CODE,
						"amount": float(-fx_diff),
						"description": "سود تسعیر ارز دریافت/پرداخت",
						"side": "credit",
					})
			else:
				if fx_diff > 0:
					fx_adj.append({
						"account_code": FX_GAIN_ACCOUNT_CODE,
						"amount": float(fx_diff),
						"description": "سود تسعیر ارز دریافت/پرداخت",
						"side": "credit",
					})
				else:
					fx_adj.append({
						"account_code": FX_LOSS_ACCOUNT_CODE,
						"amount": float(-fx_diff),
						"description": "زیان تسعیر ارز دریافت/پرداخت",
						"side": "debit",
					})

	# اشخاص: مبلغ به پایه؛ fx_settlement روی اولین شخص (یا همه با نسبت)
	new_person_lines: List[Dict[str, Any]] = []
	primary_fx = settlement_extras[0] if settlement_extras else None
	for i, pl in enumerate(person_lines):
		if not isinstance(pl, dict):
			continue
		native_p = _d(pl.get("amount"))
		p_base = quantize_money(native_p * r_settle, base_quant, round_on=round_on)
		extra = dict(pl.get("extra_info") or {}) if isinstance(pl.get("extra_info"), dict) else {}
		if primary_fx and i == 0:
			extra["fx_settlement"] = primary_fx
		elif settle_cur != base_id:
			extra["settles_native"] = {
				"amount": str(native_p),
				"currency_id": settle_cur,
			}
		new_person_lines.append({
			**pl,
			"amount": float(p_base),
			"extra_info": extra,
		})

	out = dict(data)
	out["currency_id"] = base_id
	out["account_lines"] = new_account_lines
	out["person_lines"] = new_person_lines
	out["fx_adjustment_lines"] = fx_adj
	extra_all = dict(out.get("extra_info") or {}) if isinstance(out.get("extra_info"), dict) else {}
	extra_all["cross_currency"] = True
	extra_all["settles_currency_id"] = settle_cur
	if settlement_extras:
		extra_all["fx_settlement"] = settlement_extras[0]
	out["extra_info"] = extra_all
	return out


def resolve_transfer_account_currency(
	db: Session, account_type: str, account_id: Any
) -> Optional[int]:
	tp = str(account_type or "").strip()
	if account_id is None:
		return None
	try:
		aid = int(account_id)
	except Exception:
		return None
	if tp == "bank":
		row = db.query(BankAccount).filter(BankAccount.id == aid).first()
		return int(row.currency_id) if row else None
	if tp == "cash_register":
		row = db.query(CashRegister).filter(CashRegister.id == aid).first()
		return int(row.currency_id) if row else None
	if tp == "petty_cash":
		row = db.query(PettyCash).filter(PettyCash.id == aid).first()
		return int(row.currency_id) if row else None
	return None


def resolve_cross_currency_transfer_plan(
	db: Session,
	*,
	business_id: int,
	source_type: str,
	source_id: Any,
	destination_type: str,
	destination_id: Any,
	source_amount: Decimal,
	destination_amount: Optional[Decimal],
	fx_rate: Optional[Decimal],
	source_rate_to_base: Optional[Decimal] = None,
	destination_rate_to_base: Optional[Decimal] = None,
	as_of: Optional[datetime] = None,
) -> Optional[Dict[str, Any]]:
	"""None اگر هم‌ارز؛ در غیر این صورت طرح انتقال بین‌ارزی (E1/E2)."""
	src_cur = resolve_transfer_account_currency(db, source_type, source_id)
	dst_cur = resolve_transfer_account_currency(db, destination_type, destination_id)
	if src_cur is None or dst_cur is None:
		return None
	if int(src_cur) == int(dst_cur):
		return None

	if not business_is_multi_currency(db, int(business_id)):
		raise ApiError(
			"TRANSFER_CURRENCY_MISMATCH",
			"ارز حساب مبدأ و مقصد یکسان نیست",
			http_status=400,
		)

	biz = db.get(Business, int(business_id))
	if not biz or not biz.default_currency_id:
		raise ApiError("NO_DEFAULT_CURRENCY", "ارز پایه کسب‌وکار تنظیم نشده است", http_status=400)
	base_id = int(biz.default_currency_id)

	if source_amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ مبدأ نامعتبر است", http_status=400)

	when = as_of or datetime.now(timezone.utc)
	base_quant, round_on = get_currency_quant_and_round(db, base_id)

	# سازگاری v1: fx_rate تکی وقتی یکی پایه است
	src_override = source_rate_to_base
	dst_override = destination_rate_to_base
	if src_override is None and int(src_cur) != base_id and int(dst_cur) == base_id:
		src_override = fx_rate
	if dst_override is None and int(src_cur) == base_id and int(dst_cur) != base_id:
		dst_override = fx_rate
	if src_override is None and int(src_cur) != base_id and int(dst_cur) != base_id and fx_rate is not None:
		# نرخ متقاطع مبدأ→مقصد داده شده؛ مبدأ→پایه را از جدول می‌گیریم و مقصد را از متقاطع می‌سازیم
		pass

	r_src = _resolve_rate_to_base_required(
		db,
		business_id=int(business_id),
		currency_id=int(src_cur),
		base_id=base_id,
		as_of=when,
		override=src_override,
		label="ارز مبدأ",
	)

	if (
		dst_override is None
		and int(src_cur) != base_id
		and int(dst_cur) != base_id
		and fx_rate is not None
		and _d(fx_rate) > 0
	):
		# fx_rate = واحد مقصد به ازای ۱ واحد مبدأ ≈ r_src / r_dst → r_dst = r_src / fx_rate
		dst_override = r_src / _d(fx_rate)

	r_dst = _resolve_rate_to_base_required(
		db,
		business_id=int(business_id),
		currency_id=int(dst_cur),
		base_id=base_id,
		as_of=when,
		override=dst_override,
		label="ارز مقصد",
	)

	dst_quant, dst_round = get_currency_quant_and_round(db, int(dst_cur))
	dst_amt = destination_amount
	if dst_amt is None:
		if r_dst <= 0:
			raise ApiError("INVALID_FX_RATE", "نرخ مقصد نامعتبر است", http_status=400)
		dst_amt = quantize_money(source_amount * r_src / r_dst, dst_quant, round_on=dst_round)
	if dst_amt <= 0:
		raise ApiError("INVALID_DESTINATION_AMOUNT", "مبلغ مقصد نامعتبر است", http_status=400)

	src_base = quantize_money(source_amount * r_src, base_quant, round_on=round_on)
	dst_base = quantize_money(dst_amt * r_dst, base_quant, round_on=round_on)
	fx_diff = src_base - dst_base
	cross = quantize_money(r_src / r_dst, Decimal("0.00000001"), round_on=False) if r_dst > 0 else None

	return {
		"source_currency_id": int(src_cur),
		"destination_currency_id": int(dst_cur),
		"base_currency_id": base_id,
		"source_amount": source_amount,
		"destination_amount": dst_amt,
		"rate": cross if cross is not None else (fx_rate or r_src),
		"source_rate_to_base": r_src,
		"destination_rate_to_base": r_dst,
		"source_base": src_base,
		"destination_base": dst_base,
		"fx_diff": fx_diff,
		"document_currency_id": base_id,
	}
