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

def seed_tax_types():
    """Seed standard tax types"""
    
    # Standard tax types from Iranian Tax Organization
    tax_types = [
        {
            "title": "ارزش افزوده گروه دارو",
            "code": "VAT_DRUG",
            "description": "مالیات ارزش افزوده برای گروه دارو و تجهیزات پزشکی"
        },
        {
            "title": "ارزش افزوده گروه دخانیات",
            "code": "VAT_TOBACCO",
            "description": "مالیات ارزش افزوده برای گروه دخانیات"
        },
        {
            "title": "ارزش افزوده گروه خودرو",
            "code": "VAT_AUTO",
            "description": "مالیات ارزش افزوده برای گروه خودرو و قطعات"
        },
        {
            "title": "ارزش افزوده گروه مواد غذایی",
            "code": "VAT_FOOD",
            "description": "مالیات ارزش افزوده برای گروه مواد غذایی"
        },
        {
            "title": "ارزش افزوده گروه پوشاک",
            "code": "VAT_CLOTHING",
            "description": "مالیات ارزش افزوده برای گروه پوشاک و منسوجات"
        },
        {
            "title": "ارزش افزوده گروه ساختمان",
            "code": "VAT_CONSTRUCTION",
            "description": "مالیات ارزش افزوده برای گروه ساختمان و مصالح"
        },
        {
            "title": "ارزش افزوده گروه خدمات",
            "code": "VAT_SERVICES",
            "description": "مالیات ارزش افزوده برای گروه خدمات"
        },
        {
            "title": "ارزش افزوده گروه کالاهای عمومی",
            "code": "VAT_GENERAL",
            "description": "مالیات ارزش افزوده برای کالاهای عمومی"
        },
        {
            "title": "مالیات بر درآمد",
            "code": "INCOME_TAX",
            "description": "مالیات بر درآمد کسب و کار"
        },
        {
            "title": "مالیات بر ارزش افزوده صفر",
            "code": "VAT_ZERO",
            "description": "کالاها و خدمات معاف از مالیات ارزش افزوده"
        }
    ]
    
    db = next(get_db())
    
    try:
        # Clear existing data
        db.query(TaxType).delete()
        db.commit()
        
        # Insert new data
        for tax_data in tax_types:
            tax_type = TaxType(**tax_data)
            db.add(tax_type)
        
        db.commit()
        print(f"✅ Successfully seeded {len(tax_types)} tax types")
        
        # Display seeded data
        print("\n📋 Seeded tax types:")
        for tax_type in db.query(TaxType).order_by(TaxType.title).all():
            print(f"  - {tax_type.title} ({tax_type.code})")
            
    except Exception as e:
        db.rollback()
        print(f"❌ Error seeding tax types: {e}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    seed_tax_types()
