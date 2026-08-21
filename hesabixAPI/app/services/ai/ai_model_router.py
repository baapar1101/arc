"""مسیریابی مدل و ساخت provider — استخراج تدریجی از AIService (ARC-01)."""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from app.core.responses import ApiError
from app.services.ai.ai_constants import AI_OPERATION_CHAT
from app.services.ai.ai_prompt_cache import build_prompt_cache_policy, merge_provider_extra
from app.services.ai.ai_system_prompt import StructuredSystemPrompt
from app.services.ai.ai_tool_intent import query_expects_tool_use
from app.services.ai.prompt_service import PromptRole

logger = logging.getLogger(__name__)


class AIModelRouterMixin:
    """متدهای routing/provider روی AIService می‌مانند؛ بدنه اینجاست."""

    def _is_byok_subscription(self) -> bool:
        from app.services.ai.business_ai_provider_service import is_byok_plan

        return bool(self.subscription and is_byok_plan(self.subscription.plan))

    def _byok_require_test(self) -> bool:
        from app.services.ai.business_ai_provider_service import require_byok_connection_test

        if not self.subscription:
            return True
        return require_byok_connection_test(self.subscription.plan)

    def _get_byok_config(self):
        from app.services.ai.business_ai_provider_service import get_config

        if not self.business_id:
            return None
        return get_config(self.db, int(self.business_id))

    def set_routing_context(
        self,
        *,
        operation: str = AI_OPERATION_CHAT,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
        needs_tools: bool = False,
    ) -> None:
        self._routing_context = {
            "operation": operation,
            "user_query": user_query,
            "history_messages": history_messages,
            "needs_tools": needs_tools,
        }

    def clear_routing_context(self) -> None:
        self._routing_context = None

    def _resolve_routing_params(
        self,
        *,
        operation: Optional[str] = None,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
        needs_tools: Optional[bool] = None,
    ) -> Dict[str, Any]:
        base = self._routing_context or {}
        return {
            "operation": operation if operation is not None else base.get("operation", AI_OPERATION_CHAT),
            "user_query": user_query if user_query is not None else base.get("user_query"),
            "history_messages": (
                history_messages if history_messages is not None else base.get("history_messages")
            ),
            "needs_tools": needs_tools if needs_tools is not None else bool(base.get("needs_tools", False)),
        }

    def set_request_model(self, model_code: Optional[str]) -> None:
        self._request_model_code = model_code.strip() if model_code and str(model_code).strip() else None

    def get_requested_model_code(self) -> str:
        from app.services.ai.ai_model_service import resolve_requested_model_code

        plan = self.subscription.plan if self.subscription else None
        return resolve_requested_model_code(
            self.db,
            request_model=self._request_model_code,
            subscription=self.subscription,
            plan=plan,
            config=self.config,
            business_id=int(self.business_id) if self.business_id else None,
        )

    def get_effective_model_code(
        self,
        *,
        operation: Optional[str] = None,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
        needs_tools: Optional[bool] = None,
    ) -> str:
        from app.services.ai.ai_model_service import resolve_effective_model_code

        routing = self._resolve_routing_params(
            operation=operation,
            user_query=user_query,
            history_messages=history_messages,
            needs_tools=needs_tools,
        )
        plan = self.subscription.plan if self.subscription else None
        return resolve_effective_model_code(
            self.db,
            request_model=self._request_model_code,
            subscription=self.subscription,
            plan=plan,
            config=self.config,
            business_id=int(self.business_id) if self.business_id else None,
            **routing,
        )

    def get_effective_model_api_id(
        self,
        *,
        operation: Optional[str] = None,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
        needs_tools: Optional[bool] = None,
    ) -> str:
        from app.services.ai.ai_model_service import get_api_model_id

        code = self.get_effective_model_code(
            operation=operation,
            user_query=user_query,
            history_messages=history_messages,
            needs_tools=needs_tools,
        )
        if self._is_byok_subscription() and self.business_id:
            from app.services.ai.business_ai_provider_service import get_byok_model_api_id

            return get_byok_model_api_id(self.db, int(self.business_id), code)
        return get_api_model_id(self.db, code, self.config)

    def get_effective_provider_type(
        self,
        *,
        operation: Optional[str] = None,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
        needs_tools: Optional[bool] = None,
    ) -> str:
        if self._is_byok_subscription():
            cfg = self._get_byok_config()
            if cfg and cfg.provider:
                return cfg.provider
        from app.services.ai.ai_model_service import get_model_provider

        return get_model_provider(
            self.db,
            self.get_effective_model_code(
                operation=operation,
                user_query=user_query,
                history_messages=history_messages,
                needs_tools=needs_tools,
            ),
            self.config,
        )

    def _validate_request_model_if_set(self) -> None:
        if not self._request_model_code:
            return
        from app.services.ai.ai_model_service import validate_model_selection

        plan = self.subscription.plan if self.subscription else None
        validate_model_selection(
            self.db,
            plan,
            self._request_model_code,
            business_id=int(self.business_id) if self.business_id else None,
        )

    def _effective_max_tokens(
        self,
        override: Optional[int] = None,
        *,
        operation: str = AI_OPERATION_CHAT,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
        needs_tools: bool = False,
    ) -> int:
        from app.services.ai.ai_model_service import get_max_tokens_for_model

        if override is not None:
            return int(override)
        return get_max_tokens_for_model(
            self.db,
            self.get_effective_model_code(
                operation=operation,
                user_query=user_query,
                history_messages=history_messages,
                needs_tools=needs_tools,
            ),
            self.config,
        )

    def _effective_reasoning_effort(
        self,
        *,
        complexity: Optional[str] = None,
        operation: str = AI_OPERATION_CHAT,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
        needs_tools: bool = False,
    ) -> Optional[str]:
        """سطح تلاش استدلال مؤثر برای مدل جاری (None اگر مدل reasoning نباشد)."""
        from app.services.ai.ai_model_service import get_reasoning_effort_for_model

        try:
            return get_reasoning_effort_for_model(
                self.db,
                self.get_effective_model_code(
                    operation=operation,
                    user_query=user_query,
                    history_messages=history_messages,
                    needs_tools=needs_tools,
                ),
                complexity=complexity,
            )
        except Exception as exc:
            logger.warning("reasoning effort resolve failed: %s", exc)
            return None

    def _make_provider(self, provider_type: Optional[str] = None):
        """ساخت provider فعال برای تخمین توکن و فراخوانی مدل."""
        from app.services.ai.ai_provider import create_provider
        from app.services.ai.ai_provider_service import resolve_provider_connection

        if self._is_byok_subscription():
            if not self.business_id:
                raise ApiError(
                    "BUSINESS_REQUIRED",
                    "برای پلن ارائه‌دهنده اختصاصی، انتخاب کسب‌وکار الزامی است",
                    http_status=400,
                )
            from app.services.ai.business_ai_provider_service import resolve_byok_connection

            ptype, api_key, api_base_url, _fce = resolve_byok_connection(
                self.db, int(self.business_id)
            )
            if provider_type and provider_type != ptype:
                # مدل‌های BYOK فقط از همان provider کسب‌وکار استفاده می‌کنند
                ptype = provider_type if provider_type == ptype else ptype
            return create_provider(
                provider_type=ptype,
                api_key=api_key,
                api_base_url=api_base_url,
            )

        ptype = provider_type or self.get_effective_provider_type()
        _, api_key, api_base_url, _fce = resolve_provider_connection(
            self.db,
            ptype,
            legacy_config=self.config,
        )
        if not api_key:
            raise ApiError("API_KEY_NOT_SET", "API Key تنظیم نشده است", http_status=400)
        return create_provider(
            provider_type=ptype,
            api_key=api_key,
            api_base_url=api_base_url,
        )

    def _anthropic_skills_extra(
        self,
        session_business_id: Optional[int],
        user_query: Optional[str],
    ) -> Optional[Dict[str, Any]]:
        if self.get_effective_provider_type() != "anthropic":
            return None
        bid = session_business_id or self.business_id
        if not bid:
            return None
        try:
            from app.services.ai.ai_skill_runtime import get_runtime_skill_context

            ctx = get_runtime_skill_context(
                self.db, int(bid), user_query or ""
            )
            ids = [s for s in (ctx.get("anthropic_skill_ids") or []) if s]
            if ids:
                return {"anthropic_skills": ids}
        except Exception as exc:
            logger.warning("Anthropic skills resolve failed: %s", exc)
        return None

    def _resolve_prompt_role(self) -> PromptRole:
        if self.ctx.is_superadmin():
            return PromptRole.ADMIN
        if self.ctx.can_access_support_operator():
            return PromptRole.OPERATOR
        return PromptRole.USER

    def _provider_call_extras(
        self,
        provider: Any,
        provider_extra: Optional[Dict[str, Any]],
        structured_prompt: Optional[StructuredSystemPrompt] = None,
    ) -> Dict[str, Any]:
        merged = merge_provider_extra(provider_extra, None)
        if structured_prompt is not None:
            policy = build_prompt_cache_policy(
                structured_prompt,
                self.get_effective_provider_type(),
                provider,
            )
            merged = merge_provider_extra(merged, policy)
        from app.services.ai.ai_prompt_cache import openai_supports_prompt_cache
        from app.services.ai.ai_provider_context import (
            attach_fingerprint_to_cache_key,
            resolve_provider_context_policy,
        )

        fingerprint = getattr(self, "_tool_context_fingerprint", "") or ""
        ctx_policy = resolve_provider_context_policy(
            self.get_effective_provider_type(),
            fingerprint=fingerprint,
            openai_official=openai_supports_prompt_cache(
                getattr(provider, "api_base_url", None)
            ),
        )
        merged = dict(merged or {})
        merged["tool_context"] = ctx_policy.to_dict()
        cache_block = merged.get("prompt_cache")
        if fingerprint and isinstance(cache_block, dict) and cache_block.get("cache_key"):
            cache_block["cache_key"] = attach_fingerprint_to_cache_key(
                str(cache_block.get("cache_key") or ""),
                fingerprint,
            )
        if merged:
            return {"provider_extra": merged}
        return {}

    def _provider_supports_tools(self, provider_type: Optional[str] = None) -> bool:
        if self._is_byok_subscription():
            cfg = self._get_byok_config()
            if cfg is not None:
                return bool(cfg.function_calling_enabled)
            return True

        from app.services.ai.ai_provider_service import resolve_provider_connection

        ptype = provider_type or self.get_effective_provider_type()
        try:
            _, _, _, fce = resolve_provider_connection(
                self.db, ptype, legacy_config=self.config
            )
            return bool(fce)
        except ApiError:
            if self.config and getattr(self.config, "function_calling_enabled", True) is False:
                return False
            return True

    def _routing_needs_tools(
        self,
        use_function_calling: bool,
        user_query: Optional[str],
        history_messages: Optional[List[Dict[str, Any]]],
    ) -> bool:
        """آیا این سوال به ابزار/داده نیاز دارد؟

        قبلاً فقط بر اساس پیچیدگی (medium/complex) تصمیم می‌گرفت؛ سوال‌های ساده
        اما داده‌محور (مثل «یه گزارش از هزینه‌ها بهم بگو») هرگز tools=None
        نمی‌گرفتند و narrative میانی به‌جای پاسخ نهایی می‌ماند. حالا از
        query_expects_tool_use (که هم پیچیدگی و هم دامنهٔ ابزار/تاریخچه را
        می‌بیند) استفاده می‌شود.
        """
        if not use_function_calling:
            return False
        return query_expects_tool_use(user_query, history_messages)

    def _use_tools_for_request(self, use_function_calling: bool) -> bool:
        """
        اگر در تنظیمات سراسری function_calling_enabled=False باشد،
        tools به provider ارسال نمی‌شود (مثال: vLLM بدون --enable-auto-tool-choice).
        """
        if not use_function_calling:
            return False
        if not self._provider_supports_tools():
            return False
        from app.services.ai.ai_model_service import model_supports_tools

        if not model_supports_tools(self.db, self.get_effective_model_code(), self.config):
            return False
        return True
