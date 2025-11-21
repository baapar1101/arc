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
        # Operator functions
        self._register_operator_functions()
        # Admin functions
        self._register_admin_functions()
        # Business owner functions
        self._register_business_owner_functions()
    
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
            description="جستجو و فیلتر کردن فاکتورها بر اساس تاریخ، نوع، مشتری و سایر فیلترها. شناسه کسب‌وکار به صورت خودکار از جلسه گفت‌وگو گرفته می‌شود.",
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
                    "person_id": {"type": "integer", "description": "شناسه مشتری/تامین‌کننده (اختیاری)"}
                },
                "required": []
            },
            handler=self._create_handler(search_invoices_wrapper),
            allowed_roles={AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN},
            required_permissions=["invoices.read"],
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
    
    def _register_person_functions(self):
        """ثبت function های مربوط به اشخاص (مشتریان/تامین‌کنندگان)"""
        from app.services.person_service import get_person_by_id
        
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
    
    def _register_financial_functions(self):
        """ثبت function های مربوط به امور مالی"""
        from app.services.business_dashboard_service import get_business_dashboard_data
        
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

