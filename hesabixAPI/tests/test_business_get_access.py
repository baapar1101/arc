"""تست دسترسی GET جزئیات کسب‌وکار برای مالک و عضو دعوت‌شده."""
from __future__ import annotations

from datetime import datetime
from types import SimpleNamespace
from unittest.mock import MagicMock, Mock

import pytest

from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError
from app.services.business_service import get_business_by_id


def _make_business(*, business_id: int = 15, owner_id: int = 17, deleted_at=None):
    return SimpleNamespace(
        id=business_id,
        owner_id=owner_id,
        deleted_at=deleted_at,
        name="فناوران چشم سوم",
    )


def test_get_business_by_id_returns_data_for_business_member(monkeypatch):
    business = _make_business()
    repo = MagicMock()
    repo.get_by_id.return_value = business

    db = MagicMock()
    monkeypatch.setattr(
        "app.services.business_service.BusinessRepository",
        lambda _db: repo,
    )
    monkeypatch.setattr(
        "app.core.auth_dependency._user_can_access_business",
        lambda _db, _user_id, _business_id: True,
    )
    monkeypatch.setattr(
        "app.services.business_service._business_to_dict",
        lambda b: {"id": b.id, "name": b.name, "owner_id": b.owner_id},
    )

    result = get_business_by_id(db, business_id=15, user_id=1)

    assert result is not None
    assert result["id"] == 15
    assert result["owner_id"] == 17


def test_get_business_by_id_returns_none_for_non_member(monkeypatch):
    business = _make_business()
    repo = MagicMock()
    repo.get_by_id.return_value = business

    db = MagicMock()
    monkeypatch.setattr(
        "app.services.business_service.BusinessRepository",
        lambda _db: repo,
    )
    monkeypatch.setattr(
        "app.core.auth_dependency._user_can_access_business",
        lambda _db, _user_id, _business_id: False,
    )

    result = get_business_by_id(db, business_id=15, user_id=999)

    assert result is None


def test_get_business_by_id_returns_none_for_deleted_business(monkeypatch):
    business = _make_business(deleted_at=datetime.utcnow())
    repo = MagicMock()
    repo.get_by_id.return_value = business

    db = MagicMock()
    monkeypatch.setattr(
        "app.services.business_service.BusinessRepository",
        lambda _db: repo,
    )

    result = get_business_by_id(db, business_id=15, user_id=17)

    assert result is None


def test_get_business_endpoint_allows_invited_member(monkeypatch):
    from adapters.api.v1.businesses import get_business

    business = _make_business()
    repo = MagicMock()
    repo.get_by_id.return_value = business

    user = Mock()
    user.id = 1
    ctx = AuthContext(user=user, api_key_id=1, db=MagicMock())
    ctx.can_access_business = Mock(return_value=True)

    monkeypatch.setattr(
        "adapters.db.repositories.business_repo.BusinessRepository",
        lambda _db: repo,
    )
    monkeypatch.setattr(
        "app.services.business_service._business_to_dict",
        lambda b: {"id": b.id, "name": b.name, "owner_id": b.owner_id},
    )

    response = get_business(request=MagicMock(), business_id=15, ctx=ctx, db=MagicMock())

    assert response["success"] is True
    assert response["data"]["id"] == 15


def test_get_business_endpoint_returns_403_for_unauthorized_user(monkeypatch):
    from adapters.api.v1.businesses import get_business

    business = _make_business()
    repo = MagicMock()
    repo.get_by_id.return_value = business

    user = Mock()
    user.id = 999
    ctx = AuthContext(user=user, api_key_id=1, db=MagicMock())
    ctx.can_access_business = Mock(return_value=False)

    monkeypatch.setattr(
        "adapters.db.repositories.business_repo.BusinessRepository",
        lambda _db: repo,
    )

    with pytest.raises(ApiError) as exc:
        get_business(request=MagicMock(), business_id=15, ctx=ctx, db=MagicMock())

    assert exc.value.status_code == 403


def test_get_business_endpoint_returns_404_for_missing_business(monkeypatch):
    from adapters.api.v1.businesses import get_business

    repo = MagicMock()
    repo.get_by_id.return_value = None

    user = Mock()
    user.id = 1
    ctx = AuthContext(user=user, api_key_id=1, db=MagicMock())

    monkeypatch.setattr(
        "adapters.db.repositories.business_repo.BusinessRepository",
        lambda _db: repo,
    )

    with pytest.raises(ApiError) as exc:
        get_business(request=MagicMock(), business_id=15, ctx=ctx, db=MagicMock())

    assert exc.value.status_code == 404
