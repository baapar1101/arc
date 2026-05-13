"""
ایجاد/ویرایش گروهی کالا برای یکپارچه‌سازی (مثل ووکامرس).
"""

from typing import Any, Dict, List, Optional

from pydantic import ValidationError
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.product import ProductCreateRequest, ProductUpdateRequest
from adapters.db.models.product import Product
from app.core.auth_dependency import AuthContext
from app.core.permissions import has_business_permission_for_business
from app.core.responses import ApiError
from app.services.product_service import (
    create_product,
    update_product,
    invalidate_products_cache,
)

MAX_BULK_PRODUCT_ITEMS = 1000


def _api_err(ae: ApiError) -> Dict[str, str]:
    d = getattr(ae, "detail", None)
    if isinstance(d, dict):
        p = d.get("error") or {}
        return {"code": str(p.get("code") or "API_ERROR"), "message": str(p.get("message") or str(ae))}
    return {"code": "API_ERROR", "message": str(ae)}


def bulk_upsert_products_integration(
    db: Session,
    business_id: int,
    auth_context: AuthContext,
    body: Dict[str, Any],
) -> Dict[str, Any]:
    items = body.get("items")
    if not isinstance(items, list):
        raise ApiError("INVALID_REQUEST", "items باید آرایه باشد", http_status=400)

    if len(items) > MAX_BULK_PRODUCT_ITEMS:
        raise ApiError(
            "BULK_TOO_LARGE",
            f"حداکثر {MAX_BULK_PRODUCT_ITEMS} آیتم در هر درخواست مجاز است",
            http_status=400,
        )

    create_if_update_missing = bool(body.get("create_if_update_missing", True))
    can_add = has_business_permission_for_business(auth_context, db, business_id, "products", "add")
    can_edit = has_business_permission_for_business(auth_context, db, business_id, "products", "edit")

    results: List[Dict[str, Any]] = []
    any_success = False

    for idx, raw in enumerate(items):
        base = {"index": idx}
        if isinstance(raw, dict) and raw.get("client_ref") is not None:
            base["client_ref"] = str(raw.get("client_ref") or "").strip() or None
        else:
            base["client_ref"] = None

        if not isinstance(raw, dict):
            results.append({**base, "status": "failed", "product_id": None, "error_code": "INVALID_ITEM", "message": "آیتم نامعتبر"})
            continue

        payload = raw.get("payload")
        if not isinstance(payload, dict):
            results.append(
                {**base, "status": "failed", "product_id": None, "error_code": "INVALID_PAYLOAD", "message": "payload الزامی است"}
            )
            continue

        raw_pid = raw.get("product_id")
        hesabix_product_id = None
        if raw_pid not in (None, ""):
            try:
                hesabix_product_id = int(raw_pid)
            except (ValueError, TypeError):
                hesabix_product_id = None
        if hesabix_product_id is not None and hesabix_product_id <= 0:
            hesabix_product_id = None

        def _row(st: str, pid: Any, err: Optional[str], msg: Optional[str]) -> Dict[str, Any]:
            o: Dict[str, Any] = {**base, "status": st, "product_id": pid}
            if err:
                o["error_code"] = err
            if msg:
                o["message"] = msg
            return o

        need_create = hesabix_product_id is None

        if not need_create:
            if not can_edit:
                results.append(_row("failed", None, "FORBIDDEN", "مجوز ویرایش محصولات نیست"))
                continue

            belongs = (
                db.query(Product.id)
                .filter(Product.id == hesabix_product_id, Product.business_id == business_id)
                .first()
            )
            if not belongs:
                if create_if_update_missing:
                    need_create = True
                else:
                    results.append(_row("failed", None, "PRODUCT_NOT_FOUND", "کالا برای ویرایش یافت نشد"))
                    continue
            else:
                try:
                    p_upd = ProductUpdateRequest.model_validate(payload)
                except ValidationError as ve:
                    results.append(_row("failed", None, "VALIDATION_ERROR", str(ve)))
                    continue
                try:
                    out = update_product(
                        db,
                        hesabix_product_id,
                        business_id,
                        p_upd,
                        defer_cache_invalidation=True,
                    )
                except ApiError as ae:
                    e = _api_err(ae)
                    results.append(_row("failed", None, e["code"], e["message"]))
                    continue
                except IntegrityError as ie:
                    results.append(_row("failed", None, "INTEGRITY_ERROR", str(getattr(ie, "orig", ie) or ie)))
                    continue

                if out and isinstance(out.get("data"), dict):
                    nid = out["data"].get("id")
                    any_success = True
                    results.append(_row("updated", int(nid) if nid is not None else hesabix_product_id, None, None))
                    continue
                if out is None and create_if_update_missing:
                    need_create = True
                else:
                    results.append(_row("failed", None, "UPDATE_FAILED", "به‌روزرسانی ناموفق بود"))
                    continue

        if need_create:
            if not can_add:
                results.append(_row("failed", None, "FORBIDDEN", "مجوز ایجاد محصولات نیست"))
                continue
            try:
                p_new = ProductCreateRequest.model_validate(payload)
            except ValidationError as ve:
                results.append(_row("failed", None, "VALIDATION_ERROR", str(ve)))
                continue
            try:
                cr = create_product(db, business_id, p_new, defer_cache_invalidation=True)
                pdata = cr.get("data") or {}
                nid = pdata.get("id")
                any_success = True
                results.append(_row("created", int(nid) if nid is not None else None, None, None))
            except ApiError as ae:
                e = _api_err(ae)
                results.append(_row("failed", None, e["code"], e["message"]))
            except IntegrityError as ie:
                results.append(_row("failed", None, "INTEGRITY_ERROR", str(getattr(ie, "orig", ie) or ie)))

    if any_success:
        invalidate_products_cache(business_id=business_id)

    summary = {
        "total": len(items),
        "created": sum(1 for r in results if r.get("status") == "created"),
        "updated": sum(1 for r in results if r.get("status") == "updated"),
        "failed": sum(1 for r in results if r.get("status") == "failed"),
    }
    return {"results": results, "summary": summary}
