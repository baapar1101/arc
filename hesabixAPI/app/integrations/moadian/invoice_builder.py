"""
سرویس ساخت DTO فاکتور مالیاتی از روی داده‌های داخلی
"""
from __future__ import annotations

import re
from datetime import datetime
from typing import Any, Dict, List

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
    map_payment_pattern,
    map_invoice_pattern,
    map_invoice_subject,
    validate_national_id,
    validate_economic_code,
)


def _clean_digits(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"[\s\-]", "", str(value).strip())


def _resolve_buyer_tin(national_id: str, economic_code: str) -> str | None:
    """شناسهٔ خریدار برای tinb: اولویت با کد اقتصادی معتبر، سپس کد/شناسه ملی."""
    ec = _clean_digits(economic_code)
    if ec and validate_economic_code(ec):
        return ec
    nid = _clean_digits(national_id)
    if len(nid) in (10, 11) and nid.isdigit():
        return nid
    return None


def _resolve_buyer_tob(national_id: str, economic_code: str) -> int | None:
    """
    نوع خریدار (tob): ۱ حقوقی، ۲ حقیقی.
    """
    nid = _clean_digits(national_id)
    if nid:
        valid, ptype = validate_national_id(nid)
        if valid and ptype == "legal":
            return 1
        if valid and ptype == "natural":
            return 2
    ec = _clean_digits(economic_code)
    if ec and validate_economic_code(ec) and not nid:
        return 1
    return 2 if nid else None


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

    @staticmethod
    def _aggregate_body_totals(body: List[InvoiceBodyDto]) -> Dict[str, int]:
        tprdis = sum(b.prdis for b in body)
        tdis = sum(b.dis for b in body)
        tadis = sum(b.adis for b in body)
        tvam = sum(b.vam for b in body)
        tbill = tadis + tvam
        return {
            "tprdis": tprdis,
            "tdis": tdis,
            "tadis": tadis,
            "tvam": tvam,
            "tbill": tbill,
        }

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
        # ابتدا body تا جمع‌های هدر از روی اقلام پر شود (هم‌راستا با moadian-full)
        body = self._build_body(document)
        body_totals = self._aggregate_body_totals(body)

        extra_info = document.get("extra_info") or {}
        person_snapshot = extra_info.get("person_snapshot") or extra_info.get("person_info") or {}

        setm = self._resolve_settlement_method(extra_info)
        header = self._build_header(
            document,
            person_snapshot,
            tax_setting,
            body_totals=body_totals,
            setm=setm,
        )
        payments = self._build_payments(document)

        return InvoiceDto(
            header=header,
            body=body,
            payments=payments,
        )

    @staticmethod
    def _resolve_settlement_method(extra_info: Dict[str, Any]) -> int:
        """
        setm: ۱ نقد، ۲ نسیه، ۳ نقد و نسیه.
        در صورت نبود سیگنال معتبر، پیش‌فرض نقدی (مطابق رفتار قبلی).
        """
        raw = extra_info.get("tax_settlement_method") or extra_info.get("settlement_method")
        if raw is not None:
            try:
                v = int(raw)
                if v in (1, 2, 3):
                    return v
            except (TypeError, ValueError):
                pass
        if extra_info.get("is_installment") or extra_info.get("installment_plan_id"):
            return 2
        pm = str(extra_info.get("payment_method") or "").strip().lower()
        if pm in ("credit", "نسیه", "installment", "اقساط"):
            return 2
        if pm in ("both", "mixed", "نقد_نسیه", "نقد و نسیه"):
            return 3
        return map_payment_pattern(is_cash=True, is_credit=False)

    def _build_header(
        self,
        document: Dict[str, Any],
        person_snapshot: Dict[str, Any],
        tax_setting: Any,
        *,
        body_totals: Dict[str, int],
        setm: int,
    ) -> InvoiceHeaderDto:
        """ساخت Header فاکتور"""

        doc_date_str = document.get("document_date")
        if isinstance(doc_date_str, str):
            doc_date = datetime.fromisoformat(doc_date_str.replace("Z", "+00:00"))
        else:
            doc_date = datetime.utcnow()

        timestamp_ms = timestamp_to_unix_ms(doc_date)

        client_id = tax_setting.tax_memory_id or tax_setting.economic_code
        taxid = generate_tax_id(
            client_id=client_id,
            timestamp=doc_date,
            internal_id=document.get("id", 0),
        )

        internal_id = document.get("id", 0)
        inno = normalize_invoice_number(internal_id)

        document_type = document.get("document_type", "")
        type_lower = document_type.lower()
        is_return = "return" in type_lower
        is_cancel = "cancel" in type_lower or "ابطال" in document_type

        buyer_national_id = (person_snapshot.get("national_id") or "").strip()
        buyer_economic_code = (person_snapshot.get("economic_code") or "").strip()

        has_buyer_info = bool(buyer_national_id) and validate_economic_code(buyer_economic_code)
        # inty: نوع صورت‌حساب (۱ عادی / ۲ ساده). برگشت با inp=۲ مشخص می‌شود نه inty=۳.
        inty = 1 if has_buyer_info else 2
        inp = map_invoice_pattern(is_return=is_return, is_cancel=is_cancel)

        ins = map_invoice_subject(document_type)

        tins = tax_setting.economic_code

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

        tinb = _resolve_buyer_tin(buyer_national_id, buyer_economic_code)
        if tinb:
            header.tinb = tinb

        tob = _resolve_buyer_tob(buyer_national_id, buyer_economic_code)
        if tob is not None:
            header.tob = tob

        if is_return:
            reference_taxid = (document.get("extra_info") or {}).get("reference_tax_id")
            if reference_taxid:
                header.irtaxid = reference_taxid

        # جمع‌های هدر + روش تسویه (الگوی moadian-full)
        header.tprdis = body_totals["tprdis"]
        header.tdis = body_totals["tdis"]
        header.tadis = body_totals["tadis"]
        header.tvam = body_totals["tvam"]
        header.tbill = body_totals["tbill"]
        header.todam = 0
        header.tax17 = 0
        header.setm = setm
        header.tvop = body_totals["tvam"]
        header.insp = body_totals["tadis"]
        if setm == 1:
            header.cap = body_totals["tbill"]

        return header

    def _build_body(self, document: Dict[str, Any]) -> List[InvoiceBodyDto]:
        """ساخت Body (اقلام فاکتور)"""

        product_lines = document.get("product_lines") or []
        body_items: List[InvoiceBodyDto] = []

        for idx, line in enumerate(product_lines, start=1):
            line_extra = line.get("extra_info") or {}
            tax_snapshot = line_extra.get("tax_snapshot") or {}

            tax_code = tax_snapshot.get("tax_code", "").strip()
            if not tax_code:
                product_name = line.get("product_name", "محصول")
                from app.core.responses import ApiError

                raise ApiError(
                    "PRODUCT_TAX_CODE_MISSING",
                    f"کالای '{product_name}' (ردیف {idx}) فاقد کد مالیاتی است. لطفاً کد مالیاتی را در اطلاعات کالا وارد کنید.",
                    http_status=400,
                    details={
                        "product_id": line.get("product_id"),
                        "product_name": product_name,
                        "line_number": idx,
                    },
                )

            product_name = line.get("product_name", "محصول")

            # واحد اندازه‌گیری مالیاتی؛ ۱۶۴ = عدد (رایج در نمونه‌های مودیان)
            tax_unit_code = (
                tax_snapshot.get("tax_unit_code")
                or tax_snapshot.get("product_main_unit")
                or "164"
            )

            quantity = round_to_int(line.get("quantity", 0))

            unit_price = round_to_int(
                line_extra.get("unit_price") if line_extra.get("unit_price") is not None else line.get("unit_price", 0)
            )
            discount = round_to_int(
                line_extra.get("line_discount")
                if line_extra.get("line_discount") is not None
                else line.get("line_discount", 0)
            )

            prdis = quantity * unit_price
            adis = prdis - discount

            tax_rate_raw = line_extra.get("tax_rate")
            if tax_rate_raw is None:
                tax_rate_raw = line.get("tax_rate", 0)
            tax_rate: float | int = 0
            try:
                if tax_rate_raw is not None and tax_rate_raw != "":
                    tax_rate = float(tax_rate_raw)
            except (TypeError, ValueError):
                tax_rate = 0

            if not tax_rate and adis > 0:
                tax_amount_raw = line_extra.get("tax_amount")
                if tax_amount_raw is None:
                    tax_amount_raw = line.get("tax_amount")
                try:
                    if tax_amount_raw is not None and float(tax_amount_raw) != 0:
                        tax_rate = (float(tax_amount_raw) / adis) * 100.0
                except (TypeError, ValueError):
                    pass

            vra = calculate_vat_rate(tax_rate)
            # vra به صورت «درصد × ۱۰۰» (۹٪ → ۹۰۰)؛ مالیات = پایه × درصد / ۱۰۰
            vam = round_to_int((adis * vra) / 10000) if vra > 0 else 0

            tsstam = adis + vam

            body_item = InvoiceBodyDto(
                sstid=tax_code,
                sstt=product_name[:200],
                mu=str(tax_unit_code),
                am=quantity,
                fee=unit_price,
                prdis=prdis,
                dis=discount,
                adis=adis,
                vra=vra,
                vam=vam,
                tsstam=tsstam,
                vop=vam,
            )

            product_type = tax_snapshot.get("product_type", "product")
            body_item.ssrv = 1 if product_type == "service" else 0

            body_items.append(body_item)

        return body_items

    def _build_payments(self, document: Dict[str, Any]) -> List[InvoicePaymentDto]:
        """
        ساخت اطلاعات پرداخت (اختیاری)
        در صورتی که اطلاعات پرداخت موجود نباشد، لیست خالی برمی‌گردد
        """

        payments: List[InvoicePaymentDto] = []

        extra_info = document.get("extra_info") or {}
        payment_info = extra_info.get("payment_info")

        if payment_info and isinstance(payment_info, dict):
            payment = InvoicePaymentDto(
                iinn=payment_info.get("iinn", ""),
                acn=payment_info.get("account_number", ""),
                trmn=payment_info.get("terminal", ""),
                trn=payment_info.get("transaction_ref", ""),
                pcn=payment_info.get("card_number", ""),
                pid=payment_info.get("payment_id", ""),
                pdt=payment_info.get("payment_date", timestamp_to_unix_ms(datetime.utcnow())),
                pv=round_to_int(payment_info.get("amount", 0)),
                pt=payment_info.get("payment_type", 1),
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
