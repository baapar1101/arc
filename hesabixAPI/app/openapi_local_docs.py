"""تولید HTML برای Swagger UI با فایل‌های استاتیک داخل پروژه (بدون CDN)."""

from __future__ import annotations

import json
from typing import Any

from fastapi.encoders import jsonable_encoder
from fastapi.openapi.docs import swagger_ui_default_parameters
from starlette.responses import HTMLResponse


def _html_safe_json(value: Any) -> str:
    """همان رفتار FastAPI برای embed امن JSON در تگ script."""
    return (
        json.dumps(value)
        .replace("<", "\\u003c")
        .replace(">", "\\u003e")
        .replace("&", "\\u0026")
    )


SWAGGER_UI_VENDOR_BASE = "/assets/swagger/vendor"


def get_local_swagger_ui_html(
    *,
    openapi_url: str,
    title: str,
    oauth2_redirect_url: str | None = None,
    init_oauth: dict[str, Any] | None = None,
    swagger_ui_parameters: dict[str, Any] | None = None,
    swagger_favicon_url: str = "/assets/logo-blue.png",
) -> HTMLResponse:
    """
    مانند fastapi.openapi.docs.get_swagger_ui_html با این تفاوت که JS/CSS از
    /assets/swagger/vendor سرو می‌شود و preset جداگانه (نسخهٔ swagger-ui-dist معمولاً
    دو فایل bundle + standalone-preset) بارگذاری می‌شود.
    """
    css_url = f"{SWAGGER_UI_VENDOR_BASE}/swagger-ui.css"
    bundle_js = f"{SWAGGER_UI_VENDOR_BASE}/swagger-ui-bundle.js"
    standalone_js = f"{SWAGGER_UI_VENDOR_BASE}/swagger-ui-standalone-preset.js"

    current_swagger_ui_parameters = swagger_ui_default_parameters.copy()
    if swagger_ui_parameters:
        current_swagger_ui_parameters.update(swagger_ui_parameters)

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link type="text/css" rel="stylesheet" href="{css_url}">
    <link rel="shortcut icon" href="{swagger_favicon_url}">
    <title>{title}</title>
    </head>
    <body>
    <div id="swagger-ui">
    </div>
    <script src="{bundle_js}"></script>
    <script src="{standalone_js}"></script>
    <script>
    const ui = SwaggerUIBundle({{
        url: '{openapi_url}',
    """

    for key, value in current_swagger_ui_parameters.items():
        html += f"{_html_safe_json(key)}: {_html_safe_json(jsonable_encoder(value))},\n"

    if oauth2_redirect_url:
        html += f"oauth2RedirectUrl: window.location.origin + '{oauth2_redirect_url}',"

    html += """
    presets: [
        SwaggerUIBundle.presets.apis,
        SwaggerUIStandalonePreset
        ],
    })"""

    if init_oauth:
        html += f"""
        ui.initOAuth({_html_safe_json(jsonable_encoder(init_oauth))})
        """

    html += """
    </script>
    </body>
    </html>
    """
    return HTMLResponse(html)
