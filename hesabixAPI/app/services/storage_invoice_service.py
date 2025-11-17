"""
سرویس مدیریت صورتحساب‌های ذخیره‌سازی
"""

from __future__ import annotations

import logging
from typing import Dict, Any, List, Optional
from datetime import datetime
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
from sqlalchemy.exc import PendingRollbackError

from adapters.db.models.storage_plan import StorageInvoice, BusinessStorageSubscription, StoragePlan
from adapters.db.models.wallet import WalletAccount, WalletTransaction
from adapters.db.models.business import Business
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.fiscal_year import FiscalYear
from app.core.responses import ApiError
from app.services.storage_subscription_service import calculate_total_storage_limit, get_active_subscriptions

logger = logging.getLogger(__name__)


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
	"""دریافت حساب عمومی بر اساس کد"""
	logger.debug(f"دریافت حساب با کد: {account_code}")
	account = db.query(Account).filter(
		and_(
			Account.code == account_code,
			Account.business_id.is_(None)
		)
	).first()
	if not account:
		logger.error(f"حساب با کد {account_code} یافت نشد")
		raise ApiError("ACCOUNT_NOT_FOUND", f"Account with code {account_code} not found", http_status=500)
	logger.debug(f"حساب یافت شد: {account.id} - {account.name}")
	return account


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
	"""دریافت سال مالی جاری کسب‌وکار"""
	from datetime import date
	today = date.today()
	logger.debug(f"دریافت سال مالی جاری برای کسب‌وکار {business_id}")
	fy = db.query(FiscalYear).filter(
		and_(
			FiscalYear.business_id == business_id,
			FiscalYear.start_date <= today,
			FiscalYear.end_date >= today
		)
	).first()
	if not fy:
		logger.error(f"سال مالی جاری برای کسب‌وکار {business_id} یافت نشد")
		raise ApiError("FISCAL_YEAR_NOT_FOUND", "سال مالی جاری یافت نشد", http_status=404)
	logger.debug(f"سال مالی یافت شد: {fy.id} - از {fy.start_date} تا {fy.end_date}")
	return fy


def _build_invoice_code(db: Session) -> str:
	"""تولید کد صورتحساب: STG-YYYYMMDD-NNNN"""
	from datetime import date
	today = date.today()
	base = f"STG-{today.strftime('%Y%m%d')}"
	
	last_inv = (
		db.query(StorageInvoice)
		.filter(StorageInvoice.code.like(f"{base}-%"))
		.order_by(StorageInvoice.code.desc())
		.first()
	)
	
	if last_inv:
		try:
			last_num = int(last_inv.code.split("-")[-1])
			next_num = last_num + 1
		except Exception:
			next_num = 1
	else:
		next_num = 1
	
	return f"{base}-{next_num:04d}"


def _create_storage_invoice_document(
	db: Session,
	business_id: int,
	user_id: int,
	invoice: StorageInvoice,
	amount: Decimal,
) -> int:
	"""ایجاد سند حسابداری برای صورتحساب ذخیره‌سازی"""
	from datetime import date
	
	logger.info(f"شروع ایجاد سند حسابداری برای صورتحساب {invoice.id} (کد: {invoice.code}) - مبلغ: {amount}")
	
	try:
		# دریافت حساب‌ها
		logger.debug("دریافت حساب هزینه (70401)")
		expense_account = _get_fixed_account_by_code(db, "70401")  # خرید خدمات
		logger.debug("دریافت حساب کیف پول (10205)")
		wallet_account = _get_fixed_account_by_code(db, "10205")  # کیف پول
		
		# دریافت سال مالی
		logger.debug(f"دریافت سال مالی برای کسب‌وکار {business_id}")
		fiscal_year = _get_current_fiscal_year(db, business_id)
		
		# تولید کد سند
		doc_date = invoice.issued_at.date() if invoice.issued_at else date.today()
		prefix = f"PY-{doc_date.strftime('%Y%m%d')}"
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
		logger.debug(f"کد سند تولید شد: {doc_code}")
		
		# تعیین توضیحات بر اساس نوع صورتحساب
		if invoice.invoice_type == "subscription":
			desc = f"هزینه اشتراک ذخیره‌سازی {invoice.code}"
		elif invoice.invoice_type == "over_usage":
			desc = f"هزینه استفاده اضافی ذخیره‌سازی {invoice.code}"
		elif invoice.invoice_type == "renewal":
			desc = f"هزینه تمدید اشتراک ذخیره‌سازی {invoice.code}"
		else:
			desc = f"هزینه ذخیره‌سازی {invoice.code}"
		
		# ایجاد سند
		logger.debug(f"ایجاد Document: کد={doc_code}, نوع=payment, تاریخ={doc_date}")
		document = Document(
			business_id=business_id,
			fiscal_year_id=fiscal_year.id,
			code=doc_code,
			document_type="payment",
			document_date=doc_date,
			currency_id=invoice.currency_id,
			created_by_user_id=user_id,
			registered_at=datetime.utcnow(),
			is_proforma=False,
			description=f"پرداخت {desc}",
			extra_info={"source": "storage_invoice", "storage_invoice_id": invoice.id},
		)
		db.add(document)
		db.flush()
		logger.debug(f"Document ایجاد شد: id={document.id}")
		
		# ایجاد ردیف‌های حسابداری
		logger.debug(f"ایجاد ردیف بدهکار: حساب {expense_account.id} ({expense_account.code}) - مبلغ: {amount}")
		# ردیف 1: بدهکار - هزینه ذخیره‌سازی
		db.add(DocumentLine(
			document_id=document.id,
			account_id=expense_account.id,
			debit=amount,
			credit=Decimal("0"),
			description=desc,
		))
		
		logger.debug(f"ایجاد ردیف بستانکار: حساب {wallet_account.id} ({wallet_account.code}) - مبلغ: {amount}")
		# ردیف 2: بستانکار - کیف پول
		db.add(DocumentLine(
			document_id=document.id,
			account_id=wallet_account.id,
			debit=Decimal("0"),
			credit=amount,
			description=f"پرداخت از کیف پول",
		))
		
		db.flush()
		logger.info(f"سند حسابداری با موفقیت ایجاد شد: {document.id} (کد: {document.code})")
		return int(document.id)
	except Exception as e:
		logger.error(f"خطا در ایجاد سند حسابداری برای صورتحساب {invoice.id}: {type(e).__name__}: {e}", exc_info=True)
		raise


def create_subscription_invoice(
	db: Session,
	business_id: int,
	subscription_id: int,
	user_id: int,
) -> Dict[str, Any]:
	"""ایجاد صورتحساب برای اشتراک جدید"""
	logger.info(f"شروع ایجاد صورتحساب برای اشتراک {subscription_id} کسب‌وکار {business_id}")
	
	subscription = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.id == subscription_id,
			BusinessStorageSubscription.business_id == business_id
		)
	).first()
	
	if not subscription:
		logger.error(f"اشتراک {subscription_id} برای کسب‌وکار {business_id} یافت نشد")
		raise ApiError("SUBSCRIPTION_NOT_FOUND", "اشتراک یافت نشد", http_status=404)
	
	plan = subscription.plan
	if not plan:
		logger.error(f"پلن برای اشتراک {subscription_id} یافت نشد")
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
	
	logger.debug(f"پلن یافت شد: id={plan.id}, name={plan.name}, is_free={plan.is_free}, price={plan.price}")
	
	# ایجاد صورتحساب
	invoice_code = _build_invoice_code(db)
	logger.debug(f"کد صورتحساب تولید شد: {invoice_code}")
	invoice = StorageInvoice(
		business_id=business_id,
		subscription_id=subscription_id,
		code=invoice_code,
		invoice_type="subscription",
		total=float(plan.price),
		currency_id=plan.currency_id,
		status="issued",
		issued_at=datetime.utcnow(),
		extra_info={
			"plan_id": plan.id,
			"plan_name": plan.name,
			"storage_limit_gb": float(plan.storage_limit_gb),
			"period": plan.period,
		}
	)
	
	db.add(invoice)
	db.flush()
	db.refresh(invoice)
	
	# اگر پلن رایگان است، صورتحساب را به صورت خودکار پرداخت کن
	if plan.is_free or float(plan.price) == 0:
		logger.info(f"پلن رایگان است (is_free={plan.is_free}, price={plan.price}). شروع پرداخت خودکار صورتحساب {invoice.id}")
		try:
			# پرداخت خودکار صورتحساب رایگان (بدون نیاز به موجودی کیف پول)
			result = pay_storage_invoice_from_wallet(db, business_id, invoice.id, user_id)
			# refresh برای دریافت وضعیت به‌روز شده
			db.refresh(invoice)
			logger.info(f"پرداخت خودکار صورتحساب {invoice.id} با موفقیت انجام شد. وضعیت: {invoice.status}, نتیجه: {result}")
		except Exception as e:
			# اگر پرداخت خودکار ناموفق بود، صورتحساب به صورت issued باقی می‌ماند
			logger.error(f"خطا در پرداخت خودکار صورتحساب رایگان {invoice.id} (کد: {invoice.code}): {type(e).__name__}: {e}", exc_info=True)
			pass
	else:
		logger.info(f"پلن پولی است (price={plan.price}). صورتحساب {invoice.id} منتظر پرداخت دستی است")
	
	return get_storage_invoice(db, business_id, invoice.id)


def create_over_usage_invoice(
	db: Session,
	business_id: int,
	over_usage_gb: float,
	file_size_bytes: Optional[int] = None,
) -> Dict[str, Any]:
	"""ایجاد صورتحساب فوری برای استفاده اضافی"""
	if over_usage_gb <= 0:
		raise ApiError("VALIDATION_ERROR", "حجم اضافی باید بیشتر از صفر باشد", http_status=422)
	
	# دریافت پلن‌های فعال برای محاسبه قیمت
	active_subs = get_active_subscriptions(db, business_id)
	if not active_subs:
		raise ApiError("NO_ACTIVE_SUBSCRIPTION", "اشتراک فعالی وجود ندارد", http_status=400)
	
	# استفاده از price_per_gb اولین پلن فعال که price_per_gb دارد
	price_per_gb = None
	currency_id = None
	
	for sub_data in active_subs:
		sub = db.query(BusinessStorageSubscription).filter(
			BusinessStorageSubscription.id == sub_data["id"]
		).first()
		if sub and sub.plan:
			if sub.plan.price_per_gb is not None:
				price_per_gb = float(sub.plan.price_per_gb)
				currency_id = sub.plan.currency_id
				break
			if currency_id is None:
				currency_id = sub.plan.currency_id
	
	if price_per_gb is None:
		# اگر هیچ پلنی price_per_gb ندارد، از تنظیمات سیستم استفاده می‌کنیم
		# یا خطا می‌دهیم
		raise ApiError("PRICE_NOT_CONFIGURED", "قیمت هر گیگابایت اضافی تنظیم نشده است", http_status=400)
	
	if currency_id is None:
		# دریافت ارز پیش‌فرض
		currency = db.query(Currency).filter(Currency.code == "IRR").first()
		if not currency:
			raise ApiError("CURRENCY_NOT_FOUND", "ارز پیش‌فرض یافت نشد", http_status=404)
		currency_id = currency.id
	
	total = over_usage_gb * price_per_gb
	
	# ایجاد صورتحساب
	invoice_code = _build_invoice_code(db)
	invoice = StorageInvoice(
		business_id=business_id,
		subscription_id=None,  # استفاده اضافی مربوط به اشتراک خاصی نیست
		code=invoice_code,
		invoice_type="over_usage",
		total=total,
		currency_id=currency_id,
		status="issued",
		issued_at=datetime.utcnow(),
		extra_info={
			"over_usage_gb": over_usage_gb,
			"price_per_gb": price_per_gb,
			"file_size_bytes": file_size_bytes,
		}
	)
	
	db.add(invoice)
	db.flush()
	db.refresh(invoice)
	
	return get_storage_invoice(db, business_id, invoice.id)


def create_renewal_invoice(
	db: Session,
	business_id: int,
	subscription_id: int,
) -> Dict[str, Any]:
	"""ایجاد صورتحساب برای تمدید"""
	subscription = db.query(BusinessStorageSubscription).filter(
		and_(
			BusinessStorageSubscription.id == subscription_id,
			BusinessStorageSubscription.business_id == business_id
		)
	).first()
	
	if not subscription:
		raise ApiError("SUBSCRIPTION_NOT_FOUND", "اشتراک یافت نشد", http_status=404)
	
	plan = subscription.plan
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)
	
	if plan.period == "lifetime":
		raise ApiError("INVALID_OPERATION", "پلن مادام‌العمر قابل تمدید نیست", http_status=400)
	
	# ایجاد صورتحساب
	invoice_code = _build_invoice_code(db)
	invoice = StorageInvoice(
		business_id=business_id,
		subscription_id=subscription_id,
		code=invoice_code,
		invoice_type="renewal",
		total=float(plan.price),
		currency_id=plan.currency_id,
		status="issued",
		issued_at=datetime.utcnow(),
		extra_info={
			"plan_id": plan.id,
			"plan_name": plan.name,
			"period": plan.period,
			"period_months": plan.period_months,
		}
	)
	
	db.add(invoice)
	db.flush()
	db.refresh(invoice)
	
	return get_storage_invoice(db, business_id, invoice.id)


def pay_storage_invoice_from_wallet(
	db: Session,
	business_id: int,
	invoice_id: int,
	user_id: int,
) -> Dict[str, Any]:
	"""پرداخت صورتحساب از کیف پول"""
	logger.info(f"شروع پرداخت صورتحساب {invoice_id} برای کسب‌وکار {business_id}")
	
	invoice = db.query(StorageInvoice).filter(
		and_(
			StorageInvoice.id == invoice_id,
			StorageInvoice.business_id == business_id
		)
	).first()
	
	if not invoice:
		logger.error(f"صورتحساب {invoice_id} برای کسب‌وکار {business_id} یافت نشد")
		raise ApiError("INVOICE_NOT_FOUND", "صورتحساب یافت نشد", http_status=404)
	
	logger.debug(f"صورتحساب یافت شد: کد={invoice.code}, نوع={invoice.invoice_type}, مبلغ={invoice.total}, وضعیت={invoice.status}")
	
	if invoice.status != "issued":
		logger.warning(f"صورتحساب {invoice_id} در وضعیت {invoice.status} است و قابل پرداخت نیست")
		raise ApiError("INVALID_INVOICE_STATUS", f"صورتحساب در وضعیت {invoice.status} است و قابل پرداخت نیست", http_status=400)
	
	# دریافت حساب کیف پول
	logger.debug(f"دریافت حساب کیف پول برای کسب‌وکار {business_id}")
	account = db.query(WalletAccount).filter(
		WalletAccount.business_id == business_id
	).with_for_update().first()
	
	if account is None:
		# ایجاد خودکار حساب کیف‌پول
		logger.info(f"حساب کیف پول برای کسب‌وکار {business_id} وجود ندارد. ایجاد حساب جدید")
		account = WalletAccount(
			business_id=business_id,
			available_balance=Decimal("0"),
			pending_balance=Decimal("0"),
			status="active"
		)
		db.add(account)
		db.flush()
		logger.debug(f"حساب کیف پول ایجاد شد: id={account.id}")
	else:
		logger.debug(f"حساب کیف پول یافت شد: id={account.id}, موجودی={account.available_balance}")
	
	available = Decimal(str(account.available_balance or 0))
	total_price = Decimal(str(invoice.total))
	
	# بررسی اینکه آیا صورتحساب رایگان است (از طریق plan)
	is_free_invoice = False
	if invoice.subscription_id:
		logger.debug(f"بررسی پلن برای صورتحساب. subscription_id={invoice.subscription_id}")
		subscription = db.query(BusinessStorageSubscription).filter(
			BusinessStorageSubscription.id == invoice.subscription_id
		).first()
		if subscription and subscription.plan:
			is_free_invoice = subscription.plan.is_free or float(subscription.plan.price) == 0
			logger.debug(f"پلن: is_free={subscription.plan.is_free}, price={subscription.plan.price}, is_free_invoice={is_free_invoice}")
	
	logger.debug(f"موجودی کیف پول: {available}, مبلغ صورتحساب: {total_price}, صورتحساب رایگان: {is_free_invoice}")
	
	# اگر صورتحساب رایگان نیست و موجودی کافی نیست
	if not is_free_invoice and available < total_price:
		# عدم کفایت موجودی
		shortfall = float(total_price - available)
		logger.warning(f"موجودی کیف پول کافی نیست. موجودی: {available}, مورد نیاز: {total_price}, کسری: {shortfall}")
		return {
			"invoice_id": invoice.id,
			"status": "insufficient_funds",
			"required_amount": float(total_price),
			"available_amount": float(available),
			"shortfall": shortfall,
		}
	
	# کسر موجودی (فقط برای صورتحساب‌های غیررایگان)
	if not is_free_invoice:
		logger.debug(f"کسر موجودی کیف پول: {available} -> {available - total_price}")
		account.available_balance = available - total_price
		db.flush()
	else:
		logger.debug("صورتحساب رایگان است، موجودی کیف پول کسر نمی‌شود")
	
	# تعیین نوع تراکنش
	if invoice.invoice_type == "subscription":
		tx_type = "storage_subscription"
	elif invoice.invoice_type == "over_usage":
		tx_type = "storage_over_usage"
	elif invoice.invoice_type == "renewal":
		tx_type = "storage_renewal"
	else:
		tx_type = "storage_payment"
	
	# ایجاد سند حسابداری
	logger.info(f"شروع ایجاد سند حسابداری برای صورتحساب {invoice.id}")
	document_id = None
	try:
		document_id = _create_storage_invoice_document(
			db=db,
			business_id=business_id,
			user_id=user_id,
			invoice=invoice,
			amount=total_price,
		)
		logger.info(f"سند حسابداری با موفقیت ایجاد شد: document_id={document_id}")
	except Exception as e:
		# اگر سند ایجاد نشد، تراکنش مالی معتبر است اما سند ندارد
		logger.error(f"خطا در ایجاد سند حسابداری برای صورتحساب {invoice.id}: {type(e).__name__}: {e}", exc_info=True)
		# در صورت خطا، session را rollback کن
		db.rollback()
		document_id = None
	
	tx = WalletTransaction(
		business_id=business_id,
		type=tx_type,
		status="succeeded",
		amount=total_price,
		fee_amount=Decimal("0"),
		description=f"پرداخت صورتحساب ذخیره‌سازی {invoice.code}",
		external_ref=str(invoice.id),
		document_id=document_id,
	)
	db.add(tx)
	db.flush()
	
	# تسویه صورتحساب
	logger.debug(f"تسویه صورتحساب {invoice.id}: وضعیت -> paid")
	invoice.status = "paid"
	invoice.paid_at = datetime.utcnow()
	invoice.wallet_transaction_id = tx.id
	db.commit()
	logger.info(f"صورتحساب {invoice.id} با موفقیت پرداخت شد. wallet_transaction_id={tx.id}, document_id={document_id}")
	
	# اگر صورتحساب برای اشتراک جدید است، اشتراک را فعال کن
	if invoice.invoice_type == "subscription" and invoice.subscription_id:
		logger.debug(f"فعال‌سازی اشتراک {invoice.subscription_id}")
		subscription = db.query(BusinessStorageSubscription).filter(
			BusinessStorageSubscription.id == invoice.subscription_id
		).first()
		if subscription:
			subscription.status = "active"
			db.commit()
			logger.info(f"اشتراک {invoice.subscription_id} فعال شد")
		else:
			logger.warning(f"اشتراک {invoice.subscription_id} یافت نشد")
	
	# اگر صورتحساب برای تمدید است، اشتراک را تمدید کن
	if invoice.invoice_type == "renewal" and invoice.subscription_id:
		logger.debug(f"تمدید اشتراک {invoice.subscription_id}")
		from app.services.storage_subscription_service import renew_subscription
		try:
			renew_subscription(db, business_id, invoice.subscription_id)
			logger.info(f"اشتراک {invoice.subscription_id} تمدید شد")
		except Exception as e:
			logger.error(f"خطا در تمدید اشتراک {invoice.subscription_id}: {type(e).__name__}: {e}", exc_info=True)
	
	result = {
		"invoice_id": invoice.id,
		"status": "paid",
		"wallet_transaction_id": tx.id,
		"document_id": document_id,  # اضافه کردن document_id به نتیجه
		"paid_at": invoice.paid_at.isoformat() if invoice.paid_at else None,
	}
	logger.info(f"پرداخت صورتحساب {invoice.id} با موفقیت تکمیل شد. wallet_transaction_id={tx.id}, document_id={document_id}, نتیجه: {result}")
	return result


def get_storage_invoice(
	db: Session,
	business_id: int,
	invoice_id: int,
) -> Dict[str, Any]:
	"""دریافت جزئیات یک صورتحساب"""
	# در صورت وجود خطای قبلی (PendingRollbackError)، session را rollback کن
	try:
		invoice = db.query(StorageInvoice).filter(
			and_(
				StorageInvoice.id == invoice_id,
				StorageInvoice.business_id == business_id
			)
		).first()
	except PendingRollbackError:
		# اگر خطای PendingRollbackError رخ داد، rollback کن و دوباره تلاش کن
		db.rollback()
		invoice = db.query(StorageInvoice).filter(
			and_(
				StorageInvoice.id == invoice_id,
				StorageInvoice.business_id == business_id
			)
		).first()
	
	if not invoice:
		raise ApiError("INVOICE_NOT_FOUND", "صورتحساب یافت نشد", http_status=404)
	
	currency = invoice.currency
	
	return {
		"id": invoice.id,
		"business_id": invoice.business_id,
		"subscription_id": invoice.subscription_id,
		"code": invoice.code,
		"invoice_type": invoice.invoice_type,
		"total": float(invoice.total),
		"currency_id": invoice.currency_id,
		"currency_code": currency.code if currency else None,
		"status": invoice.status,
		"issued_at": invoice.issued_at.isoformat() if invoice.issued_at else None,
		"paid_at": invoice.paid_at.isoformat() if invoice.paid_at else None,
		"wallet_transaction_id": invoice.wallet_transaction_id,
		"extra_info": invoice.extra_info,
		"created_at": invoice.created_at.isoformat() if invoice.created_at else None,
		"updated_at": invoice.updated_at.isoformat() if invoice.updated_at else None,
	}


def list_storage_invoices(
	db: Session,
	business_id: int,
	limit: int = 50,
	skip: int = 0,
	status: Optional[str] = None,
	invoice_type: Optional[str] = None,
) -> List[Dict[str, Any]]:
	"""لیست صورتحساب‌های کسب‌وکار"""
	query = db.query(StorageInvoice).filter(
		StorageInvoice.business_id == business_id
	)
	
	if status:
		query = query.filter(StorageInvoice.status == status)
	
	if invoice_type:
		query = query.filter(StorageInvoice.invoice_type == invoice_type)
	
	invoices = query.order_by(StorageInvoice.created_at.desc()).offset(skip).limit(limit).all()
	
	return [get_storage_invoice(db, business_id, inv.id) for inv in invoices]

