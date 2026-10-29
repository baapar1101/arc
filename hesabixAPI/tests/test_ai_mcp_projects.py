"""Tenant-bound MCP tools for projects, person groups, and customer credit."""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from app.core.responses import ApiError
from app.services.ai.ai_function_extensions_mcp_credit import (
    CREATE_INSTALLMENT_PLAN_SCHEMA,
    UPDATE_CREDIT_SETTINGS_SCHEMA,
    UPDATE_PERSON_CREDIT_SCHEMA,
    create_credit_installment_plan_handler,
    delete_credit_installment_plan_handler,
    get_credit_installment_plan_handler,
    update_credit_settings_handler,
    update_person_credit_handler,
)
from app.services.ai.ai_function_extensions_mcp_person_groups import (
    CREATE_PERSON_GROUP_SCHEMA,
    UPDATE_PERSON_GROUP_SCHEMA,
    create_person_group_handler,
    delete_person_group_handler,
    get_person_group_handler,
    update_person_group_handler,
)
from app.services.ai.ai_function_extensions_mcp_projects import (
    CREATE_PROJECT_SCHEMA,
    UPDATE_PROJECT_SCHEMA,
    _DOCS_SCHEMA,
    create_project_handler,
    delete_project_handler,
    list_project_documents_handler,
    update_project_handler,
)
from app.services.ai.ai_tool_catalog_quality import parse_registered_tool_fields
from app.services.ai.ai_tool_manifest import get_manifest_entry
from app.services.ai.ai_write_guard import is_write_function

PROJECT_TOOLS = (
    "create_project",
    "update_project",
    "delete_project",
    "list_project_documents",
)
PERSON_GROUP_TOOLS = (
    "get_person_group",
    "create_person_group",
    "update_person_group",
    "delete_person_group",
)
CREDIT_TOOLS = (
    "update_credit_settings",
    "get_credit_installment_plan",
    "create_credit_installment_plan",
    "update_credit_installment_plan",
    "delete_credit_installment_plan",
    "update_person_credit",
)
ALL_TOOLS = PROJECT_TOOLS + PERSON_GROUP_TOOLS + CREDIT_TOOLS
ALWAYS_CONFIRM = (
    "delete_project",
    "delete_person_group",
    "update_credit_settings",
    "delete_credit_installment_plan",
    "update_person_credit",
)


def _ctx(*, business_id: int = 7, user_id: int = 9, db=None):
    user = MagicMock()
    user.get_user_id.return_value = user_id
    return {
        "db": db if db is not None else MagicMock(),
        "business_id": business_id,
        "user_context": user,
    }


def _project(**kwargs):
    data = dict(
        id=4,
        code="P-1",
        name="ساختمان",
        description=None,
        status="active",
        is_active=True,
        start_date=None,
        end_date=None,
        budget=None,
        currency_id=None,
        manager_user_id=None,
        person_id=None,
        extra_info={"secret": 1},
        business_id=7,
    )
    data.update(kwargs)
    return SimpleNamespace(**data)


def _assert_no_extra_blob(schema: dict) -> None:
    assert schema.get("additionalProperties") is False
    props = schema.get("properties") or {}
    assert "extra_info" not in props
    assert "hard_delete" not in props
    assert "parent_id" not in props
    assert "business_id" not in props


def test_project_group_credit_tools_are_registered_with_strict_schemas():
    parsed = parse_registered_tool_fields()
    for name in ALL_TOOLS:
        assert name in parsed, name
        fields = parsed[name]
        if fields["is_readonly"]:
            assert fields["requires_approval"] is False
        else:
            assert fields["requires_approval"] is True
            assert fields["is_readonly"] is False

    create = parsed["create_project"]
    assert create["required_permissions"] == ["projects.write"]
    assert create["risk_level"] == "medium"
    assert CREATE_PROJECT_SCHEMA["required"] == ["code", "name"]
    assert CREATE_PROJECT_SCHEMA["properties"]["status"]["enum"] == [
        "active",
        "completed",
        "on_hold",
        "cancelled",
    ]
    _assert_no_extra_blob(CREATE_PROJECT_SCHEMA)
    _assert_no_extra_blob(UPDATE_PROJECT_SCHEMA)
    assert parsed["delete_project"]["required_permissions"] == ["projects.delete"]
    assert parsed["delete_project"]["risk_level"] == "high"
    assert parsed["list_project_documents"]["is_readonly"] is True
    assert parsed["list_project_documents"]["required_permissions"] == ["projects.view"]

    assert parsed["create_person_group"]["required_permissions"] == ["persons.write"]
    assert parsed["delete_person_group"]["required_permissions"] == ["people.delete"]
    assert parsed["delete_person_group"]["risk_level"] == "high"
    _assert_no_extra_blob(CREATE_PERSON_GROUP_SCHEMA)
    _assert_no_extra_blob(UPDATE_PERSON_GROUP_SCHEMA)
    legal = CREATE_PERSON_GROUP_SCHEMA["properties"]["profile_defaults"]["properties"]["legal_entity_type"]
    assert any(branch.get("type") == "null" for branch in legal["anyOf"])
    assert CREATE_PERSON_GROUP_SCHEMA["properties"]["profile_defaults"]["additionalProperties"] is False

    assert parsed["update_credit_settings"]["required_permissions"] == ["credit.write"]
    assert parsed["update_credit_settings"]["risk_level"] == "high"
    assert parsed["get_credit_installment_plan"]["is_readonly"] is True
    assert parsed["create_credit_installment_plan"]["required_permissions"] == ["credit.write"]
    assert parsed["update_person_credit"]["required_permissions"] == ["persons.write"]
    assert parsed["update_person_credit"]["risk_level"] == "high"
    _assert_no_extra_blob(UPDATE_CREDIT_SETTINGS_SCHEMA)
    _assert_no_extra_blob(CREATE_INSTALLMENT_PLAN_SCHEMA)
    _assert_no_extra_blob(UPDATE_PERSON_CREDIT_SCHEMA)
    assert CREATE_INSTALLMENT_PLAN_SCHEMA["required"] == ["name", "num_installments"]
    assert CREATE_INSTALLMENT_PLAN_SCHEMA["properties"]["method"]["enum"] == ["flat", "amortized"]
    assert UPDATE_CREDIT_SETTINGS_SCHEMA["properties"]["strategy"]["enum"] == [
        "single-default",
        "by-group",
        "per-user",
    ]


def test_manifest_marks_writes_deletes_and_companions():
    for name in ALL_TOOLS:
        entry = get_manifest_entry(name)
        assert entry is not None, name
    for name in ALWAYS_CONFIRM:
        entry = get_manifest_entry(name)
        assert entry is not None and entry.always_confirm is True and entry.intent_write is True, name
    assert get_manifest_entry("delete_project").side_effect == "delete"
    assert get_manifest_entry("delete_person_group").side_effect == "delete"
    assert get_manifest_entry("delete_credit_installment_plan").side_effect == "delete"
    assert get_manifest_entry("create_project").intent_write is True
    assert get_manifest_entry("create_project").always_confirm is False
    assert get_manifest_entry("list_project_documents").intent_write is False
    assert get_manifest_entry("create_project").capability == "financial.project"
    assert get_manifest_entry("search_projects").capability == "financial.project"
    assert get_manifest_entry("create_person_group").capability == "people.person"
    assert get_manifest_entry("update_person_credit").capability == "financial.credit"
    search = get_manifest_entry("search_projects")
    assert "create_project" in (search.companion_tools if search else ())
    groups = get_manifest_entry("list_person_groups")
    assert "create_person_group" in (groups.companion_tools if groups else ())
    credit = get_manifest_entry("get_person_credit")
    assert "update_person_credit" in (credit.companion_tools if credit else ())
    plans = get_manifest_entry("list_credit_installment_plans")
    assert "create_credit_installment_plan" in (plans.companion_tools if plans else ())
    person = get_manifest_entry("create_person")
    assert "create_person_group" in (person.companion_tools if person else ())
    assert is_write_function("create_project") is True
    assert is_write_function("delete_person_group") is True
    assert is_write_function("update_person_credit") is True
    assert is_write_function("list_project_documents") is False
    assert is_write_function("get_credit_installment_plan") is False


def test_create_project_pins_tenant_and_omits_extra_info():
    row = _project()
    with patch("app.services.project_service.create_project", return_value=row) as create:
        out = create_project_handler(
            {
                "code": "P-1",
                "name": "ساختمان",
                "business_id": 99,
                "extra_info": {"secret": 1},
            },
            _ctx(),
        )
    assert out["id"] == 4
    assert out["code"] == "P-1"
    assert "extra_info" not in out
    assert create.call_args.args[1] == 7
    assert create.call_args.args[2] == 9
    payload = create.call_args.args[3]
    assert payload == {"code": "P-1", "name": "ساختمان"}


def test_project_manager_must_be_owner_or_member():
    from adapters.db.models.business import Business
    from adapters.db.models.business_permission import BusinessPermission

    db = MagicMock()

    def query(model):
        q = MagicMock()
        q.filter.return_value = q
        if model is Business:
            q.first.return_value = SimpleNamespace(id=7, owner_id=9)
        elif model is BusinessPermission:
            q.first.return_value = None
        else:
            q.first.return_value = None
        return q

    db.query.side_effect = query
    with pytest.raises(ValueError, match="مالک یا عضو"):
        create_project_handler(
            {"code": "P-2", "name": "راه", "manager_user_id": 15},
            _ctx(db=db),
        )

    with patch("app.services.project_service.create_project", return_value=_project()) as create:
        create_project_handler(
            {"code": "P-2", "name": "راه", "manager_user_id": 9},
            _ctx(db=db),
        )
    assert create.call_args.args[3]["manager_user_id"] == 9


def test_project_get_update_delete_reject_foreign_tenant():
    foreign = _project(id=5, business_id=99)
    with patch(
        "adapters.db.repositories.project_repository.ProjectRepository"
    ) as repo_cls:
        repo_cls.return_value.get_by_id.return_value = foreign
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            update_project_handler({"project_id": 5, "name": "دیگر"}, _ctx())
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            delete_project_handler({"project_id": 5}, _ctx())
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            list_project_documents_handler({"project_id": 5}, _ctx())


def test_update_and_delete_project_pin_tenant_and_never_hard_delete():
    local = _project()
    with patch(
        "adapters.db.repositories.project_repository.ProjectRepository"
    ) as repo_cls, patch(
        "app.services.project_service.update_project", return_value=local
    ) as update:
        repo_cls.return_value.get_by_id.return_value = local
        out = update_project_handler(
            {"project_id": 4, "name": "نو", "extra_info": {"x": 1}, "business_id": 99},
            _ctx(),
        )
    assert out["name"] == "ساختمان"
    assert "extra_info" not in out
    assert update.call_args.args[1] == 4
    assert update.call_args.args[2] == 7
    assert update.call_args.args[3] == {"name": "نو"}

    with patch(
        "adapters.db.repositories.project_repository.ProjectRepository"
    ) as repo_cls, patch(
        "app.services.project_service.delete_project"
    ) as delete:
        repo_cls.return_value.get_by_id.return_value = local
        result = delete_project_handler({"project_id": 4, "hard_delete": True}, _ctx())
    assert result == {"deleted": True, "project_id": 4, "hard_delete": False}
    assert delete.call_args.args[1] == 4
    assert delete.call_args.args[2] == 7
    assert delete.call_args.args[3] is False


def test_list_project_documents_caps_and_pins_tenant():
    local = _project()
    docs = [
        SimpleNamespace(
            id=11,
            code="DOC-1",
            document_type="manual",
            document_date=None,
            description="ثبت",
        )
    ]
    with patch(
        "adapters.db.repositories.project_repository.ProjectRepository"
    ) as repo_cls, patch(
        "app.services.project_service.list_project_documents",
        return_value=(docs, 1),
    ) as listed:
        repo_cls.return_value.get_by_id.return_value = local
        out = list_project_documents_handler({"project_id": 4, "limit": 50}, _ctx())
    assert out["total"] == 1
    assert out["items"][0]["id"] == 11
    assert listed.call_args.args[1] == 4
    assert listed.call_args.args[2] == 0
    assert listed.call_args.args[3] == 50
    assert _DOCS_SCHEMA["properties"]["limit"]["maximum"] == 200


def test_person_group_write_omits_parent_and_pins_tenant():
    with patch(
        "app.services.person_group_service.create_person_group",
        return_value={"id": 3, "name": "عمده"},
    ) as create:
        out = create_person_group_handler(
            {"name": "عمده", "parent_id": 8, "business_id": 99},
            _ctx(),
        )
    assert out["id"] == 3
    assert create.call_args.args[1] == 7
    body = create.call_args.args[2]
    assert body.name == "عمده"
    assert body.parent_id is None

    with patch(
        "app.services.person_group_service.update_person_group",
        return_value=None,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            update_person_group_handler({"group_id": 3, "name": "خرده"}, _ctx())

    with patch(
        "app.services.person_group_service.get_person_group",
        return_value=None,
    ):
        with pytest.raises(ValueError, match="کسب‌وکار متصل"):
            get_person_group_handler({"group_id": 3}, _ctx())


def test_delete_person_group_fails_when_not_empty():
    with patch(
        "app.services.person_group_service.delete_person_group",
        side_effect=ApiError(
            "PERSON_GROUP_NOT_EMPTY",
            "این گروه دارای ۲ شخص است؛ ابتدا انتساب را تغییر دهید",
            http_status=400,
        ),
    ):
        with pytest.raises(ValueError, match="دارای ۲ شخص"):
            delete_person_group_handler({"group_id": 3}, _ctx())

    with patch(
        "app.services.person_group_service.delete_person_group",
    ) as delete:
        out = delete_person_group_handler({"group_id": 3}, _ctx())
    assert out == {"deleted": True, "group_id": 3}
    assert delete.call_args.args[1] == 7
    assert delete.call_args.args[2] == 3


def test_credit_writes_pin_tenant_and_commit_person_override():
    with patch(
        "app.services.credit_service.update_business_credit_settings",
        return_value={"is_enabled": True},
    ) as update:
        out = update_credit_settings_handler(
            {"is_enabled": True, "business_id": 99, "extra_info": {}},
            _ctx(),
        )
    assert out["is_enabled"] is True
    assert update.call_args.args[1] == 7
    assert update.call_args.args[2] == {"is_enabled": True}

    with patch(
        "app.services.credit_service.get_installment_plan",
        return_value={"id": 2, "name": "۶ ماهه"},
    ) as get_plan:
        get_credit_installment_plan_handler({"plan_id": 2}, _ctx())
    assert get_plan.call_args.args[1] == 7
    assert get_plan.call_args.args[2] == 2

    with patch(
        "app.services.credit_service.create_installment_plan",
        return_value={"id": 2, "name": "۶ ماهه"},
    ) as create:
        create_credit_installment_plan_handler(
            {"name": "۶ ماهه", "num_installments": 6, "business_id": 99},
            _ctx(),
        )
    assert create.call_args.args[1] == 7
    assert create.call_args.args[2] == {"name": "۶ ماهه", "num_installments": 6}

    with patch(
        "app.services.credit_service.delete_installment_plan",
        side_effect=ApiError("NOT_FOUND", "installment plan not found", http_status=404),
    ):
        with pytest.raises(ValueError, match="not found"):
            delete_credit_installment_plan_handler({"plan_id": 9}, _ctx())

    db = MagicMock()
    with patch(
        "app.services.credit_service.update_person_credit",
        return_value={"person_id": 12, "credit_limit": 1000},
    ) as person:
        out = update_person_credit_handler(
            {"person_id": 12, "credit_limit": 1000, "business_id": 99},
            _ctx(db=db),
        )
    assert out["credit_limit"] == 1000
    assert person.call_args.args[1] == 7
    assert person.call_args.args[2] == 12
    assert person.call_args.args[3] == {"credit_limit": 1000}
    db.commit.assert_called_once()
