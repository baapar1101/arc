"""add_seed_data

Revision ID: 16a08b3cf47c
Revises: 20250101_000000
Create Date: 2026-01-03 11:52:55.549072

"""
from alembic import op
import sqlalchemy as sa
from datetime import datetime
import json


# revision identifiers, used by Alembic.
revision = '16a08b3cf47c'
down_revision = '20250101_000000'
branch_labels = None
depends_on = None


def upgrade() -> None:
        conn = op.get_bind()

        # === Seed from 20250101_000000_init_schema.py ===
    # === 19_seed_data ===
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
        ON CONFLICT (code) DO UPDATE SET
                    title = EXCLUDED.title,
                    symbol = EXCLUDED.symbol,
                    updated_at = EXCLUDED.updated_at
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
        # بررسی اینکه آیا جدول system_settings وجود دارد
        try:
            # بررسی وجود جدول
            table_exists = conn.execute(
                sa.text("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_name = 'system_settings'
                    )
                """)
            ).scalar()
            
            if table_exists:
                exists = conn.execute(
                    sa.text("SELECT 1 FROM system_settings WHERE key = :k LIMIT 1"),
                    {"k": "wallet_base_currency_code"}
                ).fetchone()
                if not exists:
                    conn.execute(
                        sa.text("""
                            INSERT INTO system_settings (key, value_string, created_at, updated_at)
                            VALUES (:k, :v, NOW(), NOW())
                        """),
                        {"k": "wallet_base_currency_code", "v": "IRR"},
                    )
        except Exception:
            pass  # non-fatal - جدول system_settings ممکن است وجود نداشته باشد


        # === 20_accounts_chart ===
        conn = op.get_bind()

        # نقشه id خارجی به id داخلی
        ext_to_internal: dict[int, int] = {}

        # کوئری‌ها
        select_existing = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = :code LIMIT 1")
        insert_q = sa.text(
        """
        INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
        VALUES (:name, NULL, :account_type, :code, :parent_id, NOW(), NOW())
        """
        )
        update_q = sa.text(
        """
        UPDATE accounts
        SET name = :name, account_type = :account_type, parent_id = :parent_id, updated_at = NOW()
        WHERE id = :id
        """
        )

        # داده‌های چارت حساب
        items = [
        {"id":2454,"level":3,"code":"102","name":"موجودی نقد و بانک","parentId":2453,"accountType":0},
        {"id":2455,"level":4,"code":"10201","name":"تنخواه گردان","parentId":2454,"accountType":2},
        {"id":2456,"level":4,"code":"10202","name":"صندوق","parentId":2454,"accountType":1},
        {"id":2457,"level":4,"code":"10203","name":"بانک","parentId":2454,"accountType":3},
        {"id":2458,"level":4,"code":"10204","name":"وجوه در راه","parentId":2454,"accountType":0},
        {"id":2459,"level":3,"code":"103","name":"سپرده های کوتاه مدت","parentId":2453,"accountType":0},
        {"id":2460,"level":4,"code":"10301","name":"سپرده شرکت در مناقصه و مزایده","parentId":2459,"accountType":0},
        {"id":2461,"level":4,"code":"10302","name":"ضمانت نامه بانکی","parentId":2459,"accountType":0},
        {"id":2462,"level":4,"code":"10303","name":"سایر سپرده ها","parentId":2459,"accountType":0},
        {"id":2463,"level":3,"code":"104","name":"حساب های دریافتنی","parentId":2453,"accountType":0},
        {"id":2464,"level":4,"code":"10401","name":"حساب های دریافتنی","parentId":2463,"accountType":4},
        {"id":2465,"level":4,"code":"10402","name":"ذخیره مطالبات مشکوک الوصول","parentId":2463,"accountType":0},
        {"id":2466,"level":4,"code":"10403","name":"اسناد دریافتنی","parentId":2463,"accountType":5},
        {"id":2467,"level":4,"code":"10404","name":"اسناد در جریان وصول","parentId":2463,"accountType":6},
        {"id":2468,"level":3,"code":"105","name":"سایر حساب های دریافتنی","parentId":2453,"accountType":0},
        {"id":2469,"level":4,"code":"10501","name":"وام کارکنان","parentId":2468,"accountType":0},
        {"id":2470,"level":4,"code":"10502","name":"سایر حساب های دریافتنی","parentId":2468,"accountType":0},
        {"id":2471,"level":3,"code":"10101","name":"پیش پرداخت ها","parentId":2453,"accountType":0},
        {"id":2472,"level":3,"code":"10102","name":"موجودی کالا","parentId":2453,"accountType":7},
        {"id":2473,"level":3,"code":"10103","name":"ملزومات","parentId":2453,"accountType":0},
        {"id":2474,"level":3,"code":"10104","name":"مالیات بر ارزش افزوده خرید","parentId":2453,"accountType":8},
        {"id":2475,"level":2,"code":"106","name":"دارایی های غیر جاری","parentId":2452,"accountType":0},
        {"id":2476,"level":3,"code":"107","name":"دارایی های ثابت","parentId":2475,"accountType":0},
        {"id":2477,"level":4,"code":"10701","name":"زمین","parentId":2476,"accountType":0},
        {"id":2478,"level":4,"code":"10702","name":"ساختمان","parentId":2476,"accountType":0},
        {"id":2479,"level":4,"code":"10703","name":"وسائط نقلیه","parentId":2476,"accountType":0},
        {"id":2480,"level":4,"code":"10704","name":"اثاثیه اداری","parentId":2476,"accountType":0},
        {"id":2481,"level":3,"code":"108","name":"استهلاک انباشته","parentId":2475,"accountType":0},
        {"id":2482,"level":4,"code":"10801","name":"استهلاک انباشته ساختمان","parentId":2481,"accountType":0},
        {"id":2483,"level":4,"code":"10802","name":"استهلاک انباشته وسائط نقلیه","parentId":2481,"accountType":0},
        {"id":2484,"level":4,"code":"10803","name":"استهلاک انباشته اثاثیه اداری","parentId":2481,"accountType":0},
        {"id":2485,"level":3,"code":"109","name":"سپرده های بلندمدت","parentId":2475,"accountType":0},
        {"id":2486,"level":3,"code":"110","name":"سایر دارائی ها","parentId":2475,"accountType":0},
        {"id":2487,"level":4,"code":"11001","name":"حق الامتیازها","parentId":2486,"accountType":0},
        {"id":2488,"level":4,"code":"11002","name":"نرم افزارها","parentId":2486,"accountType":0},
        {"id":2489,"level":4,"code":"11003","name":"سایر دارایی های نامشهود","parentId":2486,"accountType":0},
        {"id":2490,"level":1,"code":"2","name":"بدهی ها","parentId":0,"accountType":0},
        {"id":2491,"level":2,"code":"201","name":"بدهیهای جاری","parentId":2490,"accountType":0},
        {"id":2492,"level":3,"code":"202","name":"حساب ها و اسناد پرداختنی","parentId":2491,"accountType":0},
        {"id":2493,"level":4,"code":"20201","name":"حساب های پرداختنی","parentId":2492,"accountType":9},
        {"id":2494,"level":4,"code":"20202","name":"اسناد پرداختنی","parentId":2492,"accountType":10},
        {"id":2495,"level":3,"code":"203","name":"سایر حساب های پرداختنی","parentId":2491,"accountType":0},
        {"id":2496,"level":4,"code":"20301","name":"ذخیره مالیات بر درآمد پرداختنی","parentId":2495,"accountType":40},
        {"id":2497,"level":4,"code":"20302","name":"مالیات بر درآمد پرداختنی","parentId":2495,"accountType":12},
        {"id":2498,"level":4,"code":"20303","name":"مالیات حقوق و دستمزد پرداختنی","parentId":2495,"accountType":0},
        {"id":2499,"level":4,"code":"20304","name":"حق بیمه پرداختنی","parentId":2495,"accountType":0},
        {"id":2500,"level":4,"code":"20305","name":"حقوق و دستمزد پرداختنی","parentId":2495,"accountType":42},
        {"id":2501,"level":4,"code":"20306","name":"عیدی و پاداش پرداختنی","parentId":2495,"accountType":0},
        {"id":2502,"level":4,"code":"20307","name":"سایر هزینه های پرداختنی","parentId":2495,"accountType":0},
        {"id":2503,"level":3,"code":"204","name":"پیش دریافت ها","parentId":2491,"accountType":0},
        {"id":2504,"level":4,"code":"20401","name":"پیش دریافت فروش","parentId":2503,"accountType":0},
        {"id":2505,"level":4,"code":"20402","name":"سایر پیش دریافت ها","parentId":2503,"accountType":0},
        {"id":2506,"level":3,"code":"20101","name":"مالیات بر ارزش افزوده فروش","parentId":2491,"accountType":11},
        {"id":2507,"level":2,"code":"205","name":"بدهیهای غیر جاری","parentId":2490,"accountType":0},
        {"id":2508,"level":3,"code":"206","name":"حساب ها و اسناد پرداختنی بلندمدت","parentId":2507,"accountType":0},
        {"id":2509,"level":4,"code":"20601","name":"حساب های پرداختنی بلندمدت","parentId":2508,"accountType":0},
        {"id":2510,"level":4,"code":"20602","name":"اسناد پرداختنی بلندمدت","parentId":2508,"accountType":0},
        {"id":2511,"level":3,"code":"20501","name":"وام پرداختنی","parentId":2507,"accountType":0},
        {"id":2512,"level":3,"code":"20502","name":"ذخیره مزایای پایان خدمت کارکنان","parentId":2507,"accountType":0},
        {"id":2513,"level":1,"code":"3","name":"حقوق صاحبان سهام","parentId":0,"accountType":0},
        {"id":2514,"level":2,"code":"301","name":"سرمایه","parentId":2513,"accountType":0},
        {"id":2515,"level":3,"code":"30101","name":"سرمایه اولیه","parentId":2514,"accountType":13},
        {"id":2516,"level":3,"code":"30102","name":"افزایش یا کاهش سرمایه","parentId":2514,"accountType":14},
        {"id":2517,"level":3,"code":"30103","name":"اندوخته قانونی","parentId":2514,"accountType":15},
        {"id":2518,"level":3,"code":"30104","name":"برداشت ها","parentId":2514,"accountType":16},
        {"id":2519,"level":3,"code":"30105","name":"سهم سود و زیان","parentId":2514,"accountType":17},
        {"id":2520,"level":3,"code":"30106","name":"سود یا زیان انباشته (سنواتی)","parentId":2514,"accountType":18},
        {"id":2521,"level":1,"code":"4","name":"بهای تمام شده کالای فروخته شده","parentId":0,"accountType":0},
        {"id":2522,"level":2,"code":"40001","name":"بهای تمام شده کالای فروخته شده","parentId":2521,"accountType":19},
        {"id":2523,"level":2,"code":"40002","name":"برگشت از خرید","parentId":2521,"accountType":20},
        {"id":2524,"level":2,"code":"40003","name":"تخفیفات نقدی خرید","parentId":2521,"accountType":21},
        {"id":2525,"level":1,"code":"5","name":"فروش","parentId":0,"accountType":0},
        {"id":2526,"level":2,"code":"50001","name":"فروش کالا","parentId":2525,"accountType":22},
        {"id":2527,"level":2,"code":"50002","name":"برگشت از فروش","parentId":2525,"accountType":23},
        {"id":2528,"level":2,"code":"50003","name":"تخفیفات نقدی فروش","parentId":2525,"accountType":24},
        {"id":2529,"level":1,"code":"6","name":"درآمد","parentId":0,"accountType":0},
        {"id":2530,"level":2,"code":"601","name":"درآمد های عملیاتی","parentId":2529,"accountType":0},
        {"id":2531,"level":3,"code":"60101","name":"درآمد حاصل از فروش خدمات","parentId":2530,"accountType":25},
        {"id":2532,"level":3,"code":"60102","name":"برگشت از خرید خدمات","parentId":2530,"accountType":26},
        {"id":2533,"level":3,"code":"60103","name":"درآمد اضافه کالا","parentId":2530,"accountType":27},
        {"id":2534,"level":3,"code":"60104","name":"درآمد حمل کالا","parentId":2530,"accountType":28},
        {"id":2535,"level":2,"code":"602","name":"درآمد های غیر عملیاتی","parentId":2529,"accountType":0},
        {"id":2536,"level":3,"code":"60201","name":"درآمد حاصل از سرمایه گذاری","parentId":2535,"accountType":0},
        {"id":2537,"level":3,"code":"60202","name":"درآمد سود سپرده ها","parentId":2535,"accountType":0},
        {"id":2538,"level":3,"code":"60203","name":"سایر درآمد ها","parentId":2535,"accountType":0},
        {"id":2539,"level":3,"code":"60204","name":"درآمد تسعیر ارز","parentId":2535,"accountType":36},
        {"id":2540,"level":1,"code":"7","name":"هزینه ها","parentId":0,"accountType":0},
        {"id":2541,"level":2,"code":"701","name":"هزینه های پرسنلی","parentId":2540,"accountType":0},
        {"id":2542,"level":3,"code":"702","name":"هزینه حقوق و دستمزد","parentId":2541,"accountType":0},
        {"id":2543,"level":4,"code":"70201","name":"حقوق پایه","parentId":2542,"accountType":0},
        {"id":2544,"level":4,"code":"70202","name":"اضافه کار","parentId":2542,"accountType":0},
        {"id":2545,"level":4,"code":"70203","name":"حق شیفت و شب کاری","parentId":2542,"accountType":0},
        {"id":2546,"level":4,"code":"70204","name":"حق نوبت کاری","parentId":2542,"accountType":0},
        {"id":2547,"level":4,"code":"70205","name":"حق ماموریت","parentId":2542,"accountType":0},
        {"id":2548,"level":4,"code":"70206","name":"فوق العاده مسکن و خاروبار","parentId":2542,"accountType":0},
        {"id":2549,"level":4,"code":"70207","name":"حق اولاد","parentId":2542,"accountType":0},
        {"id":2550,"level":4,"code":"70208","name":"عیدی و پاداش","parentId":2542,"accountType":0},
        {"id":2551,"level":4,"code":"70209","name":"بازخرید سنوات خدمت کارکنان","parentId":2542,"accountType":0},
        {"id":2552,"level":4,"code":"70210","name":"بازخرید مرخصی","parentId":2542,"accountType":0},
        {"id":2553,"level":4,"code":"70211","name":"بیمه سهم کارفرما","parentId":2542,"accountType":0},
        {"id":2554,"level":4,"code":"70212","name":"بیمه بیکاری","parentId":2542,"accountType":0},
        {"id":2555,"level":4,"code":"70213","name":"حقوق مزایای متفرقه","parentId":2542,"accountType":0},
        {"id":2556,"level":3,"code":"703","name":"سایر هزینه های کارکنان","parentId":2541,"accountType":0},
        {"id":2557,"level":4,"code":"70301","name":"سفر و ماموریت","parentId":2556,"accountType":0},
        {"id":2558,"level":4,"code":"70302","name":"ایاب و ذهاب","parentId":2556,"accountType":0},
        {"id":2559,"level":4,"code":"70303","name":"سایر هزینه های کارکنان","parentId":2556,"accountType":0},
        {"id":2560,"level":2,"code":"704","name":"هزینه های عملیاتی","parentId":2540,"accountType":0},
        {"id":2561,"level":3,"code":"70401","name":"خرید خدمات","parentId":2560,"accountType":30},
        {"id":2562,"level":3,"code":"70402","name":"برگشت از فروش خدمات","parentId":2560,"accountType":29},
        {"id":2563,"level":3,"code":"70403","name":"هزینه حمل کالا","parentId":2560,"accountType":31},
        {"id":2564,"level":3,"code":"70404","name":"تعمیر و نگهداری اموال و اثاثیه","parentId":2560,"accountType":0},
        {"id":2565,"level":3,"code":"70405","name":"هزینه اجاره محل","parentId":2560,"accountType":0},
        {"id":2566,"level":2,"code":"705","name":"هزینه های عمومی","parentId":2540,"accountType":0},
        {"id":2567,"level":4,"code":"70501","name":"هزینه آب و برق و گاز و تلفن","parentId":2566,"accountType":0},
        {"id":2568,"level":4,"code":"70502","name":"هزینه پذیرایی و آبدارخانه","parentId":2566,"accountType":0},
        {"id":2569,"level":3,"code":"70406","name":"هزینه ملزومات مصرفی","parentId":2560,"accountType":0},
        {"id":2570,"level":3,"code":"70407","name":"هزینه کسری و ضایعات کالا","parentId":2560,"accountType":32},
        {"id":2571,"level":3,"code":"70408","name":"بیمه دارایی های ثابت","parentId":2560,"accountType":0},
        {"id":2572,"level":2,"code":"706","name":"هزینه های استهلاک","parentId":2540,"accountType":0},
        {"id":2573,"level":3,"code":"70601","name":"هزینه استهلاک ساختمان","parentId":2572,"accountType":0},
        {"id":2574,"level":3,"code":"70602","name":"هزینه استهلاک وسائط نقلیه","parentId":2572,"accountType":0},
        {"id":2575,"level":3,"code":"70603","name":"هزینه استهلاک اثاثیه","parentId":2572,"accountType":0},
        {"id":2576,"level":2,"code":"707","name":"هزینه های بازاریابی و توزیع و فروش","parentId":2540,"accountType":0},
        {"id":2577,"level":3,"code":"70701","name":"هزینه آگهی و تبلیغات","parentId":2576,"accountType":0},
        {"id":2578,"level":3,"code":"70702","name":"هزینه بازاریابی و پورسانت","parentId":2576,"accountType":0},
        {"id":2579,"level":3,"code":"70703","name":"سایر هزینه های توزیع و فروش","parentId":2576,"accountType":0},
        {"id":2580,"level":2,"code":"708","name":"هزینه های غیرعملیاتی","parentId":2540,"accountType":0},
        {"id":2581,"level":3,"code":"709","name":"هزینه های بانکی","parentId":2580,"accountType":0},
        {"id":2582,"level":4,"code":"70901","name":"سود و کارمزد وامها","parentId":2581,"accountType":0},
        {"id":2583,"level":4,"code":"70902","name":"کارمزد خدمات بانکی","parentId":2581,"accountType":33},
        {"id":2584,"level":4,"code":"70903","name":"جرائم دیرکرد بانکی","parentId":2581,"accountType":0},
        {"id":2585,"level":3,"code":"70801","name":"هزینه تسعیر ارز","parentId":2580,"accountType":37},
        {"id":2586,"level":3,"code":"70802","name":"هزینه مطالبات سوخت شده","parentId":2580,"accountType":0},
        {"id":2587,"level":1,"code":"8","name":"سایر حساب ها","parentId":0,"accountType":0},
        {"id":2588,"level":2,"code":"801","name":"حساب های انتظامی","parentId":2587,"accountType":0},
        {"id":2589,"level":3,"code":"80101","name":"حساب های انتظامی","parentId":2588,"accountType":0},
        {"id":2590,"level":3,"code":"80102","name":"طرف حساب های انتظامی","parentId":2588,"accountType":0},
        {"id":2591,"level":2,"code":"802","name":"حساب های کنترلی","parentId":2587,"accountType":0},
        {"id":2592,"level":3,"code":"80201","name":"کنترل کسری و اضافه کالا","parentId":2591,"accountType":34},
        {"id":2593,"level":2,"code":"803","name":"حساب خلاصه سود و زیان","parentId":2587,"accountType":0},
        {"id":2594,"level":3,"code":"80301","name":"خلاصه سود و زیان","parentId":2593,"accountType":35},
        {"id":2595,"level":5,"code":"70503","name":"هزینه آب","parentId":2567,"accountType":0},
        {"id":2596,"level":5,"code":"70504","name":"هزینه برق","parentId":2567,"accountType":0},
        {"id":2597,"level":5,"code":"70505","name":"هزینه گاز","parentId":2567,"accountType":0},
        {"id":2598,"level":5,"code":"70506","name":"هزینه تلفن","parentId":2567,"accountType":0},
        {"id":2600,"level":4,"code":"20503","name":"وام از بانک ملت","parentId":2511,"accountType":0},
        {"id":2601,"level":4,"code":"10405","name":"سود تحقق نیافته فروش اقساطی","parentId":2463,"accountType":39},
        {"id":2602,"level":3,"code":"60205","name":"سود فروش اقساطی","parentId":2535,"accountType":38},
        {"id":2603,"level":4,"code":"70214","name":"حق تاهل","parentId":2542,"accountType":0},
        {"id":2604,"level":4,"code":"20504","name":"وام از بانک پارسیان","parentId":2511,"accountType":0},
        {"id":2605,"level":3,"code":"10105","name":"مساعده","parentId":2453,"accountType":0},
        {"id":2606,"level":3,"code":"60105","name":"تعمیرات لوازم آشپزخانه","parentId":2530,"accountType":0},
        {"id":2607,"level":4,"code":"10705","name":"کامپیوتر","parentId":2476,"accountType":0},
        {"id":2608,"level":3,"code":"60206","name":"درامد حاصل از فروش ضایعات","parentId":2535,"accountType":0},
        {"id":2609,"level":3,"code":"60207","name":"سود فروش دارایی","parentId":2535,"accountType":0},
        {"id":2610,"level":3,"code":"70803","name":"زیان فروش دارایی","parentId":2580,"accountType":0},
        {"id":2611,"level":3,"code":"10106","name":"موجودی کالای در جریان ساخت","parentId":2453,"accountType":41},
        {"id":2612,"level":3,"code":"20102","name":"سربار تولید پرداختنی","parentId":2491,"accountType":43},
        {"id":2613,"level":1,"code":"1","name":"دارایی ها","parentId":0,"accountType":0},
        {"id":2614,"level":2,"code":"101","name":"دارایی های جاری","parentId":2613,"accountType":0},
        {"id":2615,"level":4,"code":"10205","name":"کیف پول","parentId":2454,"accountType":0},
        {"id":2616,"level":4,"code":"70507","name":"هزینه جدید","parentId":2566,"accountType":0},
        {"id":2617,"level":4,"code":"70508","name":"هزینه هوش مصنوعی","parentId":2566,"accountType":0},
        {"id":2618,"level":4,"code":"70509","name":"هزینه سرویس‌های استعلامات","parentId":2566,"accountType":0},
        ]

        # 2452 و 2453 در لیست items نیستند (ارجاع به چارت قدیمی).
        # نگاشت به idهای معادل در این چارت: 2452 -> 2613 (دارایی ها)، 2453 -> 2614 (دارایی های جاری)
        LEGACY_PARENT_2452 = 2613
        LEGACY_PARENT_2453 = 2614

        # ایجاد حساب‌ها به ترتیب level تا والد قبل از فرزند درج شود
        items.sort(key=lambda x: (x["level"], int(x["code"])))

        for item in items:
            # پیدا کردن parent_id با رعایت ساختار درختی
            parent_internal_id = None
            pid = item["parentId"]
            if pid != 0:
                if pid == 2452:
                    parent_internal_id = ext_to_internal.get(LEGACY_PARENT_2452)
                elif pid == 2453:
                    parent_internal_id = ext_to_internal.get(LEGACY_PARENT_2453)
                else:
                    parent_internal_id = ext_to_internal.get(pid)

            # بررسی اینکه آیا حساب از قبل وجود دارد
            existing = conn.execute(select_existing, {"code": item["code"]}).fetchone()

            if existing:
                acc_id = existing[0]
                ext_to_internal[item["id"]] = acc_id
                conn.execute(update_q, {
                    "id": acc_id,
                    "name": item["name"],
                    "account_type": item["accountType"],
                    "parent_id": parent_internal_id
                })
            else:
                result = conn.execute(insert_q, {
                    "name": item["name"],
                    "account_type": item["accountType"],
                    "code": item["code"],
                    "parent_id": parent_internal_id
                })
                ext_to_internal[item["id"]] = result.lastrowid

        # === 43_fix_zohal_account_code ===
        conn = op.get_bind()

        # 1. برگرداندن حساب 70903 به نام اصلی "جرائم دیرکرد بانکی" (اگر تغییر کرده باشد)
        update_70903 = sa.text("""
            UPDATE accounts
            SET name = 'جرائم دیرکرد بانکی',
                updated_at = NOW()
            WHERE code = '70903'
              AND business_id IS NULL
              AND name != 'جرائم دیرکرد بانکی'
        """)
        conn.execute(update_70903)

        # 2. ایجاد حساب 70509 برای "هزینه سرویس‌های استعلامات"
        # ابتدا بررسی می‌کنیم که آیا حساب 705 وجود دارد
        check_705 = sa.text("SELECT id FROM accounts WHERE code = '705' AND business_id IS NULL LIMIT 1")
        result_705 = conn.execute(check_705).fetchone()

        if result_705:
            parent_id_705 = result_705[0]

            # بررسی می‌کنیم که آیا حساب 70509 از قبل وجود دارد
            check_70509 = sa.text("SELECT id FROM accounts WHERE code = '70509' AND business_id IS NULL LIMIT 1")
            result_70509 = conn.execute(check_70509).fetchone()

            if not result_70509:
                # ایجاد حساب 70509
                insert_70509 = sa.text("""
                    INSERT INTO accounts (name, code, account_type, business_id, parent_id, created_at, updated_at)
                    VALUES ('هزینه سرویس‌های استعلامات', '70509', 'accounting_document', NULL, :parent_id, NOW(), NOW())
                """)
                conn.execute(insert_70509, {"parent_id": parent_id_705})
            else:
                # به‌روزرسانی نام حساب در صورت نیاز
                update_70509 = sa.text("""
                    UPDATE accounts
                    SET name = 'هزینه سرویس‌های استعلامات',
                        account_type = 'accounting_document',
                        parent_id = :parent_id,
                        updated_at = NOW()
                    WHERE code = '70509'
                      AND business_id IS NULL
                """)
                conn.execute(update_70509, {"parent_id": parent_id_705})
        # === Seed from 20250205_000002_seed_repair_shop_plugin.py ===
        conn = op.get_bind()
        
        # بررسی اینکه آیا جدول marketplace_plugins وجود دارد
        table_exists = conn.execute(
            sa.text("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'marketplace_plugins'
                )
            """)
        ).scalar()
        
        if not table_exists:
            return  # جدول وجود ندارد، seed data را skip می‌کنیم
        
        # بررسی اینکه آیا افزونه قبلاً وجود دارد
        result = conn.execute(sa.text(
            "SELECT id FROM marketplace_plugins WHERE code = 'repair_shop_management'"
        ))
        existing_plugin = result.fetchone()

        if existing_plugin:
            print(f"✅ افزونه قبلاً وجود دارد (ID: {existing_plugin[0]})")
            return

            # دریافت ارز تومان
            result = conn.execute(sa.text("SELECT id FROM currencies WHERE code = 'IRR' LIMIT 1"))
            currency_row = result.fetchone()

            if not currency_row:
                print("⚠️ ارز تومان (IRR) یافت نشد. لطفاً ابتدا ارز را اضافه کنید.")
                return

            currency_id = currency_row[0]

            # اضافه کردن افزونه
            result = conn.execute(
                sa.text("""
                    INSERT INTO marketplace_plugins 
                    (code, name, description, category, icon_url, is_active, trial_days, trial_allowed, created_at, updated_at)
                    VALUES 
                    (:code, :name, :description, :category, :icon_url, :is_active, :trial_days, :trial_allowed, NOW(), NOW())
                """),
                {
                    'code': 'repair_shop_management',
                    'name': 'مدیریت تعمیرگاه',
                    'description': """سیستم جامع مدیریت تعمیرگاه با قابلیت‌های زیر:

        ✅ دریافت و تحویل کالای تعمیری
        ✅ صدور قبض رسید کالا
        ✅ کارتابل تعمیرات (Kanban Board)
        ✅ یکپارچگی با سیستم گارانتی
        ✅ مدیریت تعمیرکاران و حق‌الزحمه (فیکس، درصدی، موردی)
        ✅ افزودن قطعات استفاده شده
        ✅ حواله خروج خودکار قطعات از انبار
        ✅ بررسی موجودی قبل از مصرف
        ✅ ارسال پیامک و ایمیل خودکار به مشتری
        ✅ صدور فاکتور تعمیر (خدمات + قطعات)
        ✅ ثبت خودکار اسناد حسابداری
        ✅ تاریخچه کامل تعمیرات براساس کد گارانتی
        ✅ گزارش‌گیری جامع از عملکرد تعمیرکاران
        ✅ مدیریت ضمائم و تصاویر (قبل/بعد تعمیر)
        ✅ کنترل سطح دسترسی کاربران

        مناسب برای:
        🔧 تعمیرگاه‌های لوازم الکترونیکی
        📱 مراکز تعمیر موبایل و تبلت
        💻 سرویس‌های تعمیر لپتاپ و کامپیوتر
        🏠 تعمیرگاه‌های لوازم خانگی
        🚗 مراکز خدمات خودرو""",
                    'category': 'operations',
                    'icon_url': '/assets/icons/repair_shop.svg',
                    'is_active': True,
                    'trial_days': 14,
                    'trial_allowed': True,
                }
            )

            # دریافت ID افزونه ایجاد شده
            result = conn.execute(sa.text(
                "SELECT id FROM marketplace_plugins WHERE code = 'repair_shop_management'"
            ))
            plugin_row = result.fetchone()
            plugin_id = plugin_row[0]

            print(f"✅ افزونه ایجاد شد (ID: {plugin_id})")

            # اضافه کردن پلن ماهانه
            conn.execute(
                sa.text("""
                    INSERT INTO marketplace_plugin_plans 
                    (plugin_id, period, price, currency_id, is_active, created_at, updated_at)
                    VALUES 
                    (:plugin_id, :period, :price, :currency_id, :is_active, NOW(), NOW())
                """),
                {
                    'plugin_id': plugin_id,
                    'period': 'monthly',
                    'price': 500000,
                    'currency_id': currency_id,
                    'is_active': True,
                }
            )
            print("   ✅ پلن ماهانه ایجاد شد (500,000 تومان)")

            # اضافه کردن پلن سالانه
            conn.execute(
                sa.text("""
                    INSERT INTO marketplace_plugin_plans 
                    (plugin_id, period, price, currency_id, is_active, created_at, updated_at)
                    VALUES 
                    (:plugin_id, :period, :price, :currency_id, :is_active, NOW(), NOW())
                """),
                {
                    'plugin_id': plugin_id,
                    'period': 'yearly',
                    'price': 5000000,
                    'currency_id': currency_id,
                    'is_active': True,
                }
            )
            print("   ✅ پلن سالانه ایجاد شد (5,000,000 تومان)")

            print("\n" + "="*60)
            print("✅ افزونه مدیریت تعمیرگاه با موفقیت در marketplace ثبت شد!")
            print("="*60)




        # === Seed from 20250118_000001_add_product_warranty_plugin.py ===


            conn = op.get_bind()

            # پیدا کردن اولین ارز (معمولاً IRR)
            currency_result = conn.execute(sa.text("SELECT id FROM currencies ORDER BY id ASC LIMIT 1")).fetchone()
            if not currency_result:
                raise Exception("هیچ ارزی در سیستم یافت نشد. لطفاً ابتدا ارزها را اضافه کنید.")
            currency_id = currency_result[0]

            # بررسی اینکه آیا افزونه از قبل وجود دارد
            existing_plugin = conn.execute(
                sa.text("SELECT id FROM marketplace_plugins WHERE code = 'product_warranty' LIMIT 1")
            ).fetchone()

            if existing_plugin:
                # اگر از قبل وجود دارد، فقط اطمینان حاصل می‌کنیم که فعال است
                conn.execute(sa.text("""
                    UPDATE marketplace_plugins
                    SET is_active = 1,
                        updated_at = NOW()
                    WHERE code = 'product_warranty'
                """))
            else:
                # ایجاد افزونه گارانتی کالا
                now = datetime.utcnow()
                insert_plugin = sa.text("""
                    INSERT INTO marketplace_plugins (
                        code, name, description, category, icon_url, is_active, created_at, updated_at
                    )
                    VALUES (
                        'product_warranty',
                        'گارانتی کالا',
                        'افزونه مدیریت گارانتی کالا - امکان ثبت و پیگیری گارانتی محصولات فروخته شده',
                        'product_management',
                        NULL,
                        1,
                        :created_at,
                        :updated_at
                    )
                """)
                conn.execute(insert_plugin, {"created_at": now, "updated_at": now})

            # دریافت ID افزونه
            plugin_result = conn.execute(
                sa.text("SELECT id FROM marketplace_plugins WHERE code = 'product_warranty' LIMIT 1")
            ).fetchone()
            plugin_id = plugin_result[0]

            # بررسی و ایجاد پلن ماهانه
            existing_monthly = conn.execute(
                sa.text("""
                    SELECT id FROM marketplace_plugin_plans
                    WHERE plugin_id = :plugin_id AND period = 'monthly'
                    LIMIT 1
                """).bindparams(plugin_id=plugin_id)
            ).fetchone()

            if not existing_monthly:
                now = datetime.utcnow()
                insert_monthly = sa.text("""
                    INSERT INTO marketplace_plugin_plans (
                        plugin_id, period, price, currency_id, is_active, created_at, updated_at
                    )
                    VALUES (
                        :plugin_id,
                        'monthly',
                        100000,
                        :currency_id,
                        1,
                        :created_at,
                        :updated_at
                    )
                """)
                conn.execute(insert_monthly, {
                    "plugin_id": plugin_id,
                    "currency_id": currency_id,
                    "created_at": now,
                    "updated_at": now
                })

            # بررسی و ایجاد پلن سالانه
            existing_yearly = conn.execute(
                sa.text("""
                    SELECT id FROM marketplace_plugin_plans
                    WHERE plugin_id = :plugin_id AND period = 'yearly'
                    LIMIT 1
                """).bindparams(plugin_id=plugin_id)
            ).fetchone()

            if not existing_yearly:
                now = datetime.utcnow()
                insert_yearly = sa.text("""
                    INSERT INTO marketplace_plugin_plans (
                        plugin_id, period, price, currency_id, is_active, created_at, updated_at
                    )
                    VALUES (
                        :plugin_id,
                        'yearly',
                        1000000,
                        :currency_id,
                        1,
                        :created_at,
                        :updated_at
                    )
                """)
                conn.execute(insert_yearly, {
                    "plugin_id": plugin_id,
                    "currency_id": currency_id,
                    "created_at": now,
                    "updated_at": now
                })




        # === Seed from 20250121_000001_add_ai_expense_account.py ===
        def upgrade() -> None:
            conn = op.get_bind()

            # حساب والد (705) باید وجود داشته باشد
            parent_705 = conn.execute(
                sa.text("SELECT id FROM accounts WHERE code = '705' AND business_id IS NULL LIMIT 1")
            ).fetchone()
            if not parent_705:
                # اگر به هر دلیل chart حساب‌ها هنوز seed نشده باشد، این migration را fail نمی‌کنیم
                # تا مسیر upgrade کل سیستم نشکند؛ ایجاد 70508 بدون والد هم معنی ندارد.
                return

            parent_id_705 = parent_705[0]

            # اگر 70508 وجود ندارد، ایجادش کن؛ اگر هست، نام/والد را اصلاح کن (idempotent)
            existing_70508 = conn.execute(
                sa.text("SELECT id FROM accounts WHERE code = '70508' AND business_id IS NULL LIMIT 1")
            ).fetchone()

            if not existing_70508:
                conn.execute(
                    sa.text(

                    ),
                    {"parent_id": parent_id_705},
                )
            else:
                conn.execute(
                    sa.text(
                        """
                        UPDATE accounts
                        SET name = 'هزینه هوش مصنوعی',
                            parent_id = :parent_id,
                            account_type = 'accounting_document',
                            updated_at = NOW()
                        WHERE code = '70508' AND business_id IS NULL
                        """
                    ),
                    {"parent_id": parent_id_705},
                )




        # === Seed from 20250115_000001_fix_zohal_account_code.py ===


            conn = op.get_bind()

            # 1. برگرداندن حساب 70903 به نام اصلی "جرائم دیرکرد بانکی" (اگر تغییر کرده باشد)
            update_70903 = sa.text("""
                UPDATE accounts
                SET name = 'جرائم دیرکرد بانکی',
                    updated_at = NOW()
                WHERE code = '70903'
                AND business_id IS NULL
                AND name != 'جرائم دیرکرد بانکی'
            """)
            conn.execute(update_70903)

            # 2. ایجاد حساب 70509 برای "هزینه سرویس‌های استعلامات"
            # ابتدا بررسی می‌کنیم که آیا حساب 705 وجود دارد
            check_705 = sa.text("SELECT id FROM accounts WHERE code = '705' AND business_id IS NULL LIMIT 1")
            result_705 = conn.execute(check_705).fetchone()

            if result_705:
                parent_id_705 = result_705[0]

                # بررسی می‌کنیم که آیا حساب 70509 از قبل وجود دارد
                check_70509 = sa.text("SELECT id FROM accounts WHERE code = '70509' AND business_id IS NULL LIMIT 1")
                result_70509 = conn.execute(check_70509).fetchone()

                if not result_70509:
                    # ایجاد حساب 70509
                    insert_70509 = sa.text("""
                        INSERT INTO accounts (name, code, account_type, business_id, parent_id, created_at, updated_at)
                        VALUES ('هزینه سرویس‌های استعلامات', '70509', 'accounting_document', NULL, :parent_id, NOW(), NOW())
                    """)
                    conn.execute(insert_70509, {"parent_id": parent_id_705})
                else:
                    # به‌روزرسانی نام حساب در صورت نیاز
                    update_70509 = sa.text("""
                        UPDATE accounts
                        SET name = 'هزینه سرویس‌های استعلامات',
                            account_type = 'accounting_document',
                            parent_id = :parent_id,
                            updated_at = NOW()
                        WHERE code = '70509'
                        AND business_id IS NULL
                    """)
                    conn.execute(update_70509, {"parent_id": parent_id_705})




        # === Seed from 20251202_000002_create_document_monetization_expense_account.py ===


            conn = op.get_bind()

            # بررسی می‌کنیم که آیا حساب 705 وجود دارد
            check_705 = sa.text("SELECT id FROM accounts WHERE code = '705' AND business_id IS NULL LIMIT 1")
            result_705 = conn.execute(check_705).fetchone()

            if result_705:
                parent_id_705 = result_705[0]

                # بررسی می‌کنیم که آیا حساب 70507 از قبل وجود دارد
                check_70507 = sa.text("SELECT id FROM accounts WHERE code = '70507' AND business_id IS NULL LIMIT 1")
                result_70507 = conn.execute(check_70507).fetchone()

                if not result_70507:
                    # ایجاد حساب 70507
                    insert_70507 = sa.text("""
                        INSERT INTO accounts (name, code, account_type, business_id, parent_id, created_at, updated_at)
                        VALUES ('هزینه اشتراک و خدمات سیستم', '70507', 'accounting_document', NULL, :parent_id, NOW(), NOW())
                    """)
                    conn.execute(insert_70507, {"parent_id": parent_id_705})
                else:
                    # به‌روزرسانی نام حساب در صورت نیاز
                    update_70507 = sa.text("""
                        UPDATE accounts
                        SET name = 'هزینه اشتراک و خدمات سیستم',
                            account_type = 'accounting_document',
                            parent_id = :parent_id,
                            updated_at = NOW()
                        WHERE code = '70507'
                        AND business_id IS NULL
                    """)
                    conn.execute(update_70507, {"parent_id": parent_id_705})




        # === Seed from 20251202_000003_backfill_document_monetization_accounting_documents.py ===
        # این بخش فقط برای backfill داده‌های قدیمی است و در migration جدید نیازی نیست
        # چون دیتابیس جدید است و داده‌های قدیمی وجود ندارد
        pass

def downgrade() -> None:
    # Seed data را نمی‌توانیم downgrade کنیم
    pass
