"""
Actionهای مربوط به اسناد و فاکتورها
"""

from typing import Any, Dict
from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution


class CreateDocumentAction(ActionHandler):
    """ایجاد سند حسابداری"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد سند",
            "description": "ایجاد یک سند حسابداری",
            "config_schema": {
                "document_type": {
                    "type": "string",
                    "description": "نوع سند دستی (همیشه manual)",
                    "required": True,
                    "default": "manual",
                    "enum": ["manual"],
                    "ui_config": {"labels": {"manual": "دستی"}}
                },
                "date": {
                    "type": "string",
                    "description": "تاریخ سند (ISO format یا از node قبلی)",
                    "required": True
                },
                "description": {
                    "type": "string",
                    "description": "شرح سند",
                    "required": False
                },
                "lines": {
                    "type": "array",
                    "description": "خطوط سند",
                    "required": True
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services.document_service import create_manual_document
        from app.services.fiscal_year_service import get_current_fiscal_year
        from datetime import datetime
        
        db = context.get("db")
        if not db:
            from adapters.db.session import get_db_session
            db = get_db_session().__enter__()
        
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        
        # حل کردن مقادیر
        document_type = WorkflowEngine._resolve_value_static(config.get("document_type"), context, node_results)
        date_str = WorkflowEngine._resolve_value_static(config.get("date"), context, node_results)
        description = WorkflowEngine._resolve_value_static(config.get("description", ""), context, node_results) or None
        lines = config.get("lines", [])
        
        # تبدیل تاریخ
        if isinstance(date_str, str):
            try:
                document_date = datetime.fromisoformat(date_str.replace('Z', '+00:00')).date()
            except:
                document_date = datetime.now().date()
        else:
            document_date = datetime.now().date()
        
        # دریافت سال مالی
        fiscal_year = get_current_fiscal_year(db, business_id)
        if not fiscal_year:
            return {
                "success": False,
                "error": "Fiscal year not found"
            }
        
        # آماده‌سازی داده‌های سند
        document_data = {
            "document_type": str(document_type),
            "document_date": document_date.isoformat(),
            "description": description,
            "lines": lines
        }
        
        try:
            result = create_manual_document(
                db=db,
                business_id=business_id,
                fiscal_year_id=fiscal_year.id,
                user_id=user_id,
                data=document_data
            )
            
            return {
                "success": True,
                "document_id": result.get("id"),
                "document_code": result.get("code")
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }


class CreateInvoiceAction(ActionHandler):
    """ایجاد فاکتور"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد فاکتور",
            "description": "ایجاد فاکتور فروش، خرید یا برگشتی با امکانات پیشرفته",
            "icon": "receipt_long",
            "category": "مالی و حسابداری",
            "config_schema": {
                # گروه 1: اطلاعات پایه
                "invoice_type": {
                    "type": "string",
                    "description": "نوع فاکتور",
                    "required": True,
                    "enum": ["invoice_sales", "invoice_purchase", "invoice_return_sales", "invoice_return_purchase"],
                    "default": "invoice_sales",
                    "ui_type": "select",
                    "ui_config": {
                        "labels": {
                            "invoice_sales": "🛒 فاکتور فروش",
                            "invoice_purchase": "🛍️ فاکتور خرید",
                            "invoice_return_sales": "↩️ برگشت از فروش",
                            "invoice_return_purchase": "↪️ برگشت از خرید"
                        }
                    },
                    "ui_group": "اطلاعات پایه"
                },
                "person_id": {
                    "type": "integer",
                    "description": "شناسه طرف حساب (مشتری یا تأمین‌کننده) - می‌توانید از نودهای قبلی استفاده کنید: $node_id.person_id",
                    "required": True,
                    "ui_type": "person_selector",
                    "ui_config": {
                        "business_scoped": True,
                        "filter_by_invoice_type": True,
                        "allow_create": False,
                        "show_reference_button": True
                    },
                    "ui_group": "اطلاعات پایه"
                },
                "document_date": {
                    "type": "string",
                    "format": "date",
                    "description": "تاریخ فاکتور (ISO format: YYYY-MM-DD) - پیش‌فرض: امروز. می‌توانید از نودهای قبلی استفاده کنید: $node_id.date",
                    "required": False,
                    "default": "today",
                    "ui_type": "date_picker",
                    "ui_config": {
                        "allow_future": True,
                        "allow_past": True,
                        "max_days_past": 365,
                        "max_days_future": 30,
                        "show_reference_button": True
                    },
                    "ui_group": "اطلاعات پایه"
                },
                "description": {
                    "type": "string",
                    "description": "توضیحات فاکتور - می‌توانید از نودهای قبلی استفاده کنید: فاکتور برای $node_id.customer_name",
                    "required": False,
                    "maxLength": 500,
                    "ui_type": "textarea",
                    "ui_config": {
                        "rows": 3,
                        "placeholder": "توضیحات فاکتور را وارد کنید...",
                        "show_reference_button": True
                    },
                    "ui_group": "اطلاعات پایه"
                },
                "currency_id": {
                    "type": "integer",
                    "description": "شناسه ارز (پیش‌فرض: ارز کسب‌وکار)",
                    "required": False,
                    "ui_type": "currency_selector",
                    "ui_config": {
                        "business_scoped": True,
                        "show_default": True
                    },
                    "ui_group": "اطلاعات پایه"
                },
                
                # گروه 2: آیتم‌های فاکتور
                "items": {
                    "type": "array",
                    "description": "آیتم‌های فاکتور - می‌توانید به صورت دستی یا از نودهای قبلی استفاده کنید: $node_id.items",
                    "required": True,
                    "ui_type": "invoice_items_builder",
                    "ui_config": {
                        "min_items": 1,
                        "max_items": 100,
                        "show_reference_button": True,
                        "item_schema": {
                            "product_id": {
                                "type": "integer",
                                "required": True,
                                "ui_type": "product_selector",
                                "description": "محصول"
                            },
                            "quantity": {
                                "type": "number",
                                "required": True,
                                "min": 0.001,
                                "default": 1,
                                "description": "تعداد"
                            },
                            "unit_price": {
                                "type": "number",
                                "required": False,
                                "description": "قیمت واحد (پیش‌فرض: قیمت محصول)"
                            },
                            "discount_percent": {
                                "type": "number",
                                "required": False,
                                "min": 0,
                                "max": 100,
                                "default": 0,
                                "description": "درصد تخفیف"
                            },
                            "tax_percent": {
                                "type": "number",
                                "required": False,
                                "min": 0,
                                "max": 100,
                                "default": 9,
                                "description": "درصد مالیات"
                            },
                            "description": {
                                "type": "string",
                                "required": False,
                                "maxLength": 200,
                                "description": "توضیحات آیتم"
                            }
                        }
                    },
                    "ui_group": "آیتم‌های فاکتور"
                },
                
                # گروه 3: تنظیمات مالی
                "discount": {
                    "type": "object",
                    "description": "تخفیف کلی فاکتور (اختیاری)",
                    "required": False,
                    "properties": {
                        "type": {
                            "type": "string",
                            "enum": ["percent", "fixed"],
                            "default": "percent",
                            "description": "نوع تخفیف"
                        },
                        "value": {
                            "type": "number",
                            "min": 0,
                            "description": "مقدار تخفیف"
                        }
                    },
                    "ui_type": "discount_config",
                    "ui_group": "تنظیمات مالی"
                },
                "tax_config": {
                    "type": "object",
                    "description": "تنظیمات مالیاتی (اختیاری)",
                    "required": False,
                    "properties": {
                        "apply_tax": {
                            "type": "boolean",
                            "default": True,
                            "description": "اعمال مالیات"
                        },
                        "tax_rate": {
                            "type": "number",
                            "min": 0,
                            "max": 100,
                            "default": 9,
                            "description": "نرخ مالیات (درصد)"
                        },
                        "tax_included": {
                            "type": "boolean",
                            "default": False,
                            "description": "مالیات جزو قیمت است"
                        }
                    },
                    "ui_group": "تنظیمات مالی"
                },
                
                # گروه 4: پرداخت
                "auto_create_payment": {
                    "type": "boolean",
                    "description": "ایجاد خودکار سند پرداخت/دریافت",
                    "default": False,
                    "required": False,
                    "ui_group": "پرداخت"
                },
                "payments": {
                    "type": "array",
                    "description": "پرداخت‌های همزمان با فاکتور (اختیاری)",
                    "required": False,
                    "depends_on": {"auto_create_payment": True},
                    "ui_type": "payments_builder",
                    "ui_config": {
                        "max_payments": 5,
                        "payment_schema": {
                            "amount": {
                                "type": "number",
                                "required": True,
                                "min": 0,
                                "description": "مبلغ پرداخت"
                            },
                            "payment_method": {
                                "type": "string",
                                "enum": ["cash", "bank", "check", "card"],
                                "required": True,
                                "description": "روش پرداخت"
                            },
                            "account_id": {
                                "type": "integer",
                                "description": "حساب بانکی/صندوق",
                                "ui_type": "account_selector"
                            },
                            "description": {
                                "type": "string",
                                "maxLength": 200,
                                "description": "توضیحات پرداخت"
                            }
                        }
                    },
                    "ui_group": "پرداخت"
                },
                
                # گروه 5: انبار
                "warehouse_settings": {
                    "type": "object",
                    "description": "تنظیمات انبار و حواله (اختیاری)",
                    "required": False,
                    "properties": {
                        "create_warehouse_document": {
                            "type": "boolean",
                            "default": True,
                            "description": "ایجاد خودکار حواله انبار"
                        },
                        "warehouse_id": {
                            "type": "integer",
                            "description": "انبار مبدأ/مقصد",
                            "ui_type": "warehouse_selector",
                            "ui_config": {
                                "business_scoped": True
                            }
                        },
                        "auto_post": {
                            "type": "boolean",
                            "default": False,
                            "description": "ثبت خودکار حواله"
                        }
                    },
                    "ui_group": "انبار"
                },
                
                # گروه 6: تنظیمات پیشرفته
                "is_proforma": {
                    "type": "boolean",
                    "description": "پیش‌فاکتور (بدون تأثیر حسابداری)",
                    "default": False,
                    "required": False,
                    "ui_group": "پیشرفته"
                },
                "fiscal_year_id": {
                    "type": "integer",
                    "description": "سال مالی (پیش‌فرض: سال جاری)",
                    "required": False,
                    "ui_type": "fiscal_year_selector",
                    "ui_group": "پیشرفته"
                },
                "reference_code": {
                    "type": "string",
                    "description": "کد/شماره مرجع (اختیاری)",
                    "required": False,
                    "maxLength": 50,
                    "ui_group": "پیشرفته"
                },
                "extra_info": {
                    "type": "object",
                    "description": "اطلاعات اضافی (JSON - اختیاری)",
                    "required": False,
                    "ui_type": "json_editor",
                    "ui_group": "پیشرفته"
                }
            },
            
            # UI Configuration
            "ui_config": {
                "groups": [
                    {"key": "اطلاعات پایه", "icon": "info", "collapsible": False},
                    {"key": "آیتم‌های فاکتور", "icon": "shopping_cart", "collapsible": False},
                    {"key": "تنظیمات مالی", "icon": "payments", "collapsible": True},
                    {"key": "پرداخت", "icon": "account_balance", "collapsible": True},
                    {"key": "انبار", "icon": "warehouse", "collapsible": True},
                    {"key": "پیشرفته", "icon": "settings", "collapsible": True, "default_collapsed": True}
                ],
                "validation_rules": {
                    "items": {
                        "min_items": 1,
                        "max_items": 100,
                        "error_messages": {
                            "min": "حداقل یک آیتم باید وارد شود",
                            "max": "حداکثر 100 آیتم مجاز است"
                        }
                    },
                    "document_date": {
                        "within_fiscal_year": True,
                        "error_message": "تاریخ باید در محدوده سال مالی فعال باشد"
                    }
                },
                "help_texts": {
                    "items": "💡 محصولات فاکتور را اضافه کنید. می‌توانید از reference به نودهای قبلی استفاده کنید: $node_id.items",
                    "warehouse_settings": "📦 در صورت فعال بودن، حواله انبار به صورت خودکار ایجاد می‌شود",
                    "payments": "💳 برای ثبت پرداخت همزمان با فاکتور، این بخش را فعال کنید",
                    "is_proforma": "📄 پیش‌فاکتور بر روی حسابداری و موجودی تأثیر نمی‌گذارد"
                },
                "features": {
                    "show_preview": True,
                    "show_summary": True,
                    "show_validation_errors": True,
                    "auto_calculate": True
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services.invoice_service import create_invoice
        from datetime import datetime, date
        import logging
        
        logger = logging.getLogger(__name__)
        
        db = context.get("db")
        if not db:
            from adapters.db.session import get_db_session
            db = get_db_session().__enter__()
        
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        
        # حل کردن مقادیر پایه
        invoice_type = WorkflowEngine._resolve_value_static(config.get("invoice_type"), context, node_results)
        person_id = WorkflowEngine._resolve_value_static(config.get("person_id"), context, node_results)
        items = WorkflowEngine._resolve_value_static(config.get("items", []), context, node_results)
        
        # اعتبارسنجی
        if not invoice_type:
            return {"success": False, "error": "invoice_type مشخص نشده است"}
        if not person_id:
            return {"success": False, "error": "person_id مشخص نشده است"}
        if not items or not isinstance(items, list) or len(items) == 0:
            return {"success": False, "error": "حداقل یک آیتم باید وارد شود"}
        
        # تبدیل person_id به integer
        try:
            person_id = int(person_id)
        except (ValueError, TypeError):
            return {"success": False, "error": f"person_id نامعتبر است: {person_id}"}
        
        # دریافت currency_id
        from adapters.db.models.business import Business
        business = db.get(Business, business_id)
        currency_id_raw = config.get("currency_id")
        if currency_id_raw:
            currency_id = WorkflowEngine._resolve_value_static(currency_id_raw, context, node_results)
            try:
                currency_id = int(currency_id)
            except (ValueError, TypeError):
                currency_id = business.default_currency_id if business else None
        else:
            currency_id = business.default_currency_id if business else None
        
        if not currency_id:
            return {"success": False, "error": "Currency ID is required"}
        
        # حل کردن تاریخ
        document_date_raw = config.get("document_date")
        if document_date_raw and document_date_raw != "today":
            document_date_resolved = WorkflowEngine._resolve_value_static(document_date_raw, context, node_results)
            if isinstance(document_date_resolved, str):
                try:
                    # تلاش برای parse کردن تاریخ
                    if "T" in document_date_resolved:
                        document_date = datetime.fromisoformat(document_date_resolved.replace('Z', '+00:00')).date()
                    else:
                        document_date = date.fromisoformat(document_date_resolved)
                except (ValueError, TypeError):
                    logger.warning(f"Invalid document_date format: {document_date_resolved}, using today")
                    document_date = datetime.now().date()
            elif isinstance(document_date_resolved, (date, datetime)):
                document_date = document_date_resolved if isinstance(document_date_resolved, date) else document_date_resolved.date()
            else:
                document_date = datetime.now().date()
        else:
            document_date = datetime.now().date()
        
        # حل کردن توضیحات
        description = config.get("description")
        if description:
            description = WorkflowEngine._resolve_value_static(description, context, node_results)
        
        # حل کردن reference_code
        reference_code = config.get("reference_code")
        if reference_code:
            reference_code = WorkflowEngine._resolve_value_static(reference_code, context, node_results)
        
        # آماده‌سازی داده‌های فاکتور
        invoice_data = {
            "invoice_type": str(invoice_type),
            "person_id": int(person_id),
            "currency_id": int(currency_id),
            "document_date": document_date.isoformat(),
            "lines": items
        }
        
        # افزودن توضیحات (اگر وجود دارد)
        if description:
            invoice_data["description"] = str(description)
        
        # افزودن پیش‌فاکتور (اگر فعال باشد)
        is_proforma = config.get("is_proforma", False)
        if is_proforma:
            invoice_data["is_proforma"] = True
        
        # افزودن تخفیف (اگر وجود دارد)
        discount_config = config.get("discount")
        if discount_config and isinstance(discount_config, dict):
            discount_type = discount_config.get("type", "percent")
            discount_value = discount_config.get("value", 0)
            if discount_value > 0:
                if discount_type == "percent":
                    invoice_data["global_discount_percent"] = float(discount_value)
                else:
                    invoice_data["global_discount_amount"] = float(discount_value)
        
        # افزودن تنظیمات مالیاتی (اگر وجود دارد)
        tax_config = config.get("tax_config")
        if tax_config and isinstance(tax_config, dict):
            # این تنظیمات در سطح آیتم‌ها اعمال می‌شود
            # فعلاً فقط لاگ می‌کنیم
            logger.info(f"Tax config provided: {tax_config}")
        
        # افزودن پرداخت‌ها (اگر فعال باشد)
        auto_create_payment = config.get("auto_create_payment", False)
        if auto_create_payment:
            payments = config.get("payments", [])
            if payments and isinstance(payments, list) and len(payments) > 0:
                invoice_data["payments"] = payments
        
        # افزودن اطلاعات اضافی
        extra_info = config.get("extra_info")
        if extra_info and isinstance(extra_info, dict):
            invoice_data["extra_info"] = extra_info
        
        # افزودن reference_code به extra_info
        if reference_code:
            if "extra_info" not in invoice_data:
                invoice_data["extra_info"] = {}
            invoice_data["extra_info"]["reference_code"] = str(reference_code)
        
        # افزودن correlation_id از context
        correlation_id = context.get("correlation_id")
        if correlation_id:
            if "extra_info" not in invoice_data:
                invoice_data["extra_info"] = {}
            invoice_data["extra_info"]["workflow_correlation_id"] = correlation_id
        
        try:
            result = create_invoice(
                db=db,
                business_id=business_id,
                user_id=user_id,
                data=invoice_data
            )
            
            # اطلاعات کامل برای استفاده در نودهای بعدی
            return {
                "success": True,
                "invoice_id": result.get("id"),
                "document_id": result.get("id"),
                "document_code": result.get("code"),
                "invoice_code": result.get("code"),
                "invoice_number": result.get("number"),
                "total_amount": result.get("total"),
                "final_amount": result.get("final"),
                "invoice_type": invoice_type,
                "person_id": person_id,
                "document_date": document_date.isoformat(),
                "is_proforma": is_proforma
            }
        except Exception as e:
            logger.error(f"Failed to create invoice in workflow: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e),
                "error_type": type(e).__name__
            }


class UpdateInventoryAction(ActionHandler):
    """به‌روزرسانی موجودی"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "به‌روزرسانی موجودی",
            "description": "به‌روزرسانی موجودی یک محصول",
            "config_schema": {
                "product_id": {
                    "type": "integer",
                    "description": "شناسه محصول",
                    "required": True
                },
                "warehouse_id": {
                    "type": "integer",
                    "description": "شناسه انبار",
                    "required": True
                },
                "quantity": {
                    "type": "number",
                    "description": "تغییر مقدار موجودی (مثبت برای افزایش، منفی برای کاهش)",
                    "required": True
                }
            }
        }
    
    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services.warehouse_service import create_manual_warehouse_document, post_warehouse_document
        from datetime import datetime
        
        db = context.get("db")
        if not db:
            from adapters.db.session import get_db_session
            db = get_db_session().__enter__()
        
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        
        # حل کردن مقادیر
        product_id = WorkflowEngine._resolve_value_static(config.get("product_id"), context, node_results)
        warehouse_id = WorkflowEngine._resolve_value_static(config.get("warehouse_id"), context, node_results)
        quantity = WorkflowEngine._resolve_value_static(config.get("quantity"), context, node_results)
        
        quantity_float = float(quantity)
        
        # آماده‌سازی داده‌های حواله
        warehouse_data = {
            "doc_type": "adjustment",
            "document_date": datetime.now().date().isoformat(),
            "warehouse_id_from": int(warehouse_id) if quantity_float < 0 else None,
            "warehouse_id_to": int(warehouse_id) if quantity_float > 0 else None,
            "lines": [{
                "product_id": int(product_id),
                "warehouse_id": int(warehouse_id),
                "quantity": abs(quantity_float),
                "movement": "in" if quantity_float > 0 else "out"
            }]
        }
        
        try:
            wh_doc = create_manual_warehouse_document(
                db=db,
                business_id=business_id,
                user_id=user_id,
                data=warehouse_data
            )
            
            # پست کردن حواله برای به‌روزرسانی موجودی
            post_warehouse_document(db, wh_doc.id)
            
            return {
                "success": True,
                "warehouse_document_id": wh_doc.id,
                "warehouse_document_code": wh_doc.code
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }

