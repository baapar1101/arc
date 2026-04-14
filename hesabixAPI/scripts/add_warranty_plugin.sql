-- میگریشن افزودن افزونه گارانتی کالا
-- این اسکریپت افزونه "گارانتی کالا" را به بازار افزونه‌ها اضافه می‌کند

-- پیدا کردن اولین ارز (معمولاً IRR)
SET @currency_id = (SELECT id FROM currencies ORDER BY id ASC LIMIT 1);

-- بررسی اینکه آیا افزونه از قبل وجود دارد
SET @plugin_exists = (SELECT COUNT(*) FROM marketplace_plugins WHERE code = 'product_warranty');

-- اگر افزونه وجود ندارد، آن را ایجاد کن
INSERT INTO marketplace_plugins (
    code, name, description, category, icon_url, is_active, created_at, updated_at
)
SELECT 
    'product_warranty',
    'گارانتی کالا',
    'افزونه مدیریت گارانتی کالا - امکان ثبت و پیگیری گارانتی محصولات فروخته شده',
    'product_management',
    NULL,
    1,
    NOW(),
    NOW()
WHERE @plugin_exists = 0;

-- اگر افزونه از قبل وجود دارد، فقط اطمینان حاصل می‌کنیم که فعال است
UPDATE marketplace_plugins
SET is_active = 1,
    updated_at = NOW()
WHERE code = 'product_warranty' AND @plugin_exists > 0;

-- دریافت ID افزونه
SET @plugin_id = (SELECT id FROM marketplace_plugins WHERE code = 'product_warranty' LIMIT 1);

-- بررسی و ایجاد پلن ماهانه
INSERT INTO marketplace_plugin_plans (
    plugin_id, period, price, currency_id, is_active, created_at, updated_at
)
SELECT 
    @plugin_id,
    'monthly',
    100000,
    @currency_id,
    1,
    NOW(),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace_plugin_plans 
    WHERE plugin_id = @plugin_id AND period = 'monthly'
);

-- بررسی و ایجاد پلن سالانه
INSERT INTO marketplace_plugin_plans (
    plugin_id, period, price, currency_id, is_active, created_at, updated_at
)
SELECT 
    @plugin_id,
    'yearly',
    1000000,
    @currency_id,
    1,
    NOW(),
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace_plugin_plans 
    WHERE plugin_id = @plugin_id AND period = 'yearly'
);

-- نمایش نتیجه
SELECT 
    'افزونه گارانتی کالا با موفقیت اضافه شد' AS message,
    @plugin_id AS plugin_id,
    (SELECT COUNT(*) FROM marketplace_plugin_plans WHERE plugin_id = @plugin_id) AS plans_count;

