"""
مدیریت بارکدهای عمومی کالا: پارس، نرمال‌سازی، یکتایی در سطح کسب‌وکار و همگام‌سازی ایندکس.
"""

from __future__ import annotations

from typing import List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.product_general_barcode_alias import ProductGeneralBarcodeAlias
from adapters.db.models.product_instance import ProductInstance
from app.core.responses import ApiError

MAX_GENERAL_BARCODE_TOKENS = 64
MAX_GENERAL_BARCODE_TOKEN_LEN = 128
MAX_GENERAL_BARCODE_TOTAL_CHARS = 8192


def split_raw_general_barcodes(raw: Optional[str]) -> List[str]:
    """تقسیم ورودی خام بر اساس ویرگول (انگلیسی یا فارسی) و فیدهای معمول."""
    if raw is None:
        return []
    s = str(raw).strip()
    if not s:
        return []
    for sep in ("\n", "\r", "،"):
        s = s.replace(sep, ",")
    parts: List[str] = []
    for piece in s.split(","):
        t = piece.strip()
        if t:
            parts.append(t)
    return parts


def normalize_general_barcodes_storage(raw: Optional[str]) -> Tuple[Optional[str], List[str]]:
    """
    برگرداندن (رشتهٔ ذخیره‌شده برای products.general_barcodes, لیست توکن‌های قابل قبول برای ایندکس)

    یکتایی بدون حساسیت به حروف در خروجی لیست؛ نخستین املای واردشده برای نمایش حفظ می‌شود.
    """
    parts = split_raw_general_barcodes(raw)
    if not parts:
        return None, []

    seen_lower: set[str] = set()
    display_tokens: List[str] = []
    for p in parts:
        if len(p) > MAX_GENERAL_BARCODE_TOKEN_LEN:
            raise ApiError(
                "GENERAL_BARCODE_TOKEN_TOO_LONG",
                f"هر بارکد عمومی حداکثر {MAX_GENERAL_BARCODE_TOKEN_LEN} نویسه می‌تواند داشته باشد",
                http_status=400,
            )
        key = p.lower()
        if key in seen_lower:
            continue
        seen_lower.add(key)
        display_tokens.append(p)

    if len(display_tokens) > MAX_GENERAL_BARCODE_TOKENS:
        raise ApiError(
            "GENERAL_BARCODE_TOO_MANY",
            f"حداکثر {MAX_GENERAL_BARCODE_TOKENS} بارکد عمومی برای هر کالا مجاز است",
            http_status=400,
        )

    joined = ",".join(display_tokens)
    if len(joined) > MAX_GENERAL_BARCODE_TOTAL_CHARS:
        raise ApiError(
            "GENERAL_BARCODE_TOTAL_TOO_LONG",
            "طول مجموع بارکدهای عمومی بیش از حد مجاز است",
            http_status=400,
        )
    return joined, display_tokens


def _normalized_tokens(display_tokens: List[str]) -> List[str]:
    return [t.lower() for t in display_tokens]


def assert_tokens_unique_among_products(
    db: Session,
    business_id: int,
    display_tokens: List[str],
    exclude_product_id: Optional[int],
) -> None:
    """هر توکن در کل کسب‌وکار حداکثر به یک کالا تعلق دارد."""
    if not display_tokens:
        return
    norms = _normalized_tokens(display_tokens)
    q = db.query(ProductGeneralBarcodeAlias).filter(
        ProductGeneralBarcodeAlias.business_id == business_id,
        ProductGeneralBarcodeAlias.token_normalized.in_(norms),
    )
    if exclude_product_id is not None:
        q = q.filter(ProductGeneralBarcodeAlias.product_id != exclude_product_id)
    conflict = q.first()
    if conflict is not None:
        raise ApiError(
            "DUPLICATE_GENERAL_BARCODE",
            "یکی از بارکدهای عمومی قبلاً برای کالای دیگری ثبت شده است",
            http_status=409,
        )


def assert_tokens_not_used_by_unique_instances(
    db: Session,
    business_id: int,
    display_tokens: List[str],
    exclude_product_id: Optional[int],
) -> None:
    """عدم تداخل با بارکد واحدهای کالای یونیک."""
    if not display_tokens:
        return
    norms = _normalized_tokens(display_tokens)
    q = (
        db.query(ProductInstance.id, ProductInstance.product_id)
        .filter(
            ProductInstance.business_id == business_id,
            ProductInstance.barcode.isnot(None),
            func.lower(ProductInstance.barcode).in_(norms),
        )
    )
    if exclude_product_id is not None:
        q = q.filter(ProductInstance.product_id != exclude_product_id)
    hit = q.first()
    if hit is not None:
        raise ApiError(
            "GENERAL_BARCODE_CONFLICTS_WITH_UNIQUE_INSTANCE",
            "این بارکد برای واحد یک کالای یونیک ثبت شده است؛ ابتدا آن را اصلاح کنید",
            http_status=409,
        )


def replace_general_barcode_aliases(
    db: Session,
    business_id: int,
    product_id: int,
    display_tokens: List[str],
) -> None:
    """حذف ایندکس‌های قبلی و درج مجدد برای این کالا (بدون commit)."""
    db.query(ProductGeneralBarcodeAlias).filter(
        ProductGeneralBarcodeAlias.product_id == product_id,
        ProductGeneralBarcodeAlias.business_id == business_id,
    ).delete(synchronize_session=False)

    norms = _normalized_tokens(display_tokens)
    for token_norm in norms:
        db.add(
            ProductGeneralBarcodeAlias(
                business_id=business_id,
                product_id=product_id,
                token_normalized=token_norm,
            )
        )
