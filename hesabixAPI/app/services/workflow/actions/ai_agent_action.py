"""
AI Agent Action - نود هوشمند مشابه n8n AI Agent
با قابلیت فراخوانی توابع AI، تصمیم‌گیری و تولید متن
"""

from typing import Any, Dict, List, Optional
import json
import logging
import re
from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.workflow_engine import WorkflowEngine
from app.services.workflow.logging_decorators import log_action_execution

logger = logging.getLogger(__name__)


def _resolve_template(template: str, context: Dict[str, Any], node_results: Dict[str, Any]) -> str:
    """
    حل template با placeholderهای $node_id.field و {{ variable }}
    """
    if not template or not isinstance(template, str):
        return str(template or "")

    result = template

    # حل $node_id.field
    def replace_ref(match):
        ref = match.group(1).strip()
        val = WorkflowEngine._resolve_value_static(f"${ref}", context, node_results)
        if val is None:
            return ""
        if isinstance(val, (dict, list)):
            return json.dumps(val, ensure_ascii=False)
        return str(val)

    result = re.sub(r'\$([a-zA-Z0-9_.]+)', replace_ref, result)

    # حل {{ variable }} برای trigger_data و context
    def replace_brace(match):
        key = match.group(1).strip()
        parts = key.split(".")
        val = None
        if parts[0] == "trigger_data" and len(parts) > 1:
            val = context.get("trigger_data", {})
            for p in parts[1:]:
                val = val.get(p) if isinstance(val, dict) else None
                if val is None:
                    break
        elif parts[0] in context:
            val = context[parts[0]]
            for p in parts[1:]:
                val = val.get(p) if isinstance(val, dict) else None
                if val is None:
                    break
        elif parts[0] in node_results:
            val = node_results[parts[0]]
            for p in parts[1:]:
                val = val.get(p) if isinstance(val, dict) else val
                if val is None:
                    break
        if val is None:
            return ""
        if isinstance(val, (dict, list)):
            return json.dumps(val, ensure_ascii=False)
        return str(val)

    result = re.sub(r'\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}', replace_brace, result)

    return result


class AIAgentAction(ActionHandler):
    """
    AI Agent Action - نود هوشمند برای اتوماسیون
    قابلیت: تولید متن، تصمیم‌گیری، فراخوانی توابع، رده‌بندی، خروجی JSON
    """

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "AI Agent",
            "description": "عامل هوشمند برای تولید متن، تصمیم‌گیری، فراخوانی توابع و خروجی ساختاریافته. مشابه n8n AI Agent.",
            "config_schema": {
                "system_prompt": {
                    "type": "string",
                    "description": "دستورات سیستم برای AI (وظیفه، قوانین، قالب خروجی)",
                    "required": True,
                    "ui_type": "textarea",
                },
                "user_prompt": {
                    "type": "string",
                    "description": "سوال یا دستور برای AI. می‌توانید از $trigger_1، $node_id و {{ trigger_data.field }} استفاده کنید.",
                    "required": True,
                    "ui_type": "textarea",
                },
                "tools_mode": {
                    "type": "string",
                    "description": "حالت ابزارها",
                    "enum": ["all", "category", "custom", "none"],
                    "default": "all",
                    "required": False,
                    "ui_config": {
                        "labels": {
                            "all": "همه توابع",
                            "category": "بر اساس دسته",
                            "custom": "لیست سفارشی",
                            "none": "بدون توابع",
                        }
                    },
                },
                "tools_category": {
                    "type": "string",
                    "description": "دسته توابع (در حالت category)",
                    "required": False,
                    "enum": ["invoices", "persons", "products", "financial", "crm", "business"],
                },
                "tools_allowlist": {
                    "type": "string",
                    "description": "لیست توابع مجاز (جدا شده با کاما) - در حالت custom",
                    "required": False,
                },
                "tools_denylist": {
                    "type": "string",
                    "description": (
                        "لیست توابع غیرمجاز (جدا شده با کاما). "
                        "ابزارهای workflow (create_workflow و …) به‌طور پیش‌فرض مسدودند."
                    ),
                    "required": False,
                },
                "max_iterations": {
                    "type": "integer",
                    "description": "حداکثر چرخه فراخوانی توابع",
                    "default": 5,
                    "required": False,
                },
                "temperature": {
                    "type": "number",
                    "description": "دما (0 برای تصمیم‌گیری دقیق، بالاتر برای خلاقیت)",
                    "default": 0.3,
                    "required": False,
                },
                "max_tokens": {
                    "type": "integer",
                    "description": "حداکثر توکن خروجی",
                    "default": 2000,
                    "required": False,
                },
                "output_mode": {
                    "type": "string",
                    "description": "نوع خروجی",
                    "enum": ["text", "json"],
                    "default": "text",
                    "required": False,
                    "ui_config": {
                        "labels": {"text": "متن", "json": "JSON"}
                    },
                },
                "inject_trigger_data": {
                    "type": "boolean",
                    "description": "اضافه کردن trigger_data به context",
                    "default": True,
                    "required": False,
                },
                "inject_node_results": {
                    "type": "boolean",
                    "description": "اضافه کردن نتایج نودهای قبلی به context",
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
        node_results: Dict[str, Any]
    ) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip

        sk = dry_run_skip(context, "دستیار هوشمند (AI)")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        user_id = context.get("user_id")
        trigger_data = context.get("trigger_data", {})
        workflow_id = context.get("workflow_id")
        execution_id = context.get("execution_id")

        if not db or not business_id:
            raise ValueError("AI Agent requires db and business_id in context")

        # ساخت AuthContext برای AIService
        from adapters.db.models.user import User
        from app.core.auth_dependency import AuthContext

        user = None
        if user_id:
            user = db.get(User, user_id)
        if not user:
            # استفاده از کاربر سیستمی یا owner کسب‌وکار
            from adapters.db.models.business import Business
            business = db.get(Business, business_id)
            if business and business.owner_id:
                user = db.get(User, business.owner_id)
            if not user:
                system_user = db.query(User).filter(User.email.ilike("%system%")).first()
                if not system_user:
                    system_user = db.query(User).filter(User.app_permissions.isnot(None)).first()
                user = system_user
        if not user:
            raise ValueError("AI Agent: No user found for workflow context")

        auth_ctx = AuthContext(
            user=user,
            api_key_id=0,
            language="fa",
            business_id=business_id,
            db=db
        )

        from app.services.ai.ai_service import AIService
        from app.services.ai.function_registry import registry
        from app.core.responses import ApiError

        ai_service = AIService(db=db, user_context=auth_ctx, business_id=business_id)

        # بررسی امکان استفاده از AI
        check = ai_service.check_availability(estimated_tokens=500)
        if not check.get("can_use", True):
            reason = check.get("reason", "UNKNOWN")
            raise ApiError(
                f"AI_{reason}",
                check.get("details", {}).get("message", "امکان استفاده از AI وجود ندارد"),
                http_status=403
            )

        # حل templateها
        system_prompt = _resolve_template(
            config.get("system_prompt", ""),
            context, node_results
        )
        user_prompt = _resolve_template(
            config.get("user_prompt", ""),
            context, node_results
        )

        if not system_prompt.strip():
            raise ValueError("AI Agent: system_prompt is required")

        # اضافه کردن context به system prompt
        if config.get("inject_trigger_data", True) and trigger_data:
            system_prompt += f"\n\nداده‌های trigger:\n```json\n{json.dumps(trigger_data, ensure_ascii=False)}\n```"
        if config.get("inject_node_results", True) and node_results:
            summary = {}
            for nid, res in node_results.items():
                if isinstance(res, dict) and len(str(res)) < 500:
                    summary[nid] = res
                else:
                    summary[nid] = str(res)[:200] + "..." if len(str(res)) > 200 else res
            system_prompt += f"\n\nنتایج نودهای قبلی:\n```json\n{json.dumps(summary, ensure_ascii=False)}\n```"

        # ساخت messages - دستورات سیستم و درخواست را در user message قرار می‌دهیم
        user_content = f"{system_prompt}\n\n---\n\n{user_prompt or 'لطفاً پاسخ دهید.'}"
        messages = [{"role": "user", "content": user_content}]

        # تنظیم ابزارها (tools)
        tools = None
        use_function_calling = True
        tools_mode = config.get("tools_mode", "all")

        if tools_mode != "none":
            category = config.get("tools_category") if tools_mode == "category" else None
            tools = ai_service.get_available_functions(
                category=category,
                session_business_id=business_id
            )
            if not isinstance(tools, list):
                tools = [tools] if tools else []

            if tools_mode == "custom" and config.get("tools_allowlist"):
                allow_names = {n.strip() for n in config["tools_allowlist"].split(",") if n.strip()}
                if allow_names:
                    tools = [t for t in tools if t.get("function", {}).get("name") in allow_names]

            from app.services.ai.ai_workflow_agent_policy import merge_workflow_agent_denylist

            user_deny = None
            if config.get("tools_denylist"):
                user_deny = {n.strip() for n in config["tools_denylist"].split(",") if n.strip()}
            denylist = merge_workflow_agent_denylist(user_deny)
            if tools and denylist:
                tools = [
                    t for t in tools
                    if t.get("function", {}).get("name") not in denylist
                ]
        else:
            use_function_calling = False

        max_iterations = min(int(config.get("max_iterations", 5)), 15)
        max_tokens = int(config.get("max_tokens", 2000))
        temperature = float(config.get("temperature", 0.3))

        try:
            temperature = float(config.get("temperature", 0.3)) if config.get("temperature") is not None else 0.3
            response = ai_service.chat_completion_sync(
                messages=messages,
                tools=tools,
                use_function_calling=use_function_calling,
                max_tokens_override=max_tokens,
                temperature_override=temperature,
                session_business_id=business_id,
                max_iterations=max_iterations
            )
        except ApiError:
            raise
        except Exception as e:
            logger.error(f"AI Agent execution failed: {e}", exc_info=True)
            raise

        # شارژ و لاگ
        usage = response.get("usage", {})
        input_tokens = usage.get("input_tokens", 0)
        output_tokens = usage.get("output_tokens", 0)
        if input_tokens or output_tokens:
            try:
                charge_result = ai_service.check_quota_and_charge(input_tokens, output_tokens)
                ai_service.log_usage(
                    provider=ai_service.config.provider if ai_service.config else "openai",
                    model=ai_service.config.model_name if ai_service.config else "gpt-4",
                    input_tokens=input_tokens,
                    output_tokens=output_tokens,
                    cost=charge_result.get("cost", 0),
                    payment_method=charge_result.get("payment_method", "free"),
                    wallet_transaction_id=charge_result.get("wallet_transaction_id"),
                    document_id=charge_result.get("document_id"),
                    context={
                        "workflow_id": workflow_id,
                        "execution_id": execution_id,
                        "node_type": "ai_agent",
                    },
                )
            except Exception as e:
                logger.warning(f"AI Agent: Failed to charge/log usage: {e}")

        content = response.get("message", {}).get("content") or ""

        # خروجی
        output_mode = config.get("output_mode", "text")
        parsed = None
        if output_mode == "json" and content.strip():
            try:
                content_clean = content.strip()
                if content_clean.startswith("```"):
                    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", content_clean)
                    if match:
                        content_clean = match.group(1).strip()
                parsed = json.loads(content_clean)
            except json.JSONDecodeError:
                parsed = {"raw": content, "parse_error": True}

        result = {
            "success": True,
            "content": content,
            "usage": usage,
        }
        if parsed is not None:
            result["parsed"] = parsed
            result["response"] = parsed

        return result
