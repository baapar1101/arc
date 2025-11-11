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
		result.append(
			{
				"id": it.id,
				"code": it.code,
				"name": it.name,
				"description": it.description,
				"category": it.category,
				"icon_url": it.icon_url,
				"plans": [
					{
						"id": p.id,
						"period": p.period,
						"price": float(p.price or 0),
						"currency_id": p.currency_id,
						"is_active": bool(p.is_active),
					}
					for p in plans
				],
			}
		)
	return result


def purchase_plugin(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	plugin_id = int(payload.get("plugin_id") or 0)
	plan_id = int(payload.get("plan_id") or 0)
	quantity = int(payload.get("quantity") or 1)
	if quantity <= 0:
		raise ApiError("INVALID_QUANTITY", "تعداد نامعتبر است", http_status=400)

	plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.id == plugin_id, MarketplacePlugin.is_active == True).first()  # noqa: E712
	if not plugin:
		raise ApiError("PLUGIN_NOT_FOUND", "افزونه یافت نشد یا غیرفعال است", http_status=404)
	plan = db.query(MarketplacePluginPlan).filter(MarketplacePluginPlan.id == plan_id, MarketplacePluginPlan.plugin_id == plugin.id, MarketplacePluginPlan.is_active == True).first()  # noqa: E712
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
		account = WalletAccount(business_id=int(business_id), available_balance=Decimal("0"), pending_balance=Decimal("0"), status="active")
		db.add(account)
		db.flush()

	available = Decimal(str(account.available_balance or 0))
	if available < total_price:
		# عدم کفایت موجودی
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
	# اگر پلاگین قبلاً فعال است، پایان را تمدید کنید
	existing = (
		db.query(BusinessPlugin)
		.filter(BusinessPlugin.business_id == int(business_id), BusinessPlugin.plugin_id == plugin.id)
		.first()
	)
	if existing:
		existing.plan_id = plan.id
		existing.status = "active"
		existing.starts_at = starts_at
		existing.ends_at = ends_at
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


def list_orders(db: Session, business_id: int, limit: int = 20, skip: int = 0) -> Dict[str, Any]:
	q = (
		db.query(MarketplaceOrder)
		.filter(MarketplaceOrder.business_id == int(business_id))
		.order_by(MarketplaceOrder.id.desc())
	)
	total = q.count()
	items = q.offset(max(0, int(skip))).limit(max(1, min(200, int(limit)))).all()
	return {
		"items": [
			{
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
			for it in items
		],
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
	return {
		"items": [
			{
				"id": it.id,
				"code": it.code,
				"total": float(it.total or 0),
				"currency_id": it.currency_id,
				"status": it.status,
				"issued_at": it.issued_at,
				"paid_at": it.paid_at,
				"order_id": it.order_id,
			}
			for it in items
		],
		"total": total,
		"limit": limit,
		"page": (skip // limit) + 1 if limit > 0 else 1,
	}


