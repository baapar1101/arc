"""گزینه‌های پایدار ویژگی select با dual-write روی JSON موجود."""

from __future__ import annotations

import re
import unicodedata
from typing import Any, Iterable, List, Optional, Sequence

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.product_attribute import ProductAttribute
from adapters.db.models.product_attribute_option import ProductAttributeOption
from adapters.db.models.product_variant import ProductVariantValue
from app.core.responses import ApiError

_WS_RE = re.compile(r"\s+")


def normalize_option_label(label: str | None) -> str:
    s = unicodedata.normalize("NFC", str(label or ""))
    s = s.replace("ي", "ی").replace("ك", "ک").replace("ى", "ی")
    s = _WS_RE.sub(" ", s).strip()
    return s


def labels_from_options_json(raw: Any) -> List[str]:
    if not raw:
        return []
    if isinstance(raw, dict) and isinstance(raw.get("items"), list):
        return [str(x) for x in raw["items"] if str(x).strip()]
    if isinstance(raw, list):
        return [str(x) for x in raw if str(x).strip()]
    return []


def _used_option_ids(db: Session, attribute_id: int) -> set[int]:
    rows = (
        db.query(ProductVariantValue.option_id)
        .filter(ProductVariantValue.attribute_id == int(attribute_id))
        .all()
    )
    return {int(r[0]) for r in rows if r[0] is not None}


def _next_option_code(existing_codes: set[str], label: str, index: int) -> str:
    base = re.sub(r"[^0-9A-Za-z\u0600-\u06FF]+", "-", normalize_option_label(label)).strip("-")
    if not base:
        base = f"opt-{index + 1}"
    code = base[:64]
    n = 2
    while code.lower() in {c.lower() for c in existing_codes}:
        suffix = f"-{n}"
        code = (base[: max(1, 64 - len(suffix))] + suffix)
        n += 1
    return code


def sync_select_options(
    db: Session,
    attribute: ProductAttribute,
    labels: Sequence[str],
) -> List[ProductAttributeOption]:
    """همگام‌سازی جدول گزینه با لیست عنوان‌های JSON. ادغام مبهم انجام نمی‌شود."""
    if (attribute.data_type or "text") != "select":
        return []

    seen_norm: dict[str, str] = {}
    ordered: List[str] = []
    for raw in labels:
        label = str(raw).strip()
        if not label:
            continue
        norm = normalize_option_label(label)
        if not norm:
            continue
        if norm in seen_norm and seen_norm[norm] != label:
            raise ApiError(
                "OPTION_LABEL_CONFLICT",
                "دو گزینه پس از نرمال‌سازی یکسان شدند و ادغام خودکار انجام نمی‌شود",
                http_status=409,
                details={"label_a": seen_norm[norm], "label_b": label},
            )
        if norm not in seen_norm:
            seen_norm[norm] = label
            ordered.append(label)

    existing = (
        db.query(ProductAttributeOption)
        .filter(
            ProductAttributeOption.business_id == int(attribute.business_id),
            ProductAttributeOption.attribute_id == int(attribute.id),
        )
        .all()
    )
    by_norm = {row.normalized_label: row for row in existing}
    used_ids = _used_option_ids(db, int(attribute.id))
    existing_codes = {row.code for row in existing if row.code}

    kept_ids: set[int] = set()
    result: List[ProductAttributeOption] = []
    for idx, label in enumerate(ordered):
        norm = normalize_option_label(label)
        row = by_norm.get(norm)
        if row is None:
            code = _next_option_code(existing_codes, label, idx)
            existing_codes.add(code)
            row = ProductAttributeOption(
                business_id=int(attribute.business_id),
                attribute_id=int(attribute.id),
                code=code,
                label=label,
                normalized_label=norm,
                sort_order=idx,
                is_active=True,
            )
            db.add(row)
            db.flush()
            by_norm[norm] = row
        else:
            row.label = label
            row.sort_order = idx
            row.is_active = True
        kept_ids.add(int(row.id))
        result.append(row)

    for row in existing:
        if int(row.id) in kept_ids:
            continue
        if int(row.id) in used_ids:
            row.is_active = False
        else:
            db.delete(row)
    db.flush()
    return result


def list_option_items(db: Session, attribute_id: int, business_id: int) -> List[dict[str, Any]]:
    rows = (
        db.query(ProductAttributeOption)
        .filter(
            ProductAttributeOption.business_id == int(business_id),
            ProductAttributeOption.attribute_id == int(attribute_id),
        )
        .order_by(ProductAttributeOption.sort_order.asc(), ProductAttributeOption.id.asc())
        .all()
    )
    return [
        {
            "id": int(row.id),
            "attribute_id": int(row.attribute_id),
            "code": row.code,
            "label": row.label,
            "normalized_label": row.normalized_label,
            "sort_order": int(row.sort_order or 0),
            "is_active": bool(row.is_active),
        }
        for row in rows
    ]


def get_option(
    db: Session,
    *,
    business_id: int,
    attribute_id: int,
    option_id: int,
) -> Optional[ProductAttributeOption]:
    return (
        db.query(ProductAttributeOption)
        .filter(
            and_(
                ProductAttributeOption.id == int(option_id),
                ProductAttributeOption.business_id == int(business_id),
                ProductAttributeOption.attribute_id == int(attribute_id),
            )
        )
        .first()
    )


def ensure_options_for_attribute(db: Session, attribute: ProductAttribute) -> List[ProductAttributeOption]:
    labels = labels_from_options_json(getattr(attribute, "options", None))
    if not labels:
        return []
    existing = (
        db.query(ProductAttributeOption.id)
        .filter(ProductAttributeOption.attribute_id == int(attribute.id))
        .first()
    )
    if existing:
        return (
            db.query(ProductAttributeOption)
            .filter(ProductAttributeOption.attribute_id == int(attribute.id))
            .order_by(ProductAttributeOption.sort_order.asc())
            .all()
        )
    return sync_select_options(db, attribute, labels)


def option_ids_from_iterable(rows: Iterable[ProductAttributeOption]) -> List[int]:
    return [int(r.id) for r in rows]
