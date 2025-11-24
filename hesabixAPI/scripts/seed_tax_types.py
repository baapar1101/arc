#!/usr/bin/env python3
"""
Script to seed standard tax types from Iranian Tax Organization
"""

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from adapters.db.session import get_db
from adapters.db.models.tax_type import TaxType

LEGACY_TAX_TYPES = [
    {"title": "۱- دارو", "code": "1"},
    {"title": "۲- دخانیات", "code": "2"},
    {"title": "۳- موبایل", "code": "3"},
    {"title": "۴- لوازم خانگی برقی", "code": "4"},
    {"title": "۵- قطعات مصرفی و یدکی وسایل نقلیه", "code": "5"},
    {"title": "۶- فراورده ها و مشتقات نفتی و گازی و پتروشیمیایی", "code": "6"},
    {"title": "۷- طلا اعم از شمش ،مسکوکات و مصنوعات زینتی", "code": "7"},
    {"title": "۸- منسوجات و پوشاک", "code": "8"},
    {"title": "۹- اسباب بازی", "code": "9"},
    {"title": "۱۰- دام زنده، گوشت سفید و قرمز", "code": "10"},
    {"title": "۱۱- محصولات اساسی کشاورزی", "code": "11"},
    {"title": "۱۲- سایر کالا ها", "code": "12"},
]


def seed_tax_types():
    """Seed standard tax types"""
    
    db = next(get_db())
    
    try:
        # Clear existing data
        db.query(TaxType).delete()
        db.commit()
        
        # Insert new data
        for data in LEGACY_TAX_TYPES:
            tax_type = TaxType(
                title=data["title"],
                code=data["code"],
                description=data.get("description"),
            )
            db.add(tax_type)
        
        db.commit()
        print(f"✅ Successfully seeded {len(LEGACY_TAX_TYPES)} tax types")
        
        # Display seeded data
        print("\n📋 Seeded tax types:")
        for tax_type in db.query(TaxType).order_by(TaxType.id).all():
            print(f"  - {tax_type.title} ({tax_type.code})")
            
    except Exception as e:
        db.rollback()
        print(f"❌ Error seeding tax types: {e}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    seed_tax_types()
