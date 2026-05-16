"""Basalam integration service (settings, webhook processing, order sync)."""

from __future__ import annotations

import hashlib
import hmac
import io
import json
from datetime import date
from datetime import datetime
from datetime import timedelta
from typing import Any, Dict, List, Optional, Tuple
from uuid import UUID

from sqlalchemy import or_
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

import structlog

from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonType
from adapters.api.v1.schema_models.product import ProductCreateRequest
from adapters.db.models.business import Business
from adapters.db.models.file_storage import FileStorage
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.crm_chat import CrmChatConversation, CrmChatMessage, CrmChatWidget
from adapters.db.models.currency import BusinessCurrency, Currency
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from fastapi import HTTPException
from app.core.basalam_plugin_dependency import check_basalam_plugin_active
from app.core.cache import get_cache
from app.core.responses import ApiError
from app.services import crm_chat_service
from app.services.file_storage_service import FileStorageService
from app.services.basalam_observability import record_basalam_metric
from app.services.invoice_service import (
    INVOICE_LINK_RECEIPT_PAYMENT_IDS,
    _normalize_document_extra_info_for_storage,
    calculate_invoice_remaining,
    create_invoice,
)
from app.services.person_service import create_person
from app.services.product_service import create_product
from app.services.receipt_payment_service import create_receipt_payment
from app.services.storage_subscription_service import check_storage_limit
from app.services.workflow.workflow_trigger_service import trigger_workflows

logger = structlog.get_logger(__name__)

PLUGIN_CODE = "basalam_connector"
EXTRA_INFO_KEY = "basalam_connector"
DEDUPE_TTL_SECONDS = 60 * 60 * 48
SYNC_DEAD_LETTER_MAX = 200

_PAYMENT_DLQ_STATUSES = frozenset(
    {
        "invoice_not_found",
        "manual_review_required",
        "invalid_amount",
        "invoice_person_not_found",
        "missing_reference_id",
        "invoice_currency_not_irr",
        "payment_exceeds_invoice_remaining",
        "payment_invoice_already_settled",
    }
)


def _json_loads_safe(value: Optional[str]) -> Dict[str, Any]:
    if not value:
        return {}
    try:
        loaded = json.loads(value)
    except Exception:
        return {}
    return loaded if isinstance(loaded, dict) else {}


def _json_dumps_safe(value: Dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False)


def _find_plugin_row(db: Session) -> MarketplacePlugin:
    plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == PLUGIN_CODE).first()
    if not plugin:
        raise ApiError(
            "BASALAM_PLUGIN_NOT_REGISTERED",
            "Basalam plugin is not registered in marketplace.",
            http_status=404,
        )
    return plugin


def _find_business_plugin(db: Session, business_id: int) -> BusinessPlugin:
    plugin = _find_plugin_row(db)
    row = (
        db.query(BusinessPlugin)
        .filter(
            BusinessPlugin.business_id == int(business_id),
            BusinessPlugin.plugin_id == plugin.id,
        )
        .first()
    )
    if row:
        return row

    raise ApiError(
        "BASALAM_LICENSE_NOT_FOUND",
        "Basalam license row for this business was not found.",
        http_status=404,
    )


def _default_settings() -> Dict[str, Any]:
    return {
        "enabled": False,
        "api_key": "",
        "api_refresh_token": "",
        "api_base_url": "https://api.basalam.com",
        "default_basalam_vendor_id": None,
        "default_basalam_category_id": None,
        "default_basalam_stock": 1,
        "last_product_pull_at": None,
        "last_product_push_at": None,
        "pending_product_publish_retries": [],
        "pending_product_conflicts": [],
        "product_conflict_price_strategy": "local_wins",
        "product_conflict_stock_strategy": "local_wins",
        "product_variant_strategy": "manual_review",
        "webhook_secret": "",
        "webhook_enabled": False,
        "chat_enabled": True,
        "order_sync_enabled": True,
        "product_sync_enabled": True,
        "auto_create_person_mode": "match_or_create",
        "auto_create_product_mode": "match_or_create",
        "default_order_tag": "basalam",
        "payment_register_mode": "manual_review",
        "payment_sync_enabled": True,
        "payment_verify_remote": True,
        "create_sales_invoice_on_sync": True,
        "invoice_type_on_sync": "invoice_sales",
        "default_bank_account_id": None,
        "default_cash_register_id": None,
        "mappings": {
            "persons": {},
            "products": {},
        },
        "recent_event_keys": [],
        "updated_at": None,
        "last_webhook_event_at": None,
        "last_webhook_event_type": None,
        "sync_dead_letter": [],
        # واحد مبلغ در API/وب‌هوک باسلام: «rial» (ریال) یا «toman» (تومان؛ به ریال داخلی ×۱۰)
        "basalam_monetary_unit": "rial",
        # تطبیق سند پرداخت با ماندهٔ فاکتور (IRR)
        "payment_reconcile_block_overpayment": True,
        "payment_reconcile_tolerance_rial": 1.0,
    }


def _normalize_settings(payload: Dict[str, Any], previous: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    base = dict(_default_settings())
    if previous:
        base.update(previous)
    if payload:
        base.update(payload)

    base["enabled"] = bool(base.get("enabled", False))
    base["webhook_enabled"] = bool(base.get("webhook_enabled", False))
    base["chat_enabled"] = bool(base.get("chat_enabled", True))
    base["order_sync_enabled"] = bool(base.get("order_sync_enabled", True))
    base["product_sync_enabled"] = bool(base.get("product_sync_enabled", True))
    base["api_key"] = str(base.get("api_key") or "").strip()
    base["api_refresh_token"] = str(base.get("api_refresh_token") or "").strip()
    base["api_base_url"] = str(base.get("api_base_url") or "https://api.basalam.com").strip()
    base["default_basalam_vendor_id"] = (
        int(base.get("default_basalam_vendor_id")) if str(base.get("default_basalam_vendor_id") or "").isdigit() else None
    )
    base["default_basalam_category_id"] = (
        int(base.get("default_basalam_category_id"))
        if str(base.get("default_basalam_category_id") or "").isdigit()
        else None
    )
    stock_val = base.get("default_basalam_stock")
    try:
        base["default_basalam_stock"] = max(0, int(stock_val))
    except Exception:
        base["default_basalam_stock"] = 1
    pending_pub = base.get("pending_product_publish_retries")
    base["pending_product_publish_retries"] = (
        [x for x in pending_pub if isinstance(x, dict)] if isinstance(pending_pub, list) else []
    )
    pending_conf = base.get("pending_product_conflicts")
    base["pending_product_conflicts"] = (
        [x for x in pending_conf if isinstance(x, dict)] if isinstance(pending_conf, list) else []
    )
    dlq = base.get("sync_dead_letter")
    base["sync_dead_letter"] = [x for x in dlq if isinstance(x, dict)] if isinstance(dlq, list) else []
    price_strategy = str(base.get("product_conflict_price_strategy") or "local_wins").strip()
    stock_strategy = str(base.get("product_conflict_stock_strategy") or "local_wins").strip()
    variant_strategy = str(base.get("product_variant_strategy") or "manual_review").strip()
    allowed = {"local_wins", "remote_wins", "manual_review"}
    base["product_conflict_price_strategy"] = price_strategy if price_strategy in allowed else "local_wins"
    base["product_conflict_stock_strategy"] = stock_strategy if stock_strategy in allowed else "local_wins"
    base["product_variant_strategy"] = variant_strategy if variant_strategy in allowed else "manual_review"
    mon_unit = str(base.get("basalam_monetary_unit") or "rial").strip().lower()
    base["basalam_monetary_unit"] = "toman" if mon_unit in ("toman", "tomman", "تومان") else "rial"
    base["payment_reconcile_block_overpayment"] = bool(base.get("payment_reconcile_block_overpayment", True))
    try:
        tol = float(base.get("payment_reconcile_tolerance_rial"))
        base["payment_reconcile_tolerance_rial"] = max(0.0, tol)
    except (TypeError, ValueError):
        base["payment_reconcile_tolerance_rial"] = 1.0
    base["webhook_secret"] = str(base.get("webhook_secret") or "").strip()
    base["auto_create_person_mode"] = str(base.get("auto_create_person_mode") or "match_or_create").strip()
    base["auto_create_product_mode"] = str(base.get("auto_create_product_mode") or "match_or_create").strip()
    base["default_order_tag"] = str(base.get("default_order_tag") or "basalam").strip() or "basalam"
    base["payment_register_mode"] = str(base.get("payment_register_mode") or "manual_review").strip()
    base["payment_sync_enabled"] = bool(base.get("payment_sync_enabled", True))
    base["payment_verify_remote"] = bool(base.get("payment_verify_remote", True))
    base["create_sales_invoice_on_sync"] = bool(base.get("create_sales_invoice_on_sync", True))
    base["invoice_type_on_sync"] = str(base.get("invoice_type_on_sync") or "invoice_sales").strip()
    mappings = base.get("mappings") if isinstance(base.get("mappings"), dict) else {}
    base["mappings"] = {
        "persons": mappings.get("persons") if isinstance(mappings.get("persons"), dict) else {},
        "products": mappings.get("products") if isinstance(mappings.get("products"), dict) else {},
    }
    recent = base.get("recent_event_keys")
    base["recent_event_keys"] = [str(x) for x in recent if isinstance(x, str)] if isinstance(recent, list) else []
    base["updated_at"] = datetime.utcnow().isoformat()
    return base


def get_settings(db: Session, business_id: int) -> Dict[str, Any]:
    row = _find_business_plugin(db, business_id)
    if not check_basalam_plugin_active(db, int(business_id)):
        raise ApiError(
            "BASALAM_PLUGIN_NOT_ACTIVE",
            "Basalam plugin is not active.",
            http_status=403,
            details={"plugin_code": PLUGIN_CODE},
        )
    extra = _json_loads_safe(row.extra_info)
    saved = extra.get(EXTRA_INFO_KEY)
    if not isinstance(saved, dict):
        saved = _default_settings()
    return _normalize_settings(saved, saved)


def update_settings(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
    row = _find_business_plugin(db, business_id)
    if not check_basalam_plugin_active(db, int(business_id)):
        raise ApiError(
            "BASALAM_PLUGIN_NOT_ACTIVE",
            "Basalam plugin is not active.",
            http_status=403,
            details={"plugin_code": PLUGIN_CODE},
        )
    extra = _json_loads_safe(row.extra_info)
    prev = extra.get(EXTRA_INFO_KEY) if isinstance(extra.get(EXTRA_INFO_KEY), dict) else _default_settings()
    settings = _normalize_settings(payload or {}, prev)
    extra[EXTRA_INFO_KEY] = settings
    row.extra_info = _json_dumps_safe(extra)
    row.updated_at = datetime.utcnow()
    db.add(row)
    db.commit()
    db.refresh(row)
    return settings


def _verify_webhook_signature(raw_body: bytes, supplied_signature: Optional[str], secret: str) -> bool:
    if not secret:
        return True
    if not supplied_signature:
        return False
    digest = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(digest, supplied_signature.strip())


def _event_type(payload: Dict[str, Any]) -> str:
    for key in ("event_type", "event", "type", "topic"):
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip().lower()
    return "unknown"


def _event_id(payload: Dict[str, Any]) -> str:
    for key in ("event_id", "id", "hash_id", "message_id"):
        value = payload.get(key)
        if value not in (None, ""):
            return str(value)
    data = payload.get("data")
    if isinstance(data, dict):
        for key in ("event_id", "id", "hash_id"):
            value = data.get(key)
            if value not in (None, ""):
                return str(value)
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()[:24]


def _workflow_event_key(event_type: str) -> str:
    mapping = {
        "order.created": "basalam.order.created",
        "order.updated": "basalam.order.updated",
        "order.paid": "basalam.order.paid",
        "chat.message.received": "basalam.chat.message.received",
    }
    return mapping.get(event_type, "basalam.webhook.received")


def _digits_only(value: Optional[str]) -> str:
    if not value:
        return ""
    mapped = str(value)
    trans = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")
    mapped = mapped.translate(trans)
    return "".join(ch for ch in mapped if ch.isdigit())


def _normalize_mobile(value: Optional[str]) -> Optional[str]:
    d = _digits_only(value)
    if not d:
        return None
    if d.startswith("98") and len(d) >= 12:
        d = "0" + d[2:]
    if d.startswith("+98"):
        d = "0" + d[3:]
    return d


def _extract_order_candidates(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    candidates: List[Dict[str, Any]] = []
    for key in ("orders", "customer_orders", "items"):
        value = payload.get(key)
        if isinstance(value, list):
            candidates.extend(v for v in value if isinstance(v, dict))
    for key in ("order", "customer_order"):
        value = payload.get(key)
        if isinstance(value, dict):
            candidates.append(value)
    data = payload.get("data")
    if isinstance(data, dict):
        for key in ("orders", "customer_orders"):
            value = data.get(key)
            if isinstance(value, list):
                candidates.extend(v for v in value if isinstance(v, dict))
        if isinstance(data.get("order"), dict):
            candidates.append(data["order"])
    return candidates


def _order_id(order: Dict[str, Any]) -> str:
    for key in ("id", "order_id", "hash_id", "number"):
        value = order.get(key)
        if value not in (None, ""):
            return str(value)
    return hashlib.sha256(json.dumps(order, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()[:16]


def _extract_customer(order: Dict[str, Any]) -> Dict[str, Any]:
    for key in ("customer", "buyer", "person", "user"):
        value = order.get(key)
        if isinstance(value, dict):
            return value
    return {}


def _extract_order_lines(order: Dict[str, Any]) -> List[Dict[str, Any]]:
    for key in ("items", "lines", "products", "order_items"):
        value = order.get(key)
        if isinstance(value, list):
            return [v for v in value if isinstance(v, dict)]
    return []


def _extract_product_basalam_id(line: Dict[str, Any]) -> Optional[str]:
    for key in ("product_id", "variation_id", "id", "hash_id"):
        value = line.get(key)
        if value not in (None, ""):
            return str(value)
    product = line.get("product")
    if isinstance(product, dict):
        for key in ("id", "hash_id"):
            value = product.get(key)
            if value not in (None, ""):
                return str(value)
    return None


def _parse_decimal(value: Any, default: float = 0.0) -> float:
    try:
        if value in (None, ""):
            return float(default)
        return float(value)
    except Exception:
        return float(default)


def _basalam_monetary_unit(settings: Dict[str, Any]) -> str:
    """واحد مبلغ در دادهٔ باسلام: rial یا toman (تبدیل به ریال حساب‌یکس با ×۱۰)."""
    u = str(settings.get("basalam_monetary_unit") or "rial").strip().lower()
    return "toman" if u == "toman" else "rial"


def _incoming_basalam_amount_to_rial_amount(value: Any, settings: Dict[str, Any]) -> float:
    """مبلغ خام از باسلام → ریال داخلی (IRR) مطابق تنظیمات افزونه."""
    v = _parse_decimal(value, 0)
    if _basalam_monetary_unit(settings) == "toman":
        return float(v) * 10.0
    return float(v)


def _internal_rial_amount_to_basalam_wire(value: Any, settings: Dict[str, Any]) -> float:
    """ریال ذخیره‌شده در حساب‌یکس → عددی که به API باسلام برای قیمت می‌فرستیم."""
    v = _parse_decimal(value, 0)
    if _basalam_monetary_unit(settings) == "toman":
        return float(v) / 10.0
    return float(v)


def _basalam_currency_validation(db: Session, business_id: int) -> Dict[str, Any]:
    """اعتبارسنجی IRR-only؛ بدون پرتاب — برای UI و برای ساخت خطای اول در سینک."""
    bid = int(business_id)
    issues: List[Dict[str, Any]] = []
    default_code: Optional[str] = None
    invalid_secondary: List[str] = []

    biz = db.query(Business).filter(Business.id == bid).first()
    if not biz:
        issues.append(
            {
                "code": "BUSINESS_NOT_FOUND",
                "message": "کسب‌وکار یافت نشد.",
                "http_status": 404,
            }
        )
        return {
            "issues": issues,
            "default_currency_code": None,
            "invalid_secondary_currency_codes": invalid_secondary,
        }

    if not biz.default_currency_id:
        issues.append(
            {
                "code": "BASALAM_CURRENCY_NOT_SET",
                "message": "برای سینک با باسلام ابتدا ارز پیش‌فرض کسب‌وکار را تعیین کنید.",
                "http_status": 400,
            }
        )
        return {
            "issues": issues,
            "default_currency_code": None,
            "invalid_secondary_currency_codes": invalid_secondary,
        }

    dc = db.query(Currency).filter(Currency.id == int(biz.default_currency_id)).first()
    default_code = str(dc.code if dc else "").strip().upper() or None
    if default_code != "IRR":
        issues.append(
            {
                "code": "BASALAM_REQUIRES_IRR_DEFAULT_CURRENCY",
                "message": "برای سینک با باسلام، ارز پیش‌فرض کسب‌وکار باید ریال ایران با کد IRR باشد.",
                "http_status": 409,
                "details": {"current_currency_code": default_code},
            }
        )

    secondary_codes = (
        db.query(Currency.code)
        .join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
        .filter(BusinessCurrency.business_id == bid)
        .all()
    )
    invalid_secondary = sorted(
        {str(c[0]).strip().upper() for c in secondary_codes if str(c[0]).strip().upper() != "IRR"}
    )
    if invalid_secondary:
        issues.append(
            {
                "code": "BASALAM_REQUIRES_IRR_ONLY_CURRENCIES",
                "message": "برای سینک با باسلام فقط ارز IRR باید در ارزهای فعال کسب‌وکار باشد؛ ارزهای جانبی غیرریالی را حذف کنید.",
                "http_status": 409,
                "details": {"invalid_currency_codes": invalid_secondary},
            }
        )

    return {
        "issues": issues,
        "default_currency_code": default_code,
        "invalid_secondary_currency_codes": invalid_secondary,
    }


def get_basalam_currency_readiness(db: Session, business_id: int) -> Dict[str, Any]:
    """وضعیت ارزی برای هشدار در UI؛ هرگز پرتاب نمی‌کند."""
    if not check_basalam_plugin_active(db, int(business_id)):
        return {
            "ready": False,
            "issues": [
                {
                    "code": "BASALAM_PLUGIN_NOT_ACTIVE",
                    "message": "افزونهٔ باسلام برای این کسب‌وکار فعال نیست یا اعتبار آن به پایان رسیده است.",
                }
            ],
            "default_currency_code": None,
            "invalid_secondary_currency_codes": [],
        }
    v = _basalam_currency_validation(db, business_id)
    issues = list(v.get("issues") or [])
    return {
        "ready": len(issues) == 0,
        "issues": issues,
        "default_currency_code": v.get("default_currency_code"),
        "invalid_secondary_currency_codes": list(v.get("invalid_secondary_currency_codes") or []),
    }


def _ensure_business_irr_only_for_basalam(db: Session, business_id: int) -> None:
    """
    سینک باسلام فقط با ارز ریال ایران در حساب‌یکس: پیش‌فرض IRR و عدم وجود ارز جانبی غیر IRR.
    """
    v = _basalam_currency_validation(db, business_id)
    issues = list(v.get("issues") or [])
    if not issues:
        return
    first = issues[0]
    raise ApiError(
        str(first.get("code") or "BASALAM_CURRENCY_INVALID"),
        str(first.get("message") or "Currency validation failed."),
        http_status=int(first.get("http_status") or 409),
        details=first.get("details"),
    )


def _event_dedupe_key(business_id: int, event_type: str, event_id: str, order_id: Optional[str] = None) -> str:
    if order_id:
        return f"basalam:dedupe:{business_id}:{event_type}:{event_id}:{order_id}"
    return f"basalam:dedupe:{business_id}:{event_type}:{event_id}"


def _is_duplicate_event(business_id: int, dedupe_key: str) -> bool:
    cache = get_cache()
    if cache.enabled:
        if cache.exists(dedupe_key):
            return True
        cache.set(dedupe_key, True, ttl=DEDUPE_TTL_SECONDS)
        return False
    return False


def _remember_event_in_settings(db: Session, business_id: int, settings: Dict[str, Any], dedupe_key: str) -> None:
    recent = list(settings.get("recent_event_keys") or [])
    if dedupe_key in recent:
        return
    recent.append(dedupe_key)
    if len(recent) > 200:
        recent = recent[-200:]
    update_settings(db, business_id, {"recent_event_keys": recent})


def _resolve_actor_user_id(db: Session, business_id: int, requested_user_id: Optional[int]) -> int:
    if requested_user_id and int(requested_user_id) > 0:
        return int(requested_user_id)
    biz = db.query(Business).filter(Business.id == int(business_id)).first()
    if not biz or not biz.owner_id:
        raise ApiError("BASALAM_BUSINESS_OWNER_NOT_FOUND", "Business owner user was not found.", http_status=404)
    return int(biz.owner_id)


def _extract_person_name(customer: Dict[str, Any]) -> str:
    for key in ("full_name", "name", "display_name", "username"):
        value = customer.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    first_name = str(customer.get("first_name") or "").strip()
    last_name = str(customer.get("last_name") or "").strip()
    joined = f"{first_name} {last_name}".strip()
    return joined or "Basalam Customer"


def _find_or_create_person(
    db: Session,
    business_id: int,
    settings: Dict[str, Any],
    customer: Dict[str, Any],
) -> Optional[int]:
    mode = str(settings.get("auto_create_person_mode") or "match_or_create")
    customer_id = str(customer.get("id") or customer.get("hash_id") or "").strip()
    mappings = settings.get("mappings", {}).get("persons", {})
    if customer_id and customer_id in mappings:
        mapped_id = int(mappings[customer_id])
        exists = db.query(Person).filter(Person.business_id == int(business_id), Person.id == mapped_id).first()
        if exists:
            return mapped_id

    mobile = _normalize_mobile(customer.get("mobile") or customer.get("phone"))
    if mobile:
        hit = db.query(Person).filter(
            Person.business_id == int(business_id),
            or_(Person.mobile == mobile, Person.mobile_2 == mobile, Person.mobile_3 == mobile),
        ).first()
        if hit:
            return int(hit.id)
    name = _extract_person_name(customer)
    hit = db.query(Person).filter(Person.business_id == int(business_id), Person.alias_name == name).first()
    if hit:
        return int(hit.id)

    if mode in ("match_only", "manual_review"):
        return None

    created = create_person(
        db,
        business_id=int(business_id),
        person_data=PersonCreateRequest(
            alias_name=name,
            person_types=[PersonType.CUSTOMER],
            mobile=mobile,
            phone=mobile,
        ),
    )
    data = created.get("data") if isinstance(created, dict) else {}
    person_id = data.get("id") if isinstance(data, dict) else None
    if not person_id:
        return None
    return int(person_id)


def _find_or_create_product(
    db: Session,
    business_id: int,
    settings: Dict[str, Any],
    line: Dict[str, Any],
) -> Optional[int]:
    mode = str(settings.get("auto_create_product_mode") or "match_or_create")
    basalam_pid = _extract_product_basalam_id(line)
    mappings = settings.get("mappings", {}).get("products", {})
    if basalam_pid and basalam_pid in mappings:
        mapped_id = int(mappings[basalam_pid])
        exists = db.query(Product).filter(Product.business_id == int(business_id), Product.id == mapped_id).first()
        if exists:
            return mapped_id

    sku = str(line.get("sku") or "").strip()
    barcode = _digits_only(line.get("barcode") or "")
    name = str(line.get("title") or line.get("name") or "Basalam Item").strip()

    if sku:
        hit = db.query(Product).filter(Product.business_id == int(business_id), Product.code == sku).first()
        if hit:
            return int(hit.id)
    if barcode:
        hit = (
            db.query(Product)
            .filter(Product.business_id == int(business_id), Product.general_barcodes.isnot(None))
            .all()
        )
        for p in hit:
            raw = str(p.general_barcodes or "")
            tokens = [t.strip() for t in raw.split(",") if t.strip()]
            if barcode in tokens:
                return int(p.id)
    hit = db.query(Product).filter(Product.business_id == int(business_id), Product.name == name).first()
    if hit:
        return int(hit.id)

    if mode in ("match_only", "manual_review"):
        return None

    product_payload = ProductCreateRequest(
        code=sku if sku else None,
        name=name or "Basalam Item",
        item_type="کالا",
        base_sales_price=_incoming_basalam_amount_to_rial_amount(
            line.get("unit_price") or line.get("price"),
            settings,
        ),
        barcode=barcode or None,
        track_inventory=True,
    )
    created = create_product(db, business_id=int(business_id), payload=product_payload)
    data = created.get("data") if isinstance(created, dict) else {}
    product_id = data.get("id") if isinstance(data, dict) else None
    if not product_id:
        return None
    return int(product_id)


def _build_invoice_lines(
    db: Session,
    business_id: int,
    settings: Dict[str, Any],
    order: Dict[str, Any],
) -> Tuple[List[Dict[str, Any]], Dict[str, int]]:
    lines: List[Dict[str, Any]] = []
    mapped_products: Dict[str, int] = {}
    for item in _extract_order_lines(order):
        pid = _find_or_create_product(db, business_id, settings, item)
        if not pid:
            continue
        basalam_pid = _extract_product_basalam_id(item)
        if basalam_pid:
            mapped_products[basalam_pid] = pid
        qty = _parse_decimal(item.get("quantity") or item.get("qty") or 1, 1)
        unit_price = _incoming_basalam_amount_to_rial_amount(
            item.get("unit_price") or item.get("price"),
            settings,
        )
        lines.append(
            {
                "product_id": int(pid),
                "quantity": qty if qty > 0 else 1,
                "unit_price": unit_price if unit_price >= 0 else 0,
                "discount_percent": 0,
                "tax_percent": 0,
                "description": str(item.get("title") or item.get("name") or "").strip() or None,
            }
        )
    return lines, mapped_products


def _sync_order_to_invoice(
    db: Session,
    business_id: int,
    actor_user_id: int,
    settings: Dict[str, Any],
    order: Dict[str, Any],
) -> Dict[str, Any]:
    customer = _extract_customer(order)
    person_id = _find_or_create_person(db, business_id, settings, customer)
    if not person_id:
        return {"status": "pending_manual_person", "order_id": _order_id(order)}

    lines, mapped_products = _build_invoice_lines(db, business_id, settings, order)
    if not lines:
        return {"status": "pending_manual_products", "order_id": _order_id(order), "person_id": person_id}

    currency_id = (
        db.query(Business.default_currency_id)
        .filter(Business.id == int(business_id))
        .scalar()
    )
    if not currency_id:
        raise ApiError("BASALAM_CURRENCY_NOT_SET", "Business default currency is not configured.", http_status=400)

    invoice_type = str(settings.get("invoice_type_on_sync") or "invoice_sales").strip()
    order_id = _order_id(order)
    invoice_payload: Dict[str, Any] = {
        "invoice_type": invoice_type,
        "person_id": int(person_id),
        "currency_id": int(currency_id),
        "document_date": (date.today()).isoformat(),
        "lines": lines,
        "description": f"Basalam order {order_id}",
        "extra_info": {
            "source": "basalam",
            "basalam_order_id": order_id,
            "tags": [settings.get("default_order_tag", "basalam")],
            "basalam_order_payload": order,
        },
    }
    if not settings.get("create_sales_invoice_on_sync", True):
        return {
            "status": "prepared_only",
            "order_id": order_id,
            "person_id": int(person_id),
            "lines_count": len(lines),
        }

    created = create_invoice(
        db=db,
        business_id=int(business_id),
        user_id=int(actor_user_id),
        data=invoice_payload,
    )
    data = created.get("data") if isinstance(created, dict) else {}
    result = {
        "status": "synced",
        "order_id": order_id,
        "person_id": int(person_id),
        "invoice_id": data.get("id"),
        "invoice_code": data.get("code"),
    }
    mappings = settings.get("mappings") if isinstance(settings.get("mappings"), dict) else {"persons": {}, "products": {}}
    if customer:
        customer_id = str(customer.get("id") or customer.get("hash_id") or "").strip()
        if customer_id:
            mappings.setdefault("persons", {})[customer_id] = int(person_id)
    if mapped_products:
        mappings.setdefault("products", {}).update({k: int(v) for k, v in mapped_products.items()})
    update_settings(db, business_id, {"mappings": mappings})
    return result


def _sync_orders(
    db: Session,
    business_id: int,
    settings: Dict[str, Any],
    orders: List[Dict[str, Any]],
    source: str,
    event_type: str,
    event_id: str,
    actor_user_id: int,
) -> Dict[str, Any]:
    _ensure_business_irr_only_for_basalam(db, int(business_id))
    results: List[Dict[str, Any]] = []
    processed = 0
    skipped_duplicates = 0
    for order in orders:
        oid = _order_id(order)
        dedupe_key = _event_dedupe_key(business_id, event_type, event_id, oid)
        if dedupe_key in settings.get("recent_event_keys", []):
            skipped_duplicates += 1
            continue
        if _is_duplicate_event(business_id, dedupe_key):
            skipped_duplicates += 1
            continue
        result = _sync_order_to_invoice(
            db=db,
            business_id=int(business_id),
            actor_user_id=int(actor_user_id),
            settings=settings,
            order=order,
        )
        processed += 1
        results.append(result)
        if result.get("status") in ("pending_manual_person", "pending_manual_products"):
            _append_sync_dead_letter(
                db,
                int(business_id),
                {
                    "type": "order_sync",
                    "subtype": result.get("status"),
                    "order_id": oid,
                    "source": source,
                    "event_type": event_type,
                    "event_id": event_id,
                    "person_id": result.get("person_id"),
                },
            )
        _remember_event_in_settings(db, business_id, settings, dedupe_key)
        trigger_workflows(
            db=db,
            business_id=int(business_id),
            trigger_type="basalam.order.created",
            trigger_data={
                "source": source,
                "event_type": event_type,
                "event_id": event_id,
                "order": order,
                "order_id": oid,
                "sync_result": result,
                "tag": settings.get("default_order_tag", "basalam"),
            },
        )
    record_basalam_metric("sync_orders_batches", 1)
    record_basalam_metric("sync_orders_processed", processed)
    record_basalam_metric(
        "sync_orders_invoices_created",
        sum(1 for r in results if r.get("status") == "synced" and r.get("invoice_id")),
    )
    return {"processed_orders": processed, "skipped_duplicates": skipped_duplicates, "results": results}


def _sdk_to_dict(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, dict):
        return {k: _sdk_to_dict(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_sdk_to_dict(v) for v in value]
    dump = getattr(value, "model_dump", None)
    if callable(dump):
        try:
            return _sdk_to_dict(dump())
        except Exception:
            return str(value)
    return value


def _get_basalam_sdk_client(settings: Dict[str, Any]) -> Any:
    api_key = str(settings.get("api_key") or "").strip()
    if not api_key:
        raise ApiError("BASALAM_API_KEY_REQUIRED", "Basalam API key is not configured.", http_status=400)
    try:
        from basalam_sdk import BasalamClient, PersonalToken
    except Exception as exc:
        raise ApiError(
            "BASALAM_SDK_NOT_INSTALLED",
            "basalam-sdk is not installed. Install package basalam-sdk in API environment.",
            http_status=500,
            details={"reason": str(exc)},
        )
    refresh_token = str(settings.get("api_refresh_token") or "").strip()
    auth = PersonalToken(token=api_key, refresh_token=refresh_token)
    return BasalamClient(auth=auth)


def _basalam_request(
    settings: Dict[str, Any],
    method: str,
    path: str,
    query: Optional[Dict[str, Any]] = None,
    payload: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    client = _get_basalam_sdk_client(settings)
    query = query or {}
    payload = payload or {}
    path_norm = str(path or "").strip()
    path_lc = path_norm.lower()
    method_norm = str(method or "").strip().upper()

    if path_lc == "/v1/pay/transactions/unverified" and method_norm == "GET":
        try:
            res = client.wallet.request_sync(
                method="GET",
                path="/v1/pay/transactions/unverified",
                params={"page": query.get("page", 1), "per_page": query.get("per_page", 50)},
                require_auth=True,
            )
        except Exception as exc:
            raise ApiError(
                "BASALAM_SDK_CALL_ERROR",
                "Basalam SDK request failed for unverified transactions.",
                http_status=502,
                details={"path": path_norm, "reason": str(exc)},
            )
        parsed = _sdk_to_dict(res)
        return parsed if isinstance(parsed, dict) else {"data": parsed}

    if path_lc.startswith("/v1/pay/transactions/") and path_lc.endswith("/verify") and method_norm == "POST":
        hash_id = path_norm.split("/v1/pay/transactions/", 1)[1].rsplit("/verify", 1)[0].strip()
        try:
            res = client.wallet.request_sync(
                method="POST",
                path=f"/v1/pay/transactions/{hash_id}/verify",
                require_auth=True,
            )
        except Exception as exc:
            raise ApiError(
                "BASALAM_SDK_CALL_ERROR",
                "Basalam SDK request failed for transaction verify.",
                http_status=502,
                details={"path": path_norm, "reason": str(exc)},
            )
        parsed = _sdk_to_dict(res)
        return parsed if isinstance(parsed, dict) else {"data": parsed}

    if path_lc.startswith("/v1/chats/") and path_lc.endswith("/messages") and method_norm == "POST":
        chat_id_raw = path_norm.split("/v1/chats/", 1)[1].rsplit("/messages", 1)[0].strip()
        try:
            chat_id: Any = int(chat_id_raw)
        except Exception:
            chat_id = chat_id_raw
        message_type = str(payload.get("message_type") or "text").strip().lower()
        if message_type != "text":
            try:
                res = client.chat.request_sync(
                    method="POST",
                    path=f"/v1/chats/{chat_id}/messages",
                    json_data=payload,
                    require_auth=True,
                )
            except Exception as exc:
                raise ApiError(
                    "BASALAM_SDK_CALL_ERROR",
                    "Basalam SDK request failed for non-text chat message.",
                    http_status=502,
                    details={"path": path_norm, "reason": str(exc)},
                )
            parsed = _sdk_to_dict(res)
            return parsed if isinstance(parsed, dict) else {"data": parsed}
        content = payload.get("content") if isinstance(payload.get("content"), dict) else {}
        text = str(content.get("text") or payload.get("text") or "").strip()
        try:
            from basalam_sdk.chat.models import MessageInput, MessageRequest, MessageTypeEnum

            req = MessageRequest(
                chat_id=chat_id,
                content=MessageInput(text=text),
                message_type=MessageTypeEnum.TEXT,
            )
            res = client.chat.create_message_sync(request=req)
        except Exception as exc:
            raise ApiError(
                "BASALAM_SDK_CALL_ERROR",
                "Basalam SDK request failed for create chat message.",
                http_status=502,
                details={"path": path_norm, "reason": str(exc)},
            )
        parsed = _sdk_to_dict(res)
        return parsed if isinstance(parsed, dict) else {"data": parsed}

    raise ApiError(
        "BASALAM_SDK_UNSUPPORTED_PATH",
        "Requested Basalam API path is not mapped to SDK adapter yet.",
        http_status=400,
        details={"method": method_norm, "path": path},
    )


def _map_upload_file_type(mime_type: str) -> str:
    mt = str(mime_type or "").lower()
    if mt.startswith("image/"):
        return "chat.photo"
    if mt.startswith("video/"):
        return "chat.video"
    if mt.startswith("audio/"):
        return "chat.voice"
    return "chat.file"


async def _upload_crm_file_to_basalam(
    db: Session,
    business_id: int,
    settings: Dict[str, Any],
    file_storage_id: str,
) -> Dict[str, Any]:
    fs = db.get(FileStorage, str(file_storage_id).strip())
    if not fs:
        raise ApiError("CRM_CHAT_FILE_NOT_FOUND", "File not found", http_status=404)
    if fs.business_id is not None and int(fs.business_id) != int(business_id):
        raise ApiError(
            "CRM_CHAT_FILE_BUSINESS_MISMATCH",
            "File does not belong to this business.",
            http_status=403,
        )

    limit_info = check_storage_limit(db, int(business_id), None)
    if float(limit_info.get("total_limit_gb") or 0) <= 0:
        raise ApiError(
            "NO_ACTIVE_STORAGE_PLAN",
            "برای ارسال پیوست از CRM به باسلام، ابتدا یک پلن ذخیره‌سازی فعال برای کسب‌وکار انتخاب کنید.",
            http_status=403,
            details={
                "total_limit_gb": limit_info.get("total_limit_gb"),
                "current_usage_gb": limit_info.get("current_usage_gb"),
            },
        )

    storage_svc = FileStorageService(db)
    try:
        dl = await storage_svc.download_file(UUID(str(fs.id)))
    except HTTPException as he:
        detail = he.detail
        if isinstance(detail, dict):
            msg = str(detail.get("message") or detail.get("detail") or detail)
        else:
            msg = str(detail)
        if he.status_code == 404:
            raise ApiError("CRM_CHAT_FILE_NOT_FOUND", msg, http_status=404)
        raise ApiError(
            "FILE_STORAGE_READ_FAILED",
            msg or "Failed to read file from storage.",
            http_status=502,
            details={"file_id": str(fs.id)},
        )
    except NotImplementedError as exc:
        raise ApiError(
            "STORAGE_BACKEND_NOT_SUPPORTED",
            "خواندن این نوع فضای ذخیره‌سازی در سرور هنوز پیاده‌سازی نشده؛ با مدیر سیستم هماهنگ کنید.",
            http_status=422,
            details={"storage_type": getattr(fs, "storage_type", None), "reason": str(exc)},
        )
    except FileNotFoundError as exc:
        raise ApiError(
            "CRM_CHAT_FILE_MISSING_ON_STORAGE",
            "فایل در فضای ذخیره‌سازی یافت نشد.",
            http_status=404,
            details={"file_id": str(fs.id), "reason": str(exc)},
        )

    file_content = dl.get("content")
    if not isinstance(file_content, (bytes, bytearray)) or len(file_content) == 0:
        raise ApiError(
            "FILE_STORAGE_EMPTY_CONTENT",
            "محتوای فایل خالی یا نامعتبر است.",
            http_status=422,
            details={"file_id": str(fs.id)},
        )

    client = _get_basalam_sdk_client(settings)
    file_type = _map_upload_file_type(fs.mime_type)
    try:
        from basalam_sdk.upload.models import UserUploadFileTypeEnum

        with io.BytesIO(bytes(file_content)) as bio:
            uploaded = client.upload.upload_file_sync(file=bio, file_type=UserUploadFileTypeEnum(file_type))
    except Exception as exc:
        raise ApiError(
            "BASALAM_FILE_UPLOAD_FAILED",
            "Failed to upload attachment to Basalam.",
            http_status=502,
            details={"file_id": str(fs.id), "reason": str(exc)},
        )
    parsed = _sdk_to_dict(uploaded)
    if not isinstance(parsed, dict):
        raise ApiError("BASALAM_FILE_UPLOAD_FAILED", "Invalid upload response from Basalam.", http_status=502)
    return {
        "id": int(parsed.get("id")),
        "url": str(parsed.get("url") or (parsed.get("urls") or {}).get("original") or ""),
        "name": fs.original_name,
        "type": fs.mime_type,
        "size": int(fs.file_size or 0),
    }


async def relay_agent_message_from_crm(
    db: Session,
    business_id: int,
    conversation_id: int,
    user_id: int,
    body: Optional[str],
    file_storage_id: Optional[str] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        return {"relayed": False, "reason": "basalam_disabled"}
    if not settings.get("chat_enabled", True):
        return {"relayed": False, "reason": "chat_disabled"}
    c = db.query(CrmChatConversation).filter(
        CrmChatConversation.id == int(conversation_id),
        CrmChatConversation.business_id == int(business_id),
    ).first()
    if not c:
        raise ApiError("CRM_CHAT_CONVERSATION_NOT_FOUND", "Conversation not found", http_status=404)
    metadata = c.extra_metadata if isinstance(c.extra_metadata, dict) else {}
    if str(metadata.get("source") or "").lower() != "basalam":
        return {"relayed": False, "reason": "not_basalam_conversation"}
    chat_id = str(metadata.get("basalam_chat_id") or "").strip()
    if not chat_id:
        return {"relayed": False, "reason": "missing_chat_id"}

    text = str(body or "").strip()
    attachment = None
    if file_storage_id:
        attachment = await _upload_crm_file_to_basalam(db, int(business_id), settings, file_storage_id)
        _basalam_request(
            settings=settings,
            method="POST",
            path=f"/v1/chats/{int(chat_id)}/messages" if chat_id.isdigit() else f"/v1/chats/{chat_id}/messages",
            payload={
                "message_type": "file",
                "attachment": {"files": [attachment]},
            },
        )
    if text:
        _basalam_request(
            settings=settings,
            method="POST",
            path=f"/v1/chats/{int(chat_id)}/messages" if chat_id.isdigit() else f"/v1/chats/{chat_id}/messages",
            payload={
                "message_type": "text",
                "content": {"text": text},
            },
        )
    trigger_workflows(
        db=db,
        business_id=int(business_id),
        trigger_type="crm.chat.message.sent",
        trigger_data={
            "conversation_id": int(c.id),
            "sender_role": "agent",
            "body": text,
            "source": "basalam",
            "operator_relay": True,
            "operator_relay_channel": "basalam",
            "agent_user_id": int(user_id),
            "basalam_chat_id": chat_id,
            "file_storage_id": str(file_storage_id or "") or None,
        },
        user_id=int(user_id),
    )
    return {
        "relayed": True,
        "chat_id": chat_id,
        "attachment_uploaded": bool(attachment),
    }


def _extract_transactions(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    if isinstance(payload.get("data"), list):
        return [x for x in payload["data"] if isinstance(x, dict)]
    data = payload.get("data")
    if isinstance(data, dict) and isinstance(data.get("data"), list):
        return [x for x in data["data"] if isinstance(x, dict)]
    if isinstance(payload.get("items"), list):
        return [x for x in payload["items"] if isinstance(x, dict)]
    return []


def _tx_is_paid_or_unverified(tx: Dict[str, Any]) -> bool:
    status = tx.get("status")
    if isinstance(status, dict):
        sid = status.get("id")
        slug = str(status.get("slug") or "").lower()
        if sid in (3, 5):
            return True
        if slug in ("success", "unverified"):
            return True
    if tx.get("status_id") in (3, 5):
        return True
    return False


def _find_invoice_by_basalam_reference(db: Session, business_id: int, reference_id: str) -> Optional[Document]:
    if not reference_id:
        return None
    candidates = (
        db.query(Document)
        .filter(
            Document.business_id == int(business_id),
            Document.document_type.in_(["invoice_sales", "invoice_sales_return"]),
        )
        .order_by(Document.id.desc())
        .limit(300)
        .all()
    )
    for doc in candidates:
        extra = doc.extra_info if isinstance(doc.extra_info, dict) else {}
        if str(extra.get("basalam_order_id") or "") == reference_id:
            return doc
    return None


def _existing_basalam_receipt_for_transaction_hash(
    db: Session,
    business_id: int,
    hash_id: Optional[str],
) -> Optional[int]:
    """جلوگیری از ثبت دوبارهٔ رسید برای همان hash_id تراکنش باسلام."""
    hid = str(hash_id or "").strip()
    if not hid:
        return None
    rows = (
        db.query(Document.id, Document.extra_info)
        .filter(
            Document.business_id == int(business_id),
            Document.document_type == "receipt",
        )
        .order_by(Document.id.desc())
        .limit(1500)
        .all()
    )
    for doc_id, extra in rows:
        if not isinstance(extra, dict):
            continue
        if str(extra.get("source") or "").lower() != "basalam":
            continue
        if str(extra.get("hash_id") or "").strip() == hid:
            return int(doc_id)
    return None


def _invoice_person_id(db: Session, invoice_id: int) -> Optional[int]:
    line = (
        db.query(DocumentLine)
        .filter(DocumentLine.document_id == int(invoice_id), DocumentLine.person_id.isnot(None))
        .first()
    )
    return int(line.person_id) if line and line.person_id else None


def _payment_account_line_from_settings(settings: Dict[str, Any], amount: float) -> Optional[Dict[str, Any]]:
    mode = str(settings.get("payment_register_mode") or "manual_review")
    if mode == "auto_bank":
        bank_id = settings.get("default_bank_account_id")
        if not bank_id:
            return None
        return {
            "amount": amount,
            "transaction_type": "bank",
            "bank_id": int(bank_id),
            "description": "Basalam payment sync",
        }
    if mode == "auto_cash":
        cash_id = settings.get("default_cash_register_id")
        if not cash_id:
            return None
        return {
            "amount": amount,
            "transaction_type": "cash_register",
            "cash_register_id": int(cash_id),
            "description": "Basalam payment sync",
        }
    return None


def _append_basalam_receipt_to_invoice_links(
    db: Session,
    business_id: int,
    invoice_id: int,
    receipt_document_id: int,
) -> None:
    """پیوند رسید باسلام به فاکتور برای مانده‌گیری و گزارش."""
    inv = (
        db.query(Document)
        .filter(Document.id == int(invoice_id), Document.business_id == int(business_id))
        .first()
    )
    if not inv:
        return
    extra = dict(inv.extra_info) if isinstance(inv.extra_info, dict) else {}
    links = dict(extra.get("links") or {})
    raw_ids = links.get(INVOICE_LINK_RECEIPT_PAYMENT_IDS) or []
    ids: List[int] = []
    for x in raw_ids:
        try:
            ids.append(int(x))
        except (TypeError, ValueError):
            continue
    rid = int(receipt_document_id)
    if rid not in ids:
        ids.append(rid)
    links[INVOICE_LINK_RECEIPT_PAYMENT_IDS] = ids
    extra["links"] = links
    inv.extra_info = _normalize_document_extra_info_for_storage(extra)
    flag_modified(inv, "extra_info")
    db.add(inv)


def _basalam_payment_reconcile_gate(
    db: Session,
    business_id: int,
    invoice: Document,
    settings: Dict[str, Any],
    payment_amount: float,
) -> Optional[Dict[str, Any]]:
    """
    مانع ثبت رسید در صورت بیش‌پرداخت نسبت به ماندهٔ فاکتور.
    در خطای محاسبهٔ مانده، جهت جلوگیری از قطع بی‌جهت تراکنش، عبور داده می‌شود (متریک جداگانه).
    """
    if not settings.get("payment_reconcile_block_overpayment", True):
        return None
    tol = float(settings.get("payment_reconcile_tolerance_rial") or 1.0)
    remaining_val: Optional[float] = None
    try:
        rem = calculate_invoice_remaining(db, int(business_id), int(invoice.id))
        remaining_val = float(rem.get("remaining") or 0.0)
    except Exception as exc:
        logger.warning(
            "basalam_payment_remaining_calc_failed",
            invoice_id=invoice.id,
            business_id=int(business_id),
            error=str(exc),
        )
        record_basalam_metric("payment_reconcile_remaining_calc_failed", 1)
        return None
    pay = float(payment_amount)
    if remaining_val <= tol and pay > tol:
        record_basalam_metric("payment_reconcile_blocked", 1)
        return {
            "status": "payment_invoice_already_settled",
            "invoice_id": invoice.id,
            "remaining": remaining_val,
            "payment_amount": pay,
        }
    if pay > remaining_val + tol:
        record_basalam_metric("payment_reconcile_blocked", 1)
        return {
            "status": "payment_exceeds_invoice_remaining",
            "invoice_id": invoice.id,
            "remaining": remaining_val,
            "payment_amount": pay,
        }
    return None


def _sync_single_payment_transaction(
    db: Session,
    business_id: int,
    actor_user_id: int,
    settings: Dict[str, Any],
    tx: Dict[str, Any],
) -> Dict[str, Any]:
    if not _tx_is_paid_or_unverified(tx):
        return {"status": "ignored_status", "hash_id": tx.get("hash_id")}
    _ensure_business_irr_only_for_basalam(db, business_id)
    reference_id = str(tx.get("reference_id") or "").strip()
    if not reference_id:
        return {"status": "missing_reference_id", "hash_id": tx.get("hash_id")}
    hash_key = str(tx.get("hash_id") or "").strip()
    if hash_key:
        existing_receipt = _existing_basalam_receipt_for_transaction_hash(db, business_id, hash_key)
        if existing_receipt:
            return {
                "status": "already_synced",
                "receipt_payment_id": existing_receipt,
                "hash_id": tx.get("hash_id"),
                "reference_id": reference_id,
            }
    invoice = _find_invoice_by_basalam_reference(db, business_id, reference_id)
    if not invoice:
        return {"status": "invoice_not_found", "reference_id": reference_id}
    inv_currency_code = (
        db.query(Currency.code).filter(Currency.id == int(invoice.currency_id)).scalar()
    )
    if str(inv_currency_code or "").strip().upper() != "IRR":
        return {
            "status": "invoice_currency_not_irr",
            "invoice_id": invoice.id,
            "currency_code": inv_currency_code,
        }
    person_id = _invoice_person_id(db, invoice.id)
    if not person_id:
        return {"status": "invoice_person_not_found", "invoice_id": invoice.id}
    amount = _incoming_basalam_amount_to_rial_amount(tx.get("amount"), settings)
    if amount <= 0:
        return {"status": "invalid_amount", "invoice_id": invoice.id}
    blocked = _basalam_payment_reconcile_gate(db, business_id, invoice, settings, float(amount))
    if blocked:
        return blocked
    account_line = _payment_account_line_from_settings(settings, amount)
    if not account_line:
        return {
            "status": "manual_review_required",
            "invoice_id": invoice.id,
            "reason": "payment_register_mode or default account is not configured",
        }
    payload = {
        "document_type": "receipt",
        "document_date": date.today().isoformat(),
        "currency_id": int(invoice.currency_id),
        "description": f"Basalam payment {tx.get('hash_id') or ''}".strip(),
        "person_lines": [
            {
                "person_id": int(person_id),
                "amount": amount,
                "description": f"Basalam reference {reference_id}",
            }
        ],
        "account_lines": [account_line],
        "extra_info": {
            "source": "basalam",
            "basalam_transaction": tx,
            "reference_id": reference_id,
            "hash_id": tx.get("hash_id"),
        },
    }
    created = create_receipt_payment(
        db=db,
        business_id=int(business_id),
        user_id=int(actor_user_id),
        data=payload,
    )
    rp_id = created.get("data", {}).get("id") if isinstance(created, dict) else None
    if rp_id:
        try:
            _append_basalam_receipt_to_invoice_links(db, int(business_id), int(invoice.id), int(rp_id))
            db.commit()
        except Exception as exc:
            logger.warning(
                "basalam_receipt_invoice_link_failed",
                invoice_id=invoice.id,
                receipt_id=rp_id,
                error=str(exc),
            )
    return {
        "status": "synced",
        "invoice_id": invoice.id,
        "receipt_payment_id": rp_id,
        "hash_id": tx.get("hash_id"),
        "reference_id": reference_id,
    }


def sync_unverified_payments(
    db: Session,
    business_id: int,
    user_id: Optional[int],
    verify_remote: Optional[bool] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    if not settings.get("payment_sync_enabled", True):
        raise ApiError("BASALAM_PAYMENT_SYNC_DISABLED", "Payment sync is disabled in settings.", http_status=409)
    actor_user_id = _resolve_actor_user_id(db, business_id, user_id)
    fetched = _basalam_request(
        settings=settings,
        method="GET",
        path="/v1/pay/transactions/unverified",
        query={"page": 1, "per_page": 50},
    )
    txs = _extract_transactions(fetched)
    if not txs:
        return {"accepted": True, "processed": 0, "synced": 0, "results": []}
    _ensure_business_irr_only_for_basalam(db, int(business_id))
    record_basalam_metric("payment_sync_batches", 1)
    should_verify = settings.get("payment_verify_remote", True) if verify_remote is None else bool(verify_remote)
    results: List[Dict[str, Any]] = []
    synced = 0
    for tx in txs:
        hash_id = str(tx.get("hash_id") or "").strip()
        dedupe_key = _event_dedupe_key(business_id, "payment.unverified", hash_id or _event_id(tx))
        if _is_duplicate_event(business_id, dedupe_key):
            results.append({"status": "duplicate", "hash_id": hash_id})
            continue
        result = _sync_single_payment_transaction(
            db=db,
            business_id=int(business_id),
            actor_user_id=int(actor_user_id),
            settings=settings,
            tx=tx,
        )
        if result.get("status") == "synced":
            synced += 1
            record_basalam_metric("payment_sync_receipt_created", 1)
            trigger_workflows(
                db=db,
                business_id=int(business_id),
                trigger_type="basalam.order.paid",
                trigger_data={
                    "source": "basalam",
                    "event_type": "payment.unverified",
                    "transaction": tx,
                    "sync_result": result,
                },
            )
            if should_verify and hash_id:
                try:
                    _basalam_request(
                        settings=settings,
                        method="POST",
                        path=f"/v1/pay/transactions/{hash_id}/verify",
                    )
                    result["verified_remotely"] = True
                except ApiError as exc:
                    result["verified_remotely"] = False
                    result["verify_error"] = exc.code
        results.append(result)
        if result.get("status") in _PAYMENT_DLQ_STATUSES:
            snap: Dict[str, Any] = {}
            if isinstance(tx, dict):
                for k in ("hash_id", "reference_id", "amount"):
                    if tx.get(k) is not None:
                        snap[k] = tx.get(k)
            details = {k: v for k, v in result.items() if k != "status"}
            _append_sync_dead_letter(
                db,
                int(business_id),
                {
                    "type": "payment_sync",
                    "subtype": result.get("status"),
                    "details": details,
                    "transaction": snap,
                },
            )
            record_basalam_metric("payment_sync_dlq_appended", 1)
        _remember_event_in_settings(db, business_id, settings, dedupe_key)
    logger.info(
        "basalam_payment_sync_completed",
        business_id=int(business_id),
        processed=len(txs),
        synced=synced,
        results=len(results),
    )
    return {"accepted": True, "processed": len(txs), "synced": synced, "results": results}


def _chat_token_hash(business_id: int, basalam_chat_id: str) -> str:
    base = f"basalam:{business_id}:{basalam_chat_id}"
    return hashlib.sha256(base.encode("utf-8")).hexdigest()


def _get_or_create_basalam_widget(db: Session, business_id: int, settings: Dict[str, Any]) -> CrmChatWidget:
    widget_id = settings.get("crm_widget_id")
    if widget_id:
        widget = db.query(CrmChatWidget).filter(CrmChatWidget.id == int(widget_id)).first()
        if widget and widget.business_id == int(business_id):
            return widget
    widget = (
        db.query(CrmChatWidget)
        .filter(CrmChatWidget.business_id == int(business_id), CrmChatWidget.name == "Basalam Chat Bridge")
        .first()
    )
    if widget:
        update_settings(db, business_id, {"crm_widget_id": int(widget.id)})
        return widget
    widget = crm_chat_service.create_widget(
        db=db,
        business_id=int(business_id),
        name="Basalam Chat Bridge",
        allowed_origins=[],
        settings={"channel": "basalam", "managed_by": "basalam_connector"},
        is_active=True,
    )
    update_settings(db, business_id, {"crm_widget_id": int(widget.id)})
    return widget


def _get_or_create_basalam_conversation(
    db: Session,
    business_id: int,
    settings: Dict[str, Any],
    basalam_chat_id: str,
    customer: Dict[str, Any],
) -> CrmChatConversation:
    th = _chat_token_hash(business_id, basalam_chat_id)
    existing = (
        db.query(CrmChatConversation)
        .filter(
            CrmChatConversation.business_id == int(business_id),
            CrmChatConversation.visitor_token_hash == th,
        )
        .first()
    )
    if existing:
        return existing
    widget = _get_or_create_basalam_widget(db, business_id, settings)
    full_name = _extract_person_name(customer)
    parts = [p for p in full_name.split(" ") if p]
    first_name = parts[0] if parts else "Basalam"
    last_name = " ".join(parts[1:]) if len(parts) > 1 else "User"
    email = str(customer.get("email") or "").strip().lower() or f"basalam-{basalam_chat_id}@local.invalid"
    phone = _normalize_mobile(customer.get("mobile") or customer.get("phone")) or "00000000000"
    person_id = _find_or_create_person(db, business_id, settings, customer)
    c = CrmChatConversation(
        business_id=int(business_id),
        widget_id=int(widget.id),
        status="open",
        visitor_first_name=first_name[:120],
        visitor_last_name=last_name[:120],
        visitor_email=email[:255],
        visitor_phone=phone[:64],
        visitor_token_hash=th,
        page_url=None,
        extra_metadata={"source": "basalam", "basalam_chat_id": basalam_chat_id},
        person_id=int(person_id) if person_id else None,
        assigned_to_user_id=None,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def sync_inbound_chat_messages(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    if not settings.get("chat_enabled", True):
        raise ApiError("BASALAM_CHAT_DISABLED", "Chat bridge is disabled in settings.", http_status=409)
    chat_id = str(payload.get("chat_id") or payload.get("conversation_id") or "").strip()
    if not chat_id:
        raise ApiError("BASALAM_CHAT_ID_REQUIRED", "chat_id is required.", http_status=400)
    messages = payload.get("messages")
    if isinstance(messages, dict):
        messages = [messages]
    if not isinstance(messages, list):
        message_body = str(payload.get("body") or payload.get("text") or "").strip()
        if not message_body:
            raise ApiError("BASALAM_MESSAGE_REQUIRED", "message body is required.", http_status=400)
        messages = [{"body": message_body}]
    customer = payload.get("customer") if isinstance(payload.get("customer"), dict) else {}
    conversation = _get_or_create_basalam_conversation(db, business_id, settings, chat_id, customer)
    processed = 0
    created_messages: List[int] = []
    actor_user_id = _resolve_actor_user_id(db, business_id, user_id)
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        body = str(msg.get("body") or msg.get("text") or "").strip()
        if not body:
            attachment = msg.get("attachment") if isinstance(msg.get("attachment"), dict) else {}
            files = attachment.get("files") if isinstance(attachment.get("files"), list) else []
            if files:
                first_file = files[0] if isinstance(files[0], dict) else {}
                file_url = str(first_file.get("url") or "").strip()
                file_name = str(first_file.get("name") or "attachment").strip()
                body = f"📎 {file_name}" + (f"\n{file_url}" if file_url else "")
        if not body:
            continue
        ext_msg_id = str(msg.get("id") or msg.get("message_id") or "")
        dedupe_key = _event_dedupe_key(business_id, "chat.message.received", f"{chat_id}:{ext_msg_id or body[:30]}")
        if _is_duplicate_event(business_id, dedupe_key):
            continue
        row = CrmChatMessage(
            conversation_id=int(conversation.id),
            sender_role="visitor",
            body=body[:8000],
            user_id=None,
            file_storage_id=None,
        )
        db.add(row)
        conversation.last_message_at = datetime.utcnow()
        conversation.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(row)
        processed += 1
        created_messages.append(int(row.id))
        trigger_workflows(
            db=db,
            business_id=int(business_id),
            trigger_type="crm.chat.message.received",
            trigger_data={
                "conversation_id": int(conversation.id),
                "widget_id": int(conversation.widget_id),
                "message_id": int(row.id),
                "body": body[:8000],
                "sender_role": "visitor",
                "source": "basalam",
                "basalam_chat_id": chat_id,
            },
            user_id=int(actor_user_id),
        )
        trigger_workflows(
            db=db,
            business_id=int(business_id),
            trigger_type="basalam.chat.message.received",
            trigger_data={
                "source": "basalam",
                "chat_id": chat_id,
                "message_id": ext_msg_id,
                "body": body[:8000],
                "crm_conversation_id": int(conversation.id),
            },
            user_id=int(actor_user_id),
        )
        _remember_event_in_settings(db, business_id, settings, dedupe_key)
    return {
        "accepted": True,
        "chat_id": chat_id,
        "crm_conversation_id": int(conversation.id),
        "processed_messages": processed,
        "message_ids": created_messages,
    }


async def send_chat_reply_to_basalam(
    db: Session,
    business_id: int,
    conversation_id: int,
    body: str,
    user_id: int,
    basalam_chat_id: Optional[str] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    if not settings.get("chat_enabled", True):
        raise ApiError("BASALAM_CHAT_DISABLED", "Chat bridge is disabled in settings.", http_status=409)
    c = db.query(CrmChatConversation).filter(
        CrmChatConversation.id == int(conversation_id),
        CrmChatConversation.business_id == int(business_id),
    ).first()
    if not c:
        raise ApiError("CRM_CHAT_CONVERSATION_NOT_FOUND", "Conversation not found", http_status=404)
    metadata = c.extra_metadata if isinstance(c.extra_metadata, dict) else {}
    chat_id = str(
        basalam_chat_id
        or metadata.get("basalam_chat_id")
        or ""
    ).strip()
    if not chat_id:
        raise ApiError("BASALAM_CHAT_ID_REQUIRED", "Basalam chat id not found for this conversation.", http_status=400)
    text = str(body or "").strip()
    if not text:
        raise ApiError("BASALAM_MESSAGE_REQUIRED", "Message body is required.", http_status=400)
    remote_payload = {
        "message_type": "text",
        "content": {"text": text},
    }
    remote_resp = _basalam_request(
        settings=settings,
        method="POST",
        path=f"/v1/chats/{int(chat_id)}/messages" if chat_id.isdigit() else f"/v1/chats/{chat_id}/messages",
        payload=remote_payload,
    )
    local_msg = await crm_chat_service.post_agent_message(
        db=db,
        business_id=int(business_id),
        conversation_id=int(conversation_id),
        body=text,
        user_id=int(user_id),
        automation_context={
            "operator_relay": True,
            "operator_relay_channel": "basalam",
            "basalam_chat_id": chat_id,
        },
    )
    return {
        "accepted": True,
        "chat_id": chat_id,
        "crm_conversation_id": int(conversation_id),
        "crm_message": local_msg,
        "basalam_response": remote_resp,
    }


def process_webhook(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    raw_body: bytes,
    signature: Optional[str],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        record_basalam_metric("webhook_disabled", 1)
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)

    if not _verify_webhook_signature(raw_body, signature, str(settings.get("webhook_secret") or "")):
        record_basalam_metric("webhook_signature_invalid", 1)
        raise ApiError("BASALAM_INVALID_SIGNATURE", "Invalid webhook signature.", http_status=401)

    record_basalam_metric("webhook_received", 1)

    event_type = _event_type(payload)
    event_id = _event_id(payload)
    trigger_key = _workflow_event_key(event_type)
    actor_user_id = _resolve_actor_user_id(db, business_id, user_id)
    dedupe_key = _event_dedupe_key(business_id, event_type, event_id)

    if dedupe_key in settings.get("recent_event_keys", []) or _is_duplicate_event(business_id, dedupe_key):
        logger.info(
            "basalam_webhook_duplicate",
            business_id=int(business_id),
            event_type=event_type,
            event_id=str(event_id),
        )
        record_basalam_metric("webhook_duplicate", 1)
        return {"accepted": True, "event_type": event_type, "event_id": event_id, "duplicate": True}

    trigger_workflows(
        db=db,
        business_id=int(business_id),
        trigger_type=trigger_key,
        trigger_data={
            "source": "basalam",
            "event_type": event_type,
            "event_id": event_id,
            "payload": payload,
            "received_at": datetime.utcnow().isoformat(),
        },
    )

    sync_info: Dict[str, Any] = {"processed_orders": 0, "skipped_duplicates": 0, "results": []}
    chat_info: Dict[str, Any] = {"processed_messages": 0}
    if settings.get("order_sync_enabled"):
        orders = _extract_order_candidates(payload)
        if orders:
            sync_info = _sync_orders(
                db=db,
                business_id=int(business_id),
                settings=settings,
                orders=orders,
                source="webhook",
                event_type=event_type,
                event_id=event_id,
                actor_user_id=actor_user_id,
            )
    if settings.get("chat_enabled", True) and "chat" in str(event_type or "").lower():
        inbound_body = payload.get("message") if isinstance(payload.get("message"), dict) else payload
        inferred_chat_id = payload.get("chat_id") or payload.get("conversation_id")
        if not inferred_chat_id and isinstance(payload.get("chat"), dict):
            inferred_chat_id = payload.get("chat", {}).get("id")
        if not inferred_chat_id and isinstance(inbound_body, dict):
            inferred_chat_id = inbound_body.get("chat_id")
        chat_payload: Dict[str, Any] = {
            "chat_id": inferred_chat_id
        }
        body = None
        if isinstance(inbound_body, dict):
            body = inbound_body.get("text") or inbound_body.get("body") or inbound_body.get("content")
            msg_id = inbound_body.get("id") or inbound_body.get("message_id")
            if body:
                chat_payload["messages"] = [{"id": msg_id, "body": body}]
        sender = payload.get("sender") if isinstance(payload.get("sender"), dict) else {}
        if not sender and isinstance(inbound_body, dict) and isinstance(inbound_body.get("sender"), dict):
            sender = inbound_body.get("sender")
        customer = payload.get("customer") if isinstance(payload.get("customer"), dict) else {}
        if sender:
            customer = sender
        if customer:
            chat_payload["customer"] = customer
        if chat_payload.get("chat_id"):
            chat_info = sync_inbound_chat_messages(
                db=db,
                business_id=int(business_id),
                payload=chat_payload,
                user_id=actor_user_id,
            )

    update_settings(
        db,
        business_id,
        {
            "last_webhook_event_at": datetime.utcnow().isoformat(),
            "last_webhook_event_type": event_type,
        },
    )
    _remember_event_in_settings(db, business_id, settings, dedupe_key)
    logger.info(
        "basalam_webhook_processed",
        business_id=int(business_id),
        event_type=event_type,
        workflow_trigger=trigger_key,
        processed_orders=int(sync_info.get("processed_orders") or 0),
        skipped_order_duplicates=int(sync_info.get("skipped_duplicates") or 0),
        processed_messages=int(chat_info.get("processed_messages") or 0),
    )
    record_basalam_metric("webhook_processed_ok", 1)
    return {
        "accepted": True,
        "event_type": event_type,
        "event_id": event_id,
        "workflow_trigger": trigger_key,
        **sync_info,
        **chat_info,
    }


def manual_sync_orders(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    if not settings.get("order_sync_enabled"):
        raise ApiError("BASALAM_ORDER_SYNC_DISABLED", "Order sync is disabled in Basalam settings.", http_status=409)

    orders = payload.get("orders")
    if not isinstance(orders, list):
        raise ApiError("BASALAM_INVALID_SYNC_PAYLOAD", "orders must be an array.", http_status=400)
    actor_user_id = _resolve_actor_user_id(db, business_id, user_id)
    event_type = "order.created"
    event_id = f"manual-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    sync_info = _sync_orders(
        db=db,
        business_id=int(business_id),
        settings=settings,
        orders=[o for o in orders if isinstance(o, dict)],
        source="manual",
        event_type=event_type,
        event_id=event_id,
        actor_user_id=actor_user_id,
    )
    return {
        "accepted": True,
        "event_id": event_id,
        "tag": settings.get("default_order_tag", "basalam"),
        **sync_info,
    }


def manual_sync_products(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    if not settings.get("product_sync_enabled", True):
        raise ApiError("BASALAM_PRODUCT_SYNC_DISABLED", "Product sync is disabled in settings.", http_status=409)
    _ensure_business_irr_only_for_basalam(db, int(business_id))
    products = payload.get("products")
    if isinstance(products, dict):
        products = [products]
    if not isinstance(products, list):
        raise ApiError("BASALAM_INVALID_SYNC_PAYLOAD", "products must be an array.", http_status=400)
    actor_user_id = _resolve_actor_user_id(db, business_id, user_id)
    processed = 0
    created_or_matched = 0
    manual_review = 0
    results: List[Dict[str, Any]] = []
    pending_reviews = settings.get("pending_product_reviews") if isinstance(settings.get("pending_product_reviews"), list) else []
    pending_conflicts = (
        settings.get("pending_product_conflicts")
        if isinstance(settings.get("pending_product_conflicts"), list)
        else []
    )
    variant_strategy = str(settings.get("product_variant_strategy") or "manual_review")
    for p in products:
        if not isinstance(p, dict):
            continue
        if p.get("variants") and variant_strategy == "manual_review":
            review_row = {
                "conflict_id": _new_conflict_id("variant"),
                "type": "variant_conflict",
                "direction": "pull",
                "reason": "remote_has_variants",
                "basalam_product_id": _extract_product_basalam_id(p),
                "remote_title": p.get("title") or p.get("name"),
                "payload": p,
                "created_at": datetime.utcnow().isoformat(),
            }
            pending_conflicts.append(review_row)
            manual_review += 1
            processed += 1
            results.append({"status": "manual_review_required", "reason": "remote_has_variants"})
            continue
        basalam_pid = _extract_product_basalam_id(p)
        line_like = {
            "product_id": basalam_pid,
            "product_name": p.get("title") or p.get("name") or p.get("product_name"),
            "sku": p.get("sku") or p.get("code"),
            "unit_price": p.get("price") or p.get("unit_price"),
            "unit": p.get("unit"),
            "description": p.get("description"),
        }
        product_id = _find_or_create_product(db, business_id, settings, line_like)
        processed += 1
        if product_id:
            created_or_matched += 1
            results.append(
                {
                    "status": "synced",
                    "basalam_product_id": basalam_pid,
                    "product_id": int(product_id),
                }
            )
        else:
            manual_review += 1
            review_row = {
                "type": "product",
                "basalam_product_id": basalam_pid,
                "payload": p,
                "created_at": datetime.utcnow().isoformat(),
            }
            pending_reviews.append(review_row)
            results.append({"status": "manual_review_required", "basalam_product_id": basalam_pid})
            trigger_workflows(
                db=db,
                business_id=int(business_id),
                trigger_type="basalam.webhook.received",
                trigger_data={
                    "source": "basalam",
                    "event_type": "product.manual_review_required",
                    "payload": p,
                    "review_row": review_row,
                },
                user_id=int(actor_user_id),
            )
    update_settings(
        db,
        business_id,
        {
            "pending_product_reviews": pending_reviews[-200:],
            "pending_product_conflicts": pending_conflicts[-300:],
        },
    )
    return {
        "accepted": True,
        "processed_products": processed,
        "synced_products": created_or_matched,
        "manual_review_products": manual_review,
        "results": results,
    }


def _get_local_product(
    db: Session,
    business_id: int,
    item: Dict[str, Any],
) -> Optional[Product]:
    local_id = item.get("local_product_id") or item.get("product_id")
    if str(local_id or "").isdigit():
        p = db.query(Product).filter(Product.business_id == int(business_id), Product.id == int(local_id)).first()
        if p:
            return p
    code = str(item.get("code") or item.get("sku") or "").strip()
    if code:
        p = db.query(Product).filter(Product.business_id == int(business_id), Product.code == code).first()
        if p:
            return p
    name = str(item.get("name") or "").strip()
    if name:
        return db.query(Product).filter(Product.business_id == int(business_id), Product.name == name).first()
    return None


def _build_basalam_product_request_from_local(
    local_product: Product,
    item: Dict[str, Any],
    settings: Dict[str, Any],
) -> Any:
    try:
        from basalam_sdk.core.models import ProductRequestSchema
    except Exception as exc:
        raise ApiError(
            "BASALAM_SDK_NOT_INSTALLED",
            "basalam-sdk is not installed. Install package basalam-sdk in API environment.",
            http_status=500,
            details={"reason": str(exc)},
        )
    stock = item.get("stock")
    if stock is None:
        stock = settings.get("default_basalam_stock", 1)
    try:
        stock_int = max(0, int(stock))
    except Exception:
        stock_int = 1
    price_src = item.get("primary_price")
    if price_src is None:
        price_src = local_product.base_sales_price
    price_wire = _internal_rial_amount_to_basalam_wire(price_src, settings)
    price_int = int(round(price_wire))
    req_payload: Dict[str, Any] = {
        "name": str(item.get("name") or local_product.name or "").strip() or f"Product {local_product.id}",
        "brief": str(item.get("brief") or "")[:200] or None,
        "description": str(item.get("description") or local_product.description or "") or None,
        "primary_price": price_int if price_int > 0 else None,
        "stock": stock_int,
        "sku": str(item.get("sku") or local_product.code or "").strip() or None,
    }
    category_id = item.get("category_id")
    if category_id is None:
        category_id = settings.get("default_basalam_category_id")
    if str(category_id or "").isdigit():
        req_payload["category_id"] = int(category_id)
    clean = {k: v for k, v in req_payload.items() if v is not None}
    return ProductRequestSchema(**clean)


def publish_products_to_basalam(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    _ensure_business_irr_only_for_basalam(db, int(business_id))
    products = payload.get("products")
    if isinstance(products, dict):
        products = [products]
    if not isinstance(products, list):
        raise ApiError("BASALAM_INVALID_SYNC_PAYLOAD", "products must be an array.", http_status=400)
    vendor_id_raw = payload.get("vendor_id") or settings.get("default_basalam_vendor_id")
    if not str(vendor_id_raw or "").isdigit():
        raise ApiError(
            "BASALAM_VENDOR_ID_REQUIRED",
            "vendor_id is required for product publish (or set default_basalam_vendor_id).",
            http_status=400,
        )
    vendor_id = int(vendor_id_raw)
    actor_user_id = _resolve_actor_user_id(db, business_id, user_id)
    client = _get_basalam_sdk_client(settings)
    mappings = settings.get("mappings", {}).get("products", {})
    local_to_remote: Dict[str, str] = {}
    for k, v in mappings.items():
        local_to_remote[str(v)] = str(k)
    retry_queue = (
        settings.get("pending_product_publish_retries")
        if isinstance(settings.get("pending_product_publish_retries"), list)
        else []
    )
    conflict_queue = (
        settings.get("pending_product_conflicts")
        if isinstance(settings.get("pending_product_conflicts"), list)
        else []
    )
    price_strategy = str(settings.get("product_conflict_price_strategy") or "local_wins")
    stock_strategy = str(settings.get("product_conflict_stock_strategy") or "local_wins")
    variant_strategy = str(settings.get("product_variant_strategy") or "manual_review")

    processed = 0
    published = 0
    results: List[Dict[str, Any]] = []

    for item in products:
        if not isinstance(item, dict):
            continue
        local_product = _get_local_product(db, business_id, item)
        if not local_product:
            results.append({"status": "local_product_not_found", "input": item})
            continue
        if (item.get("variants") or (local_product.inventory_mode or "bulk") == "unique") and variant_strategy == "manual_review":
            processed += 1
            conflict_queue.append(
                {
                    "conflict_id": _new_conflict_id("variant"),
                    "type": "variant_conflict",
                    "direction": "push",
                    "reason": "local_has_variants_or_unique_mode",
                    "local_product_id": int(local_product.id),
                    "local_product_name": local_product.name,
                    "local_product_code": local_product.code,
                    "payload": item,
                    "created_at": datetime.utcnow().isoformat(),
                }
            )
            results.append({"status": "manual_review_required", "local_product_id": int(local_product.id), "reason": "variant_conflict"})
            continue
        req = _build_basalam_product_request_from_local(local_product, item, settings)
        remote_id = str(item.get("basalam_product_id") or local_to_remote.get(str(local_product.id)) or "").strip()
        try:
            req_payload = req.model_dump(exclude_none=True)
            if remote_id.isdigit() and (price_strategy != "local_wins" or stock_strategy != "local_wins"):
                remote_obj = client.core.get_product_sync(product_id=int(remote_id))
                remote_dict = _sdk_to_dict(remote_obj)
                remote_price, remote_stock = _extract_remote_price_stock(remote_dict if isinstance(remote_dict, dict) else {})
                local_price = req_payload.get("primary_price")
                local_stock = req_payload.get("stock")
                price_diff = remote_price is not None and local_price is not None and int(remote_price) != int(local_price)
                stock_diff = remote_stock is not None and local_stock is not None and int(remote_stock) != int(local_stock)
                if (price_diff and price_strategy == "manual_review") or (stock_diff and stock_strategy == "manual_review"):
                    processed += 1
                    conflict_queue.append(
                        {
                            "conflict_id": _new_conflict_id("field"),
                            "type": "field_conflict",
                            "direction": "push",
                            "local_product_id": int(local_product.id),
                            "local_product_name": local_product.name,
                            "local_product_code": local_product.code,
                            "basalam_product_id": int(remote_id),
                            "remote_title": remote_dict.get("title") if isinstance(remote_dict, dict) else None,
                            "local_price": local_price,
                            "remote_price": remote_price,
                            "local_stock": local_stock,
                            "remote_stock": remote_stock,
                            "created_at": datetime.utcnow().isoformat(),
                        }
                    )
                    results.append({"status": "manual_review_required", "local_product_id": int(local_product.id), "reason": "field_conflict"})
                    continue
                if price_diff and price_strategy == "remote_wins":
                    req_payload["primary_price"] = int(remote_price)
                if stock_diff and stock_strategy == "remote_wins":
                    req_payload["stock"] = int(remote_stock)
                from basalam_sdk.core.models import ProductRequestSchema

                req = ProductRequestSchema(**req_payload)
            if remote_id.isdigit():
                resp = client.core.update_product_sync(product_id=int(remote_id), request=req)
                action = "updated"
            else:
                resp = client.core.create_product_sync(vendor_id=vendor_id, request=req)
                action = "created"
            parsed = _sdk_to_dict(resp)
            pdata = parsed.get("data") if isinstance(parsed, dict) and isinstance(parsed.get("data"), dict) else parsed
            resolved_remote_id = str((pdata or {}).get("id") or remote_id or "").strip()
            if resolved_remote_id:
                mappings[resolved_remote_id] = int(local_product.id)
            processed += 1
            published += 1
            result_row = {
                "status": action,
                "local_product_id": int(local_product.id),
                "basalam_product_id": resolved_remote_id or None,
            }
            results.append(result_row)
            trigger_workflows(
                db=db,
                business_id=int(business_id),
                trigger_type="basalam.order.updated",
                trigger_data={
                    "source": "basalam",
                    "event_type": "product.publish",
                    "action": action,
                    "local_product_id": int(local_product.id),
                    "basalam_product_id": resolved_remote_id or None,
                },
                user_id=int(actor_user_id),
            )
        except Exception as exc:
            processed += 1
            retry_queue.append(
                {
                    "local_product_id": int(local_product.id),
                    "vendor_id": int(vendor_id),
                    "payload": item,
                    "error": str(exc),
                    "created_at": datetime.utcnow().isoformat(),
                }
            )
            results.append(
                {
                    "status": "failed",
                    "local_product_id": int(local_product.id),
                    "reason": str(exc),
                }
            )

    base_mappings = settings.get("mappings", {}) if isinstance(settings.get("mappings"), dict) else {}
    base_mappings["products"] = mappings
    update_settings(
        db,
        business_id,
        {
            "mappings": base_mappings,
            "last_product_push_at": datetime.utcnow().isoformat(),
            "pending_product_publish_retries": retry_queue[-300:],
            "pending_product_conflicts": conflict_queue[-300:],
        },
    )
    return {
        "accepted": True,
        "processed_products": processed,
        "published_products": published,
        "results": results,
    }


def _extract_basalam_products(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    if isinstance(payload.get("data"), list):
        return [x for x in payload.get("data", []) if isinstance(x, dict)]
    data = payload.get("data")
    if isinstance(data, dict) and isinstance(data.get("data"), list):
        return [x for x in data.get("data", []) if isinstance(x, dict)]
    if isinstance(payload.get("items"), list):
        return [x for x in payload.get("items", []) if isinstance(x, dict)]
    return []


def _extract_remote_price_stock(remote_payload: Dict[str, Any]) -> Tuple[Optional[int], Optional[int]]:
    price_val = remote_payload.get("primary_price")
    if price_val is None:
        price_val = remote_payload.get("price")
    try:
        price_int = int(_parse_decimal(price_val, 0)) if price_val is not None else None
    except Exception:
        price_int = None
    stock_int: Optional[int] = None
    inv = remote_payload.get("inventory")
    if isinstance(inv, dict):
        for k in ("stock", "available", "quantity", "total"):
            if inv.get(k) is not None:
                try:
                    stock_int = int(inv.get(k))
                    break
                except Exception:
                    pass
    if stock_int is None and remote_payload.get("stock") is not None:
        try:
            stock_int = int(remote_payload.get("stock"))
        except Exception:
            stock_int = None
    return price_int, stock_int


def _new_conflict_id(prefix: str = "pc") -> str:
    return f"{prefix}-{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}"


def _append_sync_dead_letter(db: Session, business_id: int, entry: Dict[str, Any]) -> None:
    settings = get_settings(db, business_id)
    q = settings.get("sync_dead_letter")
    queue = [x for x in q if isinstance(x, dict)] if isinstance(q, list) else []
    row = dict(entry)
    row.setdefault("created_at", datetime.utcnow().isoformat())
    row.setdefault("dlq_id", _new_conflict_id("dlq"))
    queue.append(row)
    update_settings(db, business_id, {"sync_dead_letter": queue[-SYNC_DEAD_LETTER_MAX:]})


def list_sync_dead_letter(
    db: Session,
    business_id: int,
    *,
    limit: int = 50,
    offset: int = 0,
    item_type: Optional[str] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    q = [x for x in settings.get("sync_dead_letter", []) if isinstance(x, dict)]
    if item_type:
        t = str(item_type).strip().lower()
        q = [x for x in q if str(x.get("type") or "").lower() == t]
    total = len(q)
    lo = max(0, int(offset))
    hi = lo + max(1, min(200, int(limit)))
    return {"items": q[lo:hi], "total": total, "limit": limit, "offset": lo}


def clear_sync_dead_letter(
    db: Session,
    business_id: int,
    *,
    mode: str = "all",
    dlq_ids: Optional[List[Any]] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    q = [x for x in settings.get("sync_dead_letter", []) if isinstance(x, dict)]
    m = str(mode or "").strip().lower()
    if m == "all":
        update_settings(db, business_id, {"sync_dead_letter": []})
        return {"accepted": True, "cleared_count": len(q), "remaining_count": 0, "mode": "all"}
    if m == "ids":
        ids = dlq_ids if isinstance(dlq_ids, list) else []
        id_set = {str(i).strip() for i in ids if i is not None and str(i).strip()}
        if not id_set:
            return {"accepted": True, "cleared_count": 0, "remaining_count": len(q), "mode": "ids"}
        remaining = [x for x in q if str(x.get("dlq_id") or "").strip() not in id_set]
        cleared = len(q) - len(remaining)
        update_settings(db, business_id, {"sync_dead_letter": remaining[-SYNC_DEAD_LETTER_MAX:]})
        return {
            "accepted": True,
            "cleared_count": cleared,
            "remaining_count": len(remaining),
            "mode": "ids",
        }
    raise ApiError(
        "BASALAM_DLQ_INVALID_CLEAR_MODE",
        "clear mode must be 'all' or 'ids'.",
        http_status=400,
    )


def pull_products_from_basalam(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    if not settings.get("product_sync_enabled", True):
        raise ApiError("BASALAM_PRODUCT_SYNC_DISABLED", "Product sync is disabled in settings.", http_status=409)
    page = int(payload.get("page") or 1)
    per_page = int(payload.get("per_page") or 50)
    params: Dict[str, Any] = {"page": max(1, page), "per_page": max(1, min(200, per_page))}
    if payload.get("created_at"):
        params["created_at"] = payload.get("created_at")
    client = _get_basalam_sdk_client(settings)
    try:
        remote = client.core.request_sync(method="GET", path="/v1/products", params=params, require_auth=True)
    except Exception as exc:
        raise ApiError(
            "BASALAM_SDK_CALL_ERROR",
            "Basalam SDK request failed for products pull.",
            http_status=502,
            details={"reason": str(exc)},
        )
    parsed = _sdk_to_dict(remote)
    remote_payload = parsed if isinstance(parsed, dict) else {"data": parsed}
    products = _extract_basalam_products(remote_payload)
    sync_result = manual_sync_products(
        db=db,
        business_id=int(business_id),
        payload={"products": products},
        user_id=user_id,
    )
    update_settings(
        db,
        business_id,
        {
            "last_product_pull_at": datetime.utcnow().isoformat(),
        },
    )
    return {
        "accepted": True,
        "fetched_products": len(products),
        **sync_result,
    }


def push_products_incremental(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    if not settings.get("enabled"):
        raise ApiError("BASALAM_DISABLED", "Basalam integration is disabled for this business.", http_status=409)
    if not settings.get("product_sync_enabled", True):
        raise ApiError("BASALAM_PRODUCT_SYNC_DISABLED", "Product sync is disabled in settings.", http_status=409)
    since_minutes = int(payload.get("since_minutes") or 120)
    limit = int(payload.get("limit") or 50)
    if since_minutes < 1:
        since_minutes = 1
    if limit < 1:
        limit = 1
    if limit > 500:
        limit = 500
    cutoff = datetime.utcnow() - timedelta(minutes=since_minutes)
    rows = (
        db.query(Product)
        .filter(Product.business_id == int(business_id), Product.updated_at >= cutoff)
        .order_by(Product.updated_at.desc())
        .limit(limit)
        .all()
    )
    products_payload: List[Dict[str, Any]] = []
    for p in rows:
        products_payload.append(
            {
                "local_product_id": int(p.id),
                "name": p.name,
                "description": p.description,
                "sku": p.code,
                "primary_price": int(_parse_decimal(p.base_sales_price, 0)),
                "stock": int(payload.get("stock") or settings.get("default_basalam_stock", 1)),
            }
        )
    out = publish_products_to_basalam(
        db=db,
        business_id=int(business_id),
        payload={
            "vendor_id": payload.get("vendor_id") or settings.get("default_basalam_vendor_id"),
            "products": products_payload,
        },
        user_id=user_id,
    )
    return {"accepted": True, "candidates": len(rows), **out}


def retry_failed_product_publishes(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    queue = settings.get("pending_product_publish_retries")
    if not isinstance(queue, list) or not queue:
        return {"accepted": True, "retried": 0, "published_products": 0, "remaining_queue": 0}
    limit = int(payload.get("limit") or 20)
    limit = max(1, min(100, limit))
    to_retry = [x for x in queue[:limit] if isinstance(x, dict)]
    remaining = [x for x in queue[limit:] if isinstance(x, dict)]
    merged_results: List[Dict[str, Any]] = []
    published_total = 0
    for item in to_retry:
        local_id = item.get("local_product_id")
        publish_payload = item.get("payload") if isinstance(item.get("payload"), dict) else {}
        if local_id and "local_product_id" not in publish_payload:
            publish_payload["local_product_id"] = local_id
        out = publish_products_to_basalam(
            db=db,
            business_id=int(business_id),
            payload={
                "vendor_id": item.get("vendor_id") or payload.get("vendor_id") or settings.get("default_basalam_vendor_id"),
                "products": [publish_payload],
            },
            user_id=user_id,
        )
        merged_results.extend(out.get("results", []))
        published_total += int(out.get("published_products") or 0)
    latest = get_settings(db, business_id)
    latest_q = latest.get("pending_product_publish_retries")
    if not isinstance(latest_q, list):
        latest_q = []
    update_settings(
        db,
        business_id,
        {"pending_product_publish_retries": (remaining + latest_q)[-300:]},
    )
    return {
        "accepted": True,
        "retried": len(to_retry),
        "published_products": published_total,
        "remaining_queue": len(remaining),
        "results": merged_results,
    }


def list_product_conflicts(
    db: Session,
    business_id: int,
    *,
    conflict_type: Optional[str] = None,
    direction: Optional[str] = None,
    search: Optional[str] = None,
    sort_by: Optional[str] = None,
    sort_dir: Optional[str] = None,
    limit: int = 25,
    offset: int = 0,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    q = settings.get("pending_product_conflicts")
    items = [dict(x) for x in q if isinstance(x, dict)] if isinstance(q, list) else []
    for i, row in enumerate(items):
        if not row.get("conflict_id"):
            row["conflict_id"] = f"legacy-{i + 1}"
    t = str(conflict_type or "").strip().lower()
    if t and t != "all":
        items = [x for x in items if str(x.get("type") or "").strip().lower() == t]
    d = str(direction or "").strip().lower()
    if d and d != "all":
        items = [x for x in items if str(x.get("direction") or "").strip().lower() == d]
    s = str(search or "").strip().lower()
    if s:
        def _hit(x: Dict[str, Any]) -> bool:
            for key in ("conflict_id", "type", "direction", "reason", "last_error", "local_product_id", "basalam_product_id"):
                if s in str(x.get(key) or "").lower():
                    return True
            return False
        items = [x for x in items if _hit(x)]
    sb = str(sort_by or "created_at").strip().lower()
    sd = str(sort_dir or "desc").strip().lower()
    reverse = sd != "asc"
    if sb == "type":
        items.sort(key=lambda x: str(x.get("type") or ""), reverse=reverse)
    elif sb == "direction":
        items.sort(key=lambda x: str(x.get("direction") or ""), reverse=reverse)
    elif sb == "conflict_id":
        items.sort(key=lambda x: str(x.get("conflict_id") or ""), reverse=reverse)
    else:
        # default: created_at
        items.sort(key=lambda x: str(x.get("created_at") or ""), reverse=reverse)
    total = len(items)
    lim = max(1, min(200, int(limit)))
    off = max(0, int(offset))
    page_items = items[off:off + lim]
    by_type: Dict[str, int] = {}
    by_direction: Dict[str, int] = {}
    for x in items:
        tkey = str(x.get("type") or "unknown")
        dkey = str(x.get("direction") or "unknown")
        by_type[tkey] = int(by_type.get(tkey, 0)) + 1
        by_direction[dkey] = int(by_direction.get(dkey, 0)) + 1
    return {
        "accepted": True,
        "items": page_items,
        "total": total,
        "limit": lim,
        "offset": off,
        "has_more": (off + lim) < total,
        "summary": {"by_type": by_type, "by_direction": by_direction},
    }


def clear_product_conflicts(
    db: Session,
    business_id: int,
) -> Dict[str, Any]:
    update_settings(db, business_id, {"pending_product_conflicts": []})
    return {"accepted": True, "cleared": True}


def resolve_product_conflicts(
    db: Session,
    business_id: int,
    payload: Dict[str, Any],
    user_id: Optional[int] = None,
) -> Dict[str, Any]:
    settings = get_settings(db, business_id)
    q = settings.get("pending_product_conflicts")
    queue = [dict(x) for x in q if isinstance(x, dict)] if isinstance(q, list) else []
    for i, row in enumerate(queue):
        if not row.get("conflict_id"):
            row["conflict_id"] = f"legacy-{i + 1}"

    resolution = str(payload.get("resolution") or "").strip()
    if resolution not in {"local_wins", "remote_wins", "discard"}:
        raise ApiError(
            "BASALAM_CONFLICT_RESOLUTION_INVALID",
            "resolution must be one of: local_wins, remote_wins, discard",
            http_status=400,
        )
    selected_ids = payload.get("conflict_ids")
    target_ids = set(str(x) for x in selected_ids if str(x).strip()) if isinstance(selected_ids, list) else set()
    limit = int(payload.get("limit") or 20)
    limit = max(1, min(200, limit))
    actor_user_id = _resolve_actor_user_id(db, business_id, user_id)

    processed = 0
    resolved = 0
    results: List[Dict[str, Any]] = []
    remaining: List[Dict[str, Any]] = []

    for row in queue:
        cid = str(row.get("conflict_id") or "")
        should_take = (cid in target_ids) if target_ids else (processed < limit)
        if not should_take:
            remaining.append(row)
            continue
        processed += 1
        try:
            if resolution == "discard":
                resolved += 1
                results.append({"conflict_id": cid, "status": "discarded"})
                continue

            ctype = str(row.get("type") or "")
            if ctype == "field_conflict":
                local_product_id = row.get("local_product_id")
                if resolution == "local_wins":
                    local_item = {"local_product_id": local_product_id}
                    out = publish_products_to_basalam(
                        db=db,
                        business_id=int(business_id),
                        payload={
                            "vendor_id": payload.get("vendor_id") or settings.get("default_basalam_vendor_id"),
                            "products": [local_item],
                        },
                        user_id=actor_user_id,
                    )
                    ok = int(out.get("published_products") or 0) > 0
                    if ok:
                        resolved += 1
                        results.append({"conflict_id": cid, "status": "resolved_local_wins"})
                    else:
                        row["last_error"] = "publish_failed"
                        remaining.append(row)
                        results.append({"conflict_id": cid, "status": "failed", "reason": "publish_failed"})
                else:
                    p = None
                    if str(local_product_id or "").isdigit():
                        p = (
                            db.query(Product)
                            .filter(Product.business_id == int(business_id), Product.id == int(local_product_id))
                            .first()
                        )
                    if not p:
                        row["last_error"] = "local_product_not_found"
                        remaining.append(row)
                        results.append({"conflict_id": cid, "status": "failed", "reason": "local_product_not_found"})
                    else:
                        remote_price = row.get("remote_price")
                        if remote_price is not None:
                            p.base_sales_price = _parse_decimal(remote_price, 0)
                        db.add(p)
                        db.commit()
                        resolved += 1
                        results.append({"conflict_id": cid, "status": "resolved_remote_wins"})
            elif ctype == "variant_conflict":
                direction = str(row.get("direction") or "")
                if resolution == "local_wins" and direction == "push":
                    local_item = row.get("payload") if isinstance(row.get("payload"), dict) else {}
                    if row.get("local_product_id") and not local_item.get("local_product_id"):
                        local_item["local_product_id"] = row.get("local_product_id")
                    out = publish_products_to_basalam(
                        db=db,
                        business_id=int(business_id),
                        payload={
                            "vendor_id": payload.get("vendor_id") or settings.get("default_basalam_vendor_id"),
                            "products": [local_item],
                        },
                        user_id=actor_user_id,
                    )
                    ok = int(out.get("published_products") or 0) > 0
                    if ok:
                        resolved += 1
                        results.append({"conflict_id": cid, "status": "resolved_local_wins"})
                    else:
                        row["last_error"] = "publish_failed"
                        remaining.append(row)
                        results.append({"conflict_id": cid, "status": "failed", "reason": "publish_failed"})
                elif resolution == "remote_wins" and direction == "pull":
                    remote_p = row.get("payload") if isinstance(row.get("payload"), dict) else {}
                    line_like = {
                        "product_id": _extract_product_basalam_id(remote_p),
                        "product_name": remote_p.get("title") or remote_p.get("name") or remote_p.get("product_name"),
                        "sku": remote_p.get("sku") or remote_p.get("code"),
                        "unit_price": remote_p.get("price") or remote_p.get("unit_price"),
                        "description": remote_p.get("description"),
                    }
                    pid = _find_or_create_product(db, business_id, settings, line_like)
                    if pid:
                        resolved += 1
                        results.append({"conflict_id": cid, "status": "resolved_remote_wins"})
                    else:
                        row["last_error"] = "remote_sync_failed"
                        remaining.append(row)
                        results.append({"conflict_id": cid, "status": "failed", "reason": "remote_sync_failed"})
                else:
                    row["last_error"] = "unsupported_resolution_for_variant_conflict"
                    remaining.append(row)
                    results.append(
                        {
                            "conflict_id": cid,
                            "status": "failed",
                            "reason": "unsupported_resolution_for_variant_conflict",
                        }
                    )
            else:
                row["last_error"] = "unknown_conflict_type"
                remaining.append(row)
                results.append({"conflict_id": cid, "status": "failed", "reason": "unknown_conflict_type"})
        except Exception as exc:
            row["last_error"] = str(exc)
            remaining.append(row)
            results.append({"conflict_id": cid, "status": "failed", "reason": str(exc)})

    update_settings(db, business_id, {"pending_product_conflicts": remaining[-300:]})
    return {
        "accepted": True,
        "processed": processed,
        "resolved": resolved,
        "remaining_conflicts": len(remaining),
        "results": results,
    }
