"""افزودن اطلاعات پایه (Seed Data) به دیتابیس

این فایل شامل:
- دسته‌بندی‌ها، اولویت‌ها و وضعیت‌های پشتیبانی
- ارزهای مختلف
- چارت حساب‌های حسابداری
- انواع مالیات
- تنظیمات سیستم
"""
from __future__ import annotations

from datetime import datetime
from alembic import op
import sqlalchemy as sa


def upgrade():
    """افزودن اطلاعات پایه"""
    
    # ========== 1. داده‌های پشتیبانی ==========
    # دسته‌بندی‌های پشتیبانی
    categories_table = sa.table(
        'support_categories',
        sa.column('id', sa.Integer),
        sa.column('name', sa.String),
        sa.column('description', sa.Text),
        sa.column('is_active', sa.Boolean),
        sa.column('created_at', sa.DateTime),
        sa.column('updated_at', sa.DateTime)
    )
    
    categories_data = [
        {
            'name': 'مشکل فنی',
            'description': 'مشکلات فنی و باگ‌ها',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'درخواست ویژگی',
            'description': 'درخواست ویژگی‌های جدید',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'سوال',
            'description': 'سوالات عمومی',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'شکایت',
            'description': 'شکایات و انتقادات',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'سایر',
            'description': 'سایر موارد',
            'is_active': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
    ]
    
    op.bulk_insert(categories_table, categories_data)
    
    # اولویت‌های پشتیبانی
    priorities_table = sa.table(
        'support_priorities',
        sa.column('id', sa.Integer),
        sa.column('name', sa.String),
        sa.column('description', sa.Text),
        sa.column('color', sa.String),
        sa.column('order', sa.Integer),
        sa.column('created_at', sa.DateTime),
        sa.column('updated_at', sa.DateTime)
    )
    
    priorities_data = [
        {
            'name': 'کم',
            'description': 'اولویت کم',
            'color': '#28a745',
            'order': 1,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'متوسط',
            'description': 'اولویت متوسط',
            'color': '#ffc107',
            'order': 2,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'بالا',
            'description': 'اولویت بالا',
            'color': '#fd7e14',
            'order': 3,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'فوری',
            'description': 'اولویت فوری',
            'color': '#dc3545',
            'order': 4,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
    ]
    
    op.bulk_insert(priorities_table, priorities_data)
    
    # وضعیت‌های پشتیبانی
    statuses_table = sa.table(
        'support_statuses',
        sa.column('id', sa.Integer),
        sa.column('name', sa.String),
        sa.column('description', sa.Text),
        sa.column('color', sa.String),
        sa.column('is_final', sa.Boolean),
        sa.column('created_at', sa.DateTime),
        sa.column('updated_at', sa.DateTime)
    )
    
    statuses_data = [
        {
            'name': 'باز',
            'description': 'تیکت باز و در انتظار پاسخ',
            'color': '#007bff',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'در حال پیگیری',
            'description': 'تیکت در حال بررسی',
            'color': '#6f42c1',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'در انتظار کاربر',
            'description': 'در انتظار پاسخ کاربر',
            'color': '#17a2b8',
            'is_final': False,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'بسته',
            'description': 'تیکت بسته شده',
            'color': '#6c757d',
            'is_final': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        },
        {
            'name': 'حل شده',
            'description': 'مشکل حل شده',
            'color': '#28a745',
            'is_final': True,
            'created_at': datetime.utcnow(),
            'updated_at': datetime.utcnow()
        }
    ]
    
    op.bulk_insert(statuses_table, statuses_data)
    
    # ========== 2. ارزها ==========
    conn = op.get_bind()
    insert_sql = sa.text(
        """
        INSERT INTO currencies (name, title, symbol, code, created_at, updated_at)
        VALUES (:name, :title, :symbol, :code, NOW(), NOW())
        ON DUPLICATE KEY UPDATE
            title = VALUES(title),
            symbol = VALUES(symbol),
            updated_at = VALUES(updated_at)
        """
    )

    currencies = [
        {"name": "Iranian Rial", "title": "ریال ایران", "symbol": "﷼", "code": "IRR"},
        {"name": "United States Dollar", "title": "US Dollar", "symbol": "$", "code": "USD"},
        {"name": "Euro", "title": "Euro", "symbol": "€", "code": "EUR"},
        {"name": "British Pound", "title": "Pound Sterling", "symbol": "£", "code": "GBP"},
        {"name": "Japanese Yen", "title": "Yen", "symbol": "¥", "code": "JPY"},
        {"name": "Chinese Yuan", "title": "Yuan", "symbol": "¥", "code": "CNY"},
        {"name": "Swiss Franc", "title": "Swiss Franc", "symbol": "CHF", "code": "CHF"},
        {"name": "Canadian Dollar", "title": "Canadian Dollar", "symbol": "$", "code": "CAD"},
        {"name": "Australian Dollar", "title": "Australian Dollar", "symbol": "$", "code": "AUD"},
        {"name": "New Zealand Dollar", "title": "New Zealand Dollar", "symbol": "$", "code": "NZD"},
        {"name": "Russian Ruble", "title": "Ruble", "symbol": "₽", "code": "RUB"},
        {"name": "Turkish Lira", "title": "Lira", "symbol": "₺", "code": "TRY"},
        {"name": "UAE Dirham", "title": "Dirham", "symbol": "د.إ", "code": "AED"},
        {"name": "Saudi Riyal", "title": "Riyal", "symbol": "﷼", "code": "SAR"},
        {"name": "Qatari Riyal", "title": "Qatari Riyal", "symbol": "﷼", "code": "QAR"},
        {"name": "Kuwaiti Dinar", "title": "Kuwaiti Dinar", "symbol": "د.ك", "code": "KWD"},
        {"name": "Omani Rial", "title": "Omani Rial", "symbol": "﷼", "code": "OMR"},
        {"name": "Bahraini Dinar", "title": "Bahraini Dinar", "symbol": ".د.ب", "code": "BHD"},
        {"name": "Iraqi Dinar", "title": "Iraqi Dinar", "symbol": "ع.د", "code": "IQD"},
        {"name": "Afghan Afghani", "title": "Afghani", "symbol": "؋", "code": "AFN"},
        {"name": "Pakistani Rupee", "title": "Rupee", "symbol": "₨", "code": "PKR"},
        {"name": "Indian Rupee", "title": "Rupee", "symbol": "₹", "code": "INR"},
        {"name": "Armenian Dram", "title": "Dram", "symbol": "֏", "code": "AMD"},
        {"name": "Azerbaijani Manat", "title": "Manat", "symbol": "₼", "code": "AZN"},
        {"name": "Georgian Lari", "title": "Lari", "symbol": "₾", "code": "GEL"},
        {"name": "Kazakhstani Tenge", "title": "Tenge", "symbol": "₸", "code": "KZT"},
        {"name": "Uzbekistani Som", "title": "Som", "symbol": "so'm", "code": "UZS"},
        {"name": "Tajikistani Somoni", "title": "Somoni", "symbol": "ЅМ", "code": "TJS"},
        {"name": "Turkmenistani Manat", "title": "Manat", "symbol": "m", "code": "TMT"},
        {"name": "Afgani Lek", "title": "Lek", "symbol": "L", "code": "ALL"},
        {"name": "Bulgarian Lev", "title": "Lev", "symbol": "лв", "code": "BGN"},
        {"name": "Romanian Leu", "title": "Leu", "symbol": "lei", "code": "RON"},
        {"name": "Polish Złoty", "title": "Zloty", "symbol": "zł", "code": "PLN"},
        {"name": "Czech Koruna", "title": "Koruna", "symbol": "Kč", "code": "CZK"},
        {"name": "Hungarian Forint", "title": "Forint", "symbol": "Ft", "code": "HUF"},
        {"name": "Danish Krone", "title": "Krone", "symbol": "kr", "code": "DKK"},
        {"name": "Norwegian Krone", "title": "Krone", "symbol": "kr", "code": "NOK"},
        {"name": "Swedish Krona", "title": "Krona", "symbol": "kr", "code": "SEK"},
        {"name": "Icelandic Króna", "title": "Krona", "symbol": "kr", "code": "ISK"},
        {"name": "Croatian Kuna", "title": "Kuna", "symbol": "kn", "code": "HRK"},
        {"name": "Serbian Dinar", "title": "Dinar", "symbol": "дин.", "code": "RSD"},
        {"name": "Bosnia and Herzegovina Mark", "title": "Mark", "symbol": "KM", "code": "BAM"},
        {"name": "Ukrainian Hryvnia", "title": "Hryvnia", "symbol": "₴", "code": "UAH"},
        {"name": "Belarusian Ruble", "title": "Ruble", "symbol": "Br", "code": "BYN"},
        {"name": "Egyptian Pound", "title": "Pound", "symbol": "£", "code": "EGP"},
        {"name": "South African Rand", "title": "Rand", "symbol": "R", "code": "ZAR"},
        {"name": "Nigerian Naira", "title": "Naira", "symbol": "₦", "code": "NGN"},
        {"name": "Kenyan Shilling", "title": "Shilling", "symbol": "Sh", "code": "KES"},
        {"name": "Ethiopian Birr", "title": "Birr", "symbol": "Br", "code": "ETB"},
        {"name": "Moroccan Dirham", "title": "Dirham", "symbol": "د.م.", "code": "MAD"},
        {"name": "Tunisian Dinar", "title": "Dinar", "symbol": "د.ت", "code": "TND"},
        {"name": "Algerian Dinar", "title": "Dinar", "symbol": "د.ج", "code": "DZD"},
        {"name": "Israeli New Shekel", "title": "Shekel", "symbol": "₪", "code": "ILS"},
        {"name": "Jordanian Dinar", "title": "Dinar", "symbol": "د.ا", "code": "JOD"},
        {"name": "Lebanese Pound", "title": "Pound", "symbol": "ل.ل", "code": "LBP"},
        {"name": "Syrian Pound", "title": "Pound", "symbol": "£", "code": "SYP"},
        {"name": "Singapore Dollar", "title": "Singapore Dollar", "symbol": "$", "code": "SGD"},
        {"name": "Hong Kong Dollar", "title": "Hong Kong Dollar", "symbol": "$", "code": "HKD"},
        {"name": "Thai Baht", "title": "Baht", "symbol": "฿", "code": "THB"},
        {"name": "Malaysian Ringgit", "title": "Ringgit", "symbol": "RM", "code": "MYR"},
        {"name": "Indonesian Rupiah", "title": "Rupiah", "symbol": "Rp", "code": "IDR"},
        {"name": "Philippine Peso", "title": "Peso", "symbol": "₱", "code": "PHP"},
        {"name": "Vietnamese Dong", "title": "Dong", "symbol": "₫", "code": "VND"},
        {"name": "South Korean Won", "title": "Won", "symbol": "₩", "code": "KRW"},
        {"name": "Taiwan New Dollar", "title": "New Dollar", "symbol": "$", "code": "TWD"},
        {"name": "Mexican Peso", "title": "Peso", "symbol": "$", "code": "MXN"},
        {"name": "Brazilian Real", "title": "Real", "symbol": "R$", "code": "BRL"},
        {"name": "Argentine Peso", "title": "Peso", "symbol": "$", "code": "ARS"},
        {"name": "Chilean Peso", "title": "Peso", "symbol": "$", "code": "CLP"},
        {"name": "Colombian Peso", "title": "Peso", "symbol": "$", "code": "COP"},
        {"name": "Peruvian Sol", "title": "Sol", "symbol": "S/.", "code": "PEN"},
        {"name": "Uruguayan Peso", "title": "Peso", "symbol": "$U", "code": "UYU"},
        {"name": "Paraguayan Guarani", "title": "Guarani", "symbol": "₲", "code": "PYG"},
        {"name": "Bolivian Boliviano", "title": "Boliviano", "symbol": "Bs.", "code": "BOB"},
        {"name": "Dominican Peso", "title": "Peso", "symbol": "RD$", "code": "DOP"},
        {"name": "Cuban Peso", "title": "Peso", "symbol": "$", "code": "CUP"},
        {"name": "Costa Rican Colon", "title": "Colon", "symbol": "₡", "code": "CRC"},
        {"name": "Guatemalan Quetzal", "title": "Quetzal", "symbol": "Q", "code": "GTQ"},
        {"name": "Honduran Lempira", "title": "Lempira", "symbol": "L", "code": "HNL"},
        {"name": "Nicaraguan Córdoba", "title": "Cordoba", "symbol": "C$", "code": "NIO"},
        {"name": "Panamanian Balboa", "title": "Balboa", "symbol": "B/.", "code": "PAB"},
        {"name": "Venezuelan Bolívar", "title": "Bolivar", "symbol": "Bs.", "code": "VES"},
    ]

    for row in currencies:
        conn.execute(insert_sql, row)
    
    # ========== 3. انواع مالیات ==========
    # پاک کردن داده‌های قبلی
    conn.execute(sa.text("DELETE FROM tax_types"))

    insert_stmt = sa.text(
        """
        INSERT INTO tax_types (title, code, description, created_at, updated_at)
        VALUES (:title, :code, :description, NOW(), NOW())
        """
    )
    
    # انواع مالیات استاندارد سازمان امور مالیاتی ایران
    tax_types = [
        {"title": "۱- دارو", "code": "1", "description": None},
        {"title": "۲- دخانیات", "code": "2", "description": None},
        {"title": "۳- موبایل", "code": "3", "description": None},
        {"title": "۴- لوازم خانگی برقی", "code": "4", "description": None},
        {"title": "۵- قطعات مصرفی و یدکی وسایل نقلیه", "code": "5", "description": None},
        {"title": "۶- فراورده ها و مشتقات نفتی و گازی و پتروشیمیایی", "code": "6", "description": None},
        {"title": "۷- طلا اعم از شمش ،مسکوکات و مصنوعات زینتی", "code": "7", "description": None},
        {"title": "۸- منسوجات و پوشاک", "code": "8", "description": None},
        {"title": "۹- اسباب بازی", "code": "9", "description": None},
        {"title": "۱۰- دام زنده، گوشت سفید و قرمز", "code": "10", "description": None},
        {"title": "۱۱- محصولات اساسی کشاورزی", "code": "11", "description": None},
        {"title": "۱۲- سایر کالا ها", "code": "12", "description": None},
    ]
    
    for tax_type in tax_types:
        conn.execute(insert_stmt, tax_type)
    
    # ========== 4. تنظیمات سیستم ==========
    # Seed default wallet base currency code to IRR if not set
    try:
        exists = conn.execute(
            sa.text("SELECT 1 FROM system_settings WHERE `key` = :k LIMIT 1"),
            {"k": "wallet_base_currency_code"}
        ).fetchone()
        if not exists:
            conn.execute(
                sa.text(
                    """
                    INSERT INTO system_settings (`key`, value_string, created_at, updated_at)
                    VALUES (:k, :v, NOW(), NOW())
                    """
                ),
                {"k": "wallet_base_currency_code", "v": "IRR"},
            )
    except Exception:
        pass  # non-fatal - جدول system_settings ممکن است وجود نداشته باشد


def downgrade():
    """حذف اطلاعات پایه"""
    conn = op.get_bind()
    
    # حذف تنظیمات سیستم
    try:
        conn.execute(
            sa.text("DELETE FROM system_settings WHERE `key` = :k"),
            {"k": "wallet_base_currency_code"}
        )
    except Exception:
        pass
    
    # حذف انواع مالیات
    try:
        conn.execute(sa.text("DELETE FROM tax_types"))
    except Exception:
        pass
    
    # حذف ارزها (اختیاری - معمولاً نمی‌خواهیم ارزها را حذف کنیم)
    # conn.execute(sa.text("DELETE FROM currencies"))
    
    # حذف داده‌های پشتیبانی
    try:
        conn.execute(sa.text("DELETE FROM support_statuses"))
        conn.execute(sa.text("DELETE FROM support_priorities"))
        conn.execute(sa.text("DELETE FROM support_categories"))
    except Exception:
        pass

