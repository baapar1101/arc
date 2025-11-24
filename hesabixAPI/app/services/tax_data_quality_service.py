from __future__ import annotations

from typing import Dict, Any, List
from dataclasses import dataclass

from sqlalchemy.orm import Session
from sqlalchemy import func, or_

from adapters.db.models.product import Product
from adapters.db.models.person import Person


@dataclass
class TaxDataQualityReport:
    business_id: int
    product_missing_tax_code: int
    product_missing_tax_unit: int
    product_samples: List[Dict[str, Any]]
    person_missing_national_id: int
    person_missing_economic_id: int
    person_samples: List[Dict[str, Any]]


def get_tax_data_quality(db: Session, business_id: int) -> TaxDataQualityReport:
    product_base = db.query(Product).filter(Product.business_id == int(business_id))

    missing_tax_code_filter = or_(
        Product.tax_code.is_(None),
        func.trim(Product.tax_code) == "",
    )
    missing_tax_unit_filter = Product.tax_unit_id.is_(None)

    product_missing_tax_code = (
        product_base.filter(missing_tax_code_filter).with_entities(func.count(Product.id)).scalar() or 0
    )
    product_missing_tax_unit = (
        product_base.filter(missing_tax_unit_filter).with_entities(func.count(Product.id)).scalar() or 0
    )

    product_samples_query = (
        product_base.filter(or_(missing_tax_code_filter, missing_tax_unit_filter))
        .with_entities(
            Product.id,
            Product.code,
            Product.name,
            Product.tax_code,
            Product.tax_unit_id,
        )
        .order_by(Product.id.desc())
        .limit(10)
    )
    product_samples = [
        {
            "id": row.id,
            "code": row.code,
            "name": row.name,
            "tax_code": row.tax_code,
            "tax_unit_id": row.tax_unit_id,
        }
        for row in product_samples_query
    ]

    person_base = db.query(Person).filter(Person.business_id == int(business_id))
    missing_national_id_filter = or_(
        Person.national_id.is_(None),
        func.trim(Person.national_id) == "",
    )
    missing_economic_id_filter = or_(
        Person.economic_id.is_(None),
        func.trim(Person.economic_id) == "",
    )

    person_missing_national_id = (
        person_base.filter(missing_national_id_filter).with_entities(func.count(Person.id)).scalar() or 0
    )
    person_missing_economic_id = (
        person_base.filter(missing_economic_id_filter).with_entities(func.count(Person.id)).scalar() or 0
    )

    person_samples_query = (
        person_base.filter(or_(missing_national_id_filter, missing_economic_id_filter))
        .with_entities(
            Person.id,
            Person.code,
            Person.alias_name,
            Person.person_types,
            Person.national_id,
            Person.economic_id,
        )
        .order_by(Person.id.desc())
        .limit(10)
    )
    person_samples = [
        {
            "id": row.id,
            "code": row.code,
            "name": row.alias_name,
            "person_types": row.person_types,
            "national_id": row.national_id,
            "economic_id": row.economic_id,
        }
        for row in person_samples_query
    ]

    return TaxDataQualityReport(
        business_id=int(business_id),
        product_missing_tax_code=int(product_missing_tax_code),
        product_missing_tax_unit=int(product_missing_tax_unit),
        product_samples=product_samples,
        person_missing_national_id=int(person_missing_national_id),
        person_missing_economic_id=int(person_missing_economic_id),
        person_samples=person_samples,
    )


def format_tax_data_quality(report: TaxDataQualityReport) -> Dict[str, Any]:
    return {
        "business_id": report.business_id,
        "products": {
            "missing_tax_code": report.product_missing_tax_code,
            "missing_tax_unit": report.product_missing_tax_unit,
            "samples": report.product_samples,
        },
        "persons": {
            "missing_national_id": report.person_missing_national_id,
            "missing_economic_id": report.person_missing_economic_id,
            "samples": report.person_samples,
        },
    }

