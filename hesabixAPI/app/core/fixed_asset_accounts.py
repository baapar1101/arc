"""کدهای عمومی دفتر کل برای افزونه اموال.

برگ‌های 10701–10704 در نگاشت هلو و تست ترازنامه استفاده می‌شوند.
برگ‌های استهلاک انباشته و هزینه در میگریشن افزونه، فقط اگر والد 108 و 704 موجود باشد، ساخته می‌شوند.
فاز ۲: 60206 سود واگذاری و 70804 زیان واگذاری اگر والد 602 و 708 موجود باشند؛ 70404 تعمیر اگر نباشد ساخته می‌شود.
مالیات خروجی فروش دارایی همان 20101 فاکتور فروش است و ساخته نمی‌شود.
"""
from __future__ import annotations

COST_LAND = "10701"
COST_BUILDING = "10702"
COST_VEHICLE = "10703"
COST_FURNITURE = "10704"

ACCUM_BUILDING = "10802"
ACCUM_VEHICLE = "10803"
ACCUM_FURNITURE = "10804"

EXPENSE_BUILDING = "70409"
EXPENSE_VEHICLE = "70410"
EXPENSE_FURNITURE = "70411"

PARENT_COST = "107"
PARENT_ACCUM = "108"
PARENT_EXPENSE = "704"

VAT_INPUT = "10104"
VAT_OUTPUT = "20101"
BANK = "10203"
CASH = "10202"
PETTY_CASH = "10201"
ACCOUNTS_PAYABLE = "20201"

GAIN_DISPOSAL = "60206"
LOSS_DISPOSAL = "70804"
REPAIR_EXPENSE = "70404"
PARENT_GAIN = "602"
PARENT_LOSS = "708"

SYSTEM_CLASSES = (
	{
		"code": "land",
		"name": "زمین",
		"depreciable": False,
		"cost_account_code": COST_LAND,
		"accum_dep_account_code": None,
		"dep_expense_account_code": None,
		"default_method": "straight_line",
		"sort_order": 1,
	},
	{
		"code": "building",
		"name": "ساختمان",
		"depreciable": True,
		"cost_account_code": COST_BUILDING,
		"accum_dep_account_code": ACCUM_BUILDING,
		"dep_expense_account_code": EXPENSE_BUILDING,
		"default_method": "straight_line",
		"sort_order": 2,
	},
	{
		"code": "vehicle",
		"name": "وسایل نقلیه",
		"depreciable": True,
		"cost_account_code": COST_VEHICLE,
		"accum_dep_account_code": ACCUM_VEHICLE,
		"dep_expense_account_code": EXPENSE_VEHICLE,
		"default_method": "straight_line",
		"sort_order": 3,
	},
	{
		"code": "furniture",
		"name": "اثاثیه",
		"depreciable": True,
		"cost_account_code": COST_FURNITURE,
		"accum_dep_account_code": ACCUM_FURNITURE,
		"dep_expense_account_code": EXPENSE_FURNITURE,
		"default_method": "straight_line",
		"sort_order": 4,
	},
)

COA_LEAVES = (
	(COST_LAND, "زمین", PARENT_COST),
	(COST_BUILDING, "ساختمان", PARENT_COST),
	(COST_VEHICLE, "وسایل نقلیه", PARENT_COST),
	(COST_FURNITURE, "اثاثیه", PARENT_COST),
	(ACCUM_BUILDING, "استهلاک انباشته ساختمان", PARENT_ACCUM),
	(ACCUM_VEHICLE, "استهلاک انباشته وسایل نقلیه", PARENT_ACCUM),
	(ACCUM_FURNITURE, "استهلاک انباشته اثاثیه", PARENT_ACCUM),
	(EXPENSE_BUILDING, "هزینه استهلاک ساختمان", PARENT_EXPENSE),
	(EXPENSE_VEHICLE, "هزینه استهلاک وسایل نقلیه", PARENT_EXPENSE),
	(EXPENSE_FURNITURE, "هزینه استهلاک اثاثیه", PARENT_EXPENSE),
	(GAIN_DISPOSAL, "سود واگذاری دارایی ثابت", PARENT_GAIN),
	(LOSS_DISPOSAL, "زیان واگذاری دارایی ثابت", PARENT_LOSS),
	(REPAIR_EXPENSE, "تعمیر و نگهداری", PARENT_EXPENSE),
)
