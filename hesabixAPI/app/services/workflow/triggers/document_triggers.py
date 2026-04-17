"""
Triggerهای مربوط به اسناد
"""

from typing import Any, Dict
from app.services.workflow.triggers.base_trigger import BaseTrigger


class DocumentCreatedTrigger(BaseTrigger):
    """Trigger برای ایجاد سند"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد سند",
            "description": "زمانی که یک سند حسابداری ایجاد می‌شود",
            "config_schema": {
                "enabled": {
                    "type": "boolean",
                    "description": "فعال/غیرفعال کردن trigger",
                    "default": True,
                    "required": False
                },
                "document_type": {
                    "type": "string",
                    "description": "نوع سند (اختیاری - خالی = همه انواع)",
                    "required": False,
                    "enum": ["expense", "income", "receipt", "payment", "transfer", "manual", "opening_balance", "year_end_closing"],
                    "ui_config": {
                        "labels": {
                            "expense": "هزینه",
                            "income": "درآمد",
                            "receipt": "دریافت",
                            "payment": "پرداخت",
                            "transfer": "انتقال",
                            "manual": "دستی",
                            "opening_balance": "تراز افتتاحیه",
                            "year_end_closing": "سربندی سال"
                        }
                    }
                },
                "min_amount": {
                    "type": "number",
                    "description": "حداقل مبلغ سند",
                    "required": False
                },
                "max_amount": {
                    "type": "number",
                    "description": "حداکثر مبلغ سند",
                    "required": False
                },
                "fiscal_year_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس سال مالی خاص",
                    "required": False,
                    "ui_type": "fiscal_year_selector",
                    "ui_config": {"business_scoped": True}
                },
                "user_id_filter": {
                    "type": "integer",
                    "description": "فیلتر بر اساس کاربر ایجادکننده",
                    "required": False,
                    "ui_type": "user_selector",
                    "ui_config": {"business_scoped": True}
                },
                "description_contains": {
                    "type": "string",
                    "description": "فیلتر بر اساس کلمات کلیدی در شرح",
                    "required": False
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
                "person_id_filter": {
                    "type": "integer",
                    "description": "فیلتر اگر هر سطر دارای این شخص باشد",
                    "required": False,
                    "ui_type": "person_selector",
                    "ui_config": {"business_scoped": True}
                },
                "line_account_id_filter": {
                    "type": "integer",
                    "description": "فیلتر اگر هر سطر سند شامل این حساب معین باشد",
                    "required": False,
                    "ui_type": "account_selector",
                    "ui_config": {"business_scoped": True}
                },
                "item_account_id_filter": {
                    "type": "integer",
                    "description": "فیلتر برای حساب سطر اقلام (هزینه/درآمد و …)",
                    "required": False,
                    "ui_type": "account_selector",
                    "ui_config": {"business_scoped": True}
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
        db = context.get("db")
        business_id = context.get("business_id")
        if db is not None and business_id is not None:
            from app.services.workflow.workflow_entity_validation import (
                validate_document_created_config_entities,
            )

            if not validate_document_created_config_entities(db, int(business_id), config):
                return {}

        data = super().execute(context, config)
        if not data:
            return {}
        
        # فیلتر بر اساس نوع سند
        document_type = config.get("document_type")
        if document_type:
            if data.get("document_type") != document_type:
                return {}
        
        # فیلتر بر اساس مبلغ
        min_amount = config.get("min_amount")
        max_amount = config.get("max_amount")
        if min_amount is not None or max_amount is not None:
            amount = data.get("total_amount", 0)
            if min_amount is not None and amount < min_amount:
                return {}
            if max_amount is not None and amount > max_amount:
                return {}
        
        # فیلتر بر اساس سال مالی
        fiscal_year_filter = config.get("fiscal_year_filter")
        if fiscal_year_filter is not None:
            fiscal_year_id = data.get("fiscal_year_id")
            if fiscal_year_id != fiscal_year_filter:
                return {}
        
        # فیلتر بر اساس کاربر
        user_id_filter = config.get("user_id_filter")
        if user_id_filter is not None:
            created_by = data.get("created_by_user_id") or context.get("user_id")
            if created_by != user_id_filter:
                return {}
        
        # فیلتر بر اساس شرح
        description_contains = config.get("description_contains")
        if description_contains:
            description = data.get("description", "")
            if description_contains.lower() not in description.lower():
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
                dc = data.get("currency_id")
                if dc is None or int(dc) != int(cur_f):
                    return {}
            except (TypeError, ValueError):
                return {}

        person_f = config.get("person_id_filter")
        if person_f is not None:
            try:
                want = int(person_f)
            except (TypeError, ValueError):
                return {}
            pids = data.get("person_ids") or []
            if not isinstance(pids, list):
                pids = []
            pids_i = []
            for x in pids:
                try:
                    pids_i.append(int(x))
                except (TypeError, ValueError):
                    continue
            ps = data.get("person_id")
            if ps is not None:
                try:
                    pids_i.append(int(ps))
                except (TypeError, ValueError):
                    pass
            if want not in pids_i:
                return {}

        line_acc_f = config.get("line_account_id_filter")
        if line_acc_f is not None:
            try:
                want_a = int(line_acc_f)
            except (TypeError, ValueError):
                return {}
            la = data.get("line_account_ids") or []
            if not isinstance(la, list):
                la = []
            la_i = []
            for x in la:
                try:
                    la_i.append(int(x))
                except (TypeError, ValueError):
                    continue
            if want_a not in la_i:
                return {}

        item_acc_f = config.get("item_account_id_filter")
        if item_acc_f is not None:
            try:
                want_i = int(item_acc_f)
            except (TypeError, ValueError):
                return {}
            ia = data.get("item_line_account_ids") or []
            if not isinstance(ia, list):
                ia = []
            ia_i = []
            for x in ia:
                try:
                    ia_i.append(int(x))
                except (TypeError, ValueError):
                    continue
            if want_i not in ia_i:
                return {}
        
        return data


class InvoiceCreatedTrigger(BaseTrigger):
    """Trigger برای ایجاد فاکتور"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد فاکتور",
            "description": "زمانی که یک فاکتور فروش یا خرید ایجاد می‌شود",
            "config_schema": {
                "enabled": {
                    "type": "boolean",
                    "description": "فعال/غیرفعال کردن trigger",
                    "default": True,
                    "required": False
                },
                "invoice_type": {
                    "type": "string",
                    "description": "نوع فاکتور",
                    "enum": ["invoice_sales", "invoice_purchase", "invoice_return_sales", "invoice_return_purchase"],
                    "ui_config": {
                        "labels": {
                            "invoice_sales": "فاکتور فروش",
                            "invoice_purchase": "فاکتور خرید",
                            "invoice_return_sales": "برگشت از فروش",
                            "invoice_return_purchase": "برگشت از خرید"
                        }
                    },
                    "required": False
                },
                "min_amount": {
                    "type": "number",
                    "description": "حداقل مبلغ فاکتور",
                    "required": False
                },
                "max_amount": {
                    "type": "number",
                    "description": "حداکثر مبلغ فاکتور",
                    "required": False
                },
                "status_filter": {
                    "type": "array",
                    "description": "فیلتر بر اساس وضعیت فاکتور",
                    "items": {
                        "type": "string",
                        "enum": ["draft", "confirmed", "cancelled", "pending"]
                    },
                    "ui_type": "multi_select",
                    "ui_config": {
                        "labels": {
                            "draft": "پیش‌نویس",
                            "confirmed": "تایید شده",
                            "cancelled": "لغو شده",
                            "pending": "در انتظار"
                        }
                    },
                    "required": False
                },
                "person_type_filter": {
                    "type": "string",
                    "description": "فیلتر بر اساس نوع شخص",
                    "enum": ["customer", "supplier", "employee", "other"],
                    "ui_config": {
                        "labels": {
                            "customer": "مشتری",
                            "supplier": "تامین‌کننده",
                            "employee": "کارمند",
                            "other": "سایر"
                        }
                    },
                    "required": False
                },
                "currency_id": {
                    "type": "integer",
                    "description": "فیلتر بر اساس ارز",
                    "ui_type": "currency_selector",
                    "ui_config": {
                        "business_scoped": True,
                        "show_all_option": True
                    },
                    "required": False
                },
                "include_tax_details": {
                    "type": "boolean",
                    "description": "شامل جزئیات مالیات در trigger data",
                    "default": False,
                    "required": False
                },
                "include_payment_status": {
                    "type": "boolean",
                    "description": "شامل وضعیت پرداخت در trigger data",
                    "default": False,
                    "required": False
                },
                "cooldown_seconds": {
                    "type": "integer",
                    "description": "مدت زمان انتظار بین triggerهای متوالی (ثانیه)",
                    "default": 0,
                    "required": False
                },
                "timeout_seconds": {
                    "type": "integer",
                    "description": "حداکثر زمان انتظار برای اجرای workflow (ثانیه)",
                    "default": 300,
                    "required": False
                }
            }
        }
    
    def execute(self, context: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
        data = super().execute(context, config)
        if not data:
            return {}
        
        # فیلتر بر اساس نوع فاکتور
        invoice_type = config.get("invoice_type")
        if invoice_type:
            if data.get("invoice_type") != invoice_type:
                return {}
        
        # فیلتر بر اساس مبلغ
        min_amount = config.get("min_amount")
        max_amount = config.get("max_amount")
        amount = data.get("total_amount", 0)
        
        if min_amount is not None and amount < min_amount:
            return {}
        
        if max_amount is not None and amount > max_amount:
            return {}
        
        # فیلتر بر اساس وضعیت
        status_filter = config.get("status_filter")
        if status_filter:
            invoice_status = data.get("status", "draft")
            if invoice_status not in status_filter:
                return {}
        
        # فیلتر بر اساس نوع شخص
        person_type_filter = config.get("person_type_filter")
        if person_type_filter:
            person_type = data.get("person_type")
            if person_type != person_type_filter:
                return {}
        
        # فیلتر بر اساس ارز
        currency_id = config.get("currency_id")
        if currency_id is not None:
            invoice_currency_id = data.get("currency_id")
            if invoice_currency_id != currency_id:
                return {}
        
        # اضافه کردن جزئیات مالیات
        if config.get("include_tax_details", False):
            # این می‌تواند از دیتابیس خوانده شود
            data["tax_details"] = data.get("tax_details", {})
        
        # اضافه کردن وضعیت پرداخت
        if config.get("include_payment_status", False):
            # این می‌تواند از دیتابیس خوانده شود
            data["payment_status"] = data.get("payment_status", "unpaid")
        
        return data

