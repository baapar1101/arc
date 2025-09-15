from fastapi import FastAPI

from app.core.settings import get_settings
from app.core.logging import configure_logging
from adapters.api.v1.health import router as health_router


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings)

    application = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        debug=settings.debug,
    )

    application.include_router(health_router, prefix=settings.api_v1_prefix)

    @application.get("/")
    def read_root() -> dict[str, str]:
        return {"service": settings.app_name, "version": settings.app_version}

    return application


app = create_app()


