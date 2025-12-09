from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.openapi.docs import get_swagger_ui_html

from app.core.settings import get_settings
from app.core.logging import configure_logging
from adapters.db.session import get_db
from app.services.system_settings_service import get_app_name, get_app_version, is_maintenance_mode_enabled
from app.core.responses import ApiError
from adapters.api.v1.health import router as health_router
from adapters.api.v1.auth import router as auth_router
from adapters.api.v1.users import router as users_router
from adapters.api.v1.businesses import router as businesses_router
from adapters.api.v1.currencies import router as currencies_router
from adapters.api.v1.business_dashboard import router as business_dashboard_router
from adapters.api.v1.profile_dashboard import router as profile_dashboard_router
from adapters.api.v1.business_users import router as business_users_router
from adapters.api.v1.accounts import router as accounts_router
from adapters.api.v1.categories import router as categories_router
from adapters.api.v1.product_attributes import router as product_attributes_router
from adapters.api.v1.products import router as products_router
from adapters.api.v1.price_lists import router as price_lists_router
from adapters.api.v1.invoices import router as invoices_router
from adapters.api.v1.persons import router as persons_router
from adapters.api.v1.customers import router as customers_router
from adapters.api.v1.bank_accounts import router as bank_accounts_router
from adapters.api.v1.cash_registers import router as cash_registers_router
from adapters.api.v1.petty_cash import router as petty_cash_router
from adapters.api.v1.tax_units import router as tax_units_router
from adapters.api.v1.tax_types import router as tax_types_router
from adapters.api.v1.tax_product_codes import (
    router as tax_product_codes_router,
    admin_router as admin_tax_product_codes_router,
)
from adapters.api.v1.tax_settings import router as tax_settings_router
from adapters.api.v1.support.tickets import router as support_tickets_router
from adapters.api.v1.support.operator import router as support_operator_router
from adapters.api.v1.support.categories import router as support_categories_router
from adapters.api.v1.support.priorities import router as support_priorities_router
from adapters.api.v1.support.statuses import router as support_statuses_router
from adapters.api.v1.admin.file_storage import router as admin_file_storage_router
from adapters.api.v1.admin.email_config import router as admin_email_config_router
from adapters.api.v1.admin.system_settings import router as admin_system_settings_router
from adapters.api.v1.admin.monitoring import router as admin_monitoring_router
from adapters.api.v1.admin.system_services import router as admin_system_services_router
from adapters.api.v1.admin.wallet_admin import router as admin_wallet_router
from adapters.api.v1.admin.storage_plans import router as admin_storage_plans_router
from adapters.api.v1.admin.businesses_admin import router as admin_businesses_router
from adapters.api.v1.admin.document_monetization import router as admin_document_monetization_router
from adapters.api.v1.admin.zohal import router as admin_zohal_router
from adapters.api.v1.admin.marketplace import router as admin_marketplace_router
from adapters.api.v1.admin.users_permissions import router as admin_users_permissions_router
from adapters.api.v1.announcements import router as announcements_router
from adapters.api.v1.admin.announcements import router as admin_announcements_router
from adapters.api.v1.receipts_payments import router as receipts_payments_router
from adapters.api.v1.transfers import router as transfers_router
from adapters.api.v1.fiscal_years import router as fiscal_years_router
from adapters.api.v1.expense_income import router as expense_income_router
from adapters.api.v1.documents import router as documents_router
from adapters.api.v1.kardex import router as kardex_router
from adapters.api.v1.opening_balance import router as opening_balance_router
from adapters.api.v1.report_templates import router as report_templates_router
from adapters.api.v1.wallet import router as wallet_router
from adapters.api.v1.zohal import router as zohal_router
from adapters.api.v1.wallet_webhook import router as wallet_webhook_router
from adapters.api.v1.credit import router as credit_router
from adapters.api.v1.document_numbering import router as document_numbering_router
from adapters.api.v1.marketplace import router as marketplace_router
from adapters.api.v1.warranty import router as warranty_router
from adapters.api.v1.repair_shop import router as repair_shop_router
from adapters.api.v1.business_notifications import router as business_notifications_router
from adapters.api.v1.ping_pong import router as ping_pong_router
from adapters.api.v1.integrations.telegram import router as telegram_integration_router
from adapters.api.v1.notifications import router as notifications_router
from adapters.api.v1.admin.notification_templates import router as admin_notification_templates_router
from adapters.api.v1.admin.notification_moderation import router as admin_notification_moderation_router
from adapters.api.v1.notifications_ws import router as notifications_ws_router
from adapters.api.v1.public_share_links import router as public_share_links_router
from adapters.api.v1.business_backups import router as business_backups_router
from adapters.api.v1.business.document_monetization import router as business_document_monetization_router
from adapters.api.v1.jobs import router as jobs_router
from adapters.api.v1.activity_logs import router as activity_logs_router
from app.services.notification_processor import background_loop as notifications_background_loop
from app.services.storage_background_jobs import storage_cleanup_loop, storage_subscription_check_loop
from app.services.document_monetization_background_jobs import document_monetization_finalize_periods_loop
from app.services.document_monetization_jobs import document_monetization_loop
from app.services.monitoring_background_jobs import (
	monitoring_metrics_collection_loop,
	monitoring_service_status_check_loop,
)
from app.services.business_background_jobs import check_expired_deleted_businesses_loop
from app.core.i18n import negotiate_locale, Translator
from app.core.error_handlers import register_error_handlers
from app.core.smart_normalizer import smart_normalize_json, SmartNormalizerConfig
from app.core.calendar_middleware import add_calendar_type

# Import activity log hooks برای ثبت event handlers
import adapters.db.activity_log_hooks  # noqa: F401


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings)

    # خواندن تنظیمات از DB در صورت امکان، در غیر این صورت از env
    app_name = settings.app_name
    app_version = settings.app_version
    try:
        # تلاش برای خواندن از DB (در startup event به‌روزرسانی می‌شود)
        # استفاده از context manager برای اطمینان از بسته شدن session
        from adapters.db.session import get_db_session
        with get_db_session() as db:
            app_name = get_app_name(db)
            app_version = get_app_version(db)
    except Exception:
        # در صورت خطا از env استفاده می‌شود
        pass

    # تعریف tags برای دسته‌بندی بهتر endpoint ها در Swagger
    tags_metadata = [
        {
            "name": "احراز هویت",
            "description": """
عملیات مربوط به ثبت‌نام، ورود، خروج و مدیریت کلیدهای API

### امکانات:
- ثبت‌نام کاربر جدید با تایید ایمیل
- ورود با ایمیل/موبایل و رمز عبور
- مدیریت کلیدهای API شخصی و session
- فراموشی و بازیابی رمز عبور
- تغییر رمز عبور و اطلاعات کاربری
- سیستم کپچا برای امنیت
            """,
            "externalDocs": {
                "description": "راهنمای کامل احراز هویت",
                "url": "https://docs.hesabix.ir/authentication"
            }
        },
        {
            "name": "کاربران",
            "description": "مدیریت کاربران، پروفایل‌ها و دسترسی‌ها",
            "externalDocs": {
                "description": "مستندات مدیریت کاربران",
                "url": "https://docs.hesabix.ir/users"
            }
        },
        {
            "name": "کسب‌وکارها",
            "description": """
مدیریت کسب‌وکارها، تنظیمات و داشبورد

### قابلیت‌ها:
- ایجاد و مدیریت چندین کسب‌وکار
- تنظیمات شخصی‌سازی شده
- داشبورد آماری و تحلیلی
- مدیریت کاربران و نقش‌ها
            """,
            "externalDocs": {
                "description": "راهنمای کسب‌وکارها",
                "url": "https://docs.hesabix.ir/businesses"
            }
        },
        {
            "name": "محصولات و کالاها",
            "description": """
مدیریت محصولات، خدمات، دسته‌بندی‌ها و ویژگی‌ها

### امکانات:
- ثبت کالا و خدمات
- دسته‌بندی و ویژگی‌های محصول
- لیست قیمت‌گذاری
- موجودی و کنترل انبار
- بارکد و QR Code
            """,
            "externalDocs": {
                "description": "مستندات محصولات",
                "url": "https://docs.hesabix.ir/products"
            }
        },
        {
            "name": "انبارداری",
            "description": "مدیریت انبارها، موجودی، حواله‌ها و کاردکس",
            "externalDocs": {
                "description": "راهنمای انبارداری",
                "url": "https://docs.hesabix.ir/warehouse"
            }
        },
        {
            "name": "اسناد فروش",
            "description": """
فاکتورهای فروش، پیش‌فاکتور و اسناد مرتبط

### انواع اسناد:
- فاکتور فروش
- پیش‌فاکتور
- برگشت از فروش
- فروش سریع
            """,
            "externalDocs": {
                "description": "راهنمای فروش",
                "url": "https://docs.hesabix.ir/sales"
            }
        },
        {
            "name": "اسناد خرید",
            "description": "فاکتورهای خرید، سفارش خرید و اسناد مرتبط",
        },
        {
            "name": "اسناد انتقال",
            "description": """
اسناد انتقال وجه بین حساب‌های بانکی، صندوق و تنخواه

### کاربردها:
- انتقال بین حساب‌های بانکی
- انتقال به/از صندوق
- انتقال به/از تنخواه
- ثبت کارمزد انتقال
            """,
            "externalDocs": {
                "description": "راهنمای اسناد انتقال",
                "url": "https://docs.hesabix.ir/transfers"
            }
        },
        {
            "name": "دریافت و پرداخت",
            "description": """
اسناد دریافت و پرداخت نقدی، چک و سایر روش‌ها

### روش‌های پرداخت:
- نقدی
- چک
- کارت بانکی
- انتقال آنلاین
            """,
        },
        {
            "name": "مدیریت مالی",
            "description": "حساب‌های بانکی، صندوق، تنخواه، چک و سایر ابزارهای مالی",
        },
        {
            "name": "اشخاص و مشتریان",
            "description": "مدیریت اشخاص، مشتریان، تامین‌کنندگان و طرف‌حساب‌ها",
            "externalDocs": {
                "description": "راهنمای مدیریت اشخاص",
                "url": "https://docs.hesabix.ir/persons"
            }
        },
        {
            "name": "حسابداری",
            "description": """
دفتر کل، اسناد حسابداری، حساب‌ها و طبقات

### قابلیت‌ها:
- دفتر کل
- اسناد حسابداری
- طرح حساب‌ها
- تراز و میزان
            """,
            "externalDocs": {
                "description": "راهنمای حسابداری",
                "url": "https://docs.hesabix.ir/accounting"
            }
        },
        {
            "name": "گزارش‌ها",
            "description": """
گزارش‌های مالی، انبارداری، فروش و تحلیلی

### انواع گزارش:
- گزارش‌های مالی
- گزارش فروش و خرید
- گزارش موجودی و کاردکس
- گزارش‌های تحلیلی
- خروجی Excel و PDF
            """,
            "externalDocs": {
                "description": "راهنمای گزارش‌ها",
                "url": "https://docs.hesabix.ir/reports"
            }
        },
        {
            "name": "مالیات",
            "description": """
تنظیمات مالیاتی، نرخ‌ها، کدها و یکپارچه‌سازی با سامانه مودیان

### امکانات:
- تنظیمات مالیات بر ارزش افزوده
- یکپارچه‌سازی با سامانه مودیان
- کدهای مالیاتی محصولات
- گزارش‌های مالیاتی
            """,
            "externalDocs": {
                "description": "راهنمای مالیات و مودیان",
                "url": "https://docs.hesabix.ir/tax"
            }
        },
        {
            "name": "سال مالی",
            "description": "مدیریت سال‌های مالی و دوره‌های حسابداری",
        },
        {
            "name": "کیف پول",
            "description": "مدیریت کیف پول، شارژ، برداشت و تراکنش‌ها",
        },
        {
            "name": "اعتبار",
            "description": "مدیریت اعتبار و بسته‌های خریداری شده",
        },
        {
            "name": "قالب‌های گزارش",
            "description": """
مدیریت قالب‌های سفارشی برای گزارش‌ها و چاپ

### امکانات:
- طراحی قالب سفارشی
- قالب فاکتور
- قالب گزارش‌ها
- لوگو و مهر
            """,
        },
        {
            "name": "پشتیبانی",
            "description": "سیستم تیکت‌ها، درخواست‌ها و ارتباط با پشتیبانی",
        },
        {
            "name": "اطلاع‌رسانی",
            "description": "مدیریت نوتیفیکیشن‌ها، اعلان‌ها و پیام‌ها",
        },
        {
            "name": "پشتیبان‌گیری",
            "description": """
ایجاد، بازیابی و مدیریت نسخه‌های پشتیبان

### امکانات:
- پشتیبان‌گیری اتوماتیک
- پشتیبان‌گیری دستی
- بازیابی داده‌ها
- مدیریت فضای ذخیره‌سازی
            """,
        },
        {
            "name": "فایل و ذخیره‌سازی",
            "description": "مدیریت فایل‌ها، آپلود، دانلود و فضای ذخیره‌سازی",
        },
        {
            "name": "یکپارچه‌سازی",
            "description": """
اتصال به سرویس‌های خارجی (تلگرام، زوهال، مارکت‌پلیس)

### سرویس‌ها:
- یکپارچه‌سازی با تلگرام
- اتصال به سامانه زوهال
- اتصال به مارکت‌پلیس‌ها
            """,
        },
        {
            "name": "مدیریت سیستم",
            "description": """
تنظیمات سیستم، مانیتورینگ، لاگ‌ها و مدیریت کلی (فقط ادمین)

⚠️ این بخش فقط برای مدیران سیستم قابل دسترسی است
            """,
            "externalDocs": {
                "description": "راهنمای مدیریت سیستم",
                "url": "https://docs.hesabix.ir/admin"
            }
        },
        {
            "name": "هوش مصنوعی",
            "description": """
چت با هوش مصنوعی، تحلیل داده‌ها و پیشنهادات هوشمند

### امکانات:
- چت با دستیار هوشمند
- تحلیل داده‌های مالی
- پیشنهادات بهینه‌سازی
- گزارش‌های هوشمند
            """,
            "externalDocs": {
                "description": "راهنمای هوش مصنوعی",
                "url": "https://docs.hesabix.ir/ai"
            }
        },
    ]

    application = FastAPI(
        title=app_name,
        version=app_version,
        debug=settings.debug,
        openapi_tags=tags_metadata,
        docs_url=None,  # غیرفعال کردن docs پیش‌فرض برای سفارسی‌سازی
        redoc_url="/redoc",
        swagger_ui_parameters={
            "defaultModelsExpandDepth": -1,  # بسته بودن Models به صورت پیش‌فرض
            "docExpansion": "list",           # نمایش لیستی endpoints
            "filter": True,                   # فعال‌سازی جستجو
            "persistAuthorization": True,     # ذخیره توکن احراز هویت
            "displayRequestDuration": True,   # نمایش زمان پاسخ
            "tryItOutEnabled": True,          # فعال بودن Try it out
            "syntaxHighlight.theme": "monokai",  # تم Syntax Highlighting
            "deepLinking": True,              # Deep linking برای مستقیم رفتن به endpoint
            "displayOperationId": False,      # عدم نمایش Operation ID
        },
        description="""
        # Hesabix API

        API جامع برای مدیریت کاربران، احراز هویت و سیستم معرفی

        ## ویژگی‌های اصلی:
        - **احراز هویت**: ثبت‌نام، ورود، فراموشی رمز عبور
        - **مدیریت کاربران**: لیست، جستجو، فیلتر و آمار کاربران
        - **سیستم معرفی**: آمار و مدیریت معرفی‌ها
        - **خروجی**: PDF و Excel برای گزارش‌ها
        - **امنیت**: کپچا، کلیدهای API، رمزگذاری

        ## 🔐 احراز هویت (Authentication)

        ### کلیدهای API
        تمام endpoint های محافظت شده نیاز به کلید API دارند که در header `Authorization` ارسال می‌شود:

        ```
        Authorization: Bearer sk_your_api_key_here
        ```

        ### نحوه دریافت کلید API:
        1. **ثبت‌نام**: با ثبت‌نام، یک کلید session دریافت می‌کنید
        2. **ورود**: با ورود موفق، کلید session دریافت می‌کنید
        3. **کلیدهای شخصی**: از endpoint `/api/v1/auth/api-keys` می‌توانید کلیدهای شخصی ایجاد کنید

        ### انواع کلیدهای API:
        - **Session Keys**: کلیدهای موقت که با ورود ایجاد می‌شوند
        - **Personal Keys**: کلیدهای دائمی که خودتان ایجاد می‌کنید

        ### مثال درخواست با احراز هویت:
        ```bash
        curl -X GET "http://localhost:8000/api/v1/auth/me" \\
             -H "Authorization: Bearer sk_1234567890abcdef" \\
             -H "Accept: application/json"
        ```

        ## 🛡️ مجوزهای دسترسی (Permissions)

        برخی endpoint ها نیاز به مجوزهای خاص دارند:

        ### مجوزهای اپلیکیشن (App-Level Permissions):
        - `user_management`: دسترسی به مدیریت کاربران
        - `superadmin`: دسترسی کامل به سیستم
        - `business_management`: مدیریت کسب و کارها
        - `system_settings`: دسترسی به تنظیمات سیستم

        ### مثال مجوزها در JSON:
        ```json
        {
          "user_management": true,
          "superadmin": false,
          "business_management": true,
          "system_settings": false
        }
        ```

        ### endpoint های محافظت شده:
        - تمام endpoint های `/api/v1/users/*` نیاز به مجوز `user_management` دارند
        - endpoint های `/api/v1/auth/me` و `/api/v1/auth/api-keys/*` نیاز به احراز هویت دارند

        ## 🌍 چندزبانه (Internationalization)

        API از چندزبانه پشتیبانی می‌کند:

        ### هدر زبان:
        ```
        Accept-Language: fa
        Accept-Language: en
        Accept-Language: fa-IR
        Accept-Language: en-US
        ```

        ### زبان‌های پشتیبانی شده:
        - **فارسی (fa)**: پیش‌فرض
        - **انگلیسی (en)**

        ### مثال درخواست با زبان فارسی:
        ```bash
        curl -X GET "http://localhost:8000/api/v1/auth/me" \\
             -H "Authorization: Bearer sk_1234567890abcdef" \\
             -H "Accept-Language: fa" \\
             -H "Accept: application/json"
        ```

        ## 📅 تقویم (Calendar)

        API از تقویم شمسی (جلالی) پشتیبانی می‌کند:

        ### هدر تقویم:
        ```
        X-Calendar-Type: jalali
        X-Calendar-Type: gregorian
        ```

        ### انواع تقویم:
        - **جلالی (jalali)**: تقویم شمسی - پیش‌فرض
        - **میلادی (gregorian)**: تقویم میلادی

        ### مثال درخواست با تقویم شمسی:
        ```bash
        curl -X GET "http://localhost:8000/api/v1/users" \\
             -H "Authorization: Bearer sk_1234567890abcdef" \\
             -H "X-Calendar-Type: jalali" \\
             -H "Accept: application/json"
        ```

        ## 📊 فرمت پاسخ‌ها (Response Format)

        تمام پاسخ‌ها در فرمت زیر هستند:

        ```json
        {
          "success": true,
          "message": "پیام توضیحی",
          "data": {
            // داده‌های اصلی
          }
        }
        ```

        ### کدهای خطا:
        - **200**: موفقیت
        - **400**: خطا در اعتبارسنجی داده‌ها
        - **401**: احراز هویت نشده
        - **403**: دسترسی غیرمجاز
        - **404**: منبع یافت نشد
        - **422**: خطا در اعتبارسنجی
        - **500**: خطای سرور

        ## 🔒 امنیت (Security)

        ### کپچا:
        برای عملیات حساس از کپچا استفاده می‌شود:
        - دریافت کپچا: `POST /api/v1/auth/captcha`
        - استفاده در ثبت‌نام، ورود، فراموشی رمز عبور

        ### رمزگذاری:
        - رمزهای عبور با bcrypt رمزگذاری می‌شوند
        - کلیدهای API با SHA-256 هش می‌شوند

        ## 📝 مثال کامل درخواست:

        ```bash
        # 1. دریافت کپچا
        curl -X POST "http://localhost:8000/api/v1/auth/captcha"

        # 2. ورود
        curl -X POST "http://localhost:8000/api/v1/auth/login" \\
             -H "Content-Type: application/json" \\
             -H "Accept-Language: fa" \\
             -H "X-Calendar-Type: jalali" \\
             -d '{
               "identifier": "user@example.com",
               "password": "password123",
               "captcha_id": "captcha_id_from_step_1",
               "captcha_code": "12345"
             }'

        # 3. استفاده از API با کلید دریافتی
        curl -X GET "http://localhost:8000/api/v1/users" \\
             -H "Authorization: Bearer sk_1234567890abcdef" \\
             -H "Accept-Language: fa" \\
             -H "X-Calendar-Type: jalali" \\
             -H "Accept: application/json"
        ```

        ## 🚀 شروع سریع:

        1. **ثبت‌نام**: `POST /api/v1/auth/register`
        2. **ورود**: `POST /api/v1/auth/login`
        3. **دریافت اطلاعات کاربر**: `GET /api/v1/auth/me`
        4. **مدیریت کاربران**: `GET /api/v1/users` (نیاز به مجوز usermanager)

        ## 📞 پشتیبانی:
        - **ایمیل**: support@hesabix.ir
        - **مستندات**: `/docs` (Swagger UI)
        - **ReDoc**: `/redoc`
        """,
        contact={
            "name": "Hesabix Team",
            "email": "support@hesabix.ir",
            "url": "https://hesabix.ir",
        },
        license_info={
            "name": "GNU GPLv3 License",
            "url": "https://opensource.org/licenses/GPL-3.0",
        },
        servers=[
            {
                "url": "http://localhost:8000",
                "description": "Development server"
            },
            {
                "url": "https://agent.hesabix.ir",
                "description": "Production server"
            }
        ],
    )

    # Mount کردن فایل‌های استاتیک برای Swagger UI سفارشی
    try:
        application.mount("/assets", StaticFiles(directory="assets"), name="assets")
    except Exception:
        # در صورت نبود دایرکتوری assets، خطا را نادیده بگیر
        pass

    # Swagger UI سفارشی با استایل‌های فارسی و RTL
    @application.get("/docs", include_in_schema=False)
    async def custom_swagger_ui_html():
        """صفحه سفارشی Swagger UI با پشتیبانی کامل از فارسی و RTL"""
        return get_swagger_ui_html(
            openapi_url=application.openapi_url,
            title=f"{app_name} - مستندات API",
            oauth2_redirect_url=application.swagger_ui_oauth2_redirect_url,
            swagger_js_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js",
            swagger_css_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css",
            swagger_favicon_url="/assets/logo-blue.png",
            # لود CSS های سفارشی برای ظاهر حرفه‌ای و RTL
            custom_js_url=None,
            custom_css_url=None,  # از init_oauth استفاده می‌کنیم
        )

    # اضافه کردن CSS های سفارشی به صورت دستی
    @application.get("/docs-custom", include_in_schema=False, response_class=HTMLResponse)
    async def swagger_ui_custom():
        """صفحه Swagger UI با استایل‌های سفارشی حسابیکس"""
        return f"""
        <!DOCTYPE html>
        <html lang="fa" dir="rtl">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{app_name} - مستندات API</title>
            <link rel="icon" type="image/png" href="/assets/logo-blue.png">
            <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css">
            <link rel="stylesheet" type="text/css" href="/assets/swagger/custom.css">
            <link rel="stylesheet" type="text/css" href="/assets/swagger/swagger-rtl.css">
            <link rel="stylesheet" type="text/css" href="/assets/swagger/dark-mode.css">
            <style>
                html {{
                    box-sizing: border-box;
                    overflow: -moz-scrollbars-vertical;
                    overflow-y: scroll;
                }}
                *, *:before, *:after {{
                    box-sizing: inherit;
                }}
                body {{
                    margin:0;
                    padding:0;
                    background: #fafafa;
                }}
            </style>
        </head>
        <body>
            <div id="swagger-ui"></div>
            
            <!-- دکمه Toggle برای Dark Mode -->
            <button id="dark-mode-toggle" class="dark-mode-toggle" title="تغییر حالت تیره/روشن" aria-label="تغییر حالت تیره/روشن">
                <span id="dark-mode-icon">🌙</span>
            </button>
            <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
            <script>
                window.onload = function() {{
                    const ui = SwaggerUIBundle({{
                        url: "{application.openapi_url}",
                        dom_id: '#swagger-ui',
                        deepLinking: true,
                        presets: [
                            SwaggerUIBundle.presets.apis,
                            SwaggerUIStandalonePreset
                        ],
                        plugins: [
                            SwaggerUIBundle.plugins.DownloadUrl
                        ],
                        layout: "StandaloneLayout",
                        // پارامترهای سفارشی
                        defaultModelsExpandDepth: -1,
                        docExpansion: "list",
                        filter: true,
                        persistAuthorization: true,
                        displayRequestDuration: true,
                        tryItOutEnabled: true,
                        syntaxHighlight: {{
                            activate: true,
                            theme: "monokai"
                        }},
                        displayOperationId: false,
                        // تنظیمات OAuth (در صورت نیاز)
                        oauth2RedirectUrl: window.location.origin + "/docs/oauth2-redirect",
                        // پیکربندی‌های اضافی
                        requestInterceptor: function(req) {{
                            // می‌توانید request ها را اینجا تغییر دهید
                            return req;
                        }},
                        responseInterceptor: function(res) {{
                            // می‌توانید response ها را اینجا تغییر دهید
                            return res;
                        }}
                    }});
                    window.ui = ui;
                    
                    // Dark Mode Toggle
                    const darkModeToggle = document.getElementById('dark-mode-toggle');
                    const darkModeIcon = document.getElementById('dark-mode-icon');
                    const swaggerContainer = document.getElementById('swagger-ui');
                    
                    // بررسی تنظیمات ذخیره شده
                    const savedTheme = localStorage.getItem('swagger-theme');
                    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                    
                    // تنظیم theme اولیه
                    if (savedTheme === 'dark' || (!savedTheme && prefersDark)) {{
                        document.body.classList.add('dark-mode');
                        swaggerContainer.classList.add('dark-mode');
                        darkModeIcon.textContent = '☀️';
                    }}
                    
                    // Toggle Dark Mode
                    darkModeToggle.addEventListener('click', function() {{
                        document.body.classList.toggle('dark-mode');
                        swaggerContainer.classList.toggle('dark-mode');
                        
                        if (document.body.classList.contains('dark-mode')) {{
                            darkModeIcon.textContent = '☀️';
                            localStorage.setItem('swagger-theme', 'dark');
                        }} else {{
                            darkModeIcon.textContent = '🌙';
                            localStorage.setItem('swagger-theme', 'light');
                        }}
                    }});
                    
                    // شناسایی تغییر تنظیمات سیستم
                    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {{
                        if (!localStorage.getItem('swagger-theme')) {{
                            if (e.matches) {{
                                document.body.classList.add('dark-mode');
                                swaggerContainer.classList.add('dark-mode');
                                darkModeIcon.textContent = '☀️';
                            }} else {{
                                document.body.classList.remove('dark-mode');
                                swaggerContainer.classList.remove('dark-mode');
                                darkModeIcon.textContent = '🌙';
                            }}
                        }}
                    }});
                }};
            </script>
        </body>
        </html>
        """

    # Response Cache Middleware (بعد از CORS و قبل از authentication)
    from app.core.response_cache import ResponseCacheMiddleware
    application.add_middleware(ResponseCacheMiddleware)
    
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @application.middleware("http")
    async def smart_number_normalizer(request: Request, call_next):
        """Middleware هوشمند برای تبدیل اعداد فارسی/عربی به انگلیسی"""
        # فقط برای درخواست‌های POST/PUT/PATCH با Content-Type JSON اعمال شود
        if not SmartNormalizerConfig.ENABLED or request.method not in ["POST", "PUT", "PATCH"]:
            return await call_next(request)
        
        content_type = request.headers.get("Content-Type", "").lower()
        if not content_type.startswith("application/json"):
            return await call_next(request)
        
        # استثنا برای endpoint های خاص که نباید normalize شوند
        # endpoint های zohal که ممکن است JSON پیچیده یا داده‌های خاص داشته باشند
        path = request.url.path
        
        # اگر path مربوط به zohal است، از normalize کردن صرف نظر کن
        if "/zohal/" in path:
            return await call_next(request)
        
        # استفاده از receive wrapper برای خواندن و normalize کردن body
        original_receive = request._receive
        body_chunks = []
        normalized_body = None
        body_processed = False
        
        async def receive():
            nonlocal body_chunks, normalized_body, body_processed
            
            try:
                # اگر body قبلاً پردازش شده، از cache استفاده کن
                if body_processed:
                    if normalized_body is not None:
                        return {"type": "http.request", "body": normalized_body, "more_body": False}
                    return {"type": "http.request", "body": b"", "more_body": False}
                
                # خواندن body از stream
                message = await original_receive()
                
                if message["type"] == "http.request":
                    body_chunk = message.get("body", b"")
                    body_chunks.append(body_chunk)
                    
                    # اگر body کامل خوانده شد
                    if not message.get("more_body", False):
                        body_processed = True
                        body = b"".join(body_chunks)
                        
                        if body:
                            try:
                                # تبدیل اعداد در JSON
                                normalized_body = smart_normalize_json(body)
                            except Exception as e:
                                # در صورت خطا، body اصلی را استفاده کن
                                import logging
                                logger = logging.getLogger(__name__)
                                logger.warning(f"Error normalizing JSON body: {e}")
                                normalized_body = body
                        else:
                            normalized_body = b""
                        
                        return {"type": "http.request", "body": normalized_body, "more_body": False}
                
                return message
            except Exception as e:
                # در صورت خطا در receive، body اصلی را برگردان
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(f"Error in receive wrapper: {e}")
                # اگر body قبلاً خوانده شده، آن را برگردان
                if body_processed and body_chunks:
                    body = b"".join(body_chunks)
                    return {"type": "http.request", "body": body, "more_body": False}
                # در غیر این صورت، message خالی برگردان
                return {"type": "http.request", "body": b"", "more_body": False}
        
        # جایگزینی receive فقط برای درخواست‌های JSON
        request._receive = receive
        
        try:
            response = await call_next(request)
            return response
        except Exception as e:
            # در صورت خطا، receive اصلی را برگردان و خطا را propagate کن
            request._receive = original_receive
            raise
        finally:
            # همیشه receive اصلی را برگردان
            request._receive = original_receive

    @application.middleware("http")
    async def maintenance_mode_middleware(request: Request, call_next):
        """بررسی حالت تعمیرات - باید قبل از سایر middleware ها باشد"""
        # استثنا برای endpoint های health و admin system settings
        if request.url.path in ["/", "/health", "/api/v1/health"] or \
           request.url.path.startswith("/api/v1/admin/system-settings/configuration"):
            response = await call_next(request)
            return response
        
        # بررسی maintenance mode با cache
        from app.core.cache import get_cache
        cache = get_cache()
        cache_key = "system:maintenance_mode"
        cached_value = cache.get(cache_key)
        
        if cached_value is not None:
            maintenance_enabled = cached_value
        else:
            # اگر در cache نبود، از دیتابیس بخوان
            # استفاده از context manager برای اطمینان از بسته شدن session
            from adapters.db.session import get_db_session
            try:
                with get_db_session() as db:
                    maintenance_enabled = is_maintenance_mode_enabled(db)
            except Exception:
                # در صورت خطا، از cache یا مقدار پیش‌فرض استفاده کن
                maintenance_enabled = False
        
        if maintenance_enabled:
            # اجازه دسترسی به admin endpoints برای مدیریت maintenance mode
            if request.url.path.startswith("/api/v1/admin/system-settings"):
                response = await call_next(request)
                return response
            # برای سایر درخواست‌ها خطا برگردان
            from fastapi.responses import JSONResponse
            return JSONResponse(
                status_code=503,
                content={
                    "success": False,
                    "error_code": "MAINTENANCE_MODE",
                    "message": "سیستم در حال تعمیرات است. لطفاً بعداً تلاش کنید."
                }
            )
        
        response = await call_next(request)
        return response

    @application.middleware("http")
    async def add_locale(request: Request, call_next):
        # استفاده از default_language از DB در صورت نبود Accept-Language
        accept_language = request.headers.get("Accept-Language")
        lang = negotiate_locale(accept_language)
        
        # اگر زبان تشخیص داده نشد، از تنظیمات سیستم استفاده کن (با cache)
        if not accept_language:
            from app.core.cache import get_cache
            from app.services.system_settings_service import get_default_language
            cache = get_cache()
            cache_key = "system:default_language"
            cached_value = cache.get(cache_key)
            
            if cached_value is not None:
                lang = cached_value
            else:
                # اگر در cache نبود، از دیتابیس بخوان
                # استفاده از context manager برای اطمینان از بسته شدن session
                from adapters.db.session import get_db_session
                try:
                    with get_db_session() as db:
                        lang = get_default_language(db)
                except Exception:
                    pass
        
        request.state.locale = lang
        request.state.translator = Translator(lang)
        response = await call_next(request)
        return response

    @application.middleware("http")
    async def add_calendar_middleware(request: Request, call_next):
        return await add_calendar_type(request, call_next)

    application.include_router(health_router, prefix=settings.api_v1_prefix)
    application.include_router(auth_router, prefix=settings.api_v1_prefix)
    application.include_router(users_router, prefix=settings.api_v1_prefix)
    application.include_router(businesses_router, prefix=settings.api_v1_prefix)
    application.include_router(currencies_router, prefix=settings.api_v1_prefix)
    application.include_router(business_dashboard_router, prefix=settings.api_v1_prefix)
    application.include_router(profile_dashboard_router, prefix=settings.api_v1_prefix)
    application.include_router(business_users_router, prefix=settings.api_v1_prefix)
    application.include_router(accounts_router, prefix=settings.api_v1_prefix)
    application.include_router(categories_router, prefix=settings.api_v1_prefix)
    application.include_router(product_attributes_router, prefix=settings.api_v1_prefix)
    application.include_router(products_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.product_instances import router as product_instances_router
    application.include_router(product_instances_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.warehouse_docs import router as warehouse_docs_router
    application.include_router(warehouse_docs_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.warehouse_reports import router as warehouse_reports_router
    application.include_router(warehouse_reports_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.warehouses import router as warehouses_router
    application.include_router(warehouses_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.boms import router as boms_router
    application.include_router(boms_router, prefix=settings.api_v1_prefix)
    application.include_router(price_lists_router, prefix=settings.api_v1_prefix)
    application.include_router(invoices_router, prefix=settings.api_v1_prefix)
    application.include_router(persons_router, prefix=settings.api_v1_prefix)
    application.include_router(customers_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.projects import router as projects_router
    application.include_router(projects_router, prefix=settings.api_v1_prefix)
    application.include_router(bank_accounts_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.checks import router as checks_router
    application.include_router(checks_router, prefix=settings.api_v1_prefix)
    application.include_router(cash_registers_router, prefix=settings.api_v1_prefix)
    application.include_router(petty_cash_router, prefix=settings.api_v1_prefix)
    application.include_router(tax_units_router, prefix=settings.api_v1_prefix)
    application.include_router(tax_types_router, prefix=settings.api_v1_prefix)
    application.include_router(tax_product_codes_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_tax_product_codes_router, prefix=settings.api_v1_prefix)
    application.include_router(tax_settings_router, prefix=settings.api_v1_prefix)
    application.include_router(receipts_payments_router, prefix=settings.api_v1_prefix)
    application.include_router(transfers_router, prefix=settings.api_v1_prefix)
    application.include_router(expense_income_router, prefix=settings.api_v1_prefix)
    application.include_router(documents_router, prefix=settings.api_v1_prefix)
    application.include_router(fiscal_years_router, prefix=settings.api_v1_prefix)
    application.include_router(activity_logs_router, prefix=settings.api_v1_prefix)
    application.include_router(kardex_router, prefix=settings.api_v1_prefix)
    application.include_router(opening_balance_router, prefix=settings.api_v1_prefix)
    application.include_router(report_templates_router, prefix=settings.api_v1_prefix)
    application.include_router(wallet_router, prefix=settings.api_v1_prefix)
    application.include_router(zohal_router, prefix=settings.api_v1_prefix)
    application.include_router(wallet_webhook_router, prefix=settings.api_v1_prefix)
    application.include_router(credit_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.quick_sales import router as quick_sales_router
    application.include_router(quick_sales_router, prefix=settings.api_v1_prefix)
    application.include_router(document_numbering_router, prefix=settings.api_v1_prefix)
    application.include_router(marketplace_router, prefix=settings.api_v1_prefix)
    application.include_router(warranty_router, prefix=settings.api_v1_prefix)
    application.include_router(repair_shop_router, prefix=settings.api_v1_prefix)
    # Business Notifications
    application.include_router(business_notifications_router, prefix=settings.api_v1_prefix)
    # Ping Pong Game
    application.include_router(ping_pong_router, prefix=settings.api_v1_prefix)
    # Integrations
    application.include_router(telegram_integration_router, prefix=settings.api_v1_prefix)
    # Notifications
    application.include_router(notifications_router, prefix=settings.api_v1_prefix)
    application.include_router(notifications_ws_router)
    # Business backups
    application.include_router(business_backups_router, prefix=settings.api_v1_prefix)
    # Business storage
    from adapters.api.v1.business.storage import router as business_storage_router
    application.include_router(business_storage_router, prefix=settings.api_v1_prefix)
    application.include_router(business_document_monetization_router, prefix=settings.api_v1_prefix)
    # Jobs
    application.include_router(jobs_router, prefix=settings.api_v1_prefix)
    # Workflows
    from adapters.api.v1.workflows import router as workflows_router
    application.include_router(workflows_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.payment_gateways import router as payment_gateways_router
    application.include_router(payment_gateways_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.payment_callbacks import router as payment_callbacks_router
    application.include_router(payment_callbacks_router, prefix=settings.api_v1_prefix)
    # Announcements
    application.include_router(announcements_router, prefix=settings.api_v1_prefix)
    # Public share links (no prefix to allow short /p/{code})
    application.include_router(public_share_links_router)
    
    # Support endpoints
    application.include_router(support_tickets_router, prefix=f"{settings.api_v1_prefix}/support")
    application.include_router(support_operator_router, prefix=f"{settings.api_v1_prefix}/support/operator")
    from adapters.api.v1.support.ai_tickets import router as support_ai_router
    application.include_router(support_ai_router, prefix=settings.api_v1_prefix)
    application.include_router(support_categories_router, prefix=f"{settings.api_v1_prefix}/metadata/categories")
    application.include_router(support_priorities_router, prefix=f"{settings.api_v1_prefix}/metadata/priorities")
    application.include_router(support_statuses_router, prefix=f"{settings.api_v1_prefix}/metadata/statuses")
    
    # Admin endpoints
    application.include_router(admin_file_storage_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_email_config_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_system_settings_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_monitoring_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_system_services_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_wallet_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_storage_plans_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_businesses_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_users_permissions_router, prefix=settings.api_v1_prefix)
    from adapters.api.v1.admin.payment_gateways import router as admin_payment_gateways_router
    application.include_router(admin_payment_gateways_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_announcements_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_notification_templates_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_notification_moderation_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_document_monetization_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_zohal_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_marketplace_router, prefix=settings.api_v1_prefix)
    # AI endpoints
    from adapters.api.v1.admin.ai_settings import router as admin_ai_settings_router
    from adapters.api.v1.admin.ai_plans import router as admin_ai_plans_router
    from adapters.api.v1.admin.ai_prompts import router as admin_ai_prompts_router
    application.include_router(admin_ai_settings_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_ai_plans_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_ai_prompts_router, prefix=settings.api_v1_prefix)
    # User AI endpoints
    from adapters.api.v1.ai.chat import router as ai_chat_router
    from adapters.api.v1.ai.subscription import router as ai_subscription_router
    from adapters.api.v1.ai.prompts import router as ai_prompts_router
    from adapters.api.v1.ai.usage import router as ai_usage_router
    application.include_router(ai_chat_router, prefix=settings.api_v1_prefix)
    application.include_router(ai_subscription_router, prefix=settings.api_v1_prefix)
    application.include_router(ai_prompts_router, prefix=settings.api_v1_prefix)
    application.include_router(ai_usage_router, prefix=settings.api_v1_prefix)

    register_error_handlers(application)

    # Start background notification outbox processor
    import asyncio
    @application.on_event("startup")
    async def _start_background_jobs():
        asyncio.create_task(notifications_background_loop(30))
        # Storage cleanup: هر 24 ساعت یکبار
        asyncio.create_task(storage_cleanup_loop(24))
        # Subscription check: هر 6 ساعت یکبار
        asyncio.create_task(storage_subscription_check_loop(6))
        # Document monetization processor
        asyncio.create_task(document_monetization_loop(10))
        # Document monetization period finalization: هر 24 ساعت یکبار
        asyncio.create_task(document_monetization_finalize_periods_loop(24))
        # AI background jobs
        from app.services.ai_background_jobs import (
            ai_quota_reset_loop,
            ai_chat_cleanup_loop,
            ai_subscription_check_loop
        )
        # AI quota reset: هر 24 ساعت یکبار
        asyncio.create_task(ai_quota_reset_loop(24))
        # AI chat cleanup: هر 24 ساعت یکبار
        asyncio.create_task(ai_chat_cleanup_loop(24))
        # AI subscription check: هر 6 ساعت یکبار
        asyncio.create_task(ai_subscription_check_loop(6))
        # Notification moderation: هر 60 ثانیه یکبار
        from app.workers.notification_moderation_worker import run_worker_loop
        asyncio.create_task(run_worker_loop(60))
        # Monitoring metrics collection: هر 60 ثانیه (افزایش برای کاهش فشار روی connection pool)
        asyncio.create_task(monitoring_metrics_collection_loop(60))
        # Service status check: هر 120 ثانیه (افزایش برای کاهش فشار روی connection pool)
        asyncio.create_task(monitoring_service_status_check_loop(120))
        # Business deletion check: هر 24 ساعت یکبار (فقط لاگ - حذف نمی‌کند)
        asyncio.create_task(check_expired_deleted_businesses_loop(24))

    @application.middleware("http")
    async def global_rate_limit_middleware(request: Request, call_next):
        import time
        """Rate limiting عمومی برای تمام endpoint ها"""
        # استثنا برای health check و static files
        if request.url.path in ["/", "/health", "/api/v1/health"] or \
           request.url.path.startswith("/docs") or \
           request.url.path.startswith("/redoc") or \
           request.url.path.startswith("/openapi.json"):
            return await call_next(request)
        
        from app.core.rate_limiter import get_rate_limiter, get_client_ip
        
        # Rate limiting عمومی: 100 request در دقیقه برای هر IP
        client_ip = get_client_ip(request)
        rate_limit_key = f"global:{client_ip}"
        
        limiter = get_rate_limiter()
        allowed, remaining, reset_after = limiter.check_rate_limit(
            rate_limit_key,
            max_requests=100,
            window_seconds=60,
        )
        
        if not allowed:
            from fastapi.responses import JSONResponse
            return JSONResponse(
                status_code=429,
                content={
                    "success": False,
                    "error_code": "RATE_LIMIT_EXCEEDED",
                    "message": "تعداد درخواست‌های شما بیش از حد مجاز است. لطفاً کمی صبر کنید."
                },
                headers={
                    "X-RateLimit-Limit": "100",
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": str(int(time.time()) + reset_after),
                    "Retry-After": str(reset_after),
                }
            )
        
        response = await call_next(request)
        
        # اضافه کردن rate limit headers
        if hasattr(response, 'headers'):
            response.headers["X-RateLimit-Limit"] = "100"
            response.headers["X-RateLimit-Remaining"] = str(remaining)
            response.headers["X-RateLimit-Reset"] = str(int(time.time()) + reset_after)
        
        return response

    @application.middleware("http")
    async def log_slow_requests(request: Request, call_next):
        import time
        import structlog
        from app.core.monitoring import get_performance_monitor
        
        start = time.perf_counter()
        status_code = 200
        user_id = None
        
        try:
            response = await call_next(request)
            
            # تلاش برای دریافت status code از response
            if hasattr(response, 'status_code'):
                status_code = response.status_code
            
            return response
        except Exception as e:
            status_code = getattr(e, 'http_status', 500) if hasattr(e, 'http_status') else 500
            raise
        finally:
            duration_ms = (time.perf_counter() - start) * 1000
            
            # ثبت در monitoring
            monitor = get_performance_monitor()
            monitor.record_request(
                method=request.method,
                path=str(request.url.path),
                duration_ms=duration_ms,
                status_code=status_code,
                user_id=user_id,
            )
            
            # Log slow requests
            if duration_ms > 2000:
                logger = structlog.get_logger()
                logger.warning(
                    "slow_request",
                    path=str(request.url.path),
                    method=request.method,
                    duration_ms=duration_ms,
                    status_code=status_code,
                )

    @application.get("/", 
        summary="اطلاعات سرویس",
        description="دریافت اطلاعات کلی سرویس و نسخه",
        tags=["general"]
    )
    def read_root() -> dict[str, str]:
        # خواندن از DB در هر درخواست برای به‌روز بودن
        # استفاده از context manager برای اطمینان از بسته شدن session
        from adapters.db.session import get_db_session
        with get_db_session() as db:
            current_app_name = get_app_name(db)
            current_app_version = get_app_version(db)
            return {"service": current_app_name, "version": current_app_version}
    
    # اضافه کردن security schemes
    from fastapi.openapi.utils import get_openapi
    
    def custom_openapi():
        if application.openapi_schema:
            return application.openapi_schema
        
        openapi_schema = get_openapi(
            title=application.title,
            version=application.version,
            description=application.description,
            routes=application.routes,
        )
        
        # اضافه کردن security schemes با مستندات کامل
        openapi_schema["components"]["securitySchemes"] = {
            "ApiKeyAuth": {
                "type": "apiKey",
                "in": "header",
                "name": "Authorization",
                "description": """
## 🔐 احراز هویت با کلید API

کلید API برای دسترسی به تمام endpoint های محافظت شده استفاده می‌شود.

### فرمت Header:
```
Authorization: Bearer sk_your_api_key_here
```

### انواع کلید API:

#### 1️⃣ Session Keys (کلیدهای موقت)
- با ورود یا ثبت‌نام ایجاد می‌شوند
- معمولاً 30 روز اعتبار دارند
- به صورت خودکار با خروج باطل می‌شوند
- فرمت: `sk_session_...`

#### 2️⃣ Personal Keys (کلیدهای دائمی)
- توسط کاربر ایجاد می‌شوند
- بدون تاریخ انقضا (تا زمان حذف توسط کاربر)
- می‌توان محدودیت IP تعریف کرد
- فرمت: `sk_personal_...`

### نحوه دریافت کلید:

**روش 1: ثبت‌نام**
```bash
POST /api/v1/auth/register
```

**روش 2: ورود**
```bash
POST /api/v1/auth/login
```

**روش 3: ایجاد کلید شخصی**
```bash
POST /api/v1/auth/api-keys
```

### مثال استفاده:
```bash
curl -X GET "https://agent.hesabix.ir/api/v1/auth/me" \\
  -H "Authorization: Bearer sk_1234567890abcdef" \\
  -H "Accept-Language: fa" \\
  -H "X-Calendar-Type: jalali"
```

### نکات امنیتی:
- ⚠️ کلید API را در کد خود hardcode نکنید
- 🔒 از متغیرهای محیطی استفاده کنید
- 🛡️ کلید را با دیگران به اشتراک نگذارید
- 🔄 به صورت دوره‌ای کلیدهای قدیمی را حذف کنید
- 📱 برای هر اپلیکیشن یک کلید جداگانه استفاده کنید
                """,
                "x-displayName": "کلید API (API Key)"
            },
            "BearerAuth": {
                "type": "http",
                "scheme": "bearer",
                "bearerFormat": "API Key",
                "description": """
احراز هویت با Bearer Token

این همان ApiKeyAuth است، فقط با فرمت استاندارد HTTP Bearer.
                """
            }
        }
        
        # اضافه کردن توضیحات برای security requirements
        if "security" not in openapi_schema:
            openapi_schema["security"] = []
        
        # اضافه کردن security به endpoint های محافظت شده
        for path, methods in openapi_schema["paths"].items():
            for method, details in methods.items():
                if method in ["get", "post", "put", "delete", "patch"]:
                    # تمام endpoint های auth، users، support و bank-accounts نیاز به احراز هویت دارند
                    if "/auth/" in path or "/users" in path or "/support" in path or "/bank-accounts" in path:
                        details["security"] = [{"ApiKeyAuth": []}]
        
        application.openapi_schema = openapi_schema
        return application.openapi_schema
    
    application.openapi = custom_openapi
    
    return application


app = create_app()


