"""
Repository برای مدیریت اسناد حسابداری (Documents)
"""

from __future__ import annotations

from typing import Optional, List, Dict, Any
from copy import deepcopy
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import select, and_, or_, func, desc, asc
from datetime import date

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.business import Business
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.currency import Currency
from adapters.db.models.user import User
from adapters.db.models.account import Account
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.check import Check


class DocumentRepository:
    """Repository برای عملیات پایگاه داده مربوط به اسناد حسابداری"""

    def __init__(self, db: Session) -> None:
        self.db = db

    def get_document(self, document_id: int) -> Optional[Document]:
        """دریافت یک سند با شناسه"""
        return self.db.query(Document).filter(Document.id == document_id).first()

    def get_document_with_relations(self, document_id: int) -> Optional[Document]:
        """دریافت سند با روابط (eager loading)"""
        return (
            self.db.query(Document)
            .options(
                joinedload(Document.business),
                joinedload(Document.fiscal_year),
                joinedload(Document.currency),
                joinedload(Document.created_by),
                joinedload(Document.lines),
            )
            .filter(Document.id == document_id)
            .first()
        )

    def list_documents_with_filters(
        self,
        business_id: int,
        filters: Dict[str, Any],
    ) -> tuple[List[Dict[str, Any]], int]:
        """
        لیست اسناد با فیلترها و صفحه‌بندی
        
        Args:
            business_id: شناسه کسب‌وکار
            filters: دیکشنری فیلترها شامل:
                - document_type: نوع سند
                - fiscal_year_id: شناسه سال مالی
                - from_date: از تاریخ
                - to_date: تا تاریخ
                - currency_id: شناسه ارز
                - is_proforma: پیش‌فاکتور یا نه
                - search: عبارت جستجو
                - sort_by: فیلد مرتب‌سازی
                - sort_desc: ترتیب نزولی
                - take: تعداد رکورد
                - skip: تعداد رکورد صرف‌نظر شده
        
        Returns:
            tuple: (لیست اسناد, تعداد کل)
        """
        # Query پایه
        # Import Project model
        from adapters.db.models.project import Project
        
        query = self.db.query(
            Document.id,
            Document.code,
            Document.business_id,
            Document.fiscal_year_id,
            Document.currency_id,
            Document.created_by_user_id,
            Document.registered_at,
            Document.document_date,
            Document.document_type,
            Document.is_proforma,
            Document.description,
            Document.project_id,
            Document.created_at,
            Document.updated_at,
            Business.name.label("business_title"),
            FiscalYear.title.label("fiscal_year_title"),
            Currency.code.label("currency_code"),
            Currency.symbol.label("currency_symbol"),
            (User.first_name + " " + User.last_name).label("created_by_name"),
            Project.name.label("project_name"),
        ).select_from(Document).join(
            Business, Document.business_id == Business.id
        ).join(
            FiscalYear, Document.fiscal_year_id == FiscalYear.id
        ).join(
            Currency, Document.currency_id == Currency.id
        ).join(
            User, Document.created_by_user_id == User.id
        ).outerjoin(
            Project, Document.project_id == Project.id
        ).filter(
            Document.business_id == business_id
        )

        # اعمال فیلترها
        if filters.get("document_type"):
            query = query.filter(Document.document_type == filters["document_type"])

        if filters.get("fiscal_year_id"):
            query = query.filter(Document.fiscal_year_id == filters["fiscal_year_id"])

        if filters.get("from_date"):
            try:
                from_date = self._parse_date(filters["from_date"])
                query = query.filter(Document.document_date >= from_date)
            except Exception:
                pass

        if filters.get("to_date"):
            try:
                to_date = self._parse_date(filters["to_date"])
                query = query.filter(Document.document_date <= to_date)
            except Exception:
                pass

        if filters.get("currency_id"):
            query = query.filter(Document.currency_id == filters["currency_id"])

        if filters.get("is_proforma") is not None:
            query = query.filter(Document.is_proforma == filters["is_proforma"])

        # جستجو
        if filters.get("search"):
            search_term = f"%{filters['search']}%"
            query = query.filter(
                or_(
                    Document.code.ilike(search_term),
                    Document.description.ilike(search_term),
                )
            )

        # شمارش کل
        total_count = query.count()

        # مرتب‌سازی (چندستونه sort یا تک‌ستونه sort_by)
        from adapters.api.v1.schemas import QueryInfo
        from app.services.document_list_sort import apply_document_accounting_list_ordering

        _qi = QueryInfo.model_validate({
            "take": int(filters.get("take", 50) or 50),
            "skip": int(filters.get("skip", 0) or 0),
            "sort_by": filters.get("sort_by"),
            "sort_desc": bool(filters.get("sort_desc", True)),
            "sort": filters.get("sort") if isinstance(filters.get("sort"), list) else None,
        })
        query = apply_document_accounting_list_ordering(query, _qi)

        # صفحه‌بندی
        skip = filters.get("skip", 0)
        take = filters.get("take", 50)
        query = query.offset(skip).limit(take)

        # اجرای query
        results = query.all()

        # محاسبه مجموع بدهکار و بستانکار برای هر سند
        def _get_document_type_name(doc_type: str | None) -> str:
            """تبدیل document_type به نام چندزبانه"""
            if not doc_type:
                return ""
            doc_type = doc_type.strip()
            mapping = {
                "invoice_sales": "فروش",
                "invoice_sales_return": "برگشت از فروش",
                "invoice_purchase": "خرید",
                "invoice_purchase_return": "برگشت از خرید",
                "invoice_direct_consumption": "مصرف مستقیم",
                "invoice_production": "تولید",
                "invoice_waste": "ضایعات",
                "inventory_transfer": "انتقال موجودی",
                "production": "تولید",
                "opening_balance": "موجودی اولیه",
                "expense": "هزینه",
                "income": "درآمد",
                "receipt": "دریافت",
                "payment": "پرداخت",
                "transfer": "انتقال",
                "manual": "سند دستی",
                "invoice": "فاکتور",
                "check": "چک",
            }
            return mapping.get(doc_type, doc_type)

        documents = []
        for row in results:
            doc_type = row.document_type
            doc_dict = {
                "id": row.id,
                "code": row.code,
                "business_id": row.business_id,
                "fiscal_year_id": row.fiscal_year_id,
                "currency_id": row.currency_id,
                "created_by_user_id": row.created_by_user_id,
                "registered_at": row.registered_at,
                "document_date": row.document_date,
                "document_type": doc_type,
                "document_type_name": _get_document_type_name(doc_type),
                "is_proforma": row.is_proforma,
                "description": row.description,
                "project_id": row.project_id,
                "project_name": row.project_name,
                "created_at": row.created_at,
                "updated_at": row.updated_at,
                "business_title": row.business_title,
                "fiscal_year_title": row.fiscal_year_title,
                "currency_code": row.currency_code,
                "currency_symbol": row.currency_symbol,
                "created_by_name": row.created_by_name,
            }

            # محاسبه مجموع
            totals = (
                self.db.query(
                    func.sum(DocumentLine.debit).label("total_debit"),
                    func.sum(DocumentLine.credit).label("total_credit"),
                    func.count(DocumentLine.id).label("lines_count"),
                )
                .filter(DocumentLine.document_id == row.id)
                .first()
            )

            doc_dict["total_debit"] = float(totals.total_debit or 0)
            doc_dict["total_credit"] = float(totals.total_credit or 0)
            doc_dict["lines_count"] = totals.lines_count or 0

            documents.append(doc_dict)

        return documents, total_count

    def get_document_details(self, document_id: int) -> Optional[Dict[str, Any]]:
        """دریافت جزئیات کامل سند شامل سطرها"""
        document = self.get_document_with_relations(document_id)
        if not document:
            return None

        return self.to_dict_with_lines(document)

    def delete_document(self, document_id: int) -> bool:
        """حذف سند"""
        document = self.get_document(document_id)
        if not document:
            return False

        self.db.delete(document)
        self.db.commit()
        return True

    @staticmethod
    def _normalize_extra_info_for_response(extra_info: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """نرمال‌سازی extra_info برای پاسخ API تا فیلدهای عددی (مثل person_id) به صورت int برگردند."""
        if not extra_info or not isinstance(extra_info, dict):
            return extra_info
        out = deepcopy(extra_info)
        pid = out.get("person_id")
        if pid is not None:
            try:
                out["person_id"] = int(pid)
            except (TypeError, ValueError):
                pass
        links = out.get("links")
        if isinstance(links, dict):
            links = dict(links)
            for key in ("warehouse_document_ids", "receipt_payment_document_ids"):
                arr = links.get(key)
                if isinstance(arr, list):
                    normalized = []
                    for x in arr:
                        try:
                            normalized.append(int(x))
                        except (TypeError, ValueError):
                            normalized.append(x)
                    links[key] = normalized
            out["links"] = links
        return out

    def to_dict(self, document: Document) -> Dict[str, Any]:
        """تبدیل Document به dictionary (بدون سطرها)"""
        return {
            "id": document.id,
            "code": document.code,
            "business_id": document.business_id,
            "fiscal_year_id": document.fiscal_year_id,
            "currency_id": document.currency_id,
            "created_by_user_id": document.created_by_user_id,
            "registered_at": document.registered_at,
            "document_date": document.document_date,
            "document_type": document.document_type,
            "is_proforma": document.is_proforma,
            "description": document.description,
            "project_id": document.project_id,
            "extra_info": self._normalize_extra_info_for_response(document.extra_info),
            "developer_settings": document.developer_settings,
            "created_at": document.created_at,
            "updated_at": document.updated_at,
        }

    def to_dict_with_lines(self, document: Document) -> Dict[str, Any]:
        """تبدیل Document به dictionary (با سطرها و جزئیات کامل)"""
        doc_dict = self.to_dict(document)

        # اضافه کردن اطلاعات روابط
        if document.business:
            doc_dict["business_title"] = document.business.name

        if document.fiscal_year:
            doc_dict["fiscal_year_title"] = document.fiscal_year.title

        if document.currency:
            doc_dict["currency_code"] = document.currency.code
            doc_dict["currency_symbol"] = document.currency.symbol

        if document.created_by:
            doc_dict["created_by_name"] = (
                f"{document.created_by.first_name} {document.created_by.last_name}"
            )

        # اضافه کردن سطرهای سند
        lines = []
        total_debit = 0
        total_credit = 0

        for line in document.lines:
            line_dict = self._document_line_to_dict(line)
            lines.append(line_dict)
            total_debit += float(line.debit or 0)
            total_credit += float(line.credit or 0)

        doc_dict["lines"] = lines
        doc_dict["total_debit"] = total_debit
        doc_dict["total_credit"] = total_credit
        doc_dict["lines_count"] = len(lines)

        return doc_dict

    def _document_line_to_dict(self, line: DocumentLine) -> Dict[str, Any]:
        """تبدیل DocumentLine به dictionary"""
        line_dict = {
            "id": line.id,
            "document_id": line.document_id,
            "account_id": line.account_id,
            "person_id": line.person_id,
            "product_id": line.product_id,
            "bank_account_id": line.bank_account_id,
            "cash_register_id": line.cash_register_id,
            "petty_cash_id": line.petty_cash_id,
            "check_id": line.check_id,
            "quantity": float(line.quantity) if line.quantity else None,
            "debit": float(line.debit or 0),
            "credit": float(line.credit or 0),
            "description": line.description,
            "extra_info": line.extra_info,
            "created_at": line.created_at,
            "updated_at": line.updated_at,
        }

        # اضافه کردن اطلاعات روابط
        if line.account:
            line_dict["account_code"] = line.account.code
            line_dict["account_name"] = line.account.name

        if line.person:
            line_dict["person_name"] = line.person.alias_name

        if line.product:
            line_dict["product_name"] = line.product.name

        if line.bank_account:
            line_dict["bank_account_name"] = line.bank_account.name

        if line.cash_register:
            line_dict["cash_register_name"] = line.cash_register.name

        if line.petty_cash:
            line_dict["petty_cash_name"] = line.petty_cash.name

        if line.check:
            line_dict["check_number"] = line.check.check_number

        return line_dict

    def _parse_date(self, date_value: Any) -> date:
        """تبدیل مقدار به date"""
        if isinstance(date_value, date):
            return date_value
        if isinstance(date_value, str):
            from datetime import datetime
            return datetime.fromisoformat(date_value.split("T")[0]).date()
        raise ValueError(f"Invalid date format: {date_value}")

    def create_document(self, document_data: Dict[str, Any]) -> Document:
        """
        ایجاد سند جدید
        
        Args:
            document_data: دیکشنری حاوی اطلاعات سند و سطرها
        
        Returns:
            Document ایجاد شده
        """
        # جداسازی سطرها از اطلاعات سند
        lines_data = document_data.pop("lines", [])
        
        # ایجاد سند
        document = Document(**document_data)
        self.db.add(document)
        self.db.flush()  # برای دریافت ID سند
        
        # ایجاد سطرهای سند
        for line_data in lines_data:
            line = DocumentLine(
                document_id=document.id,
                **line_data
            )
            self.db.add(line)
        
        self.db.commit()
        self.db.refresh(document)
        
        return document

    def update_document(
        self, 
        document_id: int, 
        document_data: Dict[str, Any]
    ) -> Optional[Document]:
        """
        ویرایش سند موجود
        
        Args:
            document_id: شناسه سند
            document_data: دیکشنری حاوی اطلاعات جدید سند و سطرها
        
        Returns:
            Document ویرایش شده یا None
        """
        document = self.get_document(document_id)
        if not document:
            return None
        
        # جداسازی سطرها
        lines_data = document_data.pop("lines", None)
        
        # ویرایش فیلدهای سند
        for key, value in document_data.items():
            if value is not None and hasattr(document, key):
                setattr(document, key, value)
        
        # اگر سطرها ارسال شده، آن‌ها را جایگزین کن
        if lines_data is not None:
            # حذف سطرهای قدیمی
            for old_line in document.lines:
                self.db.delete(old_line)
            self.db.flush()
            
            # ایجاد سطرهای جدید
            for line_data in lines_data:
                line_id = line_data.pop("id", None)
                line = DocumentLine(
                    document_id=document.id,
                    **line_data
                )
                self.db.add(line)
        
        self.db.commit()
        self.db.refresh(document)
        
        return document

    def generate_document_code(
        self, 
        business_id: int, 
        document_type: str = "manual"
    ) -> str:
        """
        تولید کد خودکار برای سند
        
        Args:
            business_id: شناسه کسب‌وکار
            document_type: نوع سند
        
        Returns:
            کد یکتای سند
        """
        from datetime import datetime
        
        # دریافت آخرین کد سند
        last_doc = (
            self.db.query(Document)
            .filter(
                Document.business_id == business_id,
                Document.document_type == document_type
            )
            .order_by(desc(Document.id))
            .first()
        )
        
        if last_doc and last_doc.code:
            try:
                # استخراج عدد از آخر کد
                import re
                numbers = re.findall(r'\d+', last_doc.code)
                if numbers:
                    last_number = int(numbers[-1])
                    return f"{document_type.upper()}-{last_number + 1:05d}"
            except Exception:
                pass
        
        # اگر سند قبلی نداشت یا فرمت نامعتبر بود
        year = datetime.now().year % 100  # دو رقم آخر سال
        return f"{document_type.upper()}-{year}{1:04d}"

    def validate_document_balance(self, lines_data: List[Dict[str, Any]]) -> tuple[bool, str]:
        """
        اعتبارسنجی متوازن بودن سند
        
        Args:
            lines_data: لیست سطرهای سند
        
        Returns:
            tuple: (متوازن است؟, پیام خطا)
        """
        if not lines_data or len(lines_data) < 2:
            return False, "سند باید حداقل 2 سطر داشته باشد"
        
        total_debit = sum(float(line.get("debit", 0)) for line in lines_data)
        total_credit = sum(float(line.get("credit", 0)) for line in lines_data)
        
        # تلرانس برای خطاهای اعشاری
        tolerance = 0.01
        if abs(total_debit - total_credit) > tolerance:
            diff = total_debit - total_credit
            return False, f"سند متوازن نیست. تفاوت: {diff:,.2f}"
        
        # حداقل یک سطر باید بدهکار و یک سطر بستانکار داشته باشد
        has_debit = any(float(line.get("debit", 0)) > 0 for line in lines_data)
        has_credit = any(float(line.get("credit", 0)) > 0 for line in lines_data)
        
        if not has_debit or not has_credit:
            return False, "سند باید حداقل یک سطر بدهکار و یک سطر بستانکار داشته باشد"
        
        # هر سطر باید یا بدهکار یا بستانکار داشته باشد (نه هر دو صفر)
        for i, line in enumerate(lines_data, 1):
            debit = float(line.get("debit", 0))
            credit = float(line.get("credit", 0))
            if debit == 0 and credit == 0:
                return False, f"سطر {i} باید مقدار بدهکار یا بستانکار داشته باشد"
            # نمی‌تواند هم بدهکار هم بستانکار داشته باشد
            if debit > 0 and credit > 0:
                return False, f"سطر {i} نمی‌تواند همزمان بدهکار و بستانکار داشته باشد"
        
        return True, ""

