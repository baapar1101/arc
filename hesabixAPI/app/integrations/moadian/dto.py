"""
Data Transfer Objects (DTOs) برای سامانه مودیان مالیاتی
هم‌تراز با Snapp-Market-Pro/moadian و مستندات رسمی سازمان امور مالیاتی
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field, asdict
from datetime import datetime
import json


def _to_dict_keep_nulls(data: Dict[str, Any], *, skip_keys: set[str] | None = None) -> Dict[str, Any]:
    """معادل تقریبی PrimitiveDto::toArray در SDK PHP (شامل nullهای مقداردهی‌شده)."""
    skip = skip_keys or set()
    return {k: v for k, v in data.items() if k not in skip}


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
    inty: int  # نوع صورت‌حساب (۱ عادی، ۲ ساده)
    inp: int  # الگوی صورت‌حساب: ۱ فروش، ۲ برگشت از فروش، ۳ ابطال، ۴ اصلاحی
    ins: int  # موضوع فاکتور
    tins: str  # شماره اقتصادی فروشنده

    # اختیاری
    irtaxid: Optional[str] = None  # شماره یکتای مالیاتی مرجع
    billid: Optional[str] = None
    tob: Optional[int] = None  # نوع خریدار: ۱ حقیقی، ۲ حقوقی، ۳ مشارکت مدنی، ۴ اتباع
    bid: Optional[str] = None  # شماره ملی / شناسه خریدار حقیقی
    tinb: Optional[str] = None  # شماره اقتصادی خریدار
    sbc: Optional[str] = None
    bpc: Optional[str] = None  # کد پستی خریدار
    bbc: Optional[str] = None
    bpn: Optional[str] = None
    scln: Optional[str] = None
    scc: Optional[str] = None
    crn: Optional[str] = None
    ft: Optional[int] = None
    cdcn: Optional[str] = None
    cdcd: Optional[str] = None

    tprdis: Optional[int] = None
    tdis: Optional[int] = None
    tadis: Optional[int] = None
    tvam: Optional[int] = None
    todam: Optional[int] = None
    tbill: Optional[int] = None
    setm: Optional[int] = None  # روش تسویه: ۱ نقد، ۲ نسیه، ۳ نقد و نسیه
    cap: Optional[int] = None
    insp: Optional[int] = None
    tvop: Optional[int] = None
    tax17: Optional[int] = None

    def to_dict(self) -> Dict[str, Any]:
        """تبدیل به dictionary — فیلدهای None حذف می‌شوند (فقط مقداردهی‌شده‌ها)."""
        return {k: v for k, v in asdict(self).items() if v is not None}


@dataclass
class InvoiceBodyDto:
    """
    Body (ردیف کالا/خدمت) فاکتور مالیاتی
    """
    sstid: str
    sstt: str
    mu: str
    am: int
    fee: int
    prdis: int
    dis: int
    adis: int
    vra: int  # نرخ مالیات بر حسب درصد (۹٪ → ۹)
    vam: int
    tsstam: int

    odt: Optional[int] = None
    odr: Optional[int] = None
    ssrv: Optional[int] = None
    vop: Optional[int] = None
    consfee: Optional[int] = None
    spro: Optional[int] = None
    bros: Optional[int] = None
    tcpbs: Optional[int] = None
    cop: Optional[int] = None
    cut: Optional[int] = None
    exr: Optional[int] = None
    bsrn: Optional[str] = None
    tins: Optional[str] = None
    nw: Optional[int] = None
    ssrv_description: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            k: v
            for k, v in asdict(self).items()
            if v is not None and k != "ssrv_description"
        }


@dataclass
class InvoicePaymentDto:
    """
    روش پرداخت — فیلدها مطابق SDK PHP (InvoicePaymentDto).
    """
    iinn: Optional[str] = None
    acn: Optional[str] = None
    trmn: Optional[str] = None
    trn: Optional[str] = None
    pcn: Optional[str] = None
    pid: Optional[str] = None
    pdt: Optional[int] = None
    pmt: Optional[int] = None  # نوع پرداخت

    def to_dict(self) -> Dict[str, Any]:
        # مثل PrimitiveDto PHP: nullهای مقداردهی‌شده حفظ می‌شوند
        return _to_dict_keep_nulls(asdict(self))


@dataclass
class InvoiceDto:
    """
    DTO کامل فاکتور مالیاتی برای ارسال به سامانه مودیان
    """
    header: InvoiceHeaderDto
    body: List[InvoiceBodyDto]
    payments: List[InvoicePaymentDto] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """تبدیل به dictionary مطابق InvoiceDto::toArray در SDK PHP."""
        return {
            "header": self.header.to_dict(),
            "body": [item.to_dict() for item in self.body],
            "payments": [p.to_dict() for p in self.payments],
            "extension": None,
        }

    def to_json(self) -> str:
        """تبدیل به JSON string (برای رمزنگاری AES، مثل json_encode در PHP)."""
        return json.dumps(self.to_dict(), ensure_ascii=False, separators=(",", ":"))


@dataclass
class MoadianApiResponse:
    success: bool
    timestamp: str
    result: Optional[Dict[str, Any]] = None
    error: Optional[Dict[str, Any]] = None

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "MoadianApiResponse":
        return cls(
            success=data.get("success", False),
            timestamp=data.get("timestamp", datetime.utcnow().isoformat()),
            result=data.get("result"),
            error=data.get("error"),
        )


@dataclass
class InvoiceSubmissionResult:
    invoice_id: int
    reference_number: Optional[str] = None
    uid: Optional[str] = None
    status: str = "pending"
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    warnings: List[str] = field(default_factory=list)
    raw_response: Optional[Dict[str, Any]] = None
    submitted_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class InvoiceInquiryResult:
    reference_number: str
    status: str
    uid: Optional[str] = None
    confirmation_date: Optional[str] = None
    tax_authority_message: Optional[str] = None
    errors: List[str] = field(default_factory=list)
    raw_response: Optional[Dict[str, Any]] = None
    inquired_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
