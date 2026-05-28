"""
نودهای ساختاری workflow (شرط، حلقه) — منبع واحد schema برای UI و AI.

برای افزودن نوع شرط/حلقه جدید، فقط یک entry به `_BUILTIN_NODES` اضافه کنید.
تریگرها و اکشن‌ها از TriggerRegistry / ActionRegistry خوانده می‌شوند.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional


_BUILTIN_NODES: Dict[str, Dict[str, Any]] = {
    "condition": {
        "node_type": "condition",
        "name": "شرط",
        "description": "شاخه‌بندی بر اساس نتیجه true/false؛ connection با branch: true|false",
        "config_schema": {
            "condition_type": {
                "type": "string",
                "enum": ["simple", "complex", "expression"],
                "default": "simple",
                "description": "نوع ارزیابی شرط",
            },
            "left_value": {"type": "any", "description": "مقدار چپ (simple) — $nodeId.field یا {{ trigger_data.x }}"},
            "right_value": {"type": "any", "description": "مقدار راست (simple)"},
            "operator": {
                "type": "string",
                "enum": [
                    "==", "!=", ">", "<", ">=", "<=",
                    "contains", "not_contains", "starts_with", "ends_with",
                    "in", "not_in", "is_null", "is_not_null",
                ],
                "default": "==",
            },
            "logical_operator": {"type": "string", "enum": ["AND", "OR"], "description": "برای complex"},
            "conditions": {"type": "array", "description": "لیست شرط‌های simple برای complex"},
            "expression": {"type": "string", "description": "برای expression"},
            "on_error": {"type": "string", "enum": ["fail", "false", "true"], "default": "fail"},
        },
        "connection_rules": {
            "outputs": [
                {"branch": "true", "description": "مسیر وقتی شرط برقرار است"},
                {"branch": "false", "description": "مسیر وقتی شرط برقرار نیست"},
            ],
        },
    },
    "loop": {
        "node_type": "loop",
        "name": "حلقه",
        "description": "تکرار روی مجموعه یا بازه",
        "variants": {
            "for_each": {
                "loop_type": "for_each",
                "config_schema": {
                    "items_source": {"type": "any", "required": True, "description": "آرایه یا $node.items"},
                    "item_variable": {"type": "string", "default": "item"},
                },
            },
            "for_range": {
                "loop_type": "for_range",
                "config_schema": {
                    "start": {"type": "integer", "default": 0},
                    "end": {"type": "integer", "required": True},
                    "step": {"type": "integer", "default": 1},
                },
            },
            "while": {
                "loop_type": "while",
                "config_schema": {
                    "condition": {"type": "object", "description": "همان ساختار simple condition"},
                    "max_iterations": {"type": "integer", "default": 100},
                },
            },
        },
        "connection_rules": {
            "outputs": [{"branch": "body", "description": "بدنه حلقه"}, {"branch": "done", "description": "پس از پایان"}],
        },
    },
}


class WorkflowBuiltinNodeRegistry:
    """رجیستری نودهای داخلی (غیر trigger/action)."""

    @classmethod
    def list_builtin_nodes(cls, *, compact: bool = True) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        for key, meta in _BUILTIN_NODES.items():
            item = {"key": key, "node_type": meta.get("node_type", key)}
            if compact:
                item["name"] = meta.get("name", key)
                item["description"] = meta.get("description", "")
            else:
                item.update(meta)
            out.append(item)
        return out

    @classmethod
    def get_builtin_schema(cls, key: str) -> Optional[Dict[str, Any]]:
        meta = _BUILTIN_NODES.get(key)
        if not meta:
            return None
        return {"key": key, **meta}
