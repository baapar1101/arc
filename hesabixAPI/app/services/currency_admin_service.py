"""مدیریت ارزها توسط ادمین: CRUD و بررسی امکان حذف."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.ai_invoice import AIInvoice
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.check import Check, CheckReconciliation
from adapters.db.models.currency import BusinessCurrency, Currency
from adapters.db.models.document import Document
from adapters.db.models.document_monetization import DocumentSubscriptionPlan, DocumentUsageCharge
from adapters.db.models.marketplace import MarketplaceInvoice, MarketplaceOrder, MarketplacePluginPlan
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.price_list import PriceItem
from adapters.db.models.project import Project
from adapters.db.models.quick_sales_settings import QuickSalesSetting
from adapters.db.models.repair_shop import RepairOrder
from adapters.db.models.storage_plan import StorageInvoice, StoragePlan
from adapters.db.models.zohal import ZohalService, ZohalServiceLog
from app.core.cache import get_cache


def invalidate_currency_caches() -> None:
	cache = get_cache()
	if not cache.enabled:
		return
	cache.delete("currencies:all")
	cache.invalidate("business_currencies:*")


def currency_to_dict(c: Currency) -> Dict[str, Any]:
	return {
		"id": c.id,
		"name": c.name,
		"title": c.title,
		"symbol": c.symbol,
		"code": c.code,
		"decimal_places": int(c.decimal_places) if c.decimal_places is not None else 2,
		"round_monetary_amounts": bool(c.round_monetary_amounts)
		if c.round_monetary_amounts is not None
		else True,
		"created_at": c.created_at.isoformat() if c.created_at else None,
		"updated_at": c.updated_at.isoformat() if c.updated_at else None,
	}


def list_all_currencies_admin(db: Session) -> List[Dict[str, Any]]:
	rows = db.query(Currency).order_by(Currency.code.asc()).all()
	return [currency_to_dict(c) for c in rows]


def get_currency_delete_blockers(db: Session, currency_id: int) -> List[str]:
	"""دلایلی که مانع حذف ارز می‌شوند (فارسی)."""
	cid = int(currency_id)
	msgs: List[str] = []

	def _add(model, cond, label: str) -> None:
		n = db.query(func.count()).select_from(model).filter(cond).scalar()
		if n and int(n) > 0:
			msgs.append(f"{label} ({int(n)} مورد)")

	_add(Business, Business.default_currency_id == cid, "ارز پیش‌فرض کسب‌وکارها")
	_add(BusinessCurrency, BusinessCurrency.currency_id == cid, "ارز جانبی در کسب‌وکارها")
	_add(Document, Document.currency_id == cid, "اسناد (فاکتور و ...)")
	_add(BankAccount, BankAccount.currency_id == cid, "حساب‌های بانکی")
	_add(CashRegister, CashRegister.currency_id == cid, "صندوق‌ها")
	_add(PettyCash, PettyCash.currency_id == cid, "تنخواه‌ها")
	_add(PriceItem, PriceItem.currency_id == cid, "اقلام قیمت‌گذاری")
	_add(Check, Check.currency_id == cid, "چک‌ها")
	_add(CheckReconciliation, CheckReconciliation.currency_id == cid, "تطبیق چک")
	_add(QuickSalesSetting, QuickSalesSetting.default_currency_id == cid, "تنظیمات فروش سریع")
	_add(Project, Project.currency_id == cid, "پروژه‌ها")
	_add(ZohalService, ZohalService.currency_id == cid, "سرویس‌های زحل")
	_add(ZohalServiceLog, ZohalServiceLog.currency_id == cid, "لاگ زحل")
	_add(StoragePlan, StoragePlan.currency_id == cid, "پلن‌های ذخیره‌سازی")
	_add(StorageInvoice, StorageInvoice.currency_id == cid, "فاکتورهای ذخیره‌سازی")
	_add(MarketplacePluginPlan, MarketplacePluginPlan.currency_id == cid, "پلن‌های افزونه مارکت‌پلیس")
	_add(MarketplaceOrder, MarketplaceOrder.currency_id == cid, "سفارش‌های مارکت‌پلیس")
	_add(MarketplaceInvoice, MarketplaceInvoice.currency_id == cid, "فاکتورهای مارکت‌پلیس")
	_add(DocumentSubscriptionPlan, DocumentSubscriptionPlan.currency_id == cid, "پلن‌های اشتراک سند")
	_add(DocumentUsageCharge, DocumentUsageCharge.currency_id == cid, "شارژهای استفاده از سند")
	_add(AIInvoice, AIInvoice.currency_id == cid, "فاکتورهای هوش مصنوعی")
	_add(RepairOrder, RepairOrder.currency_id == cid, "سفارش‌های تعمیرگاه")

	return msgs


def create_currency(
	db: Session,
	*,
	name: str,
	title: str,
	symbol: str,
	code: str,
	decimal_places: int = 2,
	round_monetary_amounts: bool = True,
) -> Currency:
	code_clean = code.strip().upper()
	name_clean = name.strip()
	title_clean = title.strip()
	symbol_clean = symbol.strip()
	dp = max(0, min(8, int(decimal_places)))

	dup_code = db.query(Currency).filter(func.upper(Currency.code) == code_clean).first()
	if dup_code:
		from app.core.responses import ApiError

		raise ApiError(
			"CURRENCY_DUPLICATE",
			"ارزی با این کد وجود دارد.",
			http_status=400,
		)
	dup_name = db.query(Currency).filter(func.lower(Currency.name) == name_clean.lower()).first()
	if dup_name:
		from app.core.responses import ApiError

		raise ApiError(
			"CURRENCY_DUPLICATE",
			"ارزی با این نام انگلیسی وجود دارد.",
			http_status=400,
		)

	c = Currency(
		name=name_clean,
		title=title_clean,
		symbol=symbol_clean,
		code=code_clean,
		decimal_places=dp,
		round_monetary_amounts=bool(round_monetary_amounts),
	)
	db.add(c)
	db.commit()
	db.refresh(c)
	invalidate_currency_caches()
	return c


def update_currency(
	db: Session,
	currency_id: int,
	*,
	name: Optional[str] = None,
	title: Optional[str] = None,
	symbol: Optional[str] = None,
	code: Optional[str] = None,
	decimal_places: Optional[int] = None,
	round_monetary_amounts: Optional[bool] = None,
) -> Currency:
	c = db.query(Currency).filter(Currency.id == int(currency_id)).first()
	if not c:
		from app.core.responses import ApiError

		raise ApiError("NOT_FOUND", "ارز یافت نشد", http_status=404)

	if code is not None:
		code_clean = code.strip().upper()
		other = (
			db.query(Currency)
			.filter(func.upper(Currency.code) == code_clean, Currency.id != c.id)
			.first()
		)
		if other:
			from app.core.responses import ApiError

			raise ApiError("CURRENCY_DUPLICATE", "کد ارز تکراری است.", http_status=400)
		c.code = code_clean
	if name is not None:
		nm = name.strip()
		other = (
			db.query(Currency)
			.filter(func.lower(Currency.name) == nm.lower(), Currency.id != c.id)
			.first()
		)
		if other:
			from app.core.responses import ApiError

			raise ApiError("CURRENCY_DUPLICATE", "نام انگلیسی ارز تکراری است.", http_status=400)
		c.name = nm
	if title is not None:
		c.title = title.strip()
	if symbol is not None:
		c.symbol = symbol.strip()
	if decimal_places is not None:
		c.decimal_places = max(0, min(8, int(decimal_places)))
	if round_monetary_amounts is not None:
		c.round_monetary_amounts = bool(round_monetary_amounts)

	db.commit()
	db.refresh(c)
	invalidate_currency_caches()
	return c


def delete_currency_if_allowed(db: Session, currency_id: int) -> None:
	blockers = get_currency_delete_blockers(db, currency_id)
	if blockers:
		from app.core.responses import ApiError

		raise ApiError(
			"CURRENCY_IN_USE",
			"حذف ارز به‌دلیل استفاده در سیستم ممکن نیست: " + "؛ ".join(blockers),
			http_status=400,
		)
	c = db.query(Currency).filter(Currency.id == int(currency_id)).first()
	if not c:
		from app.core.responses import ApiError

		raise ApiError("NOT_FOUND", "ارز یافت نشد", http_status=404)
	db.delete(c)
	db.commit()
	invalidate_currency_caches()
