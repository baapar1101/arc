from types import SimpleNamespace

from adapters.api.v1.schema_models.project_workspace import (
    ProjectMilestoneCreateRequest,
    ProjectMilestoneUpdateRequest,
)
from adapters.db.models.task_management import Milestone
import app.services.project_service as service


def test_milestone_owner_column_is_nullable_user_fk() -> None:
    column = Milestone.__table__.c.owner_id
    assert column.nullable is True
    assert {fk.target_fullname for fk in column.foreign_keys} == {"users.id"}
    assert any(index.name == "ix_project_milestones_owner_id" for index in Milestone.__table__.indexes)


def test_milestone_owner_is_exposed_by_create_and_update_schemas() -> None:
    create = ProjectMilestoneCreateRequest(title="Launch", owner_id=7)
    update = ProjectMilestoneUpdateRequest(owner_id=8)
    clear = ProjectMilestoneUpdateRequest(owner_id=None)

    assert create.owner_id == 7
    assert update.owner_id == 8
    assert clear.owner_id is None


class _FakeDb:
    def __init__(self) -> None:
        self.business = SimpleNamespace(id=1, owner_id=1)
        self.added = []

    def get(self, model, object_id):
        del model
        return self.business if object_id == 1 else None

    def add(self, obj) -> None:
        self.added.append(obj)

    def commit(self) -> None:
        return None

    def refresh(self, obj) -> None:
        return None


def test_create_milestone_validates_and_persists_owner(monkeypatch) -> None:
    db = _FakeDb()
    validated = []

    monkeypatch.setattr(
        service,
        "_require_project_in_business",
        lambda _db, _business_id, _project_id: SimpleNamespace(id=11),
    )
    monkeypatch.setattr(
        service,
        "_business_member_user",
        lambda _db, _business, user_id: validated.append(user_id)
        or SimpleNamespace(id=user_id),
    )

    milestone = service.create_project_milestone(
        db,
        business_id=1,
        project_id=11,
        actor_user_id=3,
        data={
            "title": "Launch",
            "owner_id": 7,
            "status": "open",
        },
    )

    assert validated == [7]
    assert milestone.owner_id == 7
    assert milestone.project_id == 11
    assert db.added == [milestone]
