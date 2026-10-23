"""Tenant-pinned MCP tools facade over the existing Hesabix AI registry."""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_write_guard import is_readonly_function

logger = logging.getLogger(__name__)
MCP_PROTOCOL_VERSION = "2025-11-25"
SERVER_NAME = "hesabix-ai"
SERVER_VERSION = "1.1.0"
WRITE_SCOPE = "ai:tools:write"
AGENT_TOOL_NAME = "ask_hesabix_agent"

_PROMPT_CATALOG = {
    "business_summary": ("خلاصه مدیریتی کسب‌وکار", "business", "وضعیت کلی و شاخص‌های مدیریتی کسب‌وکار را جمع‌بندی کن."),
    "sales_review": ("مرور فروش", "financial", "فروش، فاکتورها، دریافت‌ها و روندهای قابل مشاهده را مرور کن."),
    "inventory_review": ("مرور موجودی", "warehouse", "موجودی، کالاهای کم‌موجود و اسناد انبار را بررسی کن."),
    "receivables_review": ("مرور مطالبات", "financial", "مانده حساب مشتریان و دریافت‌های ثبت‌شده را بر اساس ابزارهای مجاز بررسی کن."),
    "payables_review": ("مرور بدهی‌ها", "financial", "مانده حساب تأمین‌کنندگان و پرداخت‌های ثبت‌شده را بر اساس ابزارهای مجاز بررسی کن."),
    "payroll_review": ("مرور حقوق و دستمزد", "payroll", "وضعیت دوره‌ها و اجراهای حقوق، جمع ناخالص/کسورات/خالص و وضعیت تأیید یا ثبت را فقط از ابزارهای مجاز همین کسب‌وکار بررسی کن. داده بانکی، شناسه مالیاتی یا جزئیات فردی را فقط وقتی درخواست شده و برای پاسخ لازم است نمایش بده؛ هیچ اجرا را تأیید، قطعی یا پرداخت نکن مگر کاربر همان عملیات را صریحاً درخواست کند."),
    "crm_review": ("مرور CRM", "crm", "سرنخ‌ها، فرصت‌ها، فعالیت‌ها، توالی‌های پیگیری و قیف فروش را مرور کن؛ ثبت‌نام یا تغییر توالی را فقط در صورت درخواست روشن انجام بده."),
    "repair_review": ("مرور تعمیرگاه", "repair", "سفارش‌های تعمیر و وضعیت، تعمیرکار، قطعات و هزینه را از ابزارهای مجاز کسب‌وکار بررسی کن. پیش از تغییر وضعیت، اعلان به مشتری، مصرف قطعه، اتمام/تحویل یا صدور فاکتور، اثر عملیات و سفارش دقیق را بیان کن و تأیید صریح بگیر."),
    "warranty_review": ("مرور گارانتی", "warranty", "کدها و وضعیت گارانتی را فقط از ابزارهای مجاز همین کسب‌وکار بررسی کن. اطلاعات تماس مشتری و کد لینک رهگیری را در پاسخ عادی نمایش نده. پیش از تولید کد، تغییر تنظیمات یا حذف، دامنه اثر را شرح بده و تأیید صریح بگیر؛ فعال‌سازی عمومی گارانتی را از طرف مشتری انجام نده."),
    "production_review": ("مرور تولید", "production", "وضعیت سفارش‌های تولید، مواد موردنیاز، lot و بهای تمام‌شده را از ابزارهای مجاز بررسی کن. BOM را فقط با محصولات همان کسب‌وکار به کار ببر. آزادسازی، شروع، تکمیل یا لغو سفارش می‌تواند روی موجودی اثر بگذارد؛ پیش از هر اقدام اثر، شناسه سفارش و نسخه را روشن کن و تأیید صریح بگیر."),
    "distribution_review": ("مرور توزیع", "distribution", "برنامه ویزیت، مسیرها، سفارش‌ها، مرجوعی، موجودی خودرو، تسویه و تحویل را فقط با ابزارهای مجاز همین کسب‌وکار بررسی کن. عملیات توزیع می‌تواند فاکتور، سند انبار، پرداخت، اطلاعات مکانی یا ارتباط با مشتری ایجاد کند؛ اثر و رکورد هدف را پیش از نوشتن مشخص کن و تأیید صریح بگیر. داده مکانی و اطلاعات مشتری را فقط در پاسخ لازم به درخواست کاربر نمایش بده."),
    "invoice_draft": ("آماده‌سازی فاکتور", "invoices", "اطلاعات لازم برای ثبت فاکتور را جمع‌آوری و پیش‌نویس ورودی ابزار را آماده کن."),
    "tax_review": ("بررسی وضعیت مالیاتی فاکتورها", "tax", "وضعیت کارپوشه، خطاهای ارسال و اعتبار اطلاعات مالیاتی فاکتورهای انتخابی را بررسی کن. پیش از هر ارسال، ابطال یا استعلام بیرونی، اثر عملیات و شناسهٔ فاکتور را روشن کن و تأیید صریح بگیر."),
    "warehouse_document": ("آماده‌سازی حواله انبار", "warehouse", "اطلاعات لازم برای حواله را جمع‌آوری و پیش‌نویس ورودی ابزار را آماده کن."),
}
_PROMPT_CATEGORY_ALIASES = {
    "financial": {"financial", "invoices", "checks", "accounting"},
}


def _prompt_category_available(category: str, visible: set[str]) -> bool:
    return bool((_PROMPT_CATEGORY_ALIASES.get(category) or {category}) & visible)


def _visible_tool_catalog(db: Session, ctx: AuthContext, business_id: int) -> list[dict[str, Any]]:
    registry, definitions = _get_tools(db, ctx, business_id)
    catalog = []
    for definition in definitions:
        fn_def = definition.get("function") or {}
        name = str(fn_def.get("name", ""))
        function = registry.get_function(name)
        if not function:
            continue
        read_only = _mcp_readonly(name, registry)
        if not read_only and WRITE_SCOPE not in getattr(ctx, "mcp_scopes", set()):
            continue
        catalog.append({
            "name": name,
            "description": fn_def.get("description") or function.description or "",
            "input_schema": fn_def.get("parameters") or {"type": "object", "properties": {}},
            "category": function.category or "general",
            "capability": getattr(function, "capability", "misc"),
            "read_only": read_only,
            "required_permissions": list(function.required_permissions or []),
        })
    if getattr(ctx, "mcp_tool_permissions", None) is None:
        catalog.append({
            "name": AGENT_TOOL_NAME,
            "description": "پرسش چندمرحله‌ای از ایجنت حسابیکس در حالت فقط‌خواندنی و محدود به همین کسب‌وکار.",
            "input_schema": {
                "type": "object",
                "properties": {"query": {"type": "string", "description": "درخواست یا پرسش درباره همین کسب‌وکار"}},
                "required": ["query"],
                "additionalProperties": False,
            },
            "category": "agent",
            "capability": "business_agent",
            "read_only": True,
            "required_permissions": [],
        })
    return sorted(catalog, key=lambda item: item["name"])


def _prompt_content(name: str, title: str, goal: str, user_request: str, catalog: list[dict[str, Any]]) -> str:
    categories = sorted({item["category"] for item in catalog})
    tools = [item for item in catalog if item["category"] in {"general", "query", "business", "reports", "financial", "payroll", "repair", "production", "warranty", "distribution", "invoices", "warehouse", "crm", "products", "persons"}]
    tool_names = ", ".join(item["name"] for item in tools[:100]) or "هیچ ابزار دامنه‌ای در این اتصال مجاز نیست"
    text = (
        f"{title}. {goal}\n"
        "فقط به کسب‌وکار متصل‌شده و ابزارهای صریحاً در دسترس این اتصال محدود هستی. "
        "فهرست ابزارها را از منبع hesabix://mcp/capabilities بخوان و فقط نام‌ها و پارامترهای همان ابزارها را استفاده کن؛ "
        "وجود یک قابلیت در نرم‌افزار به معنی مجاز بودن آن برای این اتصال نیست.\n"
        f"دسته‌های قابل مشاهده: {', '.join(categories) or 'هیچ‌کدام'}.\n"
        f"ابزارهای اصلی قابل مشاهده: {tool_names}.\n"
        "برای پاسخ تحلیلی، داده را از ابزارهای خواندنی بگیر، بازه و واحد را روشن کن، محاسبه را از دادهٔ واقعی جدا کن و اگر ابزار یا داده کافی نیست صریح بگو. "
        "شناسه‌ها را با جستجو به دست بیاور و حدس نزن. هیچ تغییری در داده‌ها ایجاد نکن مگر کاربر در همین گفتگو صریحاً همان تغییر را درخواست کرده باشد؛ "
        "پیش از عملیات حساس، اثر آن را توضیح بده و فقط ابزار نوشتنیِ موجود و مجاز را فراخوانی کن. هرگز محدودیت مجوز، تأیید یا tenant را دور نزن."
    )
    if user_request.strip():
        text += "\nدرخواست تکمیلی کاربر: " + user_request.strip()
    return text


def prepare_mcp_tool_arguments(arguments: Dict[str, Any], *, business_id: int) -> Dict[str, Any]:
    """Remove model-controlled tenant/approval switches and pin supported tenant args."""
    cleaned = dict(arguments or {})
    cleaned.pop("_approve_writes", None)
    cleaned.pop("approve_writes", None)
    cleaned.pop("user_id", None)
    if "business_id" in cleaned:
        cleaned["business_id"] = int(business_id)
    return cleaned


def mcp_explicit_write_approval(params: Dict[str, Any]) -> bool:
    """Kept for old callers; an RPC boolean is never an authorization signal."""
    return False


def _mcp_readonly(name: str, registry: Any) -> bool:
    """Fail closed if registry metadata is missing or internally inconsistent."""
    function = registry.get_function(name)
    if function is None:
        return False
    return bool(
        is_readonly_function(name, registry)
        and not getattr(function, "requires_approval", False)
        and not getattr(function, "intent_write", False)
        and not getattr(function, "always_confirm", False)
        and getattr(function, "side_effect", "none") in {None, "none", "read"}
    )


def _jsonrpc_result(req_id: Any, result: Any) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def _jsonrpc_error(req_id: Any, code: int, message: str, data: Any = None) -> Dict[str, Any]:
    err: Dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    return {"jsonrpc": "2.0", "id": req_id, "error": err}


def _validate_schema_value(value: Any, schema: Dict[str, Any], path: str = "arguments") -> None:
    """Validate the JSON Schema subset used by registered MCP tools, without optional runtime deps."""
    if not isinstance(schema, dict):
        raise ValueError(f"Invalid schema for {path}")
    for branch_key in ("oneOf", "anyOf"):
        branches = schema.get(branch_key)
        if branches:
            errors = []
            for branch in branches:
                try:
                    _validate_schema_value(value, branch, path)
                    return
                except ValueError as exc:
                    errors.append(str(exc))
            raise ValueError(f"{path} does not match {branch_key}")
    expected = schema.get("type")
    expected_types = expected if isinstance(expected, list) else ([expected] if expected else [])
    type_matches = {
        "object": lambda v: isinstance(v, dict),
        "array": lambda v: isinstance(v, list),
        "string": lambda v: isinstance(v, str),
        "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
        "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
        "boolean": lambda v: isinstance(v, bool),
        "null": lambda v: v is None,
    }
    if expected_types and not any(type_matches.get(t, lambda _v: True)(value) for t in expected_types):
        raise ValueError(f"{path} must be {' or '.join(expected_types)}")
    if "enum" in schema and value not in schema["enum"]:
        raise ValueError(f"{path} must be one of the allowed values")
    if isinstance(value, dict):
        properties = schema.get("properties") or {}
        missing = [key for key in schema.get("required", []) if key not in value]
        if missing:
            raise ValueError(f"{path} is missing required field(s): {', '.join(missing)}")
        if schema.get("additionalProperties") is False:
            extras = [key for key in value if key not in properties]
            if extras:
                raise ValueError(f"{path} has unsupported field(s): {', '.join(extras)}")
        for key, child in properties.items():
            if key in value:
                _validate_schema_value(value[key], child, f"{path}.{key}")
        additional = schema.get("additionalProperties")
        if isinstance(additional, dict):
            for key, child_value in value.items():
                if key not in properties:
                    _validate_schema_value(child_value, additional, f"{path}.{key}")
    elif isinstance(value, list):
        if schema.get("minItems") is not None and len(value) < int(schema["minItems"]):
            raise ValueError(f"{path} has too few items")
        if schema.get("maxItems") is not None and len(value) > int(schema["maxItems"]):
            raise ValueError(f"{path} has too many items")
        if schema.get("uniqueItems"):
            for index, item in enumerate(value):
                if any(item == previous for previous in value[:index]):
                    raise ValueError(f"{path} items must be unique")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, child_value in enumerate(value):
                _validate_schema_value(child_value, item_schema, f"{path}[{index}]")
    elif isinstance(value, str):
        if schema.get("minLength") is not None and len(value) < int(schema["minLength"]):
            raise ValueError(f"{path} is too short")
        if schema.get("maxLength") is not None and len(value) > int(schema["maxLength"]):
            raise ValueError(f"{path} is too long")
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        if schema.get("minimum") is not None and value < schema["minimum"]:
            raise ValueError(f"{path} is below the minimum")
        if schema.get("maximum") is not None and value > schema["maximum"]:
            raise ValueError(f"{path} is above the maximum")
        if schema.get("exclusiveMinimum") is not None and value <= schema["exclusiveMinimum"]:
            raise ValueError(f"{path} must be greater than the exclusive minimum")
        if schema.get("exclusiveMaximum") is not None and value >= schema["exclusiveMaximum"]:
            raise ValueError(f"{path} must be less than the exclusive maximum")


def _validate_tool_arguments(arguments: Dict[str, Any], schema: Dict[str, Any]) -> Optional[str]:
    # User identity is injected from the authenticated context; tenant is pinned before validation.
    properties = schema.get("properties") or {}
    payload = {
        key: value
        for key, value in arguments.items()
        if key not in {"user_id", "approve_writes", "_approve_writes", "business_id"}
    }
    if "business_id" in properties and "business_id" in arguments:
        payload["business_id"] = arguments["business_id"]
    try:
        _validate_schema_value(payload, schema)
        return None
    except (ValueError, TypeError) as exc:
        return str(exc)


def _openai_tool_to_mcp(tool_def: Dict[str, Any], registry: Any) -> Dict[str, Any]:
    fn = tool_def.get("function") or {}
    name = str(fn.get("name", "unknown"))
    read_only = _mcp_readonly(name, registry)
    return {
        "name": name,
        "description": fn.get("description") or "",
        "inputSchema": fn.get("parameters") or {"type": "object", "properties": {}},
        "annotations": {
            "readOnlyHint": read_only,
            "destructiveHint": not read_only,
            "idempotentHint": read_only,
            "openWorldHint": False,
        },
    }


def _get_tools(db: Session, ctx: AuthContext, business_id: int) -> tuple[Any, list[dict[str, Any]]]:
    from app.services.ai.function_registry import AIRole, registry

    context = {
        "db": db,
        "user_context": ctx,
        "business_id": business_id,
        "session_business_id": business_id,
    }
    definitions = registry.get_function_definitions(context)
    # External business connections must never publish operator/system-wide tools.
    business_roles = {AIRole.USER, AIRole.BUSINESS_OWNER}
    definitions = [
        item
        for item in definitions
        if (function := registry.get_function(str((item.get("function") or {}).get("name", ""))))
        and getattr(function, "enabled", True)
        and not getattr(function, "deprecated", False)
        and function.business_context_required
        and bool(function.allowed_roles & business_roles)
    ]
    allowed_tools = getattr(ctx, "mcp_tool_permissions", None)
    if allowed_tools is not None:
        definitions = [
            item for item in definitions
            if str((item.get("function") or {}).get("name", "")) in allowed_tools
        ]
    return registry, definitions


async def handle_mcp_request(
    db: Session,
    ctx: AuthContext,
    body: Dict[str, Any],
    *,
    business_id: Optional[int] = None,
    diagnostic_id: Optional[str] = None,
) -> Dict[str, Any]:
    req_id = body.get("id")
    method = body.get("method")
    params = body.get("params") or {}
    if not isinstance(params, dict):
        return _jsonrpc_error(req_id, -32602, "Invalid params")
    if body.get("jsonrpc") != "2.0":
        return _jsonrpc_error(req_id, -32600, "Invalid Request")

    # The endpoint supplies the tenant from the authenticated MCP credential.
    eff_business = int(business_id or ctx.business_id or 0)
    if not eff_business:
        return _jsonrpc_error(req_id, -32001, "Business-bound MCP credential required")

    request_meta = params.get("_meta") if isinstance(params, dict) else None
    modern = isinstance(request_meta, dict) and request_meta.get("io.modelcontextprotocol/protocolVersion") == "2026-07-28"

    if method == "server/discover":
        if not modern:
            return _jsonrpc_error(req_id, -32601, "Method not found")
        return _jsonrpc_result(req_id, {
            "supportedVersions": ["2026-07-28", MCP_PROTOCOL_VERSION, "2025-06-18", "2025-03-26"],
            "capabilities": {
                "tools": {"listChanged": False},
                "resources": {"subscribe": False, "listChanged": False},
                "prompts": {"listChanged": False},
            },
            "instructions": "Tools are restricted to the business and current user's permissions bound to this credential. Only consented tools are published. Read hesabix://mcp/capabilities to discover this connection's available tools; write operations require the connection's write grant and the user's domain permission.",
            "ttlMs": 300000,
            "cacheScope": "public",
        })

    if method == "initialize":
        if modern:
            return _jsonrpc_error(req_id, -32601, "Method not found")
        requested = params.get("protocolVersion")
        supported = {"2025-11-25", "2025-06-18", "2025-03-26"}
        version = requested if requested in supported else MCP_PROTOCOL_VERSION
        return _jsonrpc_result(
            req_id,
            {
                "protocolVersion": version,
                "capabilities": {
                    "tools": {"listChanged": False},
                    "resources": {"subscribe": False, "listChanged": False},
                    "prompts": {"listChanged": False},
                },
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
                "instructions": "Tools operate only on the business and current user's permissions bound to this credential. Read hesabix://mcp/capabilities to discover this connection's tools. Write operations require a granted ai:tools:write scope and the user's current domain permission.",
            },
        )

    if method in ("notifications/initialized", "notifications/cancelled", "initialized"):
        return _jsonrpc_result(req_id, {})

    if method == "ping":
        return _jsonrpc_result(req_id, {})

    if method == "resources/list":
        return _jsonrpc_result(req_id, {
            "resources": [{
                "uri": "hesabix://business/overview",
                "name": "نمای کلی کسب‌وکار",
                "description": "اطلاعات پایه کسب‌وکاری که این اتصال به آن محدود است.",
                "mimeType": "application/json",
            }, {
                "uri": "hesabix://mcp/capabilities",
                "name": "قابلیت‌های مجاز اتصال",
                "description": "فهرست ابزارها، دسته‌ها، نوع اثر و مجوزهای لازم که برای همین کاربر و اتصال قابل استفاده‌اند.",
                "mimeType": "application/json",
            }],
            **({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"} if modern else {}),
        })

    if method == "resources/read":
        uri = params.get("uri")
        if uri == "hesabix://mcp/capabilities":
            catalog = _visible_tool_catalog(db, ctx, eff_business)
            categories: Dict[str, int] = {}
            for item in catalog:
                categories[item["category"]] = categories.get(item["category"], 0) + 1
            content = json.dumps({
                "business_id": eff_business,
                "tool_count": len(catalog),
                "categories": categories,
                "tools": catalog,
            }, ensure_ascii=False)
            return _jsonrpc_result(req_id, {
                "contents": [{"uri": uri, "mimeType": "application/json", "text": content}],
                **({"resultType": "complete"} if modern else {}),
            })
        if uri != "hesabix://business/overview":
            return _jsonrpc_error(req_id, -32602, "Resource not found")
        from adapters.db.models.business import Business

        business = db.query(Business).filter(
            Business.id == eff_business,
            Business.deleted_at.is_(None),
        ).first()
        if not business:
            return _jsonrpc_error(req_id, -32001, "Business is unavailable")
        content = json.dumps({
            "name": business.name,
            "type": business.business_type.value if hasattr(business.business_type, "value") else str(business.business_type),
            "field": business.business_field.value if hasattr(business.business_field, "value") else str(business.business_field),
        }, ensure_ascii=False)
        return _jsonrpc_result(req_id, {
            "contents": [{"uri": uri, "mimeType": "application/json", "text": content}],
            **({"resultType": "complete"} if modern else {}),
        })

    if method == "prompts/list":
        catalog = _visible_tool_catalog(db, ctx, eff_business)
        categories = {item["category"] for item in catalog}
        prompts = [
            {
                "name": name,
                "description": f"{title} با اتکا به ابزارهای مجاز این اتصال.",
                "arguments": [{"name": "request", "description": "درخواست تکمیلی کاربر (اختیاری)", "required": False}],
            }
            for name, (title, category, _goal) in _PROMPT_CATALOG.items()
            if _prompt_category_available(category, categories) or (name == "business_summary" and bool(catalog))
        ]
        return _jsonrpc_result(req_id, {
            "prompts": prompts,
            **({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"} if modern else {}),
        })

    if method == "prompts/get":
        prompt_name = params.get("name")
        prompt_config = _PROMPT_CATALOG.get(prompt_name)
        if not prompt_config:
            return _jsonrpc_error(req_id, -32602, "Prompt not found")
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict) or set(arguments) - {"request"}:
            return _jsonrpc_error(req_id, -32602, "Invalid prompt arguments")
        user_request = arguments.get("request", "")
        if not isinstance(user_request, str) or len(user_request) > 2000:
            return _jsonrpc_error(req_id, -32602, "Invalid prompt arguments")
        prompt_title, prompt_category, prompt_goal = prompt_config
        catalog = _visible_tool_catalog(db, ctx, eff_business)
        visible_categories = {item["category"] for item in catalog}
        if not _prompt_category_available(prompt_category, visible_categories) and not (prompt_name == "business_summary" and bool(catalog)):
            return _jsonrpc_error(req_id, -32602, "Prompt is not available for this connection")
        prompt_text = _prompt_content(prompt_name, prompt_title, prompt_goal, user_request.strip(), catalog)
        return _jsonrpc_result(req_id, {
            "description": prompt_title,
            "messages": [{"role": "user", "content": {"type": "text", "text": prompt_text}}],
            **({"resultType": "complete"} if modern else {}),
        })

    if method == "tools/list":
        registry, definitions = _get_tools(db, ctx, eff_business)
        tools = []
        for definition in definitions:
            tool = _openai_tool_to_mcp(definition, registry)
            if tool["annotations"]["readOnlyHint"] or WRITE_SCOPE in getattr(ctx, "mcp_scopes", set()):
                tools.append(tool)
        # The internal agent discovers tools independently. Hide it for scoped
        # OAuth grants so it cannot bypass the per-tool allowlist.
        if getattr(ctx, "mcp_tool_permissions", None) is None:
            tools.append(
                {
                    "name": AGENT_TOOL_NAME,
                    "description": "پرسش چندمرحله‌ای از ایجنت حسابیکس؛ ایجنت ابزارهای مجاز و فقط‌خواندنی همین کسب‌وکار را انتخاب و ترکیب می‌کند.",
                    "inputSchema": {
                        "type": "object",
                        "properties": {"query": {"type": "string", "description": "درخواست یا پرسش درباره همین کسب‌وکار"}},
                        "required": ["query"],
                        "additionalProperties": False,
                    },
                    "annotations": {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": False, "openWorldHint": False},
                }
            )
        tools.sort(key=lambda item: item["name"])
        cursor = params.get("cursor")
        try:
            offset = max(0, int(cursor)) if cursor is not None else 0
        except (TypeError, ValueError):
            return _jsonrpc_error(req_id, -32602, "Invalid cursor")
        page_size = 50
        page = tools[offset : offset + page_size]
        result: Dict[str, Any] = {"tools": page}
        if modern:
            result.update({"resultType": "complete", "ttlMs": 0, "cacheScope": "private"})
        if offset + page_size < len(tools):
            result["nextCursor"] = str(offset + page_size)
        return _jsonrpc_result(req_id, result)

    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments") or {}
        if not isinstance(name, str) or not name or not isinstance(arguments, dict):
            return _jsonrpc_error(req_id, -32602, "Invalid tool name or arguments")

        registry, definitions = _get_tools(db, ctx, eff_business)
        available = {str((item.get("function") or {}).get("name")): item for item in definitions}
        if name == AGENT_TOOL_NAME and getattr(ctx, "mcp_tool_permissions", None) is None:
            available[name] = {"function": {"name": name}}
        if name not in available:
            return _jsonrpc_error(req_id, -32602, "Tool not found or not permitted")
        if name != AGENT_TOOL_NAME and not _mcp_readonly(name, registry) and WRITE_SCOPE not in getattr(ctx, "mcp_scopes", set()):
            return _jsonrpc_error(req_id, -32003, "This MCP connection is read-only; create a separately authorized write connection.")
        safe_arguments = prepare_mcp_tool_arguments(arguments, business_id=eff_business)
        if name != AGENT_TOOL_NAME:
            tool_schema = (available[name].get("function") or {}).get("parameters") or {"type": "object"}
            schema_error = _validate_tool_arguments(safe_arguments, tool_schema)
            if schema_error:
                return _jsonrpc_error(req_id, -32602, "Invalid tool arguments", {"reason": schema_error})

        logger.info(
            "mcp_tool_call_started diagnostic_id=%s tool=%s connection_id=%s user_id=%s business_id=%s",
            diagnostic_id,
            name,
            getattr(ctx, "mcp_connection_id", None),
            ctx.get_user_id(),
            eff_business,
        )
        context = {
            "user_context": ctx,
            "business_id": eff_business,
            "session_business_id": eff_business,
        }
        try:
            if name == AGENT_TOOL_NAME:
                query = safe_arguments.get("query")
                if not isinstance(query, str) or not query.strip() or len(query) > 8000:
                    return _jsonrpc_error(req_id, -32602, "query must contain 1 to 8000 characters")
                from app.services.ai.ai_service import AIService

                service = AIService(db, ctx, eff_business)
                result = await service.chat_completion(
                    [{"role": "user", "content": query.strip()}],
                    use_function_calling=True,
                    session_business_id=eff_business,
                    user_query=query.strip(),
                    execution_mode="analyzer",
                    max_iterations=8,
                )
                message = result.get("message") if isinstance(result, dict) else None
                answer = message.get("content") if isinstance(message, dict) else None
                rendered = answer if isinstance(answer, str) and answer.strip() else "Agent task completed without a text answer."
                logger.info(
                    "MCP agent task completed diagnostic_id=%s connection_id=%s user_id=%s business_id=%s",
                    diagnostic_id,
                    getattr(ctx, "mcp_connection_id", None), ctx.get_user_id(), eff_business,
                )
                return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": str(rendered)}], "isError": False, **({"resultType": "complete"} if modern else {})})

            from app.services.ai.ai_db_helpers import run_ai_registry_function

            result = run_ai_registry_function(name, safe_arguments, context)
            text = result if isinstance(result, str) else json.dumps(result, ensure_ascii=False, default=str)
            logger.info(
                "MCP tool call completed diagnostic_id=%s connection_id=%s user_id=%s business_id=%s tool=%s result_type=%s result_chars=%s",
                diagnostic_id,
                getattr(ctx, "mcp_connection_id", None), ctx.get_user_id(), eff_business, name,
                type(result).__name__, len(text),
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": text}], "isError": False, **({"resultType": "complete"} if modern else {})})
        except PermissionError:
            logger.warning(
                "MCP tool call denied diagnostic_id=%s connection_id=%s user_id=%s business_id=%s tool=%s reason=permission_error",
                diagnostic_id,
                getattr(ctx, "mcp_connection_id", None),
                ctx.get_user_id(),
                eff_business,
                name,
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": "Permission denied for this tool."}], "isError": True})
        except Exception:
            from app.services.ai.ai_db_helpers import safe_db_rollback

            safe_db_rollback(db)
            logger.exception(
                "MCP tool call failed diagnostic_id=%s connection_id=%s user_id=%s business_id=%s tool=%s",
                diagnostic_id,
                getattr(ctx, "mcp_connection_id", None), ctx.get_user_id(), eff_business, name,
            )
            return _jsonrpc_result(req_id, {"content": [{"type": "text", "text": "Tool execution failed."}], "isError": True})

    return _jsonrpc_error(req_id, -32601, "Method not found")
