"""پردازش تعداد اولیه و انبار در ایمپورت اکسل کالا — هم‌راستا با فرم افزودن/ویرایش."""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, List, Optional, Set, Tuple

from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.product import ProductOpeningBalanceInput
from adapters.db.models.product import Product
from adapters.db.models.warehouse import Warehouse
from app.core.responses import ApiError
from app.services.product_opening_balance_service import (
    get_product_opening_balance_eligibility,
    validate_product_opening_balance_allowed,
)

OPENING_BALANCE_QUANTITY_KEY = "opening_balance_quantity"
OPENING_BALANCE_COST_KEY = "opening_balance_cost_price"
WAREHOUSE_CODE_KEY = "warehouse_code"
WAREHOUSE_NAME_KEY = "warehouse_name"

OPENING_BALANCE_EXCEL_KEYS = frozenset({
    OPENING_BALANCE_QUANTITY_KEY,
    OPENING_BALANCE_COST_KEY,
})

WAREHOUSE_RESOLVE_EXCEL_KEYS = frozenset({
    "default_warehouse_id",
    WAREHOUSE_CODE_KEY,
    WAREHOUSE_NAME_KEY,
})

EXCEL_ONLY_POP_KEYS = frozenset({
    OPENING_BALANCE_QUANTITY_KEY,
    OPENING_BALANCE_COST_KEY,
    WAREHOUSE_CODE_KEY,
    WAREHOUSE_NAME_KEY,
})


def opening_balance_columns_mapped(mapped_keys: Set[str]) -> bool:
    return bool(OPENING_BALANCE_EXCEL_KEYS & mapped_keys)


def warehouse_columns_mapped(mapped_keys: Set[str]) -> bool:
    return bool(WAREHOUSE_RESOLVE_EXCEL_KEYS & mapped_keys)


def _blank(val: Any) -> bool:
    if val is None:
        return True
    if isinstance(val, str) and val.strip() == "":
        return True
    return False


def _qty_specified(item: Dict[str, Any]) -> bool:
    return OPENING_BALANCE_QUANTITY_KEY in item and not _blank(item.get(OPENING_BALANCE_QUANTITY_KEY))


def _cost_specified(item: Dict[str, Any]) -> bool:
    return OPENING_BALANCE_COST_KEY in item and not _blank(item.get(OPENING_BALANCE_COST_KEY))


class WarehouseImportIndex:
    def __init__(self, rows: List[Warehouse]) -> None:
        self._by_id: Dict[int, Warehouse] = {int(w.id): w for w in rows}
        self._by_code: Dict[str, Warehouse] = {}
        self._by_name: Dict[str, Warehouse] = {}
        for w in rows:
            code = (w.code or "").strip().lower()
            if code:
                self._by_code[code] = w
            name = (w.name or "").strip().lower()
            if name:
                self._by_name.setdefault(name, w)

    def resolve(
        self,
        *,
        warehouse_id: Any = None,
        warehouse_code: Any = None,
        warehouse_name: Any = None,
    ) -> Tuple[Optional[int], Optional[str], Dict[str, Any]]:
        preview: Dict[str, Any] = {}
        wid = warehouse_id
        if wid is not None and not isinstance(wid, int):
            try:
                wid = int(wid)
            except (TypeError, ValueError):
                return None, "شناسه انبار پیش‌فرض نامعتبر است", preview

        if wid is not None:
            if wid not in self._by_id:
                return None, f"انبار با شناسه {wid} یافت نشد", preview
            preview["default_warehouse_id"] = wid
            preview["by"] = "id"
            return wid, None, preview

        code = str(warehouse_code).strip() if warehouse_code is not None else ""
        if code:
            found = self._by_code.get(code.lower())
            if not found:
                return None, f"انبار با کد '{code}' یافت نشد", preview
            preview["default_warehouse_id"] = found.id
            preview["by"] = "code"
            return int(found.id), None, preview

        name = str(warehouse_name).strip() if warehouse_name is not None else ""
        if name:
            found = self._by_name.get(name.lower())
            if not found:
                return None, f"انبار با نام '{name}' یافت نشد", preview
            preview["default_warehouse_id"] = found.id
            preview["by"] = "name"
            return int(found.id), None, preview

        return None, None, preview

    def default_warehouse_id(self) -> Optional[int]:
        for w in self._by_id.values():
            if w.is_default:
                return int(w.id)
        if len(self._by_id) == 1:
            return int(next(iter(self._by_id)))
        return None


def resolve_import_default_warehouse(
    item: Dict[str, Any],
    mapped_keys: Set[str],
    warehouse_index: WarehouseImportIndex,
) -> Tuple[List[str], Dict[str, Any]]:
    """تعیین انبار پیش‌فرض کالا از ستون‌های اکسل."""
    errors: List[str] = []
    preview: Dict[str, Any] = {}
    if not warehouse_columns_mapped(mapped_keys):
        return errors, preview

    wid, err, info = warehouse_index.resolve(
        warehouse_id=item.get("default_warehouse_id"),
        warehouse_code=item.get(WAREHOUSE_CODE_KEY),
        warehouse_name=item.get(WAREHOUSE_NAME_KEY),
    )
    if err:
        errors.append(err)
        return errors, preview
    if wid is not None:
        item["default_warehouse_id"] = wid
        preview = info
    return errors, preview


def prepare_opening_balance_for_import_row(
    *,
    item: Dict[str, Any],
    mapped_keys: Set[str],
    business_id: int,
    db: Session,
    can_edit_opening_balance: bool,
    is_update: bool,
    existing_product: Optional[Product] = None,
    warehouse_index: WarehouseImportIndex,
) -> Tuple[Optional[ProductOpeningBalanceInput], List[str], List[str], Dict[str, Any]]:
    """
    ساخت opening_balance برای یک ردیف ایمپورت.

    برمی‌گرداند:
      - ProductOpeningBalanceInput در صورت ثبت/به‌روزرسانی/حذف
      - None اگر نباید opening_balance ارسال شود
    """
    errors: List[str] = []
    warnings: List[str] = []
    preview: Dict[str, Any] = {}

    if not opening_balance_columns_mapped(mapped_keys):
        return None, errors, warnings, preview

    item_type = str(item.get("item_type") or "کالا").strip()
    track_inventory = bool(item.get("track_inventory"))

    qty_raw = item.get(OPENING_BALANCE_QUANTITY_KEY)
    cost_raw = item.get(OPENING_BALANCE_COST_KEY)
    qty_specified = _qty_specified(item)
    cost_specified = _cost_specified(item)

    if not qty_specified and not cost_specified:
        if is_update and existing_product is not None:
            eligibility = get_product_opening_balance_eligibility(
                db,
                business_id,
                None,
                can_edit_opening_balance=can_edit_opening_balance,
                product_id=int(existing_product.id),
                warehouse_id=item.get("default_warehouse_id") or existing_product.default_warehouse_id,
            )
            if eligibility.get("has_opening_balance_line"):
                if not can_edit_opening_balance:
                    errors.append(
                        eligibility.get("message")
                        or "برای حذف تعداد اولیه به دسترسی ویرایش تراز افتتاحیه نیاز است"
                    )
                    return None, errors, warnings, preview
                if not eligibility.get("editable"):
                    errors.append(
                        eligibility.get("message")
                        or "تعداد اولیه در این شرایط قابل تغییر نیست"
                    )
                    return None, errors, warnings, preview
                preview["action"] = "clear"
                return (
                    ProductOpeningBalanceInput(clear=True),
                    errors,
                    warnings,
                    preview,
                )
        return None, errors, warnings, preview

    if cost_specified and not qty_specified:
        errors.append("برای ثبت بهای تمام‌شده، تعداد اولیه الزامی است")
        return None, errors, warnings, preview

    if item_type != "کالا":
        errors.append("ثبت تعداد اولیه فقط برای کالا مجاز است")
        return None, errors, warnings, preview

    if not track_inventory:
        errors.append("برای ثبت تعداد اولیه باید کنترل موجودی فعال باشد")
        return None, errors, warnings, preview

    if not can_edit_opening_balance:
        errors.append("برای ثبت تعداد اولیه به دسترسی ویرایش تراز افتتاحیه نیاز است")
        return None, errors, warnings, preview

    qty_dec = qty_raw if isinstance(qty_raw, Decimal) else Decimal(str(qty_raw or 0))
    if qty_dec <= 0:
        errors.append("تعداد اولیه باید بزرگتر از صفر باشد")
        return None, errors, warnings, preview

    cost_dec = Decimal(0)
    if cost_specified:
        cost_dec = cost_raw if isinstance(cost_raw, Decimal) else Decimal(str(cost_raw or 0))
        if cost_dec < 0:
            errors.append("بهای تمام‌شده نمی‌تواند منفی باشد")
            return None, errors, warnings, preview
    else:
        purchase = item.get("base_purchase_price")
        if purchase is not None:
            cost_dec = purchase if isinstance(purchase, Decimal) else Decimal(str(purchase))
        if cost_dec < 0:
            cost_dec = Decimal(0)

    warehouse_id = item.get("default_warehouse_id")
    if existing_product is not None and warehouse_id is None:
        warehouse_id = existing_product.default_warehouse_id
    if warehouse_id is None:
        warehouse_id = warehouse_index.default_warehouse_id()
    if warehouse_id is None:
        errors.append("برای ثبت تعداد اولیه، انتخاب انبار الزامی است")
        return None, errors, warnings, preview

    item["default_warehouse_id"] = int(warehouse_id)

    product_id = int(existing_product.id) if existing_product is not None else None
    try:
        if is_update and product_id is not None:
            validate_product_opening_balance_allowed(
                db,
                business_id,
                None,
                product_id=product_id,
                warehouse_id=int(warehouse_id),
                for_update=True,
            )
        else:
            validate_product_opening_balance_allowed(
                db,
                business_id,
                None,
                product_id=None,
                warehouse_id=int(warehouse_id),
                for_update=False,
            )
    except ApiError as exc:
        err = exc.detail.get("error") if isinstance(exc.detail, dict) else {}
        errors.append(str((err or {}).get("message") or exc))
        return None, errors, warnings, preview

    eligibility = get_product_opening_balance_eligibility(
        db,
        business_id,
        None,
        can_edit_opening_balance=can_edit_opening_balance,
        product_id=product_id,
        warehouse_id=int(warehouse_id),
    )
    if not eligibility.get("editable"):
        errors.append(
            eligibility.get("message") or "تعداد اولیه در این شرایط قابل ثبت نیست"
        )
        return None, errors, warnings, preview

    fiscal_year_id = eligibility.get("fiscal_year_id")
    preview.update({
        "action": "upsert",
        "quantity": float(qty_dec),
        "cost_price": float(cost_dec),
        "warehouse_id": int(warehouse_id),
        "fiscal_year_id": fiscal_year_id,
        "fiscal_year_title": eligibility.get("fiscal_year_title"),
    })
    if cost_dec <= 0 and not cost_specified:
        warnings.append(
            "بهای تمام‌شده خالی است؛ مانند فرم کالا از قیمت خرید (یا صفر) استفاده می‌شود"
        )

    return (
        ProductOpeningBalanceInput(
            quantity=float(qty_dec),
            cost_price=float(cost_dec),
            warehouse_id=int(warehouse_id),
            fiscal_year_id=int(fiscal_year_id) if fiscal_year_id is not None else None,
        ),
        errors,
        warnings,
        preview,
    )


def pop_excel_only_keys(item: Dict[str, Any]) -> None:
    for key in EXCEL_ONLY_POP_KEYS:
        item.pop(key, None)
