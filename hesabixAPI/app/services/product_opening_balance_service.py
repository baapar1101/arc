from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional, Set

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.product import Product
from app.core.responses import ApiError
from app.services.invoice_service import _get_fixed_account_by_code
from app.services.opening_balance_service import (
    _ensure_fiscal_year,
    _find_existing_ob_document,
    get_opening_balance,
    upsert_opening_balance,
)
from app.services.person_opening_balance_service import (
    _count_other_fiscal_year_documents,
    _document_lines_to_upsert_inputs,
    _resolve_default_equity_account_id,
    _validate_ob_editable,
)

_DEFAULT_INVENTORY_ACCOUNT_CODES = ("10102", "12101")


def _resolve_default_inventory_account_id(db: Session) -> int:
    for code in _DEFAULT_INVENTORY_ACCOUNT_CODES:
        try:
            return int(_get_fixed_account_by_code(db, code).id)
        except ApiError:
            continue
    raise ApiError(
        "INVENTORY_ACCOUNT_NOT_FOUND",
        "حساب موجودی کالا برای ثبت تراز افتتاحیه یافت نشد",
        http_status=400,
    )


def _warehouse_id_from_line(line: Dict[str, Any]) -> Optional[int]:
    info = dict(line.get("extra_info") or {})
    wid = info.get("warehouse_id")
    if wid is None:
        return None
    try:
        return int(wid)
    except (TypeError, ValueError):
        return None


def _extract_product_ob_line(
    doc: Optional[Dict[str, Any]],
    product_id: int,
    warehouse_id: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    if not doc:
        return None
    pid = int(product_id)
    for line in doc.get("lines") or []:
        if line.get("product_id") is None:
            continue
        if int(line.get("product_id")) != pid:
            continue
        line_wh = _warehouse_id_from_line(line)
        if warehouse_id is not None and line_wh != int(warehouse_id):
            continue
        qty = float(line.get("quantity") or 0)
        if qty <= 0:
            continue
        info = dict(line.get("extra_info") or {})
        return {
            "quantity": qty,
            "cost_price": float(info.get("cost_price") or 0),
            "warehouse_id": line_wh,
        }
    return None


def _resolve_warehouse_id(
    ob: Any,
    *,
    default_warehouse_id: Optional[int],
) -> int:
    wh = getattr(ob, "warehouse_id", None)
    if wh is not None:
        return int(wh)
    if default_warehouse_id is not None:
        return int(default_warehouse_id)
    raise ApiError(
        "WAREHOUSE_REQUIRED",
        "برای ثبت تعداد اولیه، انتخاب انبار الزامی است",
        http_status=400,
    )


def _validate_product_ob_prerequisites(
    *,
    item_type: str,
    track_inventory: bool,
) -> None:
    if str(item_type or "").strip() != "کالا":
        raise ApiError(
            "OPENING_BALANCE_NOT_FOR_SERVICE",
            "ثبت تعداد اولیه فقط برای کالا مجاز است",
            http_status=400,
        )
    if not track_inventory:
        raise ApiError(
            "OPENING_BALANCE_REQUIRES_TRACK_INVENTORY",
            "برای ثبت تعداد اولیه باید کنترل موجودی فعال باشد",
            http_status=400,
        )


def validate_product_opening_balance_allowed(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int],
    *,
    product_id: Optional[int] = None,
    warehouse_id: Optional[int] = None,
    for_update: bool = False,
) -> Dict[str, Any]:
    """اعتبارسنجی امکان ثبت تعداد اولیه کالا؛ در صورت عدم مجاز بودن ApiError."""
    ctx = _validate_ob_editable(db, business_id, fiscal_year_id)

    if not for_update and product_id is not None and warehouse_id is not None:
        existing = _find_existing_ob_document(db, business_id, int(ctx["fiscal_year_id"]))
        if existing is not None:
            for line in existing.lines:
                if line.product_id is None:
                    continue
                if int(line.product_id) != int(product_id):
                    continue
                line_wh = _warehouse_id_from_line(
                    {"extra_info": dict(line.extra_info or {})}
                )
                if line_wh is not None and int(line_wh) == int(warehouse_id):
                    raise ApiError(
                        "DUPLICATE_OPENING_BALANCE_PRODUCT_WAREHOUSE",
                        "این کالا قبلاً برای این انبار در سند تراز افتتاحیه ثبت شده است",
                        http_status=400,
                    )

    return ctx


def get_product_opening_balance_eligibility(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int],
    *,
    can_edit_opening_balance: bool,
    product_id: Optional[int] = None,
    warehouse_id: Optional[int] = None,
) -> Dict[str, Any]:
    """وضعیت نمایش/ثبت تعداد اولیه در فرم افزودن یا ویرایش کالا."""
    try:
        fy_id, _, _ = _ensure_fiscal_year(db, business_id, fiscal_year_id)
    except ApiError as exc:
        err_code = ""
        if isinstance(exc.detail, dict):
            err_code = str((exc.detail.get("error") or {}).get("code") or "")
        if err_code == "NO_CURRENT_FISCAL_YEAR":
            return {
                "eligible": False,
                "editable": False,
                "show_section": False,
                "reason": "no_fiscal_year",
                "message": "سال مالی فعالی برای این کسب‌وکار یافت نشد",
                "can_edit_opening_balance": can_edit_opening_balance,
                "product_opening_balance": None,
                "has_opening_balance_line": False,
            }
        raise

    from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository

    fy_repo = FiscalYearRepository(db)
    fy = fy_repo.get_by_id(fy_id)
    existing = _find_existing_ob_document(db, business_id, fy_id)
    posted = bool(existing and (existing.extra_info or {}).get("posted"))
    other_docs = _count_other_fiscal_year_documents(db, business_id, fy_id) > 0

    ob_doc = get_opening_balance(db, business_id, fy_id)
    product_line = (
        _extract_product_ob_line(ob_doc, int(product_id), warehouse_id)
        if product_id is not None
        else None
    )
    has_line = product_line is not None

    base = {
        "fiscal_year_id": fy_id,
        "fiscal_year_title": fy.title if fy else None,
        "opening_balance_exists": existing is not None,
        "opening_balance_posted": posted,
        "has_other_documents": other_docs,
        "can_edit_opening_balance": can_edit_opening_balance,
        "product_opening_balance": product_line,
        "has_opening_balance_line": has_line,
    }

    editable = False
    reason: Optional[str] = None
    message = ""

    if not can_edit_opening_balance:
        reason = "no_permission"
        message = "برای تغییر تعداد اولیه به دسترسی ویرایش تراز افتتاحیه نیاز است"
    elif posted:
        reason = "posted"
        message = "سند تراز افتتاحیه نهایی شده و تعداد اولیه قابل تغییر نیست"
    elif other_docs:
        reason = "other_documents"
        message = (
            "به‌دلیل ثبت اسناد دیگر در این سال مالی، تعداد اولیه قابل تغییر نیست. "
            "از رسید انبار، فاکتور یا سند دستی استفاده کنید"
        )
    else:
        editable = True
        message = (
            "تعداد اولیه در سند تراز افتتاحیه سال مالی جاری ثبت می‌شود"
            if not has_line
            else "تعداد اولیه قابل ویرایش است"
        )

    if product_id is None:
        show_section = editable
    else:
        show_section = has_line or editable

    return {
        **base,
        "eligible": editable,
        "editable": editable,
        "show_section": show_section,
        "reason": reason,
        "message": message,
    }


def _build_ob_payload_with_product_line(
    db: Session,
    business_id: int,
    fy_id: int,
    product_id: int,
    warehouse_id: int,
    *,
    quantity: Optional[float],
    cost_price: Optional[float],
    product_name: str,
    remove_line: bool,
    remove_warehouse_ids: Optional[List[int]] = None,
) -> Dict[str, Any]:
    existing_doc = get_opening_balance(db, business_id, fy_id)
    _, fy_start, _ = _ensure_fiscal_year(db, business_id, fy_id)

    if existing_doc:
        account_lines, inventory_lines, settings = _document_lines_to_upsert_inputs(existing_doc)
        currency_id = existing_doc.get("currency_id")
        document_date = existing_doc.get("document_date")
    else:
        account_lines = []
        inventory_lines = []
        settings = {
            "auto_balance_to_equity": True,
            "equity_account_id": None,
            "inventory_account_id": None,
        }
        business = db.query(Business).filter(Business.id == int(business_id)).first()
        currency_id = getattr(business, "default_currency_id", None) if business else None
        if not currency_id:
            raise ApiError("CURRENCY_REQUIRED", "ارز پیش‌فرض کسب‌وکار تنظیم نشده است", http_status=400)
        document_date = fy_start

    warehouse_ids_to_remove: Set[int] = {int(warehouse_id)}
    if remove_warehouse_ids:
        warehouse_ids_to_remove.update(int(w) for w in remove_warehouse_ids)

    filtered_inventory: List[Dict[str, Any]] = []
    for ln in inventory_lines:
        if ln.get("product_id") is None:
            filtered_inventory.append(ln)
            continue
        if int(ln.get("product_id")) != int(product_id):
            filtered_inventory.append(ln)
            continue
        line_wh = _warehouse_id_from_line(ln)
        if line_wh is not None and line_wh in warehouse_ids_to_remove:
            continue
        filtered_inventory.append(ln)
    inventory_lines = filtered_inventory

    if not remove_line:
        qty_dec = Decimal(str(quantity or 0))
        if qty_dec <= 0:
            raise ApiError(
                "INVALID_OPENING_BALANCE_QUANTITY",
                "تعداد اولیه باید بزرگتر از صفر باشد",
                http_status=400,
            )
        cost_dec = Decimal(str(cost_price or 0))
        if cost_dec < 0:
            raise ApiError(
                "INVALID_OPENING_BALANCE_COST",
                "بهای تمام‌شده نمی‌تواند منفی باشد",
                http_status=400,
            )
        extra_info: Dict[str, Any] = {
            "movement": "in",
            "warehouse_id": int(warehouse_id),
        }
        if cost_dec > 0:
            extra_info["cost_price"] = float(cost_dec)
        inventory_lines.append(
            {
                "product_id": int(product_id),
                "quantity": float(qty_dec),
                "extra_info": extra_info,
                "description": f"موجودی اولیه - {product_name}",
            }
        )

    auto_balance = bool(settings.get("auto_balance_to_equity", True))
    equity_account_id = settings.get("equity_account_id")
    inventory_account_id = settings.get("inventory_account_id")

    if inventory_lines and not inventory_account_id:
        inventory_account_id = _resolve_default_inventory_account_id(db)

    if auto_balance and not equity_account_id and (account_lines or inventory_lines):
        equity_account_id = _resolve_default_equity_account_id(db)

    payload: Dict[str, Any] = {
        "fiscal_year_id": fy_id,
        "currency_id": int(currency_id),
        "document_date": document_date,
        "account_lines": account_lines,
        "inventory_lines": inventory_lines,
        "auto_balance_to_equity": auto_balance,
    }
    if inventory_account_id:
        payload["inventory_account_id"] = int(inventory_account_id)
    if equity_account_id:
        payload["equity_account_id"] = int(equity_account_id)
    return payload


def upsert_product_opening_balance_line(
    db: Session,
    business_id: int,
    user_id: int,
    product_id: int,
    *,
    quantity: Optional[float],
    cost_price: Optional[float],
    warehouse_id: int,
    fiscal_year_id: Optional[int],
    product_name: str,
    remove_line: bool = False,
    previous_warehouse_id: Optional[int] = None,
) -> Dict[str, Any]:
    """افزودن، به‌روزرسانی یا حذف خط موجودی اولیه کالا در سند تراز افتتاحیه."""
    ctx = validate_product_opening_balance_allowed(
        db,
        business_id,
        fiscal_year_id,
        product_id=product_id,
        warehouse_id=warehouse_id if not remove_line else None,
        for_update=True,
    )
    fy_id = int(ctx["fiscal_year_id"])

    if remove_line:
        existing_doc = get_opening_balance(db, business_id, fy_id)
        wh_ids = [warehouse_id]
        if previous_warehouse_id is not None and int(previous_warehouse_id) != int(warehouse_id):
            wh_ids.append(int(previous_warehouse_id))
        found = False
        for wh in wh_ids:
            if _extract_product_ob_line(existing_doc, product_id, wh) is not None:
                found = True
                break
        if not found:
            return existing_doc or {}

    remove_wh: List[int] = []
    if (
        previous_warehouse_id is not None
        and int(previous_warehouse_id) != int(warehouse_id)
        and not remove_line
    ):
        remove_wh.append(int(previous_warehouse_id))

    payload = _build_ob_payload_with_product_line(
        db,
        business_id,
        fy_id,
        product_id,
        warehouse_id,
        quantity=quantity,
        cost_price=cost_price,
        product_name=product_name,
        remove_line=remove_line,
        remove_warehouse_ids=remove_wh or None,
    )
    return upsert_opening_balance(db, business_id, int(user_id), payload)


def append_product_line_to_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    product_id: int,
    *,
    quantity: float,
    cost_price: float,
    warehouse_id: int,
    fiscal_year_id: Optional[int],
    product_name: str,
) -> Dict[str, Any]:
    """افزودن خط موجودی اولیه کالا به سند تراز افتتاحیه (ایجاد کالای جدید)."""
    validate_product_opening_balance_allowed(
        db,
        business_id,
        fiscal_year_id,
        product_id=product_id,
        warehouse_id=warehouse_id,
    )
    return upsert_product_opening_balance_line(
        db,
        business_id,
        user_id,
        product_id,
        quantity=quantity,
        cost_price=cost_price,
        warehouse_id=warehouse_id,
        fiscal_year_id=fiscal_year_id,
        product_name=product_name,
        remove_line=False,
    )


def _merged_track_inventory(payload: Any, existing: Optional[Product]) -> bool:
    if hasattr(payload, "track_inventory") and payload.track_inventory is not None:
        return bool(payload.track_inventory)
    if existing is not None:
        return bool(existing.track_inventory)
    return bool(getattr(payload, "track_inventory", False))


def _merged_item_type(payload: Any, existing: Optional[Product]) -> str:
    if getattr(payload, "item_type", None) is not None:
        return str(payload.item_type)
    if existing is not None:
        val = existing.item_type
        return val.value if hasattr(val, "value") else str(val)
    return str(getattr(payload, "item_type", "کالا"))


def _merged_default_warehouse_id(payload: Any, existing: Optional[Product]) -> Optional[int]:
    if getattr(payload, "default_warehouse_id", None) is not None:
        return int(payload.default_warehouse_id) if payload.default_warehouse_id else None
    if existing is not None and existing.default_warehouse_id is not None:
        return int(existing.default_warehouse_id)
    return None


def create_product_with_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    product_data: Any,
    *,
    create_product_fn: Any,
    delete_product_fn: Any,
) -> Dict[str, Any]:
    """ایجاد کالا و در صورت درخواست، ثبت تعداد اولیه در سند افتتاحیه (با بازگشت در صورت خطا)."""
    ob = getattr(product_data, "opening_balance", None)

    if ob is not None and not getattr(ob, "clear", False):
        _validate_product_ob_prerequisites(
            item_type=_merged_item_type(product_data, None),
            track_inventory=_merged_track_inventory(product_data, None),
        )
        wh_id = _resolve_warehouse_id(ob, default_warehouse_id=_merged_default_warehouse_id(product_data, None))
        validate_product_opening_balance_allowed(
            db, business_id, ob.fiscal_year_id, product_id=None, warehouse_id=wh_id
        )

    result = create_product_fn(db, business_id, product_data)
    product_id = int(result["data"]["id"])
    product_name = str(result["data"].get("name") or "")

    if ob is None:
        return result

    try:
        if getattr(ob, "clear", False):
            raise ApiError("INVALID_OPENING_BALANCE", "clear در ایجاد کالا مجاز نیست", http_status=400)
        wh_id = _resolve_warehouse_id(
            ob,
            default_warehouse_id=result["data"].get("default_warehouse_id")
            or _merged_default_warehouse_id(product_data, None),
        )
        ob_doc = append_product_line_to_opening_balance(
            db,
            business_id,
            user_id,
            product_id,
            quantity=float(ob.quantity),
            cost_price=float(ob.cost_price or 0),
            warehouse_id=wh_id,
            fiscal_year_id=ob.fiscal_year_id,
            product_name=product_name,
        )
    except Exception:
        success, _ = delete_product_fn(db, product_id, business_id)
        if not success:
            db.rollback()
        raise

    data = dict(result["data"])
    data["opening_balance_document_id"] = ob_doc.get("id")
    data["opening_balance_applied"] = True
    return {
        "message": "کالا ایجاد شد و تعداد اولیه در سند تراز افتتاحیه ثبت شد",
        "data": data,
    }


def update_product_with_opening_balance(
    db: Session,
    business_id: int,
    user_id: int,
    product_id: int,
    product_data: Any,
    *,
    update_product_fn: Any,
    previous_warehouse_id: Optional[int] = None,
) -> Dict[str, Any]:
    """ویرایش کالا و در صورت درخواست، به‌روزرسانی تعداد اولیه در سند افتتاحیه."""
    ob = getattr(product_data, "opening_balance", None)
    existing_product = db.get(Product, product_id)

    result = update_product_fn(db, product_id, business_id, product_data, user_id=user_id)
    if not result:
        return {}

    if ob is None:
        return result

    _validate_product_ob_prerequisites(
        item_type=_merged_item_type(product_data, existing_product),
        track_inventory=_merged_track_inventory(product_data, existing_product),
    )

    product_name = str((result.get("data") or {}).get("name") or "")
    default_wh = (result.get("data") or {}).get("default_warehouse_id")
    if default_wh is None and existing_product is not None:
        default_wh = existing_product.default_warehouse_id

    if getattr(ob, "clear", False):
        wh_for_remove = previous_warehouse_id or _resolve_warehouse_id(
            ob, default_warehouse_id=default_wh
        )
        upsert_product_opening_balance_line(
            db,
            business_id,
            user_id,
            product_id,
            quantity=None,
            cost_price=None,
            warehouse_id=wh_for_remove,
            fiscal_year_id=ob.fiscal_year_id,
            product_name=product_name,
            remove_line=True,
            previous_warehouse_id=previous_warehouse_id,
        )
        msg = "کالا ویرایش شد و تعداد اولیه از سند تراز افتتاحیه حذف شد"
    else:
        wh_id = _resolve_warehouse_id(ob, default_warehouse_id=default_wh)
        upsert_product_opening_balance_line(
            db,
            business_id,
            user_id,
            product_id,
            quantity=float(ob.quantity),
            cost_price=float(ob.cost_price or 0),
            warehouse_id=wh_id,
            fiscal_year_id=ob.fiscal_year_id,
            product_name=product_name,
            remove_line=False,
            previous_warehouse_id=previous_warehouse_id,
        )
        msg = "کالا ویرایش شد و تعداد اولیه در سند تراز افتتاحیه به‌روزرسانی شد"

    data = dict(result.get("data") or {})
    data["opening_balance_applied"] = True
    return {"message": msg, "data": data}
