from __future__ import annotations

from alembic import op
import sqlalchemy as sa


"""
Replace accounts chart seed with the provided list (public accounts only)

Revision ID: 20251011_010001_replace_accounts_chart_seed
Revises: 20251006_000001_add_tax_types_table_and_product_fks
Create Date: 2025-10-11 01:00:01.000001
"""


# revision identifiers, used by Alembic.
revision = '20251011_010001_replace_accounts_chart_seed'
down_revision = '20251011_000901_add_checks_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()

    # لیست کامل از کاربر (فقط فیلدهای لازم برای جدول accounts نگه داشته شده)
    # نگاشت: id => extId (صرفاً برای حلقه والد/فرزند). در جدول id خودکار است
    items = [
        {"id": 2452, "level": 1, "code": "1", "name": "دارایی ها", "parentId": 0, "accountType": 0},
        {"id": 2453, "level": 2, "code": "101", "name": "دارایی های جاری", "parentId": 2452, "accountType": 0},
        {"id": 2454, "level": 3, "code": "102", "name": "موجودی نقد و بانک", "parentId": 2453, "accountType": 0},
        {"id": 2455, "level": 4, "code": "10201", "name": "تنخواه گردان", "parentId": 2454, "accountType": 2},
        {"id": 2456, "level": 4, "code": "10202", "name": "صندوق", "parentId": 2454, "accountType": 1},
        {"id": 2457, "level": 4, "code": "10203", "name": "بانک", "parentId": 2454, "accountType": 3},
        {"id": 2458, "level": 4, "code": "10204", "name": "وجوه در راه", "parentId": 2454, "accountType": 0},
        {"id": 2459, "level": 3, "code": "103", "name": "سپرده های کوتاه مدت", "parentId": 2453, "accountType": 0},
        {"id": 2460, "level": 4, "code": "10301", "name": "سپرده شرکت در مناقصه و مزایده", "parentId": 2459, "accountType": 0},
        {"id": 2461, "level": 4, "code": "10302", "name": "ضمانت نامه بانکی", "parentId": 2459, "accountType": 0},
        {"id": 2462, "level": 4, "code": "10303", "name": "سایر سپرده ها", "parentId": 2459, "accountType": 0},
        {"id": 2463, "level": 3, "code": "104", "name": "حساب های دریافتنی", "parentId": 2453, "accountType": 0},
        {"id": 2464, "level": 4, "code": "10401", "name": "حساب های دریافتنی", "parentId": 2463, "accountType": 4},
        {"id": 2465, "level": 4, "code": "10402", "name": "ذخیره مطالبات مشکوک الوصول", "parentId": 2463, "accountType": 0},
        {"id": 2466, "level": 4, "code": "10403", "name": "اسناد دریافتنی", "parentId": 2463, "accountType": 5},
        {"id": 2467, "level": 4, "code": "10404", "name": "اسناد در جریان وصول", "parentId": 2463, "accountType": 6},
        {"id": 2468, "level": 3, "code": "105", "name": "سایر حساب های دریافتنی", "parentId": 2453, "accountType": 0},
        {"id": 2469, "level": 4, "code": "10501", "name": "وام کارکنان", "parentId": 2468, "accountType": 0},
        {"id": 2470, "level": 4, "code": "10502", "name": "سایر حساب های دریافتنی", "parentId": 2468, "accountType": 0},
        {"id": 2471, "level": 3, "code": "10101", "name": "پیش پرداخت ها", "parentId": 2453, "accountType": 0},
        {"id": 2472, "level": 3, "code": "10102", "name": "موجودی کالا", "parentId": 2453, "accountType": 7},
        {"id": 2473, "level": 3, "code": "10103", "name": "ملزومات", "parentId": 2453, "accountType": 0},
        {"id": 2474, "level": 3, "code": "10104", "name": "مالیات بر ارزش افزوده خرید", "parentId": 2453, "accountType": 8},
        {"id": 2475, "level": 2, "code": "106", "name": "دارایی های غیر جاری", "parentId": 2452, "accountType": 0},
        {"id": 2476, "level": 3, "code": "107", "name": "دارایی های ثابت", "parentId": 2475, "accountType": 0},
        {"id": 2477, "level": 4, "code": "10701", "name": "زمین", "parentId": 2476, "accountType": 0},
        {"id": 2478, "level": 4, "code": "10702", "name": "ساختمان", "parentId": 2476, "accountType": 0},
        {"id": 2479, "level": 4, "code": "10703", "name": "وسائط نقلیه", "parentId": 2476, "accountType": 0},
        {"id": 2480, "level": 4, "code": "10704", "name": "اثاثیه اداری", "parentId": 2476, "accountType": 0},
        {"id": 2481, "level": 3, "code": "108", "name": "استهلاک انباشته", "parentId": 2475, "accountType": 0},
        {"id": 2482, "level": 4, "code": "10801", "name": "استهلاک انباشته ساختمان", "parentId": 2481, "accountType": 0},
        {"id": 2483, "level": 4, "code": "10802", "name": "استهلاک انباشته وسائط نقلیه", "parentId": 2481, "accountType": 0},
        {"id": 2484, "level": 4, "code": "10803", "name": "استهلاک انباشته اثاثیه اداری", "parentId": 2481, "accountType": 0},
        {"id": 2485, "level": 3, "code": "109", "name": "سپرده های بلندمدت", "parentId": 2475, "accountType": 0},
        {"id": 2486, "level": 3, "code": "110", "name": "سایر دارائی ها", "parentId": 2475, "accountType": 0},
        {"id": 2487, "level": 4, "code": "11001", "name": "حق الامتیازها", "parentId": 2486, "accountType": 0},
        {"id": 2488, "level": 4, "code": "11002", "name": "نرم افزارها", "parentId": 2486, "accountType": 0},
        {"id": 2489, "level": 4, "code": "11003", "name": "سایر دارایی های نامشهود", "parentId": 2486, "accountType": 0},
        {"id": 2490, "level": 1, "code": "2", "name": "بدهی ها", "parentId": 0, "accountType": 0},
        {"id": 2491, "level": 2, "code": "201", "name": "بدهیهای جاری", "parentId": 2490, "accountType": 0},
        {"id": 2492, "level": 3, "code": "202", "name": "حساب ها و اسناد پرداختنی", "parentId": 2491, "accountType": 0},
        {"id": 2493, "level": 4, "code": "20201", "name": "حساب های پرداختنی", "parentId": 2492, "accountType": 9},
        {"id": 2494, "level": 4, "code": "20202", "name": "اسناد پرداختنی", "parentId": 2492, "accountType": 10},
        {"id": 2495, "level": 3, "code": "203", "name": "سایر حساب های پرداختنی", "parentId": 2491, "accountType": 0},
        {"id": 2496, "level": 4, "code": "20301", "name": "ذخیره مالیات بر درآمد پرداختنی", "parentId": 2495, "accountType": 40},
        {"id": 2497, "level": 4, "code": "20302", "name": "مالیات بر درآمد پرداختنی", "parentId": 2495, "accountType": 12},
        {"id": 2498, "level": 4, "code": "20303", "name": "مالیات حقوق و دستمزد پرداختنی", "parentId": 2495, "accountType": 0},
        {"id": 2499, "level": 4, "code": "20304", "name": "حق بیمه پرداختنی", "parentId": 2495, "accountType": 0},
        {"id": 2500, "level": 4, "code": "20305", "name": "حقوق و دستمزد پرداختنی", "parentId": 2495, "accountType": 42},
        {"id": 2501, "level": 4, "code": "20306", "name": "عیدی و پاداش پرداختنی", "parentId": 2495, "accountType": 0},
        {"id": 2502, "level": 4, "code": "20307", "name": "سایر هزینه های پرداختنی", "parentId": 2495, "accountType": 0},
        {"id": 2503, "level": 3, "code": "204", "name": "پیش دریافت ها", "parentId": 2491, "accountType": 0},
        {"id": 2504, "level": 4, "code": "20401", "name": "پیش دریافت فروش", "parentId": 2503, "accountType": 0},
        {"id": 2505, "level": 4, "code": "20402", "name": "سایر پیش دریافت ها", "parentId": 2503, "accountType": 0},
        {"id": 2506, "level": 3, "code": "20101", "name": "مالیات بر ارزش افزوده فروش", "parentId": 2491, "accountType": 11},
        {"id": 2507, "level": 2, "code": "205", "name": "بدهیهای غیر جاری", "parentId": 2490, "accountType": 0},
        {"id": 2508, "level": 3, "code": "206", "name": "حساب ها و اسناد پرداختنی بلندمدت", "parentId": 2507, "accountType": 0},
        {"id": 2509, "level": 4, "code": "20601", "name": "حساب های پرداختنی بلندمدت", "parentId": 2508, "accountType": 0},
        {"id": 2510, "level": 4, "code": "20602", "name": "اسناد پرداختنی بلندمدت", "parentId": 2508, "accountType": 0},
        {"id": 2511, "level": 3, "code": "20501", "name": "وام پرداختنی", "parentId": 2507, "accountType": 0},
        {"id": 2512, "level": 3, "code": "20502", "name": "ذخیره مزایای پایان خدمت کارکنان", "parentId": 2507, "accountType": 0},
        {"id": 2513, "level": 1, "code": "3", "name": "حقوق صاحبان سهام", "parentId": 0, "accountType": 0},
        {"id": 2514, "level": 2, "code": "301", "name": "سرمایه", "parentId": 2513, "accountType": 0},
        {"id": 2515, "level": 3, "code": "30101", "name": "سرمایه اولیه", "parentId": 2514, "accountType": 13},
        {"id": 2516, "level": 3, "code": "30102", "name": "افزایش یا کاهش سرمایه", "parentId": 2514, "accountType": 14},
        {"id": 2517, "level": 3, "code": "30103", "name": "اندوخته قانونی", "parentId": 2514, "accountType": 15},
        {"id": 2518, "level": 3, "code": "30104", "name": "برداشت ها", "parentId": 2514, "accountType": 16},
        {"id": 2519, "level": 3, "code": "30105", "name": "سهم سود و زیان", "parentId": 2514, "accountType": 17},
        {"id": 2520, "level": 3, "code": "30106", "name": "سود یا زیان انباشته (سنواتی)", "parentId": 2514, "accountType": 18},
        {"id": 2521, "level": 1, "code": "4", "name": "بهای تمام شده کالای فروخته شده", "parentId": 0, "accountType": 0},
        {"id": 2522, "level": 2, "code": "40001", "name": "بهای تمام شده کالای فروخته شده", "parentId": 2521, "accountType": 19},
        {"id": 2523, "level": 2, "code": "40002", "name": "برگشت از خرید", "parentId": 2521, "accountType": 20},
        {"id": 2524, "level": 2, "code": "40003", "name": "تخفیفات نقدی خرید", "parentId": 2521, "accountType": 21},
        {"id": 2525, "level": 1, "code": "5", "name": "فروش", "parentId": 0, "accountType": 0},
        {"id": 2526, "level": 2, "code": "50001", "name": "فروش کالا", "parentId": 2525, "accountType": 22},
        {"id": 2527, "level": 2, "code": "50002", "name": "برگشت از فروش", "parentId": 2525, "accountType": 23},
        {"id": 2528, "level": 2, "code": "50003", "name": "تخفیفات نقدی فروش", "parentId": 2525, "accountType": 24},
        {"id": 2529, "level": 1, "code": "6", "name": "درآمد", "parentId": 0, "accountType": 0},
        {"id": 2530, "level": 2, "code": "601", "name": "درآمد های عملیاتی", "parentId": 2529, "accountType": 0},
        {"id": 2531, "level": 3, "code": "60101", "name": "درآمد حاصل از فروش خدمات", "parentId": 2530, "accountType": 25},
        {"id": 2532, "level": 3, "code": "60102", "name": "برگشت از خرید خدمات", "parentId": 2530, "accountType": 26},
        {"id": 2533, "level": 3, "code": "60103", "name": "درآمد اضافه کالا", "parentId": 2530, "accountType": 27},
        {"id": 2534, "level": 3, "code": "60104", "name": "درآمد حمل کالا", "parentId": 2530, "accountType": 28},
        {"id": 2535, "level": 2, "code": "602", "name": "درآمد های غیر عملیاتی", "parentId": 2529, "accountType": 0},
        {"id": 2536, "level": 3, "code": "60201", "name": "درآمد حاصل از سرمایه گذاری", "parentId": 2535, "accountType": 0},
        {"id": 2537, "level": 3, "code": "60202", "name": "درآمد سود سپرده ها", "parentId": 2535, "accountType": 0},
        {"id": 2538, "level": 3, "code": "60203", "name": "سایر درآمد ها", "parentId": 2535, "accountType": 0},
        {"id": 2539, "level": 3, "code": "60204", "name": "درآمد تسعیر ارز", "parentId": 2535, "accountType": 36},
        {"id": 2540, "level": 1, "code": "7", "name": "هزینه ها", "parentId": 0, "accountType": 0},
        {"id": 2541, "level": 2, "code": "701", "name": "هزینه های پرسنلی", "parentId": 2540, "accountType": 0},
        {"id": 2542, "level": 3, "code": "702", "name": "هزینه حقوق و دستمزد", "parentId": 2541, "accountType": 0},
        {"id": 2543, "level": 4, "code": "70201", "name": "حقوق پایه", "parentId": 2542, "accountType": 0},
        {"id": 2544, "level": 4, "code": "70202", "name": "اضافه کار", "parentId": 2542, "accountType": 0},
        {"id": 2545, "level": 4, "code": "70203", "name": "حق شیفت و شب کاری", "parentId": 2542, "accountType": 0},
        {"id": 2546, "level": 4, "code": "70204", "name": "حق نوبت کاری", "parentId": 2542, "accountType": 0},
        {"id": 2547, "level": 4, "code": "70205", "name": "حق ماموریت", "parentId": 2542, "accountType": 0},
        {"id": 2548, "level": 4, "code": "70206", "name": "فوق العاده مسکن و خاروبار", "parentId": 2542, "accountType": 0},
        {"id": 2549, "level": 4, "code": "70207", "name": "حق اولاد", "parentId": 2542, "accountType": 0},
        {"id": 2550, "level": 4, "code": "70208", "name": "عیدی و پاداش", "parentId": 2542, "accountType": 0},
        {"id": 2551, "level": 4, "code": "70209", "name": "بازخرید سنوات خدمت کارکنان", "parentId": 2542, "accountType": 0},
        {"id": 2552, "level": 4, "code": "70210", "name": "بازخرید مرخصی", "parentId": 2542, "accountType": 0},
        {"id": 2553, "level": 4, "code": "70211", "name": "بیمه سهم کارفرما", "parentId": 2542, "accountType": 0},
        {"id": 2554, "level": 4, "code": "70212", "name": "بیمه بیکاری", "parentId": 2542, "accountType": 0},
        {"id": 2555, "level": 4, "code": "70213", "name": "حقوق مزایای متفرقه", "parentId": 2542, "accountType": 0},
        {"id": 2556, "level": 3, "code": "703", "name": "سایر هزینه های کارکنان", "parentId": 2541, "accountType": 0},
        {"id": 2557, "level": 4, "code": "70301", "name": "سفر و ماموریت", "parentId": 2556, "accountType": 0},
        {"id": 2558, "level": 4, "code": "70302", "name": "ایاب و ذهاب", "parentId": 2556, "accountType": 0},
        {"id": 2559, "level": 4, "code": "70303", "name": "سایر هزینه های کارکنان", "parentId": 2556, "accountType": 0},
        {"id": 2560, "level": 2, "code": "704", "name": "هزینه های عملیاتی", "parentId": 2540, "accountType": 0},
        {"id": 2561, "level": 3, "code": "70401", "name": "خرید خدمات", "parentId": 2560, "accountType": 30},
        {"id": 2562, "level": 3, "code": "70402", "name": "برگشت از فروش خدمات", "parentId": 2560, "accountType": 29},
        {"id": 2563, "level": 3, "code": "70403", "name": "هزینه حمل کالا", "parentId": 2560, "accountType": 31},
        {"id": 2564, "level": 3, "code": "70404", "name": "تعمیر و نگهداری اموال و اثاثیه", "parentId": 2560, "accountType": 0},
        {"id": 2565, "level": 3, "code": "70405", "name": "هزینه اجاره محل", "parentId": 2560, "accountType": 0},
        {"id": 2566, "level": 3, "code": "705", "name": "هزینه های عمومی", "parentId": 2560, "accountType": 0},
        {"id": 2567, "level": 4, "code": "70501", "name": "هزینه آب و برق و گاز و تلفن", "parentId": 2566, "accountType": 0},
        {"id": 2568, "level": 4, "code": "70502", "name": "هزینه پذیرایی و آبدارخانه", "parentId": 2566, "accountType": 0},
        {"id": 2569, "level": 3, "code": "70406", "name": "هزینه ملزومات مصرفی", "parentId": 2560, "accountType": 0},
        {"id": 2570, "level": 3, "code": "70407", "name": "هزینه کسری و ضایعات کالا", "parentId": 2560, "accountType": 32},
        {"id": 2571, "level": 3, "code": "70408", "name": "بیمه دارایی های ثابت", "parentId": 2560, "accountType": 0},
        {"id": 2572, "level": 2, "code": "706", "name": "هزینه های استهلاک", "parentId": 2540, "accountType": 0},
        {"id": 2573, "level": 3, "code": "70601", "name": "هزینه استهلاک ساختمان", "parentId": 2572, "accountType": 0},
        {"id": 2574, "level": 3, "code": "70602", "name": "هزینه استهلاک وسائط نقلیه", "parentId": 2572, "accountType": 0},
        {"id": 2575, "level": 3, "code": "70603", "name": "هزینه استهلاک اثاثیه", "parentId": 2572, "accountType": 0},
        {"id": 2576, "level": 2, "code": "707", "name": "هزینه های بازاریابی و توزیع و فروش", "parentId": 2540, "accountType": 0},
        {"id": 2577, "level": 3, "code": "70701", "name": "هزینه آگهی و تبلیغات", "parentId": 2576, "accountType": 0},
        {"id": 2578, "level": 3, "code": "70702", "name": "هزینه بازاریابی و پورسانت", "parentId": 2576, "accountType": 0},
        {"id": 2579, "level": 3, "code": "70703", "name": "سایر هزینه های توزیع و فروش", "parentId": 2576, "accountType": 0},
        {"id": 2580, "level": 2, "code": "708", "name": "هزینه های غیرعملیاتی", "parentId": 2540, "accountType": 0},
        {"id": 2581, "level": 3, "code": "709", "name": "هزینه های بانکی", "parentId": 2580, "accountType": 0},
        {"id": 2582, "level": 4, "code": "70901", "name": "سود و کارمزد وامها", "parentId": 2581, "accountType": 0},
        {"id": 2583, "level": 4, "code": "70902", "name": "کارمزد خدمات بانکی", "parentId": 2581, "accountType": 33},
        {"id": 2584, "level": 4, "code": "70903", "name": "جرائم دیرکرد بانکی", "parentId": 2581, "accountType": 0},
        {"id": 2585, "level": 3, "code": "70801", "name": "هزینه تسعیر ارز", "parentId": 2580, "accountType": 37},
        {"id": 2586, "level": 3, "code": "70802", "name": "هزینه مطالبات سوخت شده", "parentId": 2580, "accountType": 0},
        {"id": 2587, "level": 1, "code": "8", "name": "سایر حساب ها", "parentId": 0, "accountType": 0},
        {"id": 2588, "level": 2, "code": "801", "name": "حساب های انتظامی", "parentId": 2587, "accountType": 0},
        {"id": 2589, "level": 3, "code": "80101", "name": "حساب های انتظامی", "parentId": 2588, "accountType": 0},
        {"id": 2590, "level": 3, "code": "80102", "name": "طرف حساب های انتظامی", "parentId": 2588, "accountType": 0},
        {"id": 2591, "level": 2, "code": "802", "name": "حساب های کنترلی", "parentId": 2587, "accountType": 0},
        {"id": 2592, "level": 3, "code": "80201", "name": "کنترل کسری و اضافه کالا", "parentId": 2591, "accountType": 34},
        {"id": 2593, "level": 2, "code": "803", "name": "حساب خلاصه سود و زیان", "parentId": 2587, "accountType": 0},
        {"id": 2594, "level": 3, "code": "80301", "name": "خلاصه سود و زیان", "parentId": 2593, "accountType": 35},
        {"id": 2595, "level": 5, "code": "70503", "name": "هزینه آب", "parentId": 2567, "accountType": 0},
        {"id": 2596, "level": 5, "code": "70504", "name": "هزینه برق", "parentId": 2567, "accountType": 0},
        {"id": 2597, "level": 5, "code": "70505", "name": "هزینه گاز", "parentId": 2567, "accountType": 0},
        {"id": 2598, "level": 5, "code": "70506", "name": "هزینه تلفن", "parentId": 2567, "accountType": 0},
        {"id": 2600, "level": 4, "code": "20503", "name": "وام از بانک ملت", "parentId": 2511, "accountType": 0},
        {"id": 2601, "level": 4, "code": "10405", "name": "سود تحقق نیافته فروش اقساطی", "parentId": 2463, "accountType": 39},
        {"id": 2602, "level": 3, "code": "60205", "name": "سود فروش اقساطی", "parentId": 2535, "accountType": 38},
        {"id": 2603, "level": 4, "code": "70214", "name": "حق تاهل", "parentId": 2542, "accountType": 0},
        {"id": 2604, "level": 4, "code": "20504", "name": "وام از بانک پارسیان", "parentId": 2511, "accountType": 0},
        {"id": 2605, "level": 3, "code": "10105", "name": "مساعده", "parentId": 2453, "accountType": 0},
        {"id": 2606, "level": 3, "code": "60105", "name": "تعمیرات لوازم آشپزخانه", "parentId": 2530, "accountType": 0},
        {"id": 2607, "level": 4, "code": "10705", "name": "کامپیوتر", "parentId": 2476, "accountType": 0},
        {"id": 2608, "level": 3, "code": "60206", "name": "درامد حاصل از فروش ضایعات", "parentId": 2535, "accountType": 0},
        {"id": 2609, "level": 3, "code": "60207", "name": "سود فروش دارایی", "parentId": 2535, "accountType": 0},
        {"id": 2610, "level": 3, "code": "70803", "name": "زیان فروش دارایی", "parentId": 2580, "accountType": 0},
        {"id": 2611, "level": 3, "code": "10106", "name": "موجودی کالای در جریان ساخت", "parentId": 2453, "accountType": 41},
        {"id": 2612, "level": 3, "code": "20102", "name": "سربار تولید پرداختنی", "parentId": 2491, "accountType": 43},
        {"id": 2613, "level": 4, "code": "70507", "name": "هزینه جدید", "parentId": 2566, "accountType": 0},
    ]

    # ۱) حذف حساب‌های عمومی موجود که در لیست جدید نیستند
    existing_codes = set(r[0] for r in conn.execute(sa.text("SELECT code FROM accounts WHERE business_id IS NULL")).fetchall())
    new_codes = {row["code"] for row in items}
    to_delete = tuple(sorted(existing_codes - new_codes))
    if to_delete:
        # حذف امن بر اساس کد و فقط عمومی
        del_sql = sa.text("DELETE FROM accounts WHERE business_id IS NULL AND code = :code")
        for c in to_delete:
            conn.execute(del_sql, {"code": c})

    # ۲) درج/به‌روزرسانی حساب‌ها به‌همراه نگاشت والدین
    ext_to_internal: dict[int, int] = {}
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

    for item in items:
        parent_internal = None
        if item.get("parentId") and item["parentId"] in ext_to_internal:
            parent_internal = ext_to_internal[item["parentId"]]

        res = conn.execute(select_existing, {"code": item["code"]})
        row = res.fetchone()
        if row is None:
            result = conn.execute(
                insert_q,
                {
                    "name": item["name"],
                    "account_type": str(item.get("accountType", 0)),
                    "code": item["code"],
                    "parent_id": parent_internal,
                },
            )
            new_id = result.lastrowid if hasattr(result, "lastrowid") else None
            if new_id is None:
                # fallback: انتخاب مجدد بر اساس code
                res2 = conn.execute(select_existing, {"code": item["code"]})
                row2 = res2.fetchone()
                if row2:
                    new_id = row2[0]
            if new_id is not None:
                ext_to_internal[item["id"]] = int(new_id)
        else:
            acc_id = int(row[0])
            conn.execute(
                update_q,
                {
                    "id": acc_id,
                    "name": item["name"],
                    "account_type": str(item.get("accountType", 0)),
                    "parent_id": parent_internal,
                },
            )
            ext_to_internal[item["id"]] = acc_id


def downgrade() -> None:
    # در downgrade صرفاً کدهایی که در این میگریشن اضافه/بروز شده‌اند حذف می‌شوند
    conn = op.get_bind()
    codes = [
        "1","101","102","10201","10202","10203","10204","103","10301","10302","10303","104","10401","10402","10403","10404","105","10501","10502","10101","10102","10103","10104","106","107","10701","10702","10703","10704","108","10801","10802","10803","109","110","11001","11002","11003","2","201","202","20201","20202","203","20301","20302","20303","20304","20305","20306","20307","204","20401","20402","20101","205","206","20601","20602","20501","20502","3","301","30101","30102","30103","30104","30105","30106","4","40001","40002","40003","5","50001","50002","50003","6","601","60101","60102","60103","60104","602","60201","60202","60203","60204","7","701","702","70201","70202","70203","70204","70205","70206","70207","70208","70209","70210","70211","70212","70213","703","70301","70302","70303","704","70401","70402","70403","70404","70405","705","70501","70502","70406","70407","70408","706","70601","70602","70603","707","70701","70702","70703","708","709","70901","70902","70903","70801","70802","8","801","80101","80102","802","80201","803","80301","70503","70504","70505","70506","20503","10405","60205","70214","20504","10105","60105","10705","60206","60207","70803","10106","20102","70507"
    ]
    delete_q = sa.text("DELETE FROM accounts WHERE business_id IS NULL AND code = :code")
    for code in codes:
        conn.execute(delete_q, {"code": code})


