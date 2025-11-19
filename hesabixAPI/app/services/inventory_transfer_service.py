from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, date
from decimal import Decimal

from sqlalchemy.orm import Session
from sqlalchemy import and_

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.currency import Currency
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.product import Product
from app.core.responses import ApiError
from app.services.document_monetization_service import ensure_document_policy_allows_creation

# از توابع موجود برای تاریخ و کنترل موجودی استفاده می‌کنیم
from app.services.invoice_service import _parse_iso_date, _get_current_fiscal_year, _ensure_stock_sufficient


DOCUMENT_TYPE_INVENTORY_TRANSFER = "inventory_transfer"


def _build_doc_code(prefix_base: str) -> str:
    today = datetime.now().date()
    prefix = f"{prefix_base}-{today.strftime('%Y%m%d')}"
    return prefix


def _build_transfer_code(db: Session, business_id: int) -> str:
    prefix = _build_doc_code("ITR")
    last_doc = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.code.like(f"{prefix}-%"),
        )
    ).order_by(Document.code.desc()).first()
    if last_doc:
        try:
            last_num = int(last_doc.code.split("-")[-1])
            next_num = last_num + 1
        except Exception:
            next_num = 1
    else:
        next_num = 1
    return f"{prefix}-{next_num:04d}"


def create_inventory_transfer(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    """ایجاد سند انتقال موجودی بین انبارها (بدون ثبت حسابداری)."""

    document_date = _parse_iso_date(data.get("document_date", datetime.now()))
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)

    fiscal_year = _get_current_fiscal_year(db, business_id)

    raw_lines: List[Dict[str, Any]] = list(data.get("lines") or [])
    if not raw_lines:
        raise ApiError("LINES_REQUIRED", "At least one transfer line is required", http_status=400)

    # اعتبارسنجی خطوط و آماده‌سازی برای کنترل کسری
    outgoing_lines: List[Dict[str, Any]] = []
    for i, ln in enumerate(raw_lines, start=1):
        pid = ln.get("product_id")
        qty = Decimal(str(ln.get("quantity", 0) or 0))
        src_wh = ln.get("source_warehouse_id")
        dst_wh = ln.get("destination_warehouse_id")
        if not pid or qty <= 0:
            raise ApiError("INVALID_LINE", f"line {i}: product_id and positive quantity are required", http_status=400)
        if src_wh is None or dst_wh is None:
            raise ApiError("WAREHOUSE_REQUIRED", f"line {i}: source_warehouse_id and destination_warehouse_id are required", http_status=400)
        if int(src_wh) == int(dst_wh):
            raise ApiError("INVALID_WAREHOUSES", f"line {i}: source and destination warehouse cannot be the same", http_status=400)

        # فقط برای محصولات کنترل موجودی، کنترل کسری لازم است
        tracked = db.query(Product.track_inventory).filter(
            and_(Product.business_id == business_id, Product.id == int(pid))
        ).scalar()
        if bool(tracked):
            outgoing_lines.append({
                "product_id": int(pid),
                "quantity": float(qty),
                "extra_info": {
                    "warehouse_id": int(src_wh),
                    "movement": "out",
                    "inventory_tracked": True,
                },
            })

    # کنترل کسری موجودی بر مبنای انبار مبدا
    if outgoing_lines:
        _ensure_stock_sufficient(db, business_id, document_date, outgoing_lines)

    # ایجاد سند بدون ثبت حسابداری
    doc_code = _build_transfer_code(db, business_id)

    ensure_document_policy_allows_creation(
        db,
        business_id,
        document_type=DOCUMENT_TYPE_INVENTORY_TRANSFER,
        document_date=document_date,
        amount=Decimal(0),
    )
    document = Document(
        business_id=business_id,
        fiscal_year_id=fiscal_year.id,
        code=doc_code,
        document_type=DOCUMENT_TYPE_INVENTORY_TRANSFER,
        document_date=document_date,
        currency_id=int(currency_id),
        created_by_user_id=user_id,
        registered_at=datetime.utcnow(),
        is_proforma=False,
        description=data.get("description"),
        extra_info={"source": "inventory_transfer"},
    )
    db.add(document)
    db.flush()

    # ایجاد خطوط کالایی: یک خروج از انبار مبدا و یک ورود به انبار مقصد
    for ln in raw_lines:
        pid = int(ln.get("product_id"))
        qty = Decimal(str(ln.get("quantity", 0) or 0))
        src_wh = int(ln.get("source_warehouse_id"))
        dst_wh = int(ln.get("destination_warehouse_id"))
        desc = ln.get("description")

        db.add(DocumentLine(
            document_id=document.id,
            product_id=pid,
            quantity=qty,
            debit=Decimal(0),
            credit=Decimal(0),
            description=desc,
            extra_info={
                "movement": "out",
                "warehouse_id": src_wh,
                "inventory_tracked": True,
            },
        ))
        db.add(DocumentLine(
            document_id=document.id,
            product_id=pid,
            quantity=qty,
            debit=Decimal(0),
            credit=Decimal(0),
            description=desc,
            extra_info={
                "movement": "in",
                "warehouse_id": dst_wh,
                "inventory_tracked": True,
            },
        ))

    db.commit()
    db.refresh(document)

    return {
        "message": "INVENTORY_TRANSFER_CREATED",
        "data": {
            "id": document.id,
            "code": document.code,
            "document_date": document.document_date.isoformat(),
        },
    }


