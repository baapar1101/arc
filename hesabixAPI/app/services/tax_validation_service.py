from __future__ import annotations

import re
from typing import Dict, Any, List

from sqlalchemy.orm import Session

from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.invoice_item_line import InvoiceItemLine
from app.integrations.moadian.utils import (
    validate_tax_code,
    validate_national_id,
    validate_economic_code,
)


def validate_document_for_tax(db: Session, document) -> Dict[str, Any]:
    """
    بررسی کامل داده‌های لازم برای ارسال فاکتور به سامانه مودیان.
    
    بررسی‌ها:
    - اطلاعات طرف حساب (کد ملی، کد اقتصادی)
    - کد مالیاتی کالاها (13 رقم)
    - واحد مالیاتی کالاها
    - صحیح بودن مبالغ مالیات (بدون اعشار)
    - محدودیت‌های دیگر
    
    Returns:
        {
            "valid": bool,
            "issues": [{"code": str, "message": str, "meta": dict}]
        }
    """
    issues: List[Dict[str, Any]] = []
    extra = document.extra_info or {}

    # 1. بررسی اطلاعات شخص
    person_id = extra.get("person_id")
    person: Person | None = None
    
    if not person_id:
        issues.append({
            "code": "PERSON_MISSING",
            "message": "برای فاکتورهای فروش/خرید، انتخاب طرف حساب الزامی است.",
        })
    else:
        person = db.query(Person).filter(Person.id == int(person_id)).first()
        
        if not person:
            issues.append({
                "code": "PERSON_NOT_FOUND",
                "message": "طرف حساب انتخاب شده یافت نشد.",
            })
        else:
            # بررسی کد ملی
            national_id = (person.national_id or "").strip()
            economic_code = (person.economic_id or "").strip()
            
            if not national_id and not economic_code:
                issues.append({
                    "code": "PERSON_TAX_ID_MISSING",
                    "message": "طرف حساب فاقد کد ملی و شناسه اقتصادی است.",
                    "meta": {"person_id": person.id, "person_name": person.name},
                })
            else:
                # اعتبارسنجی کد ملی
                if national_id:
                    is_valid, person_type = validate_national_id(national_id)
                    if not is_valid:
                        issues.append({
                            "code": "PERSON_NATIONAL_ID_INVALID",
                            "message": f"کد ملی طرف حساب '{person.name}' نامعتبر است (باید 10 یا 11 رقم باشد).",
                            "meta": {"person_id": person.id, "national_id": national_id},
                        })
                
                # اعتبارسنجی کد اقتصادی
                if economic_code and not validate_economic_code(economic_code):
                    issues.append({
                        "code": "PERSON_ECONOMIC_CODE_INVALID",
                        "message": f"کد اقتصادی طرف حساب '{person.name}' نامعتبر است (باید 11 یا 14 رقم باشد).",
                        "meta": {"person_id": person.id, "economic_code": economic_code},
                    })

    # 2. بررسی اقلام فاکتور
    item_lines: List[InvoiceItemLine] = (
        db.query(InvoiceItemLine)
        .filter(InvoiceItemLine.document_id == document.id)
        .all()
    )
    
    if not item_lines:
        issues.append({
            "code": "LINES_MISSING",
            "message": "فاکتور فاقد ردیف کالا/خدمت است.",
        })
    
    for idx, line in enumerate(item_lines, 1):
        product = db.query(Product).filter(Product.id == line.product_id).first()
        
        if not product:
            issues.append({
                "code": "PRODUCT_NOT_FOUND",
                "message": f"کالای ردیف {idx} حذف شده است.",
                "meta": {"line_id": line.id, "line_number": idx},
            })
            continue
        
        # بررسی کد مالیاتی
        tax_code = (product.tax_code or "").strip()
        if not tax_code:
            issues.append({
                "code": "PRODUCT_TAX_CODE_MISSING",
                "message": f"کالای '{product.name}' (ردیف {idx}) فاقد کد مالیاتی است.",
                "meta": {"product_id": product.id, "product_name": product.name, "line_number": idx},
            })
        elif not validate_tax_code(tax_code):
            issues.append({
                "code": "PRODUCT_TAX_CODE_INVALID",
                "message": f"کد مالیاتی کالای '{product.name}' (ردیف {idx}) نامعتبر است (باید دقیقا 13 رقم باشد).",
                "meta": {"product_id": product.id, "tax_code": tax_code, "line_number": idx},
            })
        
        # بررسی واحد مالیاتی
        if not product.tax_unit_id:
            issues.append({
                "code": "PRODUCT_TAX_UNIT_MISSING",
                "message": f"کالای '{product.name}' (ردیف {idx}) فاقد واحد مالیاتی است.",
                "meta": {"product_id": product.id, "product_name": product.name, "line_number": idx},
            })
        
        # بررسی مالیات (نباید اعشار داشته باشد)
        line_extra = line.extra_info or {}
        tax_amount = line_extra.get("tax_amount", 0)
        
        try:
            tax_float = float(tax_amount)
            # بررسی اعشار
            if tax_float != int(tax_float):
                issues.append({
                    "code": "TAX_AMOUNT_HAS_DECIMAL",
                    "message": f"مبلغ مالیات ردیف {idx} (کالای '{product.name}') نباید اعشار داشته باشد.",
                    "meta": {"line_id": line.id, "tax_amount": tax_amount, "line_number": idx},
                })
            
            # بررسی منفی نبودن
            if tax_float < 0:
                issues.append({
                    "code": "TAX_AMOUNT_NEGATIVE",
                    "message": f"مبلغ مالیات ردیف {idx} (کالای '{product.name}') نمی‌تواند منفی باشد.",
                    "meta": {"line_id": line.id, "tax_amount": tax_amount, "line_number": idx},
                })
        except (ValueError, TypeError):
            issues.append({
                "code": "TAX_AMOUNT_INVALID",
                "message": f"مبلغ مالیات ردیف {idx} نامعتبر است.",
                "meta": {"line_id": line.id, "line_number": idx},
            })

    # 3. بررسی هزینه حمل
    shipping_cost = (extra or {}).get("shipping_cost", 0)
    try:
        shipping_cost_val = float(shipping_cost or 0)
    except Exception:
        shipping_cost_val = 0
    
    if shipping_cost_val and abs(shipping_cost_val) > 0.5:
        issues.append({
            "code": "SHIPPING_COST_NOT_ALLOWED",
            "message": "در نسخه فعلی، هزینه حمل باید صفر باشد.",
            "meta": {"shipping_cost": shipping_cost},
        })

    # 4. بررسی مبلغ کل فاکتور
    totals = extra.get("totals") or {}
    total_amount = totals.get("net", 0)
    
    try:
        total_float = float(total_amount)
        if total_float <= 0:
            issues.append({
                "code": "TOTAL_AMOUNT_INVALID",
                "message": "مبلغ کل فاکتور باید بیشتر از صفر باشد.",
                "meta": {"total_amount": total_amount},
            })
    except (ValueError, TypeError):
        issues.append({
            "code": "TOTAL_AMOUNT_INVALID",
            "message": "مبلغ کل فاکتور نامعتبر است.",
        })

    return {
        "valid": len(issues) == 0,
        "issues": issues,
        "total_issues": len(issues),
    }

