from __future__ import annotations

from typing import Dict, Any, List, Callable, Optional, Set
from dataclasses import dataclass
from enum import Enum
from sqlalchemy.orm import Session
from app.core.auth_dependency import AuthContext
import json


class AIRole(str, Enum):
    """نقش‌های مختلف برای AI Functions"""
    USER = "user"              # کاربران عادی کسب‌وکار
    OPERATOR = "operator"      # اپراتورهای پشتیبانی
    ADMIN = "admin"            # مدیر سیستم (superadmin)
    BUSINESS_OWNER = "business_owner"  # مالک کسب‌وکار


@dataclass
class AIFunction:
    """تعریف یک function قابل استفاده توسط AI"""
    name: str
    description: str
    parameters_schema: Dict[str, Any]
    handler: Callable
    allowed_roles: Set[AIRole]
    required_permissions: Optional[List[str]] = None
    business_context_required: bool = True
    category: Optional[str] = None


class AIFunctionRegistry:
    """
    Registry مرکزی برای تمام function های AI
    این registry به صورت lazy load می‌شود و از service layer استفاده می‌کند
    """
    
    _instance: Optional['AIFunctionRegistry'] = None
    _functions: Dict[str, AIFunction] = {}
    _initialized: bool = False
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        if not self._initialized:
            self._register_all_functions()
            self._initialized = True
    
    def _register_all_functions(self):
        """ثبت تمام function ها - این متد فقط یکبار اجرا می‌شود"""
        # Business & Financial Functions
        self._register_business_functions()
        self._register_invoice_functions()
        self._register_product_functions()
        self._register_person_functions()
        self._register_financial_functions()
        self._register_crm_functions()
        # Operator functions
        self._register_operator_functions()
        # Admin functions
        self._register_admin_functions()
        # Business owner functions
        self._register_business_owner_functions()
        # External HTTP connectors
        self._register_connector_functions()
    
    def _register_business_functions(self):
        """ثبت function های مربوط به کسب‌وکار"""
        from app.services.business_service import get_business_by_id
        
        def get_business_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای دریافت اطلاعات کسب‌وکار"""
            return get_business_by_id(db, business_id, user_id)
        
        self.register(AIFunction(
            name="get_business_info",
            description="دریافت اطلاعات کامل کسب‌وکار فعلی شامل نام، آدرس، اطلاعات تماس و تنظیمات. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {},
                "required": []
            },
            handler=self._create_handler(get_business_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            business_context_required=True,
            category="business"
        ))
    
    def _register_invoice_functions(self):
        """ثبت function های مربوط به فاکتورها"""
        def search_invoices_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای جستجوی فاکتورها"""
            from app.services.document_service import list_documents
            
            # فیلتر کردن فقط فاکتورها
            invoice_types = [
                "invoice_sales", "invoice_sales_return",
                "invoice_purchase", "invoice_purchase_return",
                "invoice_direct_consumption", "invoice_production", "invoice_waste"
            ]
            
            # ساخت query dict برای list_documents
            query = {}
            
            # document_type
            if "document_type" in kwargs:
                query["document_type"] = kwargs["document_type"]
            elif "document_types" in kwargs:
                # اگر لیست document_types داده شده، از اولین استفاده کن
                doc_types = kwargs["document_types"]
                if isinstance(doc_types, list) and doc_types:
                    query["document_type"] = doc_types[0]
            else:
                # پیش‌فرض: اولین نوع فاکتور
                query["document_type"] = invoice_types[0]
            
            # سایر فیلترها
            if "fiscal_year_id" in kwargs:
                query["fiscal_year_id"] = kwargs["fiscal_year_id"]
            if "from_date" in kwargs:
                query["from_date"] = kwargs["from_date"]
            if "to_date" in kwargs:
                query["to_date"] = kwargs["to_date"]
            if "search" in kwargs:
                query["search"] = kwargs["search"]
            if "person_id" in kwargs:
                query["person_id"] = kwargs["person_id"]
            
            # Pagination
            query["take"] = kwargs.get("take", 50)
            query["skip"] = kwargs.get("skip", 0)
            
            return list_documents(db, business_id, query)
        
        self.register(AIFunction(
            name="search_invoices",
            description="جستجو و فیلتر کردن فاکتورها بر اساس تاریخ، نوع، مشتری و سایر فیلترها. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود. نتیجه شامل لیست فاکتورها در 'items' و تعداد کل فاکتورها در 'pagination.total' است. برای دریافت تعداد کل فاکتورها، از 'pagination.total' استفاده کنید.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع (اختیاری)"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان (اختیاری)"},
                    "document_type": {
                        "type": "string",
                        "enum": ["invoice_sales", "invoice_purchase", "invoice_sales_return"],
                        "description": "نوع فاکتور (اختیاری)"
                    },
                    "person_id": {"type": "integer", "description": "شناسه مشتری/تامین‌کننده (اختیاری)"},
                    "take": {"type": "integer", "description": "تعداد نتایج (اختیاری، پیش‌فرض: 50)"},
                    "skip": {"type": "integer", "description": "تعداد نتایج صرف‌نظر شده (اختیاری، پیش‌فرض: 0)"}
                },
                "required": []
            },
            handler=self._create_handler(search_invoices_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.read"],
            category="invoices"
        ))
    
        # اضافه کردن get_invoice_details
        def get_invoice_details_wrapper(db, business_id, user_id, invoice_id, **kwargs):
            """Wrapper برای دریافت جزئیات فاکتور"""
            from app.services.invoice_service import invoice_document_to_dict
            from adapters.db.models.document import Document
            
            document = db.query(Document).filter(
                Document.id == invoice_id,
                Document.business_id == business_id
            ).first()
            
            if not document:
                raise ValueError(f"Invoice {invoice_id} not found")
            
            # بررسی نوع سند - باید فاکتور باشد
            invoice_types = [
                "invoice_sales", "invoice_sales_return",
                "invoice_purchase", "invoice_purchase_return",
                "invoice_direct_consumption", "invoice_production", "invoice_waste"
            ]
            if document.document_type not in invoice_types:
                raise ValueError(f"Document {invoice_id} is not an invoice")
            
            return invoice_document_to_dict(db, document)
        
        self.register(AIFunction(
            name="get_invoice_details",
            description="دریافت جزئیات کامل یک فاکتور شامل اقلام، مالیات، پرداخت‌ها و سایر اطلاعات. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "invoice_id": {"type": "integer", "description": "شناسه فاکتور"}
                },
                "required": ["invoice_id"]
            },
            handler=self._create_handler(get_invoice_details_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.read"],
            category="invoices"
        ))
        
        # اضافه کردن get_invoices_count
        def get_invoices_count_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای دریافت تعداد فاکتورها"""
            from app.services.document_service import list_documents
            
            # فیلتر کردن فقط فاکتورها
            invoice_types = [
                "invoice_sales", "invoice_sales_return",
                "invoice_purchase", "invoice_purchase_return",
                "invoice_direct_consumption", "invoice_production", "invoice_waste"
            ]
            
            # ساخت query dict برای list_documents
            query = {}
            
            # document_type
            if "document_type" in kwargs:
                query["document_type"] = kwargs["document_type"]
            elif "document_types" in kwargs:
                doc_types = kwargs["document_types"]
                if isinstance(doc_types, list) and doc_types:
                    query["document_type"] = doc_types[0]
            
            # سایر فیلترها
            if "fiscal_year_id" in kwargs:
                query["fiscal_year_id"] = kwargs["fiscal_year_id"]
            if "from_date" in kwargs:
                query["from_date"] = kwargs["from_date"]
            if "to_date" in kwargs:
                query["to_date"] = kwargs["to_date"]
            if "person_id" in kwargs:
                query["person_id"] = kwargs["person_id"]
            
            # برای دریافت تعداد، فقط یک رکورد می‌خواهیم
            query["take"] = 1
            query["skip"] = 0
            
            result = list_documents(db, business_id, query)
            total = result.get("pagination", {}).get("total", 0)
            
            return {
                "total": total,
                "filters_applied": {
                    "document_type": query.get("document_type"),
                    "fiscal_year_id": query.get("fiscal_year_id"),
                    "from_date": query.get("from_date"),
                    "to_date": query.get("to_date"),
                    "person_id": query.get("person_id")
                }
            }
        
        self.register(AIFunction(
            name="get_invoices_count",
            description="دریافت تعداد کل فاکتورها بر اساس فیلترهای انتخابی (تاریخ، نوع، مشتری و غیره). شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود. این function برای پاسخ به سوالات مربوط به تعداد فاکتورها استفاده می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع (اختیاری)"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان (اختیاری)"},
                    "document_type": {
                        "type": "string",
                        "enum": ["invoice_sales", "invoice_purchase", "invoice_sales_return", "invoice_purchase_return", "invoice_direct_consumption", "invoice_production", "invoice_waste"],
                        "description": "نوع فاکتور (اختیاری)"
                    },
                    "person_id": {"type": "integer", "description": "شناسه مشتری/تامین‌کننده (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(get_invoices_count_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.read"],
            category="invoices"
        ))
        
        # اضافه کردن create_invoice
        def create_invoice_wrapper(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
            """Wrapper برای ایجاد فاکتور"""
            from app.services.invoice_service import create_invoice
            
            db: Session = context["db"]
            user_context: AuthContext = context["user_context"]
            business_id = args.get("business_id") or context.get("business_id")
            user_id = user_context.get_user_id()
            
            # ساخت data dict از args
            data = {
                "invoice_type": args.get("invoice_type"),
                "document_date": args.get("document_date"),
                "currency_id": args.get("currency_id"),
                "person_id": args.get("person_id"),
                "description": args.get("description"),
                "lines": args.get("lines", []),
                "extra_info": args.get("extra_info", {})
            }
            
            return create_invoice(db, business_id, user_id, data)
        
        self.register(AIFunction(
            name="create_invoice",
            description="ایجاد یک فاکتور جدید (فروش، خرید و غیره). شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "invoice_type": {
                        "type": "string",
                        "enum": ["invoice_sales", "invoice_purchase", "invoice_sales_return", "invoice_purchase_return"],
                        "description": "نوع فاکتور"
                    },
                    "document_date": {"type": "string", "format": "date", "description": "تاریخ فاکتور"},
                    "currency_id": {"type": "integer", "description": "شناسه ارز"},
                    "person_id": {"type": "integer", "description": "شناسه مشتری/تامین‌کننده (برای فاکتورهای طرف شخص)"},
                    "description": {"type": "string", "description": "توضیحات (اختیاری)"},
                    "lines": {
                        "type": "array",
                        "description": "اقلام فاکتور",
                        "items": {
                            "type": "object",
                            "properties": {
                                "product_id": {"type": "integer", "description": "شناسه محصول"},
                                "quantity": {"type": "number", "description": "تعداد"},
                                "unit_price": {"type": "number", "description": "قیمت واحد"},
                                "description": {"type": "string", "description": "توضیحات (اختیاری)"}
                            },
                            "required": ["product_id", "quantity", "unit_price"]
                        }
                    }
                },
                "required": ["invoice_type", "document_date", "currency_id", "lines"]
            },
            handler=create_invoice_wrapper,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.write"],
            category="invoices"
        ))
    
    def _register_product_functions(self):
        """ثبت function های مربوط به محصولات"""
        from app.services.product_service import list_products, get_product
        
        self.register(AIFunction(
            name="search_products",
            description="جستجو در محصولات و کالاها بر اساس نام، کد، دسته‌بندی و سایر فیلترها. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "متن جستجو (اختیاری)"},
                    "category_id": {"type": "integer", "description": "شناسه دسته‌بندی (اختیاری)"},
                    "item_type": {"type": "string", "enum": ["product", "service"], "description": "نوع کالا (اختیاری)"},
                    "track_inventory": {"type": "boolean", "description": "فقط کالاهای با موجودی (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(list_products),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="products"
        ))
        
        self.register(AIFunction(
            name="get_product_info",
            description="دریافت اطلاعات کامل یک محصول یا کالا. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "شناسه محصول"}
                },
                "required": ["product_id"]
            },
            handler=self._create_handler(get_product),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="products"
        ))
        
        # اضافه کردن get_inventory_status
        def get_inventory_status_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای دریافت وضعیت موجودی"""
            from app.services.warehouse_service import get_warehouse_stock_report
            
            query = {
                "product_ids": kwargs.get("product_ids", []),
                "warehouse_ids": kwargs.get("warehouse_ids", []),
                "as_of_date": kwargs.get("as_of_date"),
                "include_zero": kwargs.get("include_zero", False)
            }
            
            return get_warehouse_stock_report(db, business_id, query)
        
        self.register(AIFunction(
            name="get_inventory_status",
            description="دریافت وضعیت موجودی محصولات در انبارها. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "شناسه محصول (اختیاری - اگر مشخص نشود، لیست تمام محصولات)"},
                    "warehouse_id": {"type": "integer", "description": "شناسه انبار (اختیاری)"},
                    "as_of_date": {"type": "string", "format": "date", "description": "تاریخ محاسبه موجودی (اختیاری)"},
                    "include_zero": {"type": "boolean", "description": "نمایش محصولات با موجودی صفر (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(get_inventory_status_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="products"
        ))
        
        # اضافه کردن get_product_kardex
        def get_product_kardex_wrapper(db, business_id, user_id, product_id, **kwargs):
            """Wrapper برای دریافت کاردکس محصول"""
            from app.services.product_service import get_inventory_kardex_report
            
            result = get_inventory_kardex_report(
                db=db,
                business_id=business_id,
                fiscal_year_id=kwargs.get("fiscal_year_id"),
                date_from=kwargs.get("from_date"),
                date_to=kwargs.get("to_date"),
                product_ids=[product_id],
                warehouse_ids=[kwargs.get("warehouse_id")] if kwargs.get("warehouse_id") else None,
                category_ids=None,
                search=None,
                skip=kwargs.get("skip", 0),
                take=kwargs.get("take", 100)
            )
            
            return result
        
        self.register(AIFunction(
            name="get_product_kardex",
            description="دریافت کاردکس (گردش موجودی) یک محصول در انبار. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "شناسه محصول"},
                    "warehouse_id": {"type": "integer", "description": "شناسه انبار (اختیاری)"},
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع (اختیاری)"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان (اختیاری)"},
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"}
                },
                "required": ["product_id"]
            },
            handler=self._create_handler(get_product_kardex_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="products"
        ))
    
    def _register_person_functions(self):
        """ثبت function های مربوط به اشخاص (مشتریان/تامین‌کنندگان)"""
        from app.services.person_service import get_person_by_id, search_persons, calculate_person_balance
        from app.services.person_service import get_debtors_report, get_creditors_report
        from app.services.person_service import create_person, update_person
        from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonUpdateRequest
        
        def get_person_wrapper(db, business_id, person_id, user_id, **kwargs):
            """Wrapper برای دریافت اطلاعات شخص"""
            return get_person_by_id(db, person_id, business_id)
        
        self.register(AIFunction(
            name="get_customer_info",
            description="دریافت اطلاعات کامل یک مشتری یا تامین‌کننده شامل اطلاعات تماس، اعتبار و تاریخچه. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "person_id": {"type": "integer", "description": "شناسه مشتری یا تامین‌کننده"}
                },
                "required": ["person_id"]
            },
            handler=self._create_handler(get_person_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["persons.read"],
            category="persons"
        ))
        
        # اضافه کردن search_persons
        def search_persons_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای جستجوی اشخاص"""
            from app.services.person_service import _person_to_dict
            
            search_query = kwargs.get("search")
            page = kwargs.get("page", 1)
            limit = kwargs.get("limit", 20)
            
            persons = search_persons(db, business_id, search_query, page, limit)
            
            # تبدیل به dict با استفاده از helper function
            result = []
            for person in persons:
                person_dict = _person_to_dict(person)
                result.append(person_dict)
            
            return result
        
        self.register(AIFunction(
            name="search_persons",
            description="جستجو در مشتریان و تامین‌کنندگان بر اساس نام، کد، تلفن و سایر فیلترها. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "search": {"type": "string", "description": "متن جستجو در نام، کد، تلفن یا ایمیل (اختیاری)"},
                    "person_type": {"type": "string", "enum": ["customer", "supplier", "both"], "description": "نوع شخص (اختیاری)"},
                    "city": {"type": "string", "description": "شهر (اختیاری)"},
                    "page": {"type": "integer", "description": "شماره صفحه (اختیاری، پیش‌فرض: 1)"},
                    "limit": {"type": "integer", "description": "تعداد نتایج (اختیاری، پیش‌فرض: 20)"}
                },
                "required": []
            },
            handler=self._create_handler(search_persons_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["persons.read"],
            category="persons"
        ))
        
        # اضافه کردن get_person_balance
        def get_person_balance_wrapper(db, business_id, person_id, user_id, **kwargs):
            """Wrapper برای دریافت موجودی شخص"""
            fiscal_year_id = kwargs.get("fiscal_year_id")
            balance, status = calculate_person_balance(db, person_id, fiscal_year_id)
            
            return {
                "person_id": person_id,
                "balance": balance,
                "status": status,
                "fiscal_year_id": fiscal_year_id
            }
        
        self.register(AIFunction(
            name="get_person_balance",
            description="دریافت موجودی و بدهی/بستانکاری یک مشتری یا تامین‌کننده. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "person_id": {"type": "integer", "description": "شناسه مشتری یا تامین‌کننده"},
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"}
                },
                "required": ["person_id"]
            },
            handler=self._create_handler(get_person_balance_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["persons.read"],
            category="persons"
        ))
        
        # اضافه کردن create_person
        def create_person_wrapper(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
            """Wrapper برای ایجاد شخص"""
            from adapters.api.v1.schema_models.person import PersonCreateRequest
            from adapters.db.models.person import PersonType
            
            db: Session = context["db"]
            business_id = args.get("business_id") or context.get("business_id")
            
            # تبدیل person_type از string به PersonType enum
            person_type_enum = None
            person_types_list = None
            if args.get("person_type"):
                person_type_str = args.get("person_type").lower()
                if person_type_str == "customer":
                    person_type_enum = PersonType.CUSTOMER
                    person_types_list = [PersonType.CUSTOMER]
                elif person_type_str == "supplier":
                    person_type_enum = PersonType.SUPPLIER
                    person_types_list = [PersonType.SUPPLIER]
            
            # ساخت PersonCreateRequest از args
            # alias_name required است، از name استفاده می‌کنیم
            name = args.get("name", "")
            alias_name = name if name else "نامشخص"
            
            person_data = PersonCreateRequest(
                alias_name=alias_name,
                first_name=args.get("name"),
                code=args.get("code"),
                phone=args.get("phone"),
                email=args.get("email"),
                address=args.get("address"),
                economic_id=args.get("tax_id"),  # economic_id معادل tax_id است
                person_type=person_type_enum,
                person_types=person_types_list
            )
            
            return create_person(db, business_id, person_data)
        
        self.register(AIFunction(
            name="create_person",
            description="ایجاد یک مشتری یا تامین‌کننده جدید. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "نام شخص"},
                    "person_type": {"type": "string", "enum": ["customer", "supplier"], "description": "نوع شخص"},
                    "phone": {"type": "string", "description": "تلفن (اختیاری)"},
                    "email": {"type": "string", "format": "email", "description": "ایمیل (اختیاری)"},
                    "address": {"type": "string", "description": "آدرس (اختیاری)"},
                    "tax_id": {"type": "string", "description": "شناسه ملی/کد اقتصادی (اختیاری)"},
                    "code": {"type": "integer", "description": "کد شخص (اختیاری - در غیر این صورت خودکار تولید می‌شود)"}
                },
                "required": ["name", "person_type"]
            },
            handler=create_person_wrapper,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["persons.write"],
            category="persons"
        ))
        
        # اضافه کردن update_person
        def update_person_wrapper(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
            """Wrapper برای ویرایش شخص"""
            from adapters.api.v1.schema_models.person import PersonUpdateRequest
            
            db: Session = context["db"]
            business_id = args.get("business_id") or context.get("business_id")
            person_id = args.get("person_id")
            
            if not person_id:
                raise ValueError("person_id is required")
            
            # ساخت PersonUpdateRequest از args
            # فقط فیلدهایی که ارائه شده‌اند را set می‌کنیم
            update_data = {}
            if args.get("name"):
                update_data["alias_name"] = args.get("name")
                update_data["first_name"] = args.get("name")
            if args.get("phone"):
                update_data["phone"] = args.get("phone")
            if args.get("email"):
                update_data["email"] = args.get("email")
            if args.get("address"):
                update_data["address"] = args.get("address")
            if args.get("tax_id"):
                update_data["economic_id"] = args.get("tax_id")  # economic_id معادل tax_id است
            
            person_data = PersonUpdateRequest(**update_data)
            
            # ترتیب صحیح: update_person(db, person_id, business_id, person_data)
            return update_person(db, person_id, business_id, person_data)
        
        self.register(AIFunction(
            name="update_person",
            description="ویرایش اطلاعات یک مشتری یا تامین‌کننده. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "person_id": {"type": "integer", "description": "شناسه شخص"},
                    "name": {"type": "string", "description": "نام جدید (اختیاری)"},
                    "phone": {"type": "string", "description": "تلفن جدید (اختیاری)"},
                    "email": {"type": "string", "format": "email", "description": "ایمیل جدید (اختیاری)"},
                    "address": {"type": "string", "description": "آدرس جدید (اختیاری)"},
                    "tax_id": {"type": "string", "description": "شناسه ملی/کد اقتصادی جدید (اختیاری)"}
                },
                "required": ["person_id"]
            },
            handler=update_person_wrapper,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["persons.write"],
            category="persons"
        ))
    
    def _register_financial_functions(self):
        """ثبت function های مربوط به امور مالی"""
        from app.services.business_dashboard_service import get_business_dashboard_data
        from app.services.person_service import get_debtors_report, get_creditors_report
        from app.services.receipt_payment_service import list_receipts_payments, create_receipt_payment
        from app.services.product_service import get_sales_by_product_report
        
        def get_financial_summary_wrapper(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
            """Wrapper برای دریافت خلاصه مالی"""
            db: Session = context["db"]
            user_context: AuthContext = context["user_context"]
            business_id = args.get("business_id") or context.get("business_id")
            return get_business_dashboard_data(db, business_id, user_context)
        
        self.register(AIFunction(
            name="get_financial_summary",
            description="دریافت خلاصه مالی کسب‌وکار فعلی شامل درآمد، هزینه، موجودی و سایر آمارها. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {},
                "required": []
            },
            handler=get_financial_summary_wrapper,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="financial"
        ))
        
        # اضافه کردن get_debtors_report
        def get_debtors_report_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای گزارش بدهکاران"""
            return get_debtors_report(
                db=db,
                business_id=business_id,
                fiscal_year_id=kwargs.get("fiscal_year_id"),
                currency_id=kwargs.get("currency_id"),
                date_from=kwargs.get("date_from"),
                date_to=kwargs.get("date_to"),
                min_balance=kwargs.get("min_balance"),
                person_ids=kwargs.get("person_ids"),
                search=kwargs.get("search"),
                skip=kwargs.get("skip", 0),
                take=kwargs.get("take", 50)
            )
        
        self.register(AIFunction(
            name="get_debtors_report",
            description="گزارش بدهکاران با جزئیات بدهی و تاریخچه. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
                    "date_from": {"type": "string", "format": "date", "description": "از تاریخ (اختیاری)"},
                    "date_to": {"type": "string", "format": "date", "description": "تا تاریخ (اختیاری)"},
                    "min_balance": {"type": "number", "description": "حداقل بدهی (اختیاری)"},
                    "search": {"type": "string", "description": "جستجو در نام/کد (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(get_debtors_report_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="financial"
        ))
        
        # اضافه کردن get_creditors_report
        def get_creditors_report_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای گزارش بستانکاران"""
            return get_creditors_report(
                db=db,
                business_id=business_id,
                fiscal_year_id=kwargs.get("fiscal_year_id"),
                currency_id=kwargs.get("currency_id"),
                date_from=kwargs.get("date_from"),
                date_to=kwargs.get("date_to"),
                min_balance=kwargs.get("min_balance"),
                person_ids=kwargs.get("person_ids"),
                search=kwargs.get("search"),
                skip=kwargs.get("skip", 0),
                take=kwargs.get("take", 50)
            )
        
        self.register(AIFunction(
            name="get_creditors_report",
            description="گزارش بستانکاران با جزئیات بستانکاری و تاریخچه. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"},
                    "date_from": {"type": "string", "format": "date", "description": "از تاریخ (اختیاری)"},
                    "date_to": {"type": "string", "format": "date", "description": "تا تاریخ (اختیاری)"},
                    "min_balance": {"type": "number", "description": "حداقل بستانکاری (اختیاری)"},
                    "search": {"type": "string", "description": "جستجو در نام/کد (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(get_creditors_report_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="financial"
        ))
        
        # اضافه کردن search_receipts_payments
        def search_receipts_payments_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای جستجوی دریافت/پرداخت‌ها"""
            query = {
                "fiscal_year_id": kwargs.get("fiscal_year_id"),
                "document_type": kwargs.get("type"),  # "receipt" or "payment"
                "from_date": kwargs.get("from_date"),
                "to_date": kwargs.get("to_date"),
                "person_id": kwargs.get("person_id"),
                "account_type": kwargs.get("account_type"),  # "bank", "cash", "petty_cash"
                "take": kwargs.get("take", 50),
                "skip": kwargs.get("skip", 0)
            }
            
            return list_receipts_payments(db, business_id, query)
        
        self.register(AIFunction(
            name="search_receipts_payments",
            description="جستجو در دریافت/پرداخت‌ها بر اساس تاریخ، نوع، شخص و سایر فیلترها. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع (اختیاری)"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان (اختیاری)"},
                    "person_id": {"type": "integer", "description": "شناسه شخص (اختیاری)"},
                    "type": {"type": "string", "enum": ["receipt", "payment"], "description": "نوع: دریافت یا پرداخت (اختیاری)"},
                    "account_type": {"type": "string", "enum": ["bank", "cash", "petty_cash"], "description": "نوع حساب: بانکی، نقدی یا خرد (اختیاری)"},
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(search_receipts_payments_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["receipts_payments.read"],
            category="financial"
        ))
        
        # اضافه کردن create_receipt_payment
        def create_receipt_payment_wrapper(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
            """Wrapper برای ایجاد دریافت/پرداخت"""
            db: Session = context["db"]
            user_context: AuthContext = context["user_context"]
            business_id = args.get("business_id") or context.get("business_id")
            user_id = user_context.get_user_id()
            
            # ساخت person_lines و account_lines از پارامترها
            person_lines = []
            if args.get("person_id") and args.get("amount"):
                person_lines.append({
                    "person_id": args.get("person_id"),
                    "amount": float(args.get("amount", 0)),
                    "description": args.get("description", "")
                })
            
            account_lines = []
            if args.get("account_id") and args.get("amount"):
                account_lines.append({
                    "account_id": args.get("account_id"),
                    "amount": float(args.get("amount", 0)),
                    "description": args.get("description", "")
                })
            
            data = {
                "document_type": args.get("type"),  # "receipt" or "payment"
                "document_date": args.get("document_date"),
                "currency_id": args.get("currency_id"),
                "description": args.get("description", ""),
                "person_lines": person_lines if person_lines else args.get("person_lines", []),
                "account_lines": account_lines if account_lines else args.get("account_lines", []),
                "extra_info": args.get("extra_info", {})
            }
            
            return create_receipt_payment(db, business_id, user_id, data)
        
        self.register(AIFunction(
            name="create_receipt_payment",
            description="ثبت دریافت یا پرداخت نقدی/بانکی. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["receipt", "payment"], "description": "نوع: دریافت یا پرداخت"},
                    "document_date": {"type": "string", "format": "date", "description": "تاریخ سند"},
                    "currency_id": {"type": "integer", "description": "شناسه ارز"},
                    "person_id": {"type": "integer", "description": "شناسه شخص (اختیاری)"},
                    "amount": {"type": "number", "description": "مبلغ"},
                    "account_id": {"type": "integer", "description": "شناسه حساب بانکی/نقدی"},
                    "description": {"type": "string", "description": "توضیحات (اختیاری)"}
                },
                "required": ["type", "document_date", "currency_id", "amount", "account_id"]
            },
            handler=create_receipt_payment_wrapper,
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["receipts_payments.write"],
            category="financial"
        ))
        
        # اضافه کردن get_sales_report
        def get_sales_report_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای گزارش فروش"""
            return get_sales_by_product_report(
                db=db,
                business_id=business_id,
                fiscal_year_id=kwargs.get("fiscal_year_id"),
                currency_id=kwargs.get("currency_id"),
                date_from=kwargs.get("from_date"),
                date_to=kwargs.get("to_date"),
                product_ids=[kwargs.get("product_id")] if kwargs.get("product_id") else None,
                category_ids=[kwargs.get("category_id")] if kwargs.get("category_id") else None,
                warehouse_ids=None,
                include_zero_sales=kwargs.get("include_zero_sales", False),
                search=kwargs.get("search"),
                skip=kwargs.get("skip", 0),
                take=kwargs.get("take", 50)
            )
        
        self.register(AIFunction(
            name="get_sales_report",
            description="گزارش فروش بر اساس تاریخ، محصول، مشتری. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان"},
                    "product_id": {"type": "integer", "description": "فیلتر بر اساس محصول (اختیاری)"},
                    "person_id": {"type": "integer", "description": "فیلتر بر اساس مشتری (اختیاری)"},
                    "category_id": {"type": "integer", "description": "فیلتر بر اساس دسته‌بندی (اختیاری)"},
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"}
                },
                "required": ["from_date", "to_date"]
            },
            handler=self._create_handler(get_sales_report_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="financial"
        ))
        
        # اضافه کردن get_purchase_report
        def get_purchase_report_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای گزارش خرید"""
            from app.services.product_service import get_sales_by_product_report
            from app.services.invoice_service import INVOICE_PURCHASE
            from adapters.db.models.document import Document
            from adapters.db.models.invoice_item_line import InvoiceItemLine
            from datetime import date, datetime
            from decimal import Decimal
            from sqlalchemy import and_, or_
            
            # تبدیل تاریخ‌ها
            date_from_obj = None
            date_to_obj = None
            if kwargs.get("from_date"):
                try:
                    date_from_obj = datetime.strptime(kwargs["from_date"], '%Y-%m-%d').date()
                except ValueError:
                    pass
            if kwargs.get("to_date"):
                try:
                    date_to_obj = datetime.strptime(kwargs["to_date"], '%Y-%m-%d').date()
                except ValueError:
                    pass
            
            # دریافت فاکتورهای خرید در بازه زمانی
            purchase_invoice_query = db.query(Document).filter(
                and_(
                    Document.business_id == business_id,
                    Document.document_type == INVOICE_PURCHASE,
                    Document.is_proforma == False,
                )
            )
            
            if date_from_obj:
                purchase_invoice_query = purchase_invoice_query.filter(Document.document_date >= date_from_obj)
            if date_to_obj:
                purchase_invoice_query = purchase_invoice_query.filter(Document.document_date <= date_to_obj)
            if kwargs.get("fiscal_year_id"):
                purchase_invoice_query = purchase_invoice_query.filter(Document.fiscal_year_id == kwargs["fiscal_year_id"])
            if kwargs.get("currency_id"):
                purchase_invoice_query = purchase_invoice_query.filter(Document.currency_id == kwargs["currency_id"])
            
            purchase_invoices = purchase_invoice_query.all()
            invoice_ids = [inv.id for inv in purchase_invoices]
            
            if not invoice_ids:
                return {
                    'items': [],
                    'summary': {'total_count': 0, 'total_quantity': 0.0, 'total_amount': 0.0},
                    'pagination': {'total': 0, 'page': 1, 'per_page': 50, 'total_pages': 0, 'has_next': False, 'has_prev': False}
                }
            
            # دریافت خطوط فاکتور خرید
            purchase_lines = db.query(InvoiceItemLine).filter(
                InvoiceItemLine.document_id.in_(invoice_ids)
            ).all()
            
            # گروه‌بندی خطوط بر اساس product_id
            product_purchases = {}
            product_ids_with_purchases = set()
            
            for line in purchase_lines:
                if not line.product_id:
                    continue
                
                product_ids_with_purchases.add(line.product_id)
                
                if line.product_id not in product_purchases:
                    product_purchases[line.product_id] = {
                        'total_quantity': Decimal(0),
                        'total_amount': Decimal(0),
                        'last_purchase_date': None,
                    }
                
                qty = Decimal(str(line.quantity or 0))
                line_total = Decimal(0)
                
                extra_info = line.extra_info or {}
                if 'line_total' in extra_info and extra_info['line_total'] is not None:
                    line_total = Decimal(str(extra_info['line_total']))
                else:
                    unit_price = Decimal(str(extra_info.get('unit_price', 0) or 0))
                    line_discount = Decimal(str(extra_info.get('line_discount', 0) or 0))
                    tax_amount = Decimal(str(extra_info.get('tax_amount', 0) or 0))
                    if unit_price > 0 and qty > 0:
                        line_total = (unit_price * qty) - line_discount + tax_amount
                
                product_purchases[line.product_id]['total_quantity'] += qty
                product_purchases[line.product_id]['total_amount'] += line_total
            
            # ساخت نتایج
            items = []
            for product_id, purchase_data in product_purchases.items():
                items.append({
                    'product_id': product_id,
                    'total_quantity': float(purchase_data['total_quantity']),
                    'total_amount': float(purchase_data['total_amount']),
                    'last_purchase_date': purchase_data['last_purchase_date'].isoformat() if purchase_data['last_purchase_date'] else None
                })
            
            # Pagination
            skip = kwargs.get("skip", 0)
            take = kwargs.get("take", 50)
            total = len(items)
            paginated_items = items[skip:skip + take]
            total_pages = (total + take - 1) // take if take > 0 else 0
            current_page = (skip // take) + 1 if take > 0 else 1
            
            total_quantity_sum = sum(item.get('total_quantity', 0) for item in items)
            total_amount_sum = sum(item.get('total_amount', 0) for item in items)
            
            return {
                'items': paginated_items,
                'summary': {
                    'total_count': total,
                    'total_quantity': float(total_quantity_sum),
                    'total_amount': float(total_amount_sum),
                },
                'pagination': {
                    'total': total,
                    'page': current_page,
                    'per_page': take,
                    'total_pages': total_pages,
                    'has_next': current_page < total_pages,
                    'has_prev': current_page > 1,
                }
            }
        
        self.register(AIFunction(
            name="get_purchase_report",
            description="گزارش خرید بر اساس تاریخ، محصول، تامین‌کننده. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان"},
                    "product_id": {"type": "integer", "description": "فیلتر بر اساس محصول (اختیاری)"},
                    "person_id": {"type": "integer", "description": "فیلتر بر اساس تامین‌کننده (اختیاری)"},
                    "category_id": {"type": "integer", "description": "فیلتر بر اساس دسته‌بندی (اختیاری)"},
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"}
                },
                "required": ["from_date", "to_date"]
            },
            handler=self._create_handler(get_purchase_report_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="financial"
        ))
        
        # اضافه کردن get_inventory_valuation
        def get_inventory_valuation_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای محاسبه ارزش موجودی"""
            from app.services.warehouse_service import get_warehouse_stock_report
            from adapters.db.models.product import Product
            from decimal import Decimal
            
            # دریافت موجودی
            query = {
                "product_ids": [kwargs.get("product_id")] if kwargs.get("product_id") else [],
                "warehouse_ids": [kwargs.get("warehouse_id")] if kwargs.get("warehouse_id") else [],
                "as_of_date": kwargs.get("as_of_date"),
                "include_zero": kwargs.get("include_zero", False)
            }
            
            stock_report = get_warehouse_stock_report(db, business_id, query)
            
            # محاسبه ارزش موجودی
            total_valuation = Decimal(0)
            items = []
            
            for item in stock_report.get("items", []):
                product_id = item.get("product_id")
                quantity = Decimal(str(item.get("quantity", 0)))
                
                # دریافت محصول
                product = db.query(Product).filter(Product.id == product_id).first()
                if not product:
                    continue
                
                # قیمت تمام شده یا قیمت فروش
                cost_price = Decimal(str(product.cost_price or 0))
                if cost_price == 0:
                    cost_price = Decimal(str(product.sale_price or 0))
                
                valuation = quantity * cost_price
                total_valuation += valuation
                
                items.append({
                    "product_id": product_id,
                    "product_name": product.name,
                    "quantity": float(quantity),
                    "cost_price": float(cost_price),
                    "valuation": float(valuation)
                })
            
            return {
                "items": items,
                "total_valuation": float(total_valuation),
                "currency_id": stock_report.get("currency_id"),
                "as_of_date": kwargs.get("as_of_date")
            }
        
        self.register(AIFunction(
            name="get_inventory_valuation",
            description="محاسبه ارزش موجودی محصولات در انبار بر اساس قیمت تمام شده. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "product_id": {"type": "integer", "description": "شناسه محصول (اختیاری - اگر مشخص نشود، تمام محصولات)"},
                    "warehouse_id": {"type": "integer", "description": "شناسه انبار (اختیاری)"},
                    "as_of_date": {"type": "string", "format": "date", "description": "تاریخ محاسبه (اختیاری)"},
                    "include_zero": {"type": "boolean", "description": "نمایش محصولات با موجودی صفر (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(get_inventory_valuation_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["inventory.read"],
            category="financial"
        ))
        
        # اضافه کردن get_cash_flow
        def get_cash_flow_wrapper(db, business_id, user_id, **kwargs):
            """Wrapper برای گزارش گردش نقدی"""
            from app.services.receipt_payment_service import list_receipts_payments
            from decimal import Decimal
            
            # دریافت دریافت‌ها و پرداخت‌ها
            query_receipts = {
                "document_type": "receipt",
                "from_date": kwargs.get("from_date"),
                "to_date": kwargs.get("to_date"),
                "fiscal_year_id": kwargs.get("fiscal_year_id"),
                "take": 1000,
                "skip": 0
            }
            
            query_payments = {
                "document_type": "payment",
                "from_date": kwargs.get("from_date"),
                "to_date": kwargs.get("to_date"),
                "fiscal_year_id": kwargs.get("fiscal_year_id"),
                "take": 1000,
                "skip": 0
            }
            
            receipts_result = list_receipts_payments(db, business_id, query_receipts)
            payments_result = list_receipts_payments(db, business_id, query_payments)
            
            # محاسبه مجموع دریافت‌ها و پرداخت‌ها
            total_receipts = Decimal(0)
            total_payments = Decimal(0)
            
            for item in receipts_result.get("items", []):
                # محاسبه از account_lines یا person_lines
                extra_info = item.get("extra_info", {})
                total_receipts += Decimal(str(extra_info.get("total_amount", 0) or 0))
            
            for item in payments_result.get("items", []):
                extra_info = item.get("extra_info", {})
                total_payments += Decimal(str(extra_info.get("total_amount", 0) or 0))
            
            net_cash_flow = total_receipts - total_payments
            
            return {
                "period": {
                    "from_date": kwargs.get("from_date"),
                    "to_date": kwargs.get("to_date")
                },
                "total_receipts": float(total_receipts),
                "total_payments": float(total_payments),
                "net_cash_flow": float(net_cash_flow),
                "receipts_count": receipts_result.get("pagination", {}).get("total", 0),
                "payments_count": payments_result.get("pagination", {}).get("total", 0)
            }
        
        self.register(AIFunction(
            name="get_cash_flow",
            description="گزارش گردش نقدی شامل دریافت‌ها، پرداخت‌ها و خالص گردش نقدی. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "from_date": {"type": "string", "format": "date", "description": "تاریخ شروع"},
                    "to_date": {"type": "string", "format": "date", "description": "تاریخ پایان"},
                    "fiscal_year_id": {"type": "integer", "description": "شناسه سال مالی (اختیاری)"}
                },
                "required": ["from_date", "to_date"]
            },
            handler=self._create_handler(get_cash_flow_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["reports.read"],
            category="financial"
        ))
    
    def _register_crm_functions(self):
        """ثبت function های مربوط به CRM"""
        from sqlalchemy import func as sql_func, and_, or_
        from adapters.db.models.crm import Lead, Deal, CrmActivity, CrmProcessDefinition, CrmProcessStage
        from adapters.db.models.person import Person

        def _lead_to_dict_simple(lead: Lead) -> Dict[str, Any]:
            d = {
                "id": lead.id,
                "stage_name": lead.stage.name if lead.stage else None,
                "source_code": lead.source_code,
                "name": lead.name,
                "company_name": lead.company_name,
                "mobile": lead.mobile,
                "email": lead.email,
                "description": lead.description,
                "person_id": lead.person_id,
                "converted_at": lead.converted_at.isoformat() if lead.converted_at else None,
                "created_at": lead.created_at.isoformat() if lead.created_at else None,
            }
            return d

        def _deal_to_dict_simple(deal: Deal) -> Dict[str, Any]:
            d = {
                "id": deal.id,
                "person_name": deal.person.alias_name if deal.person else None,
                "stage_name": deal.stage.name if deal.stage else None,
                "title": deal.title,
                "amount": float(deal.amount),
                "probability_percent": deal.probability_percent,
                "expected_close_date": deal.expected_close_date.isoformat() if deal.expected_close_date else None,
                "closed_at": deal.closed_at.isoformat() if deal.closed_at else None,
                "created_at": deal.created_at.isoformat() if deal.created_at else None,
            }
            return d

        def _activity_to_dict_simple(a: CrmActivity) -> Dict[str, Any]:
            d = {
                "id": a.id,
                "activity_type": a.activity_type,
                "subject": a.subject,
                "description": a.description,
                "activity_date": a.activity_date.isoformat() if a.activity_date else None,
                "deal_id": a.deal_id,
                "created_at": a.created_at.isoformat() if a.created_at else None,
            }
            return d

        def search_leads_wrapper(db, business_id, user_id, **kwargs):
            q = db.query(Lead).filter(Lead.business_id == business_id)
            if kwargs.get("process_definition_id"):
                q = q.filter(Lead.process_definition_id == kwargs["process_definition_id"])
            if kwargs.get("stage_id"):
                q = q.filter(Lead.stage_id == kwargs["stage_id"])
            if kwargs.get("assigned_to_user_id") is not None:
                q = q.filter(Lead.assigned_to_user_id == kwargs["assigned_to_user_id"])
            search = kwargs.get("search", "").strip()
            if search:
                term = f"%{search}%"
                q = q.filter(
                    or_(
                        Lead.name.ilike(term),
                        Lead.company_name.ilike(term),
                        Lead.mobile.ilike(term),
                        Lead.email.ilike(term),
                    )
                )
            limit = kwargs.get("limit", 20)
            skip = kwargs.get("skip", 0)
            total = q.count()
            items = q.order_by(Lead.created_at.desc()).offset(skip).limit(limit).all()
            return {"items": [_lead_to_dict_simple(lead) for lead in items], "total": total}

        def get_lead_details_wrapper(db, business_id, user_id, lead_id, **kwargs):
            lead = db.query(Lead).filter(
                and_(Lead.id == lead_id, Lead.business_id == business_id)
            ).first()
            if not lead:
                raise ValueError(f"Lead {lead_id} not found")
            return _lead_to_dict_simple(lead)

        def search_deals_wrapper(db, business_id, user_id, **kwargs):
            q = db.query(Deal).filter(Deal.business_id == business_id)
            if kwargs.get("process_definition_id"):
                q = q.filter(Deal.process_definition_id == kwargs["process_definition_id"])
            if kwargs.get("stage_id"):
                q = q.filter(Deal.stage_id == kwargs["stage_id"])
            if kwargs.get("person_id"):
                q = q.filter(Deal.person_id == kwargs["person_id"])
            if kwargs.get("assigned_to_user_id") is not None:
                q = q.filter(Deal.assigned_to_user_id == kwargs["assigned_to_user_id"])
            search = kwargs.get("search", "").strip()
            if search:
                term = f"%{search}%"
                q = q.join(Deal.person).filter(
                    or_(Deal.title.ilike(term), Person.alias_name.ilike(term))
                )
            limit = kwargs.get("limit", 20)
            skip = kwargs.get("skip", 0)
            total = q.count()
            items = q.order_by(Deal.updated_at.desc()).offset(skip).limit(limit).all()
            return {"items": [_deal_to_dict_simple(dl) for dl in items], "total": total}

        def get_deal_details_wrapper(db, business_id, user_id, deal_id, **kwargs):
            deal = db.query(Deal).filter(
                and_(Deal.id == deal_id, Deal.business_id == business_id)
            ).first()
            if not deal:
                raise ValueError(f"Deal {deal_id} not found")
            return _deal_to_dict_simple(deal)

        def search_activities_wrapper(db, business_id, user_id, **kwargs):
            q = db.query(CrmActivity).filter(CrmActivity.business_id == business_id)
            if kwargs.get("person_id"):
                q = q.filter(CrmActivity.person_id == kwargs["person_id"])
            if kwargs.get("deal_id"):
                q = q.filter(CrmActivity.deal_id == kwargs["deal_id"])
            if kwargs.get("activity_type"):
                q = q.filter(CrmActivity.activity_type == kwargs["activity_type"])
            limit = kwargs.get("limit", 20)
            skip = kwargs.get("skip", 0)
            total = q.count()
            items = q.order_by(CrmActivity.activity_date.desc()).offset(skip).limit(limit).all()
            return {"items": [_activity_to_dict_simple(a) for a in items], "total": total}

        def get_crm_summary_wrapper(db, business_id, user_id, **kwargs):
            total_leads = db.query(Lead).filter(Lead.business_id == business_id).count()
            converted_leads = db.query(Lead).filter(
                Lead.business_id == business_id, Lead.person_id.isnot(None)
            ).count()
            total_deals = db.query(Deal).filter(Deal.business_id == business_id).count()
            deals_amount = (
                db.query(sql_func.coalesce(sql_func.sum(Deal.amount), 0))
                .filter(Deal.business_id == business_id)
                .scalar() or 0
            )
            closed_deals = db.query(Deal).filter(
                Deal.business_id == business_id, Deal.closed_at.isnot(None)
            ).count()
            conversion_rate = (converted_leads / total_leads * 100) if total_leads else 0
            return {
                "total_leads": total_leads,
                "converted_leads": converted_leads,
                "conversion_rate": round(conversion_rate, 1),
                "total_deals": total_deals,
                "closed_deals": closed_deals,
                "total_deals_amount": float(deals_amount),
            }

        def get_pipeline_report_wrapper(db, business_id, user_id, **kwargs):
            process_def_id = kwargs.get("process_definition_id")
            q = db.query(
                CrmProcessStage.id,
                CrmProcessStage.name,
                CrmProcessStage.order_index,
                sql_func.count(Deal.id).label("deal_count"),
                sql_func.coalesce(sql_func.sum(Deal.amount), 0).label("total_amount"),
            ).outerjoin(
                Deal, and_(Deal.stage_id == CrmProcessStage.id, Deal.business_id == business_id)
            )
            q = q.join(CrmProcessDefinition, CrmProcessDefinition.id == CrmProcessStage.process_definition_id)
            q = q.filter(
                CrmProcessDefinition.business_id == business_id,
                CrmProcessDefinition.process_type == "sales_pipeline",
            )
            if process_def_id:
                q = q.filter(CrmProcessDefinition.id == process_def_id)
            q = q.group_by(CrmProcessStage.id, CrmProcessStage.name, CrmProcessStage.order_index)
            q = q.order_by(CrmProcessStage.order_index)
            rows = q.all()
            return [
                {"stage_id": r.id, "stage_name": r.name, "order_index": r.order_index, "deal_count": r.deal_count, "total_amount": float(r.total_amount or 0)}
                for r in rows
            ]

        def get_lead_funnel_report_wrapper(db, business_id, user_id, **kwargs):
            process_def_id = kwargs.get("process_definition_id")
            q = db.query(
                CrmProcessStage.id,
                CrmProcessStage.name,
                CrmProcessStage.order_index,
                sql_func.count(Lead.id).label("lead_count"),
            ).outerjoin(
                Lead, and_(Lead.stage_id == CrmProcessStage.id, Lead.business_id == business_id)
            )
            q = q.join(CrmProcessDefinition, CrmProcessDefinition.id == CrmProcessStage.process_definition_id)
            q = q.filter(
                CrmProcessDefinition.business_id == business_id,
                CrmProcessDefinition.process_type == "lead_funnel",
            )
            if process_def_id:
                q = q.filter(CrmProcessDefinition.id == process_def_id)
            q = q.group_by(CrmProcessStage.id, CrmProcessStage.name, CrmProcessStage.order_index)
            q = q.order_by(CrmProcessStage.order_index)
            rows = q.all()
            return [
                {"stage_id": r.id, "stage_name": r.name, "order_index": r.order_index, "lead_count": r.lead_count}
                for r in rows
            ]

        self.register(AIFunction(
            name="search_leads",
            description="جستجو در سرنخ‌های CRM بر اساس مرحله، منبع، مسئول و متن جستجو. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "process_definition_id": {"type": "integer", "description": "شناسه فرایند (اختیاری)"},
                    "stage_id": {"type": "integer", "description": "شناسه مرحله (اختیاری)"},
                    "assigned_to_user_id": {"type": "integer", "description": "شناسه مسئول (اختیاری)"},
                    "search": {"type": "string", "description": "جستجو در نام، شرکت، موبایل، ایمیل (اختیاری)"},
                    "limit": {"type": "integer", "description": "تعداد نتایج (پیش‌فرض: 20)"},
                    "skip": {"type": "integer", "description": "ردیف شروع (پیش‌فرض: 0)"},
                },
                "required": [],
            },
            handler=self._create_handler(search_leads_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

        self.register(AIFunction(
            name="get_lead_details",
            description="دریافت جزئیات کامل یک سرنخ. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {"lead_id": {"type": "integer", "description": "شناسه سرنخ"}},
                "required": ["lead_id"],
            },
            handler=self._create_handler(get_lead_details_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

        self.register(AIFunction(
            name="search_deals",
            description="جستجو در فرصت‌های فروش CRM بر اساس مرحله، مشتری، مسئول و متن جستجو. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "process_definition_id": {"type": "integer", "description": "شناسه فرایند (اختیاری)"},
                    "stage_id": {"type": "integer", "description": "شناسه مرحله (اختیاری)"},
                    "person_id": {"type": "integer", "description": "شناسه مشتری (اختیاری)"},
                    "assigned_to_user_id": {"type": "integer", "description": "شناسه مسئول (اختیاری)"},
                    "search": {"type": "string", "description": "جستجو در عنوان یا نام مشتری (اختیاری)"},
                    "limit": {"type": "integer", "description": "تعداد نتایج (پیش‌فرض: 20)"},
                    "skip": {"type": "integer", "description": "ردیف شروع (پیش‌فرض: 0)"},
                },
                "required": [],
            },
            handler=self._create_handler(search_deals_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

        self.register(AIFunction(
            name="get_deal_details",
            description="دریافت جزئیات کامل یک فرصت فروش. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {"deal_id": {"type": "integer", "description": "شناسه فرصت فروش"}},
                "required": ["deal_id"],
            },
            handler=self._create_handler(get_deal_details_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

        self.register(AIFunction(
            name="search_activities",
            description="جستجو در فعالیت‌های CRM (تماس، ایمیل، جلسه، یادداشت) بر اساس شخص، فرصت و نوع. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {
                    "person_id": {"type": "integer", "description": "شناسه شخص (اختیاری)"},
                    "deal_id": {"type": "integer", "description": "شناسه فرصت فروش (اختیاری)"},
                    "activity_type": {"type": "string", "enum": ["call", "email", "meeting", "note"], "description": "نوع فعالیت (اختیاری)"},
                    "limit": {"type": "integer", "description": "تعداد نتایج (پیش‌فرض: 20)"},
                    "skip": {"type": "integer", "description": "ردیف شروع (پیش‌فرض: 0)"},
                },
                "required": [],
            },
            handler=self._create_handler(search_activities_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

        self.register(AIFunction(
            name="get_crm_summary",
            description="دریافت خلاصه CRM شامل تعداد سرنخ‌ها، فرصت‌های فروش، نرخ تبدیل و مبلغ کل. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={"type": "object", "properties": {}, "required": []},
            handler=self._create_handler(get_crm_summary_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

        self.register(AIFunction(
            name="get_pipeline_report",
            description="گزارش پایپلاین فروش: تعداد و مبلغ فرصت‌ها به تفکیک مرحله. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {"process_definition_id": {"type": "integer", "description": "شناسه فرایند پایپلاین (اختیاری)"}},
                "required": [],
            },
            handler=self._create_handler(get_pipeline_report_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

        self.register(AIFunction(
            name="get_lead_funnel_report",
            description="گزارش قیف سرنخ: تعداد سرنخ‌ها به تفکیک مرحله. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
            parameters_schema={
                "type": "object",
                "properties": {"process_definition_id": {"type": "integer", "description": "شناسه فرایند (اختیاری)"}},
                "required": [],
            },
            handler=self._create_handler(get_lead_funnel_report_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["crm.view"],
            category="crm",
        ))

    def _register_operator_functions(self):
        """ثبت function های مخصوص اپراتورهای پشتیبانی"""
        # این function ها بعداً اضافه می‌شوند
        pass
    
    def _register_admin_functions(self):
        """ثبت function های مخصوص مدیر سیستم"""
        # این function ها بعداً اضافه می‌شوند
        pass
    
    def _register_business_owner_functions(self):
        """ثبت function های مخصوص مالک کسب‌وکار"""
        # این function ها بعداً اضافه می‌شوند
        pass

    def _register_connector_functions(self):
        """فراخوانی کانکتورهای HTTP تعریف‌شده توسط کسب‌وکار."""
        from app.services.ai.ai_connector_service import invoke_connector_handler

        self.register(
            AIFunction(
                name="invoke_business_connector",
                description=(
                    "فراخوانی یک کانکتور HTTP خارجی که برای این کسب‌وکار تعریف شده "
                    "(لیست نام‌ها در system prompt). برای پارامترهای URL از query_params استفاده کن."
                ),
                parameters_schema={
                    "type": "object",
                    "properties": {
                        "connector_name": {
                            "type": "string",
                            "description": "نام یکتا کانکتور (slug)",
                        },
                        "query_params": {
                            "type": "object",
                            "description": "پارامترهای query یا جایگزین {{key}} در URL",
                        },
                        "body": {
                            "type": "object",
                            "description": "بدنه JSON برای POST",
                        },
                    },
                    "required": ["connector_name"],
                },
                handler=invoke_connector_handler,
                allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.ADMIN},
                business_context_required=True,
                category="integration",
            )
        )
    
    def _create_handler(self, service_func: Callable) -> Callable:
        """
        ایجاد wrapper برای service function ها
        این wrapper context (db, user_context) را اضافه می‌کند
        و business_id را از session inject می‌کند (امنیت)
        """
        def handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
            db: Session = context["db"]
            user_context: AuthContext = context["user_context"]
            
            # دریافت business_id از session (اولویت) یا context
            session_business_id = context.get("session_business_id")
            context_business_id = context.get("business_id")
            effective_business_id = session_business_id or context_business_id
            
            # امنیت: اگر AI یک business_id دیگر بدهد، آن را نادیده می‌گیریم
            if "business_id" in args:
                provided_business_id = args.get("business_id")
                # اگر business_id ارائه شده با session متفاوت باشد، از session استفاده می‌کنیم
                if provided_business_id != effective_business_id:
                    import logging
                    logger = logging.getLogger(__name__)
                    logger.warning(
                        f"AI attempted to use business_id {provided_business_id} "
                        f"but session has {effective_business_id}. Using session business_id."
                    )
                # همیشه از session/context استفاده می‌کنیم (امنیت)
                args["business_id"] = effective_business_id
            elif effective_business_id:
                # اگر business_id در args نیست، از context اضافه می‌کنیم
                args["business_id"] = effective_business_id
            
            # Validation: بررسی دسترسی کاربر به business_id
            if args.get("business_id") and not user_context.can_access_business(args["business_id"]):
                raise PermissionError(
                    f"User does not have access to business {args['business_id']}"
                )
            
            # اضافه کردن user_id از context
            if "user_id" not in args:
                args["user_id"] = user_context.get_user_id()
            
            # فراخوانی service function
            return service_func(db=db, **args)
        
        return handler
    
    def register(self, func: AIFunction):
        """ثبت function جدید"""
        self._functions[func.name] = func
    
    def _detect_user_role(
        self,
        user_context: AuthContext,
        business_id: Optional[int] = None
    ) -> Set[AIRole]:
        """
        تشخیص نقش کاربر بر اساس دسترسی‌ها
        """
        roles = set()
        
        # بررسی superadmin
        if user_context.is_superadmin():
            roles.add(AIRole.ADMIN)
            # SuperAdmin به همه function ها دسترسی دارد
            roles.add(AIRole.USER)
            roles.add(AIRole.OPERATOR)
            roles.add(AIRole.BUSINESS_OWNER)
            return roles
        
        # بررسی اپراتور پشتیبانی
        if user_context.can_access_support_operator():
            roles.add(AIRole.OPERATOR)
        
        # بررسی مالک کسب‌وکار
        target_business_id = business_id or user_context.business_id
        if target_business_id and user_context.is_business_owner(target_business_id):
            roles.add(AIRole.BUSINESS_OWNER)
        
        # کاربر عادی (اگر business_id دارد)
        if target_business_id and user_context.can_access_business(target_business_id):
            roles.add(AIRole.USER)
        
        return roles
    
    def get_function_definitions(
        self,
        context: Dict[str, Any],
        filter_by_category: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        دریافت لیست function definitions برای OpenAI
        فقط function هایی که کاربر دسترسی دارد را برمی‌گرداند
        """
        user_context: AuthContext = context["user_context"]
        business_id = context.get("business_id")
        
        # تشخیص نقش کاربر
        user_roles = self._detect_user_role(user_context, business_id)
        
        definitions = []
        for func in self._functions.values():
            # بررسی نقش
            if not (func.allowed_roles & user_roles):
                continue
            
            # بررسی دسترسی‌های دقیق‌تر
            if func.required_permissions:
                has_access = any(
                    user_context.has_business_permission(perm.split(".")[0], perm.split(".")[1])
                    if "." in perm and business_id else
                    user_context.has_app_permission(perm)
                    for perm in func.required_permissions
                )
                if not has_access:
                    continue
            
            # بررسی نیاز به business context
            if func.business_context_required and not business_id:
                continue
            
            # فیلتر بر اساس دسته‌بندی
            if filter_by_category and func.category != filter_by_category:
                continue
            
            definitions.append({
                "type": "function",
                "function": {
                    "name": func.name,
                    "description": func.description,
                    "parameters": func.parameters_schema
                }
            })
        
        return definitions
    
    def call_function(
        self,
        name: str,
        arguments: Dict[str, Any],
        context: Dict[str, Any]
    ) -> Any:
        """
        فراخوانی یک function با validation امنیتی
        """
        if name not in self._functions:
            raise ValueError(f"Function '{name}' not found in registry")
        
        func = self._functions[name]
        user_context: AuthContext = context["user_context"]
        
        # دریافت business_id از session (اولویت) یا context
        session_business_id = context.get("session_business_id")
        context_business_id = context.get("business_id")
        effective_business_id = session_business_id or context_business_id
        
        # امنیت: اگر AI یک business_id دیگر در arguments بدهد، validation می‌کنیم
        if "business_id" in arguments:
            provided_business_id = arguments.get("business_id")
            if provided_business_id and provided_business_id != effective_business_id:
                # بررسی دسترسی کاربر به business_id ارائه شده
                if not user_context.can_access_business(provided_business_id):
                    raise PermissionError(
                        f"User does not have access to business {provided_business_id}. "
                        f"Session business_id is {effective_business_id}"
                    )
                # اگر دسترسی دارد اما متفاوت است، warning می‌دهیم
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(
                    f"Function {name}: AI provided business_id {provided_business_id} "
                    f"but session has {effective_business_id}. "
                    f"Handler will use session business_id for security."
                )
        
        # بررسی نقش
        user_roles = self._detect_user_role(user_context, effective_business_id)
        if not (func.allowed_roles & user_roles):
            raise PermissionError(
                f"User role {user_roles} does not have access to function {name}. "
                f"Required roles: {func.allowed_roles}"
            )
        
        # بررسی دسترسی‌های دقیق‌تر
        if func.required_permissions:
            has_access = any(
                user_context.has_business_permission(perm.split(".")[0], perm.split(".")[1])
                if "." in perm and effective_business_id else
                user_context.has_app_permission(perm)
                for perm in func.required_permissions
            )
            if not has_access:
                raise PermissionError(f"User does not have required permissions for {name}")
        
        # بررسی business context
        if func.business_context_required and not effective_business_id:
            raise ValueError(f"Function {name} requires business context")
        
        # فراخوانی handler (handler خودش business_id را از session inject می‌کند)
        return func.handler(arguments, context)


# Singleton instance
registry = AIFunctionRegistry()

