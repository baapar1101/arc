from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import (
	MarketplacePlugin,
	MarketplacePluginPlan,
	MarketplaceOrder,
	MarketplaceInvoice,
	BusinessPlugin,
)
from adapters.db.models.wallet import WalletTransaction
from adapters.db.models.currency import Currency
from adapters.db.models.business import Business
from app.core.responses import ApiError


def _period_to_duration(period: str) -> Optional[timedelta]:
	period = (period or "").lower()
	if period == "monthly":
		return timedelta(days=30)
	if period == "yearly":
		return timedelta(days=365)
	if period == "lifetime":
		return None
	# پیش‌فرض: یک ماه
	return timedelta(days=30)


def _build_invoice_code(db: Session) -> str:
	today = datetime.utcnow().strftime("%Y%m%d")
	# شمارنده ساده بر اساس تاریخ
	base = f"MKP-{today}"
	like_pattern = f"{base}-%"
	last = (
		db.query(MarketplaceInvoice)
		.filter(MarketplaceInvoice.code.like(like_pattern))
		.order_by(MarketplaceInvoice.id.desc())
		.first()
	)
	next_num = 1
	if last and isinstance(last.code, str) and last.code.startswith(base + "-"):
		try:
			next_num = int(last.code.split("-")[-1]) + 1
		except Exception:
			next_num = 1
	return f"{base}-{next_num:04d}"


def list_plugins(db: Session) -> List[Dict[str, Any]]:
	items = (
		db.query(MarketplacePlugin)
		.filter(MarketplacePlugin.is_active == True)  # noqa: E712
		.order_by(MarketplacePlugin.id.desc())
		.all()
	)
	result: List[Dict[str, Any]] = []
	for it in items:
		plans = (
			db.query(MarketplacePluginPlan)
			.filter(
				MarketplacePluginPlan.plugin_id == it.id,
				MarketplacePluginPlan.is_active == True,  # noqa: E712
			)
			.order_by(MarketplacePluginPlan.price.asc())
			.all()
		)
		# دریافت اطلاعات ارز برای هر پلن
		plans_data = []
		for p in plans:
			currency = db.query(Currency).filter(Currency.id == int(p.currency_id)).first()
			plan_data = {
				"id": p.id,
				"period": p.period,
				"price": float(p.price or 0),
				"currency_id": p.currency_id,
				"is_active": bool(p.is_active),
			}
			# اضافه کردن اطلاعات ارز
			if currency:
				plan_data["currency"] = {
					"id": currency.id,
					"code": currency.code,
					"title": currency.title,
					"symbol": currency.symbol,
				}
			plans_data.append(plan_data)
		
		result.append(
			{
				"id": it.id,
				"code": it.code,
				"name": it.name,
				"description": it.description,
				"category": it.category,
				"icon_url": it.icon_url,
				"trial_days": it.trial_days,
				"trial_allowed": it.trial_allowed,
				"plans": plans_data,
			}
		)
	return result


def purchase_plugin(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	"""
	خرید افزونه برای کسب‌وکار با استفاده از transaction برای اطمینان از یکپارچگی داده‌ها
	"""
	try:
		plugin_id = int(payload.get("plugin_id") or 0)
		plan_id = int(payload.get("plan_id") or 0)
		quantity = int(payload.get("quantity") or 1)
		if quantity <= 0:
			raise ApiError("INVALID_QUANTITY", "تعداد نامعتبر است", http_status=400)

		# بررسی افزونه و پلن با lock برای جلوگیری از race condition
		plugin = db.query(MarketplacePlugin).filter(
			MarketplacePlugin.id == plugin_id,
			MarketplacePlugin.is_active == True  # noqa: E712
		).with_for_update().first()
		if not plugin:
			raise ApiError("PLUGIN_NOT_FOUND", "افزونه یافت نشد یا غیرفعال است", http_status=404)
		
		plan = db.query(MarketplacePluginPlan).filter(
			MarketplacePluginPlan.id == plan_id,
			MarketplacePluginPlan.plugin_id == plugin.id,
			MarketplacePluginPlan.is_active == True  # noqa: E712
		).with_for_update().first()
		if not plan:
			raise ApiError("PLAN_NOT_FOUND", "پلن افزونه یافت نشد یا غیرفعال است", http_status=404)

		# اعتبارسنجی ارز
		currency = db.query(Currency).filter(Currency.id == int(plan.currency_id)).first()
		if not currency:
			raise ApiError("CURRENCY_NOT_FOUND", "ارز پلن نامعتبر است", http_status=400)

		business = db.query(Business).filter(Business.id == int(business_id)).first()
		if not business:
			raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

		unit_price = Decimal(str(plan.price or 0))
		total_price = unit_price * Decimal(quantity)

		# ایجاد سفارش
		order = MarketplaceOrder(
			business_id=int(business_id),
			plugin_id=int(plugin.id),
			plan_id=int(plan.id),
			quantity=quantity,
			unit_price=unit_price,
			total_price=total_price,
			currency_id=plan.currency_id,
			status="pending",
		)
		db.add(order)
		db.flush()

		# ایجاد صورتحساب بازار
		invoice_code = _build_invoice_code(db)
		invoice = MarketplaceInvoice(
			order_id=order.id,
			business_id=int(business_id),
			code=invoice_code,
			total=total_price,
			currency_id=plan.currency_id,
			status="issued",
			issued_at=datetime.utcnow(),
		)
		db.add(invoice)
		db.flush()

		order.invoice_id = invoice.id
		db.flush()

		# تلاش برای پرداخت از کیف‌پول
		# دریافت اتمی حساب کیف‌پول و بررسی مانده
		from adapters.db.models.wallet import WalletAccount  # import محلی برای جلوگیری از چرخه
		account = (
			db.query(WalletAccount)
			.filter(WalletAccount.business_id == int(business_id))
			.with_for_update()
			.first()
		)
		if account is None:
			# ایجاد خودکار حساب کیف‌پول
			account = WalletAccount(
				business_id=int(business_id),
				available_balance=Decimal("0"),
				pending_balance=Decimal("0"),
				status="active"
			)
			db.add(account)
			db.flush()

		available = Decimal(str(account.available_balance or 0))
		if available < total_price:
			# عدم کفایت موجودی - rollback نمی‌کنیم چون order و invoice باید ثبت شوند
			shortfall = float(total_price - available)
			return {
				"order_id": order.id,
				"invoice_id": invoice.id,
				"status": "insufficient_funds",
				"required_amount": float(total_price),
				"available_amount": float(available),
				"shortfall": float(Decimal(str(shortfall))),
			}

		# کسر موجودی و ثبت تراکنش
		account.available_balance = available - total_price
		db.flush()

		tx = WalletTransaction(
			business_id=int(business_id),
			type="plugin_purchase",
			status="succeeded",
			amount=total_price,
			fee_amount=Decimal("0"),
			description=f"خرید افزونه {plugin.name} - پلن {plan.period}",
			external_ref=str(invoice.id),
			document_id=None,
		)
		db.add(tx)
		db.flush()

		# تسویه سفارش و صورتحساب
		invoice.status = "paid"
		invoice.paid_at = datetime.utcnow()
		order.status = "paid"
		order.wallet_transaction_id = tx.id
		db.flush()

		# فعال‌سازی لایسنس
		duration = _period_to_duration(plan.period)
		starts_at = datetime.utcnow()
		ends_at = (starts_at + duration) if duration is not None else None
		
		# بررسی لایسنس موجود - اگر منقضی شده باشد، آن را تمدید می‌کنیم
		existing = (
			db.query(BusinessPlugin)
			.filter(
				BusinessPlugin.business_id == int(business_id),
				BusinessPlugin.plugin_id == plugin.id
			)
			.with_for_update()
			.first()
		)
		if existing:
			# اگر لایسنس موجود است، آن را تمدید می‌کنیم
			# اگر trial بود، آن را به خرید تبدیل می‌کنیم
			existing.plan_id = plan.id
			existing.status = "active"
			existing.starts_at = starts_at
			existing.ends_at = ends_at
			existing.is_trial = False  # تبدیل trial به خرید
			existing.trial_started_at = None
		else:
			db.add(
				BusinessPlugin(
					business_id=int(business_id),
					plugin_id=plugin.id,
					plan_id=plan.id,
					status="active",
					starts_at=starts_at,
					ends_at=ends_at,
					auto_renew=False,
				)
			)
		db.flush()

		return {
			"order_id": order.id,
			"invoice_id": invoice.id,
			"wallet_transaction_id": tx.id,
			"status": "paid",
			"license": {
				"plugin_id": plugin.id,
				"plan_id": plan.id,
				"starts_at": starts_at,
				"ends_at": ends_at,
				"status": "active",
			},
		}
	except Exception as e:
		# در صورت خطا، rollback می‌کنیم
		db.rollback()
		# اگر ApiError است، آن را دوباره raise می‌کنیم
		if isinstance(e, ApiError):
			raise
		# در غیر این صورت، آن را به عنوان خطای داخلی می‌فرستیم
		raise ApiError("INTERNAL_ERROR", f"خطا در خرید افزونه: {str(e)}", http_status=500)


def list_orders(db: Session, business_id: int, limit: int = 20, skip: int = 0) -> Dict[str, Any]:
	q = (
		db.query(MarketplaceOrder)
		.filter(MarketplaceOrder.business_id == int(business_id))
		.order_by(MarketplaceOrder.id.desc())
	)
	total = q.count()
	items = q.offset(max(0, int(skip))).limit(max(1, min(200, int(limit)))).all()
	result_items = []
	for it in items:
		currency = db.query(Currency).filter(Currency.id == int(it.currency_id)).first()
		item_data = {
			"id": it.id,
			"plugin_id": it.plugin_id,
			"plan_id": it.plan_id,
			"quantity": it.quantity,
			"unit_price": float(it.unit_price or 0),
			"total_price": float(it.total_price or 0),
			"currency_id": it.currency_id,
			"status": it.status,
			"invoice_id": it.invoice_id,
			"wallet_transaction_id": it.wallet_transaction_id,
			"created_at": it.created_at,
		}
		# اضافه کردن اطلاعات ارز
		if currency:
			item_data["currency"] = {
				"id": currency.id,
				"code": currency.code,
				"title": currency.title,
				"symbol": currency.symbol,
			}
		result_items.append(item_data)
	
	return {
		"items": result_items,
		"total": total,
		"limit": limit,
		"page": (skip // limit) + 1 if limit > 0 else 1,
	}


def list_invoices(db: Session, business_id: int, limit: int = 20, skip: int = 0) -> Dict[str, Any]:
	q = (
		db.query(MarketplaceInvoice)
		.filter(MarketplaceInvoice.business_id == int(business_id))
		.order_by(MarketplaceInvoice.id.desc())
	)
	total = q.count()
	items = q.offset(max(0, int(skip))).limit(max(1, min(200, int(limit)))).all()
	result_items = []
	for it in items:
		currency = db.query(Currency).filter(Currency.id == int(it.currency_id)).first()
		item_data = {
			"id": it.id,
			"code": it.code,
			"total": float(it.total or 0),
			"currency_id": it.currency_id,
			"status": it.status,
			"issued_at": it.issued_at,
			"paid_at": it.paid_at,
			"order_id": it.order_id,
		}
		# اضافه کردن اطلاعات ارز
		if currency:
			item_data["currency"] = {
				"id": currency.id,
				"code": currency.code,
				"title": currency.title,
				"symbol": currency.symbol,
			}
		result_items.append(item_data)
	
	return {
		"items": result_items,
		"total": total,
		"limit": limit,
		"page": (skip // limit) + 1 if limit > 0 else 1,
	}


# ========== Admin Functions ==========

def create_plugin(db: Session, payload: Dict[str, Any]) -> Dict[str, Any]:
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	description = payload.get("description")
	category = payload.get("category")
	icon_url = payload.get("icon_url")
	is_active = bool(payload.get("is_active", True))
	trial_days = payload.get("trial_days")
	trial_allowed = bool(payload.get("trial_allowed", False))

	if not code:
		raise ApiError("INVALID_CODE", "کد افزونه الزامی است", http_status=400)
	if not name:
		raise ApiError("INVALID_NAME", "نام افزونه الزامی است", http_status=400)
	
	# اعتبارسنجی trial_days
	if trial_allowed:
		if trial_days is None or int(trial_days or 0) <= 0:
			raise ApiError("INVALID_TRIAL_DAYS", "تعداد روزهای trial باید بیشتر از صفر باشد", http_status=400)
		trial_days = int(trial_days)
	else:
		trial_days = None

	# بررسی تکراری نبودن کد
	existing = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == code).first()
	if existing:
		raise ApiError("DUPLICATE_CODE", f"افزونه با کد {code} قبلاً ثبت شده است", http_status=400)

	plugin = MarketplacePlugin(
		code=code,
		name=name,
		description=description,
		category=category,
		icon_url=icon_url,
		is_active=is_active,
		trial_days=trial_days,
		trial_allowed=trial_allowed,
	)
	db.add(plugin)
	db.commit()
	db.refresh(plugin)

	return {
		"id": plugin.id,
		"code": plugin.code,
		"name": plugin.name,
		"description": plugin.description,
		"category": plugin.category,
		"icon_url": plugin.icon_url,
		"is_active": plugin.is_active,
		"trial_days": plugin.trial_days,
		"trial_allowed": plugin.trial_allowed,
		"created_at": plugin.created_at,
		"updated_at": plugin.updated_at,
	}


def update_plugin(db: Session, plugin_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.id == plugin_id).first()
	if not plugin:
		raise ApiError("PLUGIN_NOT_FOUND", "افزونه یافت نشد", http_status=404)

	if "code" in payload:
		new_code = str(payload.get("code") or "").strip()
		if new_code and new_code != plugin.code:
			existing = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == new_code, MarketplacePlugin.id != plugin_id).first()
			if existing:
				raise ApiError("DUPLICATE_CODE", f"افزونه با کد {new_code} قبلاً ثبت شده است", http_status=400)
			plugin.code = new_code

	if "name" in payload:
		name = str(payload.get("name") or "").strip()
		if name:
			plugin.name = name

	if "description" in payload:
		plugin.description = payload.get("description")

	if "category" in payload:
		plugin.category = payload.get("category")

	if "icon_url" in payload:
		plugin.icon_url = payload.get("icon_url")

	if "is_active" in payload:
		plugin.is_active = bool(payload.get("is_active"))

	if "trial_allowed" in payload:
		trial_allowed = bool(payload.get("trial_allowed", False))
		if trial_allowed:
			trial_days = payload.get("trial_days")
			if trial_days is None or int(trial_days or 0) <= 0:
				raise ApiError("INVALID_TRIAL_DAYS", "تعداد روزهای trial باید بیشتر از صفر باشد", http_status=400)
			plugin.trial_days = int(trial_days)
			plugin.trial_allowed = True
		else:
			plugin.trial_days = None
			plugin.trial_allowed = False
	elif "trial_days" in payload:
		# اگر فقط trial_days تغییر کرده، بررسی می‌کنیم
		trial_days = payload.get("trial_days")
		if trial_days is not None and int(trial_days or 0) > 0:
			plugin.trial_days = int(trial_days)
			plugin.trial_allowed = True
		elif trial_days is None or int(trial_days or 0) <= 0:
			plugin.trial_days = None
			plugin.trial_allowed = False

	db.commit()
	db.refresh(plugin)

	return {
		"id": plugin.id,
		"code": plugin.code,
		"name": plugin.name,
		"description": plugin.description,
		"category": plugin.category,
		"icon_url": plugin.icon_url,
		"is_active": plugin.is_active,
		"trial_days": plugin.trial_days,
		"trial_allowed": plugin.trial_allowed,
		"created_at": plugin.created_at,
		"updated_at": plugin.updated_at,
	}


def delete_plugin(db: Session, plugin_id: int) -> Dict[str, Any]:
	plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.id == plugin_id).first()
	if not plugin:
		raise ApiError("PLUGIN_NOT_FOUND", "افزونه یافت نشد", http_status=404)

	# بررسی استفاده از افزونه
	has_orders = db.query(MarketplaceOrder).filter(MarketplaceOrder.plugin_id == plugin_id).first()
	has_licenses = db.query(BusinessPlugin).filter(BusinessPlugin.plugin_id == plugin_id).first()

	if has_orders or has_licenses:
		# غیرفعال کردن به جای حذف
		plugin.is_active = False
		db.commit()
		return {"message": "افزونه غیرفعال شد (به دلیل استفاده در سفارش‌ها یا لایسنس‌ها قابل حذف نیست)"}

	db.delete(plugin)
	db.commit()
	return {"message": "افزونه با موفقیت حذف شد"}


def create_plugin_plan(db: Session, plugin_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.id == plugin_id).first()
	if not plugin:
		raise ApiError("PLUGIN_NOT_FOUND", "افزونه یافت نشد", http_status=404)

	period = str(payload.get("period") or "").strip().lower()
	price = Decimal(str(payload.get("price") or 0))
	currency_id = int(payload.get("currency_id") or 0)
	is_active = bool(payload.get("is_active", True))

	if period not in ("monthly", "yearly", "lifetime"):
		raise ApiError("INVALID_PERIOD", "دوره باید یکی از monthly, yearly, lifetime باشد", http_status=400)
	if price < 0:
		raise ApiError("INVALID_PRICE", "قیمت نمی‌تواند منفی باشد", http_status=400)
	if not currency_id:
		raise ApiError("INVALID_CURRENCY", "ارز الزامی است", http_status=400)

	currency = db.query(Currency).filter(Currency.id == currency_id).first()
	if not currency:
		raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)

	plan = MarketplacePluginPlan(
		plugin_id=plugin_id,
		period=period,
		price=price,
		currency_id=currency_id,
		is_active=is_active,
	)
	db.add(plan)
	db.commit()
	db.refresh(plan)

	return {
		"id": plan.id,
		"plugin_id": plan.plugin_id,
		"period": plan.period,
		"price": float(plan.price or 0),
		"currency_id": plan.currency_id,
		"is_active": plan.is_active,
		"created_at": plan.created_at,
		"updated_at": plan.updated_at,
	}


def update_plugin_plan(db: Session, plan_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	plan = db.query(MarketplacePluginPlan).filter(MarketplacePluginPlan.id == plan_id).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

	if "period" in payload:
		period = str(payload.get("period") or "").strip().lower()
		if period not in ("monthly", "yearly", "lifetime"):
			raise ApiError("INVALID_PERIOD", "دوره باید یکی از monthly, yearly, lifetime باشد", http_status=400)
		plan.period = period

	if "price" in payload:
		price = Decimal(str(payload.get("price") or 0))
		if price < 0:
			raise ApiError("INVALID_PRICE", "قیمت نمی‌تواند منفی باشد", http_status=400)
		plan.price = price

	if "currency_id" in payload:
		currency_id = int(payload.get("currency_id") or 0)
		if currency_id:
			currency = db.query(Currency).filter(Currency.id == currency_id).first()
			if not currency:
				raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
			plan.currency_id = currency_id

	if "is_active" in payload:
		plan.is_active = bool(payload.get("is_active"))

	db.commit()
	db.refresh(plan)

	return {
		"id": plan.id,
		"plugin_id": plan.plugin_id,
		"period": plan.period,
		"price": float(plan.price or 0),
		"currency_id": plan.currency_id,
		"is_active": plan.is_active,
		"created_at": plan.created_at,
		"updated_at": plan.updated_at,
	}


def delete_plugin_plan(db: Session, plan_id: int) -> Dict[str, Any]:
	plan = db.query(MarketplacePluginPlan).filter(MarketplacePluginPlan.id == plan_id).first()
	if not plan:
		raise ApiError("PLAN_NOT_FOUND", "پلن یافت نشد", http_status=404)

	# بررسی استفاده از پلن
	has_orders = db.query(MarketplaceOrder).filter(MarketplaceOrder.plan_id == plan_id).first()
	has_licenses = db.query(BusinessPlugin).filter(BusinessPlugin.plan_id == plan_id).first()

	if has_orders or has_licenses:
		# غیرفعال کردن به جای حذف
		plan.is_active = False
		db.commit()
		return {"message": "پلن غیرفعال شد (به دلیل استفاده در سفارش‌ها یا لایسنس‌ها قابل حذف نیست)"}

	db.delete(plan)
	db.commit()
	return {"message": "پلن با موفقیت حذف شد"}


def list_all_plugins(db: Session, only_active: Optional[bool] = None) -> List[Dict[str, Any]]:
	query = db.query(MarketplacePlugin)
	if only_active is not None:
		query = query.filter(MarketplacePlugin.is_active == only_active)  # noqa: E712
	items = query.order_by(MarketplacePlugin.id.desc()).all()

	result: List[Dict[str, Any]] = []
	for it in items:
		plans = (
			db.query(MarketplacePluginPlan)
			.filter(MarketplacePluginPlan.plugin_id == it.id)
			.order_by(MarketplacePluginPlan.price.asc())
			.all()
		)
		result.append(
			{
				"id": it.id,
				"code": it.code,
				"name": it.name,
				"description": it.description,
				"category": it.category,
				"icon_url": it.icon_url,
				"is_active": it.is_active,
				"trial_days": it.trial_days,
				"trial_allowed": it.trial_allowed,
				"created_at": it.created_at,
				"updated_at": it.updated_at,
				"plans": [
					{
						"id": p.id,
						"period": p.period,
						"price": float(p.price or 0),
						"currency_id": p.currency_id,
						"is_active": bool(p.is_active),
						"created_at": p.created_at,
						"updated_at": p.updated_at,
					}
					for p in plans
				],
			}
		)
	return result


# ========== Trial Functions ==========

def start_trial_plugin(
	db: Session,
	business_id: int,
	plugin_id: int,
	user_id: int,
) -> Dict[str, Any]:
	"""
	شروع دوره trial برای یک افزونه
	هر کسب‌وکار فقط یکبار می‌تواند از trial استفاده کند
	"""
	# بررسی افزونه
	plugin = db.query(MarketplacePlugin).filter(
		MarketplacePlugin.id == plugin_id,
		MarketplacePlugin.is_active == True  # noqa: E712
	).first()
	if not plugin:
		raise ApiError("PLUGIN_NOT_FOUND", "افزونه یافت نشد یا غیرفعال است", http_status=404)
	
	# بررسی اینکه آیا trial مجاز است
	if not plugin.trial_allowed or not plugin.trial_days or plugin.trial_days <= 0:
		raise ApiError("TRIAL_NOT_ALLOWED", "این افزونه trial ندارد", http_status=400)
	
	# بررسی کسب‌وکار
	business = db.query(Business).filter(Business.id == int(business_id)).first()
	if not business:
		raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
	
	# بررسی اینکه آیا قبلاً trial استفاده شده است
	existing_trial = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == int(business_id),
			BusinessPlugin.plugin_id == plugin.id,
			BusinessPlugin.is_trial == True  # noqa: E712
		)
		.first()
	)
	if existing_trial:
		raise ApiError("TRIAL_ALREADY_USED", "شما قبلاً از trial این افزونه استفاده کرده‌اید", http_status=400)
	
	# بررسی اینکه آیا لایسنس فعال (غیر trial) وجود دارد
	existing_license = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == int(business_id),
			BusinessPlugin.plugin_id == plugin.id,
			BusinessPlugin.is_trial == False  # noqa: E712
		)
		.first()
	)
	if existing_license and existing_license.status == "active":
		raise ApiError("PLUGIN_ALREADY_ACTIVE", "این افزونه قبلاً برای شما فعال شده است", http_status=400)
	
	# پیدا کردن اولین پلن فعال (برای ثبت در BusinessPlugin)
	plan = (
		db.query(MarketplacePluginPlan)
		.filter(
			MarketplacePluginPlan.plugin_id == plugin.id,
			MarketplacePluginPlan.is_active == True  # noqa: E712
		)
		.order_by(MarketplacePluginPlan.price.asc())
		.first()
	)
	if not plan:
		raise ApiError("NO_PLAN_AVAILABLE", "هیچ پلن فعالی برای این افزونه وجود ندارد", http_status=400)
	
	# محاسبه تاریخ شروع و پایان trial
	starts_at = datetime.utcnow()
	ends_at = starts_at + timedelta(days=plugin.trial_days)
	
	# ایجاد لایسنس trial
	trial_license = BusinessPlugin(
		business_id=int(business_id),
		plugin_id=plugin.id,
		plan_id=plan.id,  # استفاده از اولین پلن برای ثبت
		status="active",
		starts_at=starts_at,
		ends_at=ends_at,
		auto_renew=False,
		is_trial=True,
		trial_started_at=starts_at,
	)
	db.add(trial_license)
	db.commit()
	db.refresh(trial_license)
	
	return {
		"license_id": trial_license.id,
		"plugin_id": plugin.id,
		"plugin_code": plugin.code,
		"plugin_name": plugin.name,
		"plan_id": plan.id,
		"status": "active",
		"is_trial": True,
		"is_active": True,
		"starts_at": starts_at,
		"ends_at": ends_at,
		"trial_days": plugin.trial_days,
		"trial_remaining_days": plugin.trial_days,
	}


# ========== Business Plugin Status Functions ==========

def get_business_plugin_status(db: Session, business_id: int, plugin_id: int) -> Optional[Dict[str, Any]]:
	now = datetime.utcnow()
	license = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == int(business_id),
			BusinessPlugin.plugin_id == int(plugin_id),
		)
		.first()
	)

	if not license:
		return None

	plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.id == plugin_id).first()
	plan = db.query(MarketplacePluginPlan).filter(MarketplacePluginPlan.id == license.plan_id).first()

	# بررسی انقضا
	is_expired = False
	if license.ends_at and license.ends_at < now:
		is_expired = True
		if license.status == "active":
			license.status = "expired"
			db.commit()

	is_active = license.status == "active" and not is_expired
	
	# محاسبه روزهای باقی‌مانده trial
	trial_remaining_days = None
	if license.is_trial and license.ends_at:
		remaining = (license.ends_at - now).days
		trial_remaining_days = max(0, remaining)

	return {
		"license_id": license.id,
		"plugin_id": license.plugin_id,
		"plugin_code": plugin.code if plugin else None,
		"plugin_name": plugin.name if plugin else None,
		"plan_id": license.plan_id,
		"plan_period": plan.period if plan else None,
		"status": license.status,
		"is_active": is_active,
		"is_expired": is_expired,
		"is_trial": license.is_trial,
		"trial_started_at": license.trial_started_at,
		"trial_remaining_days": trial_remaining_days,
		"starts_at": license.starts_at,
		"ends_at": license.ends_at,
		"auto_renew": license.auto_renew,
		"created_at": license.created_at,
		"updated_at": license.updated_at,
	}


def list_business_plugins(db: Session, business_id: int) -> List[Dict[str, Any]]:
	import logging
	from sqlalchemy.exc import SQLAlchemyError
	
	logger = logging.getLogger(__name__)
	
	try:
		now = datetime.utcnow()
		licenses = (
			db.query(BusinessPlugin)
			.filter(BusinessPlugin.business_id == int(business_id))
			.order_by(BusinessPlugin.id.desc())
			.all()
		)

		result: List[Dict[str, Any]] = []
		for license in licenses:
			try:
				plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.id == license.plugin_id).first()
				plan = db.query(MarketplacePluginPlan).filter(MarketplacePluginPlan.id == license.plan_id).first()

				# بررسی انقضا
				is_expired = False
				if license.ends_at and license.ends_at < now:
					is_expired = True
					if license.status == "active":
						try:
							license.status = "expired"
							db.commit()
						except SQLAlchemyError as e:
							logger.warning(
								f"Failed to update expired license status for license_id={license.id}: {str(e)}",
								extra={"license_id": license.id, "business_id": business_id}
							)
							db.rollback()
							# ادامه می‌دهیم حتی اگر commit fail شود

				is_active = license.status == "active" and not is_expired
				
				# محاسبه روزهای باقی‌مانده trial
				trial_remaining_days = None
				if license.is_trial and license.ends_at:
					remaining = (license.ends_at - now).days
					trial_remaining_days = max(0, remaining)

				result.append({
					"license_id": license.id,
					"plugin_id": license.plugin_id,
					"plugin_code": plugin.code if plugin else None,
					"plugin_name": plugin.name if plugin else None,
					"plan_id": license.plan_id,
					"plan_period": plan.period if plan else None,
					"plan_price": float(plan.price or 0) if plan else None,
					"status": license.status,
					"is_active": is_active,
					"is_expired": is_expired,
					"is_trial": license.is_trial,
					"trial_started_at": license.trial_started_at,
					"trial_remaining_days": trial_remaining_days,
					"starts_at": license.starts_at,
					"ends_at": license.ends_at,
					"auto_renew": license.auto_renew,
					"created_at": license.created_at,
					"updated_at": license.updated_at,
				})
			except Exception as e:
				# اگر خطا در پردازش یک license رخ دهد، آن را لاگ می‌کنیم و ادامه می‌دهیم
				logger.warning(
					f"Error processing license_id={license.id} for business_id={business_id}: {str(e)}",
					exc_info=True,
					extra={"license_id": license.id, "business_id": business_id}
				)
				# ادامه می‌دهیم تا سایر licenses را پردازش کنیم

		return result
	except SQLAlchemyError as e:
		logger.error(
			f"Database error in list_business_plugins for business_id={business_id}: {str(e)}",
			exc_info=True,
			extra={"business_id": business_id}
		)
		db.rollback()
		raise
	except Exception as e:
		logger.error(
			f"Unexpected error in list_business_plugins for business_id={business_id}: {str(e)}",
			exc_info=True,
			extra={"business_id": business_id}
		)
		raise


def check_and_update_expired_licenses(db: Session) -> Dict[str, Any]:
	"""بررسی و به‌روزرسانی لایسنس‌های منقضی شده"""
	now = datetime.utcnow()
	expired_licenses = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.status == "active",
			BusinessPlugin.ends_at.isnot(None),
			BusinessPlugin.ends_at < now,
		)
		.all()
	)

	updated_count = 0
	for license in expired_licenses:
		license.status = "expired"
		updated_count += 1

	if updated_count > 0:
		db.commit()

	return {
		"updated_count": updated_count,
		"checked_at": now,
	}


