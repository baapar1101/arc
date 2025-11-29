"""
Triggerهای مربوط به عملیات مالی
"""

from typing import Any, Dict
from datetime import datetime
from app.services.workflow.triggers.base_trigger import BaseTrigger


class ReceiptPaymentCreatedTrigger(BaseTrigger):
    """Trigger برای ایجاد دریافت/پرداخت"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد دریافت/پرداخت",
            "description": "زمانی که یک دریافت یا پرداخت ثبت می‌شود",
            "config_schema": {
                "enabled": {
                    "type": "boolean",
                    "description": "فعال/غیرفعال کردن trigger",
                    "default": True,
                    "required": False
                },
                "type": {
                    "type": "string",
                    "description": "نوع (receipt/payment)",
                    "required": False
                },
                "min_amount": {
                    "type": "number",
                    "description": "حداقل مبلغ",
                    "required": False
                },
                "max_amount": {
                    "type": "number",
                    "description": "حداکثر مبلغ",
                    "required": False
                },
                "payment_method_filter": {
                    "type": "array",
                    "description": "فیلتر بر اساس روش پرداخت",
                    "items": {"type": "string"},
                    "required": False
                },
                "account_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس حساب بانکی",
                    "required": False
                },
                "include_balance": {
                    "type": "boolean",
                    "description": "شامل موجودی حساب در trigger data",
                    "default": False,
                    "required": False
                },
                "check_duplicate": {
                    "type": "boolean",
                    "description": "بررسی تراکنش تکراری",
                    "default": False,
                    "required": False
                },
                "cooldown_seconds": {
                    "type": "integer",
                    "description": "مدت زمان انتظار بین triggerهای متوالی (ثانیه)",
                    "default": 0,
                    "required": False
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        data = super().execute(context, config)
        if not data:
            return {}
        
        # فیلتر بر اساس نوع
        type_filter = config.get("type")
        if type_filter:
            if data.get("type") != type_filter:
                return {}
        
        # فیلتر بر اساس مبلغ
        min_amount = config.get("min_amount")
        max_amount = config.get("max_amount")
        amount = data.get("amount", 0)
        
        if min_amount is not None and amount < min_amount:
            return {}
        
        if max_amount is not None and amount > max_amount:
            return {}
        
        # فیلتر بر اساس روش پرداخت
        payment_method_filter = config.get("payment_method_filter")
        if payment_method_filter:
            payment_method = data.get("payment_method")
            if payment_method not in payment_method_filter:
                return {}
        
        # فیلتر بر اساس حساب
        account_id_filter = config.get("account_id_filter")
        if account_id_filter is not None:
            account_id = data.get("account_id")
            if account_id != account_id_filter:
                return {}
        
        # اضافه کردن موجودی حساب
        if config.get("include_balance", False):
            # این می‌تواند از دیتابیس خوانده شود
            data["account_balance"] = data.get("account_balance", 0)
        
        return data


class CheckDueDateTrigger(BaseTrigger):
    """Trigger برای سررسید چک"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "سررسید چک",
            "description": "زمانی که چک به سررسید می‌رسد",
            "config_schema": {
                "check_type": {
                    "type": "string",
                    "description": "نوع چک (received/paid)",
                    "required": False
                },
                "days_before": {
                    "type": "number",
                    "description": "تعداد روز قبل از سررسید",
                    "required": False
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        data = super().execute(context, config)
        
        # فیلتر بر اساس نوع چک
        check_type = config.get("check_type")
        if check_type:
            if data.get("check_type") != check_type:
                return {}
        
        return data

