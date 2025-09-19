from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.core.settings import get_settings
from app.core.logging import configure_logging
from adapters.api.v1.health import router as health_router
from adapters.api.v1.auth import router as auth_router
from adapters.api.v1.users import router as users_router
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

    register_error_handlers(application)

    @application.get("/")
    def read_root() -> dict[str, str]:
        return {"service": settings.app_name, "version": settings.app_version}

    return application


app = create_app()


