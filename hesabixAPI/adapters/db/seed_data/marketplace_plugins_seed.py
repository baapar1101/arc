"""Seed / sync پیش‌فرض افزونه‌های بازار (تک‌منبع برای migration و API همگام‌سازی)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from adapters.db.models.currency import Currency
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan


ADVANCED_ACCOUNTING_PLUGIN_CODE = "advanced_accounting"
AI_MCP_SERVER_PLUGIN_CODE = "ai_mcp_server"

_ADVANCED_ACCOUNTING_DESCRIPTION = """
بسته حسابداری پیشرفته برای حسابداران و کسب‌وکارهای حرفه‌ای:

✅ صورت‌های مالی: تراز آزمایشی، ترازنامه، سود و زیان دوره و تجمیعی
✅ دفاتر قانونی: دفتر کل، دفتر روزنامه و خروجی دفاتر الکترونیکی
✅ مرور حساب‌ها، صورت جریان وجوه نقد و بسته گزارش‌های مالی
✅ بستن سال مالی و برگردان سال مالی
✅ تسعیر ارز، نرخ‌گذاری، تسعیر پایان دوره و گزارش تسعیر
✅ راس‌گیری چک، تسهیلات دریافتی، سن بدهی و سن بستانکاری
✅ پشتیبان‌گیری کسب‌وکار، مقصد FTP و بازیابی داخل تنظیمات
✅ استودیو ساخت قالب فاکتور و اسناد

جدول حساب‌ها، اسناد، فاکتور و تراز افتتاحیه در نسخه پایه باقی می‌مانند.
""".strip()

_AI_MCP_SERVER_DESCRIPTION = """
اتصال امن دستیارهای خارجی هوش مصنوعی به داده همین کسب‌وکار از طریق MCP:

✅ اتصال ChatGPT، Claude، Cursor و کلاینت‌های سازگار با MCP
✅ خواندن و کار با فاکتور، کالا، اشخاص، خزانه، گزارش و سایر ابزارهای مجاز همان کاربر
✅ رضایت OAuth با انتخاب کسب‌وکار و ابزار؛ توکن محدود به همان کسب‌وکار
✅ اگر افزونه فعال نباشد یا اشتراک تمام شود، دستیار به داده دسترسی ندارد و این موضوع را به کاربر می‌گوید

چت داخل حسابیکس و API معمولی نرم‌افزار بدون این افزونه در دسترس می‌مانند.
ابزارهای افزونه‌های دیگر (حقوق، تعمیرگاه، بارکد و غیره) همچنان لایسنس خودشان را لازم دارند.
""".strip()

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
			"مدیریت مسیر و قلمرو، برنامه روز ویزیتور، ویزیت میدانی با GPS، "
			"فروش ون و پیش‌فروش، مرجوعی، تسویه روزانه با چک، تحویل با POD، "
			"پروموشن تجاری، پورسانت، KPI و اتصال به CRM/workflow."
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
		code="moadian_tax_integration",
		name="اتصال به سامانه مودیان",
		description=(
			"ارسال صورت‌حساب الکترونیکی به سامانه مودیان: کارپوشه مالیاتی، "
			"تنظیمات کلید و گواهی، ارسال/ابطال/اصلاحی، استعلام وضعیت و گزارش ارسال‌ها."
		),
		category="integration",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 350_000), ("yearly", 3_500_000), ("lifetime", 12_000_000)),
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
	_PluginSeed(
		code="payroll",
		name="حقوق و دستمزد",
		description=(
			"مدیریت جامع حقوق و دستمزد: تعریف انعطاف‌پذیر آیتم‌های حقوق (مزایا، کسورات، هزینه کارفرما) "
			"با نگاشت حساب از دفتر کل، ثبت پرسنل، دوره‌های حقوق، اجرای حقوق و صدور اسناد حسابداری."
		),
		category="hr_payroll",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 180_000), ("yearly", 1_800_000)),
	),
	_PluginSeed(
		code="fixed_assets",
		name="کنترل اموال و دارایی ثابت",
		description=(
			"دفتر معین اموال مستقل از انبار: تحصیل اثاثیه و دارایی برای استفاده داخلی، "
			"نگاشت به حساب‌های ۱۰۷/۱۰۸/۷۰۴، استهلاک خط مستقیم و مانده نزولی مطابق استاندارد ۱۱، "
			"و صدور سند دفتر کل جدا از فاکتور خرید کالا."
		),
		category="operations",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 220_000), ("yearly", 2_200_000)),
	),
	_PluginSeed(
		code="hscript_custom_reports",
		name="گزارش‌ساز اسکریپتی (HScript)",
		description=(
			"ساخت گزارش و داشبورد سفارشی با زبان امن HScript: KPI، جدول، نمودار، PDF و Excel. "
			"بدون لایسنس هم با سقف رایگان قابل استفاده است؛ با فعال‌سازی افزونه سقف ذخیره‌سازی و اجرا افزایش می‌یابد."
		),
		category="reporting",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 220_000), ("yearly", 2_200_000), ("lifetime", 8_800_000)),
	),
	_PluginSeed(
		code="asterisk_issabel_connector",
		name="اتصال به استریسک و ایزابل",
		description=(
			"یکپارچگی مرکز تلفن Issabel/Asterisk با حسابیکس: Screen Pop، Click-to-Call، "
			"تاریخچه تماس، نگاشت داخلی کاربران، اعلان لحظه‌ای و ثبت خودکار در CRM. "
			"نیاز به نصب Hesabix Telephony Connector روی سرور تلفن دارد."
		),
		category="integration",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 350_000), ("yearly", 3_500_000)),
	),
	_PluginSeed(
		code="digipay_credit",
		name="پرداخت اعتباری دیجی‌پی",
		description=(
			"پذیرش خرید اعتباری و اقساطی دیجی‌پی در فروش حضوری و آنلاین: تیکت UPG، "
			"ثبت طلب روی حساب دریافتنی شخص دیجی‌پی (۱۰۴۰۱) بدون بدهکار کردن بانک در لحظه فروش، "
			"و سند تسویهٔ دوره‌ای با کارمزد (۷۰۹۰۲) و مالیات ورودی کارمزد (۱۰۱۰۴)."
		),
		category="integration",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 250_000), ("yearly", 2_500_000)),
	),
	_PluginSeed(
		code="office_automation",
		name="اتوماسیون اداری",
		description=(
			"کارتابل سمت‌محور: نامه داخلی، وارده و صادره، پیش‌نویس، ارجاع، پاراف، "
			"پیوست، دبیرخانه، جانشین و چند سمت برای هر کاربر."
		),
		category="operations",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 280_000), ("yearly", 2_800_000)),
	),
	_PluginSeed(
		code="barcode_label_studio",
		name="طراحی و چاپ برچسب بارکد",
		description=(
			"استودیوی حرفه‌ای طراحی برچسب کالا: Drag & Drop، چند طرح ذخیره‌شونده، "
			"طرح پیش‌فرض، انواع بارکد استاندارد (Code128/39/93، EAN، QR، DataMatrix)، "
			"چینش سطر و ستون، چاپ از لیست کالا و اکسل سریالی. "
			"خروجی PDF دقیق با مقیاس میلی‌متر روی وب، ویندوز و اندروید."
		),
		category="product_management",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 180_000), ("yearly", 1_800_000), ("lifetime", 7_200_000)),
	),
	_PluginSeed(
		code=ADVANCED_ACCOUNTING_PLUGIN_CODE,
		name="بسته حسابداری پیشرفته",
		description=_ADVANCED_ACCOUNTING_DESCRIPTION,
		category="accounting",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 250_000), ("yearly", 2_500_000), ("lifetime", 9_000_000)),
	),
	_PluginSeed(
		code="advanced_production",
		name="افزونه تولید پیشرفته",
		description=(
			"گزارش‌های صنعتی تولید روی سفارش، فرمول ساخت و فاکتور تولید موجود: "
			"پیشرفت، عقب‌افتادگی، بهای گزارشی استاندارد/واقعی/میانگین، کسری مواد و انحراف مصرف. "
			"ثبت دفتر کل فاکتور تولید هسته بدون این افزونه تغییر نمی‌کند."
		),
		category="operations",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 220_000), ("yearly", 2_200_000)),
	),
	_PluginSeed(
		code=AI_MCP_SERVER_PLUGIN_CODE,
		name="سرور MCP هوش مصنوعی",
		description=_AI_MCP_SERVER_DESCRIPTION,
		category="integration",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 300_000), ("yearly", 3_000_000), ("lifetime", 10_000_000)),
	),
	_PluginSeed(
		code="procurement",
		name="مدیریت خرید و تدارکات",
		description="درخواست خرید، استعلام و مناقصه، سفارش، رسید و کنترل کیفیت، تطبیق سه‌جانبه، بودجه تعهدی، قرارداد و امتیاز تأمین‌کننده.",
		category="operations",
		icon_url=None,
		trial_days=14,
		trial_allowed=True,
		plans=(("monthly", 320_000), ("yearly", 3_200_000)),
	),
)


def _existing_columns(db: Session, table: str) -> Optional[set[str]]:
	getter = getattr(db, "get_bind", None)
	if getter is None:
		return None
	try:
		return {col["name"] for col in inspect(getter()).get_columns(table)}
	except Exception:
		return None


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

	plugin_columns = _existing_columns(db, "marketplace_plugins")
	for spec in _DEFAULT_PLUGINS:
		codes.append(spec.code)
		if plugin_columns is None:
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
					listed_in_marketplace=True,
					enabled_for_all_businesses=False,
					trial_days=spec.trial_days,
					trial_allowed=spec.trial_allowed,
				)
				db.add(row)
				db.flush()
			plugin_id = int(row.id)
		else:
			found = db.execute(text("SELECT id FROM marketplace_plugins WHERE code = :code"), {"code": spec.code}).first()
			if found:
				updated_plugins += 1
				values = {
					"name": spec.name,
					"description": spec.description,
					"category": spec.category,
					"icon_url": spec.icon_url,
					"trial_days": spec.trial_days,
					"trial_allowed": spec.trial_allowed,
					"is_active": True,
					"updated_at": now,
				}
				present = {key: value for key, value in values.items() if key in plugin_columns}
				assignments = ", ".join(f"{key} = :{key}" for key in present)
				db.execute(text(f"UPDATE marketplace_plugins SET {assignments} WHERE id = :id"), {**present, "id": int(found[0])})
				plugin_id = int(found[0])
			else:
				created_plugins += 1
				values = {
					"code": spec.code,
					"name": spec.name,
					"description": spec.description,
					"category": spec.category,
					"icon_url": spec.icon_url,
					"is_active": True,
					"listed_in_marketplace": True,
					"enabled_for_all_businesses": False,
					"trial_days": spec.trial_days,
					"trial_allowed": spec.trial_allowed,
					"created_at": now,
					"updated_at": now,
				}
				present = {key: value for key, value in values.items() if key in plugin_columns}
				columns = ", ".join(present)
				params = ", ".join(f":{key}" for key in present)
				inserted = db.execute(text(f"INSERT INTO marketplace_plugins ({columns}) VALUES ({params}) RETURNING id"), present).first()
				plugin_id = int(inserted[0])
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

	grandfather_result: Dict[str, Any] = {}
	if plugin_columns is not None and "listed_in_marketplace" not in plugin_columns:
		grandfather_result = {"ok": False, "skipped": "schema"}
	else:
		nested = db.begin_nested() if hasattr(db, "begin_nested") else None
		try:
			from app.services.moadian_grandfather_service import grant_moadian_grandfather_licenses

			grandfather_result = grant_moadian_grandfather_licenses(db)
			if nested is not None:
				nested.commit()
		except Exception as exc:  # noqa: BLE001
			if nested is not None:
				nested.rollback()
			grandfather_result = {"ok": False, "error": str(exc)}

	return {
		"ok": True,
		"currency_id": currency_id,
		"plugin_codes": codes,
		"plugins_created": created_plugins,
		"plugins_updated": updated_plugins,
		"plans_created": created_plans,
		"plans_reactivated": reactivated_plans,
		"moadian_grandfather": grandfather_result,
	}
