from __future__ import annotations

import httpx
import structlog
from typing import Optional, List
from urllib.parse import urlencode

from app.utils.phone_utils import normalize_phone_number

logger = structlog.get_logger()

# Mapping کدهای خطا
BEHINSMS_ERROR_CODES = {
	50: "موفقیت آمیز",
	51: "نام کاربری یا رمز عبور اشتباه است",
	52: "نام کاربری یا رمز عبور خالی است",
	53: "طول کلید RecipientNumber بیش از حد مجاز است (بیش از 1000 عدد است)",
	54: "کلید RecipientNumber خالی است",
	55: "کلید RecipientNumber نامعتبر است (مقدار آن Null است)",
	56: "طول آرایه MessageID بیش از حد مجاز است (بیش از 1000 عدد است)",
	57: "کلید MessageID خالی است",
	58: "کلید MessageID نامعتبر است (مقدار آن Null است)",
	59: "کلید MessageBody خالی است",
	60: "در حال حاضر به علت ترافیک بالا سرور توانایی پاسخ گویی ندارد",
	61: "کلید SpecialNumber نامعتبر است (شماره اختصاصی وارد شده وجود ندارد یا متعلق به این کاربر نمی باشد)",
	62: "کلید SpecialNumber خالی است",
	63: "این IP اجازه دسترسی به وب سرویس این کاربر را ندارد",
	65: "کلید NumberOfMessage اشتباه است (مقدار آن منفی است)",
	66: "طول کلید CheckingMessageID با طول کلید RecipientNumber برابر نیست",
	67: "طول آرایه CheckingMessageID بیش از حد مجاز است (بیش از 50 عدد است)",
	68: "کلید CheckingMessageID خالی است",
	69: "کلید CheckingMessageID نامعتبر است (مقدار آن Null است)",
	70: "کاربر غیر فعال شده است",
	72: "ترکیب پارامترهای زمان (ترکیب Hour و Minute) اشتباه است",
	73: "ترکیب پارامترهای تاریخ (ترکیب Year، Month و Day) اشتباه است",
	74: "طول کلید NumberGroupID بیش از حد مجاز است (بیش از 1000 عدد است)",
	75: "کلید NumberGroupID خالی است",
	76: "کلید NumberGroupID نامعتبر است (مقدار آن Null است)",
	77: "شما کاربر وب سرویس نیستید",
	78: "شما کاربر سامانه مدیریت ارسال و دریافت پیام کوتاه نیستید",
	79: "طول کلید PersonName با طول PersonNumber برابر نیست",
	80: "در حال حاضر وب سرویس توسط Admin غیر فعال شده است",
	81: "طول کلید PersonNumber بیش از حد مجاز است (بیش از 1000 عدد است)",
	82: "کلید PersonNumber خالی است",
	83: "کلید PersonNumber نامعتبر است (مقدار آن Null است)",
	84: "شماره گروه دفتر تلفن (NumberGroupID) نامعتبر است",
	201: "فرمت شماره RecipientNumber اشتباه است",
	202: "اپراتور مخابراتی شماره RecipientNumber برای سیستم ناشناخته است",
	203: "به علت کمبود اعتبار پیام کوتاه شما توانایی ارسال به این شماره را ندارید",
	204: "هیچ شناسه ای با مقدار CheckingMessageID در سیستم وجود ندارد",
	205: "فرمت شماره PersonNumber اشتباه است",
	206: "شماره اپراتور نامعتبر می باشد",
	207: "عنوان انگلیسی گروه دفتر تلفن نامعتبر است",
	300: "ارسال پیامک حاوی لینک مجاز نمی باشد",
	400: "تعداد درخواست های ارسالی از حد مجاز در یک فراخوانی سرویس یا بازه زمانی بیشتر است",
	666: "سرویس موقتاً غیر فعال است",
	777: "این IP مسدود است",
	888: "برای شماره فرستنده احراز هویت ثبت نشده است",
	999: "ارسال این پیامک مجاز نیست",
}


class BehinSmsProvider:
	"""
	Provider برای ارسال پیامک از طریق سرویس بهین اس ام اس
	
	مستندات API: راهنمای استفاده از سرویس HTTP-URL بهین اس ام اس
	"""
	BASE_URL = "https://panel.behinsms.com/smsws/HttpService.ashx"
	
	def __init__(self, username: str, password: str, sender: str):
		"""
		Args:
			username: نام کاربری بهین اس ام اس
			password: کلمه عبور بهین اس ام اس
			sender: شماره اختصاصی (فرستنده) - باید به صورت 3000xxxxxxx باشد
		"""
		if not username or not password or not sender:
			raise ValueError("username, password و sender الزامی هستند")
		
		self.username = username.strip()
		self.password = password.strip()
		# حذف 98+ یا 98 از ابتدای شماره فرستنده
		sender = sender.strip()
		if sender.startswith('98'):
			sender = sender[2:]
		elif sender.startswith('0098'):
			sender = sender[4:]
		self.sender = sender
	
	def _make_request(self, service: str, params: dict) -> tuple[bool, str, Optional[str]]:
		"""
		انجام درخواست HTTP به API بهین اس ام اس
		
		Returns:
			(success: bool, response_text: str, error_message: Optional[str])
		"""
		# اضافه کردن پارامترهای مشترک
		params['service'] = service
		params['username'] = self.username
		params['password'] = self.password
		
		try:
			# لاگ‌گذاری درخواست
			logger.info(
				"behinsms_make_request",
				service=service,
				url=self.BASE_URL,
				params_keys=list(params.keys()),
				recipient_number=params.get('to'),
				recipient_number_repr=repr(params.get('to'))
			)
			
			with httpx.Client(timeout=30.0) as client:
				response = client.get(self.BASE_URL, params=params)
				response.raise_for_status()
				response_text = response.text.strip()
				
				# لاگ‌گذاری پاسخ
				logger.info(
					"behinsms_response",
					service=service,
					status_code=response.status_code,
					response_text=response_text,
					request_url=str(response.request.url)
				)
				
				# Parse response
				return self._parse_response(response_text)
		except httpx.HTTPError as e:
			logger.error("behinsms_http_error", error=str(e), service=service, params=params)
			return False, "", f"خطا در ارتباط با سرور بهین اس ام اس: {str(e)}"
		except Exception as e:
			logger.error("behinsms_unexpected_error", error=str(e), service=service, params=params)
			return False, "", f"خطای غیرمنتظره: {str(e)}"
	
	def _parse_response(self, response_text: str) -> tuple[bool, str, Optional[str]]:
		"""
		Parse پاسخ API بهین اس ام اس
		
		Returns:
			(success: bool, message_id_or_code: str, error_message: Optional[str])
		"""
		try:
			# بررسی اینکه آیا چند MessageID با کاما جدا شده‌اند
			if ',' in response_text:
				parts = response_text.split(',')
				# بررسی اینکه همه عدد هستند
				if all(part.strip().isdigit() for part in parts):
					# همه MessageID هستند (موفقیت)
					return True, response_text, None
			
			# بررسی اینکه آیا یک عدد است
			result = int(response_text.strip())
			
			if result == 50:
				# موفقیت (فقط در InsertNumberInNumberGroup)
				return True, str(result), None
			elif result >= 1000:
				# MessageID موفق
				return True, str(result), None
			elif result in BEHINSMS_ERROR_CODES:
				# کد خطا
				error_msg = BEHINSMS_ERROR_CODES[result]
				return False, str(result), error_msg
			else:
				# وضعیت نامشخص
				return False, str(result), "وضعیت نامشخص از سرور"
		except ValueError:
			# پاسخ نامعتبر
			return False, response_text, "فرمت پاسخ نامعتبر از سرور"
	
	def send_text(
		self,
		to_phone: str | List[str],
		text: str,
		is_flash: bool = False,
		checking_message_id: Optional[str] = None
	) -> tuple[bool, Optional[str], Optional[str]]:
		"""
		ارسال پیامک به یک یا چند شماره (متد SendArray)
		
		Args:
			to_phone: شماره گیرنده (یک شماره یا لیست حداکثر 1000 شماره)
			text: متن پیامک
			is_flash: آیا ارسال به صورت Flash باشد
			checking_message_id: شناسه منحصر به فرد پیامک کاربر (اختیاری)
		
		Returns:
			(success: bool, message_id: Optional[str], error_message: Optional[str])
		"""
		if not text or not text.strip():
			return False, None, "متن پیامک خالی است"
		
		# نرمال‌سازی شماره‌ها
		if isinstance(to_phone, str):
			phone_numbers = [to_phone]
		else:
			phone_numbers = list(to_phone)
		
		if not phone_numbers:
			return False, None, "هیچ شماره گیرنده‌ای مشخص نشده است"
		
		if len(phone_numbers) > 1000:
			return False, None, "حداکثر 1000 شماره می‌تواند ارسال شود"
		
		try:
			# نرمال‌سازی شماره‌ها
			normalized_numbers = []
			for phone in phone_numbers:
				normalized = normalize_phone_number(phone)
				# API behinsms انتظار فرمت 09183282405 (با صفر اول) دارد
				# پس صفر اول را حذف نمی‌کنیم
				normalized_numbers.append(normalized)
			
			# حذف شماره‌های تکراری
			normalized_numbers = list(set(normalized_numbers))
			
			# تبدیل به رشته با کاما
			recipient_numbers_str = ','.join(normalized_numbers)
			
			# لاگ‌گذاری برای دیباگ
			logger.info(
				"behinsms_send_text_prepare",
				original_phones=phone_numbers,
				normalized_numbers=normalized_numbers,
				recipient_numbers_str=recipient_numbers_str,
				recipient_numbers_str_length=len(recipient_numbers_str),
				recipient_numbers_str_repr=repr(recipient_numbers_str)
			)
			
			# بررسی اینکه آیا رشته خالی است
			if not recipient_numbers_str or len(recipient_numbers_str.strip()) == 0:
				logger.error(
					"behinsms_empty_recipient_numbers",
					original_phones=phone_numbers,
					normalized_numbers=normalized_numbers
				)
				return False, None, "شماره گیرنده خالی است"
		except ValueError as e:
			logger.error("behinsms_normalize_error", error=str(e), phones=phone_numbers)
			return False, None, str(e)
		
		# آماده‌سازی پارامترها
		# استفاده از نام‌های استاندارد API behinsms (بر اساس مستندات: to, message, from)
		params = {
			'to': recipient_numbers_str,
			'message': text,
			'from': self.sender,
			'IsFlashMessage': 'true' if is_flash else 'false',
		}
		
		if checking_message_id:
			params['chkMessageId'] = checking_message_id
		
		# لاگ‌گذاری پارامترها قبل از ارسال
		logger.debug(
			"behinsms_send_text_params",
			recipient_number=params.get('to'),
			recipient_number_type=type(params.get('to')).__name__,
			recipient_number_length=len(params.get('to', '')),
			special_number=params.get('from'),
			message_body_length=len(params.get('message', ''))
		)
		
		# ارسال درخواست
		success, result, error_msg = self._make_request('SendArray', params)
		
		if success:
			# اگر چند MessageID برگردانده شده، اولین را برمی‌گردانیم
			if ',' in result:
				message_ids = result.split(',')
				return True, message_ids[0].strip(), None
			return True, result, None
		else:
			return False, None, error_msg or "خطا در ارسال پیامک"
	
	def get_credit(self) -> tuple[bool, Optional[float], Optional[str]]:
		"""
		دریافت اعتبار باقیمانده پیام کوتاه (متد GetCredit)
		
		Returns:
			(success: bool, credit_amount: Optional[float], error_message: Optional[str])
		"""
		params = {}
		success, result, error_msg = self._make_request('GetCredit', params)
		
		if success:
			try:
				credit = float(result)
				return True, credit, None
			except ValueError:
				return False, None, "فرمت اعتبار نامعتبر است"
		else:
			return False, None, error_msg or "خطا در دریافت اعتبار"
	
	def get_message_status(self, message_id: str) -> tuple[bool, Optional[int], Optional[str]]:
		"""
		دریافت وضعیت پیامک ارسال شده (متد GetMessageStatus)
		
		Args:
			message_id: شناسه پیامک (MessageID)
		
		Returns:
			(success: bool, status_code: Optional[int], error_message: Optional[str])
			
		Status Codes:
			0: شناسه پیامک نامعتبر است
			1: هنوز وضعیتی دریافت نشده است
			2: پیامک به موبایل گیرنده رسیده است
			3: پیامک به موبایل گیرنده نرسیده است
			4: پیامک به مرکز مخابراتی رسیده است
			5: پیامک به مرکز مخابراتی نرسیده است
			6: شماره موبایل در لیست غیر فعال قرار گرفته است
			7: پیامک در صف ارسال قرار دارد
			8: سرور در حال ارسال پیامک می‌باشد
			9: به علت کمبود اعتبار پیامک ارسال نشده است
			10: پیامک ارسال نشده است (اختلالات ارتباطی)
			11: پیامک هنوز توسط اپراتور تأیید نشده است
			12: پیامک در لیست کنسل شده یا فیلتر شده قرار دارد
		"""
		if not message_id or not message_id.strip():
			return False, None, "شناسه پیامک خالی است"
		
		params = {
			'MessageID': message_id.strip(),
		}
		
		success, result, error_msg = self._make_request('GetMessageStatus', params)
		
		if success:
			try:
				status_code = int(result)
				return True, status_code, None
			except ValueError:
				return False, None, "فرمت وضعیت نامعتبر است"
		else:
			return False, None, error_msg or "خطا در دریافت وضعیت پیامک"
	
	def send_bulk(
		self,
		recipient_numbers: List[str],
		text: str,
		is_flash: bool = False
	) -> tuple[bool, Optional[List[str]], Optional[str]]:
		"""
		ارسال پیامک به چند شماره (تا 1000 شماره)
		
		این متد در واقع یک wrapper برای send_text است که لیست MessageID را برمی‌گرداند
		
		Args:
			recipient_numbers: لیست شماره‌های گیرنده (حداکثر 1000)
			text: متن پیامک
			is_flash: آیا ارسال به صورت Flash باشد
		
		Returns:
			(success: bool, message_ids: Optional[List[str]], error_message: Optional[str])
		"""
		if len(recipient_numbers) > 1000:
			return False, None, "حداکثر 1000 شماره می‌تواند ارسال شود"
		
		success, message_id_str, error_msg = self.send_text(recipient_numbers, text, is_flash)
		
		if success:
			# اگر چند MessageID برگردانده شده، همه را برمی‌گردانیم
			if ',' in message_id_str:
				message_ids = [mid.strip() for mid in message_id_str.split(',')]
				return True, message_ids, None
			else:
				return True, [message_id_str], None
		else:
			return False, None, error_msg

