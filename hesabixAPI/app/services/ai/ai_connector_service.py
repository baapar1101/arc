"""
کانکتورهای HTTP خارجی — فراخوانی APIهای سفارشی کسب‌وکار توسط AI.
"""
from __future__ import annotations

import json
import logging
import re
import ipaddress
import socket
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

import httpx
from sqlalchemy.orm import Session

from adapters.db.models.ai_connector import AIConnector
from app.core.responses import ApiError

logger = logging.getLogger(__name__)

MAX_RESPONSE_CHARS = 16_000
REQUEST_TIMEOUT = 25.0
ALLOWED_METHODS = {"GET", "POST"}
ALLOWED_SCHEMES = {"http", "https"}
METADATA_HOSTS = {
    "metadata.google.internal",
}
METADATA_IPS = {
    "169.254.169.254",  # AWS/GCP/Azure metadata endpoint
}


def _slug_name(name: str) -> str:
    s = re.sub(r"[^\w\u0600-\u06FF-]+", "_", (name or "").strip().lower())
    return s[:128] or "connector"


def _mask_secret(value: str) -> str:
    if not value:
        return ""
    if len(value) <= 8:
        return "••••"
    return f"{value[:4]}…{value[-4:]}"


def _mask_headers(headers: Dict[str, Any]) -> Dict[str, str]:
    secretish = ("authorization", "api-key", "apikey", "token", "secret", "password", "cookie")
    masked: Dict[str, str] = {}
    for key, value in headers.items():
        k = str(key)
        v = str(value)
        masked[k] = _mask_secret(v) if any(part in k.lower() for part in secretish) else v
    return masked


def _is_blocked_ip(host: str) -> bool:
    try:
        addr = ipaddress.ip_address(host)
    except ValueError:
        return False
    if str(addr) in METADATA_IPS:
        return True
    return not addr.is_global


def _validate_connector_url(url: str) -> str:
    candidate = (url or "").strip()
    if not candidate:
        raise ApiError("INVALID_URL", "آدرس URL الزامی است", http_status=400)
    parsed = urlparse(candidate)
    if parsed.scheme.lower() not in ALLOWED_SCHEMES:
        raise ApiError("INVALID_URL", "فقط آدرس‌های http و https مجاز هستند", http_status=400)
    if not parsed.hostname:
        raise ApiError("INVALID_URL", "دامنه URL معتبر نیست", http_status=400)
    if parsed.username or parsed.password:
        raise ApiError("INVALID_URL", "استفاده از نام کاربری/رمز در URL مجاز نیست", http_status=400)
    if "{{" in parsed.netloc or "}}" in parsed.netloc:
        raise ApiError(
            "INVALID_URL",
            "قالب‌گذاری فقط در مسیر یا query مجاز است، نه دامنه",
            http_status=400,
        )

    host = parsed.hostname.strip().lower().rstrip(".")
    if host in {"localhost", "localhost.localdomain"} or host.endswith(".localhost"):
        raise ApiError("CONNECTOR_HOST_BLOCKED", "اتصال به localhost مجاز نیست", http_status=400)
    if host in METADATA_HOSTS:
        raise ApiError("CONNECTOR_HOST_BLOCKED", "اتصال به آدرس metadata مجاز نیست", http_status=400)
    if _is_blocked_ip(host):
        raise ApiError("CONNECTOR_HOST_BLOCKED", "اتصال به IP داخلی یا غیرعمومی مجاز نیست", http_status=400)

    try:
        infos = socket.getaddrinfo(host, parsed.port or (443 if parsed.scheme == "https" else 80))
    except socket.gaierror as exc:
        raise ApiError("INVALID_URL", "دامنه URL قابل resolve نیست", http_status=400) from exc
    for info in infos:
        resolved_ip = info[4][0]
        if _is_blocked_ip(resolved_ip):
            raise ApiError(
                "CONNECTOR_HOST_BLOCKED",
                "دامنه کانکتور به IP داخلی یا غیرعمومی resolve می‌شود",
                http_status=400,
            )
    return candidate


def list_connectors(db: Session, business_id: int) -> List[AIConnector]:
    return (
        db.query(AIConnector)
        .filter(
            AIConnector.business_id == business_id,
            AIConnector.is_active == True,  # noqa: E712
        )
        .order_by(AIConnector.title.asc())
        .all()
    )


def connector_to_dict(row: AIConnector, include_secrets: bool = False) -> Dict[str, Any]:
    headers = {}
    if row.headers_json:
        try:
            headers = json.loads(row.headers_json)
        except json.JSONDecodeError:
            headers = {}
    d: Dict[str, Any] = {
        "id": row.id,
        "business_id": row.business_id,
        "name": row.name,
        "title": row.title,
        "description": row.description,
        "http_method": row.http_method,
        "url": row.url,
        "is_active": row.is_active,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }
    if include_secrets:
        d["headers"] = _mask_headers(headers)
        d["body_template"] = "***" if row.body_template else None
    else:
        d["has_headers"] = bool(headers)
        d["has_body_template"] = bool(row.body_template)
    return d


def create_connector(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> AIConnector:
    method = (data.get("http_method") or "GET").upper()
    if method not in ALLOWED_METHODS:
        raise ApiError("INVALID_METHOD", "فقط GET و POST مجاز است", http_status=400)
    name = _slug_name(data.get("name") or data.get("title", ""))
    existing = (
        db.query(AIConnector)
        .filter(AIConnector.business_id == business_id, AIConnector.name == name)
        .first()
    )
    if existing:
        raise ApiError("DUPLICATE_NAME", "نام کانکتور تکراری است", http_status=400)

    headers_json = None
    if data.get("headers"):
        headers_json = json.dumps(data["headers"], ensure_ascii=False)

    validated_url = _validate_connector_url((data.get("url") or "").strip())

    row = AIConnector(
        business_id=business_id,
        user_id=user_id,
        name=name,
        title=(data.get("title") or name)[:512],
        description=data.get("description"),
        http_method=method,
        url=validated_url,
        headers_json=headers_json,
        body_template=data.get("body_template"),
        is_active=True,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def delete_connector(db: Session, connector_id: int, business_id: int) -> bool:
    row = (
        db.query(AIConnector)
        .filter(AIConnector.id == connector_id, AIConnector.business_id == business_id)
        .first()
    )
    if not row:
        return False
    db.delete(row)
    db.commit()
    return True


def format_connectors_for_prompt(db: Session, business_id: int) -> str:
    rows = list_connectors(db, business_id)
    if not rows:
        return ""
    lines = [
        "\n\n--- کانکتورهای خارجی (با invoke_business_connector فراخوانی کن) ---"
    ]
    for r in rows:
        desc = r.description or ""
        lines.append(f"- {r.name}: {r.title} — {r.http_method} {r.url}")
        if desc:
            lines.append(f"  توضیح: {desc[:300]}")
    return "\n".join(lines)


def _render_template(template: Optional[str], params: Dict[str, Any]) -> Optional[str]:
    if not template:
        return None
    out = template
    for key, val in params.items():
        out = out.replace("{{" + key + "}}", str(val))
    return out


def invoke_connector(
    db: Session,
    business_id: int,
    connector_name: str,
    query_params: Optional[Dict[str, Any]] = None,
    body: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    name = _slug_name(connector_name)
    row = (
        db.query(AIConnector)
        .filter(
            AIConnector.business_id == business_id,
            AIConnector.name == name,
            AIConnector.is_active == True,  # noqa: E712
        )
        .first()
    )
    if not row:
        raise ApiError("CONNECTOR_NOT_FOUND", f"کانکتور '{connector_name}' یافت نشد", http_status=404)

    headers: Dict[str, str] = {}
    if row.headers_json:
        try:
            raw = json.loads(row.headers_json)
            if isinstance(raw, dict):
                headers = {str(k): str(v) for k, v in raw.items()}
        except json.JSONDecodeError:
            pass

    params = query_params or {}
    method = row.http_method.upper()
    url = _validate_connector_url(_render_template(row.url, params) or row.url)

    try:
        with httpx.Client(timeout=REQUEST_TIMEOUT, follow_redirects=False) as client:
            if method == "GET":
                resp = client.get(url, headers=headers, params=params)
            else:
                body_data = body
                if body_data is None and row.body_template:
                    rendered = _render_template(row.body_template, params)
                    if rendered:
                        try:
                            body_data = json.loads(rendered)
                        except json.JSONDecodeError:
                            body_data = rendered
                resp = client.post(url, headers=headers, json=body_data, params=params)
    except ApiError:
        raise
    except httpx.TimeoutException:
        raise ApiError("CONNECTOR_TIMEOUT", "زمان درخواست به کانکتور تمام شد", http_status=504)
    except Exception as exc:
        raise ApiError("CONNECTOR_ERROR", f"خطا در فراخوانی کانکتور: {exc}", http_status=502)

    logger.info(
        "AI connector invoked: business=%s connector=%s method=%s status=%s",
        business_id,
        name,
        method,
        resp.status_code,
    )

    text = resp.text[:MAX_RESPONSE_CHARS]
    parsed: Any = text
    try:
        parsed = resp.json()
    except Exception:
        pass

    return {
        "connector": name,
        "status_code": resp.status_code,
        "ok": resp.is_success,
        "data": parsed,
    }


def invoke_connector_handler(arguments: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    db: Session = context["db"]
    business_id = context.get("session_business_id") or context.get("business_id")
    if not business_id:
        raise ValueError("business_id required")
    return invoke_connector(
        db,
        int(business_id),
        arguments.get("connector_name", ""),
        query_params=arguments.get("query_params"),
        body=arguments.get("body"),
    )
