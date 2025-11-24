from __future__ import annotations

from typing import Dict, Any, List

from sqlalchemy.orm import Session

from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.invoice_item_line import InvoiceItemLine


def validate_document_for_tax(db: Session, document) -> Dict[str, Any]:
    """
    بررسی حداقل داده‌های لازم برای ارسال فاکتور به سامانه مودیان.
    خروجی:
    {
        "valid": bool,
        "issues": [
            {"code": "...", "message": "...", "meta": {...}}
        ]
    }
    """
    issues: List[Dict[str, Any]] = []
    extra = document.extra_info or {}

    # 1. بررسی اطلاعات شخص
    person_id = extra.get("person_id")
    person: Person | None = None
    if not person_id:
        issues.append(
            {
                "code": "PERSON_MISSING",
                "message": "برای فاکتورهای فروش/خرید، انتخاب طرف حساب الزامی است.",
            }
        )
    else:
        person = (
            db.query(Person)
            .filter(Person.id == int(person_id))
            .first()
        )
        if not person:
            issues.append(
                {
                    "code": "PERSON_NOT_FOUND",
                    "message": "طرف حساب انتخاب شده یافت نشد.",
                }
            )
        else:
            has_national = bool((person.national_id or "").strip())
            has_economic = bool((person.economic_id or "").strip())
            if not (has_national or has_economic):
                issues.append(
                    {
                        "code": "PERSON_TAX_ID_MISSING",
                        "message": "طرف حساب فاقد کد ملی یا شناسه اقتصادی است.",
                        "meta": {"person_id": person.id},
                    }
                )

    # 2. بررسی اقلام فاکتور
    item_lines: List[InvoiceItemLine] = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id == document.id)
        .all()
    )
    if not item_lines:
        issues.append(
            {
                "code": "LINES_MISSING",
                "message": "فاکتور فاقد ردیف کالا/خدمت است.",
            }
        )
    for line in item_lines:
        product = (
            db.query(Product)
            .filter(Product.id == line.product_id)
            .first()
        )
        if not product:
            issues.append(
                {
                    "code": "PRODUCT_NOT_FOUND",
                    "message": f"کالای ردیف {line.id} حذف شده است.",
                    "meta": {"line_id": line.id},
                }
            )
            continue
        if not (product.tax_code or "").strip():
            issues.append(
                {
                    "code": "PRODUCT_TAX_CODE_MISSING",
                    "message": f"کالای '{product.name}' فاقد کد مالیاتی است.",
                    "meta": {"product_id": product.id},
                }
            )
        if not product.tax_unit_id:
            issues.append(
                {
                    "code": "PRODUCT_TAX_UNIT_MISSING",
                    "message": f"کالای '{product.name}' فاقد واحد مالیاتی است.",
                    "meta": {"product_id": product.id},
                }
            )

    # 3. بررسی هزینه حمل
    shipping_cost = (extra or {}).get("shipping_cost", 0)
    try:
        shipping_cost_val = float(shipping_cost or 0)
    except Exception:
        shipping_cost_val = 0
    if shipping_cost_val and abs(shipping_cost_val) > 0.5:
        issues.append(
            {
                "code": "SHIPPING_COST_NOT_ALLOWED",
                "message": "در نسخه فعلی، هزینه حمل باید صفر باشد.",
            }
        )

    return {"valid": len(issues) == 0, "issues": issues}

