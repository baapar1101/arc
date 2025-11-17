from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Request, Body
from fastapi.responses import Response
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
import io
import json
import datetime
import re
import base64
from pathlib import Path
import logging

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_management_dep
from app.core.responses import success_response, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.currency import Currency
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.business import Business
from adapters.db.models.business_print_settings import BusinessPrintSettings
from adapters.db.models.user import User
from app.core.responses import ApiError
from app.services.invoice_service import (
    create_invoice,
    update_invoice,
    delete_invoice,
    invoice_document_to_dict,
    SUPPORTED_INVOICE_TYPES,
    get_invoice_installment_plan,
    search_installments,
    export_installments_csv,
)
from app.services.pdf.template_renderer import render_template
from app.core.calendar import CalendarConverter
from adapters.db.models.person import Person
from app.services.receipt_payment_service import get_receipt_payment
from app.services.file_storage_service import FileStorageService
from app.services.person_service import calculate_person_balance
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from sqlalchemy import func


logger = logging.getLogger(__name__)

router = APIRouter(prefix="/invoices", tags=["invoices"])  # Stubs only


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_invoice_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    result = create_invoice(
        db=db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        data=payload,
    )
    return success_response(data=result, request=request, message="INVOICE_CREATED")


@router.get("/business/{business_id}/{invoice_id}/installments")
@require_business_access("business_id")
def get_invoice_installments_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data = get_invoice_installment_plan(db=db, business_id=business_id, invoice_id=invoice_id)
    return success_response(data=data, request=request, message="INSTALLMENT_PLAN_FETCHED")


@router.post("/business/{business_id}/installments/search")
@require_business_access("business_id")
def search_installments_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    جستجوی اقساط با فیلترهای:
    {
      "fiscal_year_id": int?,
      "due_from": "YYYY-MM-DD"?,
      "due_to": "YYYY-MM-DD"?,
      "status": "pending|partial|paid|overdue"?,
      "person_id": int?,
      "invoice_id": int?,
      "take": 200,
      "skip": 0
    }
    """
    result = search_installments(db=db, business_id=business_id, query=payload or {})
    return success_response(data=result, request=request, message="INSTALLMENTS_LIST_FETCHED")


@router.post("/business/{business_id}/installments/export/excel")
@require_business_access("business_id")
def export_installments_excel_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Response:
    """
    خروجی XLSX از اقساط (در صورت نبودن کتابخانه، CSV بازگردانده می‌شود).
    """
    content, mime, ext = export_installments_xlsx(db=db, business_id=business_id, query=payload or {})
    filename = f"installments_{business_id}.{ext}"
    headers = {
        "Content-Disposition": f'attachment; filename="{filename}"',
        "Content-Type": mime,
    }
    return Response(content=content, media_type=mime, headers=headers)


@router.put("/business/{business_id}/{invoice_id}")
@require_business_access("business_id")
def update_invoice_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    # Optional safety: ensure ownership
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        # Lazy import to avoid circular
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
    result = update_invoice(
        db=db,
        document_id=invoice_id,
        user_id=ctx.get_user_id(),
        data=payload,
    )
    return success_response(data=result, request=request, message="INVOICE_UPDATED")


@router.delete(
    "/business/{business_id}/{invoice_id}",
    summary="حذف فاکتور",
    description="حذف یک فاکتور",
)
@require_business_access("business_id")
def delete_invoice_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_management_dep),
) -> Dict[str, Any]:
    """حذف یک فاکتور"""
    # بررسی مالکیت
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
    
    # حذف فاکتور
    success = delete_invoice(db, invoice_id)
    
    if not success:
        from app.core.responses import ApiError
        raise ApiError("DELETE_FAILED", "Failed to delete invoice", http_status=500)
    
    return success_response(
        data={"deleted": True, "invoice_id": invoice_id},
        request=request,
        message="INVOICE_DELETED"
    )


@router.get("/business/{business_id}/{invoice_id}")
@require_business_access("business_id")
def get_invoice_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
    result = invoice_document_to_dict(db, doc)
    return success_response(data={"item": result}, request=request, message="INVOICE")

@router.get(
    "/business/{business_id}/{invoice_id}/pdf",
    summary="PDF یک فاکتور",
    description="دریافت فایل PDF یک فاکتور با پشتیبانی از قالب سفارشی (invoices/detail)",
)
@require_business_access("business_id")
async def export_single_invoice_pdf(
    business_id: int,
    invoice_id: int,
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    template_id: int | None = None,
):
    """
    خروجی PDF تک‌سند فاکتور با پشتیبانی از قالب سفارشی:
    - اگر template_id داده شود و منتشرشده باشد، همان استفاده می‌شود.
    - در غیر این صورت اگر قالب پیش‌فرض منتشرشده برای invoices/detail موجود باشد، استفاده می‌شود.
    - در نبود قالب، خروجی HTML پیش‌فرض تولید می‌شود.
    """
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    import datetime

    # دریافت سند و اعتبارسنجی
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)

    # جزئیات کامل فاکتور (به‌صورت دیکشنری قابل ارسال به قالب)
    item = invoice_document_to_dict(db, doc)
    item = dict(item or {})

    # اطلاعات کسب‌وکار (اختیاری) + فایل‌های گرافیکی (لوگو/مهر) و امضای مالک
    business_name = ""
    business_info: Dict[str, Any] = {}
    business_logo_data_uri: Optional[str] = None
    business_stamp_data_uri: Optional[str] = None
    owner_signature_data_uri: Optional[str] = None

    storage = FileStorageService(db)

    async def _load_image_data_uri(file_id_str: Optional[str]) -> Optional[str]:
        """دریافت داده فایل و تبدیل به data URI برای استفاده در HTML/PDF."""
        if not file_id_str:
            return None
        try:
            from uuid import UUID

            try:
                file_data = await storage.download_file(UUID(str(file_id_str)))
            except Exception:
                # در صورت بروز خطا، None برمی‌گردانیم تا قالب بدون تصویر ادامه دهد
                return None
            content: bytes = file_data.get("content") or b""
            if not content:
                return None
            mime = file_data.get("mime_type") or "image/png"
            b64 = base64.b64encode(content).decode("ascii")
            return f"data:{mime};base64,{b64}"
        except Exception:
            return None

    # تنظیمات چاپ کسب‌وکار (لوگو، مهر، پرداخت‌ها، اقساط و متن انتهایی)
    # یک کانفیگ پیش‌فرض تعریف می‌کنیم تا در صورت بروز خطا یا نبود کسب‌وکار، همچنان در دسترس باشد
    print_settings: Dict[str, Any] = {
        "show_logo": True,
        "show_stamp": True,
        "show_payments": True,
        "show_installment_plan": True,
        "footer_note": None,
    }
    invoice_footer_note: Optional[str] = None

    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
            # اطلاعات اقتصادی و تماس کسب‌وکار
            economic_id = getattr(b, "economic_id", None)
            economic_code = getattr(b, "economic_code", None)
            business_info = {
                "name": getattr(b, "name", None),
                # برای سازگاری با قالب‌های قدیمی
                "economic_id": economic_id or economic_code,
                "economic_code": economic_code or economic_id,
                "national_id": getattr(b, "national_id", None),
                "registration_number": getattr(b, "registration_number", None),
                "address": getattr(b, "address", None),
                "postal_code": getattr(b, "postal_code", None),
                "phone": getattr(b, "phone", None),
                "mobile": getattr(b, "mobile", None),
            }

            # ابتدا تنظیمات چاپ را (در صورت وجود) برای این کسب‌وکار و نوع سند می‌خوانیم
            try:
                print_rows = (
                    db.query(BusinessPrintSettings)
                    .filter(BusinessPrintSettings.business_id == business_id)
                    .all()
                )
            except Exception:
                print_rows = []

            def _pick_print_settings() -> dict:
                # از print_settings فعلی به‌عنوان مقدار اولیه استفاده می‌کنیم
                default_cfg = dict(print_settings)
                per_type_cfg = None
                for r in print_rows:
                    if r.document_type == "all":
                        default_cfg = {
                            "show_logo": bool(getattr(r, "show_logo", True)),
                            "show_stamp": bool(getattr(r, "show_stamp", True)),
                            "show_payments": bool(getattr(r, "show_payments", True)),
                            "show_installment_plan": bool(
                                getattr(r, "show_installment_plan", True)
                            ),
                            "footer_note": getattr(r, "footer_note", None),
                        }
                    elif r.document_type == doc.document_type:
                        per_type_cfg = {
                            "show_logo": bool(getattr(r, "show_logo", True)),
                            "show_stamp": bool(getattr(r, "show_stamp", True)),
                            "show_payments": bool(getattr(r, "show_payments", True)),
                            "show_installment_plan": bool(
                                getattr(r, "show_installment_plan", True)
                            ),
                            "footer_note": getattr(r, "footer_note", None),
                        }
                if per_type_cfg is None:
                    return default_cfg
                # per_type روی default override می‌شود
                merged = dict(default_cfg)
                merged.update({k: v for k, v in per_type_cfg.items() if v is not None})
                return merged

            print_settings = _pick_print_settings()

            # لوگو و مهر کسب‌وکار بر اساس تنظیمات چاپ
            if print_settings.get("show_logo", True):
                business_logo_data_uri = await _load_image_data_uri(
                    getattr(b, "logo_file_id", None)
                )
            else:
                business_logo_data_uri = None

            if print_settings.get("show_stamp", True):
                business_stamp_data_uri = await _load_image_data_uri(
                    getattr(b, "stamp_file_id", None)
                )
            else:
                business_stamp_data_uri = None

            # امضای مالک کسب‌وکار (بر اساس owner_id) فقط اگر show_stamp فعال باشد
            try:
                owner_user = db.query(User).filter(User.id == b.owner_id).first()
            except Exception:
                owner_user = None
            if owner_user is not None and print_settings.get("show_stamp", True):
                owner_signature_data_uri = await _load_image_data_uri(
                    getattr(owner_user, "signature_file_id", None)
                )

            invoice_footer_note = print_settings.get("footer_note")
    except Exception:
        business_name = ""
        business_info = {}
        business_logo_data_uri = None
        business_stamp_data_uri = None
        owner_signature_data_uri = None
        invoice_footer_note = None

    # Locale و نوع تقویم
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    calendar_header = (request.headers.get("X-Calendar-Type") or "").strip().lower()
    calendar_type = calendar_header or ("jalali" if is_fa else "gregorian")

    # تاریخ فاکتور با هر دو فرمت
    invoice_date_raw = item.get("document_date")
    invoice_date_jalali = None
    invoice_date_gregorian = None
    if invoice_date_raw:
        try:
            dt = datetime.datetime.fromisoformat(str(invoice_date_raw).replace("Z", "+00:00"))
            jalali = CalendarConverter.format_datetime(dt, "jalali")
            greg = CalendarConverter.format_datetime(dt, "gregorian")
            # فقط تاریخ بدون زمان را برای نمایش استفاده می‌کنیم
            invoice_date_jalali = jalali.get("date_only") or jalali.get("formatted", "")
            invoice_date_gregorian = greg.get("date_only") or greg.get("formatted", "")
        except Exception:
            invoice_date_gregorian = str(invoice_date_raw)

    if calendar_type == "jalali" and invoice_date_jalali:
        invoice_date_display = invoice_date_jalali
    else:
        invoice_date_display = invoice_date_gregorian or invoice_date_raw

    # نوع فاکتور به‌صورت خوانا
    def _type_name(tp: str) -> str:
        mapping = {
            "invoice_sales": ("فروش" if is_fa else "Sales"),
            "invoice_sales_return": ("برگشت از فروش" if is_fa else "Sales return"),
            "invoice_purchase": ("خرید" if is_fa else "Purchase"),
            "invoice_purchase_return": ("برگشت از خرید" if is_fa else "Purchase return"),
            "invoice_direct_consumption": ("مصرف مستقیم" if is_fa else "Direct consumption"),
            "invoice_production": ("تولید" if is_fa else "Production"),
            "invoice_waste": ("ضایعات" if is_fa else "Waste"),
        }
        return mapping.get(str(tp), str(tp))

    invoice_type_name = _type_name(item.get("document_type"))
    is_proforma = bool(item.get("is_proforma"))

    # اطلاعات طرف حساب (خریدار/فروشنده) بر اساس نوع فاکتور
    extra = item.get("extra_info") or {}
    person_id = extra.get("person_id")
    buyer_info: Dict[str, Any] = {}
    seller_info: Dict[str, Any] = {}

    person_obj = None
    try:
        if person_id is not None:
            person_obj = db.query(Person).filter(Person.id == int(person_id)).first()
    except Exception:
        person_obj = None

    person_info: Dict[str, Any] = {}
    if person_obj is not None:
        # اطلاعات اقتصادی و هویتی شخص (با پشتیبانی از فیلدهای قدیمی و جدید)
        national_id = getattr(person_obj, "national_id", None)
        national_code = getattr(person_obj, "national_code", None)
        registration_number = getattr(person_obj, "registration_number", None)
        economic_id = getattr(person_obj, "economic_id", None)
        economic_code = getattr(person_obj, "economic_code", None)

        person_info = {
            "id": getattr(person_obj, "id", None),
            "code": getattr(person_obj, "code", None),
            "name": getattr(person_obj, "display_name", None) or getattr(person_obj, "name", None),
            # برای سازگاری با قالب‌های قدیمی، هر دو کلید نگه داشته می‌شوند
            "national_id": national_id or national_code,
            "national_code": national_code or national_id,
            "registration_number": registration_number,
            "economic_id": economic_id or economic_code,
            "economic_code": economic_code or economic_id,
            "address": getattr(person_obj, "address", None),
            "postal_code": getattr(person_obj, "postal_code", None),
            "mobile": getattr(person_obj, "mobile", None),
            "phone": getattr(person_obj, "phone", None),
        }

    inv_type = str(item.get("document_type") or "")
    # برای فروش، کسب‌وکار فروشنده و شخص خریدار است
    if inv_type in ("invoice_sales", "invoice_sales_return"):
        seller_info = business_info if business_info else {"name": business_name}
        buyer_info = person_info if person_info else {}
    # برای خرید، شخص فروشنده و کسب‌وکار خریدار است
    elif inv_type in ("invoice_purchase", "invoice_purchase_return"):
        seller_info = person_info if person_info else {}
        buyer_info = business_info if business_info else {"name": business_name}
    else:
        # سایر انواع: فقط کسب‌وکار را به‌عنوان صاحب فاکتور نمایش می‌دهیم
        seller_info = business_info if business_info else {"name": business_name}
        buyer_info = person_info if person_info else {}
    
    # لاگ برای دیباگ آدرس
    logger.info(
        "Invoice PDF addresses: invoice_id=%s, seller.address=%s, buyer.address=%s",
        invoice_id,
        seller_info.get("address"),
        buyer_info.get("address"),
    )

    # خطوط فاکتور (کالا/خدمت)
    normalized_lines: list[dict[str, Any]] = []
    try:
        for pl in item.get("product_lines", []) or []:
            info = (pl.get("extra_info") or {}) if isinstance(pl, dict) else {}
            qty = pl.get("quantity")
            unit_price = info.get("unit_price")
            line_discount = info.get("line_discount") or 0
            tax_amount = info.get("tax_amount") or 0
            line_total = info.get("line_total")
            qty_display = None
            try:
                qf = float(qty or 0)
                upf = float(unit_price or 0)
                discf = float(line_discount or 0)
                taxf = float(tax_amount or 0)
                if line_total is None:
                    line_total = (qf * upf) - discf + taxf
                # نمایش تعداد: بدون اعشار اگر عدد صحیح باشد
                if qf.is_integer():
                    qty_display = f"{int(qf):,}"
                else:
                    qty_display = f"{qf:,.3f}".rstrip("0").rstrip(".")
            except Exception:
                qty_display = qty
            normalized_lines.append(
                {
                    "product_name": pl.get("product_name"),
                    "description": pl.get("description"),
                    "quantity": qty,
                    "quantity_display": qty_display,
                    "unit_price": unit_price,
                    "discount": line_discount,
                    "tax_amount": tax_amount,
                    "line_total": line_total,
                }
            )
    except Exception:
        normalized_lines = []

    # جمع مبالغ فاکتور از totals یا محاسبه مجدد
    totals = (extra.get("totals") or {}) if isinstance(extra, dict) else {}
    subtotal = totals.get("gross")
    discount_total = totals.get("discount")
    tax_total = totals.get("tax")
    payable_total = totals.get("net")

    try:
        if subtotal is None or discount_total is None or tax_total is None or payable_total is None:
            gross = 0.0
            discount_sum = 0.0
            tax_sum = 0.0
            net_sum = 0.0
            for ln in normalized_lines:
                try:
                    qf = float(ln.get("quantity") or 0)
                    upf = float(ln.get("unit_price") or 0)
                    discf = float(ln.get("discount") or 0)
                    taxf = float(ln.get("tax_amount") or 0)
                    line_total = ln.get("line_total")
                    if line_total is None:
                        line_total = (qf * upf) - discf + taxf
                    gross += qf * upf
                    discount_sum += discf
                    tax_sum += taxf
                    net_sum += float(line_total)
                except Exception:
                    continue
            if subtotal is None:
                subtotal = gross
            if discount_total is None:
                discount_total = discount_sum
            if tax_total is None:
                tax_total = tax_sum
            if payable_total is None:
                payable_total = net_sum
    except Exception:
        pass

    # تشخیص وجود تخفیف/مالیات در سطح سطرها برای نمایش ستون‌های جداگانه
    has_line_discount = False
    has_line_tax = False
    try:
        for ln in normalized_lines:
            try:
                if float(ln.get("discount") or 0) != 0:
                    has_line_discount = True
                if float(ln.get("tax_amount") or 0) != 0:
                    has_line_tax = True
                if has_line_discount and has_line_tax:
                    break
            except Exception:
                continue
    except Exception:
        has_line_discount = False
        has_line_tax = False

    # مبالغ تکمیلی: قبل از تخفیف و مالیات، و بدون مالیات
    amount_before_discount_and_tax = subtotal
    amount_without_tax = None
    try:
        base = float(subtotal or 0)
        disc = float(discount_total or 0)
        taxv = float(tax_total or 0)
        # مبلغ بدون مالیات = مبلغ بعد از تخفیف و قبل از مالیات
        amount_without_tax = base - disc
    except Exception:
        try:
            if payable_total is not None and tax_total is not None:
                amount_without_tax = float(payable_total) - float(tax_total or 0)
        except Exception:
            amount_without_tax = None

    # محاسبه وضعیت حساب مشتری (فقط برای فاکتورهای دارای person_id و با همان ارز فاکتور)
    customer_balance_info: Dict[str, Any] = {}
    try:
        if person_id is not None:
            # محاسبه تراز فعلی مشتری (فقط اسناد قطعی و با همان ارز فاکتور)
            invoice_currency_id = item.get("currency_id")
            if invoice_currency_id:
                # محاسبه تراز با فیلتر ارز
                query = db.query(
                    func.coalesce(func.sum(DocumentLine.credit), 0).label('total_credit'),
                    func.coalesce(func.sum(DocumentLine.debit), 0).label('total_debit')
                ).join(
                    Document, DocumentLine.document_id == Document.id
                ).filter(
                    DocumentLine.person_id == int(person_id),
                    Document.is_proforma == False,  # فقط اسناد قطعی
                    Document.currency_id == int(invoice_currency_id)  # فقط همان ارز فاکتور
                )
                result = query.first()
                if result is not None:
                    total_credit = float(result.total_credit or 0)
                    total_debit = float(result.total_debit or 0)
                    current_balance = total_credit - total_debit
                    if total_credit == 0 and total_debit == 0:
                        current_status = "بدون تراکنش"
                    elif current_balance > 0:
                        current_status = "بستانکار"
                    elif current_balance < 0:
                        current_status = "بدهکار"
                    else:
                        current_status = "بالانس"
                else:
                    current_balance = 0.0
                    current_status = "بدون تراکنش"
            else:
                # اگر ارز فاکتور مشخص نبود، از تابع قبلی استفاده می‌کنیم
                current_balance, current_status = calculate_person_balance(db, int(person_id))
            
            # اگر فاکتور پیش‌فاکتور است، تراز احتمالی بعد از قطعی شدن را محاسبه می‌کنیم
            if is_proforma:
                # محاسبه تاثیر این فاکتور بر تراز
                # برای فاکتور فروش: بدهکار می‌شود (debit)
                # برای فاکتور برگشت از فروش: بستانکار می‌شود (credit)
                # برای فاکتور خرید: بستانکار می‌شود (credit)
                # برای فاکتور برگشت از خرید: بدهکار می‌شود (debit)
                invoice_impact = 0.0
                if inv_type in ("invoice_sales", "invoice_purchase_return"):
                    # بدهکار می‌شود
                    invoice_impact = -float(payable_total or 0)
                elif inv_type in ("invoice_sales_return", "invoice_purchase"):
                    # بستانکار می‌شود
                    invoice_impact = float(payable_total or 0)
                
                potential_balance = current_balance + invoice_impact
                
                # تعیین وضعیت احتمالی
                if potential_balance > 0:
                    potential_status = "بستانکار" if is_fa else "Creditor"
                elif potential_balance < 0:
                    potential_status = "بدهکار" if is_fa else "Debtor"
                else:
                    potential_status = "بالانس" if is_fa else "Balanced"
                
                customer_balance_info = {
                    "current_balance": current_balance,
                    "current_status": current_status,
                    "potential_balance": potential_balance,
                    "potential_status": potential_status,
                    "invoice_impact": invoice_impact,
                }
            else:
                # فاکتور قطعی است، تراز فعلی شامل این فاکتور است
                customer_balance_info = {
                    "current_balance": current_balance,
                    "current_status": current_status,
                }
    except Exception:
        logger.exception("Error calculating customer balance for invoice_id=%s", invoice_id)
        customer_balance_info = {}

    # تراکنش‌های پرداخت مرتبط با فاکتور (رسید/پرداخت‌ها)
    payments: list[dict[str, Any]] = []
    try:
        show_payments = bool(print_settings.get("show_payments", True))
        logger.info(
            "Invoice PDF payments: show_payments=%s for invoice_id=%s", show_payments, invoice_id
        )
        if show_payments:
            links = (extra.get("links") or {}) if isinstance(extra, dict) else {}
            receipt_payment_ids = links.get("receipt_payment_document_ids") or []
            logger.info(
                "Invoice PDF payments: receipt_payment_document_ids=%s for invoice_id=%s",
                receipt_payment_ids,
                invoice_id,
            )
            for rid in receipt_payment_ids:
                try:
                    rp = get_receipt_payment(db, int(rid))
                except Exception:
                    rp = None
                if not rp:
                    continue
                # تاریخ پرداخت با تقویم کاربر
                pay_date_raw = rp.get("document_date")
                pay_date_display = None
                try:
                    if pay_date_raw:
                        dt = datetime.datetime.fromisoformat(str(pay_date_raw).replace("Z", "+00:00"))
                        if calendar_type == "jalali":
                            fd = CalendarConverter.format_datetime(dt, "jalali")
                            pay_date_display = fd.get("date_only") or fd.get("formatted", "")
                        else:
                            fd = CalendarConverter.format_datetime(dt, "gregorian")
                            pay_date_display = fd.get("date_only") or fd.get("formatted", "")
                except Exception:
                    pay_date_display = str(pay_date_raw) if pay_date_raw is not None else None
                # استخراج اطلاعات کامل از account_lines (نوع پرداخت، نام حساب، توضیحات)
                account_details: list[dict[str, Any]] = []
                methods: list[str] = []
                
                for ln in (rp.get("account_lines") or []):
                    ttype = (ln.get("transaction_type") or "").strip().lower()
                    if not ttype:
                        continue
                    
                    # نام نوع پرداخت
                    if ttype == "bank":
                        method_label = "بانک" if is_fa else "Bank"
                    elif ttype == "cash_register":
                        method_label = "صندوق" if is_fa else "Cash"
                    elif ttype == "petty_cash":
                        method_label = "تنخواه" if is_fa else "Petty cash"
                    elif ttype == "check":
                        method_label = "چک" if is_fa else "Check"
                    elif ttype == "wallet":
                        method_label = "کیف‌پول" if is_fa else "Wallet"
                    elif ttype == "person":
                        method_label = "شخص" if is_fa else "Person"
                    else:
                        method_label = ttype
                    
                    if method_label not in methods:
                        methods.append(method_label)
                    
                    # استخراج نام حساب (بانک/صندوق/تنخواه)
                    account_name = ln.get("account_name") or ""
                    bank_name = ln.get("bank_name") or ""
                    cash_register_name = ln.get("cash_register_name") or ""
                    petty_cash_name = ln.get("petty_cash_name") or ""
                    check_number = ln.get("check_number") or ""
                    description = ln.get("description") or ""
                    
                    # تعیین نام نمایشی
                    display_name = account_name
                    if ttype == "bank" and bank_name:
                        display_name = bank_name
                    elif ttype == "cash_register" and cash_register_name:
                        display_name = cash_register_name
                    elif ttype == "petty_cash" and petty_cash_name:
                        display_name = petty_cash_name
                    elif ttype == "check" and check_number:
                        display_name = f"چک {check_number}" if is_fa else f"Check {check_number}"
                    
                    account_details.append({
                        "transaction_type": ttype,
                        "method_label": method_label,
                        "display_name": display_name,
                        "amount": ln.get("amount", 0),
                        "description": description,
                    })
                
                payments.append(
                    {
                        "id": rp.get("id"),
                        "code": rp.get("code"),
                        "document_type": rp.get("document_type"),
                        "document_type_name": rp.get("document_type_name"),
                        "date": pay_date_display,
                        "total_amount": rp.get("total_amount"),
                        "methods": ", ".join(methods),
                        "account_details": account_details,
                        "description": rp.get("description") or "",
                    }
                )
        logger.info(
            "Invoice PDF payments: built %d payment rows for invoice_id=%s",
            len(payments),
            invoice_id,
        )
    except Exception:
        logger.exception(
            "Invoice PDF payments: error while building payments list for invoice_id=%s",
            invoice_id,
        )
        payments = []

    # طرح اقساط (در صورت وجود)
    installment_plan: dict[str, Any] | None = None
    try:
        if print_settings.get("show_installment_plan", True):
            extra_info = item.get("extra_info") or {}
            if isinstance(extra_info, dict) and isinstance(extra_info.get("installment_plan"), dict):
                # از سرویس نصب اقساط برای غنی‌سازی برنامه استفاده می‌کنیم
                try:
                    plan_view = get_invoice_installment_plan(db=db, business_id=business_id, invoice_id=invoice_id)
                except Exception:
                    plan_view = None
                if isinstance(plan_view, dict) and isinstance(plan_view.get("plan"), dict):
                    plan = dict(plan_view["plan"])
                    schedule = []
                    for it in plan.get("schedule") or []:
                        due_raw = it.get("due_date")
                        due_display = None
                        try:
                            if due_raw:
                                dt = datetime.datetime.fromisoformat(str(due_raw).replace("Z", "+00:00"))
                                if calendar_type == "jalali":
                                    fd = CalendarConverter.format_datetime(dt, "jalali")
                                    due_display = fd.get("date_only") or fd.get("formatted", "")
                                else:
                                    fd = CalendarConverter.format_datetime(dt, "gregorian")
                                    due_display = fd.get("date_only") or fd.get("formatted", "")
                        except Exception:
                            due_display = str(due_raw) if due_raw is not None else None
                        new_it = dict(it)
                        new_it["due_date_display"] = due_display
                        schedule.append(new_it)
                    plan["schedule"] = schedule
                    installment_plan = {
                        "meta": {
                            "invoice_code": plan_view.get("invoice_code"),
                            "person_id": plan_view.get("person_id"),
                        },
                        "data": plan,
                    }
    except Exception:
        installment_plan = None

    # غنی‌سازی دیکشنری فاکتور برای استفاده راحت‌تر در قالب و لیست‌ها
    item["title"] = item.get("title") or item.get("description") or ("فاکتور" if is_fa else "Invoice")
    item["issue_date"] = invoice_date_display
    item["invoice_type_name"] = invoice_type_name
    item["is_proforma"] = is_proforma
    item["subtotal"] = subtotal
    item["discount_total"] = discount_total
    item["tax_total"] = tax_total
    item["payable_total"] = payable_total
    item["amount_before_discount_and_tax"] = amount_before_discount_and_tax
    item["amount_without_tax"] = amount_without_tax
    # فلگ فروش اقساطی: اگر طرح اقساط روی سند وجود داشته باشد
    try:
        extra_info_for_flag = item.get("extra_info") or {}
        item["is_installment_sale"] = bool(
            isinstance(extra_info_for_flag, dict)
            and isinstance(extra_info_for_flag.get("installment_plan"), dict)
        )
    except Exception:
        item["is_installment_sale"] = False

    # نام کاربر صادرکننده فاکتور
    issuer_name: Optional[str] = None
    try:
        issuer = db.query(User).filter(User.id == doc.created_by_user_id).first()
        if issuer is not None:
            first = getattr(issuer, "first_name", None) or ""
            last = getattr(issuer, "last_name", None) or ""
            full = (f"{first} {last}").strip()
            issuer_name = full or (issuer.email or issuer.mobile or str(issuer.id))
    except Exception:
        issuer_name = None

    # آدرس/داده فونت فارسی برای PDF (در صورت وجود و زبان فارسی)
    fa_font_url_regular: Optional[str] = None
    fa_font_url_bold: Optional[str] = None
    try:
        if is_fa:
            project_root = Path(__file__).resolve().parents[4]
            fonts_dir = project_root / "hesabixUI" / "hesabix_ui" / "assets" / "fonts"
            regular_path = fonts_dir / "YekanBakhFaNum-Regular.ttf"
            bold_path = fonts_dir / "YekanBakhFaNum-Bold.ttf"
            logger.info("PDF Font detection: fonts_dir=%s", fonts_dir)
            if regular_path.is_file():
                logger.info("PDF Font detection: Regular font found at %s", regular_path)
                import base64 as _b64
                _data = regular_path.read_bytes()
                _b64_data = _b64.b64encode(_data).decode("ascii")
                fa_font_url_regular = f"data:font/ttf;base64,{_b64_data}"
            else:
                logger.warning("PDF Font detection: Regular font NOT found at %s", regular_path)
            if bold_path.is_file():
                logger.info("PDF Font detection: Bold font found at %s", bold_path)
                import base64 as _b64b
                _data_b = bold_path.read_bytes()
                _b64_data_b = _b64b.b64encode(_data_b).decode("ascii")
                fa_font_url_bold = f"data:font/ttf;base64,{_b64_data_b}"
            else:
                logger.warning("PDF Font detection: Bold font NOT found at %s", bold_path)
    except Exception:
        logger.exception("PDF Font detection: error while loading YekanBakhFaNum fonts")
        fa_font_url_regular = None
        fa_font_url_bold = None

    # کانتکست قالب
    template_context = {
        "business_id": business_id,
        "business_name": business_name,
        "business": business_info,
        "business_logo_data_uri": business_logo_data_uri,
        "business_stamp_data_uri": business_stamp_data_uri,
        "owner_signature_data_uri": owner_signature_data_uri,
        "invoice": item,
        "lines": normalized_lines,
        "buyer": buyer_info,
        "seller": seller_info,
        "has_line_discount": has_line_discount,
        "has_line_tax": has_line_tax,
        "payments": payments,
        "installment_plan": installment_plan,
        "invoice_date_jalali": invoice_date_jalali,
        "invoice_date_gregorian": invoice_date_gregorian,
        "generated_at": datetime.datetime.now(),
        "is_fa": is_fa,
        "issuer_name": issuer_name,
        "fa_font_url_regular": fa_font_url_regular,
        "fa_font_url_bold": fa_font_url_bold,
        "invoice_footer_note": invoice_footer_note,
        "customer_balance_info": customer_balance_info,
    }

    # تلاش برای رندر با قالب سفارشی
    resolved_html = None
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if template_id is not None:
                explicit_template_id = int(template_id)
        except Exception:
            explicit_template_id = None
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="invoices",
            subtype="detail",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # HTML پیش‌فرض در نبود قالب: استفاده از قالب فایل
    # پارامترهای صفحه از کوئری (اختیاری)
    try:
        qp = request.query_params
        paper_size = qp.get("paper_size")
        orientation = qp.get("orientation")
        disposition = qp.get("disposition") or "attachment"
    except Exception:
        paper_size = None
        orientation = None
        disposition = "attachment"

    # حالت پیش‌فرض صفحه برای فاکتور: افقی (landscape)، مگر این‌که صراحتاً چیز دیگری ارسال شده باشد
    if not orientation:
        orientation = "landscape"
    # متن فوتر با زمان چاپ (بر اساس تقویم انتخاب‌شده کاربر) و نام صادرکننده
    try:
        now = template_context["generated_at"]
        footer_text = ""
        if isinstance(now, datetime.datetime):
            footer_label = "زمان چاپ" if is_fa else "Printed at"
            issuer_label = "صادرکننده" if is_fa else "Issued by"
            try:
                if calendar_type == "jalali":
                    fd = CalendarConverter.format_datetime(now, "jalali")
                else:
                    fd = CalendarConverter.format_datetime(now, "gregorian")
                printed_at_str = fd.get("formatted") or fd.get("date_only", "")
                if printed_at_str:
                    footer_text = f"{footer_label}: {printed_at_str}"
                    if issuer_name:
                        footer_text += f" | {issuer_label}: {issuer_name}"
            except Exception:
                footer_text = f"{footer_label}: {now.strftime('%Y/%m/%d %H:%M')}"
                if issuer_name:
                    footer_text += f" | {issuer_label}: {issuer_name}"
    except Exception:
        footer_text = ""

    default_ctx = {
        **template_context,
        "title_text": item.get("title") or ("فاکتور" if is_fa else "Invoice"),
        "paper_size": paper_size,
        "orientation": orientation,
        "footer_text": footer_text,
    }
    html_content = resolved_html or render_template("pdf/invoices/detail.html", default_ctx)

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_content).write_pdf(font_config=font_config)

    # نام فایل
    def _slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", (text or "")).strip("_") or "invoice"
    filename = f"invoice_{_slugify(item.get('code'))}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"{disposition}; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )

@router.post("/business/{business_id}/search")
@require_business_access("business_id")
async def search_invoices_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """لیست فاکتورها با فیلتر، جست‌وجو، مرتب‌سازی و صفحه‌بندی استاندارد"""

    # Locale for labels
    from app.core.i18n import negotiate_locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"

    # Base query
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    # Merge flat body extras similar to other list endpoints
    body: Dict[str, Any] = {}
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            body = body_json
    except Exception:
        body = {}

    # Simple search on code/description
    search: Optional[str] = getattr(query_info, 'search', None)
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    # Extra filters
    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    # Fiscal year from header or body
    fiscal_year_id = None
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            fiscal_year_id = int(fy_header)
    except Exception:
        fiscal_year_id = None
    if fiscal_year_id is None:
        try:
            if body.get("fiscal_year_id") is not None:
                fiscal_year_id = int(body.get("fiscal_year_id"))
        except Exception:
            fiscal_year_id = None
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    # Date range from filters or flat body
    # 1) From QueryInfo.filters operators
    try:
        filters = getattr(query_info, 'filters', None)
    except Exception:
        filters = None
    if filters and isinstance(filters, (list, tuple)):
        for flt in filters:
            try:
                prop = getattr(flt, 'property', None) if not isinstance(flt, dict) else flt.get('property')
                op = getattr(flt, 'operator', None) if not isinstance(flt, dict) else flt.get('operator')
                val = getattr(flt, 'value', None) if not isinstance(flt, dict) else flt.get('value')
                if prop == 'document_date' and isinstance(val, str) and val:
                    from app.services.transfer_service import _parse_iso_date as _p
                    dt = _p(val)
                    col = getattr(Document, prop)
                    if op == ">=":
                        q = q.filter(col >= dt)
                    elif op == "<=":
                        q = q.filter(col <= dt)
            except Exception:
                pass

    # 2) From flat body keys
    if isinstance(body.get("from_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p
            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p
            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    # Sorting
    sort_desc = bool(getattr(query_info, 'sort_desc', True))
    sort_by = getattr(query_info, 'sort_by', None) or 'document_date'
    sort_col = Document.document_date
    if isinstance(sort_by, str):
        if sort_by == 'code' and hasattr(Document, 'code'):
            sort_col = Document.code
        elif sort_by == 'created_at' and hasattr(Document, 'created_at'):
            sort_col = Document.created_at
        elif sort_by == 'registered_at' and hasattr(Document, 'registered_at'):
            sort_col = Document.registered_at
        else:
            sort_col = Document.document_date
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    # Pagination
    take = int(getattr(query_info, 'take', 20) or 20)
    skip = int(getattr(query_info, 'skip', 0) or 0)

    total = q.count()
    items: List[Document] = q.offset(skip).limit(take).all()

    # Helpers for display fields
    def _type_name(tp: str) -> str:
        mapping = {
            'invoice_sales': ('فروش' if is_fa else 'Sales'),
            'invoice_sales_return': ('برگشت از فروش' if is_fa else 'Sales return'),
            'invoice_purchase': ('خرید' if is_fa else 'Purchase'),
            'invoice_purchase_return': ('برگشت از خرید' if is_fa else 'Purchase return'),
            'invoice_direct_consumption': ('مصرف مستقیم' if is_fa else 'Direct consumption'),
            'invoice_production': ('تولید' if is_fa else 'Production'),
            'invoice_waste': ('ضایعات' if is_fa else 'Waste'),
        }
        return mapping.get(str(tp), str(tp))

    data_items: List[Dict[str, Any]] = []
    for d in items:
        item = invoice_document_to_dict(db, d)

        # Tax workspace fields from extra_info
        try:
            extra = item.get("extra_info") or {}
        except Exception:
            extra = {}
        tax_workspace = bool(extra.get("tax_workspace"))
        tax_status = (extra.get("tax_status") or "").strip() if isinstance(extra.get("tax_status"), str) else extra.get("tax_status")
        if not tax_status:
            tax_status = "in_workspace" if tax_workspace else "not_in_workspace"
        item["tax_status"] = tax_status

        # Installment sale flag: اگر طرح اقساط روی سند وجود داشته باشد
        try:
            item["is_installment_sale"] = bool(
                isinstance(extra, dict) and isinstance(extra.get("installment_plan"), dict)
            )
        except Exception:
            item["is_installment_sale"] = False

        # total_amount from extra_info.totals.net if available
        total_amount = None
        try:
            totals = (item.get('extra_info') or {}).get('totals') or {}
            if isinstance(totals, dict) and 'net' in totals:
                total_amount = totals.get('net')
        except Exception:
            total_amount = None
        # Fallback compute from product lines
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get('product_lines', []) or []:
                    info = pl.get('extra_info') or {}
                    qty = float(pl.get('quantity') or 0)
                    unit_price = float(info.get('unit_price') or 0)
                    line_discount = float(info.get('line_discount') or 0)
                    tax_amount = float(info.get('tax_amount') or 0)
                    line_total = info.get('line_total')
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None

        item['document_type_name'] = _type_name(item.get('document_type'))
        if total_amount is not None:
            item['total_amount'] = total_amount
        data_items.append(format_datetime_fields(item, request))

    # Build pagination info
    page = (skip // take) + 1 if take > 0 else 1
    total_pages = (total + take - 1) // take if take > 0 else 1

    return success_response(
        data={
            "items": data_items,
            "total": total,
            "take": take,
            "skip": skip,
            # Optional standard pagination shape (supported by UI model)
            "pagination": {
                "page": page,
                "per_page": take,
                "total": total,
                "total_pages": total_pages,
            },
            # Flat shape too, for compatibility
            "page": page,
            "limit": take,
            "total_pages": total_pages,
        },
        request=request,
        message="INVOICE_LIST",
    )

@router.post("/business/{business_id}/tax-workspace/search")
@require_business_access("business_id")
async def search_tax_workspace_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """لیست فاکتورهای موجود در کارپوشه مودیان با فیلتر و صفحه‌بندی."""
    from app.core.i18n import negotiate_locale

    # Base query: all invoice documents for business
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    # Merge flat body extras
    body: Dict[str, Any] = {}
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            body = body_json
    except Exception:
        body = {}

    # Search on code/description
    search: Optional[str] = getattr(query_info, "search", None)
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    # Document type filter
    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    # Proforma filter
    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    # Currency filter
    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    # Fiscal year from header or body
    fiscal_year_id = None
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            fiscal_year_id = int(fy_header)
    except Exception:
        fiscal_year_id = None
    if fiscal_year_id is None:
        try:
            if body.get("fiscal_year_id") is not None:
                fiscal_year_id = int(body.get("fiscal_year_id"))
        except Exception:
            fiscal_year_id = None
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    # Date range filters from QueryInfo.filters
    try:
        filters = getattr(query_info, "filters", None)
    except Exception:
        filters = None
    if filters and isinstance(filters, (list, tuple)):
        for flt in filters:
            try:
                prop = getattr(flt, "property", None) if not isinstance(flt, dict) else flt.get("property")
                op = getattr(flt, "operator", None) if not isinstance(flt, dict) else flt.get("operator")
                val = getattr(flt, "value", None) if not isinstance(flt, dict) else flt.get("value")
                if prop == "document_date" and isinstance(val, str) and val:
                    from app.services.transfer_service import _parse_iso_date as _p

                    dt = _p(val)
                    col = getattr(Document, prop)
                    if op == ">=":
                        q = q.filter(col >= dt)
                    elif op == "<=":
                        q = q.filter(col <= dt)
            except Exception:
                pass

    # Date range from flat body
    if isinstance(body.get("from_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p

            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p

            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    # Sorting similar to main invoice list
    sort_desc = bool(getattr(query_info, "sort_desc", True))
    sort_by = getattr(query_info, "sort_by", None) or "document_date"
    sort_col = Document.document_date
    if isinstance(sort_by, str):
        if sort_by == "code" and hasattr(Document, "code"):
            sort_col = Document.code
        elif sort_by == "created_at" and hasattr(Document, "created_at"):
            sort_col = Document.created_at
        elif sort_by == "registered_at" and hasattr(Document, "registered_at"):
            sort_col = Document.registered_at
        else:
            sort_col = Document.document_date
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    # Fetch all candidates and filter by workspace/tax_status in Python
    all_docs: List[Document] = q.all()
    requested_status = body.get("tax_status")
    requested_status = requested_status.strip() if isinstance(requested_status, str) else None

    workspace_docs: List[Document] = []
    for d in all_docs:
        extra = d.extra_info or {}
        in_workspace = bool(extra.get("tax_workspace"))
        if not in_workspace:
            continue
        status = extra.get("tax_status")
        if isinstance(status, str):
            status = status.strip()
        if not status:
            status = "not_sent"
        if requested_status and status != requested_status:
            continue
        workspace_docs.append(d)

    # Pagination (after workspace filter)
    take = int(getattr(query_info, "take", 20) or 20)
    skip = int(getattr(query_info, "skip", 0) or 0)
    total = len(workspace_docs)
    page_docs = workspace_docs[skip : skip + take] if take > 0 else workspace_docs

    # Locale for type names
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"

    def _type_name(tp: str) -> str:
        mapping = {
            "invoice_sales": ("فروش" if is_fa else "Sales"),
            "invoice_sales_return": ("برگشت از فروش" if is_fa else "Sales return"),
            "invoice_purchase": ("خرید" if is_fa else "Purchase"),
            "invoice_purchase_return": ("برگشت از خرید" if is_fa else "Purchase return"),
            "invoice_direct_consumption": ("مصرف مستقیم" if is_fa else "Direct consumption"),
            "invoice_production": ("تولید" if is_fa else "Production"),
            "invoice_waste": ("ضایعات" if is_fa else "Waste"),
        }
        return mapping.get(str(tp), str(tp))

    data_items: List[Dict[str, Any]] = []
    for d in page_docs:
        item = invoice_document_to_dict(db, d)
        extra = item.get("extra_info") or {}
        tax_status = extra.get("tax_status")
        if isinstance(tax_status, str):
            tax_status = tax_status.strip()
        if not tax_status:
            tax_status = "not_sent"
        item["tax_status"] = tax_status
        item["tax_tracking_code"] = extra.get("tax_tracking_code")
        item["tax_last_send_at"] = extra.get("tax_last_send_at")

        # total_amount from totals.net or recomputed
        total_amount = None
        try:
            totals = (item.get("extra_info") or {}).get("totals") or {}
            if isinstance(totals, dict) and "net" in totals:
                total_amount = totals.get("net")
        except Exception:
            total_amount = None
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get("product_lines", []) or []:
                    info = pl.get("extra_info") or {}
                    qty = float(pl.get("quantity") or 0)
                    unit_price = float(info.get("unit_price") or 0)
                    line_discount = float(info.get("line_discount") or 0)
                    tax_amount = float(info.get("tax_amount") or 0)
                    line_total = info.get("line_total")
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None

        item["document_type_name"] = _type_name(item.get("document_type"))
        if total_amount is not None:
            item["total_amount"] = total_amount
        data_items.append(format_datetime_fields(item, request))

    page = (skip // take) + 1 if take > 0 else 1
    total_pages = (total + take - 1) // take if take > 0 else 1

    return success_response(
        data={
            "items": data_items,
            "total": total,
            "take": take,
            "skip": skip,
            "pagination": {
                "page": page,
                "per_page": take,
                "total": total,
                "total_pages": total_pages,
            },
            "page": page,
            "limit": take,
            "total_pages": total_pages,
        },
        request=request,
        message="INVOICE_TAX_WORKSPACE_LIST",
    )

def _get_invoice_for_business(
    db: Session,
    business_id: int,
    invoice_id: int,
) -> Document:
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
    return doc


def _ensure_sales_or_return(doc: Document) -> None:
    if doc.document_type not in ("invoice_sales", "invoice_sales_return"):
        raise ApiError(
            "TAX_WORKSPACE_NOT_ALLOWED",
            "Only sales and sales-return invoices can be added to tax workspace",
            http_status=400,
        )
    if doc.is_proforma:
        raise ApiError(
            "TAX_WORKSPACE_NOT_ALLOWED",
            "Proforma invoices cannot be added to tax workspace",
            http_status=400,
        )


@router.post("/business/{business_id}/{invoice_id}/tax-workspace/add")
@require_business_access("business_id")
async def add_invoice_to_tax_workspace(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """افزودن فاکتور به کارپوشه مودیان."""
    doc = _get_invoice_for_business(db, business_id, invoice_id)
    _ensure_sales_or_return(doc)

    extra = dict(doc.extra_info or {})
    extra["tax_workspace"] = True
    status = extra.get("tax_status")
    if not isinstance(status, str) or not status.strip():
        extra["tax_status"] = "not_sent"
    doc.extra_info = extra
    db.commit()
    db.refresh(doc)

    return success_response(
        data={"id": doc.id, "tax_status": extra.get("tax_status")},
        request=request,
        message="INVOICE_ADDED_TO_TAX_WORKSPACE",
    )


@router.post("/business/{business_id}/{invoice_id}/tax-workspace/remove")
@require_business_access("business_id")
async def remove_invoice_from_tax_workspace(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """حذف فاکتور از کارپوشه مودیان (فقط اگر قطعی نشده باشد)."""
    doc = _get_invoice_for_business(db, business_id, invoice_id)
    extra = dict(doc.extra_info or {})
    status = (extra.get("tax_status") or "").strip() if isinstance(extra.get("tax_status"), str) else extra.get("tax_status")
    if status == "finalized":
        raise ApiError(
            "TAX_WORKSPACE_REMOVE_NOT_ALLOWED",
            "Cannot remove finalized invoice from tax workspace",
            http_status=409,
        )

    extra["tax_workspace"] = False
    # Optional: mark as not in workspace
    extra["tax_status"] = status or "not_in_workspace"
    doc.extra_info = extra
    db.commit()
    db.refresh(doc)

    return success_response(
        data={"id": doc.id, "tax_status": extra.get("tax_status")},
        request=request,
        message="INVOICE_REMOVED_FROM_TAX_WORKSPACE",
    )


def _simulate_send_to_tax_system(doc: Document, db: Session) -> None:
    """
    شبیه‌سازی ارسال فاکتور به سامانه مودیان.
    در این نسخه اولیه، فقط وضعیت و کد رهگیری آزمایشی ذخیره می‌شود.
    """
    extra = dict(doc.extra_info or {})
    now = datetime.datetime.utcnow().isoformat()
    extra["tax_workspace"] = True
    extra["tax_status"] = "sent"
    extra["tax_tracking_code"] = extra.get("tax_tracking_code") or f"SIM-{doc.id}-{int(datetime.datetime.utcnow().timestamp())}"
    extra["tax_last_send_at"] = now
    extra.pop("tax_error_message", None)
    doc.extra_info = extra
    db.add(doc)


@router.post("/business/{business_id}/{invoice_id}/tax-workspace/send-to-system")
@require_business_access("business_id")
async def send_invoice_to_tax_system(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """
    ارسال تکی فاکتور موجود در کارپوشه به سامانه مودیان.
    (نسخه MVP: فقط بروزرسانی وضعیت و کد رهگیری آزمایشی)
    """
    doc = _get_invoice_for_business(db, business_id, invoice_id)
    _ensure_sales_or_return(doc)

    extra = dict(doc.extra_info or {})
    if not bool(extra.get("tax_workspace")):
        raise ApiError(
            "TAX_WORKSPACE_NOT_SET",
            "Invoice is not in tax workspace",
            http_status=400,
        )
    status = (extra.get("tax_status") or "").strip() if isinstance(extra.get("tax_status"), str) else extra.get("tax_status")
    if status == "finalized":
        raise ApiError(
            "TAX_ALREADY_FINALIZED",
            "Invoice is already finalized in tax system",
            http_status=409,
        )

    # Simulated send (replace with real integration later)
    _simulate_send_to_tax_system(doc, db)
    db.commit()
    db.refresh(doc)

    return success_response(
        data={"id": doc.id, "tax_status": (doc.extra_info or {}).get("tax_status")},
        request=request,
        message="INVOICE_SENT_TO_TAX_SYSTEM",
    )


@router.post("/business/{business_id}/tax-workspace/send-to-system-batch")
@require_business_access("business_id")
async def send_invoices_to_tax_system_batch(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """
    ارسال گروهی فاکتورهای موجود در کارپوشه به سامانه مودیان.
    (MVP: شبیه‌سازی ارسال و بروزرسانی وضعیت)
    """
    ids = body.get("invoice_ids") or []
    if not isinstance(ids, list) or not ids:
        raise ApiError("INVALID_REQUEST", "invoice_ids must be a non-empty list", http_status=400)

    succeeded: List[int] = []
    failed: List[Dict[str, Any]] = []

    for raw_id in ids:
        try:
            invoice_id = int(raw_id)
        except Exception:
            failed.append({"id": raw_id, "error": "INVALID_ID"})
            continue
        try:
            doc = _get_invoice_for_business(db, business_id, invoice_id)
            _ensure_sales_or_return(doc)
            extra = dict(doc.extra_info or {})
            if not bool(extra.get("tax_workspace")):
                raise ApiError("TAX_WORKSPACE_NOT_SET", "Invoice is not in tax workspace", http_status=400)
            status = (extra.get("tax_status") or "").strip() if isinstance(extra.get("tax_status"), str) else extra.get("tax_status")
            if status == "finalized":
                raise ApiError("TAX_ALREADY_FINALIZED", "Invoice is already finalized in tax system", http_status=409)

            _simulate_send_to_tax_system(doc, db)
            succeeded.append(invoice_id)
        except ApiError as e:
            failed.append({"id": invoice_id, "error": e.detail.get("error", {}).get("code")})
        except Exception as e:
            failed.append({"id": invoice_id, "error": str(e)})

    db.commit()

    return success_response(
        data={"succeeded": succeeded, "failed": failed},
        request=request,
        message="INVOICE_BATCH_SENT_TO_TAX_SYSTEM",
    )


@router.post("/business/{business_id}/tax-workspace/remove-batch")
@require_business_access("business_id")
async def remove_invoices_from_tax_workspace_batch(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """حذف گروهی فاکتورها از کارپوشه مودیان (صرفاً غیرقطعی‌ها)."""
    ids = body.get("invoice_ids") or []
    if not isinstance(ids, list) or not ids:
        raise ApiError("INVALID_REQUEST", "invoice_ids must be a non-empty list", http_status=400)

    removed: List[int] = []
    failed: List[Dict[str, Any]] = []

    for raw_id in ids:
        try:
            invoice_id = int(raw_id)
        except Exception:
            failed.append({"id": raw_id, "error": "INVALID_ID"})
            continue
        try:
            doc = _get_invoice_for_business(db, business_id, invoice_id)
            extra = dict(doc.extra_info or {})
            status = (extra.get("tax_status") or "").strip() if isinstance(extra.get("tax_status"), str) else extra.get("tax_status")
            if status == "finalized":
                raise ApiError("TAX_WORKSPACE_REMOVE_NOT_ALLOWED", "Cannot remove finalized invoice", http_status=409)
            extra["tax_workspace"] = False
            extra["tax_status"] = status or "not_in_workspace"
            doc.extra_info = extra
            db.add(doc)
            removed.append(invoice_id)
        except ApiError as e:
            failed.append({"id": invoice_id, "error": e.detail.get("error", {}).get("code")})
        except Exception as e:
            failed.append({"id": invoice_id, "error": str(e)})

    db.commit()

    return success_response(
        data={"removed": removed, "failed": failed},
        request=request,
        message="INVOICE_BATCH_REMOVED_FROM_TAX_WORKSPACE",
    )


    # Merge flat body extras
    body: Dict[str, Any] = {}
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            body = body_json
    except Exception:
        body = {}

    # Search on code/description
    search: Optional[str] = getattr(query_info, "search", None)
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    # Document type filter (sales / sales_return / ...)
    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    # Proforma filter
    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    # Currency filter
    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    # Fiscal year from header or body
    fiscal_year_id = None
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            fiscal_year_id = int(fy_header)
    except Exception:
        fiscal_year_id = None
    if fiscal_year_id is None:
        try:
            if body.get("fiscal_year_id") is not None:
                fiscal_year_id = int(body.get("fiscal_year_id"))
        except Exception:
            fiscal_year_id = None
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    # Date range filters
    try:
        filters = getattr(query_info, "filters", None)
    except Exception:
        filters = None
    if filters and isinstance(filters, (list, tuple)):
        for flt in filters:
            try:
                prop = getattr(flt, "property", None) if not isinstance(flt, dict) else flt.get("property")
                op = getattr(flt, "operator", None) if not isinstance(flt, dict) else flt.get("operator")
                val = getattr(flt, "value", None) if not isinstance(flt, dict) else flt.get("value")
                if prop == "document_date" and isinstance(val, str) and val:
                    from app.services.transfer_service import _parse_iso_date as _p

                    dt = _p(val)
                    col = getattr(Document, prop)
                    if op == ">=":
                        q = q.filter(col >= dt)
                    elif op == "<=":
                        q = q.filter(col <= dt)
            except Exception:
                pass

    if isinstance(body.get("from_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p

            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p

            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    # Sorting (reuse same logic as main invoice list)
    sort_desc = bool(getattr(query_info, "sort_desc", True))
    sort_by = getattr(query_info, "sort_by", None) or "document_date"
    sort_col = Document.document_date
    if isinstance(sort_by, str):
        if sort_by == "code" and hasattr(Document, "code"):
            sort_col = Document.code
        elif sort_by == "created_at" and hasattr(Document, "created_at"):
            sort_col = Document.created_at
        elif sort_by == "registered_at" and hasattr(Document, "registered_at"):
            sort_col = Document.registered_at
        else:
            sort_col = Document.document_date
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    # Fetch all candidates and filter by workspace and tax_status in Python (JSON-friendly)
    all_docs: List[Document] = q.all()
    requested_status = body.get("tax_status")
    requested_status = requested_status.strip() if isinstance(requested_status, str) else None

    workspace_docs: List[Document] = []
    for d in all_docs:
        extra = d.extra_info or {}
        in_workspace = bool(extra.get("tax_workspace"))
        if not in_workspace:
            continue
        status = extra.get("tax_status")
        if isinstance(status, str):
            status = status.strip()
        if not status:
            status = "not_sent"
        if requested_status and status != requested_status:
            continue
        workspace_docs.append(d)

    # Pagination (after workspace filter)
    take = int(getattr(query_info, "take", 20) or 20)
    skip = int(getattr(query_info, "skip", 0) or 0)
    total = len(workspace_docs)
    page_docs = workspace_docs[skip : skip + take] if take > 0 else workspace_docs

    # Locale for display fields
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"

    def _type_name(tp: str) -> str:
        mapping = {
            "invoice_sales": ("فروش" if is_fa else "Sales"),
            "invoice_sales_return": ("برگشت از فروش" if is_fa else "Sales return"),
            "invoice_purchase": ("خرید" if is_fa else "Purchase"),
            "invoice_purchase_return": ("برگشت از خرید" if is_fa else "Purchase return"),
            "invoice_direct_consumption": ("مصرف مستقیم" if is_fa else "Direct consumption"),
            "invoice_production": ("تولید" if is_fa else "Production"),
            "invoice_waste": ("ضایعات" if is_fa else "Waste"),
        }
        return mapping.get(str(tp), str(tp))

    data_items: List[Dict[str, Any]] = []
    for d in page_docs:
        item = invoice_document_to_dict(db, d)
        extra = item.get("extra_info") or {}
        tax_status = extra.get("tax_status")
        if isinstance(tax_status, str):
            tax_status = tax_status.strip()
        if not tax_status:
            tax_status = "not_sent"
        item["tax_status"] = tax_status
        item["tax_tracking_code"] = extra.get("tax_tracking_code")
        item["tax_last_send_at"] = extra.get("tax_last_send_at")

        # total_amount from totals.net or recomputed
        total_amount = None
        try:
            totals = (item.get("extra_info") or {}).get("totals") or {}
            if isinstance(totals, dict) and "net" in totals:
                total_amount = totals.get("net")
        except Exception:
            total_amount = None
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get("product_lines", []) or []:
                    info = pl.get("extra_info") or {}
                    qty = float(pl.get("quantity") or 0)
                    unit_price = float(info.get("unit_price") or 0)
                    line_discount = float(info.get("line_discount") or 0)
                    tax_amount = float(info.get("tax_amount") or 0)
                    line_total = info.get("line_total")
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None

        item["document_type_name"] = _type_name(item.get("document_type"))
        if total_amount is not None:
            item["total_amount"] = total_amount
        data_items.append(format_datetime_fields(item, request))

    page = (skip // take) + 1 if take > 0 else 1
    total_pages = (total + take - 1) // take if take > 0 else 1

    return success_response(
        data={
            "items": data_items,
            "total": total,
            "take": take,
            "skip": skip,
            "pagination": {
                "page": page,
                "per_page": take,
                "total": total,
                "total_pages": total_pages,
            },
            "page": page,
            "limit": take,
            "total_pages": total_pages,
        },
        request=request,
        message="INVOICE_TAX_WORKSPACE_LIST",
    )

@router.post(
    "/business/{business_id}/export/excel",
    summary="خروجی Excel لیست فاکتورها",
    description="خروجی Excel لیست فاکتورها با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_invoices_excel(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from app.core.i18n import negotiate_locale

    # Build base query similar to search endpoint
    take_value = min(int(body.get("take", 1000)), 10000)
    skip_value = int(body.get("skip", 0))

    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    # Search
    search = body.get("search")
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    # Filters
    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    # Fiscal year
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            q = q.filter(Document.fiscal_year_id == int(fy_header))
        elif body.get("fiscal_year_id") is not None:
            q = q.filter(Document.fiscal_year_id == int(body.get("fiscal_year_id")))
    except Exception:
        pass

    # Date range
    from app.services.transfer_service import _parse_iso_date as _p
    if isinstance(body.get("from_date"), str):
        try:
            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    # Sorting
    sort_desc = bool(body.get("sort_desc", True))
    sort_by = body.get("sort_by") or "document_date"
    sort_col = Document.document_date
    if sort_by == 'code' and hasattr(Document, 'code'):
        sort_col = Document.code
    elif sort_by == 'created_at' and hasattr(Document, 'created_at'):
        sort_col = Document.created_at
    elif sort_by == 'registered_at' and hasattr(Document, 'registered_at'):
        sort_col = Document.registered_at
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    total = q.count()
    docs: List[Document] = q.offset(skip_value).limit(take_value).all()

    # Build items like list endpoint
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'

    def _type_name(tp: str) -> str:
        mapping = {
            'invoice_sales': ('فروش' if is_fa else 'Sales'),
            'invoice_sales_return': ('برگشت از فروش' if is_fa else 'Sales return'),
            'invoice_purchase': ('خرید' if is_fa else 'Purchase'),
            'invoice_purchase_return': ('برگشت از خرید' if is_fa else 'Purchase return'),
            'invoice_direct_consumption': ('مصرف مستقیم' if is_fa else 'Direct consumption'),
            'invoice_production': ('تولید' if is_fa else 'Production'),
            'invoice_waste': ('ضایعات' if is_fa else 'Waste'),
        }
        return mapping.get(str(tp), str(tp))

    items: List[Dict[str, Any]] = []
    for d in docs:
        item = invoice_document_to_dict(db, d)
        # total_amount
        total_amount = None
        try:
            totals = (item.get('extra_info') or {}).get('totals') or {}
            if isinstance(totals, dict) and 'net' in totals:
                total_amount = totals.get('net')
        except Exception:
            total_amount = None
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get('product_lines', []) or []:
                    info = pl.get('extra_info') or {}
                    qty = float(pl.get('quantity') or 0)
                    unit_price = float(info.get('unit_price') or 0)
                    line_discount = float(info.get('line_discount') or 0)
                    tax_amount = float(info.get('tax_amount') or 0)
                    line_total = info.get('line_total')
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None

        item['document_type_name'] = _type_name(item.get('document_type'))
        if total_amount is not None:
            item['total_amount'] = total_amount
        items.append(format_datetime_fields(item, request))

    # Handle selected rows
    selected_only = bool(body.get('selected_only', False))
    selected_indices = body.get('selected_indices')
    if selected_only and selected_indices is not None:
        indices = None
        if isinstance(selected_indices, str):
            try:
                indices = json.loads(selected_indices)
            except (json.JSONDecodeError, TypeError):
                indices = None
        elif isinstance(selected_indices, list):
            indices = selected_indices
        if isinstance(indices, list):
            items = [items[i] for i in indices if isinstance(i, int) and 0 <= i < len(items)]

    # Prepare columns
    headers: List[str] = []
    keys: List[str] = []
    export_columns = body.get('export_columns')
    if export_columns:
        for col in export_columns:
            key = col.get('key')
            label = col.get('label', key)
            if key:
                keys.append(str(key))
                headers.append(str(label))
    else:
        default_columns = [
            ('code', 'کد سند' if is_fa else 'Code'),
            ('document_type_name', 'نوع فاکتور' if is_fa else 'Invoice type'),
            ('document_date', 'تاریخ سند' if is_fa else 'Document date'),
            ('total_amount', 'مبلغ کل' if is_fa else 'Total amount'),
            ('currency_code', 'ارز' if is_fa else 'Currency'),
            ('created_by_name', 'ایجادکننده' if is_fa else 'Created by'),
            ('is_proforma', 'پیش‌فاکتور' if is_fa else 'Proforma'),
            ('registered_at', 'تاریخ ثبت' if is_fa else 'Registered at'),
        ]
        for key, label in default_columns:
            if items and key in items[0]:
                keys.append(key)
                headers.append(label)

    # Create workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "Invoices"

    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
    header_alignment = Alignment(horizontal="center", vertical="center")
    border = Border(left=Side(style='thin'), right=Side(style='thin'), top=Side(style='thin'), bottom=Side(style='thin'))

    # Header row
    for col_idx, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_alignment
        cell.border = border

    # Data rows
    for row_idx, item in enumerate(items, 2):
        for col_idx, key in enumerate(keys, 1):
            value = item.get(key, "")
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = str(value)
            ws.cell(row=row_idx, column=col_idx, value=value).border = border

    # Auto-width
    for column in ws.columns:
        max_length = 0
        column_letter = column[0].column_letter
        for cell in column:
            try:
                if len(str(cell.value)) > max_length:
                    max_length = len(str(cell.value))
            except Exception:
                pass
        ws.column_dimensions[column_letter].width = min(max_length + 2, 50)

    # Save to bytes
    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    # Filename
    biz_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            biz_name = b.name or ""
    except Exception:
        biz_name = ""

    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")

    base = "invoices"
    if biz_name:
        base += f"_{slugify(biz_name)}"
    if selected_only:
        base += "_selected"
    filename = f"{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    content = buffer.getvalue()

    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(content)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post(
    "/business/{business_id}/export/pdf",
    summary="خروجی PDF لیست فاکتورها",
    description="خروجی PDF لیست فاکتورها با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_invoices_pdf(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape

    # Build same list as excel
    take_value = min(int(body.get("take", 1000)), 10000)
    skip_value = int(body.get("skip", 0))

    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    search = body.get("search")
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            q = q.filter(Document.fiscal_year_id == int(fy_header))
        elif body.get("fiscal_year_id") is not None:
            q = q.filter(Document.fiscal_year_id == int(body.get("fiscal_year_id")))
    except Exception:
        pass

    from app.services.transfer_service import _parse_iso_date as _p
    if isinstance(body.get("from_date"), str):
        try:
            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    sort_desc = bool(body.get("sort_desc", True))
    sort_by = body.get("sort_by") or "document_date"
    sort_col = Document.document_date
    if sort_by == 'code' and hasattr(Document, 'code'):
        sort_col = Document.code
    elif sort_by == 'created_at' and hasattr(Document, 'created_at'):
        sort_col = Document.created_at
    elif sort_by == 'registered_at' and hasattr(Document, 'registered_at'):
        sort_col = Document.registered_at
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    docs: List[Document] = q.offset(skip_value).limit(take_value).all()

    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'

    def _type_name(tp: str) -> str:
        mapping = {
            'invoice_sales': ('فروش' if is_fa else 'Sales'),
            'invoice_sales_return': ('برگشت از فروش' if is_fa else 'Sales return'),
            'invoice_purchase': ('خرید' if is_fa else 'Purchase'),
            'invoice_purchase_return': ('برگشت از خرید' if is_fa else 'Purchase return'),
            'invoice_direct_consumption': ('مصرف مستقیم' if is_fa else 'Direct consumption'),
            'invoice_production': ('تولید' if is_fa else 'Production'),
            'invoice_waste': ('ضایعات' if is_fa else 'Waste'),
        }
        return mapping.get(str(tp), str(tp))

    items: List[Dict[str, Any]] = []
    # Helper to resolve person display name
    def _get_person_display_name(person_id: int | None) -> str | None:
        if person_id is None:
            return None
        try:
            p = db.query(Person).filter(Person.id == int(person_id)).first()
            if p is None:
                return None
            return getattr(p, "display_name", None) or getattr(p, "name", None)
        except Exception:
            return None
    for d in docs:
        item = invoice_document_to_dict(db, d)
        total_amount = None
        try:
            totals = (item.get('extra_info') or {}).get('totals') or {}
            if isinstance(totals, dict) and 'net' in totals:
                total_amount = totals.get('net')
        except Exception:
            total_amount = None
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get('product_lines', []) or []:
                    info = pl.get('extra_info') or {}
                    qty = float(pl.get('quantity') or 0)
                    unit_price = float(info.get('unit_price') or 0)
                    line_discount = float(info.get('line_discount') or 0)
                    tax_amount = float(info.get('tax_amount') or 0)
                    line_total = info.get('line_total')
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None
        item['document_type_name'] = _type_name(item.get('document_type'))
        if total_amount is not None:
            item['total_amount'] = total_amount
        # Counterparty based on type: sales -> buyer (person), purchase -> seller (person)
        try:
            inv_type = str(item.get("document_type") or "")
            extra = item.get("extra_info") or {}
            person_id = extra.get("person_id")
            person_name = _get_person_display_name(person_id)
            counterparty = ""
            if inv_type in ("invoice_sales", "invoice_sales_return"):
                counterparty = person_name or ""
            elif inv_type in ("invoice_purchase", "invoice_purchase_return"):
                counterparty = person_name or ""
            else:
                counterparty = person_name or ""
            item["counterparty"] = counterparty
        except Exception:
            item["counterparty"] = ""
        items.append(format_datetime_fields(item, request))

    # Handle selected rows
    selected_only = bool(body.get('selected_only', False))
    selected_indices = body.get('selected_indices')
    if selected_only and selected_indices is not None:
        indices = None
        if isinstance(selected_indices, str):
            try:
                indices = json.loads(selected_indices)
            except (json.JSONDecodeError, TypeError):
                indices = None
        elif isinstance(selected_indices, list):
            indices = selected_indices
        if isinstance(indices, list):
            items = [items[i] for i in indices if isinstance(i, int) and 0 <= i < len(items)]

    # Prepare columns
    headers: List[str] = []
    keys: List[str] = []
    export_columns = body.get('export_columns')
    if export_columns:
        for col in export_columns:
            key = col.get('key')
            label = col.get('label', key)
            if key:
                keys.append(str(key))
                headers.append(str(label))
    else:
        default_columns = [
            ('code', 'کد سند' if is_fa else 'Code'),
            ('document_type_name', 'نوع فاکتور' if is_fa else 'Invoice type'),
            ('counterparty', 'طرف حساب' if is_fa else 'Counterparty'),
            ('document_date', 'تاریخ سند' if is_fa else 'Document date'),
            ('total_amount', 'مبلغ کل' if is_fa else 'Total amount'),
            ('currency_code', 'ارز' if is_fa else 'Currency'),
            ('created_by_name', 'ایجادکننده' if is_fa else 'Created by'),
            ('is_proforma', 'پیش‌فاکتور' if is_fa else 'Proforma'),
            ('registered_at', 'تاریخ ثبت' if is_fa else 'Registered at'),
        ]
        for key, label in default_columns:
            if items and key in items[0]:
                keys.append(key)
                headers.append(label)

    # Business name & locale
    business_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""

    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'
    # respect user's calendar for generated_at
    try:
        cal_header = (request.headers.get("X-Calendar-Type") or "").strip().lower()
        cal_type = cal_header or ("jalali" if is_fa else "gregorian")
    except Exception:
        cal_type = "jalali" if is_fa else "gregorian"
    try:
        _now = datetime.datetime.now()
        _fd = CalendarConverter.format_datetime(_now, cal_type)
        now = _fd.get("formatted") or _fd.get("date_only") or _now.strftime('%Y/%m/%d %H:%M')
    except Exception:
        now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = "لیست فاکتورها" if is_fa else "Invoices List"
    label_biz = "کسب و کار" if is_fa else "Business"
    label_date = "تاریخ تولید" if is_fa else "Generated Date"
    footer_text = f"تولید شده در {now}" if is_fa else f"Generated at {now}"

    headers_html = ''.join(f'<th>{escape(header)}</th>' for header in headers)

    # Determine calendar type for date formatting in table rows
    try:
        cal_header = (request.headers.get("X-Calendar-Type") or "").strip().lower()
        cal_type_for_rows = cal_header or ("jalali" if is_fa else "gregorian")
    except Exception:
        cal_type_for_rows = "jalali" if is_fa else "gregorian"

    # Helper to format date string using CalendarConverter
    def _format_date_for_calendar(value: str) -> str:
        try:
            dt = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            fd = CalendarConverter.format_datetime(dt, cal_type_for_rows)
            return fd.get("date_only") or fd.get("formatted") or str(value)
        except Exception:
            return str(value)

    # Helpers for numeric formatting with thousands separator and trimming .00
    def _format_number_for_display(value: object) -> str:
        try:
            if value is None:
                return ""
            v = float(value)
            s = f"{v:,.2f}"
            # Trim trailing .00 or trailing zeros
            if "." in s:
                s = s.rstrip("0").rstrip(".")
            return s
        except Exception:
            return str(value)

    # Build rows with numeric alignment and calendar-aware dates
    amount_keys = {"total_amount", "subtotal", "discount_total", "tax_total", "payable_total"}
    date_keys = {"document_date", "registered_at", "created_at"}
    rows_html = []
    total_sum = 0.0
    discount_sum = 0.0
    tax_sum = 0.0
    for item in items:
        row_cells = []
        for key in keys:
            value = item.get(key, "")
            # Normalize list/dict to string
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = str(value)
            # Calendar-aware date formatting
            if key in date_keys and value:
                value = _format_date_for_calendar(value)
            # Amount cells: format and accumulate totals
            if key in amount_keys:
                try:
                    vnum = float(item.get(key)) if item.get(key) is not None else None
                    if key == "total_amount" and vnum is not None:
                        total_sum += vnum
                    if key == "discount_total" and vnum is not None:
                        discount_sum += vnum
                    if key == "tax_total" and vnum is not None:
                        tax_sum += vnum
                except Exception:
                    pass
                disp = _format_number_for_display(value)
                row_cells.append(f'<td class="amount">{escape(disp)}</td>')
            # Proforma: show checkmark for true, empty otherwise
            elif key == "is_proforma":
                checked = (str(value).lower() in ("true", "1"))
                cell = "✓" if checked else ""
                row_cells.append(f'<td style="text-align:center">{cell}</td>')
            else:
                row_cells.append(f'<td>{escape(str(value))}</td>')
        rows_html.append(f'<tr>{"".join(row_cells)}</tr>')

    # Summary block (only total amount and count for list)
    total_count = len(items)
    label_rows = 'تعداد ردیف' if is_fa else 'Rows'
    label_total = 'جمع مبلغ کل' if is_fa else 'Total of amounts'
    label_discount = 'جمع تخفیف' if is_fa else 'Total discount'
    label_tax = 'جمع مالیات' if is_fa else 'Total tax'
    summary_parts = [
        f'<div><strong>{label_rows}:</strong> {total_count}</div>',
        f'<div><strong>{label_total}:</strong> <span class="amount">{total_sum:.2f}</span></div>',
    ]
    # Only render discount/tax if present in any row (non-zero)
    if discount_sum != 0.0:
        summary_parts.append(f'<div><strong>{label_discount}:</strong> <span class="amount">{discount_sum:.2f}</span></div>')
    if tax_sum != 0.0:
        summary_parts.append(f'<div><strong>{label_tax}:</strong> <span class="amount">{tax_sum:.2f}</span></div>')
    summary_html = f'<div class="summary">{"".join(summary_parts)}</div>'

    # کانتکست مشترک برای قالب‌های سفارشی
    template_context: Dict[str, Any] = {
        "title_text": title_text,
        "business_name": business_name,
        "generated_at": now,
        "is_fa": is_fa,
        "fa_font_url_regular": None,
        "fa_font_url_bold": None,
        "headers": headers,
        "keys": keys,
        "items": items,
        # خروجی‌های HTML آماده برای استفاده سریع در قالب
        "table_headers_html": headers_html,
        "table_rows_html": "".join(rows_html),
        "table_summary_html": summary_html,
    }

    # Embed Farsi fonts like single-invoice PDF (if available)
    try:
        if is_fa:
            project_root = Path(__file__).resolve().parents[4]
            fonts_dir = project_root / "hesabixUI" / "hesabix_ui" / "assets" / "fonts"
            regular_path = fonts_dir / "YekanBakhFaNum-Regular.ttf"
            bold_path = fonts_dir / "YekanBakhFaNum-Bold.ttf"
            if regular_path.is_file():
                import base64 as _b64
                _data = regular_path.read_bytes()
                _b64_data = _b64.b64encode(_data).decode("ascii")
                template_context["fa_font_url_regular"] = f"data:font/ttf;base64,{_b64_data}"
            if bold_path.is_file():
                import base64 as _b64b
                _data_b = bold_path.read_bytes()
                _b64_data_b = _b64b.b64encode(_data_b).decode("ascii")
                template_context["fa_font_url_bold"] = f"data:font/ttf;base64,{_b64_data_b}"
    except Exception:
        pass

    # تلاش برای رندر با قالب سفارشی (explicit یا پیش‌فرض)
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if "template_id" in body and body.get("template_id") is not None:
                explicit_template_id = int(body.get("template_id"))
        except Exception:
            explicit_template_id = None
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="invoices",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # HTML پیش‌فرض در نبود قالب: استفاده از فایل قالب
    disposition = "attachment"
    try:
        disposition = str(body.get("disposition") or "attachment")
    except Exception:
        disposition = "attachment"
    paper_size = None
    orientation = None
    try:
        paper_size = body.get("paper_size")
        orientation = body.get("orientation")
    except Exception:
        pass
    html_content = resolved_html or render_template(
        "pdf/invoices/list.html",
        {
            **template_context,
            "title_text": title_text,
            "paper_size": paper_size,
            "orientation": orientation,
            "footer_text": footer_text,
        },
    )

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_content).write_pdf(font_config=font_config)

    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")

    base = "invoices"
    if business_name:
        base += f"_{slugify(business_name)}"
    if selected_only:
        base += "_selected"
    # Add filters to filename when available
    try:
        doc_type = body.get("document_type")
        if isinstance(doc_type, str) and doc_type:
            base += f"_{slugify(doc_type)}"
    except Exception:
        pass
    try:
        fd = body.get("from_date")
        td = body.get("to_date")
        if isinstance(fd, str) and fd:
            base += f"_from_{slugify(fd[:10])}"
        if isinstance(td, str) and td:
            base += f"_to_{slugify(td[:10])}"
    except Exception:
        pass
    filename = f"{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"{disposition}; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )

