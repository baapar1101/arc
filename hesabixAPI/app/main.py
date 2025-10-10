from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.core.settings import get_settings
from app.core.logging import configure_logging
from adapters.api.v1.health import router as health_router
from adapters.api.v1.auth import router as auth_router
from adapters.api.v1.users import router as users_router
from adapters.api.v1.businesses import router as businesses_router
from adapters.api.v1.currencies import router as currencies_router
from adapters.api.v1.business_dashboard import router as business_dashboard_router
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
from adapters.api.v1.support.tickets import router as support_tickets_router
from adapters.api.v1.support.operator import router as support_operator_router
from adapters.api.v1.support.categories import router as support_categories_router
from adapters.api.v1.support.priorities import router as support_priorities_router
from adapters.api.v1.support.statuses import router as support_statuses_router
from adapters.api.v1.admin.file_storage import router as admin_file_storage_router
from adapters.api.v1.admin.email_config import router as admin_email_config_router
from app.core.i18n import negotiate_locale, Translator
from app.core.error_handlers import register_error_handlers
from app.core.smart_normalizer import smart_normalize_json, SmartNormalizerConfig
from app.core.calendar_middleware import add_calendar_type


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings)

    application = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        debug=settings.debug,
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
        if SmartNormalizerConfig.ENABLED and request.method in ["POST", "PUT", "PATCH"]:
            # فقط برای درخواست‌های JSON اعمال شود تا فایل‌های باینری/چندبخشی خراب نشوند
            content_type = request.headers.get("Content-Type", "").lower()
            if content_type.startswith("application/json"):
                # خواندن body درخواست
                body = await request.body()
                if body:
                    # تبدیل اعداد در JSON
                    normalized_body = smart_normalize_json(body)
                    if normalized_body != body:
                        # ایجاد request جدید با body تبدیل شده
                        request._body = normalized_body
        
        response = await call_next(request)
        return response

    @application.middleware("http")
    async def add_locale(request: Request, call_next):
        lang = negotiate_locale(request.headers.get("Accept-Language"))
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
    application.include_router(business_users_router, prefix=settings.api_v1_prefix)
    application.include_router(accounts_router, prefix=settings.api_v1_prefix)
    application.include_router(categories_router, prefix=settings.api_v1_prefix)
    application.include_router(product_attributes_router, prefix=settings.api_v1_prefix)
    application.include_router(products_router, prefix=settings.api_v1_prefix)
    application.include_router(price_lists_router, prefix=settings.api_v1_prefix)
    application.include_router(invoices_router, prefix=settings.api_v1_prefix)
    application.include_router(persons_router, prefix=settings.api_v1_prefix)
    application.include_router(customers_router, prefix=settings.api_v1_prefix)
    application.include_router(bank_accounts_router, prefix=settings.api_v1_prefix)
    application.include_router(cash_registers_router, prefix=settings.api_v1_prefix)
    application.include_router(petty_cash_router, prefix=settings.api_v1_prefix)
    application.include_router(tax_units_router, prefix=settings.api_v1_prefix)
    application.include_router(tax_types_router, prefix=settings.api_v1_prefix)
    
    # Support endpoints
    application.include_router(support_tickets_router, prefix=f"{settings.api_v1_prefix}/support")
    application.include_router(support_operator_router, prefix=f"{settings.api_v1_prefix}/support/operator")
    application.include_router(support_categories_router, prefix=f"{settings.api_v1_prefix}/metadata/categories")
    application.include_router(support_priorities_router, prefix=f"{settings.api_v1_prefix}/metadata/priorities")
    application.include_router(support_statuses_router, prefix=f"{settings.api_v1_prefix}/metadata/statuses")
    
    # Admin endpoints
    application.include_router(admin_file_storage_router, prefix=settings.api_v1_prefix)
    application.include_router(admin_email_config_router, prefix=settings.api_v1_prefix)

    register_error_handlers(application)

    @application.get("/", 
        summary="اطلاعات سرویس",
        description="دریافت اطلاعات کلی سرویس و نسخه",
        tags=["general"]
    )
    def read_root() -> dict[str, str]:
        return {"service": settings.app_name, "version": settings.app_version}
    
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
        
        # اضافه کردن security schemes
        openapi_schema["components"]["securitySchemes"] = {
            "ApiKeyAuth": {
                "type": "apiKey",
                "in": "header",
                "name": "Authorization",
                "description": "کلید API برای احراز هویت. فرمت: ApiKey sk_your_api_key_here"
            }
        }
        
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


