"""Seed / sync پیش‌فرض افزونه‌های بازار (تک‌منبع برای migration و API همگام‌سازی)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.currency import Currency
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan


_REPAIR_SHOP_DESCRIPTION = """
سیستم جامع مدیریت تعمیرگاه با قابلیت‌های زیر:

✅ دریافت و تحویل کالای تعمیری
✅ صدور قبض رسید کالا
✅ کارتابل تعمیرات (Kanban Board)
✅ یکپارچگی با سیستم گارانتی
✅ مدیریت تعمیرکاران و حق‌الزحمه (فیکس، درصدی، موردی)
✅ افزودن قطعات استفاده شده
✅ حواله خروج خودکار قطعات از انبار
✅ بررسی موجودی قبل از مصرف
✅ ارسال پیامک و ایمیل خودکار به مشتری
✅ صدور فاکتور تعمیر (خدمات + قطعات)
✅ ثبت خودکار اسناد حسابداری
✅ تاریخچه کامل تعمیرات براساس کد گارانتی
✅ گزارش‌گیری جامع از عملکرد تعمیرکاران
✅ مدیریت ضمائم و تصاویر (قبل/بعد تعمیر)
✅ کنترل سطح دسترسی کاربران

مناسب برای:
🔧 تعمیرگاه‌های لوازم الکترونیکی
📱 مراکز تعمیر موبایل و تبلت
💻 سرویس‌های تعمیر لپتاپ و کامپیوتر
🏠 تعمیرگاه‌های لوازم خانگی
🚗 مراکز خدمات خودرو
""".strip()


@dataclass(frozen=True)
class _PluginSeed:
	code: str
	name: str
	description: str
	category: Optional[str]
	icon_url: Optional[str]
	trial_days: Optional[int]
	trial_allowed: bool
	plans: Tuple[Tuple[str, float], ...]  # (period, price)


_DEFAULT_PLUGINS: Tuple[_PluginSeed, ...] = (
	_PluginSeed(
		code="basalam_connector",
		name="اتصال باسلام",
		description=(
			"اتصال کامل به باسلام برای دریافت وب‌هوک، همگام‌سازی سفارش/محصول، "
			"بریج چت و پشتیبانی از اتوماسیون‌های مرتبط."
		),
		category="integration",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 250_000), ("yearly", 2_500_000)),
	),
	_PluginSeed(
		code="repair_shop_management",
		name="مدیریت تعمیرگاه",
		description=_REPAIR_SHOP_DESCRIPTION,
		category="operations",
		icon_url="/assets/icons/repair_shop.svg",
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 500_000), ("yearly", 5_000_000)),
	),
	_PluginSeed(
		code="product_warranty",
		name="گارانتی کالا",
		description="افزونه مدیریت گارانتی کالا — ثبت و پیگیری گارانتی محصولات فروخته‌شده",
		category="product_management",
		icon_url=None,
		trial_days=None,
		trial_allowed=False,
		plans=(("monthly", 100_000), ("yearly", 1_000_000)),
	),
	_PluginSeed(
		code="distribution",
		name="پخش مویرگی و ویزیتوری",
		description=(
			"مدیریت مسیرهای پخش، برنامه روز ویزیتور، ثبت ویزیت میدانی، "
			"مرجوعی و گزارش عملکرد با اتصال به CRM و اتوماسیون workflow."
		),
		category="sales",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 150_000), ("yearly", 1_500_000)),
	),
	_PluginSeed(
		code="woocommerce_hesabix",
		name="نمایش ووکامرس در حسابیکس",
		description=(
			"اتصال به افزونهٔ Hesabix V2 روی وردپرس: مشاهدهٔ سفارشات، محصولات و مشتریان فروشگاه "
			"از داخل حسابیکس از طریق پل REST امن (ArcWOC)."
		),
		category="integration",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 200_000), ("yearly", 2_000_000)),
	),
	_PluginSeed(
		code="customer_club",
		name="باشگاه مشتریان",
		description=(
			"مدیریت باشگاه وفاداری: امتیاز خودکار از فاکتور فروش، کسر متناسب با برگشت از فروش، "
			"دفتر تراکنش و تنظیمات قوانین امتیاز به ازای هر کسب‌وکار."
		),
		category="crm_marketing",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 120_000), ("yearly", 1_200_000)),
	),
)


def _resolve_currency_id(db: Session) -> Optional[int]:
	cur = db.query(Currency).filter(Currency.code == "IRR").first()
	if cur:
		return int(cur.id)
	cur = db.query(Currency).order_by(Currency.id.asc()).first()
	return int(cur.id) if cur else None


def ensure_default_marketplace_plugins(db: Session) -> Dict[str, Any]:
	"""
	ایجاد یا تکمیل افزونه‌ها و پلن‌های پیش‌فرض (idempotent).

	- افزونه موجود: فعال می‌شود، فیلدهای نمایشی از seed به‌روز می‌شوند (همسان با نصب تازه).
	- پلن موجود برای همان period: فعال می‌شود؛ قیمت و ارز دست‌نخورده می‌ماند.
	- پلن موجود نیست: با قیمت seed و ارز پیش‌فرض ایجاد می‌شود.
	"""
	now = datetime.utcnow()
	currency_id = _resolve_currency_id(db)
	if not currency_id:
		return {
			"ok": False,
			"error": "NO_CURRENCY",
			"message": "هیچ ارزی در سیستم ثبت نشده؛ ابتدا ارزها را seed کنید.",
		}

	created_plugins = 0
	updated_plugins = 0
	created_plans = 0
	reactivated_plans = 0
	codes: List[str] = []

	for spec in _DEFAULT_PLUGINS:
		codes.append(spec.code)
		row = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == spec.code).first()
		if row:
			updated_plugins += 1
			row.name = spec.name
			row.description = spec.description
			row.category = spec.category
			row.icon_url = spec.icon_url
			row.trial_days = spec.trial_days
			row.trial_allowed = spec.trial_allowed
			row.is_active = True
			row.updated_at = now
		else:
			created_plugins += 1
			row = MarketplacePlugin(
				code=spec.code,
				name=spec.name,
				description=spec.description,
				category=spec.category,
				icon_url=spec.icon_url,
				is_active=True,
				trial_days=spec.trial_days,
				trial_allowed=spec.trial_allowed,
			)
			db.add(row)
			db.flush()

		plugin_id = int(row.id)
		for period, default_price in spec.plans:
			plan = (
				db.query(MarketplacePluginPlan)
				.filter(
					MarketplacePluginPlan.plugin_id == plugin_id,
					MarketplacePluginPlan.period == period,
				)
				.first()
			)
			if plan:
				if not plan.is_active:
					plan.is_active = True
					plan.updated_at = now
					reactivated_plans += 1
				continue
			db.add(
				MarketplacePluginPlan(
					plugin_id=plugin_id,
					period=period,
					price=default_price,
					currency_id=currency_id,
					is_active=True,
				)
			)
			created_plans += 1

	return {
		"ok": True,
		"currency_id": currency_id,
		"plugin_codes": codes,
		"plugins_created": created_plugins,
		"plugins_updated": updated_plugins,
		"plans_created": created_plans,
		"plans_reactivated": reactivated_plans,
	}
