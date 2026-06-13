import json

import pytest
from sqlalchemy.orm import Session

from adapters.db.models.ai_model import AIModel
from adapters.db.models.ai_plan import AIPlan
from adapters.db.repositories.ai_model_repository import AIModelRepository
from adapters.db.session import get_db
from app.services.ai.ai_constants import (
    AI_OPERATION_CHAT,
    AI_OPERATION_TITLE,
    AUTO_MODEL_CODE,
)
from app.services.ai.ai_model_service import (
    is_auto_routing_available,
    resolve_auto_model,
    resolve_effective_model_code,
    resolve_requested_model_code,
)


@pytest.fixture
def db():
    db_gen = get_db()
    session = next(db_gen)
    try:
        yield session
    finally:
        session.close()


def _plan_with_pricing(pricing: dict) -> AIPlan:
    return AIPlan(
        code="test",
        name="Test",
        plan_type="pay_as_go",
        pricing_config=json.dumps(pricing, ensure_ascii=False),
    )


def _seed_models(db: Session) -> None:
    repo = AIModelRepository(db)
    if repo.get_by_code("gpt-4o-mini") and repo.get_by_code("gpt-4o"):
        return
    db.add_all(
        [
            AIModel(
                code="gpt-4o-mini",
                display_name="GPT-4o Mini",
                provider="openai",
                model_id="gpt-4o-mini",
                tier="basic",
                sort_order=10,
            ),
            AIModel(
                code="gpt-4o",
                display_name="GPT-4o",
                provider="openai",
                model_id="gpt-4o",
                tier="pro",
                sort_order=20,
            ),
        ]
    )
    db.commit()


def test_resolve_auto_model_simple_chat(db: Session):
    _seed_models(db)
    plan = _plan_with_pricing(
        {
            "allowed_models": ["auto", "gpt-4o-mini", "gpt-4o"],
            "routing": {"enabled": True},
        }
    )
    resolved = resolve_auto_model(
        db,
        plan,
        operation=AI_OPERATION_CHAT,
        user_query="سلام",
        needs_tools=False,
    )
    assert resolved == "gpt-4o-mini"


def test_resolve_auto_model_complex_chat(db: Session):
    _seed_models(db)
    plan = _plan_with_pricing(
        {
            "allowed_models": ["auto", "gpt-4o-mini", "gpt-4o"],
            "routing": {"enabled": True},
        }
    )
    resolved = resolve_auto_model(
        db,
        plan,
        operation=AI_OPERATION_CHAT,
        user_query="گزارش جامع فروش و موجودی انبار سه ماه اخیر با مقایسه کامل",
        needs_tools=True,
    )
    assert resolved == "gpt-4o"


def test_resolve_auto_model_title_uses_basic(db: Session):
    _seed_models(db)
    plan = _plan_with_pricing(
        {
            "allowed_models": ["auto", "gpt-4o-mini", "gpt-4o"],
            "routing": {"enabled": True},
        }
    )
    resolved = resolve_auto_model(
        db,
        plan,
        operation=AI_OPERATION_TITLE,
        user_query="گزارش جامع فروش و موجودی انبار",
    )
    assert resolved == "gpt-4o-mini"


def test_resolve_effective_model_code_with_auto_request(db: Session):
    _seed_models(db)
    plan = _plan_with_pricing(
        {
            "default_model": "auto",
            "allowed_models": ["auto", "gpt-4o-mini", "gpt-4o"],
            "routing": {"enabled": True},
        }
    )
    code = resolve_effective_model_code(
        db,
        request_model=AUTO_MODEL_CODE,
        subscription=None,
        plan=plan,
        config=None,
        operation=AI_OPERATION_CHAT,
        user_query="موجودی انبار چقدره؟",
        needs_tools=False,
    )
    assert code == "gpt-4o-mini"


def test_is_auto_routing_available_when_both_tiers_exist(db: Session):
    _seed_models(db)
    plan = _plan_with_pricing({"allowed_models": ["gpt-4o-mini", "gpt-4o"]})
    assert is_auto_routing_available(db, plan) is True


def test_resolve_requested_model_code_returns_auto(db: Session):
    _seed_models(db)
    plan = _plan_with_pricing(
        {
            "default_model": "auto",
            "allowed_models": ["auto", "gpt-4o-mini", "gpt-4o"],
            "routing": {"enabled": True},
        }
    )
    code = resolve_requested_model_code(
        db,
        request_model=None,
        subscription=None,
        plan=plan,
        config=None,
    )
    assert code == AUTO_MODEL_CODE
