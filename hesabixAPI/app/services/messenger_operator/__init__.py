# noqa: D100
"""
پل اپراتور در پیام‌رسان‌ها (تلگرام/بله).

برای افزودن فلو جدید:
- flow_key یکتا تعریف کنید
- کلاس هندلر با متد handle(...) مشابه CrmWebChatMessengerFlow بسازید
- در dispatch.FLOW_HANDLERS ثبت کنید
- در نشست (MessengerOperatorSession) flow_key را عوض کنید (مثلاً با دستور /myflow)
"""

from app.services.messenger_operator.dispatch import (
	dispatch_operator_messenger_message,
	register_operator_flow,
)

__all__ = ["dispatch_operator_messenger_message", "register_operator_flow"]
