from __future__ import annotations

import httpx
import structlog
from typing import List, Optional

from app.services.providers.behin_sms_provider import BEHINSMS_ERROR_CODES
from app.utils.phone_utils import normalize_phone_number

logger = structlog.get_logger()


class SunwaySmsProvider:
	"""
	Provider برای ارسال پیامک از طریق سرویس سان‌وی اس‌ام‌اس (Sunway SMS)

	مستندات API: سرویس HTTP-URL پنل sms.sunwaysms.com
	"""

	BASE_URL = "https://sms.sunwaysms.com/smsws/HttpService.ashx"

	def __init__(self, username: str, password: str, sender: str):
		if not username or not password or not sender:
			raise ValueError("username, password و sender الزامی هستند")

		self.username = username.strip()
		self.password = password.strip()
		sender = sender.strip()
		if sender.startswith("98"):
			sender = sender[2:]
		elif sender.startswith("0098"):
			sender = sender[4:]
		self.sender = sender

	def _make_request(self, service: str, params: dict) -> tuple[bool, str, Optional[str]]:
		params["service"] = service
		params["UserName"] = self.username
		params["Password"] = self.password

		try:
			logger.info(
				"sunwaysms_make_request",
				service=service,
				url=self.BASE_URL,
				params_keys=list(params.keys()),
				recipient_number=params.get("To"),
			)

			with httpx.Client(timeout=30.0) as client:
				response = client.get(self.BASE_URL, params=params)
				response.raise_for_status()
				response_text = response.text.strip()

				logger.info(
					"sunwaysms_response",
					service=service,
					status_code=response.status_code,
					response_text=response_text,
					request_url=str(response.request.url),
				)

				return self._parse_response(response_text)
		except httpx.HTTPError as e:
			logger.error("sunwaysms_http_error", error=str(e), service=service, params=params)
			return False, "", f"خطا در ارتباط با سرور سان‌وی اس‌ام‌اس: {str(e)}"
		except Exception as e:
			logger.error("sunwaysms_unexpected_error", error=str(e), service=service, params=params)
			return False, "", f"خطای غیرمنتظره: {str(e)}"

	def _parse_response(self, response_text: str) -> tuple[bool, str, Optional[str]]:
		try:
			if "," in response_text:
				parts = response_text.split(",")
				if all(part.strip().isdigit() for part in parts):
					return True, response_text, None

			result = int(response_text.strip())

			if result == 50:
				return True, str(result), None
			if result >= 1000:
				return True, str(result), None
			if result in BEHINSMS_ERROR_CODES:
				return False, str(result), BEHINSMS_ERROR_CODES[result]
			return False, str(result), "وضعیت نامشخص از سرور"
		except ValueError:
			return False, response_text, "فرمت پاسخ نامعتبر از سرور"

	def send_text(
		self,
		to_phone: str | List[str],
		text: str,
		is_flash: bool = False,
		checking_message_id: Optional[str] = None,
	) -> tuple[bool, Optional[str], Optional[str]]:
		if not text or not text.strip():
			return False, None, "متن پیامک خالی است"

		if isinstance(to_phone, str):
			phone_numbers = [to_phone]
		else:
			phone_numbers = list(to_phone)

		if not phone_numbers:
			return False, None, "هیچ شماره گیرنده‌ای مشخص نشده است"

		if len(phone_numbers) > 1000:
			return False, None, "حداکثر 1000 شماره می‌تواند ارسال شود"

		try:
			normalized_numbers = []
			for phone in phone_numbers:
				normalized_numbers.append(normalize_phone_number(phone))
			normalized_numbers = list(set(normalized_numbers))
			recipient_numbers_str = ",".join(normalized_numbers)

			if not recipient_numbers_str.strip():
				return False, None, "شماره گیرنده خالی است"
		except ValueError as e:
			logger.error("sunwaysms_normalize_error", error=str(e), phones=phone_numbers)
			return False, None, str(e)

		params = {
			"To": recipient_numbers_str,
			"Message": text,
			"From": self.sender,
			"Flash": "true" if is_flash else "false",
		}

		if checking_message_id:
			params["chkMessageId"] = checking_message_id

		success, result, error_msg = self._make_request("SendArray", params)

		if success:
			if "," in result:
				message_ids = result.split(",")
				return True, message_ids[0].strip(), None
			return True, result, None
		return False, None, error_msg or "خطا در ارسال پیامک"

	def get_credit(self) -> tuple[bool, Optional[float], Optional[str]]:
		success, result, error_msg = self._make_request("GetCredit", {})

		if success:
			try:
				return True, float(result), None
			except ValueError:
				return False, None, "فرمت اعتبار نامعتبر است"
		return False, None, error_msg or "خطا در دریافت اعتبار"

	def get_message_status(self, message_id: str) -> tuple[bool, Optional[int], Optional[str]]:
		if not message_id or not message_id.strip():
			return False, None, "شناسه پیامک خالی است"

		success, result, error_msg = self._make_request("GetMessageStatus", {"MessageID": message_id.strip()})

		if success:
			try:
				return True, int(result), None
			except ValueError:
				return False, None, "فرمت وضعیت نامعتبر است"
		return False, None, error_msg or "خطا در دریافت وضعیت پیامک"
