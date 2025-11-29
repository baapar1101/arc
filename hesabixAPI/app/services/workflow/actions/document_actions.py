"""
Actionهای مربوط به اسناد و فاکتورها
"""

from typing import Any, Dict
from app.services.workflow.action_registry import ActionHandler


class CreateDocumentAction(ActionHandler):
    """ایجاد سند حسابداری"""
    
    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ایجاد سند",
            "description": "ایجاد یک سند حسابداری",
            "config_schema": {
                "document_type": {
                    "type": "string",
                    "description": "نوع سند",
                    "required": True
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
            "description": "ایجاد یک فاکتور فروش یا خرید",
            "config_schema": {
                "invoice_type": {
                    "type": "string",
                    "description": "نوع فاکتور (invoice_sales/invoice_purchase)",
                    "required": True
                },
                "person_id": {
                    "type": "integer",
                    "description": "شناسه شخص",
                    "required": True
                },
                "items": {
                    "type": "array",
                    "description": "آیتم‌های فاکتور",
                    "required": True
                }
            }
        }
    
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services.invoice_service import create_invoice
        from datetime import datetime
        
        db = context.get("db")
        if not db:
            from adapters.db.session import get_db_session
            db = get_db_session().__enter__()
        
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        
        # حل کردن مقادیر
        invoice_type = WorkflowEngine._resolve_value_static(config.get("invoice_type"), context, node_results)
        person_id = WorkflowEngine._resolve_value_static(config.get("person_id"), context, node_results)
        items = config.get("items", [])
        
        # دریافت currency_id از business یا از config
        from adapters.db.models.business import Business
        business = db.get(Business, business_id)
        currency_id = config.get("currency_id") or (business.default_currency_id if business else None)
        if not currency_id:
            return {
                "success": False,
                "error": "Currency ID is required"
            }
        
        # آماده‌سازی داده‌های فاکتور
        invoice_data = {
            "invoice_type": str(invoice_type),
            "person_id": int(person_id),
            "currency_id": int(currency_id),
            "document_date": datetime.now().date().isoformat(),
            "lines": items
        }
        
        try:
            result = create_invoice(
                db=db,
                business_id=business_id,
                user_id=user_id,
                data=invoice_data
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

