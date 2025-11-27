from __future__ import annotations

import re
from typing import Optional


def normalize_phone_number(phone: str) -> str:
	"""
	نرمال‌سازی شماره تلفن به فرمت استاندارد بهین اس ام اس
	
	فرمت خروجی: 0912xxxxxxx (یازده کاراکتر با شروع 09)
	
	Args:
		phone: شماره تلفن در هر فرمت
	
	Returns:
		شماره تلفن نرمال‌سازی شده
	
	Raises:
		ValueError: اگر فرمت شماره نامعتبر باشد
	"""
	if not phone:
		raise ValueError("شماره تلفن خالی است")
	
	# حذف فاصله، خط تیره، پرانتز و سایر کاراکترهای غیرعددی
	phone = re.sub(r'[\s\-\(\)\.]', '', phone.strip())
	
	# حذف + و 00 از ابتدا
	if phone.startswith('+98'):
		phone = '0' + phone[3:]
	elif phone.startswith('0098'):
		phone = '0' + phone[4:]
	elif phone.startswith('98'):
		phone = '0' + phone[2:]
	
	# اطمینان از شروع با 0
	if not phone.startswith('0'):
		phone = '0' + phone
	
	# بررسی طول (باید 11 رقم باشد)
	if len(phone) != 11:
		raise ValueError(f"طول شماره تلفن نامعتبر: {len(phone)} رقم (باید 11 رقم باشد)")
	
	# بررسی شروع با 09
	if not phone.startswith('09'):
		raise ValueError(f"شماره تلفن باید با 09 شروع شود: {phone}")
	
	# بررسی اینکه فقط عدد باشد
	if not phone.isdigit():
		raise ValueError(f"شماره تلفن باید فقط شامل اعداد باشد: {phone}")
	
	return phone


def format_phone_for_behinsms(phone: str) -> str:
	"""
	فرمت‌سازی شماره برای ارسال به بهین اس ام اس
	
	این تابع فقط شماره را normalize می‌کند و همان را برمی‌گرداند
	چون بهین اس ام اس فرمت 0912xxxxxxx را می‌پذیرد
	
	Args:
		phone: شماره تلفن
	
	Returns:
		شماره فرمت شده برای بهین اس ام اس
	"""
	return normalize_phone_number(phone)


def validate_iranian_mobile(phone: str) -> bool:
	"""
	اعتبارسنجی شماره موبایل ایرانی
	
	Args:
		phone: شماره موبایل
	
	Returns:
		True اگر شماره معتبر باشد
	"""
	try:
		normalized = normalize_phone_number(phone)
		# بررسی اینکه با یکی از پیش‌شماره‌های معتبر موبایل شروع شود
		valid_prefixes = ['0910', '0911', '0912', '0913', '0914', '0915', '0916', '0917', '0918', '0919',
		                  '0920', '0921', '0922', '0923', '0930', '0931', '0932', '0933', '0934', '0935',
		                  '0936', '0937', '0938', '0939', '0940', '0941', '0942', '0943', '0950', '0951',
		                  '0952', '0953', '0954', '0955', '0960', '0961', '0962', '0963', '0964', '0970',
		                  '0971', '0972', '0973', '0980', '0981', '0982', '0983', '0990', '0991', '0992',
		                  '0993', '0994']
		return any(normalized.startswith(prefix) for prefix in valid_prefixes)
	except ValueError:
		return False

