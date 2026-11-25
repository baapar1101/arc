"""MCP tools for project CRUD and related documents. extra_info and hard delete are out of band."""
from __future__ import annotations

from typing import Any, Dict

CREATE_PROJECT_SCHEMA: Dict[str, Any] = {}
UPDATE_PROJECT_SCHEMA: Dict[str, Any] = {}

_STATUS = ["active", "completed", "on_hold", "cancelled"]
_MAX_DOCS = 200


def _schema(properties: Dict[str, Any], required: list[str] | None = None) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": list(required or []),
        "additionalProperties": False,
    }


def _raise_service(exc: BaseException) -> None:
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


def _run(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except Exception as exc:
        _raise_service(exc)


def _bid(context: Dict[str, Any]) -> int:
    return int(context["business_id"])


def _uid(context: Dict[str, Any]) -> int:
    return int(context["user_context"].get_user_id())


def _db(context: Dict[str, Any]):
    return context["db"]


def _public_project(row: Any) -> Dict[str, Any]:
    return {
        "id": row.id,
        "code": row.code,
        "name": row.name,
        "description": row.description,
        "status": row.status,
        "is_active": bool(row.is_active),
        "start_date": row.start_date.isoformat() if row.start_date else None,
        "end_date": row.end_date.isoformat() if row.end_date else None,
        "budget": float(row.budget) if row.budget is not None else None,
        "currency_id": row.currency_id,
        "manager_user_id": row.manager_user_id,
        "person_id": row.person_id,
    }


def _ensure_manager_member(db, business_id: int, manager_user_id: Any) -> None:
    if manager_user_id is None:
        return
    from adapters.db.models.business import Business
    from adapters.db.models.business_permission import BusinessPermission

    uid = int(manager_user_id)
    biz = db.query(Business).filter(Business.id == int(business_id)).first()
    if biz and biz.owner_id == uid:
        return
    member = (
        db.query(BusinessPermission)
        .filter(
            BusinessPermission.business_id == int(business_id),
            BusinessPermission.user_id == uid,
        )
        .first()
    )
    if not member:
        raise ValueError("مدیر پروژه باید مالک یا عضو همین کسب‌وکار باشد.")


def _load_tenant_project(db, business_id: int, project_id: int):
    from adapters.db.repositories.project_repository import ProjectRepository

    project = ProjectRepository(db).get_by_id(int(project_id), load_relations=True)
    if not project or project.business_id != int(business_id):
        raise ValueError("پروژه در کسب‌وکار متصل یافت نشد.")
    return project


_FIELDS = {
    "code": {"type": "string", "minLength": 1, "maxLength": 50, "description": "کد یکتای پروژه در همین کسب‌وکار"},
    "name": {"type": "string", "minLength": 1, "maxLength": 255},
    "description": {"type": ["string", "null"], "maxLength": 2000},
    "status": {"type": "string", "enum": _STATUS},
    "start_date": {"type": ["string", "null"], "format": "date"},
    "end_date": {"type": ["string", "null"], "format": "date"},
    "budget": {"type": ["number", "null"], "minimum": 0},
    "currency_id": {"type": ["integer", "null"], "minimum": 1, "description": "شناسه ارز از list_currencies"},
    "manager_user_id": {
        "type": ["integer", "null"],
        "minimum": 1,
        "description": "کاربر عضو همین کسب‌وکار؛ از list_business_users",
    },
    "person_id": {"type": ["integer", "null"], "minimum": 1, "description": "شخص مرتبط از search_persons"},
    "is_active": {"type": "boolean"},
}
CREATE_PROJECT_SCHEMA = _schema(dict(_FIELDS), ["code", "name"])
UPDATE_PROJECT_SCHEMA = _schema({"project_id": {"type": "integer", "minimum": 1}, **_FIELDS}, ["project_id"])
_PROJECT_ID = _schema({"project_id": {"type": "integer", "minimum": 1}}, ["project_id"])
_DOCS_SCHEMA = _schema(
    {
        "project_id": {"type": "integer", "minimum": 1},
        "limit": {"type": "integer", "minimum": 1, "maximum": _MAX_DOCS},
        "skip": {"type": "integer", "minimum": 0},
    },
    ["project_id"],
)


def _project_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in args.items() if k in _FIELDS}


def create_project_handler(args, context):
    from app.services.project_service import create_project

    db = _db(context)
    bid = _bid(context)
    payload = _project_payload(args)
    _ensure_manager_member(db, bid, payload.get("manager_user_id"))
    row = _run(create_project, db, bid, _uid(context), payload)
    return _public_project(row)


def update_project_handler(args, context):
    from app.services.project_service import update_project

    db = _db(context)
    bid = _bid(context)
    project_id = int(args["project_id"])
    _load_tenant_project(db, bid, project_id)
    payload = _project_payload(args)
    if "manager_user_id" in payload:
        _ensure_manager_member(db, bid, payload.get("manager_user_id"))
    row = _run(update_project, db, project_id, bid, payload)
    return _public_project(row)


def delete_project_handler(args, context):
    from app.services.project_service import delete_project

    db = _db(context)
    bid = _bid(context)
    project_id = int(args["project_id"])
    _load_tenant_project(db, bid, project_id)
    _run(delete_project, db, project_id, bid, False)
    return {"deleted": True, "project_id": project_id, "hard_delete": False}


def list_project_documents_handler(args, context):
    from app.services.project_service import list_project_documents

    db = _db(context)
    bid = _bid(context)
    project_id = int(args["project_id"])
    _load_tenant_project(db, bid, project_id)
    limit = int(args.get("limit", 50))
    skip = int(args.get("skip", 0))
    documents, total = _run(list_project_documents, db, project_id, skip, limit)
    return {
        "project_id": project_id,
        "total": total,
        "items": [
            {
                "id": doc.id,
                "code": doc.code,
                "document_type": doc.document_type,
                "document_date": doc.document_date.isoformat() if doc.document_date else None,
                "description": doc.description,
            }
            for doc in documents
        ],
    }


def register_mcp_project_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="create_project",
        description="ثبت پروژه جدید برای کسب‌وکار متصل. code و name الزامی است. extra_info پذیرفته نمی‌شود. نیاز به تأیید.",
        parameters_schema=CREATE_PROJECT_SCHEMA,
        handler=create_project_handler,
        allowed_roles=roles,
        required_permissions=["projects.write"],
        category="projects",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_project",
        description="ویرایش پروژه متعلق به کسب‌وکار متصل. extra_info پذیرفته نمی‌شود. نیاز به تأیید.",
        parameters_schema=UPDATE_PROJECT_SCHEMA,
        handler=update_project_handler,
        allowed_roles=roles,
        required_permissions=["projects.write"],
        category="projects",
        requires_approval=True,
        risk_level="medium",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_project",
        description="حذف نرم پروژه کسب‌وکار متصل. حذف کامل از MCP نیست. نیازمند تأیید.",
        parameters_schema=_PROJECT_ID,
        handler=delete_project_handler,
        allowed_roles=roles,
        required_permissions=["projects.delete"],
        category="projects",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="list_project_documents",
        description="اسناد حسابداری مرتبط با یک پروژه متعلق به کسب‌وکار متصل، حداکثر ۲۰۰ مورد در صفحه.",
        parameters_schema=_DOCS_SCHEMA,
        handler=list_project_documents_handler,
        allowed_roles=roles,
        required_permissions=["projects.view"],
        category="projects",
        is_readonly=True,
    ))
