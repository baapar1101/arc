from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session, selectinload

from adapters.api.v1.schema_models.product import ProductSupplierInput
from adapters.db.models.person import Person
from adapters.db.models.product_supplier import ProductSupplier, ProductSupplierSocialContact
from app.core.responses import ApiError


def _empty_to_none(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    t = str(value).strip()
    return t if t else None


def _validate_supplier_input(item: ProductSupplierInput, index: int) -> ProductSupplierInput:
    person_id = item.person_id
    name = _empty_to_none(item.name)
    if person_id is None and not name:
        raise ApiError(
            "INVALID_PRODUCT_SUPPLIER",
            f"تأمین‌کنندهٔ ردیف {index + 1}: نام یا انتخاب شخص الزامی است",
            http_status=400,
        )
    return item


def _resolve_supplier_name(db: Session, business_id: int, item: ProductSupplierInput) -> str:
    name = _empty_to_none(item.name)
    if name:
        return name
    if item.person_id is not None:
        person = (
            db.query(Person)
            .filter(Person.id == item.person_id, Person.business_id == business_id)
            .first()
        )
        if person is None:
            raise ApiError(
                "INVALID_PRODUCT_SUPPLIER_PERSON",
                "شخص تأمین‌کننده یافت نشد یا متعلق به این کسب‌وکار نیست",
                http_status=400,
            )
        return (person.alias_name or "").strip() or f"شخص #{person.id}"
    raise ApiError(
        "INVALID_PRODUCT_SUPPLIER",
        "نام تأمین‌کننده الزامی است",
        http_status=400,
    )


def _validate_person_id(db: Session, business_id: int, person_id: Optional[int]) -> None:
    if person_id is None:
        return
    person = (
        db.query(Person.id)
        .filter(Person.id == person_id, Person.business_id == business_id)
        .first()
    )
    if person is None:
        raise ApiError(
            "INVALID_PRODUCT_SUPPLIER_PERSON",
            "شخص تأمین‌کننده یافت نشد یا متعلق به این کسب‌وکار نیست",
            http_status=400,
        )


def upsert_product_suppliers(
    db: Session,
    product_id: int,
    business_id: int,
    suppliers: Optional[List[ProductSupplierInput]],
    *,
    auto_commit: bool = True,
) -> None:
    if suppliers is None:
        return

    validated = [_validate_supplier_input(s, i) for i, s in enumerate(suppliers)]

    db.query(ProductSupplier).filter(ProductSupplier.product_id == product_id).delete(
        synchronize_session=False
    )

    preferred_count = sum(1 for s in validated if s.is_preferred)
    if preferred_count > 1:
        raise ApiError(
            "INVALID_PRODUCT_SUPPLIER",
            "فقط یک تأمین‌کننده می‌تواند به‌عنوان ترجیحی علامت بخورد",
            http_status=400,
        )

    for sort_idx, item in enumerate(validated):
        _validate_person_id(db, business_id, item.person_id)
        resolved_name = _resolve_supplier_name(db, business_id, item)
        row = ProductSupplier(
            business_id=business_id,
            product_id=product_id,
            person_id=item.person_id,
            name=resolved_name,
            website=_empty_to_none(item.website),
            phone=_empty_to_none(item.phone),
            email=_empty_to_none(item.email),
            notes=_empty_to_none(item.notes),
            is_preferred=bool(item.is_preferred),
            sort_order=item.sort_order if item.sort_order is not None else sort_idx,
        )
        db.add(row)
        db.flush()

        for sc_idx, sc in enumerate(item.social_contacts or []):
            value = (sc.value or "").strip()
            if not value:
                continue
            platform_key = (sc.platform_key or "").strip().lower()
            if not platform_key:
                continue
            if platform_key == "other" and not _empty_to_none(sc.custom_label):
                raise ApiError(
                    "INVALID_PRODUCT_SUPPLIER_SOCIAL",
                    "برای پلتفرم «سایر» باید برچسب وارد شود",
                    http_status=400,
                )
            db.add(
                ProductSupplierSocialContact(
                    supplier_id=row.id,
                    platform_key=platform_key,
                    custom_label=_empty_to_none(sc.custom_label),
                    value=value,
                    sort_order=sc_idx,
                )
            )

    if auto_commit:
        db.commit()


def load_product_suppliers(db: Session, product_id: int) -> List[Dict[str, Any]]:
    rows = (
        db.query(ProductSupplier)
        .options(
            selectinload(ProductSupplier.social_contacts),
            selectinload(ProductSupplier.person),
        )
        .filter(ProductSupplier.product_id == product_id)
        .order_by(ProductSupplier.sort_order.asc(), ProductSupplier.id.asc())
        .all()
    )
    out: List[Dict[str, Any]] = []
    for row in rows:
        person = row.person
        out.append(
            {
                "id": row.id,
                "person_id": row.person_id,
                "person_name": person.alias_name if person else None,
                "name": row.name,
                "website": row.website,
                "phone": row.phone,
                "email": row.email,
                "notes": row.notes,
                "is_preferred": bool(row.is_preferred),
                "sort_order": row.sort_order,
                "social_contacts": [
                    {
                        "id": sc.id,
                        "platform_key": sc.platform_key,
                        "custom_label": sc.custom_label,
                        "value": sc.value,
                        "sort_order": sc.sort_order,
                    }
                    for sc in sorted(row.social_contacts or [], key=lambda x: (x.sort_order, x.id))
                ],
            }
        )
    return out
