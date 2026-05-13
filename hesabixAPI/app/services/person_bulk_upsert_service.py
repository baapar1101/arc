"""
ایجاد/ویرایش گروهی اشخاص برای ادغام (مثل ووکامرس) — هر آیتم جدا خطا؛ کش در انتهای موفقیت یک‌بار invalidate.
"""

from typing import Any, Dict, List, Optional

from pydantic import ValidationError
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonUpdateRequest
from adapters.db.models.person import Person
from app.core.auth_dependency import AuthContext
from app.core.permissions import has_business_permission_for_business
from app.core.responses import ApiError
from app.services.person_service import create_person, update_person, invalidate_persons_cache

MAX_BULK_PERSON_ITEMS = 1000


def api_error_detail(err: ApiError) -> Dict[str, str]:
    d = getattr(err, "detail", None)
    if isinstance(d, dict):
        payload = d.get("error") or {}
        code = payload.get("code") or getattr(err, "status_code", "API_ERROR")
        msg = payload.get("message") or str(err)
        return {"code": str(code), "message": str(msg)}
    return {"code": "API_ERROR", "message": str(err)}


def bulk_upsert_persons_integration(
    db: Session,
    business_id: int,
    auth_context: AuthContext,
    body: Dict[str, Any],
) -> Dict[str, Any]:
    items = body.get("items")
    if not isinstance(items, list):
        raise ApiError("INVALID_REQUEST", "items باید آرایه باشد", http_status=400)

    if len(items) > MAX_BULK_PERSON_ITEMS:
        raise ApiError(
            "BULK_TOO_LARGE",
            f"حداکثر {MAX_BULK_PERSON_ITEMS} آیتم در هر درخواست مجاز است",
            http_status=400,
        )

    create_if_update_missing = bool(body.get("create_if_update_missing", True))

    can_add = has_business_permission_for_business(auth_context, db, business_id, "people", "add")
    can_edit = has_business_permission_for_business(auth_context, db, business_id, "people", "edit")

    results: List[Dict[str, Any]] = []
    any_success = False

    for idx, raw in enumerate(items):
        row_base = {"index": idx}

        def _cref(c: Any) -> Optional[str]:
            if c is None:
                return None
            s = str(c).strip()
            return s or None

        if not isinstance(raw, dict):
            results.append(
                {
                    **row_base,
                    "client_ref": None,
                    "status": "failed",
                    "person_id": None,
                    "error_code": "INVALID_ITEM",
                    "message": "آیتم باید یک شیٔ JSON باشد",
                }
            )
            continue

        client_ref = _cref(raw.get("client_ref"))
        row_base["client_ref"] = client_ref

        payload = raw.get("payload")
        if not isinstance(payload, dict):
            results.append(
                {
                    **row_base,
                    "status": "failed",
                    "person_id": None,
                    "error_code": "INVALID_PAYLOAD",
                    "message": "فیلد payload الزامی است و باید شیٔ باشد",
                }
            )
            continue

        raw_pid = raw.get("person_id")
        person_id: Optional[int] = None
        if raw_pid not in (None, ""):
            try:
                person_id = int(raw_pid)
            except (ValueError, TypeError):
                person_id = None
        if person_id is not None and person_id <= 0:
            person_id = None

        resolved_to_create = person_id is None

        # --- مسیر به‌روزرسانی ---
        if not resolved_to_create:
            if not can_edit:
                results.append(
                    {
                        **row_base,
                        "status": "failed",
                        "person_id": None,
                        "error_code": "FORBIDDEN",
                        "message": "مجوز ویرایش اشخاص (people.edit) وجود ندارد",
                    }
                )
                continue

            exists_here = (
                db.query(Person.id)
                .filter(Person.id == person_id, Person.business_id == business_id)
                .first()
            )
            if not exists_here:
                if create_if_update_missing:
                    resolved_to_create = True
                else:
                    results.append(
                        {
                            **row_base,
                            "status": "failed",
                            "person_id": None,
                            "error_code": "PERSON_NOT_FOUND",
                            "message": "شخص برای به‌روزرسانی یافت نشد یا متعلق به این کسب‌وکار نیست",
                        }
                    )
                    continue
            else:
                try:
                    p_update = PersonUpdateRequest.model_validate(payload)
                except ValidationError as ve:
                    results.append(
                        {
                            **row_base,
                            "status": "failed",
                            "person_id": None,
                            "error_code": "VALIDATION_ERROR",
                            "message": str(ve),
                        }
                    )
                    continue
                try:
                    updated = update_person(
                        db,
                        int(person_id),
                        business_id,
                        p_update,
                        defer_cache_invalidation=True,
                    )
                except ApiError as ae:
                    de = api_error_detail(ae)
                    results.append(
                        {
                            **row_base,
                            "status": "failed",
                            "person_id": None,
                            "error_code": de["code"],
                            "message": de["message"],
                        }
                    )
                    continue
                except ValueError as ve:
                    results.append(
                        {
                            **row_base,
                            "status": "failed",
                            "person_id": None,
                            "error_code": "VALUE_ERROR",
                            "message": str(ve),
                        }
                    )
                    continue

                if updated and isinstance(updated.get("data"), dict):
                    nid = updated["data"].get("id")
                    any_success = True
                    results.append(
                        {
                            **row_base,
                            "status": "updated",
                            "person_id": int(nid)
                            if nid is not None
                            else int(person_id),
                        }
                    )
                    continue
                elif updated is None and create_if_update_missing:
                    resolved_to_create = True
                else:
                    results.append(
                        {
                            **row_base,
                            "status": "failed",
                            "person_id": None,
                            "error_code": "UPDATE_FAILED",
                            "message": "به‌روزرسانی شخص ناموفق بود",
                        }
                    )
                    continue

        # --- مسیر ایجاد ---
        if resolved_to_create:
            if not can_add:
                results.append(
                    {
                        **row_base,
                        "status": "failed",
                        "person_id": None,
                        "error_code": "FORBIDDEN",
                        "message": "مجوز ایجاد اشخاص (people.add) وجود ندارد",
                    }
                )
                continue

            try:
                p_create = PersonCreateRequest.model_validate(payload)
            except ValidationError as ve:
                results.append(
                    {
                        **row_base,
                        "status": "failed",
                        "person_id": None,
                        "error_code": "VALIDATION_ERROR",
                        "message": str(ve),
                    }
                )
                continue

            try:
                cr = create_person(db, business_id, p_create, defer_cache_invalidation=True)
                pdata = cr.get("data") or {}
                nid = pdata.get("id")
                any_success = True
                results.append(
                    {
                        **row_base,
                        "status": "created",
                        "person_id": int(nid)
                        if nid is not None
                        else None,
                    }
                )
            except ApiError as ae:
                de = api_error_detail(ae)
                results.append(
                    {
                        **row_base,
                        "status": "failed",
                        "person_id": None,
                        "error_code": de["code"],
                        "message": de["message"],
                    }
                )

    if any_success:
        invalidate_persons_cache(business_id, fiscal_year_id=None)

    summary = {
        "total": len(items),
        "created": sum(1 for r in results if r.get("status") == "created"),
        "updated": sum(1 for r in results if r.get("status") == "updated"),
        "failed": sum(1 for r in results if r.get("status") == "failed"),
        "skipped": sum(1 for r in results if r.get("status") == "skipped"),
    }

    return {"results": results, "summary": summary}
