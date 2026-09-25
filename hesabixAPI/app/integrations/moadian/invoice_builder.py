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
    coerce_to_datetime,
    generate_tax_id,
    normalize_invoice_number,
    normalize_moadian_unit_code,
    timestamp_to_unix_ms,
    round_to_int,
    calculate_vat_rate,
    map_payment_pattern,
    map_invoice_pattern,
    map_invoice_subject_for_inp,
    validate_national_id,
    validate_economic_code,
)


def _clean_digits(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"[\s\-]", "", str(value).strip())


def build_person_snapshot_from_person(person: Any) -> Dict[str, Any]:
    """ساخت person_snapshot از مدل Person برای ارسال به مودیان."""
    if not person:
        return {}
    name = (
        getattr(person, "alias_name", None)
        or (
            f"{getattr(person, 'first_name', '') or ''} {getattr(person, 'last_name', '') or ''}".strip()
            if getattr(person, "first_name", None) or getattr(person, "last_name", None)
            else None
        )
        or getattr(person, "company_name", None)
        or ""
    )
    return {
        "person_id": getattr(person, "id", None),
        "name": name,
        "national_id": (getattr(person, "national_id", None) or "").strip() or None,
        "economic_code": (getattr(person, "economic_id", None) or "").strip() or None,
        "postal_code": (getattr(person, "postal_code", None) or "").strip() or None,
        "address": getattr(person, "address", None),
        "phone": getattr(person, "mobile", None) or getattr(person, "phone", None),
        "legal_entity_type": getattr(person, "legal_entity_type", None),
    }


def ensure_person_snapshot_on_document_dict(db: Any, document_dict: Dict[str, Any]) -> Dict[str, Any]:
    """
    قبل از ارسال به مودیان، person_snapshot را از طرف‌حساب زنده می‌سازد/تازه‌سازی می‌کند.

    snapshot قدیمی (مثلاً کد ملی «0» بعد از پاک‌شدن در کارت شخص) نباید نوع فاکتور
    یا فیلدهای خریدار را منحرف کند. اگر هویت کامل نباشد، builder عمداً نوع ۲ می‌سازد.
    """
    extra = dict(document_dict.get("extra_info") or {})
    person_id = extra.get("person_id")
    if not person_id:
        return document_dict

    try:
        from adapters.db.models.person import Person

        person = db.query(Person).filter(Person.id == int(person_id)).first()
    except Exception:
        person = None

    built = build_person_snapshot_from_person(person)
    if built:
        extra["person_snapshot"] = built
        document_dict = dict(document_dict)
        document_dict["extra_info"] = extra
    return document_dict


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
    نوع خریدار (tob) مطابق مستند رسمی مودیان:
    ۱ حقیقی، ۲ حقوقی، ۳ مشارکت مدنی، ۴ اتباع غیر ایرانی.
    """
    nid = _clean_digits(national_id)
    if nid:
        valid, ptype = validate_national_id(nid)
        if valid and ptype == "natural":
            return 1
        if valid and ptype == "legal":
            return 2
    ec = _clean_digits(economic_code)
    if ec and validate_economic_code(ec) and not nid:
        return 2
    return 1 if nid else None


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
        *,
        submission_mode: str | None = None,
        irtaxid: str | None = None,
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
            submission_mode=submission_mode,
            irtaxid=irtaxid,
        )
        # در صورتحساب ساده، vop و payments معمولاً خارج از الگو هستند
        if header.inty == 2:
            for item in body:
                item.vop = None
        payments = self._build_payments(document, inty=header.inty)

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
        submission_mode: str | None = None,
        irtaxid: str | None = None,
    ) -> InvoiceHeaderDto:
        """ساخت Header فاکتور"""

        doc_date = coerce_to_datetime(document.get("document_date"))
        # اگر فقط تاریخ روز موجود است، ساعت را از registered_at بگیر تا midnights اشتباه ایجاد نشود
        registered_at = document.get("registered_at") or document.get("created_at")
        if registered_at and getattr(doc_date, "hour", 0) == 0 and getattr(doc_date, "minute", 0) == 0:
            try:
                reg_dt = coerce_to_datetime(registered_at)
                if reg_dt.date() == doc_date.date():
                    doc_date = reg_dt
            except Exception:
                pass

        timestamp_ms = timestamp_to_unix_ms(doc_date)

        client_id = tax_setting.tax_memory_id or tax_setting.economic_code
        internal_id = document.get("_tax_internal_id_override") or document.get("id", 0)
        taxid = generate_tax_id(
            client_id=client_id,
            timestamp=doc_date,
            internal_id=int(internal_id),
        )

        inno = normalize_invoice_number(internal_id)

        document_type = document.get("document_type", "")
        type_lower = document_type.lower()
        mode = (submission_mode or "").strip().lower()
        is_return = mode == "return" or ("return" in type_lower and mode not in ("cancel", "corrective"))
        is_cancel = mode == "cancel" or ("cancel" in type_lower or "ابطال" in document_type)
        is_corrective = mode == "corrective" or "corrective" in type_lower or "اصلاح" in document_type

        buyer_national_id = (person_snapshot.get("national_id") or "").strip()
        buyer_economic_code = (person_snapshot.get("economic_code") or "").strip()
        # کد اقتصادی نامعتبر را مثل نبودن در نظر بگیر
        if buyer_economic_code and not validate_economic_code(buyer_economic_code):
            buyer_economic_code = ""

        nid_clean = _clean_digits(buyer_national_id)
        nid_valid, nid_type = validate_national_id(nid_clean) if nid_clean else (False, None)
        has_valid_economic = bool(buyer_economic_code and validate_economic_code(buyer_economic_code))
        postal_code = _clean_digits(person_snapshot.get("postal_code") or "")

        # صورتحساب نوع ۱ فقط وقتی هویت خریدار برای مودیان قابل قبول است:
        # - کد اقتصادی معتبر (tinb) داشته باشیم، یا
        # - حقیقی با کد ملی معتبر + کد پستی (الزام رایج نوع ۱)
        # در غیر این صورت نوع ۲ (ساده/مصرف‌کننده) بدون اطلاعات خریدار.
        has_buyer_info = has_valid_economic or (
            nid_valid and nid_type == "natural" and len(postal_code) >= 10
        )

        inty = 1 if has_buyer_info else 2
        inp = map_invoice_pattern(
            is_return=is_return,
            is_cancel=is_cancel,
            is_corrective=is_corrective,
        )
        ins = map_invoice_subject_for_inp(inp, document_type)

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

        tob = _resolve_buyer_tob(buyer_national_id, buyer_economic_code)

        if inty == 1:
            if tob is not None:
                header.tob = tob
            if has_valid_economic:
                header.tinb = buyer_economic_code
            if tob == 1 and nid_valid and nid_type == "natural":
                header.bid = nid_clean
                if postal_code:
                    header.bpc = postal_code
            elif tob == 2 and nid_valid and nid_type == "legal" and not has_valid_economic:
                header.bid = nid_clean
        # else: نوع ۲ — بدون فیلد خریدار

        resolved_irtaxid = irtaxid or (document.get("extra_info") or {}).get("reference_tax_id")
        if resolved_irtaxid and inp in (2, 3, 4):
            header.irtaxid = str(resolved_irtaxid).strip()

        # جمع‌های هدر
        header.tprdis = body_totals["tprdis"]
        header.tdis = body_totals["tdis"]
        header.tadis = body_totals["tadis"]
        header.tvam = body_totals["tvam"]
        header.tbill = body_totals["tbill"]
        header.todam = 0
        header.tax17 = 0

        # روش تسویه فقط برای صورتحساب نوع اول
        if inty == 1:
            header.setm = setm
            if body_totals["tvam"] > 0:
                header.tvop = body_totals["tvam"]
            if setm == 1:
                header.cap = body_totals["tbill"]
            elif setm == 2:
                header.insp = body_totals["tbill"]
            else:
                header.cap = body_totals["tbill"]

        return header

    def _build_body(self, document: Dict[str, Any]) -> List[InvoiceBodyDto]:
        """ساخت Body (اقلام فاکتور)"""

        product_lines = document.get("product_lines") or []
        body_items: List[InvoiceBodyDto] = []

        for idx, line in enumerate(product_lines, start=1):
            line_extra = line.get("extra_info") or {}
            tax_snapshot = line_extra.get("tax_snapshot") or {}

            tax_code = (tax_snapshot.get("tax_code") or line.get("product_tax_code") or "").strip()
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
            if not tax_snapshot.get("tax_code"):
                tax_snapshot = dict(tax_snapshot)
                tax_snapshot["tax_code"] = tax_code

            product_name = line.get("product_name", "محصول")

            # واحد اندازه‌گیری مالیاتی باید کد عددی مودیان باشد (نه نام فارسی)
            tax_unit_raw = (
                tax_snapshot.get("tax_unit_code")
                or tax_snapshot.get("product_main_unit")
                or line.get("product_main_unit")
                or "1627"
            )
            tax_unit_code = normalize_moadian_unit_code(tax_unit_raw)

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
            # vra درصد واقعی (۹٪ → ۹)؛ مالیات = پایه × درصد / ۱۰۰
            vam = round_to_int((adis * vra) / 100) if vra > 0 else 0

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
                vop=vam if vam > 0 else None,
            )

            # توجه: ssrv در سامانه مودیان «ارزش ریالی» است (نه پرچم کالا/خدمت).
            # ارسال ssrv=0 باعث خطای 0107305 می‌شود؛ فقط در صورت مقدار واقعی ست شود.
            ssrv_raw = tax_snapshot.get("ssrv")
            if ssrv_raw is not None:
                try:
                    ssrv_val = round_to_int(ssrv_raw)
                    if ssrv_val > 0:
                        body_item.ssrv = ssrv_val
                except (TypeError, ValueError):
                    pass

            body_items.append(body_item)

        return body_items

    def _build_payments(self, document: Dict[str, Any], *, inty: int = 1) -> List[InvoicePaymentDto]:
        """
        ساخت اطلاعات پرداخت مطابق SDK PHP / نسخه قدیمی حسابیکس.
        برای صورتحساب ساده (inty=2) معمولاً payments خالی است.
        """
        if inty == 2:
            return []

        extra_info = document.get("extra_info") or {}
        payment_info = extra_info.get("payment_info")

        if payment_info and isinstance(payment_info, dict):
            return [
                InvoicePaymentDto(
                    iinn=payment_info.get("iinn") or None,
                    acn=payment_info.get("account_number") or payment_info.get("acn") or None,
                    trmn=payment_info.get("terminal") or payment_info.get("trmn") or None,
                    trn=payment_info.get("transaction_ref") or payment_info.get("trn") or None,
                    pcn=payment_info.get("card_number") or payment_info.get("pcn") or None,
                    pid=payment_info.get("payment_id") or payment_info.get("pid") or None,
                    pdt=payment_info.get("payment_date") or payment_info.get("pdt"),
                    pmt=payment_info.get("payment_type") or payment_info.get("pmt"),
                )
            ]

        return [
            InvoicePaymentDto(
                iinn=None,
                acn=None,
                trmn=None,
                trn=None,
                pcn=None,
                pid=None,
                pdt=None,
                pmt=None,
            )
        ]


def build_invoice_for_moadian(
    document: Dict[str, Any],
    tax_setting: Any,
    *,
    submission_mode: str | None = None,
    irtaxid: str | None = None,
) -> InvoiceDto:
    """
    تابع کمکی برای ساخت DTO فاکتور

    Args:
        document: داده‌های فاکتور
        tax_setting: تنظیمات مالیاتی
        submission_mode: normal | return | cancel | corrective
        irtaxid: شناسه مالیاتی مرجع (برای برگشت/ابطال/اصلاح)

    Returns:
        InvoiceDto آماده برای ارسال
    """
    builder = InvoiceBuilder(seller_economic_code=tax_setting.economic_code)
    return builder.build_invoice_dto(
        document,
        tax_setting,
        submission_mode=submission_mode,
        irtaxid=irtaxid,
    )
