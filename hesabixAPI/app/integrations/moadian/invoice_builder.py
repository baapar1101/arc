"""
سرویس ساخت DTO فاکتور مالیاتی از روی داده‌های داخلی
"""
from __future__ import annotations

from datetime import datetime
from typing import Dict, Any, List, Optional

from app.integrations.moadian.dto import (
    InvoiceDto,
    InvoiceHeaderDto,
    InvoiceBodyDto,
    InvoicePaymentDto,
)
from app.integrations.moadian.utils import (
    generate_tax_id,
    normalize_invoice_number,
    timestamp_to_unix_ms,
    round_to_int,
    calculate_vat_rate,
    map_invoice_type_to_moadian,
    map_payment_pattern,
    map_invoice_subject,
    validate_national_id,
    validate_economic_code,
)


class InvoiceBuilder:
    """
    کلاس ساخت DTO فاکتور مالیاتی
    """

    def __init__(self, seller_economic_code: str):
        """
        Args:
            seller_economic_code: کد اقتصادی فروشنده
        """
        self.seller_economic_code = seller_economic_code

    def build_invoice_dto(
        self,
        document: Dict[str, Any],
        tax_setting: Any,
    ) -> InvoiceDto:
        """
        ساخت DTO کامل فاکتور برای ارسال به سامانه مودیان
        
        Args:
            document: داده‌های فاکتور (از invoice_document_to_dict)
            tax_setting: تنظیمات مالیاتی کسب‌وکار
        
        Returns:
            InvoiceDto آماده برای ارسال
        """
        # استخراج اطلاعات پایه
        extra_info = document.get('extra_info') or {}
        person_snapshot = extra_info.get('person_snapshot') or extra_info.get('person_info') or {}
        totals = extra_info.get('totals') or {}
        
        # ساخت Header
        header = self._build_header(document, person_snapshot, tax_setting)
        
        # ساخت Body (اقلام فاکتور)
        body = self._build_body(document)
        
        # ساخت Payments (اختیاری)
        payments = self._build_payments(document)
        
        return InvoiceDto(
            header=header,
            body=body,
            payments=payments,
        )

    def _build_header(
        self,
        document: Dict[str, Any],
        person_snapshot: Dict[str, Any],
        tax_setting: Any,
    ) -> InvoiceHeaderDto:
        """ساخت Header فاکتور"""
        
        # زمان صدور
        doc_date_str = document.get('document_date')
        if isinstance(doc_date_str, str):
            doc_date = datetime.fromisoformat(doc_date_str.replace('Z', '+00:00'))
        else:
            doc_date = datetime.utcnow()
        
        timestamp_ms = timestamp_to_unix_ms(doc_date)
        
        # شناسه یکتای مالیاتی
        taxid = generate_tax_id(
            economic_code=tax_setting.economic_code,
            timestamp=doc_date,
            internal_id=document.get('id', 0),
        )
        
        # شماره فاکتور نرمال شده
        invoice_code = document.get('code', str(document.get('id', 0)))
        inno = normalize_invoice_number(invoice_code)
        
        # نوع فاکتور
        document_type = document.get('document_type', '')
        is_return = 'return' in document_type.lower()
        
        # اطلاعات خریدار
        buyer_national_id = (person_snapshot.get('national_id') or '').strip()
        buyer_economic_code = (person_snapshot.get('economic_code') or '').strip()
        
        # تعیین نوع فاکتور (عادی یا ساده)
        # نوع 1 (عادی): اگر خریدار کد ملی و اقتصادی داشته باشد
        # نوع 2 (ساده): در غیر این صورت
        has_buyer_info = bool(buyer_national_id) and validate_economic_code(buyer_economic_code)
        inty = 1 if has_buyer_info and not is_return else (3 if is_return else 2)
        
        # الگوی پرداخت (نقدی/نسیه)
        # TODO: باید از extra_info یا payment_terms استخراج شود
        inp = map_payment_pattern(is_cash=True, is_credit=False)
        
        # موضوع فاکتور
        ins = map_invoice_subject(document_type)
        
        # شماره اقتصادی فروشنده
        tins = tax_setting.economic_code
        
        # ساخت Header
        header = InvoiceHeaderDto(
            taxid=taxid,
            indatim=timestamp_ms,
            indati2m=timestamp_ms,
            inno=inno,
            inty=inty,
            inp=inp,
            ins=ins,
            tins=tins,
        )
        
        # فیلدهای اختیاری
        if buyer_economic_code and validate_economic_code(buyer_economic_code):
            header.tinb = buyer_economic_code
        
        # اگر فاکتور برگشتی است، شناسه فاکتور مرجع
        if is_return:
            reference_taxid = (document.get('extra_info') or {}).get('reference_tax_id')
            if reference_taxid:
                header.irtaxid = reference_taxid
        
        return header

    def _build_body(self, document: Dict[str, Any]) -> List[InvoiceBodyDto]:
        """ساخت Body (اقلام فاکتور)"""
        
        product_lines = document.get('product_lines') or []
        body_items: List[InvoiceBodyDto] = []
        
        for line in product_lines:
            line_extra = line.get('extra_info') or {}
            tax_snapshot = line_extra.get('tax_snapshot') or {}
            
            # کد مالیاتی کالا (13 رقم)
            tax_code = tax_snapshot.get('tax_code', '').strip()
            if not tax_code:
                # اگر کد مالیاتی نداشت، از یک کد پیش‌فرض استفاده می‌کنیم
                # TODO: باید خطا بدهد یا از جدول استاندارد پیدا کند
                tax_code = '0000000000000'
            
            # شرح کالا
            product_name = line.get('product_name', 'محصول')
            
            # واحد اندازه‌گیری
            tax_unit_code = tax_snapshot.get('tax_unit_code') or tax_snapshot.get('product_main_unit') or '1614'  # عدد (پیش‌فرض)
            
            # تعداد
            quantity = round_to_int(line.get('quantity', 0))
            
            # قیمت واحد
            unit_price = round_to_int(line_extra.get('unit_price', 0))
            
            # تخفیف
            discount = round_to_int(line_extra.get('line_discount', 0))
            
            # مالیات
            tax_amount = round_to_int(line_extra.get('tax_amount', 0))
            
            # مبلغ کل ردیف
            line_total = round_to_int(line_extra.get('line_total', 0))
            
            # نرخ مالیات (درصد × 100)
            # اگر tax_rate در line نباشد، از رابطه tax_amount / (quantity * unit_price - discount) محاسبه می‌کنیم
            tax_rate = line_extra.get('tax_rate', 0)
            if not tax_rate and (quantity * unit_price - discount) > 0:
                tax_rate = (tax_amount / (quantity * unit_price - discount)) * 100
            vra = calculate_vat_rate(tax_rate)
            
            # مبلغ قبل از تخفیف
            gross_amount = quantity * unit_price
            
            body_item = InvoiceBodyDto(
                sstid=tax_code,
                sstt=product_name[:200],  # محدودیت طول
                mu=tax_unit_code,
                am=quantity,
                fee=unit_price,
                prdis=0,  # تخفیف قبل از جمع
                dis=discount,  # تخفیف روی جمع
                adis=0,  # تخفیف بعد از مالیات
                vra=vra,
                vam=tax_amount,
                tsstam=line_total,
            )
            
            # فیلدهای اختیاری
            # نوع: کالا یا خدمت
            product_type = tax_snapshot.get('product_type', 'product')
            body_item.ssrv = 1 if product_type == 'service' else 0
            
            body_items.append(body_item)
        
        return body_items

    def _build_payments(self, document: Dict[str, Any]) -> List[InvoicePaymentDto]:
        """
        ساخت اطلاعات پرداخت (اختیاری)
        در صورتی که اطلاعات پرداخت موجود نباشد، لیست خالی برمی‌گردد
        """
        
        # TODO: باید از account_lines یا payment_info استخراج شود
        # فعلا لیست خالی برمی‌گردانیم
        
        payments: List[InvoicePaymentDto] = []
        
        # اگر اطلاعات پرداخت در extra_info موجود باشد
        extra_info = document.get('extra_info') or {}
        payment_info = extra_info.get('payment_info')
        
        if payment_info and isinstance(payment_info, dict):
            # ساخت یک payment entry
            payment = InvoicePaymentDto(
                iinn=payment_info.get('iinn', ''),
                acn=payment_info.get('account_number', ''),
                trmn=payment_info.get('terminal', ''),
                trn=payment_info.get('transaction_ref', ''),
                pcn=payment_info.get('card_number', ''),
                pid=payment_info.get('payment_id', ''),
                pdt=payment_info.get('payment_date', timestamp_to_unix_ms(datetime.utcnow())),
                pv=round_to_int(payment_info.get('amount', 0)),
                pt=payment_info.get('payment_type', 1),  # 1=کارت
            )
            payments.append(payment)
        
        return payments


def build_invoice_for_moadian(
    document: Dict[str, Any],
    tax_setting: Any,
) -> InvoiceDto:
    """
    تابع کمکی برای ساخت DTO فاکتور
    
    Args:
        document: داده‌های فاکتور
        tax_setting: تنظیمات مالیاتی
    
    Returns:
        InvoiceDto آماده برای ارسال
    """
    builder = InvoiceBuilder(seller_economic_code=tax_setting.economic_code)
    return builder.build_invoice_dto(document, tax_setting)




