"""
تسعیر خطوط سند به ارز پایه (P2.5) و غنی‌سازی جمع فاکتور (P2).

اصول:
- debit/credit همیشه به ارز سند می‌مانند (مانده حساب بانکی/صندوق به ارز همان حساب).
- debit_base/credit_base معادل ارز پایه برای گزارش‌گیری، مانده شخص، بستن سال.
- ستون‌ها nullable؛ اسناد قدیمی با fallback (fx سند → resolve نرخ → ارز پایه) خوانده می‌شوند.
- کسب‌وکار تک‌ارزی: rate=1 و base=amount (یا NULL؛ هر دو از نظر معنایی یکسان‌اند اگر ارز سند=پایه).
"""
from __future__ import annotations

import logging
from datetime import datetime, time, timezone
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from app.core.responses import ApiError
from app.services.currency_quant import get_currency_quant_and_round

logger = logging.getLogger(__name__)


def _d(value: Any) -> Decimal:
	try:
		return Decimal(str(value if value is not None else 0))
	except Exception:
		return Decimal(0)


def parse_fx_rate_from_extra(extra_info: Any) -> Optional[Decimal]:
	"""نرخ قفل‌شده از extra_info.fx؛ در صورت skip یا نامعتبر → None."""
	if not isinstance(extra_info, dict):
		return None
	fx = extra_info.get("fx")
	if not isinstance(fx, dict) or fx.get("skipped"):
		return None
	raw = fx.get("rate")
	if raw is None:
		return None
	try:
		rate = Decimal(str(raw))
	except Exception:
		return None
	if rate <= 0:
		return None
	return rate


def quantize_money(amount: Decimal, quant: Decimal, *, round_on: bool) -> Decimal:
	if not round_on:
		return amount
	return amount.quantize(quant, rounding=ROUND_HALF_UP)


def compute_base_amounts(
	*,
	debit: Decimal,
	credit: Decimal,
	rate: Decimal,
	base_quant: Decimal,
	round_on: bool,
) -> Tuple[Decimal, Decimal]:
	"""debit/credit × rate → مبالغ پایه گردشده طبق اعشار ارز پایه."""
	r = rate if rate > 0 else Decimal(1)
	debit_base = quantize_money(_d(debit) * r, base_quant, round_on=round_on)
	credit_base = quantize_money(_d(credit) * r, base_quant, round_on=round_on)
	return debit_base, credit_base


def resolve_document_fx_rate(
	db: Session,
	document: Document,
	*,
	business: Optional[Business] = None,
	allow_infer: bool = True,
	fallback_one_on_missing: bool = True,
) -> Tuple[Optional[Decimal], str]:
	"""
	نرخ تبدیل ۱ واحد ارز سند → ارز پایه.

	Returns: (rate, source) که source یکی از:
	  snapshot | base | inferred | missing | no_default_currency
	"""
	biz = business or db.get(Business, int(document.business_id))
	if not biz or not biz.default_currency_id:
		return None, "no_default_currency"

	base_id = int(biz.default_currency_id)
	doc_currency_id = int(document.currency_id or 0)
	if doc_currency_id == base_id:
		return Decimal(1), "base"

	snap = parse_fx_rate_from_extra(document.extra_info)
	if snap is not None:
		return snap, "snapshot"

	if not allow_infer:
		return (Decimal(1), "missing") if fallback_one_on_missing else (None, "missing")

	from app.services.business_currency_rate_service import resolve_rate_to_base, _to_utc_aware
	from app.services.invoice_fx_revaluation import compute_fx_as_of_utc, get_fx_revaluation_policy

	policy = get_fx_revaluation_policy(biz)
	reg = document.registered_at or datetime.now(timezone.utc)
	if reg.tzinfo is None:
		reg = reg.replace(tzinfo=timezone.utc)
	reg = _to_utc_aware(reg)
	as_of = compute_fx_as_of_utc(document.document_date, reg, policy)
	try:
		res = resolve_rate_to_base(db, int(document.business_id), doc_currency_id, as_of)
		rate = res["rate"] if isinstance(res["rate"], Decimal) else Decimal(str(res["rate"]))
		if rate > 0:
			return rate, "inferred"
	except ApiError:
		pass
	try:
		fallback_as_of = datetime.combine(
			document.document_date, time(23, 59, 59, 999999), tzinfo=timezone.utc
		)
		res = resolve_rate_to_base(db, int(document.business_id), doc_currency_id, fallback_as_of)
		rate = res["rate"] if isinstance(res["rate"], Decimal) else Decimal(str(res["rate"]))
		if rate > 0:
			return rate, "inferred"
	except ApiError as e:
		logger.warning(
			"document_line_fx: no rate business=%s document=%s currency=%s: %s",
			document.business_id,
			document.id,
			doc_currency_id,
			e,
		)

	if fallback_one_on_missing:
		return Decimal(1), "missing"
	return None, "missing"


def stamp_document_lines_fx_base(
	db: Session,
	document: Document,
	*,
	business: Optional[Business] = None,
	only_missing: bool = False,
	allow_infer: bool = True,
) -> int:
	"""
	پر کردن exchange_rate / debit_base / credit_base برای همه خطوط یک سند.

	only_missing=True → فقط خطوطی که هنوز base ندارند (مناسب backfill).
	Returns: تعداد خطوط به‌روزشده.
	"""
	biz = business or db.get(Business, int(document.business_id))
	if not biz or not biz.default_currency_id:
		return 0

	rate, _source = resolve_document_fx_rate(
		db,
		document,
		business=biz,
		allow_infer=allow_infer,
		# V2-P8: هرگز base را با نرخ جعلی ۱ برای اسناد ارزی ناقص پر نکن
		fallback_one_on_missing=False,
	)
	if rate is None:
		return 0

	base_quant, round_on = get_currency_quant_and_round(db, int(biz.default_currency_id))
	lines: List[DocumentLine] = (
		db.query(DocumentLine).filter(DocumentLine.document_id == int(document.id)).all()
	)
	updated = 0
	for line in lines:
		if only_missing and line.debit_base is not None and line.credit_base is not None:
			continue
		debit_base, credit_base = compute_base_amounts(
			debit=_d(line.debit),
			credit=_d(line.credit),
			rate=rate,
			base_quant=base_quant,
			round_on=round_on,
		)
		line.exchange_rate = rate
		line.debit_base = debit_base
		line.credit_base = credit_base
		updated += 1
	return updated


def line_side_amount_to_base(
	db: Session,
	document: Document,
	line: DocumentLine,
	amount: Any,
	*,
	side: str,
	rate_cache: Dict[int, Decimal],
	base_currency_by_business: Dict[int, Optional[int]],
) -> Decimal:
	"""
	تبدیل یک طرف خط (debit یا credit) به ارز پایه با اولویت فیلدهای ذخیره‌شده.
	side: 'debit' | 'credit'
	"""
	amt = _d(amount)
	if amt == 0:
		return Decimal(0)

	if side == "debit" and line.debit_base is not None and _d(line.debit) == amt:
		return _d(line.debit_base)
	if side == "credit" and line.credit_base is not None and _d(line.credit) == amt:
		return _d(line.credit_base)

	bid = int(document.business_id)
	if bid not in base_currency_by_business:
		bz = db.get(Business, bid)
		base_currency_by_business[bid] = (
			int(bz.default_currency_id) if bz and bz.default_currency_id else None
		)
	base_id = base_currency_by_business[bid]
	if base_id is None:
		return amt

	# نرخ خط ذخیره‌شده
	if line.exchange_rate is not None and _d(line.exchange_rate) > 0:
		quant, round_on = get_currency_quant_and_round(db, int(base_id))
		return quantize_money(amt * _d(line.exchange_rate), quant, round_on=round_on)

	# نرخ سند (کش‌شده) یا resolve
	doc_id = int(document.id)
	if doc_id in rate_cache:
		rate = rate_cache[doc_id]
	else:
		rate, _src = resolve_document_fx_rate(
			db, document, allow_infer=True, fallback_one_on_missing=True
		)
		rate = rate if rate is not None else Decimal(1)
		rate_cache[doc_id] = rate

	quant, round_on = get_currency_quant_and_round(db, int(base_id))
	return quantize_money(amt * rate, quant, round_on=round_on)


def build_invoice_dual_totals(
	db: Session,
	document: Document,
	*,
	business: Optional[Business] = None,
) -> Dict[str, Any]:
	"""
	P2: ساختار totals دوگانه برای پاسخ API فاکتور.

	- totals.foreign: همان جمع‌های ارز سند (از extra_info.totals)
	- totals.base: معادل ارز پایه (اگر fx معتبر باشد)
	- fx: snapshot یا خلاصه وضعیت
	"""
	biz = business or db.get(Business, int(document.business_id))
	extra = document.extra_info if isinstance(document.extra_info, dict) else {}
	raw_totals = extra.get("totals") if isinstance(extra.get("totals"), dict) else {}
	fx = extra.get("fx") if isinstance(extra.get("fx"), dict) else None

	foreign = {
		"gross": float(_d(raw_totals.get("gross"))),
		"discount": float(_d(raw_totals.get("discount"))),
		"tax": float(_d(raw_totals.get("tax"))),
		"net": float(_d(raw_totals.get("net"))),
		"adjustments_net": float(_d(raw_totals.get("adjustments_net"))),
		"adjustments_tax": float(_d(raw_totals.get("adjustments_tax"))),
		"currency_id": int(document.currency_id) if document.currency_id else None,
	}
	# قابل پرداخت ≈ net + adj_net + adj_tax (هم‌راستا با UI)
	payable_foreign = (
		_d(foreign["net"]) + _d(foreign["adjustments_net"]) + _d(foreign["adjustments_tax"])
	)
	foreign["payable"] = float(payable_foreign)

	out: Dict[str, Any] = {
		"foreign": foreign,
		"base": None,
		"fx": fx,
		"is_foreign_currency": False,
		"show_dual": False,
	}

	if not biz or not biz.default_currency_id:
		return out

	base_id = int(biz.default_currency_id)
	doc_cur = int(document.currency_id or 0)
	out["is_foreign_currency"] = doc_cur != base_id

	rate, source = resolve_document_fx_rate(
		db, document, business=biz, allow_infer=True, fallback_one_on_missing=False
	)
	# برای ارز پایه همیشه dual لازم نیست
	if doc_cur == base_id:
		base_quant, round_on = get_currency_quant_and_round(db, base_id)
		base_block = {
			k: float(quantize_money(_d(v), base_quant, round_on=round_on))
			for k, v in foreign.items()
			if k != "currency_id"
		}
		base_block["currency_id"] = base_id
		base_block["rate"] = 1.0
		base_block["rate_source"] = "base"
		out["base"] = base_block
		out["show_dual"] = False
		return out

	if rate is None:
		out["show_dual"] = False
		return out

	base_quant, round_on = get_currency_quant_and_round(db, base_id)

	def _to_base(v: Any) -> float:
		return float(quantize_money(_d(v) * rate, base_quant, round_on=round_on))

	out["base"] = {
		"gross": _to_base(foreign["gross"]),
		"discount": _to_base(foreign["discount"]),
		"tax": _to_base(foreign["tax"]),
		"net": _to_base(foreign["net"]),
		"adjustments_net": _to_base(foreign["adjustments_net"]),
		"adjustments_tax": _to_base(foreign["adjustments_tax"]),
		"payable": _to_base(foreign["payable"]),
		"currency_id": base_id,
		"rate": float(rate),
		"rate_source": source,
	}
	# فقط وقتی ارز ≠ پایه و نرخ معتبر: نمایش دوگانه (Gate در UI هم MC را چک می‌کند)
	out["show_dual"] = True
	return out


def backfill_document_lines_fx_base(
	db: Session,
	*,
	business_id: Optional[int] = None,
	batch_size: int = 200,
	only_with_fx_snapshot: bool = True,
	max_documents: Optional[int] = None,
	commit_every_batch: bool = True,
) -> Dict[str, int]:
	"""
	مهاجرت نرم لایه ۲: پر کردن base برای اسنادی که fx دارند (پیش‌فرض).
	idempotent با only_missing روی خطوط.
	از keyset روی document.id استفاده می‌کند (نه OFFSET) تا روی دیتابیس بزرگ مقیاس‌پذیر باشد.
	"""
	from sqlalchemy import text

	processed = 0
	updated_docs = 0
	updated_lines = 0
	skipped = 0
	last_id = 0

	while True:
		if max_documents is not None and processed >= max_documents:
			break

		# انتخاب دسته‌ای: فقط اسنادی که هنوز حداقل یک خط بدون base دارند
		params: Dict[str, Any] = {"last_id": last_id, "lim": int(batch_size)}
		biz_clause = ""
		if business_id is not None:
			biz_clause = "AND d.business_id = :business_id"
			params["business_id"] = int(business_id)

		if only_with_fx_snapshot:
			# اسناد با snapshot نرخ، یا ارز سند = ارز پایه کسب‌وکار
			sql = text(
				f"""
				SELECT d.id
				FROM documents d
				JOIN businesses b ON b.id = d.business_id
				WHERE d.id > :last_id
				  {biz_clause}
				  AND EXISTS (
					SELECT 1 FROM document_lines dl
					WHERE dl.document_id = d.id
					  AND (dl.debit_base IS NULL OR dl.credit_base IS NULL)
				  )
				  AND (
					b.default_currency_id IS NOT NULL
					AND (
					  d.currency_id = b.default_currency_id
					  OR (
						d.extra_info IS NOT NULL
						AND (d.extra_info::jsonb) ? 'fx'
						AND COALESCE(((d.extra_info::jsonb)->'fx'->>'skipped')::boolean, false) = false
						AND ((d.extra_info::jsonb)->'fx'->>'rate') IS NOT NULL
					  )
					)
				  )
				ORDER BY d.id
				LIMIT :lim
				"""
			)
		else:
			sql = text(
				f"""
				SELECT d.id
				FROM documents d
				WHERE d.id > :last_id
				  {biz_clause}
				  AND EXISTS (
					SELECT 1 FROM document_lines dl
					WHERE dl.document_id = d.id
					  AND (dl.debit_base IS NULL OR dl.credit_base IS NULL)
				  )
				ORDER BY d.id
				LIMIT :lim
				"""
			)

		ids = [int(r[0]) for r in db.execute(sql, params).fetchall()]
		if not ids:
			break

		for doc_id in ids:
			if max_documents is not None and processed >= max_documents:
				break
			doc = db.get(Document, doc_id)
			if not doc:
				skipped += 1
				continue
			processed += 1
			last_id = doc_id
			biz = db.get(Business, int(doc.business_id))
			n = stamp_document_lines_fx_base(
				db,
				doc,
				business=biz,
				only_missing=True,
				allow_infer=not only_with_fx_snapshot,
			)
			if n:
				updated_docs += 1
				updated_lines += n
			else:
				skipped += 1

		db.flush()
		if commit_every_batch:
			db.commit()

	return {
		"processed_documents": processed,
		"updated_documents": updated_docs,
		"updated_lines": updated_lines,
		"skipped_documents": skipped,
	}

