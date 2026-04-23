"""
Triggerهای مربوط به عملیات مالی
"""

from typing import Any, Dict

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
                    "description": "نوع (دریافت/پرداخت)",
                    "required": False,
                    "enum": ["receipt", "payment"],
                    "ui_config": {
                        "labels": {
                            "receipt": "دریافت",
                            "payment": "پرداخت"
                        }
                    }
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
                    "items": {"type": "string", "enum": ["cash", "bank", "check", "card"]},
                    "ui_type": "multi_select",
                    "ui_config": {
                        "labels": {"cash": "نقد", "bank": "بانک", "check": "چک", "card": "کارت"}
                    },
                    "required": False
                },
                "account_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس حساب بانکی/صندوق",
                    "required": False,
                    "ui_type": "account_selector",
                    "ui_config": {"business_scoped": True}
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
                },
                "person_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس طرف‌حساب (شخص)",
                    "required": False,
                    "ui_type": "person_selector",
                    "ui_config": {"business_scoped": True}
                },
                "project_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس پروژه",
                    "required": False
                },
                "currency_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس ارز سند",
                    "required": False,
                    "ui_type": "currency_selector",
                    "ui_config": {"business_scoped": True, "show_all_option": True}
                },
                "fiscal_year_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس سال مالی",
                    "required": False,
                    "ui_type": "fiscal_year_selector",
                    "ui_config": {"business_scoped": True}
                },
                "account_ids_filter": {
                    "type": "array",
                    "description": "اگر هر حساب معین از این لیست در سطرهای سند باشد، تریگر فعال می‌شود",
                    "items": {"type": "integer"},
                    "required": False
                },
                "description_contains": {
                    "type": "string",
                    "description": "فیلتر متنی روی شرح سند",
                    "required": False
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        db = context.get("db")
        business_id = context.get("business_id")
        if db is not None and business_id is not None:
            from app.services.workflow.workflow_entity_validation import (
                validate_receipt_payment_config_entities,
            )

            if not validate_receipt_payment_config_entities(db, int(business_id), config):
                return {}

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
            pm_single = data.get("payment_method")
            pm_list = data.get("payment_methods") or []
            if not isinstance(pm_list, list):
                pm_list = []
            ok_pm = (pm_single in payment_method_filter) or any(
                x in payment_method_filter for x in pm_list
            )
            if not ok_pm:
                return {}
        
        # فیلتر بر اساس حساب (تک حساب یا لیست حساب‌های سطر)
        account_id_filter = config.get("account_id_filter")
        if account_id_filter is not None:
            account_id = data.get("account_id")
            acc_ids = data.get("account_ids") or []
            if not isinstance(acc_ids, list):
                acc_ids = []
            try:
                want = int(account_id_filter)
            except (TypeError, ValueError):
                return {}
            if account_id != want and want not in [int(x) for x in acc_ids if x is not None]:
                return {}

        account_ids_filter = config.get("account_ids_filter")
        if account_ids_filter and isinstance(account_ids_filter, list):
            try:
                need = {int(x) for x in account_ids_filter}
            except (TypeError, ValueError):
                return {}
            have = data.get("account_ids") or []
            if not isinstance(have, list):
                have = []
            have_int = set()
            for x in have:
                try:
                    have_int.add(int(x))
                except (TypeError, ValueError):
                    continue
            if not need.intersection(have_int):
                return {}

        person_id_filter = config.get("person_id_filter")
        if person_id_filter is not None:
            try:
                want_p = int(person_id_filter)
            except (TypeError, ValueError):
                return {}
            pids = data.get("person_ids") or []
            if not isinstance(pids, list):
                pids = []
            pid_single = data.get("person_id")
            pids_int = []
            for x in pids:
                try:
                    pids_int.append(int(x))
                except (TypeError, ValueError):
                    continue
            if pid_single != want_p and want_p not in pids_int:
                return {}

        proj_f = config.get("project_id_filter")
        if proj_f is not None:
            try:
                dp = data.get("project_id")
                if dp is None or int(dp) != int(proj_f):
                    return {}
            except (TypeError, ValueError):
                return {}

        cur_f = config.get("currency_id_filter")
        if cur_f is not None:
            try:
                if int(data.get("currency_id") or -1) != int(cur_f):
                    return {}
            except (TypeError, ValueError):
                return {}

        fy_f = config.get("fiscal_year_id_filter")
        if fy_f is not None:
            try:
                if int(data.get("fiscal_year_id") or -1) != int(fy_f):
                    return {}
            except (TypeError, ValueError):
                return {}

        desc_sub = config.get("description_contains")
        if desc_sub:
            description = (data.get("description") or "") or ""
            if str(desc_sub).lower() not in description.lower():
                return {}
        
        # اضافه کردن موجودی حساب
        if config.get("include_balance", False):
            # این می‌تواند از دیتابیس خوانده شود
            data["account_balance"] = data.get("account_balance", 0)
        
        return data


class ReceiptPaymentUpdatedTrigger(ReceiptPaymentCreatedTrigger):
    """همان فیلترهای «ایجاد» برای رویداد ویرایش دریافت/پرداخت"""

    def get_metadata(self) -> Dict[str, Any]:
        meta = super().get_metadata()
        meta["name"] = "ویرایش دریافت/پرداخت"
        meta["description"] = "زمانی که سند دریافت یا پرداخت ویرایش می‌شود"
        return meta


class CheckDueDateTrigger(BaseTrigger):
    """Trigger برای سررسید چک"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "سررسید چک",
            "description": "زمانی که چک به سررسید می‌رسد",
            "config_schema": {
                "check_type": {
                    "type": "string",
                    "description": "نوع چک",
                    "required": False,
                    "enum": ["received", "paid"],
                    "ui_config": {
                        "labels": {
                            "received": "دریافتی",
                            "paid": "پرداختی"
                        }
                    }
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

        days_before = config.get("days_before")
        if days_before is not None and data:
            try:
                max_days_before = int(float(days_before))
            except (TypeError, ValueError):
                max_days_before = None
            if max_days_before is not None:
                dud = data.get("days_until_due")
                if dud is not None:
                    try:
                        dud_i = int(dud)
                    except (TypeError, ValueError):
                        dud_i = None
                    if dud_i is not None and dud_i > max_days_before:
                        return {}

        return data

