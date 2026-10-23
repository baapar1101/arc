"""Payam-Resan UAPI v4. Never retry Send automatically: a timeout is ambiguous."""
from __future__ import annotations
from typing import Optional
from uuid import uuid4
import httpx
from app.utils.phone_utils import normalize_phone_number


class PayamResanSmsProvider:
    BASE_URL = 'https://www.payam-resan.com/uapi/v4/Send'

    def __init__(self, api_key: str, sender: str, *, transport=None):
        if not api_key.strip() or not sender.strip().isdigit():
            raise ValueError('کلید و شماره فرستنده پیام‌رسان الزامی است.')
        self.api_key, self.sender = api_key.strip(), int(sender.strip())
        self.transport = transport

    def send_text(self, to_phone: str, text: str, is_flash: bool = False, checking_message_id: Optional[str] = None):
        try:
            phone = normalize_phone_number(to_phone)
        except ValueError:
            return False, None, 'شماره گیرنده پیام‌رسان معتبر نیست.'
        if not text or not text.strip():
            return False, None, 'متن پیامک خالی است.'
        trace = checking_message_id or uuid4().hex
        payload = {'ApiKey': self.api_key, 'Sender': self.sender, 'Text': text,
                   'Recipients': [{'Destination': int(phone), 'UserTraceId': trace}]}
        try:
            with httpx.Client(timeout=25, transport=self.transport, follow_redirects=False) as client:
                response = client.post(self.BASE_URL, json=payload)
            if not response.is_success:
                return False, None, f'خطای HTTP {response.status_code} از پیام‌رسان؛ پاسخ یا کلید در لاگ ذخیره نمی‌شود.'
            data = response.json()
            if not isinstance(data, dict):
                return False, None, 'پاسخ نامعتبر از پیام‌رسان.'
            accepted = data.get('success', data.get('Success'))
            if accepted is not True:
                code = data.get('errorCode', data.get('ErrorCode'))
                # Do not echo an untrusted vendor error which may contain credentials or content.
                safe_code = str(code) if isinstance(code, int) else 'unknown'
                return False, None, f'پیام‌رسان ارسال را نپذیرفت (کد {safe_code}).'
            result = data.get('result', data.get('Result'))
            if isinstance(result, list):
                result = result[0] if result else None
            if isinstance(result, dict):
                # A batch may be accepted while an individual recipient is rejected.
                if result.get('success', result.get('Success')) is False:
                    return False, None, 'گیرنده توسط پیام‌رسان پذیرفته نشد.'
                message_id = next((result[k] for k in ['messageId','MessageId','messageID','MessageID','id','Id'] if result.get(k)), None)
            elif isinstance(result, (str, int)) and not isinstance(result, bool):
                message_id = result
            else:
                message_id = None
            return True, str(message_id) if message_id else trace, None
        except httpx.TimeoutException:
            return False, None, 'مهلت پاسخ پیام‌رسان تمام شد؛ وضعیت ارسال نامشخص است و خودکار دوباره ارسال نشد.'
        except httpx.HTTPError:
            return False, None, 'اتصال امن به پیام‌رسان ناموفق بود.'
        except (ValueError, TypeError):
            return False, None, 'پاسخ JSON معتبر از پیام‌رسان دریافت نشد.'

    def get_credit(self):
        return False, None, 'این اتصال فقط ارسال UAPI v4 را پشتیبانی می‌کند؛ مانده را در پنل پیام‌رسان ببینید.'
