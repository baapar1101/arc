from __future__ import annotations

from typing import Dict, Any, Optional
from decimal import Decimal
from datetime import datetime
from sqlalchemy.orm import Session
import logging

from app.core.responses import ApiError
from adapters.db.models.ai_invoice import AIInvoice, AIInvoiceType, AIInvoiceStatus
from adapters.db.models.ai_subscription import UserAISubscription
from adapters.db.repositories.ai_invoice_repository import AIInvoiceRepository
from app.services.wallet_service import (
    _get_current_fiscal_year,
    _resolve_wallet_currency_id,
    _get_fixed_account_by_code,
    _create_simple_document
)

logger = logging.getLogger(__name__)


def _build_invoice_code(db: Session) -> str:
    """تولید کد صورتحساب"""
    from datetime import date
    today = date.today()
    prefix = f"AI-{today.strftime('%Y%m%d')}"
    
    from adapters.db.models.ai_invoice import AIInvoice
    last_invoice = (
        db.query(AIInvoice)
        .filter(AIInvoice.code.like(f"{prefix}-%"))
        .order_by(AIInvoice.code.desc())
        .first()
    )
    
    if last_invoice:
        try:
            last_num = int(str(last_invoice.code).split("-")[-1])
            next_num = last_num + 1
        except Exception:
            next_num = 1
    else:
        next_num = 1
    
    return f"{prefix}-{next_num:04d}"


def create_subscription_invoice(
    db: Session,
    subscription_id: int,
    business_id: int,
    amount: Decimal,
    period: str,
    currency_id: int
) -> AIInvoice:
    """ایجاد صورتحساب اشتراک"""
    invoice_code = _build_invoice_code(db)
    
    invoice = AIInvoice(
        subscription_id=subscription_id,
        business_id=business_id,
        invoice_type=AIInvoiceType.SUBSCRIPTION.value,
        code=invoice_code,
        total=float(amount),
        currency_id=currency_id,
        status=AIInvoiceStatus.ISSUED.value,
        issued_at=datetime.utcnow()
    )
    
    db.add(invoice)
    db.commit()
    db.refresh(invoice)
    return invoice


def create_usage_invoice(
    db: Session,
    business_id: int,
    amount: Decimal,
    currency_id: int,
    usage_logs: Optional[list] = None
) -> AIInvoice:
    """ایجاد صورتحساب برای استفاده اضافی (pay_as_go)"""
    invoice_code = _build_invoice_code(db)
    
    invoice = AIInvoice(
        subscription_id=None,
        business_id=business_id,
        invoice_type=AIInvoiceType.USAGE.value,
        code=invoice_code,
        total=float(amount),
        currency_id=currency_id,
        status=AIInvoiceStatus.ISSUED.value,
        issued_at=datetime.utcnow()
    )
    
    db.add(invoice)
    db.commit()
    db.refresh(invoice)
    return invoice


def pay_ai_invoice_from_wallet(
    db: Session,
    business_id: int,
    invoice_id: int,
    user_id: int
) -> Dict[str, Any]:
    """
    پرداخت صورتحساب AI از کیف پول
    - کسر از WalletAccount
    - ایجاد WalletTransaction
    - ایجاد سند حسابداری
    - به‌روزرسانی invoice
    """
    from adapters.db.models.wallet import WalletAccount, WalletTransaction
    from decimal import Decimal as D
    
    invoice = db.query(AIInvoice).filter(
        AIInvoice.id == invoice_id,
        AIInvoice.business_id == business_id
    ).first()
    
    if not invoice:
        raise ApiError("INVOICE_NOT_FOUND", "صورتحساب یافت نشد", http_status=404)
    
    if invoice.status != AIInvoiceStatus.ISSUED.value:
        raise ApiError("INVALID_INVOICE_STATUS", f"صورتحساب در وضعیت {invoice.status} است", http_status=400)
    
    # دریافت حساب کیف پول
    account = db.query(WalletAccount).filter(
        WalletAccount.business_id == business_id
    ).with_for_update().first()
    
    if account is None:
        from app.services.wallet_service import _ensure_wallet_account
        account = _ensure_wallet_account(db, business_id)
    
    available = D(str(account.available_balance or 0))
    total_price = D(str(invoice.total))
    
    if available < total_price:
        raise ApiError("INSUFFICIENT_FUNDS", "موجودی کیف پول کافی نیست", http_status=400)
    
    # کسر از کیف پول
    account.available_balance = float(available - total_price)
    db.flush()
    
    # ایجاد سند حسابداری
    document_id = None
    try:
        document_id = _create_ai_invoice_document(
            db=db,
            business_id=business_id,
            user_id=user_id,
            invoice=invoice,
            amount=total_price
        )
    except Exception as e:
        logger.error(f"خطا در ایجاد سند حسابداری: {e}", exc_info=True)
        db.rollback()
        raise
    
    # ایجاد تراکنش کیف پول
    tx = WalletTransaction(
        business_id=business_id,
        type="ai_subscription" if invoice.invoice_type == AIInvoiceType.SUBSCRIPTION.value else "ai_usage",
        status="succeeded",
        amount=total_price,
        fee_amount=D("0"),
        description=f"پرداخت صورتحساب AI {invoice.code}",
        external_ref=str(invoice.id),
        document_id=document_id
    )
    db.add(tx)
    db.flush()
    
    # به‌روزرسانی invoice
    invoice.status = AIInvoiceStatus.PAID.value
    invoice.paid_at = datetime.utcnow()
    invoice.wallet_transaction_id = tx.id
    invoice.document_id = document_id
    
    db.commit()
    
    return {
        "invoice_id": invoice.id,
        "status": invoice.status,
        "wallet_transaction_id": tx.id,
        "document_id": document_id
    }


def _create_ai_invoice_document(
    db: Session,
    business_id: int,
    user_id: int,
    invoice: AIInvoice,
    amount: Decimal
) -> int:
    """ایجاد سند حسابداری برای صورتحساب AI"""
    currency_id = _resolve_wallet_currency_id(db)
    wallet_acc = _get_fixed_account_by_code(db, "10205")  # حساب کیف پول
    ai_expense_acc = _get_fixed_account_by_code(db, "70508")  # هزینه هوش مصنوعی
    
    lines = [
        {
            "account_id": ai_expense_acc.id,
            "debit": amount,
            "credit": 0,
            "description": f"هزینه AI - {invoice.code}"
        },
        {
            "account_id": wallet_acc.id,
            "debit": 0,
            "credit": amount,
            "description": "پرداخت از کیف پول"
        }
    ]
    
    document = _create_simple_document(
        db=db,
        business_id=business_id,
        user_id=user_id,
        document_type="payment",
        currency_id=currency_id,
        document_date=invoice.issued_at.date() if invoice.issued_at else datetime.utcnow().date(),
        description=f"پرداخت صورتحساب AI - {invoice.code}",
        accounting_lines=lines
    )
    
    return int(document.id)


def _create_ai_usage_document(
    db: Session,
    business_id: int,
    user_id: int,
    amount: Decimal,
    input_tokens: int,
    output_tokens: int
) -> int:
    """
    ایجاد سند حسابداری برای هزینه استفاده از AI
    Dr: هزینه هوش مصنوعی (حساب هزینه - 70508)
    Cr: کیف پول (حساب کیف پول - 10205)
    """
    currency_id = _resolve_wallet_currency_id(db)
    wallet_acc = _get_fixed_account_by_code(db, "10205")  # حساب کیف پول
    ai_expense_acc = _get_fixed_account_by_code(db, "70508")  # هزینه هوش مصنوعی
    
    lines = [
        {
            "account_id": ai_expense_acc.id,
            "debit": amount,
            "credit": 0,
            "description": f"هزینه استفاده از AI ({input_tokens} ورودی + {output_tokens} خروجی)"
        },
        {
            "account_id": wallet_acc.id,
            "debit": 0,
            "credit": amount,
            "description": "پرداخت از کیف پول"
        }
    ]
    
    document = _create_simple_document(
        db=db,
        business_id=business_id,
        user_id=user_id,
        document_type="payment",
        currency_id=currency_id,
        document_date=datetime.utcnow().date(),
        description=f"هزینه استفاده از هوش مصنوعی - {input_tokens + output_tokens} توکن",
        accounting_lines=lines
    )
    
    return int(document.id)

