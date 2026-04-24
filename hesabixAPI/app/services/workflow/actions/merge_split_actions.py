"""
ادغام خروجی چند نود و تقسیم آرایه به دسته (الگوی Merge / Split in Batches)
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution
from app.services.workflow.workflow_engine import WorkflowEngine

logger = logging.getLogger(__name__)


def _lookup_node_value(node_results: Dict[str, Any], node_id: Any) -> Any:
    if node_id is None:
        return None
    key = str(node_id).strip()
    if key in node_results:
        return node_results[key]
    for a, b in (node_results or {}).items():
        if str(a) == key:
            return b
    return None


def _as_dict_for_merge(
    value: Any,
    *,
    prefer_data: bool,
) -> Optional[Dict[str, Any]]:
    if value is None:
        return None
    if isinstance(value, dict):
        if (
            prefer_data
            and "data" in value
            and isinstance(value.get("data"), dict)
        ):
            return dict(value["data"])
        if not prefer_data and "data" in value and isinstance(value.get("data"), dict):
            return dict(value["data"])
        return dict(value) if value else None
    return None


def _as_list(value: Any, *, prefer_data: bool) -> Optional[List[Any]]:
    if value is None:
        return None
    if isinstance(value, list):
        return list(value)
    if isinstance(value, dict) and prefer_data and isinstance(value.get("data"), list):
        return list(value["data"])
    return None


class MergeDataAction(ActionHandler):
    """
    - object_shallow: ادغام چند dict (کلیدهای بعدی روی قبلی override می‌کنند)
    - array_concat: پشت‌سرهم‌چیدن چند لیست
    - array_union_distinct: اتحاد توالی‌ها بدون تکرار (فقط مقادیر hashable)
    """

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "ادغام داده",
            "description": "ادغام خروجی چند نود: شیء (dict) یا اتصال آرایه‌ها",
            "config_schema": {
                "mode": {
                    "type": "string",
                    "description": "نوع ادغام",
                    "enum": ["object_shallow", "array_concat", "array_union_distinct"],
                    "default": "object_shallow",
                    "required": False,
                    "ui_config": {
                        "labels": {
                            "object_shallow": "ادغام شیء (shallow merge)",
                            "array_concat": "چسباندن آرایه‌ها",
                            "array_union_distinct": "اتحاد بدون تکرار (مقادیر ساده)",
                        }
                    },
                },
                "source_node_ids": {
                    "type": "array",
                    "description": "شناسه نودها به ترتیب (مثلاً [\"node_a\", \"node_b\"])",
                    "items": {"type": "string"},
                    "required": True,
                },
                "use_data_key": {
                    "type": "boolean",
                    "description": "اگر true، در صورت dict بودن و وجود data، همان data ادغام/لیست شود",
                    "default": True,
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        mode = (config.get("mode") or "object_shallow").strip()
        prefer_data = bool(config.get("use_data_key", True))
        raw_ids = config.get("source_node_ids") or []
        if not isinstance(raw_ids, list) or not raw_ids:
            return {"success": False, "error": "source_node_ids is required (non-empty array)"}

        resolved_ids: List[str] = []
        for x in raw_ids:
            r = WorkflowEngine._resolve_value_static(x, context, node_results)
            if r is None or r == "":
                continue
            resolved_ids.append(str(r).strip())

        if not resolved_ids:
            return {"success": False, "error": "no valid source_node_ids"}

        if mode == "object_shallow":
            merged: Dict[str, Any] = {}
            for nid in resolved_ids:
                v = _lookup_node_value(node_results, nid)
                dct = _as_dict_for_merge(v, prefer_data=prefer_data)
                if dct is not None:
                    merged.update(dct)
                else:
                    merged[f"node_{nid}"] = v
            return {"success": True, "merged": merged, "mode": mode}

        if mode in ("array_concat", "array_union_distinct"):
            acc: List[Any] = []
            seen: set = set()
            for nid in resolved_ids:
                v = _lookup_node_value(node_results, nid)
                part = _as_list(v, prefer_data=prefer_data)
                if part is None and isinstance(v, dict) and "items" in v and isinstance(v.get("items"), list):
                    part = list(v["items"])
                if part is None:
                    return {
                        "success": False,
                        "error": f"node {nid} is not a list (or .data / .items list)",
                    }
                if mode == "array_concat":
                    acc.extend(part)
                else:
                    for item in part:
                        try:
                            k = item
                            if k not in seen:
                                seen.add(k)
                                acc.append(item)
                        except TypeError:
                            acc.append(item)
            return {
                "success": True,
                "items": acc,
                "count": len(acc),
                "mode": mode,
            }

        return {"success": False, "error": f"Unknown mode: {mode}"}


class SplitInBatchesAction(ActionHandler):
    """تقسیم یک آرایه به بلوک‌های با اندازه ثابت (خروجی برای for_each)"""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تقسیم به دسته",
            "description": "تقسیم لیست به چند بخش با batch_size (خروجی: batches + current_batch)",
            "config_schema": {
                "items": {
                    "type": "any",
                    "description": "لیست یا ارجاع به خروجی نود قبل (مثلاً $node_id.items)",
                    "required": True,
                },
                "batch_size": {
                    "type": "integer",
                    "description": "تعداد آیتم در هر دسته (حداقل ۱، حداکثر ۱۰۰۰)",
                    "default": 20,
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(
        self,
        context: Dict[str, Any],
        config: Dict[str, Any],
        node_results: Dict[str, Any],
    ) -> Dict[str, Any]:
        raw = config.get("items")
        items = WorkflowEngine._resolve_value_static(raw, context, node_results)
        if not isinstance(items, list):
            return {
                "success": False,
                "error": "items must resolve to a list",
            }
        try:
            bs = int(config.get("batch_size", 20) or 20)
        except (TypeError, ValueError):
            bs = 20
        bs = max(1, min(bs, 1000))
        batches: List[List[Any]] = [items[i : i + bs] for i in range(0, len(items), bs)]
        return {
            "success": True,
            "batches": batches,
            "batch_count": len(batches),
            "total_items": len(items),
            "batch_size": bs,
            "current_batch": batches[0] if batches else [],
        }
