"""
پرداخت آنلاین از طریق لینک عمومی فاکتور (اشتراک سند).
پس از تأیید درگاه، سند دریافت با transaction_type=wallet ثبت و به فاکتور لینک می‌شود.
"""

from __future__ import annotations

import json
import logging
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from adapters.db.models.document import Document
from adapters.db.models.wallet import WalletTransaction
from adapters.db.models.payment_gateway import BusinessPaymentGateway, PaymentGateway
from app.core.responses import ApiError
from app.services.document_share_link_service import get_share_link_by_code
from app.services.invoice_service import calculate_invoice_remaining
from app.services.system_settings_service import get_share_link_invoice_gateway_fee_percent
from app.services.receipt_payment_service import create_receipt_payment
from app.services.payment_service import initiate_payment

logger = logging.getLogger(__name__)

WALLET_TX_TYPE_PUBLIC_INVOICE_SHARE = "public_invoice_share_pay"
INVOICE_LINK_RECEIPT_PAYMENT_IDS = "receipt_payment_document_ids"


def _parse_extra(tx: WalletTransaction) -> Dict[str, Any]:
	try:
		return json.loads(tx.extra_info or "{}") if tx.extra_info else {}
	except Exception:
		return {}


def _assert_business_gateway(db: Session, business_id: int, gateway_id: int) -> PaymentGateway:
	gw = (
		db.query(PaymentGateway)
		.filter(PaymentGateway.id == int(gateway_id), PaymentGateway.is_active == True)  # noqa: E712
		.first()
	)
	if not gw:
		raise ApiError("GATEWAY_NOT_FOUND", "درگاه پرداخت یافت نشد یا غیرفعال است", http_status=404)
	links = (
		db.query(BusinessPaymentGateway)
		.filter(
			BusinessPaymentGateway.business_id == int(business_id),
			BusinessPaymentGateway.is_active == True,  # noqa: E712
		)
		.all()
	)
	if links:
		allowed = {int(lg.gateway_id) for lg in links}
		if int(gateway_id) not in allowed:
			raise ApiError(
				"GATEWAY_NOT_LINKED",
				"این درگاه برای این کسب‌وکار فعال نیست",
				http_status=400,
			)
	return gw


def _link_options(link) -> Dict[str, Any]:
	raw = getattr(link, "options", None)
	return raw if isinstance(raw, dict) else {}


def _has_pending_public_payment(db: Session, business_id: int, invoice_id: int) -> bool:
	q = (
		db.query(WalletTransaction)
		.filter(
			WalletTransaction.business_id == int(business_id),
			WalletTransaction.type == WALLET_TX_TYPE_PUBLIC_INVOICE_SHARE,
			WalletTransaction.status == "pending",
		)
		.all()
	)
	for t in q:
		ex = _parse_extra(t)
		try:
			if int(ex.get("document_id") or 0) == int(invoice_id):
				return True
		except Exception:
			continue
	return False


def start_public_invoice_share_payment(
	db: Session,
	*,
	share_code: str,
	amount: Decimal,
) -> Dict[str, Any]:
	"""
	شروع پرداخت: اعتبارسنجی لینک و فاکتور، ایجاد تراکنش داخلی (بدون تغییر کیف‌پول SaaS)،
	بازگرداندن payment_url از درگاه.
	"""
	code = (share_code or "").strip()
	if not code:
		raise ApiError("INVALID_CODE", "کد لینک نامعتبر است", http_status=400)

	link = get_share_link_by_code(db, code)
	if not link or not link.is_active:
		raise ApiError("LINK_INACTIVE", "لینک معتبر نیست یا منقضی شده است", http_status=404)

	opts = _link_options(link)
	if not opts.get("online_payment_enabled"):
		raise ApiError("ONLINE_PAYMENT_DISABLED", "پرداخت آنلاین برای این لینک فعال نیست", http_status=403)

	gateway_id = opts.get("online_payment_gateway_id")
	try:
		gateway_id = int(gateway_id)
	except Exception:
		raise ApiError("GATEWAY_NOT_CONFIGURED", "درگاه پرداخت برای این لینک تنظیم نشده است", http_status=400)

	_assert_business_gateway(db, link.business_id, gateway_id)

	document = (
		db.query(Document)
		.filter(
			Document.id == link.document_id,
			Document.business_id == link.business_id,
		)
		.first()
	)
	if not document:
		raise ApiError("INVOICE_NOT_FOUND", "فاکتور یافت نشد", http_status=404)

	if document.document_type != "invoice_sales":
		raise ApiError(
			"ONLINE_PAYMENT_NOT_SUPPORTED",
			"پرداخت آنلاین فقط برای فاکتور فروش پشتیبانی می‌شود",
			http_status=400,
		)
	if getattr(document, "is_proforma", False):
		raise ApiError("PROFORMA_NOT_PAYABLE", "فاکتور پیش‌فاکتور قابل پرداخت آنلاین نیست", http_status=400)

	try:
		amt = Decimal(str(amount))
	except Exception:
		raise ApiError("INVALID_AMOUNT", "مبلغ نامعتبر است", http_status=400)
	if amt <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ باید بزرگتر از صفر باشد", http_status=400)

	# حداقل عملی برای درگاه‌های رایج (ریال)
	if amt < Decimal("1000"):
		raise ApiError("AMOUNT_TOO_SMALL", "حداقل مبلغ پرداخت ۱۰۰۰ ریال است", http_status=400)

	remaining_info = calculate_invoice_remaining(db, int(link.business_id), int(document.id))
	remaining = Decimal(str(remaining_info.get("remaining") or 0))
	if remaining <= Decimal("0.01"):
		raise ApiError("INVOICE_ALREADY_SETTLED", "مانده‌ای برای پرداخت وجود ندارد", http_status=400)
	if amt - remaining > Decimal("0.01"):
		raise ApiError("AMOUNT_EXCEEDS_REMAINING", "مبلغ از مانده فاکتور بیشتر است", http_status=400)

	if int(document.currency_id or 0) <= 0:
		raise ApiError("CURRENCY_INVALID", "ارز فاکتور نامعتبر است", http_status=400)

	extra_inv = document.extra_info if isinstance(document.extra_info, dict) else {}
	person_id = extra_inv.get("person_id")
	try:
		person_id = int(person_id)
	except Exception:
		raise ApiError("PERSON_REQUIRED", "فاکتور فاقد طرف حساب است", http_status=400)

	if _has_pending_public_payment(db, int(link.business_id), int(document.id)):
		raise ApiError(
			"PAYMENT_PENDING",
			"یک پرداخت در انتظار تأیید برای این فاکتور وجود دارد؛ لطفاً بعداً تلاش کنید",
			http_status=409,
		)

	fee_percent = Decimal(str(get_share_link_invoice_gateway_fee_percent(db)))
	if fee_percent < 0:
		fee_percent = Decimal(0)
	if fee_percent > Decimal("100"):
		fee_percent = Decimal(100)

	# کارمزد محاسباتی (ثبت در سند دریافت به‌صورت commission روی خط wallet)
	commission = (amt * fee_percent / Decimal(100)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
	if commission > amt:
		commission = amt

	doc_user_id = int(getattr(document, "created_by_user_id", None) or 0) or int(getattr(link, "created_by_user_id", None) or 0) or 0

	extra_info: Dict[str, Any] = {
		"kind": "public_invoice_share_payment",
		"share_link_code": code,
		"document_id": int(document.id),
		"person_id": person_id,
		"gateway_id": gateway_id,
		"accounting_commission": float(commission),
		"fee_percent_applied": float(fee_percent),
		"created_by_user_id": doc_user_id,
		"currency_id": int(document.currency_id),
	}

	tx = WalletTransaction(
		business_id=int(link.business_id),
		type=WALLET_TX_TYPE_PUBLIC_INVOICE_SHARE,
		status="pending",
		amount=float(amt.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
		fee_amount=float(commission) if commission > 0 else None,
		description=f"پرداخت آنلاین فاکتور {document.code or document.id}",
		external_ref=None,
		document_id=None,
		extra_info=json.dumps(extra_info, ensure_ascii=False),
	)
	db.add(tx)
	db.flush()

	try:
		init_res = initiate_payment(
			db=db,
			business_id=int(link.business_id),
			tx_id=int(tx.id),
			amount=float(amt),
			gateway_id=int(gateway_id),
		)
	except Exception as ex:
		logger.exception("public_invoice_share_gateway_init_failed", exc_info=ex)
		tx.status = "failed"
		db.flush()
		raise ApiError("GATEWAY_INIT_FAILED", f"خطا در ایجاد لینک پرداخت: {ex}", http_status=502) from ex

	db.flush()
	return {
		"transaction_id": int(tx.id),
		"payment_url": init_res.payment_url,
		"amount": float(amt),
		"accounting_commission": float(commission),
		"fee_percent": float(fee_percent),
	}


def _append_receipt_to_invoice(db: Session, invoice: Document, receipt_id: int) -> None:
	extra = dict(invoice.extra_info) if invoice.extra_info else {}
	links = dict(extra.get("links") or {})
	raw_ids = list(links.get(INVOICE_LINK_RECEIPT_PAYMENT_IDS) or [])
	new_ids: list[int] = []
	for x in raw_ids:
		try:
			new_ids.append(int(x))
		except Exception:
			continue
	if int(receipt_id) not in new_ids:
		new_ids.append(int(receipt_id))
	links[INVOICE_LINK_RECEIPT_PAYMENT_IDS] = new_ids
	extra["links"] = links
	invoice.extra_info = extra
	flag_modified(invoice, "extra_info")
	db.add(invoice)


def confirm_public_invoice_share_payment(
	db: Session,
	tx: WalletTransaction,
	*,
	success: bool,
	external_ref: str | None = None,
	user_id: int | None = None,
) -> Dict[str, Any]:
	"""تأیید بازگشت درگاه: ثبت سند دریافت و اتصال به فاکتور (بدون تغییر کیف‌پول کسب‌وکار SaaS)."""
	if (tx.type or "") != WALLET_TX_TYPE_PUBLIC_INVOICE_SHARE:
		raise ApiError("INVALID_TX", "نوع تراکنش نامعتبر است", http_status=400)

	if (tx.status or "").lower() in ("succeeded", "failed"):
		tx.external_ref = external_ref or tx.external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status}

	ex = _parse_extra(tx)
	if not success:
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status}

	try:
		invoice_id = int(ex.get("document_id") or 0)
		person_id = int(ex.get("person_id") or 0)
		gateway_id = int(ex.get("gateway_id") or 0)
	except Exception:
		logger.error("public_invoice_share_payment_bad_metadata tx_id=%s", tx.id)
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "INVALID_TX_METADATA"}

	invoice = (
		db.query(Document)
		.filter(
			Document.id == invoice_id,
			Document.business_id == int(tx.business_id),
		)
		.with_for_update()
		.first()
	)
	if not invoice:
		logger.error("public_invoice_share_payment_invoice_missing tx_id=%s invoice_id=%s", tx.id, invoice_id)
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "INVOICE_NOT_FOUND"}

	remaining_info = calculate_invoice_remaining(db, int(tx.business_id), int(invoice.id))
	remaining = Decimal(str(remaining_info.get("remaining") or 0))
	gross = Decimal(str(tx.amount or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
	if gross <= 0:
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "INVALID_AMOUNT"}
	if gross - remaining > Decimal("0.02"):
		logger.error(
			"public_invoice_share_payment_remaining_mismatch tx_id=%s gross=%s remaining=%s",
			tx.id,
			gross,
			remaining,
		)
		tx.status = "failed"
		tx.external_ref = external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status, "error": "REMAINING_CHANGED"}

	commission = Decimal(str(ex.get("accounting_commission") or tx.fee_amount or 0))
	if commission < 0:
		commission = Decimal(0)
	if commission > gross:
		commission = gross

	doc_user_id = user_id if user_id and user_id > 0 else int(ex.get("created_by_user_id") or 0)
	if doc_user_id <= 0:
		doc_user_id = int(getattr(invoice, "created_by_user_id", None) or 0)

	account_line: Dict[str, Any] = {
		"transaction_type": "wallet",
		"amount": float(gross),
	}
	if commission > 0:
		account_line["commission"] = float(commission)

	rp_data: Dict[str, Any] = {
		"document_type": "receipt",
		"document_date": invoice.document_date.isoformat(),
		"currency_id": int(invoice.currency_id),
		"description": f"دریافت آنلاین (لینک اشتراک) — فاکتور {invoice.code or invoice.id}",
		"person_lines": [
			{
				"person_id": person_id,
				"amount": float(gross),
				"description": f"تسویه بابت فاکتور {invoice.code or invoice.id}",
				"extra_info": {
					"invoice_id": int(invoice.id),
					"invoice_code": invoice.code,
					"link_to_invoice": True,
				},
			}
		],
		"account_lines": [account_line],
		"extra_info": {
			"source": "public_invoice_share_link",
			"invoice_id": int(invoice.id),
			"wallet_transaction_id": int(tx.id),
			"payment_gateway_id": gateway_id,
			"person_is_receivable": True,
		},
	}

	rp_doc = create_receipt_payment(
		db=db,
		business_id=int(tx.business_id),
		user_id=int(doc_user_id),
		data=rp_data,
		commit=False,
	)
	receipt_id = int(rp_doc.get("id") or 0)
	if not receipt_id:
		db.rollback()
		raise ApiError("RECEIPT_CREATE_FAILED", "ثبت سند دریافت ناموفق بود", http_status=500)

	_append_receipt_to_invoice(db, invoice, receipt_id)

	tx.status = "succeeded"
	tx.document_id = receipt_id
	tx.external_ref = external_ref
	db.flush()
	return {"transaction_id": tx.id, "status": tx.status, "receipt_document_id": receipt_id}


def maybe_redirect_public_invoice_share_payment_return(
	db: Session,
	*,
	tx_id: int,
	verify_data: Dict[str, Any],
):
	"""
	بازگشت کاربر از درگاه به صفحهٔ عمومی Flutter (به‌جای HTML بک‌اند).
	اگر پایهٔ اپ عمومی تنظیم نشده باشد، None برمی‌گردد تا مسیر قبلی ادامه یابد.
	"""
	from urllib.parse import quote, urlencode

	from fastapi.responses import RedirectResponse

	from app.services.system_settings_service import resolve_public_app_base_url_for_public_links

	tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if not tx or (tx.type or "").strip() != WALLET_TX_TYPE_PUBLIC_INVOICE_SHARE:
		return None
	ex = _parse_extra(tx)
	code = (ex.get("share_link_code") or "").strip()
	if not code:
		return None
	base = (resolve_public_app_base_url_for_public_links(db) or "").strip().rstrip("/")
	if not base:
		return None
	success = bool(verify_data.get("success"))
	ref = verify_data.get("external_ref") or ""
	q = urlencode(
		{
			"payment_status": "success" if success else "failed",
			"tx_id": str(tx_id),
			"ref": str(ref),
		}
	)
	enc = quote(code, safe="")
	return RedirectResponse(url=f"{base}/public/invoice-link/{enc}?{q}", status_code=302)
