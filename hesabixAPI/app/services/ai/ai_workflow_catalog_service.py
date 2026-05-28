"""
کاتالوگ پویا برای طراحی workflow توسط AI — بدون hardcode تریگر/اکشن.

منبع حقیقت:
- TriggerRegistry / ActionRegistry (هر handler با get_metadata)
- WorkflowBuiltinNodeRegistry (condition, loop)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from app.services.workflow.action_registry import ActionRegistry
from app.services.workflow.trigger_registry import TriggerRegistry
from app.services.workflow.workflow_builtin_node_registry import WorkflowBuiltinNodeRegistry


def _compact_trigger_item(key: str, meta: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "key": key,
        "name": meta.get("name", key),
        "description": meta.get("description", ""),
        "category": meta.get("category"),
        "tags": meta.get("tags"),
    }


def _compact_action_item(key: str, meta: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "key": key,
        "name": meta.get("name", key),
        "description": meta.get("description", ""),
        "category": meta.get("category"),
        "tags": meta.get("tags"),
    }


def list_trigger_catalog(
    *,
    compact: bool = True,
    search: Optional[str] = None,
    category: Optional[str] = None,
) -> Dict[str, Any]:
    registry = TriggerRegistry()
    items: List[Dict[str, Any]] = []
    for key, meta in registry.list_triggers().items():
        if category and meta.get("category") != category:
            continue
        if search:
            hay = f"{key} {meta.get('name', '')} {meta.get('description', '')}".lower()
            if search.lower() not in hay:
                continue
        if compact:
            items.append(_compact_trigger_item(key, meta))
        else:
            row = dict(meta)
            row["key"] = key
            items.append(row)
    items.sort(key=lambda x: x.get("key", ""))
    return {"items": items, "total": len(items), "source": "trigger_registry"}


def list_action_catalog(
    *,
    compact: bool = True,
    search: Optional[str] = None,
    category: Optional[str] = None,
) -> Dict[str, Any]:
    registry = ActionRegistry()
    items: List[Dict[str, Any]] = []
    for key, meta in registry.list_actions().items():
        if category and meta.get("category") != category:
            continue
        if search:
            hay = f"{key} {meta.get('name', '')} {meta.get('description', '')}".lower()
            if search.lower() not in hay:
                continue
        if compact:
            items.append(_compact_action_item(key, meta))
        else:
            row = dict(meta)
            row["key"] = key
            items.append(row)
    items.sort(key=lambda x: x.get("key", ""))
    return {"items": items, "total": len(items), "source": "action_registry"}


def list_builtin_node_catalog(*, compact: bool = True) -> Dict[str, Any]:
    items = WorkflowBuiltinNodeRegistry.list_builtin_nodes(compact=compact)
    return {"items": items, "total": len(items), "source": "builtin_node_registry"}


def get_component_schema(component_kind: str, key: str) -> Dict[str, Any]:
    """
    component_kind: trigger | action | builtin
    key: trigger_type / action_type / condition|loop
    """
    kind = (component_kind or "").strip().lower()
    k = (key or "").strip()
    if not k:
        raise ValueError("key الزامی است")

    if kind == "trigger":
        meta = TriggerRegistry().list_triggers().get(k)
        if not meta:
            raise ValueError(f"تریگر «{k}» یافت نشد")
        return {"component_kind": "trigger", "key": k, **meta}

    if kind == "action":
        meta = ActionRegistry().list_actions().get(k)
        if not meta:
            raise ValueError(f"اکشن «{k}» یافت نشد")
        return {"component_kind": "action", "key": k, **meta}

    if kind == "builtin":
        schema = WorkflowBuiltinNodeRegistry.get_builtin_schema(k)
        if not schema:
            raise ValueError(f"نود داخلی «{k}» یافت نشد")
        return schema

    raise ValueError("component_kind باید trigger، action یا builtin باشد")


def get_workflow_design_rules() -> Dict[str, Any]:
    """قوانین ساخت گراف — مستقل از لیست تریگر/اکشن."""
    return {
        "workflow_data_shape": {
            "nodes": "لیست نودها",
            "connections": "لیست {source, target, branch?}",
        },
        "node_types": ["trigger", "action", "condition", "loop"],
        "rules": [
            "حداقل یک نود type=trigger با config.trigger_type برابر کلید تریگر رجیستری",
            "هر نود باید id یکتا (UUID پیشنهادی) و label داشته باشد",
            "connections.source و connections.target باید به id نودهای موجود اشاره کنند",
            "برای condition شاخه‌ها: branch=true یا branch=false روی connection",
            "برای action نودها: config.action_type برابر کلید اکشن رجیستری",
            "مقادیر پویا: $nodeId.field یا {{ trigger_data.x }}",
            "پیش از ذخیره validate_workflow_draft را صدا بزن",
            "پیش‌نویس با status=پیش‌نویس؛ فعال‌سازی فقط با تأیید کاربر",
            "تست پیش‌نمایش: test_workflow با workflow_data (sandbox، بدون ذخیره روی اتوماسیون کاربر)",
            "تست با dry_run=true قبل از فعال‌سازی",
        ],
        "status_values": ["پیش‌نویس", "فعال", "غیرفعال"],
        "position": {"x": "number", "y": "number", "note": "برای نمایش در ادیتور؛ می‌توان ساده چید"},
        "discovery_tools": {
            "triggers": "list_workflow_trigger_catalog",
            "actions": "list_workflow_action_catalog",
            "builtin_nodes": "list_workflow_builtin_nodes",
            "schema": "get_workflow_component_schema(component_kind, key)",
        },
    }
