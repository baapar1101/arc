"""خواندن خلاصه مالی و امتیاز پیش‌بین. هیچ سندی اینجا صادر نمی‌شود."""
from __future__ import annotations

from typing import Any

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.crm import CrmProcessStage, Deal
from adapters.db.models.person import Person
from app.services.crm_assistant import predictive_from_counts, whitelist_financial_answer


def deal_predictive_score(db: Session, business_id: int, stage_id: int | None) -> dict[str, Any]:
    closed = (
        db.query(func.count(Deal.id))
        .filter(Deal.business_id == business_id, Deal.closed_at.isnot(None))
        .scalar()
        or 0
    )
    won = (
        db.query(func.count(Deal.id))
        .join(CrmProcessStage, CrmProcessStage.id == Deal.stage_id)
        .filter(
            Deal.business_id == business_id,
            Deal.closed_at.isnot(None),
            CrmProcessStage.is_win.is_(True),
        )
        .scalar()
        or 0
    )
    stage_closed = 0
    stage_won = 0
    if stage_id is not None:
        stage_closed = (
            db.query(func.count(Deal.id))
            .filter(Deal.business_id == business_id, Deal.closed_at.isnot(None), Deal.stage_id == stage_id)
            .scalar()
            or 0
        )
        stage_won = (
            db.query(func.count(Deal.id))
            .join(CrmProcessStage, CrmProcessStage.id == Deal.stage_id)
            .filter(
                Deal.business_id == business_id,
                Deal.closed_at.isnot(None),
                Deal.stage_id == stage_id,
                CrmProcessStage.is_win.is_(True),
            )
            .scalar()
            or 0
        )
    return predictive_from_counts(
        closed_deals=int(closed),
        business_won=int(won),
        stage_closed=int(stage_closed),
        stage_won=int(stage_won),
    )


def person_financial_answer(db: Session, business_id: int, person_id: int, ctx: Any | None = None) -> dict[str, Any]:
    person = db.query(Person.id).filter(Person.id == person_id, Person.business_id == business_id).first()
    if person is None:
        raise ValueError("شخص در کسب‌وکار متصل پیدا نشد")
    from app.services.crm_next_action_service import next_action_for_person
    from app.services.crm_person_stats_service import build_person_commercial
    from app.services.person_service import calculate_person_balance_breakdown

    breakdown = calculate_person_balance_breakdown(db, person_id)
    commercial = build_person_commercial(db, business_id, person_id, persist=False)
    action = next_action_for_person(
        db,
        business_id,
        person_id,
        financial={
            "open_invoices_count": commercial.get("open_document_count") or 0,
            "open_invoices": commercial.get("open_documents") or [],
        },
        ctx=ctx,
    )
    return whitelist_financial_answer(
        {
            "balance": breakdown.get("balance"),
            "status": breakdown.get("status"),
            "sales_total": commercial.get("sales_total"),
            "returns_total": commercial.get("returns_total"),
            "net_sales": commercial.get("net_sales"),
            "open_document_count": commercial.get("open_document_count"),
            "open_remaining": commercial.get("open_remaining"),
            "margin_amount": commercial.get("margin_amount"),
            "margin_complete": commercial.get("margin_complete"),
            "mixed_currency": commercial.get("mixed_currency"),
            "documents_truncated": commercial.get("documents_truncated"),
            "receipt_count": commercial.get("receipt_count"),
            "repeat_products": commercial.get("repeat_products") or [],
            "next_action": action,
            "predictive": deal_predictive_score(db, business_id, None),
        }
    )
