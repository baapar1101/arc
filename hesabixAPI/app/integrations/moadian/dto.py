"""
Data Transfer Objects (DTOs) برای سامانه مودیان مالیاتی
بر اساس مستندات رسمی سازمان امور مالیاتی
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field, asdict
from datetime import datetime
import json


@dataclass
class InvoiceHeaderDto:
    """
    Header فاکتور مالیاتی
    """
    # الزامی
    taxid: str  # شناسه یکتای مالیاتی (الگوریتم خاص)
    indatim: int  # تاریخ و زمان صدور (Unix timestamp milliseconds)
    indati2m: int  # زمان صدور فاکتور (Unix timestamp milliseconds)
    inno: str  # شماره سریال فاکتور (normalized)
    inty: int  # نوع صورت‌حساب (طبق مستند سامانه؛ مثلاً ۱ عادی، ۲ ساده)
    inp: int  # الگوی صورت‌حساب: ۱ فروش، ۲ برگشت از فروش، ۳ ابطال
    ins: int  # موضوع فاکتور: 1=فروش، 2=فروش ارزی، 3=خرید، 4=...
    tins: str  # شماره اقتصادی فروشنده
    
    # اختیاری
    irtaxid: Optional[str] = None  # شماره یکتای مالیاتی مرجع (برای برگشت)
    billid: Optional[str] = None  # شماره قبض / سریال سفارش
    tob: Optional[int] = None  # نوع خریدار: ۱ حقوقی، ۲ حقیقی، ۳ اتباع، ۴ گذرنامه
    bid: Optional[str] = None  # شماره اشتراک / پروانه
    tinb: Optional[str] = None  # شماره اقتصادی خریدار
    sbc: Optional[str] = None  # شناسه یکتای ثبت قرارداد
    bbc: Optional[str] = None  # شماره ثبت شعبه
    bpn: Optional[str] = None  # شماره پروانه / ثبت
    scln: Optional[str] = None  # کد رهگیری گمرکی
    scc: Optional[str] = None  # کد فروشنده در سامانه
    crn: Optional[str] = None  # شماره گواهی ارزش افزوده
    ft: Optional[int] = None  # نوع پرواز (برای بلیط هواپیما)
    cdcn: Optional[str] = None  # شماره صورت حساب مرجع
    cdcd: Optional[str] = None  # تاریخ صورت حساب مرجع

    # جمع‌های سطح هدر (برای تطابق با کارپوشه / الگوی moadian-full)
    tprdis: Optional[int] = None  # جمع مبلغ قبل از تخفیف
    tdis: Optional[int] = None  # جمع تخفیفات
    tadis: Optional[int] = None  # جمع مبلغ پس از تخفیف
    tvam: Optional[int] = None  # جمع مالیات و عوارض
    todam: Optional[int] = None  # جمع سایر مالیات و عوارض
    tbill: Optional[int] = None  # جمع صورت‌حساب
    setm: Optional[int] = None  # روش تسویه: ۱ نقد، ۲ نسیه، ۳ نقد و نسیه
    cap: Optional[int] = None  # مبلغ پرداختی نقدی
    insp: Optional[int] = None  # مبلغ نسیه
    tvop: Optional[int] = None  # مجموع سهم مالیات و عوارض از پرداخت
    tax17: Optional[int] = None  # مالیات ماده ۱۷

    def to_dict(self) -> Dict[str, Any]:
        """تبدیل به dictionary با حذف مقادیر None"""
        result = {}
        for key, value in asdict(self).items():
            if value is not None:
                result[key] = value
        return result


@dataclass
class InvoiceBodyDto:
    """
    Body (ردیف کالا/خدمت) فاکتور مالیاتی
    """
    # الزامی
    sstid: str  # کد کالا یا خدمت در سامانه مالیاتی (13 رقم)
    sstt: str  # شرح کالا یا خدمت
    mu: str  # واحد اندازه‌گیری (کد استاندارد)
    am: int  # تعداد / مقدار
    fee: int  # مبلغ واحد (بدون اعشار)
    prdis: int  # جمع مبلغ قبل از تخفیف (مثلاً تعداد × فی)
    dis: int  # مبلغ تخفیف
    adis: int  # مبلغ پس از تخفیف (پایه مالیات)
    vra: int  # نرخ مالیات و عوارض (درصد × ۱۰۰، مثلاً ۹۰۰ = ۹٪)
    vam: int  # مبلغ مالیات و عوارض (بدون اعشار)
    tsstam: int  # مبلغ کل پس از تخفیف و مالیات (بدون اعشار)
    
    # اختیاری
    odt: Optional[int] = None  # تاریخ تولید (yyyyMMdd)
    odr: Optional[int] = None  # تاریخ انقضا (yyyyMMdd)
    ssrv: Optional[int] = None  # نوع کالا: 0=کالا، 1=خدمت
    vop: Optional[int] = None  # سهم مالیات و عوارض (معمولاً برابر vam)
    consfee: Optional[int] = None  # حق العمل / کارمزد (بدون اعشار)
    spro: Optional[int] = None  # مالیات سایر مشمولین
    bros: Optional[int] = None  # کمیسیون / کارمزد واسطه‌گری
    tcpbs: Optional[int] = None  # مجموع مبلغ قبل از کسر تخفیف
    cop: Optional[int] = None  # سهم نقدی پرداخت‌کننده
    cut: Optional[int] = None  # مالیات گمرکی
    exr: Optional[int] = None  # نرخ ارز (برای فاکتور ارزی)
    bsrn: Optional[str] = None  # شماره سریال رهگیری کالا
    tins: Optional[str] = None  # کد اقتصادی فروشنده اصلی
    nw: Optional[int] = None  # وزن خالص
    ssrv_description: Optional[str] = None  # توضیحات نوع خدمت

    def to_dict(self) -> Dict[str, Any]:
        """تبدیل به dictionary با حذف مقادیر None"""
        result = {}
        for key, value in asdict(self).items():
            if value is not None and key != 'ssrv_description':
                result[key] = value
        return result


@dataclass
class InvoicePaymentDto:
    """
    روش پرداخت فاکتور مالیاتی
    """
    # الزامی
    iinn: str  # شماره حساب / شناسه پرداخت
    acn: str  # شماره حساب
    trmn: str  # شماره پایانه / ترمینال
    trn: str  # شماره پیگیری / مرجع تراکنش
    pcn: str  # شماره کارت پرداخت‌کننده
    pid: str  # شناسه پرداخت (Payment ID)
    pdt: int  # تاریخ پرداخت (Unix timestamp milliseconds)
    pv: int  # مبلغ پرداخت (بدون اعشار)
    pt: int  # نوع پرداخت: 1=کارت، 2=نقد، 3=چک، 4=اعتباری، 5=سایر

    def to_dict(self) -> Dict[str, Any]:
        """تبدیل به dictionary"""
        return asdict(self)


@dataclass
class InvoiceDto:
    """
    DTO کامل فاکتور مالیاتی برای ارسال به سامانه مودیان
    """
    header: InvoiceHeaderDto
    body: List[InvoiceBodyDto]
    payments: List[InvoicePaymentDto] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """تبدیل به dictionary برای ارسال به API"""
        return {
            "header": self.header.to_dict(),
            "body": [item.to_dict() for item in self.body],
            "payments": [p.to_dict() for p in self.payments],
        }

    def to_json(self) -> str:
        """تبدیل به JSON string"""
        return json.dumps(self.to_dict(), ensure_ascii=False, separators=(',', ':'))


@dataclass
class MoadianApiResponse:
    """
    پاسخ استاندارد API سامانه مودیان
    """
    success: bool
    timestamp: str
    result: Optional[Dict[str, Any]] = None
    error: Optional[Dict[str, Any]] = None

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'MoadianApiResponse':
        return cls(
            success=data.get('success', False),
            timestamp=data.get('timestamp', datetime.utcnow().isoformat()),
            result=data.get('result'),
            error=data.get('error'),
        )


@dataclass
class InvoiceSubmissionResult:
    """
    نتیجه ارسال فاکتور به سامانه
    """
    invoice_id: int
    reference_number: Optional[str] = None  # کد رهگیری سامانه
    uid: Optional[str] = None  # شناسه یکتای فاکتور در سامانه
    status: str = "pending"  # pending, sent, finalized, failed
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    warnings: List[str] = field(default_factory=list)
    raw_response: Optional[Dict[str, Any]] = None
    submitted_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class InvoiceInquiryResult:
    """
    نتیجه استعلام وضعیت فاکتور
    """
    reference_number: str
    status: str  # pending, sent, accepted, finalized, rejected, failed
    uid: Optional[str] = None
    confirmation_date: Optional[str] = None
    tax_authority_message: Optional[str] = None
    errors: List[str] = field(default_factory=list)
    raw_response: Optional[Dict[str, Any]] = None
    inquired_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)




