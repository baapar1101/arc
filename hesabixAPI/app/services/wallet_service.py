from __future__ import annotations

from typing import Optional, Dict, Any, List
from decimal import Decimal
import json
import structlog

from sqlalchemy.orm import Session
from sqlalchemy import select, and_

from adapters.db.models.wallet import WalletAccount, WalletTransaction, WalletPayout, WalletSetting
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError
from app.services.system_settings_service import get_wallet_settings
from datetime import datetime, date

logger = structlog.get_logger()


def _ensure_wallet_account(db: Session, business_id: int) -> WalletAccount:
	obj = db.execute(
		select(WalletAccount).where(WalletAccount.business_id == int(business_id))
	).scalars().first()
	if obj:
		return obj
	obj = WalletAccount(
		business_id=int(business_id),
		available_balance=Decimal("0"),
		pending_balance=Decimal("0"),
		status="active",
	)
	db.add(obj)
	db.flush()
	return obj


def _get_wallet_account_for_update(db: Session, business_id: int) -> WalletAccount:
	"""
	قفل ردیفی روی حساب کیف‌پول برای جلوگیری از رقابت در به‌روزرسانی مانده‌ها
	"""
	acc = (
		db.query(WalletAccount)
		.filter(WalletAccount.business_id == int(business_id))
		.with_for_update()
		.first()
	)
	if acc:
		return acc
	# اگر وجود ندارد، ایجاد سپس تلاش مجدد برای قفل
	acc = _ensure_wallet_account(db, business_id)
	db.flush()
	try:
		acc = (
			db.query(WalletAccount)
			.filter(WalletAccount.business_id == int(business_id))
			.with_for_update()
			.first()
		) or acc
	except Exception:
		pass
	return acc


def charge_wallet_for_service(
	db: Session,
	business_id: int,
	amount: Decimal,
	*,
	description: str,
	tx_type: str = "internal_service_charge",
	document_id: int | None = None,
	extra_info: Dict[str, Any] | None = None,
	allow_negative_balance: bool = False,
) -> Dict[str, Any]:
	"""
	کسر مبلغ از کیف‌پول برای سرویس‌های داخلی (مثل سناریو درآمدزایی اسناد)
	"""
	amount = Decimal(str(amount or 0))
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ باید بزرگتر از صفر باشد", http_status=400)

	account = _get_wallet_account_for_update(db, business_id)
	available = Decimal(str(account.available_balance or 0))

	if not allow_negative_balance and available < amount:
		raise ApiError("INSUFFICIENT_FUNDS", "موجودی کیف پول کافی نیست", http_status=400)

	account.available_balance = available - amount
	db.flush()

	extra_info_json = json.dumps(extra_info) if extra_info else None

	tx = WalletTransaction(
		business_id=int(business_id),
		type=tx_type,
		status="succeeded",
		amount=amount,
		fee_amount=Decimal("0"),
		description=description,
		document_id=document_id,
		extra_info=extra_info_json,
	)
	db.add(tx)
	db.flush()

	return {
		"transaction_id": tx.id,
		"status": tx.status,
		"available_balance": float(account.available_balance or 0),
	}


def get_wallet_overview(db: Session, business_id: int) -> Dict[str, Any]:
	_ = db.query(Business).filter(Business.id == int(business_id)).first() or None
	if _ is None:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	account = _ensure_wallet_account(db, business_id)
	settings = get_wallet_settings(db)
	return {
		"business_id": business_id,
		"available_balance": float(account.available_balance or 0),
		"pending_balance": float(account.pending_balance or 0),
		"status": account.status,
		"base_currency_code": settings.get("wallet_base_currency_code"),
		"base_currency_id": settings.get("wallet_base_currency_id"),
		"base_currency_title": settings.get("wallet_base_currency_title"),
		"base_currency_symbol": settings.get("wallet_base_currency_symbol"),
	}


def list_wallet_transactions(
	db: Session,
	business_id: int,
	limit: int = 50,
	skip: int = 0,
	from_date: Optional[datetime] = None,
	to_date: Optional[datetime] = None,
) -> List[Dict[str, Any]]:
	q = (
		db.query(WalletTransaction)
		.filter(WalletTransaction.business_id == int(business_id))
		.order_by(WalletTransaction.id.desc())
	)
	if from_date is not None:
		q = q.filter(WalletTransaction.created_at >= from_date)
	if to_date is not None:
		q = q.filter(WalletTransaction.created_at <= to_date)
	items = q.offset(max(0, int(skip))).limit(max(1, min(200, int(limit)))).all()
	return [
		{
			"id": it.id,
			"type": it.type,
			"status": it.status,
			"amount": float(it.amount or 0),
			"fee_amount": float(it.fee_amount or 0) if it.fee_amount is not None else None,
			"description": it.description,
			"external_ref": it.external_ref,
			"document_id": it.document_id,
			"created_at": it.created_at,
			"updated_at": it.updated_at,
		}
		for it in items
	]


def get_wallet_metrics(
	db: Session,
	business_id: int,
	from_date: Optional[datetime] = None,
	to_date: Optional[datetime] = None,
) -> Dict[str, Any]:
	account = _ensure_wallet_account(db, business_id)
	# پایه: مجموع‌ها از WalletTransaction
	q = db.query(WalletTransaction).filter(WalletTransaction.business_id == int(business_id))
	if from_date is not None:
		q = q.filter(WalletTransaction.created_at >= from_date)
	if to_date is not None:
		q = q.filter(WalletTransaction.created_at <= to_date)
	transactions = q.all()
	gross_in = Decimal("0")
	fees_in = Decimal("0")
	gross_out = Decimal("0")
	fees_out = Decimal("0")

	for tx in transactions:
		amt = Decimal(str(tx.amount or 0))
		fee = Decimal(str(tx.fee_amount or 0))
		t = (tx.type or "").lower()
		st = (tx.status or "").lower()
		if st not in ("succeeded", "pending", "approved", "processing"):  # موفق/در جریان را در گزارش لحاظ می‌کنیم
			continue
		if t in ("top_up", "customer_payment"):
			gross_in += amt
			fees_in += fee if fee > 0 else Decimal("0")
		elif t in ("payout_settlement", "refund"):
			gross_out += amt
			fees_out += fee if fee > 0 else Decimal("0")
		# سایر انواع در صورت نیاز بعداً اضافه شوند

	# همچنین از wallet_payouts برای کارمزدهای تسویه استفاده کنیم
	pq = db.query(WalletPayout).filter(WalletPayout.business_id == int(business_id))
	if from_date is not None:
		pq = pq.filter(WalletPayout.created_at >= from_date)
	if to_date is not None:
		pq = pq.filter(WalletPayout.created_at <= to_date)
	for p in pq.all():
		fees_out += Decimal(str(p.fees or 0))

	net_in = gross_in - fees_in
	net_out = gross_out + fees_out  # خروجی خالصی که از کیف‌پول خارج می‌شود

	return {
		"period": {
			"from": from_date,
			"to": to_date,
		},
		"totals": {
			"gross_in": float(gross_in),
			"fees_in": float(fees_in),
			"net_in": float(net_in),
			"gross_out": float(gross_out),
			"fees_out": float(fees_out),
			"net_out": float(net_out),
		},
		"balances": {
			"available": float(account.available_balance or 0),
			"pending": float(account.pending_balance or 0),
		},
	}


def create_payout_request(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	amount = Decimal(str(payload.get("amount") or 0))
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ نامعتبر است", http_status=400)
	bank_account_id = payload.get("bank_account_id")
	if not bank_account_id:
		raise ApiError("BANK_ACCOUNT_REQUIRED", "شناسه حساب بانکی الزامی است", http_status=400)
	bank_acc = db.query(BankAccount).filter(BankAccount.id == int(bank_account_id)).first()
	if not bank_acc:
		raise ApiError("BANK_ACCOUNT_NOT_FOUND", "حساب بانکی یافت نشد", http_status=404)
	if not bank_acc.is_active:
		raise ApiError("BANK_ACCOUNT_INACTIVE", "حساب بانکی غیرفعال است", http_status=400)

	account = _get_wallet_account_for_update(db, business_id)
	available = Decimal(str(account.available_balance or 0))
	if amount > available:
		raise ApiError("INSUFFICIENT_FUNDS", "موجودی کافی نیست", http_status=400)

	# قفل مبلغ: کسر از مانده قابل برداشت
	account.available_balance = available - amount
	db.flush()

	payout = WalletPayout(
		business_id=int(business_id),
		bank_account_id=int(bank_account_id),
		gross_amount=amount,
		fees=Decimal("0"),
		net_amount=amount,
		status="requested",
		schedule_type=str(payload.get("schedule_type") or "manual"),
		external_ref=None,
	)
	db.add(payout)
	db.flush()

	# ثبت تراکنش کنترلی
	tx = WalletTransaction(
		business_id=int(business_id),
		type="payout_request",
		status="pending",
		amount=amount,
		fee_amount=Decimal("0"),
		description=str(payload.get("description") or "درخواست تسویه"),
		external_ref=str(payout.id),
		document_id=None,
	)
	db.add(tx)
	db.flush()

	return {
		"id": payout.id,
		"status": payout.status,
		"gross_amount": float(payout.gross_amount),
		"net_amount": float(payout.net_amount),
		"bank_account_id": payout.bank_account_id,
	}


def approve_payout_request(db: Session, payout_id: int, approver_user_id: int) -> Dict[str, Any]:
	payout = db.query(WalletPayout).filter(WalletPayout.id == int(payout_id)).first()
	if not payout:
		raise ApiError("PAYOUT_NOT_FOUND", "درخواست تسویه یافت نشد", http_status=404)
	if payout.status != "requested":
		raise ApiError("INVALID_STATE", "تنها درخواست‌های در وضعیت requested قابل تایید هستند", http_status=400)
	payout.status = "approved"
	db.flush()
	return {"id": payout.id, "status": payout.status}


def cancel_payout_request(db: Session, payout_id: int, canceller_user_id: int) -> Dict[str, Any]:
	payout = db.query(WalletPayout).filter(WalletPayout.id == int(payout_id)).first()
	if not payout:
		raise ApiError("PAYOUT_NOT_FOUND", "درخواست تسویه یافت نشد", http_status=404)
	if payout.status not in ("requested", "approved"):
		raise ApiError("INVALID_STATE", "فقط درخواست‌های requested/approved قابل لغو هستند", http_status=400)

	# بازگردانی مبلغ به مانده قابل برداشت
	account = _get_wallet_account_for_update(db, payout.business_id)
	account.available_balance = Decimal(str(account.available_balance or 0)) + Decimal(str(payout.gross_amount or 0))
	db.flush()

	payout.status = "canceled"
	db.flush()
	return {"id": payout.id, "status": payout.status}


def settle_payout(db: Session, payout_id: int, user_id: int) -> Dict[str, Any]:
	payout = db.query(WalletPayout).filter(WalletPayout.id == int(payout_id)).first()
	if not payout:
		raise ApiError("PAYOUT_NOT_FOUND", "درخواست تسویه یافت نشد", http_status=404)
	if payout.status not in ("approved", "processing"):
		raise ApiError("INVALID_STATE", "تسویه تنها پس از تایید/در حال پردازش مجاز است", http_status=400)
	# ایجاد سند پرداخت برای خالص دریافتی بانک
	try:
		doc_id = _post_payout_document(
			db,
			business_id=int(payout.business_id),
			user_id=int(user_id),
			net_amount=Decimal(str(payout.net_amount or 0)),
			fee_amount=Decimal(str(payout.fees or 0)),
		)
	except Exception:
		doc_id = None
	payout.status = "settled"
	db.flush()
	# ثبت تراکنش کیف‌پول برای گزارش‌ها
	try:
		tx = WalletTransaction(
			business_id=int(payout.business_id),
			type="payout_settlement",
			status="succeeded",
			amount=Decimal(str(payout.net_amount or 0)),
			fee_amount=Decimal(str(payout.fees or 0)),
			description="تسویه کیف‌پول",
			document_id=doc_id,
		)
		db.add(tx)
		db.flush()
	except Exception:
		pass
	return {"id": payout.id, "status": payout.status, "document_id": doc_id}


def get_business_wallet_settings(db: Session, business_id: int) -> Dict[str, Any]:
	obj = db.query(WalletSetting).filter(WalletSetting.business_id == int(business_id)).first()
	if not obj:
		return {
			"business_id": business_id,
			"mode": "manual",
			"frequency": None,
			"threshold_amount": None,
			"min_reserve": None,
			"default_bank_account_id": None,
		}
	return {
		"business_id": business_id,
		"mode": obj.mode,
		"frequency": obj.frequency,
		"threshold_amount": float(obj.threshold_amount) if obj.threshold_amount is not None else None,
		"min_reserve": float(obj.min_reserve) if obj.min_reserve is not None else None,
		"default_bank_account_id": obj.default_bank_account_id,
	}


def update_business_wallet_settings(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	obj = db.query(WalletSetting).filter(WalletSetting.business_id == int(business_id)).first()
	if not obj:
		obj = WalletSetting(business_id=int(business_id))
		db.add(obj)
	mode = str(payload.get("mode") or obj.mode or "manual")
	frequency = payload.get("frequency") if payload.get("frequency") in (None, "daily", "weekly") else obj.frequency
	def _dec(v): 
		return Decimal(str(v)) if v is not None and str(v).strip() != "" else None
	obj.mode = mode
	obj.frequency = frequency
	obj.threshold_amount = _dec(payload.get("threshold_amount"))
	obj.min_reserve = _dec(payload.get("min_reserve"))
	obj.default_bank_account_id = int(payload.get("default_bank_account_id")) if payload.get("default_bank_account_id") else None
	db.flush()
	return get_business_wallet_settings(db, business_id)


def run_auto_settlement(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
	"""
	منطق ساده: اگر mode=auto و (available - min_reserve) >= threshold آنگاه به حساب پیش‌فرض تسویه کن.
	"""
	settings = get_business_wallet_settings(db, business_id)
	if (settings.get("mode") or "manual") != "auto":
		return {"executed": False, "reason": "AUTO_MODE_DISABLED"}
	threshold = Decimal(str(settings.get("threshold_amount") or 0))
	min_reserve = Decimal(str(settings.get("min_reserve") or 0))
	default_bank_account_id = settings.get("default_bank_account_id")
	if not default_bank_account_id:
		return {"executed": False, "reason": "NO_DEFAULT_BANK_ACCOUNT"}
	account = _get_wallet_account_for_update(db, business_id)
	available = Decimal(str(account.available_balance or 0))
	cand = available - min_reserve
	if cand <= 0 or cand < threshold:
		return {"executed": False, "reason": "THRESHOLD_NOT_MET", "available": float(available)}
	# ایجاد payout و تسویه
	payload = {
		"bank_account_id": int(default_bank_account_id),
		"amount": float(cand),
		"description": "تسویه خودکار",
	}
	pr = create_payout_request(db, business_id, user_id, payload)
	pa = db.query(WalletPayout).filter(WalletPayout.id == int(pr["id"])).first()
	# تایید و تسویه
	approve_payout_request(db, pa.id, user_id)
	result = settle_payout(db, pa.id, user_id)
	return {"executed": True, "payout": result}

def create_top_up_request(db: Session, business_id: int, user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	"""
	ایجاد درخواست افزایش اعتبار (در انتظار تایید درگاه)
	- مانده pending افزایش می‌یابد تا پس از تایید به available منتقل شود
	"""
	logger.info("create_top_up_request_start", business_id=business_id, user_id=user_id, amount=payload.get("amount"))
	amount = Decimal(str(payload.get("amount") or 0))
	if amount <= 0:
		logger.error("create_top_up_request_invalid_amount", amount=float(amount))
		raise ApiError("INVALID_AMOUNT", "مبلغ نامعتبر است", http_status=400)
	
	gateway_id = payload.get("gateway_id")
	source = payload.get("source", "app")  # پیش‌فرض: app
	# اعتبارسنجی gateway_id در صورت ارسال
	if gateway_id:
		try:
			from adapters.db.models.payment_gateway import PaymentGateway
			gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first()
			if not gw:
				logger.error("create_top_up_request_gateway_not_found", gateway_id=gateway_id)
				raise ApiError("GATEWAY_NOT_FOUND", "درگاه پرداخت یافت نشد", http_status=404)
			if not gw.is_active:
				logger.error("create_top_up_request_gateway_inactive", gateway_id=gateway_id)
				raise ApiError("GATEWAY_DISABLED", "درگاه پرداخت غیرفعال است", http_status=400)
		except ApiError:
			raise
		except Exception as ex:
			logger.error("create_top_up_request_gateway_check_failed", gateway_id=gateway_id, error=str(ex))
			raise ApiError("GATEWAY_CHECK_FAILED", "خطا در بررسی درگاه پرداخت", http_status=500)
	
	# اگر gateway_id نداریم، فقط تراکنش ایجاد می‌کنیم بدون افزایش pending
	# (برای پرداخت دستی یا روش‌های دیگر)
	account = _get_wallet_account_for_update(db, business_id)
	
	# بارگذاری اطلاعات کاربر برای ارسال به درگاه پرداخت
	from adapters.db.models.user import User
	user = db.query(User).filter(User.id == int(user_id)).first()
	
	# ذخیره user_id و اطلاعات کاربر در extra_info برای استفاده بعدی
	extra_info_dict = {"created_by_user_id": user_id, "source": source}
	
	if user:
		# نام کامل کاربر (ترکیب first_name و last_name یا mobile)
		user_full_name = None
		if user.first_name or user.last_name:
			user_full_name = f"{user.first_name or ''} {user.last_name or ''}".strip()
		elif user.mobile:
			user_full_name = user.mobile
		
		extra_info_dict["user_name"] = user_full_name
		extra_info_dict["user_email"] = user.email
		extra_info_dict["user_mobile"] = user.mobile
	
	extra_info_json = json.dumps(extra_info_dict, ensure_ascii=False)
	
	tx = WalletTransaction(
		business_id=int(business_id),
		type="top_up",
		status="pending",
		amount=amount,
		fee_amount=Decimal("0"),
		description=str(payload.get("description") or "افزایش اعتبار"),
		external_ref=None,
		document_id=None,
		extra_info=extra_info_json,
	)
	db.add(tx)
	db.flush()
	
	# تولید لینک درگاه پرداخت (در صورت ارسال gateway_id)
	payment_url = None
	if gateway_id:
		# فقط در صورت وجود gateway_id، pending_balance را افزایش می‌دهیم
		account.pending_balance = Decimal(str(account.pending_balance or 0)) + amount
		db.flush()
		logger.info("create_top_up_request_pending_increased", tx_id=tx.id, amount=float(amount), new_pending=float(account.pending_balance))
		
		try:
			from app.services.payment_service import initiate_payment
			init_res = initiate_payment(
				db=db,
				business_id=int(business_id),
				tx_id=int(tx.id),
				amount=float(amount),
				gateway_id=int(gateway_id),
			)
			payment_url = init_res.payment_url
			logger.info("create_top_up_request_payment_url_created", tx_id=tx.id, payment_url=payment_url)
		except Exception as ex:
			# اگر ایجاد لینک شکست بخورد، مانده pending به حالت قبل برگردد و تراکنش failed شود
			logger.error("create_top_up_request_gateway_init_failed", tx_id=tx.id, error=str(ex), exc_info=True)
			try:
				current_pending = Decimal(str(account.pending_balance or 0))
				if current_pending >= amount:
					account.pending_balance = current_pending - amount
				else:
					account.pending_balance = Decimal("0")
				tx.status = "failed"
				db.flush()
				logger.info("create_top_up_request_rollback_completed", tx_id=tx.id, new_pending=float(account.pending_balance))
			except Exception as rollback_ex:
				logger.error("create_top_up_request_rollback_failed", tx_id=tx.id, error=str(rollback_ex), exc_info=True)
			raise ApiError("GATEWAY_INIT_FAILED", f"خطا در ایجاد لینک پرداخت: {str(ex)}", http_status=502)
	else:
		logger.info("create_top_up_request_no_gateway", tx_id=tx.id, message="تراکنش بدون درگاه ایجاد شد")
	
	logger.info("create_top_up_request_completed", tx_id=tx.id, status=tx.status, has_payment_url=payment_url is not None)
	return {"transaction_id": tx.id, "status": tx.status, **({"payment_url": payment_url} if payment_url else {})}


def confirm_top_up(db: Session, tx_id: int, success: bool, external_ref: str | None = None, user_id: int | None = None) -> Dict[str, Any]:
	"""
	تایید/لغو top-up از وبهوک درگاه
	- در موفقیت: انتقال از pending به available
	- در عدم موفقیت: کاهش از pending
	"""
	logger.info("confirm_top_up_start", tx_id=tx_id, success=success, external_ref=external_ref, user_id=user_id)
	tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if not tx or tx.type != "top_up":
		logger.error("confirm_top_up_tx_not_found", tx_id=tx_id)
		raise ApiError("TX_NOT_FOUND", "تراکنش افزایش اعتبار یافت نشد", http_status=404)
	
	# بررسی تعلق تراکنش به کسب‌وکار (امنیتی)
	if tx.business_id is None:
		logger.error("confirm_top_up_no_business_id", tx_id=tx_id)
		raise ApiError("INVALID_TX", "تراکنش به کسب‌وکار مرتبط نیست", http_status=400)
	
	# Idempotency guard: if already finalized, do nothing
	if (tx.status or "").lower() in ("succeeded", "failed"):
		logger.info("confirm_top_up_already_finalized", tx_id=tx_id, status=tx.status)
		tx.external_ref = external_ref or tx.external_ref
		db.flush()
		return {"transaction_id": tx.id, "status": tx.status}
	
	account = _get_wallet_account_for_update(db, tx.business_id)
	if success:
		# move pending -> available
		gross = Decimal(str(tx.amount or 0))
		fee = Decimal(str(tx.fee_amount or 0))
		if fee < 0:
			fee = Decimal("0")
		if fee > gross:
			fee = gross
		net = gross - fee
		# Prevent negative pending due to duplicate webhook/callback
		current_pending = Decimal(str(account.pending_balance or 0))
		if current_pending < gross:
			logger.warning("confirm_top_up_insufficient_pending", tx_id=tx_id, current_pending=float(current_pending), gross=float(gross))
			# اگر pending کمتر از gross باشد، فقط همان مقدار موجود را کم می‌کنیم
			account.pending_balance = Decimal("0")
		else:
			account.pending_balance = current_pending - gross
		account.available_balance = Decimal(str(account.available_balance or 0)) + net
		tx.status = "succeeded"
		logger.info("confirm_top_up_success", tx_id=tx_id, gross=float(gross), fee=float(fee), net=float(net), new_available=float(account.available_balance))
		# create accounting document
		try:
			# استفاده از user_id از تراکنش یا پارامتر ورودی
			doc_user_id = user_id if user_id and user_id > 0 else None
			# اگر user_id نداریم، از extra_info تراکنش تلاش می‌کنیم
			if not doc_user_id:
				try:
					extra = json.loads(tx.extra_info or "{}") if tx.extra_info else {}
					doc_user_id = extra.get("created_by_user_id")
				except Exception:
					pass
			# در نهایت اگر هنوز نداریم، از 0 استفاده می‌کنیم (سیستم)
			doc_user_id = doc_user_id if doc_user_id and doc_user_id > 0 else 0
			doc_id = _post_topup_document(db, tx.business_id, user_id=doc_user_id, amount=gross, fee_amount=fee)
			tx.document_id = int(doc_id)
			logger.info("confirm_top_up_document_created", tx_id=tx_id, document_id=doc_id)
		except Exception as ex:
			# اگر سند ایجاد نشد، تراکنش مالی معتبر است اما سند ندارد
			logger.warning("confirm_top_up_document_failed", tx_id=tx_id, error=str(ex), exc_info=True)
	else:
		# rollback pending
		current_pending = Decimal(str(account.pending_balance or 0))
		dec_amt = Decimal(str(tx.amount or 0))
		if current_pending < dec_amt:
			logger.warning("confirm_top_up_insufficient_pending_rollback", tx_id=tx_id, current_pending=float(current_pending), dec_amt=float(dec_amt))
			account.pending_balance = Decimal("0")
		else:
			account.pending_balance = current_pending - dec_amt
		tx.status = "failed"
		logger.info("confirm_top_up_failed", tx_id=tx_id, new_pending=float(account.pending_balance))
	tx.external_ref = external_ref
	db.flush()
	logger.info("confirm_top_up_completed", tx_id=tx_id, status=tx.status)
	return {"transaction_id": tx.id, "status": tx.status}


def refund_transaction(db: Session, tx_id: int, amount: Decimal | None = None, reason: str | None = None) -> Dict[str, Any]:
	"""
	استرداد تراکنش موفق (بازگشت وجه از کیف‌پول)
	- کاهش از available به میزان مبلغ استرداد
	"""
	src = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	if not src or src.status != "succeeded":
		raise ApiError("TX_NOT_REFUNDABLE", "تراکنش موفق برای استرداد پیدا نشد", http_status=400)
	refund_amount = Decimal(str(amount if amount is not None else src.amount or 0))
	if refund_amount <= 0 or refund_amount > Decimal(str(src.amount or 0)):
		raise ApiError("INVALID_REFUND_AMOUNT", "مبلغ استرداد نامعتبر است", http_status=400)
	account = _ensure_wallet_account(db, src.business_id)
	available = Decimal(str(account.available_balance or 0))
	if refund_amount > available:
		raise ApiError("INSUFFICIENT_FUNDS", "موجودی کافی برای استرداد نیست", http_status=400)
	account.available_balance = available - refund_amount
	db.flush()
	tx = WalletTransaction(
		business_id=int(src.business_id),
		type="refund",
		status="succeeded",
		amount=refund_amount,
		description=reason or f"استرداد تراکنش {src.id}",
		external_ref=None,
		document_id=None,
	)
	db.add(tx)
	db.flush()
	return {"refund_transaction_id": tx.id, "status": tx.status}

def _parse_iso_date_only(dt: str | datetime | date) -> date:
	try:
		if isinstance(dt, date) and not isinstance(dt, datetime):
			return dt
		if isinstance(dt, datetime):
			return dt.date()
		return datetime.fromisoformat(str(dt)).date()
	except Exception:
		return datetime.utcnow().date()


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	fy = (
		db.query(FiscalYear)
		.filter(
			and_(
				FiscalYear.business_id == int(business_id),
				FiscalYear.is_last == True,  # noqa: E712
			)
		)
		.first()
	)
	if not fy:
		raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی جاری یافت نشد", http_status=400)
	return fy


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
	acc = db.query(Account).filter(
		and_(Account.business_id == None, Account.code == str(account_code))  # noqa: E711
	).first()
	if not acc:
		raise ApiError("ACCOUNT_NOT_FOUND", f"Account with code {account_code} not found", http_status=500)
	return acc


def _resolve_wallet_currency_id(db: Session) -> int:
	settings = get_wallet_settings(db)
	cid = settings.get("wallet_base_currency_id")
	if cid:
		return int(cid)
	# fallback: resolve by code IRR
	from adapters.db.models.currency import Currency
	cur = db.query(Currency).filter(Currency.code == "IRR").first()
	if not cur:
		raise ApiError("CURRENCY_NOT_FOUND", "ارز پایه کیف‌پول یافت نشد", http_status=400)
	return int(cur.id)


def _create_simple_document(
	db: Session,
	business_id: int,
	user_id: int,
	document_type: str,  # 'receipt' | 'payment'
	currency_id: int,
	document_date: date,
	description: str | None,
	accounting_lines: list[dict],
) -> Document:
	fiscal_year = _get_current_fiscal_year(db, business_id)
	today = _parse_iso_date_only(document_date)
	prefix = f"{'RC' if document_type == 'receipt' else 'PY'}-{today.strftime('%Y%m%d')}"
	last_doc = (
		db.query(Document)
		.filter(
			and_(
				Document.business_id == business_id,
				Document.code.like(f"{prefix}-%"),
			)
		)
		.order_by(Document.code.desc())
		.first()
	)
	if last_doc:
		try:
			last_num = int(str(last_doc.code).split("-")[-1])
			next_num = last_num + 1
		except Exception:
			next_num = 1
	else:
		next_num = 1
	doc_code = f"{prefix}-{next_num:04d}"

	document = Document(
		business_id=business_id,
		fiscal_year_id=fiscal_year.id,
		code=doc_code,
		document_type=document_type,
		document_date=today,
		currency_id=int(currency_id),
		created_by_user_id=user_id,
		registered_at=datetime.utcnow(),
		is_proforma=False,
		description=description,
		extra_info={"source": "wallet"},
	)
	db.add(document)
	db.flush()

	for ln in accounting_lines:
		db.add(DocumentLine(
			document_id=document.id,
			account_id=int(ln["account_id"]),
			debit=Decimal(str(ln.get("debit", 0) or 0)),
			credit=Decimal(str(ln.get("credit", 0) or 0)),
			description=ln.get("description"),
		))
	db.flush()
	return document


def _post_topup_document(db: Session, business_id: int, user_id: int, amount: Decimal, fee_amount: Decimal | None = None, doc_date: date | None = None) -> int:
	currency_id = _resolve_wallet_currency_id(db)
	wallet_acc = _get_fixed_account_by_code(db, "10205")  # حساب کیف پول
	bank_acc = _get_fixed_account_by_code(db, "10203")
	fee_amt = Decimal(str(fee_amount or 0))
	net = amount - fee_amt if amount >= fee_amt else Decimal("0")
	lines = [
		# Receipt pattern with commission (per existing commission logic):
		# Dr 10205 (wallet) = net, Dr 70902 (fee expense) = fee, Cr 10203 (bank) = gross
		{"account_id": wallet_acc.id, "debit": net, "credit": 0, "description": "افزایش اعتبار (خالص)"},
	]
	if fee_amt > 0:
		commission_expense = _get_fixed_account_by_code(db, "70902")
		lines.append({"account_id": commission_expense.id, "debit": fee_amt, "credit": 0, "description": "کارمزد درگاه"})
	lines.append({"account_id": bank_acc.id, "debit": 0, "credit": amount, "description": "واریز از درگاه/بانک (ناخالص)"})
	document = _create_simple_document(
		db=db,
		business_id=business_id,
		user_id=user_id,
		document_type="receipt",
		currency_id=currency_id,
		document_date=doc_date or datetime.utcnow().date(),
		description="افزایش اعتبار کیف‌پول",
		accounting_lines=lines,
	)
	return int(document.id)


def _post_payout_document(db: Session, business_id: int, user_id: int, net_amount: Decimal, fee_amount: Decimal | None = None, doc_date: date | None = None) -> int:
	currency_id = _resolve_wallet_currency_id(db)
	wallet_acc = _get_fixed_account_by_code(db, "10205")  # حساب کیف پول
	bank_acc = _get_fixed_account_by_code(db, "10203")
	fee_amt = Decimal(str(fee_amount or 0))
	# Per existing commission logic for Payment: Dr bank = fee, Cr 70902 = fee
	lines = [
		{"account_id": bank_acc.id, "debit": net_amount, "credit": 0, "description": "وصول تسویه کیف‌پول (خالص)"},
		{"account_id": wallet_acc.id, "debit": 0, "credit": net_amount, "description": "انتقال از کیف‌پول"},
	]
	if fee_amt > 0:
		commission_expense = _get_fixed_account_by_code(db, "70902")
		lines.append({"account_id": bank_acc.id, "debit": fee_amt, "credit": 0, "description": "کارمزد تسویه (الگوی پرداخت)"})
		lines.append({"account_id": commission_expense.id, "debit": 0, "credit": fee_amt, "description": "کارمزد خدمات بانکی"})
	document = _create_simple_document(
		db=db,
		business_id=business_id,
		user_id=user_id,
		document_type="payment",
		currency_id=currency_id,
		document_date=doc_date or datetime.utcnow().date(),
		description="تسویه کیف‌پول به حساب بانکی",
		accounting_lines=lines,
	)
	return int(document.id)


def _post_gift_credit_document(db: Session, business_id: int, user_id: int, amount: Decimal, description: str | None = None, doc_date: date | None = None) -> int:
	"""
	ایجاد سند حسابداری برای اعتبارات هدیه
	Dr 10205 (wallet) = amount
	Cr 60205 (gift credit income) = amount
	"""
	currency_id = _resolve_wallet_currency_id(db)
	wallet_acc = _get_fixed_account_by_code(db, "10205")  # حساب کیف پول
	gift_income_acc = _get_fixed_account_by_code(db, "60205")
	
	lines = [
		{"account_id": wallet_acc.id, "debit": amount, "credit": 0, "description": "افزایش اعتبار هدیه"},
		{"account_id": gift_income_acc.id, "debit": 0, "credit": amount, "description": description or "اعتبارات هدیه از مدیر سیستم"},
	]
	
	document = _create_simple_document(
		db=db,
		business_id=business_id,
		user_id=user_id,
		document_type="receipt",
		currency_id=currency_id,
		document_date=doc_date or datetime.utcnow().date(),
		description=description or "افزایش اعتبار هدیه توسط مدیر سیستم",
		accounting_lines=lines,
	)
	return int(document.id)


def _ensure_zohal_expense_account(db: Session) -> Account:
	"""
	بررسی و ایجاد/به‌روزرسانی حساب هزینه سرویس‌های استعلامات (70509)
	این تابع اطمینان می‌دهد که حساب 70509 با نام صحیح "هزینه سرویس‌های استعلامات" وجود دارد
	حساب در گروه هزینه‌های عمومی (705) قرار دارد که مناسب هزینه‌های عملیاتی است
	"""
	account = db.query(Account).filter(
		and_(
			Account.code == "70509",
			Account.business_id.is_(None)
		)
	).first()
	
	expected_name = "هزینه سرویس‌های استعلامات"
	
	if not account:
		# دریافت حساب والد (705 - هزینه‌های عمومی)
		parent_account = _get_fixed_account_by_code(db, "705")
		
		# ایجاد حساب هزینه سرویس‌های استعلامات
		account = Account(
			name=expected_name,
			code="70509",
			account_type="accounting_document",
			business_id=None,  # حساب عمومی
			parent_id=parent_account.id if parent_account else None
		)
		db.add(account)
		db.flush()
	else:
		# بررسی و به‌روزرسانی نام حساب در صورت نیاز
		if account.name != expected_name:
			import logging
			logger = logging.getLogger(__name__)
			logger.info(f"به‌روزرسانی نام حساب 70509 از '{account.name}' به '{expected_name}'")
			account.name = expected_name
			# اطمینان از نوع حساب
			if account.account_type != "accounting_document":
				account.account_type = "accounting_document"
				db.flush()
	
	return account


def charge_wallet_for_zohal_service(
	db: Session,
	business_id: int,
	user_id: int,
	amount: Decimal,
	service_id: int,
	service_name: str,
	description: str | None = None,
) -> Dict[str, Any]:
	"""
	کسر مبلغ از کیف‌پول برای سرویس‌های زحل و ایجاد سند حسابداری
	"""
	amount = Decimal(str(amount or 0))
	if amount <= 0:
		raise ApiError("INVALID_AMOUNT", "مبلغ باید بزرگتر از صفر باشد", http_status=400)
	
	# بررسی موجودی
	account = _get_wallet_account_for_update(db, business_id)
	available = Decimal(str(account.available_balance or 0))
	
	if available < amount:
		raise ApiError("INSUFFICIENT_FUNDS", "موجودی کیف پول کافی نیست", http_status=400)
	
	# کسر از موجودی
	account.available_balance = available - amount
	db.flush()
	
	# ایجاد سند حسابداری
	currency_id = _resolve_wallet_currency_id(db)
	wallet_acc = _get_fixed_account_by_code(db, "10205")  # حساب کیف پول
	expense_acc = _ensure_zohal_expense_account(db)  # حساب هزینه سرویس‌های استعلامات
	
	lines = [
		{"account_id": expense_acc.id, "debit": amount, "credit": 0, "description": description or f"هزینه سرویس {service_name}"},
		{"account_id": wallet_acc.id, "debit": 0, "credit": amount, "description": f"کسر از کیف پول برای سرویس استعلامات"},
	]
	
	document = _create_simple_document(
		db=db,
		business_id=business_id,
		user_id=user_id,
		document_type="payment",
		currency_id=currency_id,
		document_date=datetime.utcnow().date(),
		description=description or f"هزینه سرویس {service_name}",
		accounting_lines=lines,
	)
	
	# ثبت تراکنش کیف پول
	extra_info = {
		"source": "zohal_service",
		"service_id": service_id,
		"service_name": service_name,
	}
	extra_info_json = json.dumps(extra_info)
	
	tx = WalletTransaction(
		business_id=int(business_id),
		type="zohal_service_charge",
		status="succeeded",
		amount=amount,
		fee_amount=Decimal("0"),
		description=description or f"هزینه سرویس {service_name}",
		document_id=document.id,
		extra_info=extra_info_json,
	)
	db.add(tx)
	db.flush()
	
	return {
		"wallet_transaction_id": tx.id,
		"document_id": document.id,
		"available_balance": float(account.available_balance or 0),
	}


def add_gift_balance_admin(
	db: Session,
	business_id: int,
	user_id: int,
	amount: Decimal,
	description: str | None = None,
	reason: str | None = None,
) -> Dict[str, Any]:
	"""
	افزودن موجودی هدیه به کیف‌پول کسب‌وکار توسط مدیر سیستم
	
	Args:
		db: Database session
		business_id: شناسه کسب‌وکار
		user_id: شناسه کاربر مدیر سیستم
		amount: مبلغ هدیه
		description: توضیحات (اختیاری)
		reason: دلیل (اختیاری)
	
	Returns:
		اطلاعات کیف‌پول و تراکنش ایجاد شده
	"""
	logger.info(
		"add_gift_balance_admin_start",
		business_id=business_id,
		user_id=user_id,
		amount=float(amount),
		description=description,
		reason=reason
	)
	
	# بررسی کسب‌وکار
	business = db.query(Business).filter(Business.id == int(business_id)).first()
	if not business:
		logger.error("add_gift_balance_admin_business_not_found", business_id=business_id)
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	
	logger.debug("add_gift_balance_admin_business_found", business_id=business_id, business_name=business.name)
	
	# اعتبارسنجی مبلغ
	amount = Decimal(str(amount))
	if amount <= 0:
		logger.error("add_gift_balance_admin_invalid_amount", amount=float(amount))
		raise ApiError("INVALID_AMOUNT", "مبلغ باید بزرگتر از صفر باشد", http_status=400)
	
	logger.debug("add_gift_balance_admin_amount_validated", amount=float(amount))
	
	# دریافت یا ایجاد حساب کیف‌پول
	logger.debug("add_gift_balance_admin_getting_wallet_account", business_id=business_id)
	account = _get_wallet_account_for_update(db, business_id)
	old_balance = float(account.available_balance or 0)
	logger.debug(
		"add_gift_balance_admin_wallet_account_found",
		account_id=account.id,
		old_balance=old_balance,
		old_pending=float(account.pending_balance or 0)
	)
	
	# افزایش موجودی قابل استفاده
	account.available_balance = Decimal(str(account.available_balance or 0)) + amount
	new_balance = float(account.available_balance)
	logger.debug(
		"add_gift_balance_admin_balance_updated",
		old_balance=old_balance,
		new_balance=new_balance,
		delta=float(amount)
	)
	
	try:
		db.flush()
		logger.debug("add_gift_balance_admin_wallet_balance_flushed")
	except Exception as e:
		logger.error("add_gift_balance_admin_flush_error", error=str(e), error_type=type(e).__name__, exc_info=True)
		raise
	
	# ثبت تراکنش
	desc_text = description or "افزایش اعتبار هدیه توسط مدیر سیستم"
	if reason:
		desc_text = f"{desc_text} (دلیل: {reason})"
	
	# تبدیل extra_info به JSON string
	extra_info_dict = {"added_by": user_id}
	if reason:
		extra_info_dict["reason"] = reason
	extra_info_json = json.dumps(extra_info_dict) if extra_info_dict else None
	
	logger.debug(
		"add_gift_balance_admin_creating_transaction",
		description=desc_text,
		extra_info=extra_info_json
	)
	
	tx = WalletTransaction(
		business_id=int(business_id),
		type="gift_credit",
		status="succeeded",
		amount=amount,
		fee_amount=Decimal("0"),
		description=desc_text,
		external_ref=None,
		document_id=None,
		extra_info=extra_info_json,
	)
	db.add(tx)
	
	try:
		db.flush()
		logger.info(
			"add_gift_balance_admin_transaction_created",
			transaction_id=tx.id,
			business_id=business_id,
			amount=float(amount)
		)
	except Exception as e:
		logger.error("add_gift_balance_admin_transaction_flush_error", error=str(e), error_type=type(e).__name__, exc_info=True)
		raise
	
	# ایجاد سند حسابداری
	logger.debug("add_gift_balance_admin_creating_document", business_id=business_id)
	try:
		doc_id = _post_gift_credit_document(db, business_id, user_id, amount, desc_text)
		tx.document_id = int(doc_id)
		db.flush()
		logger.info(
			"add_gift_balance_admin_document_created",
			document_id=doc_id,
			transaction_id=tx.id
		)
	except Exception as e:
		# اگر سند ایجاد نشد، تراکنش مالی معتبر است اما سند ندارد
		logger.warning(
			"add_gift_balance_admin_document_creation_failed",
			error=str(e),
			error_type=type(e).__name__,
			business_id=business_id,
			amount=float(amount),
			transaction_id=tx.id,
			exc_info=True
		)
	
	# Commit تغییرات (اگر session خودمان commit می‌کند)
	try:
		# بررسی اینکه آیا session در حالت autocommit است
		if db.is_active:
			logger.debug("add_gift_balance_admin_session_is_active", in_transaction=db.in_transaction())
		else:
			logger.warning("add_gift_balance_admin_session_not_active")
	except Exception:
		pass
	
	# بازگشت اطلاعات
	result = {
		"transaction_id": tx.id,
		"business_id": business_id,
		"amount": float(amount),
		"available_balance": float(account.available_balance),
		"pending_balance": float(account.pending_balance or 0),
		"status": account.status,
		"document_id": tx.document_id,
	}
	
	logger.info(
		"add_gift_balance_admin_completed",
		transaction_id=tx.id,
		business_id=business_id,
		amount=float(amount),
		final_balance=result["available_balance"],
		document_id=tx.document_id
	)
	
	return result
