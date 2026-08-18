from __future__ import annotations

from typing import Dict, Any, List, Optional, AsyncGenerator, AbstractSet, Set, Union
from decimal import Decimal
from sqlalchemy.orm import Session
import json
import logging
import asyncio
import time
from concurrent.futures import ThreadPoolExecutor

from app.core.auth_dependency import AuthContext
from app.core.responses import ApiError
from app.services.ai.function_registry import registry, AIRole
from adapters.db.repositories.ai_config_repository import AIConfigRepository
from adapters.db.repositories.ai_subscription_repository import AISubscriptionRepository
from adapters.db.models.ai_subscription import UserAISubscription
from app.services.ai.prompt_service import get_prompt, get_prompt_by_key, PromptRole
from app.services.ai.ai_untrusted import with_untrusted_policy
from app.services.ai.ai_write_guard import (
    is_write_function,
    is_write_guard_stop_result,
    build_approval_pause_content,
    build_approval_required_result,
    build_approval_mismatch_result,
    build_read_only_mode_result,
    resolve_approved_write,
    is_readonly_function,
    is_agent_internal_function,
    WRITE_FUNCTION_LABELS_FA,
)
from app.services.ai.ai_execution_policy import (
    DEFAULT_EXECUTION_MODE,
    execution_mode_prompt_block,
    exposes_write_tools,
    resolve_execution_mode,
    should_block_write_in_analyzer,
    should_require_write_approval,
)
from app.services.ai.ai_tool_keys import (
    status_event,
    tool_label_fa,
    tool_l10n_key,
)
from app.services.ai.ai_answer_from_evidence import (
    build_deterministic_answer_from_trace,
    redact_final_answer_from_reasoning_trace,
)
from app.services.ai.ai_content_sanitize import (
    resolve_round_function_calls,
    sanitize_assistant_content,
)
from app.services.ai.ai_trace import (
    context_trace,
    extract_citations_from_result,
    extract_explored_context_for_synthesis,
    extract_final_content_from_trace,
    extract_result_count,
    extract_usable_narrative_for_answer,
    finalize_trace_steps_for_persist,
    format_planned_tools,
    summarize_tool_result,
    summarize_tool_result_for_llm,
    trace_has_unanswered_evidence,
    trace_record_from_event,
    trace_step,
)
from app.services.ai.ai_db_helpers import (
    json_safe_value,
    run_ai_registry_function,
    safe_db_rollback,
)
from app.services.ai.ai_constants import (
    AI_OPERATION_CHAT,
    AI_OPERATION_HISTORY_SUMMARY,
    AI_OPERATION_SUBAGENT,
    AI_OPERATION_TITLE,
    AI_OPERATION_THOUGHT,
    EXPLORATION_COMPLEXITY_ITERATIONS,
    EXPLORATION_LLM_THOUGHT_MIN_TOOLS,
    FORCED_SYNTHESIS_TIMEOUT_SEC,
    KNOWLEDGE_LOAD_TIMEOUT_SEC,
    MAX_AGENT_ITERATIONS,
    PLANNING_STEP_MIN_CHARS,
    PROMPT_LOADER_TIMEOUT_SEC,
)
from app.services.ai.ai_exploration_service import (
    EXPLORATION_MODE_EXPLORE,
    ObservationStore,
    ExplorationBundle,
    ThoughtRecord,
    ToolObservation,
    build_explored_body_markdown,
    build_thought_markdown_rule_based,
    bundle_title_from_calls,
    explore_target_for_call,
    extract_entity_refs_from_calls,
    new_bundle_id,
    resolve_exploration_enabled,
    assess_tool_round_productivity,
    synthesize_thought_with_llm,
)
from app.services.ai.ai_goal_assessment import (
    AgentGoalTracker,
    resolve_budget_gate,
    should_agent_continue_after_text_round,
    try_extend_budget_for_goal,
)
from app.services.ai.ai_agent_run import (
    AGENT_RUN_PHASE_AGENT_LOOP,
    AGENT_RUN_PHASE_DONE,
    AGENT_RUN_PHASE_ERROR,
    AGENT_RUN_PHASE_GATHER_CONTEXT,
    AGENT_RUN_PHASE_SYNTHESIZE,
    AgentRunState,
    new_agent_run_id,
    status_for_stop,
)
from app.services.ai.ai_tool_parallel import parallel_round_stats, run_tool_calls_partitioned
from app.services.ai.ai_retry_policy import is_retryable_error
from app.services.ai.ai_constants import MAX_LLM_RETRIES
from app.services.ai.ai_budget import (
    AgentBudget,
    STOP_REASON_ITERATIONS,
    STOP_REASON_WALL_CLOCK,
    build_agent_budget,
    budget_snapshot,
)
from app.services.ai.ai_stream_budget import WallClockExceeded, iter_stream_with_wall_clock
from app.services.ai.ai_tool_catalog import (
    build_tool_catalog_system_section,
    is_tool_discovery_query,
)
from app.services.ai.ai_tool_cache import (
    get_cached,
    invalidate_session,
    set_cached,
)
from app.services.ai.ai_system_prompt import (
    StructuredSystemPrompt,
    compose_structured_system_prompt,
    coerce_structured_system_prompt,
    split_runtime_prompt_parts,
)
from app.services.ai.ai_model_router import AIModelRouterMixin
from app.services.ai.ai_usage_meter import AIUsageMeterMixin
from app.services.ai.ai_context_budget import (
    context_usage_event_payload,
    is_context_overflow_error,
    prepare_messages_for_context,
)
from app.services.ai.ai_tool_intent import (
    estimate_query_complexity,
    filter_function_definitions,
    iterations_for_query,
    merge_tool_allowlists,
    query_expects_tool_use,
    query_needs_knowledge,
    select_tool_names,
)

logger = logging.getLogger(__name__)

# Thread pool executor برای اجرای عملیات blocking
_executor = ThreadPoolExecutor(max_workers=10, thread_name_prefix="ai_service")


def _unpack_memory_loader(value: Any) -> tuple[str, str]:
    """خروجی loader حافظه: (بلوک semi_static, لنگر هویت)."""
    if isinstance(value, tuple) and len(value) >= 2:
        return str(value[0] or ""), str(value[1] or "")
    if isinstance(value, str):
        return value, ""
    return "", ""

def _tool_call_id_for(call: Dict[str, Any], iteration: int, index: int) -> str:
    return str(call.get("id") or f"call_{iteration}_{index}_{call.get('name', 'unknown')}")

def _lookup_tool_result(
    function_results: Dict[str, Any],
    call: Dict[str, Any],
) -> Any:
    """یافتن نتیجه با tool_call_id؛ fallback به نام function."""
    tc_id = call.get("id")
    if tc_id and tc_id in function_results:
        val = function_results[tc_id]
        if isinstance(val, dict) and "result" in val:
            return val["result"]
        return val
    name = call.get("name")
    if name and name in function_results:
        val = function_results[name]
        if isinstance(val, dict) and "result" in val and "name" in val:
            return val.get("result")
        return val
    return {}

def _merge_round_tool_results(
    accumulated: Dict[str, Any],
    round_results: Dict[str, Any],
) -> None:
    """ادغام نتایج یک round؛ کلید اصلی tool_call_id + سازگاری با نام."""
    for tc_id, entry in round_results.items():
        if isinstance(entry, dict) and "name" in entry and "result" in entry:
            accumulated[tc_id] = entry
            accumulated[entry["name"]] = entry["result"]
        else:
            accumulated[tc_id] = entry

class AIService(AIModelRouterMixin, AIUsageMeterMixin):
    """سرویس اصلی AI با یکپارچه‌سازی کیف پول"""
    
    def __init__(
        self,
        db: Session,
        user_context: AuthContext,
        business_id: Optional[int] = None
    ):
        self.db = db
        self.ctx = user_context
        self.business_id = business_id or user_context.business_id
        self.subscription = self._get_active_subscription()
        self.config = self._get_ai_config()
        self._request_model_code: Optional[str] = None
        self._routing_context: Optional[Dict[str, Any]] = None
        self._turn_activated_skills: List[Dict[str, Any]] = []
        self._subagent_depth: int = 0
        self._subagent_sse_queue: asyncio.Queue = asyncio.Queue()
    
    def _get_active_subscription(self) -> Optional[UserAISubscription]:
        """دریافت اشتراک فعال کاربر"""
        # اگر دسترسی سیستمی ندارد، business_id الزامی است
        # چون کیف پول‌ها فقط business-specific هستند
        if not self.business_id:
            if not (self.ctx.can_access_support_operator() or self.ctx.is_superadmin()):
                logger.warning(
                    f"AIService initialized without business_id for regular user {self.ctx.get_user_id()}. "
                    f"This may cause issues with wallet charging."
                )
            return None
        
        repo = AISubscriptionRepository(self.db)
        return repo.get_active_subscription(
            user_id=self.ctx.get_user_id(),
            business_id=self.business_id
        )

    
    
    def _get_ai_config(self):
        """دریافت تنظیمات AI"""
        repo = AIConfigRepository(self.db)
        return repo.get_active_config()

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    def _prepare_llm_messages(
        self,
        system_prompt: Union[str, StructuredSystemPrompt],
        messages: List[Dict[str, Any]],
        provider: Any = None,
        *,
        force_summarize: bool = False,
        use_llm_summary: bool = False,
    ) -> tuple[List[Dict[str, Any]], Dict[str, Any]]:
        from app.services.ai.ai_history_summarizer import (
            build_rule_based_history_summary,
        )

        if provider is None:
            provider = self._make_provider()

        structured = coerce_structured_system_prompt(system_prompt)

        def summarize_fn(middle_msgs: List[Dict[str, Any]]) -> str:
            if use_llm_summary and self.config:
                from app.services.ai.ai_summarize_quota import (
                    can_use_llm_summarize,
                    record_llm_summarize,
                )

                bid = self.business_id
                uid = self.ctx.get_user_id()
                # بدون اشتراک/سهمیه به LLM نزن — فقط خلاصهٔ rule-based
                can_bill = False
                if bid and uid and can_use_llm_summarize(uid, int(bid)):
                    try:
                        can_bill = bool(
                            self.check_availability(
                                estimated_tokens=800,
                                user_query="history_summary",
                            ).get("can_use")
                        )
                    except Exception:
                        can_bill = False
                if can_bill:
                    from app.services.ai.ai_history_summarizer import (
                        summarize_history_with_llm_detailed,
                    )
                    from app.services.ai.ai_language_prompt import (
                        detect_message_language,
                    )
                    from app.services.ai.ai_usage_accumulate import merge_usage

                    last_user = next(
                        (
                            m.get("content")
                            for m in reversed(middle_msgs)
                            if m.get("role") == "user"
                            and isinstance(m.get("content"), str)
                        ),
                        None,
                    )
                    text, summary_usage = summarize_history_with_llm_detailed(
                        provider,
                        self.get_effective_model_api_id(
                            operation=AI_OPERATION_HISTORY_SUMMARY,
                        ),
                        middle_msgs,
                        db=self.db,
                        language=detect_message_language(last_user),
                    )
                    if text:
                        if summary_usage:
                            self._turn_usage = merge_usage(
                                getattr(self, "_turn_usage", None),
                                summary_usage,
                            )
                        record_llm_summarize(uid, int(bid))
                        from app.services.ai.ai_ops_metrics import log_ai_event

                        log_ai_event(
                            "context_llm_summarized",
                            business_id=int(bid),
                            user_id=uid,
                        )
                        return text
            return build_rule_based_history_summary(middle_msgs)

        return prepare_messages_for_context(
            structured,
            messages,
            provider,
            summarize_fn=summarize_fn,
            force_summarize=force_summarize,
            structured_role=structured.role,
            structured_business_id=structured.business_id,
        )

    

    
    
    def check_availability(
        self,
        estimated_tokens: int = 1000,
        model: Optional[str] = None,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """
        بررسی اینکه آیا کاربر می‌تواند از AI استفاده کند
        (بدون ارسال واقعی پیام - برای چک پیشگیرانه)
        
        Returns:
            {
                "can_use": bool,
                "reason": str | None,
                "details": {
                    "subscription": {...},
                    "wallet": {...},
                    "suggestions": [...]
                }
            }
        """
        if model:
            self.set_request_model(model)
        try:
            from app.services.ai.ai_model_service import is_auto_model_code

            requested_model = self.get_requested_model_code()
            if is_auto_model_code(requested_model):
                self.set_routing_context(
                    operation=AI_OPERATION_CHAT,
                    user_query=user_query,
                    history_messages=history_messages,
                    needs_tools=self._routing_needs_tools(
                        True, user_query, history_messages
                    ),
                )
            effective_model = self.get_effective_model_code()
        except ApiError as exc:
            err = {}
            if isinstance(exc.detail, dict):
                err = exc.detail.get("error") or {}
            return {
                "can_use": False,
                "reason": err.get("code", "NO_AI_MODEL"),
                "details": {
                    "message": err.get("message", "مدل در دسترس نیست"),
                    "suggestions": ["مدل دیگری انتخاب کنید یا با پشتیبانی تماس بگیرید"],
                },
            }
        self._validate_request_model_if_set()

        # دسترسی‌های سیستمی (اپراتور/سوپرادمین) بدون نیاز به اشتراک
        if self.ctx.can_access_support_operator() or self.ctx.is_superadmin():
            fce = bool(getattr(self.config, "function_calling_enabled", True)) if self.config else True
            return {
                "can_use": True,
                "reason": None,
                "details": {
                    "subscription": {
                        "plan_name": "دسترسی سیستمی",
                        "plan_type": "system",
                        "is_unlimited": True
                    },
                    "function_calling_enabled": fce,
                    "suggestions": []
                }
            }
        
        # بررسی اشتراک
        if not self.subscription:
            from adapters.db.repositories.ai_plan_repository import AIPlanRepository
            plan_repo = AIPlanRepository(self.db)
            available_plans = plan_repo.get_active_plans()
            
            return {
                "can_use": False,
                "reason": "NO_ACTIVE_SUBSCRIPTION",
                "details": {
                    "message": "اشتراک فعالی وجود ندارد",
                    "available_plans": [
                        {
                            "id": p.id,
                            "name": p.name,
                            "plan_type": p.plan_type,
                            "description": p.description
                        }
                        for p in available_plans[:3]  # نمایش ۳ پلن اول
                    ],
                    "suggestions": [
                        "برای استفاده از هوش مصنوعی، ابتدا یک پلن را انتخاب کنید",
                        "پلن رایگان با ۵۰۰۰ توکن در دسترس است"
                    ]
                }
            }

        plan = self.subscription.plan
        from app.services.ai.business_ai_provider_service import (
            config_is_ready,
            is_byok_plan,
            parse_models_json,
            require_byok_connection_test,
        )

        if is_byok_plan(plan):
            if not self.business_id:
                return {
                    "can_use": False,
                    "reason": "BUSINESS_REQUIRED",
                    "details": {
                        "message": "برای پلن ارائه‌دهنده اختصاصی، انتخاب کسب‌وکار الزامی است",
                        "suggestions": ["لطفاً ابتدا یک کسب‌وکار را انتخاب کنید"],
                    },
                }
            byok_cfg = self._get_byok_config()
            require_test = require_byok_connection_test(plan)
            if not config_is_ready(byok_cfg, require_test=require_test):
                suggestions = [
                    "از بخش تنظیمات کسب‌وکار → ارائه‌دهنده هوش مصنوعی، URL و API Key را وارد کنید",
                ]
                if byok_cfg and byok_cfg.api_key and require_test and byok_cfg.last_test_ok is not True:
                    reason = "BYOK_TEST_REQUIRED"
                    message = "اتصال ارائه‌دهنده اختصاصی هنوز با موفقیت تست نشده است"
                    suggestions = ["دکمه «تست اتصال» را در تنظیمات ارائه‌دهنده بزنید"]
                elif byok_cfg and not parse_models_json(byok_cfg.models_json):
                    reason = "BYOK_NO_MODELS"
                    message = "هیچ مدلی برای ارائه‌دهنده اختصاصی تعریف نشده است"
                else:
                    reason = "BYOK_NOT_CONFIGURED"
                    message = "ارائه‌دهنده اختصاصی هنوز پیکربندی نشده است"
                return {
                    "can_use": False,
                    "reason": reason,
                    "details": {
                        "message": message,
                        "suggestions": suggestions,
                        "provider_settings_path": "settings/ai-provider",
                    },
                }
        else:
            # بررسی تنظیمات AI پلتفرم
            if not self.config or not self.config.is_active:
                return {
                    "can_use": False,
                    "reason": "AI_NOT_CONFIGURED",
                    "details": {
                        "message": "تنظیمات AI فعال نیست",
                        "suggestions": ["لطفاً با مدیر سیستم تماس بگیرید"]
                    }
                }
        if not self.subscription.is_active:
            return {
                "can_use": False,
                "reason": "SUBSCRIPTION_INACTIVE",
                "details": {
                    "message": "اشتراک غیرفعال است",
                    "subscription": {
                        "plan_name": self.subscription.plan.name if self.subscription.plan else "نامشخص",
                        "expired_at": self.subscription.expires_at.isoformat() if self.subscription.expires_at else None
                    },
                    "suggestions": [
                        "اشتراک شما منقضی شده است",
                        "لطفاً اشتراک خود را تمدید کنید"
                    ]
                }
            }
        
        plan = self.subscription.plan
        if not plan:
            return {
                "can_use": False,
                "reason": "PLAN_NOT_FOUND",
                "details": {
                    "message": "پلن اشتراک یافت نشد",
                    "suggestions": ["لطفاً با پشتیبانی تماس بگیرید"]
                }
            }
        
        from app.services.ai.ai_quota_helpers import (
            quota_allows_tokens,
            subscription_quota_info,
        )

        quota = subscription_quota_info(self.subscription)
        subscription_info = {
            "plan_name": plan.name,
            "plan_type": plan.plan_type,
            "tokens_used": quota["tokens_used"],
            "tokens_limit": quota["tokens_limit"],
            "tokens_remaining": quota["tokens_remaining"],
            "usage_percentage": quota["usage_percentage"],
            "is_unlimited": not quota["has_token_cap"],
        }
        
        suggestions = []
        wallet_info = None
        
        # بررسی بر اساس نوع پلن
        if plan.plan_type == "byok":
            # هزینه LLM با مالک کسب‌وکار؛ بدون سهمیه/کیف پول پلتفرم
            suggestions.append("هزینه مصرف مدل توسط ارائه‌دهنده شما محاسبه می‌شود")
        
        elif plan.plan_type == "free":
            if quota["has_token_cap"] and not quota_allows_tokens(
                quota["tokens_used"], self.subscription.tokens_limit, estimated_tokens
            ):
                remaining = quota["tokens_remaining"] or 0
                cap = quota["tokens_limit"] or 0
                return {
                    "can_use": False,
                    "reason": "QUOTA_EXCEEDED",
                    "details": {
                        "message": f"سهمیه رایگان تمام شده است. باقیمانده: {remaining} توکن",
                        "subscription": subscription_info,
                        "suggestions": [
                            f"شما {quota['tokens_used']:,} از {cap:,} توکن رایگان خود را استفاده کرده‌اید",
                            "برای استفاده بیشتر، به پلن پولی ارتقا دهید"
                        ]
                    }
                }
            
            if quota["has_token_cap"] and quota["tokens_remaining"] is not None:
                cap = quota["tokens_limit"] or 0
                if cap > 0 and quota["tokens_remaining"] < cap * 0.2:
                    suggestions.append(f"⚠️ تنها {quota['tokens_remaining']:,} توکن رایگان باقی مانده است")
                    suggestions.append("پیشنهاد می‌کنیم به پلن بالاتر ارتقا دهید")
        
        elif plan.plan_type == "subscription":
            if quota["has_token_cap"] and not quota_allows_tokens(
                quota["tokens_used"], self.subscription.tokens_limit, estimated_tokens
            ):
                remaining = quota["tokens_remaining"] or 0
                cap = quota["tokens_limit"] or 0
                return {
                    "can_use": False,
                    "reason": "QUOTA_EXCEEDED",
                    "details": {
                        "message": f"سهمیه اشتراک تمام شده است. باقیمانده: {remaining:,} توکن",
                        "subscription": subscription_info,
                        "suggestions": [
                            f"شما {quota['tokens_used']:,} از {cap:,} توکن ماهانه خود را استفاده کرده‌اید",
                            "منتظر تمدید ماهانه بمانید یا به پلن بالاتر ارتقا دهید"
                        ]
                    }
                }
            
            if quota["has_token_cap"] and quota["tokens_remaining"] is not None:
                cap = quota["tokens_limit"] or 0
                if cap > 0 and quota["tokens_remaining"] < cap * 0.2:
                    suggestions.append(f"⚠️ {quota['tokens_remaining']:,} توکن از سهمیه ماهانه شما باقی مانده")
        
        elif plan.plan_type in ["pay_as_go", "hybrid"]:
            # بررسی الزامی بودن business_id چون کیف پول‌ها business-specific هستند
            if not self.business_id:
                return {
                    "can_use": False,
                    "reason": "BUSINESS_REQUIRED",
                    "details": {
                        "message": "برای استفاده از پلن پرداختی، انتخاب کسب‌وکار الزامی است",
                        "suggestions": [
                            "لطفاً ابتدا یک کسب‌وکار را انتخاب کنید",
                            "کیف پول‌ها مختص به هر کسب‌وکار هستند"
                        ]
                    }
                }
            
            from app.services.ai.ai_model_service import (
                estimate_auto_cost_range,
                estimate_cost_for_tokens,
                is_auto_model_code,
            )

            if plan.plan_type == "hybrid" and quota["has_token_cap"]:
                remaining = quota["tokens_remaining"] or 0
                billable_tokens = max(0, estimated_tokens - remaining)
            else:
                billable_tokens = estimated_tokens
            if billable_tokens > 0:
                if is_auto_model_code(requested_model):
                    cost_range = estimate_auto_cost_range(plan, self.db, billable_tokens)
                    estimated_cost = Decimal(str(cost_range["max"]))
                else:
                    estimated_cost = estimate_cost_for_tokens(
                        plan, effective_model, billable_tokens
                    )
            else:
                estimated_cost = Decimal(0)
            
            from app.services.wallet_service import get_wallet_overview
            try:
                wallet = get_wallet_overview(self.db, self.business_id)
                available_balance = Decimal(str(wallet.get("available_balance", 0)))
                
                wallet_info = {
                    "balance": float(available_balance),
                    "estimated_cost": float(estimated_cost),
                    "sufficient": available_balance >= estimated_cost
                }
                
                cur_label = (
                    wallet.get("base_currency_symbol")
                    or wallet.get("base_currency_title")
                    or wallet.get("base_currency_code")
                    or ""
                ).strip()
                cur_suffix = f" {cur_label}" if cur_label else ""

                if billable_tokens > 0 and available_balance < estimated_cost:
                    return {
                        "can_use": False,
                        "reason": "INSUFFICIENT_FUNDS",
                        "details": {
                            "message": "موجودی کیف پول کافی نیست",
                            "wallet": wallet_info,
                            "subscription": subscription_info,
                            "suggestions": [
                                f"موجودی فعلی: {available_balance:,.0f}{cur_suffix}",
                                f"هزینه تخمینی: {estimated_cost:,.0f}{cur_suffix}",
                                "لطفاً کیف پول خود را شارژ کنید"
                            ]
                        }
                    }
                
                if billable_tokens > 0 and available_balance < estimated_cost * 10:
                    suggestions.append(f"💰 موجودی کیف پول: {available_balance:,.0f}{cur_suffix}")
                    suggestions.append("پیشنهاد می‌کنیم کیف پول خود را شارژ کنید")
                
            except Exception as e:
                logger.warning(f"Error checking wallet balance: {e}")
                return {
                    "can_use": False,
                    "reason": "WALLET_CHECK_FAILED",
                    "details": {
                        "message": "خطا در بررسی موجودی کیف پول",
                        "subscription": subscription_info,
                        "suggestions": [
                            "لطفاً چند لحظه دیگر دوباره تلاش کنید",
                            "در صورت تکرار، با پشتیبانی تماس بگیرید",
                        ],
                    },
                }
        
        # همه چیز OK است
        from app.services.ai.ai_model_service import (
            _format_pricing_hint,
            estimate_auto_cost_range,
            estimate_cost_for_tokens,
            get_model_pricing_rates,
            is_auto_model_code,
            model_supports_tools,
        )

        requested_model = self.get_requested_model_code()
        if self._is_byok_subscription():
            from app.services.ai.business_ai_provider_service import parse_models_json

            byok_cfg = self._get_byok_config()
            model_tools = True
            if byok_cfg:
                for m in parse_models_json(byok_cfg.models_json):
                    if m["code"] == effective_model:
                        model_tools = bool(m.get("supports_tools", True))
                        break
            fce = bool(byok_cfg and byok_cfg.function_calling_enabled and model_tools)
        else:
            fce = self._provider_supports_tools() and model_supports_tools(
                self.db, effective_model, self.config
            )
        in_per_1k = out_per_1k = est_cost = 0.0
        model_pricing: Dict[str, Any] = {}
        if plan and plan.plan_type == "byok":
            model_pricing = {
                "estimated_cost": 0.0,
                "price_per_1k_input_tokens": 0.0,
                "price_per_1k_output_tokens": 0.0,
                "pricing_hint": "هزینه توسط ارائه‌دهنده شما محاسبه می‌شود",
            }
        elif plan:
            if is_auto_model_code(requested_model):
                cost_range = estimate_auto_cost_range(plan, self.db, estimated_tokens)
                est_cost = float(cost_range["max"])
                model_pricing = {
                    "estimated_cost": est_cost,
                    "estimated_cost_min": cost_range["min"],
                    "estimated_cost_max": cost_range["max"],
                    "likely_model": cost_range.get("likely_model"),
                    "pricing_hint": (
                        f"از {cost_range['min']:,.0f} تا {cost_range['max']:,.0f} "
                        f"(بسته به پیچیدگی سوال)"
                    ),
                }
            else:
                in_p, out_p = get_model_pricing_rates(plan, effective_model)
                in_per_1k = float(in_p * 1000)
                out_per_1k = float(out_p * 1000)
                est_cost = float(estimate_cost_for_tokens(plan, effective_model, estimated_tokens))
                model_pricing = {
                    "estimated_cost": est_cost,
                    "price_per_1k_input_tokens": in_per_1k,
                    "price_per_1k_output_tokens": out_per_1k,
                    "pricing_hint": _format_pricing_hint(in_per_1k, out_per_1k, est_cost),
                }
        return {
            "can_use": True,
            "reason": None,
            "details": {
                "subscription": subscription_info,
                "wallet": wallet_info if plan.plan_type in ["pay_as_go", "hybrid"] else None,
                "function_calling_enabled": fce,
                "model": effective_model,
                "requested_model": requested_model,
                "resolved_model": effective_model if is_auto_model_code(requested_model) else None,
                "model_pricing": model_pricing,
                "suggestions": suggestions
            }
        }

    def ensure_availability_or_raise(
        self,
        estimated_tokens: int = 1000,
        model: Optional[str] = None,
        user_query: Optional[str] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        """پیش‌چک اجباری؛ در صورت عدم امکان استفاده، ApiError می‌اندازد."""
        availability = self.check_availability(
            estimated_tokens=estimated_tokens,
            model=model,
            user_query=user_query,
            history_messages=history_messages,
        )
        if availability.get("can_use"):
            return availability
        details = availability.get("details") or {}
        reason = availability.get("reason") or "AI_UNAVAILABLE"
        message = details.get("message") or "امکان استفاده از هوش مصنوعی وجود ندارد"
        raise ApiError(
            reason,
            message,
            http_status=400,
            details=details,
        )

    
    
    @staticmethod
    def _last_user_query(messages: List[Dict[str, Any]]) -> Optional[str]:
        for m in reversed(messages):
            if m.get("role") == "user":
                content = m.get("content")
                if isinstance(content, str) and content.strip():
                    return content.strip()
        return None

    def _resolve_chat_language(
        self,
        business_id: Optional[int] = None,
        user_query: Optional[str] = None,
    ) -> str:
        from app.services.ai.ai_language_prompt import resolve_effective_chat_language

        return resolve_effective_chat_language(
            ctx_language=self.ctx.language,
            preferred_language=None,
            user_message=user_query,
        )

    def _build_execution_prompt_block(
        self,
        execution_mode: Optional[str],
        business_id: Optional[int] = None,
        user_query: Optional[str] = None,
    ) -> str:
        from app.services.ai.ai_language_prompt import build_language_context_prompt_block

        language_block = build_language_context_prompt_block(
            self._resolve_chat_language(business_id, user_query=user_query)
        )
        mode_block = execution_mode_prompt_block(execution_mode)
        from app.services.ai.ai_memory_compiler import IDENTITY_TOOL_POLICY

        parts = [p for p in (language_block, mode_block, IDENTITY_TOOL_POLICY) if p]
        return "\n\n".join(parts)

    def get_system_prompt(
        self,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        user_query: Optional[str] = None,
        execution_mode: Optional[str] = None,
    ) -> StructuredSystemPrompt:
        """دریافت system prompt ساختاریافته با business_id، حافظه، پیوست‌ها و دانشنامه"""
        role = self._resolve_prompt_role()
        
        # دریافت prompt پایه
        base_prompt = with_untrusted_policy(
            get_prompt(
                db=self.db,
                role=role,
                user_id=self.ctx.get_user_id(),
            )
        )
        
        # اضافه کردن business_id به prompt (اگر موجود باشد)
        business_id = session_business_id or self.business_id
        if business_id:
            business_info = f"\n\nکسب‌وکار فعلی: شناسه {business_id}"
            business_info += "\nنکته مهم: شما در حال کار با این کسب‌وکار هستید و نیازی به پرسیدن شناسه کسب‌وکار ندارید."
            business_info += " تمام function calls به صورت خودکار با شناسه کسب‌وکار فعلی انجام می‌شوند."

            bid = int(business_id)

            def _load_insights() -> str:
                try:
                    from app.services.ai.ai_insight_service import (
                        get_business_insights_cached,
                        format_insights_for_prompt,
                    )

                    insights = get_business_insights_cached(self.db, bid, self.ctx)
                    uid = self.ctx.get_user_id()
                    return format_insights_for_prompt(
                        insights,
                        db=self.db,
                        business_id=bid,
                        user_id=uid,
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI insights for prompt: %s", exc)
                    safe_db_rollback(self.db)
                    return ""

            def _load_memory() -> tuple[str, str]:
                try:
                    from app.services.ai.ai_memory_service import format_memory_prompt_parts

                    return format_memory_prompt_parts(
                        self.db,
                        bid,
                        self.ctx.get_user_id(),
                        user_query=user_query,
                        display_name=self.ctx.get_user_name(),
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI memory for prompt: %s", exc)
                    safe_db_rollback(self.db)
                    return "", ""

            def _load_attachments() -> str:
                try:
                    from app.services.ai.ai_attachment_service import (
                        format_attachments_for_prompt,
                    )

                    return format_attachments_for_prompt(self.db, session_id)
                except Exception as exc:
                    logger.warning("Failed to load AI attachments for prompt: %s", exc)
                    safe_db_rollback(self.db)
                    return ""

            def _load_knowledge() -> str:
                try:
                    from app.services.ai.ai_knowledge_service import format_knowledge_for_prompt

                    return format_knowledge_for_prompt(self.db, bid, user_query or "")
                except Exception as exc:
                    logger.warning("Failed to load AI knowledge for prompt: %s", exc)
                    safe_db_rollback(self.db)
                    return ""

            def _load_connectors() -> str:
                try:
                    from app.services.ai.ai_connector_service import format_connectors_for_prompt

                    return format_connectors_for_prompt(self.db, bid)
                except Exception as exc:
                    logger.warning("Failed to load AI connectors for prompt: %s", exc)
                    safe_db_rollback(self.db)
                    return ""

            def _load_skills() -> str:
                try:
                    from app.services.ai.ai_skill_runtime import get_runtime_skill_context

                    ctx_data = get_runtime_skill_context(
                        self.db, bid, user_query or ""
                    )
                    return str(ctx_data.get("metadata_prompt") or "") + str(
                        ctx_data.get("activated_prompt") or ""
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI skills for prompt: %s", exc)
                    safe_db_rollback(self.db)
                    return ""

            loaders: List[tuple[str, Any]] = [
                ("insights", _load_insights),
                ("memory", _load_memory),
                ("connectors", _load_connectors),
                ("skills", _load_skills),
            ]
            if session_id:
                loaders.append(("attachments", _load_attachments))
            if user_query and query_needs_knowledge(user_query):
                loaders.append(("knowledge", _load_knowledge))

            todos_text, plan_block = self._session_todo_prompt_extras(session_id, user_query)

            from app.services.ai.ai_calendar_prompt import (
                build_calendar_context_prompt_block,
                build_datetime_now_prompt_block,
            )

            calendar_block = build_calendar_context_prompt_block(
                self.ctx.get_calendar_type(),
                business_id=int(bid),
            )
            datetime_block = build_datetime_now_prompt_block(
                self.ctx.get_calendar_type(),
                business_id=int(bid),
            )

            parts: Dict[str, str] = {}
            identity_anchor = ""
            futures = [_executor.submit(fn) for _, fn in loaders]
            for (key, _), fut in zip(loaders, futures):
                try:
                    result = fut.result()
                except Exception as exc:
                    logger.warning("Prompt loader %s failed: %s", key, exc)
                    result = ""
                if key == "memory":
                    memory_block, identity_anchor = _unpack_memory_loader(result)
                    parts[key] = memory_block
                else:
                    parts[key] = result or ""

            semi, dynamic, insights_text = split_runtime_prompt_parts(
                {
                    "datetime": datetime_block,
                    "memory": parts.get("memory", ""),
                    "insights": parts.get("insights", ""),
                    "knowledge": parts.get("knowledge", ""),
                    "skills": parts.get("skills", ""),
                    "connectors": parts.get("connectors", ""),
                    "attachments": parts.get("attachments", ""),
                    "todos": todos_text,
                }
            )
            return compose_structured_system_prompt(
                static_core=base_prompt,
                business_anchor=business_info + identity_anchor + calendar_block,
                execution_block=self._build_execution_prompt_block(
                    execution_mode, business_id=bid, user_query=user_query
                ),
                plan_block=plan_block,
                runtime_sections=dynamic,
                semi_static_sections=semi,
                insights_section=insights_text,
                role=role.value,
                business_id=bid,
            )

        from app.services.ai.ai_calendar_prompt import (
            build_calendar_context_prompt_block,
            build_datetime_now_prompt_block,
        )

        cal_type = self.ctx.get_calendar_type()
        datetime_block = build_datetime_now_prompt_block(cal_type)

        return compose_structured_system_prompt(
            static_core=base_prompt,
            business_anchor=build_calendar_context_prompt_block(cal_type),
            execution_block=self._build_execution_prompt_block(
                execution_mode, user_query=user_query
            ),
            runtime_sections=(datetime_block,) if datetime_block else (),
            role=role.value,
            business_id=None,
        )

    async def build_system_prompt_stream(
        self,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        user_query: Optional[str] = None,
        execution_mode: Optional[str] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """ساخت system prompt — هر مرحله ابتدا trace فعال، سپس پس از اتمام trace انجام‌شده."""
        loop = asyncio.get_running_loop()

        if self.ctx.is_superadmin():
            role = PromptRole.ADMIN
        elif self.ctx.can_access_support_operator():
            role = PromptRole.OPERATOR
        else:
            role = PromptRole.USER
        role_value = role.value

        yield context_trace("loading_prompt", "active")
        await asyncio.sleep(0)
        base_prompt = with_untrusted_policy(
            await loop.run_in_executor(
                _executor,
                lambda: get_prompt(
                    db=self.db,
                    role=role,
                    user_id=self.ctx.get_user_id(),
                ),
            )
        )
        yield context_trace("loading_prompt", "done")
        await asyncio.sleep(0)

        business_id = session_business_id or self.business_id
        if not business_id:
            from app.services.ai.ai_calendar_prompt import (
                build_calendar_context_prompt_block,
                build_datetime_now_prompt_block,
            )

            cal_type = self.ctx.get_calendar_type()
            structured = compose_structured_system_prompt(
                static_core=base_prompt,
                business_anchor=build_calendar_context_prompt_block(cal_type),
                execution_block=self._build_execution_prompt_block(
                    execution_mode, user_query=user_query
                ),
                runtime_sections=(
                    build_datetime_now_prompt_block(cal_type),
                ),
                role=role_value,
                business_id=None,
            )
            yield {
                "event": "prompt_ready",
                "prompt": structured.full_text(),
                "structured_prompt": structured,
            }
            return

        business_info = (
            f"\n\nکسب‌وکار فعلی: شناسه {business_id}"
            "\nنکته مهم: شما در حال کار با این کسب‌وکار هستید و نیازی به پرسیدن شناسه کسب‌وکار ندارید."
            " تمام function calls به صورت خودکار با شناسه کسب‌وکار فعلی انجام می‌شوند."
        )

        bid = int(business_id)

        def _load_insights() -> str:
            from adapters.db.session import get_db_session

            with get_db_session() as loader_db:
                try:
                    from app.services.ai.ai_insight_service import (
                        get_business_insights_cached,
                        format_insights_for_prompt,
                    )

                    insights = get_business_insights_cached(loader_db, bid, self.ctx)
                    uid = self.ctx.get_user_id()
                    return format_insights_for_prompt(
                        insights,
                        db=loader_db,
                        business_id=bid,
                        user_id=uid,
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI insights for prompt: %s", exc)
                    safe_db_rollback(loader_db)
                    return ""

        def _load_memory() -> tuple[str, str]:
            from adapters.db.session import get_db_session

            with get_db_session() as loader_db:
                try:
                    from app.services.ai.ai_memory_service import format_memory_prompt_parts

                    return format_memory_prompt_parts(
                        loader_db,
                        bid,
                        self.ctx.get_user_id(),
                        user_query=user_query,
                        display_name=self.ctx.get_user_name(),
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI memory for prompt: %s", exc)
                    safe_db_rollback(loader_db)
                    return "", ""

        def _load_attachments() -> str:
            from adapters.db.session import get_db_session

            with get_db_session() as loader_db:
                try:
                    from app.services.ai.ai_attachment_service import (
                        format_attachments_for_prompt,
                    )

                    return format_attachments_for_prompt(loader_db, session_id)
                except Exception as exc:
                    logger.warning("Failed to load AI attachments for prompt: %s", exc)
                    safe_db_rollback(loader_db)
                    return ""

        def _load_knowledge() -> str:
            from adapters.db.session import get_db_session

            with get_db_session() as loader_db:
                try:
                    from app.services.ai.ai_knowledge_service import format_knowledge_for_prompt

                    return format_knowledge_for_prompt(loader_db, bid, user_query or "")
                except Exception as exc:
                    logger.warning("Failed to load AI knowledge for prompt: %s", exc)
                    safe_db_rollback(loader_db)
                    return ""

        def _load_connectors() -> str:
            from adapters.db.session import get_db_session

            with get_db_session() as loader_db:
                try:
                    from app.services.ai.ai_connector_service import format_connectors_for_prompt

                    return format_connectors_for_prompt(loader_db, bid)
                except Exception as exc:
                    logger.warning("Failed to load AI connectors for prompt: %s", exc)
                    safe_db_rollback(loader_db)
                    return ""

        def _load_skills() -> str:
            from adapters.db.session import get_db_session

            with get_db_session() as loader_db:
                try:
                    from app.services.ai.ai_skill_runtime import get_runtime_skill_context

                    ctx_data = get_runtime_skill_context(
                        loader_db, bid, user_query or ""
                    )
                    return str(ctx_data.get("metadata_prompt") or "") + str(
                        ctx_data.get("activated_prompt") or ""
                    )
                except Exception as exc:
                    logger.warning("Failed to load AI skills for prompt: %s", exc)
                    safe_db_rollback(loader_db)
                    return ""

        def _load_session_todos() -> str:
            if not session_id:
                return ""
            from adapters.db.session import get_db_session

            with get_db_session() as loader_db:
                try:
                    from app.services.ai.ai_session_todo_service import (
                        format_session_todos_for_prompt,
                    )

                    return format_session_todos_for_prompt(loader_db, int(session_id))
                except Exception as exc:
                    logger.warning("Failed to load session todos for prompt: %s", exc)
                    safe_db_rollback(loader_db)
                    return ""

        parallel_loaders: List[tuple[str, Any]] = [
            ("loading_insights", _load_insights),
            ("loading_memory", _load_memory),
            ("loading_connectors", _load_connectors),
            ("loading_skills", _load_skills),
        ]
        if session_id:
            parallel_loaders.append(("loading_attachments", _load_attachments))
            parallel_loaders.append(("loading_session_todos", _load_session_todos))
        if user_query and query_needs_knowledge(user_query):
            parallel_loaders.append(("loading_knowledge", _load_knowledge))

        async def _run_loader(step_key: str, loader_fn) -> tuple[str, str]:
            try:
                timeout = (
                    KNOWLEDGE_LOAD_TIMEOUT_SEC
                    if step_key == "loading_knowledge"
                    else PROMPT_LOADER_TIMEOUT_SEC
                )
                text = await asyncio.wait_for(
                    loop.run_in_executor(_executor, loader_fn),
                    timeout=timeout,
                )
                if step_key == "loading_memory":
                    return step_key, text if text is not None else ("", "")
                return step_key, text or ""
            except asyncio.TimeoutError:
                logger.info("Prompt loader %s timed out, continuing", step_key)
                return step_key, ""
            except Exception as exc:
                logger.warning("Prompt loader %s failed: %s", step_key, exc)
                return step_key, ""

        for step_key, _ in parallel_loaders:
            yield context_trace(step_key, "active")
        await asyncio.sleep(0)

        tasks = {
            asyncio.create_task(_run_loader(step_key, loader_fn)): step_key
            for step_key, loader_fn in parallel_loaders
        }
        parts: Dict[str, str] = {}
        identity_anchor = ""
        pending = set(tasks.keys())
        while pending:
            done_set, pending = await asyncio.wait(
                pending, return_when=asyncio.FIRST_COMPLETED
            )
            for task in done_set:
                step_key, text = await task
                if step_key == "loading_memory":
                    memory_block, identity_anchor = _unpack_memory_loader(text)
                    parts[step_key] = memory_block
                else:
                    parts[step_key] = text or ""
                yield context_trace(step_key, "done")
                await asyncio.sleep(0)

        todos_text, plan_block = self._session_todo_prompt_extras(session_id, user_query)

        from app.services.ai.ai_calendar_prompt import (
            build_calendar_context_prompt_block,
            build_datetime_now_prompt_block,
        )

        calendar_block = build_calendar_context_prompt_block(
            self.ctx.get_calendar_type(),
            business_id=int(bid),
        )
        datetime_block = build_datetime_now_prompt_block(
            self.ctx.get_calendar_type(),
            business_id=int(bid),
        )

        semi, dynamic, insights_text = split_runtime_prompt_parts(
            {
                "datetime": datetime_block,
                "memory": parts.get("loading_memory", ""),
                "insights": parts.get("loading_insights", ""),
                "knowledge": parts.get("loading_knowledge", ""),
                "skills": parts.get("loading_skills", ""),
                "connectors": parts.get("loading_connectors", ""),
                "attachments": parts.get("loading_attachments", ""),
                "todos": parts.get("loading_session_todos", "") or todos_text,
            }
        )
        structured = compose_structured_system_prompt(
            static_core=base_prompt,
            business_anchor=business_info + identity_anchor + calendar_block,
            execution_block=self._build_execution_prompt_block(
                execution_mode, business_id=bid, user_query=user_query
            ),
            plan_block=plan_block,
            runtime_sections=dynamic,
            semi_static_sections=semi,
            insights_section=insights_text,
            role=role_value,
            business_id=bid,
        )
        yield {
            "event": "prompt_ready",
            "prompt": structured.full_text(),
            "structured_prompt": structured,
        }
    
    @staticmethod
    def _forced_write_tool_names(
        approve_writes: bool,
        approved_write_calls: Optional[List[Dict[str, Any]]],
    ) -> Set[str]:
        """نام ابزارهای نوشتنیِ تأییدشده که باید در لیست ابزارها بمانند.

        هنگام تأیید عملیات، متن پیام کاربر فاقد کلیدواژهٔ نوشتنی است و
        intent-router ابزار نوشتنی را حذف می‌کند؛ این مجموعه تضمین می‌کند
        همان ابزار تأییدشده در دسترس مدل باقی بماند.
        """
        if not approve_writes:
            return set()
        forced = {
            str(call.get("function"))
            for call in (approved_write_calls or [])
            if call.get("function")
        }
        if forced:
            return forced
        # fallback: اگر به هر دلیل لیست تأییدشده خالی بود، همهٔ ابزارهای نوشتنی
        from app.services.ai.ai_tool_intent import _WRITE_TOOLS

        return set(_WRITE_TOOLS)

    def _session_todo_prompt_extras(
        self,
        session_id: Optional[int],
        user_query: Optional[str],
    ) -> tuple[str, str]:
        """(متن todoهای باز، راهنمای ابزار برنامه)"""
        from app.services.ai.ai_session_todo_service import (
            format_session_todos_for_prompt,
            session_has_open_todos,
            session_plan_tools_prompt_block,
            should_expose_session_plan_tools,
        )
        from app.services.ai.ai_tool_intent import estimate_query_complexity

        todos_text = ""
        plan_block = ""
        has_open = False
        if session_id:
            try:
                todos_text = format_session_todos_for_prompt(self.db, int(session_id))
                has_open = session_has_open_todos(self.db, int(session_id))
            except Exception as exc:
                logger.warning("Failed to load session todos for prompt: %s", exc)
                safe_db_rollback(self.db)
        if should_expose_session_plan_tools(
            user_query,
            session_id=session_id,
            db=self.db,
        ):
            require_first = (
                estimate_query_complexity(user_query) == "complex" and not has_open
            )
            plan_block = session_plan_tools_prompt_block(require_first=require_first)
        return todos_text, plan_block

    def _session_todo_goal_state(self, session_id: Optional[int]):
        if not session_id:
            return None
        try:
            from app.services.ai.ai_session_todo_service import get_session_todo_goal_state

            return get_session_todo_goal_state(self.db, int(session_id))
        except Exception as exc:
            logger.warning("Failed to load session todo goal state: %s", exc)
            safe_db_rollback(self.db)
            return None

    def get_available_functions(
        self,
        category: Optional[str] = None,
        session_business_id: Optional[int] = None,
        user_query: Optional[str] = None,
        force_tool_names: Optional[AbstractSet[str]] = None,
        execution_mode: Optional[str] = None,
        session_id: Optional[int] = None,
        history_messages: Optional[List[Dict[str, Any]]] = None,
    ) -> List[Dict[str, Any]]:
        """دریافت function های قابل استفاده بر اساس نقش کاربر و intent سوال.

        force_tool_names: نام ابزارهایی که باید حتماً در لیست بمانند حتی اگر
        intent متن کاربر آن‌ها را انتخاب نکند (مثلاً ابزار نوشتنیِ تأییدشده
        هنگام اجرای مرحلهٔ approve). بدون این، پیام تأیید کاربر (که فاقد
        کلیدواژهٔ نوشتنی است) باعث حذف ابزار از لیست و عدم اجرای عملیات می‌شود.
        """
        effective_business_id = session_business_id or self.business_id
        context = {
            "db": self.db,
            "user_context": self.ctx,
            "business_id": effective_business_id,
            "session_business_id": session_business_id,
        }
        definitions = registry.get_function_definitions(
            context, filter_by_category=category
        )
        from app.services.ai.ai_session_todo_service import (
            SESSION_TODO_TOOL_NAMES,
            should_expose_session_plan_tools,
        )
        from app.services.ai.ai_subagent import (
            SUBAGENT_TOOL_NAMES,
            should_expose_subagent_tools,
        )

        expose_plan_tools = should_expose_session_plan_tools(
            user_query,
            session_id=session_id,
            db=self.db,
        )
        expose_subagents = should_expose_subagent_tools(
            user_query,
            is_subagent=getattr(self, "_subagent_depth", 0) > 0,
        )
        if user_query and effective_business_id:
            all_names = {
                (d.get("function") or {}).get("name")
                for d in definitions
                if (d.get("function") or {}).get("name")
            }
            forced = set(force_tool_names or ()) & all_names
            plan_prefer = (
                set(SESSION_TODO_TOOL_NAMES) & all_names if expose_plan_tools else set()
            )
            subagent_prefer = (
                set(SUBAGENT_TOOL_NAMES) & all_names if expose_subagents else set()
            )
            skill_tools: Set[str] = set()
            try:
                from app.services.ai.ai_skill_runtime import (
                    collect_allowed_tool_names,
                    get_runtime_skill_context,
                )

                skill_ctx = get_runtime_skill_context(
                    self.db, int(effective_business_id), user_query
                )
                activated = skill_ctx.get("activated") or []
                self._turn_activated_skills = [
                    {
                        "slug": getattr(item, "skill_slug", None),
                        "description": (getattr(item, "description", None) or "")[:180],
                    }
                    for item in activated
                    if getattr(item, "skill_slug", None)
                ]
                collected = collect_allowed_tool_names(activated, all_names)
                if collected:
                    skill_tools = set(collected)
            except Exception as exc:
                logger.warning("AI skill tool filter failed: %s", exc)
            hist = history_messages
            if hist is None:
                hist = (self._routing_context or {}).get("history_messages")
            allowed = merge_tool_allowlists(
                select_tool_names(
                    all_names,
                    user_query,
                    history_messages=hist if isinstance(hist, list) else None,
                    prefer_names=skill_tools | plan_prefer | subagent_prefer,
                ),
                skill_names=skill_tools,
                forced_names=forced | plan_prefer | subagent_prefer,
            )
            definitions = filter_function_definitions(definitions, allowed)
        forced_names = set(force_tool_names or ())
        if not expose_plan_tools and not (forced_names & SESSION_TODO_TOOL_NAMES):
            definitions = [
                d
                for d in definitions
                if (d.get("function") or {}).get("name") not in SESSION_TODO_TOOL_NAMES
            ]
        if not expose_subagents and not (forced_names & SUBAGENT_TOOL_NAMES):
            definitions = [
                d
                for d in definitions
                if (d.get("function") or {}).get("name") not in SUBAGENT_TOOL_NAMES
            ]
        if not exposes_write_tools(resolve_execution_mode(execution_mode)):
            definitions = [
                d
                for d in definitions
                if is_readonly_function(
                    (d.get("function") or {}).get("name") or "", registry
                )
                or is_agent_internal_function(
                    (d.get("function") or {}).get("name") or "", registry
                )
            ]
        return definitions
    
    
    
    
    
    
    
    

    @staticmethod
    def _validate_messages(messages: List[Dict[str, Any]]) -> None:
        """اعتبارسنجی پیام‌ها — پشتیبانی از tool و assistant با tool_calls."""
        if not messages:
            raise ApiError("MESSAGES_REQUIRED", "حداقل یک پیام الزامی است", http_status=400)
        if not isinstance(messages, list):
            raise ApiError("INVALID_MESSAGES", "messages باید یک لیست باشد", http_status=400)

        for idx, msg in enumerate(messages):
            if not isinstance(msg, dict):
                raise ApiError(
                    "INVALID_MESSAGE_FORMAT",
                    f"پیام {idx} باید یک dictionary باشد",
                    http_status=400,
                )
            if "role" not in msg:
                raise ApiError(
                    "INVALID_MESSAGE_FORMAT",
                    f"پیام {idx} باید role داشته باشد",
                    http_status=400,
                )
            role = msg.get("role")
            if role == "tool":
                if not msg.get("tool_call_id"):
                    raise ApiError(
                        "INVALID_MESSAGE_FORMAT",
                        f"پیام tool {idx} باید tool_call_id داشته باشد",
                        http_status=400,
                    )
                continue
            if role == "assistant" and msg.get("tool_calls"):
                continue
            if "content" not in msg:
                raise ApiError(
                    "INVALID_MESSAGE_FORMAT",
                    f"پیام {idx} باید content داشته باشد",
                    http_status=400,
                )
    
    async def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        temperature_override: Optional[float] = None,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        max_iterations: int = MAX_AGENT_ITERATIONS,
        approve_writes: bool = False,
        approved_write_calls: Optional[List[Dict[str, Any]]] = None,
        user_query: Optional[str] = None,
        request_model: Optional[str] = None,
        execution_mode: Optional[str] = None,
        iteration_cap: Optional[int] = None,
    ) -> Dict[str, Any]:
        """پاسخ غیر استریم — همان حلقهٔ chat_completion_stream، فقط تجمیع‌شده.

        تلگرام / CRM / تیکت / ورک‌فلو / eval از این مسیر می‌آیند تا exploration،
        Plan C، سنتز اجباری و tool_choice با چت استریم یکی باشد (STR-02).
        """
        from app.services.ai.ai_stream_aggregate import aggregate_chat_completion_stream

        return await aggregate_chat_completion_stream(
            self.chat_completion_stream(
                messages,
                tools=tools,
                use_function_calling=use_function_calling,
                max_tokens_override=max_tokens_override,
                temperature_override=temperature_override,
                session_business_id=session_business_id,
                session_id=session_id,
                approve_writes=approve_writes,
                approved_write_calls=approved_write_calls,
                max_iterations=max_iterations,
                user_query=user_query,
                request_model=request_model,
                execution_mode=execution_mode,
                iteration_cap=iteration_cap,
            )
        )

    
    def chat_completion_sync(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        temperature_override: Optional[float] = None,
        session_business_id: Optional[int] = None,
        max_iterations: int = MAX_AGENT_ITERATIONS,
        execution_mode: Optional[str] = None,
        approve_writes: bool = False,
    ) -> Dict[str, Any]:
        """
        نسخه sync برای استفاده در workflow engine
        از asyncio.run برای اجرای chat_completion استفاده می‌کند
        """
        def _run():
            return asyncio.run(
                self.chat_completion(
                    messages=messages,
                    tools=tools,
                    use_function_calling=use_function_calling,
                    max_tokens_override=max_tokens_override,
                    temperature_override=temperature_override,
                    session_business_id=session_business_id,
                    max_iterations=max_iterations,
                    execution_mode=execution_mode,
                    approve_writes=approve_writes,
                )
            )

        try:
            asyncio.get_running_loop()
            # در context async هستیم — asyncio.run تودرتو مجاز نیست؛
            # از pool مشترک ماژول استفاده می‌شود نه executor یک‌بارمصرف (ARC-05).
            return _executor.submit(_run).result()
        except RuntimeError:
            return _run()
    
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, Any]],
        tools: Optional[List[Dict[str, Any]]] = None,
        use_function_calling: bool = True,
        max_tokens_override: Optional[int] = None,
        temperature_override: Optional[float] = None,
        session_business_id: Optional[int] = None,
        session_id: Optional[int] = None,
        approve_writes: bool = False,
        approved_write_calls: Optional[List[Dict[str, Any]]] = None,
        max_iterations: int = MAX_AGENT_ITERATIONS,
        user_query: Optional[str] = None,
        exploration_mode: Optional[str] = None,
        request_model: Optional[str] = None,
        execution_mode: Optional[str] = None,
        prebuilt_system_prompt: Optional[Union[str, StructuredSystemPrompt]] = None,
        resume_from_run: Optional[Dict[str, Any]] = None,
        iteration_cap: Optional[int] = None,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """ارسال streaming با چند نوبت tool calling (مثل chat_completion).

        ویژگی‌های جدید:
         - adaptive max_iterations بر اساس پیچیدگی سوال
         - tool timing در trace events
         - planning step برای سوال‌های پیچیده
         - session caching در handle_function_calls_async
        """
        self._validate_messages(messages)
        if request_model:
            self.set_request_model(request_model)
        self._validate_request_model_if_set()
        effective_user_query = user_query or self._last_user_query(messages)
        chat_language = self._resolve_chat_language(
            session_business_id or self.business_id,
            user_query=effective_user_query,
        )
        from app.services.ai.ai_language_prompt import visible_reasoning_markdown
        _needs_tools_routing = self._routing_needs_tools(
            use_function_calling, effective_user_query, messages
        )
        self.set_routing_context(
            operation=(
                AI_OPERATION_SUBAGENT
                if getattr(self, "_subagent_depth", 0) > 0
                else AI_OPERATION_CHAT
            ),
            user_query=effective_user_query,
            history_messages=messages,
            needs_tools=_needs_tools_routing,
        )
        # وضعیت اجرا (run_id/phase) — checkpoint در جدول و function_results.
        resume_run_id = None
        if isinstance(resume_from_run, dict):
            resume_run_id = resume_from_run.get("run_id")
        agent_run = AgentRunState(
            run_id=str(resume_run_id) if resume_run_id else new_agent_run_id(),
            needs_tools=_needs_tools_routing,
            phase=(
                AGENT_RUN_PHASE_AGENT_LOOP
                if resume_run_id
                else AGENT_RUN_PHASE_GATHER_CONTEXT
            ),
        )
        yield {"event": "agent_run", **agent_run.snapshot()}
        exploration_enabled = resolve_exploration_enabled(
            exploration_mode, effective_user_query, messages
        )
        effective_execution_mode = resolve_execution_mode(execution_mode)

        # تنظیم خودکار max_iterations بر اساس پیچیدگی
        complexity = estimate_query_complexity(effective_user_query, messages)
        has_open_session_plan = False
        if session_id:
            try:
                from app.services.ai.ai_session_todo_service import session_has_open_todos

                has_open_session_plan = session_has_open_todos(self.db, int(session_id))
            except Exception:
                safe_db_rollback(self.db)
                has_open_session_plan = False
        if exploration_enabled:
            adaptive_max_iterations = EXPLORATION_COMPLEXITY_ITERATIONS.get(
                complexity, MAX_AGENT_ITERATIONS
            )
        else:
            adaptive_max_iterations = iterations_for_query(
                effective_user_query, messages
            )
        # اگر caller مقدار غیر پیش‌فرض داد، max بگیر
        if max_iterations != MAX_AGENT_ITERATIONS:
            adaptive_max_iterations = max(adaptive_max_iterations, max_iterations)
        from app.services.ai.ai_channel_policy import apply_iteration_cap

        max_iterations = apply_iteration_cap(adaptive_max_iterations, iteration_cap)

        # بودجهٔ یکپارچهٔ مراحل استدلال (نوبت + توکن + زمان + بازده نزولی)
        budget: AgentBudget = build_agent_budget(
            complexity, max_iterations=max_iterations
        )

        # سطح تلاش استدلال درون‌مدلی (در صورت پشتیبانی مدل)
        reasoning_effort = self._effective_reasoning_effort(
            complexity=complexity,
            operation=AI_OPERATION_CHAT,
            user_query=effective_user_query,
            history_messages=messages,
            needs_tools=self._routing_needs_tools(
                use_function_calling, effective_user_query, messages
            ),
        )

        observation_store: Optional[ObservationStore] = (
            ObservationStore() if exploration_enabled else None
        )
        use_llm_thought = (
            exploration_enabled
            and (exploration_mode or "").strip().lower() == EXPLORATION_MODE_EXPLORE
        )

        accumulated_function_calls: List[Dict[str, Any]] = []
        accumulated_function_results: Dict[str, Any] = {}

        if not self.config or not self.config.is_active:
            raise ApiError("AI_NOT_CONFIGURED", "تنظیمات AI فعال نیست", http_status=400)

        effective_temperature = (
            float(temperature_override)
            if temperature_override is not None
            else float(self.config.temperature)
        )

        provider = self._make_provider()
        context_compress_retried = False
        resolved_model_code = self.get_effective_model_code()
        requested_model_code = self.get_requested_model_code()

        try:
            accumulated_content = ""
            final_usage = None
            from app.services.ai.ai_usage_accumulate import empty_usage, merge_usage

            billed_usage = empty_usage()
            self._turn_usage = empty_usage()
            self._turn_activated_skills = []
            iteration = 0
            trace_steps: List[Dict[str, Any]] = []
            trace_step_counter = 0

            def _ingest_trace_event(event: Dict[str, Any]) -> Dict[str, Any]:
                record = trace_record_from_event(event)
                sid = record.get("step_id")
                if sid:
                    for i, existing in enumerate(trace_steps):
                        if existing.get("step_id") == sid:
                            trace_steps[i] = record
                            break
                    else:
                        trace_steps.append(record)
                return event

            def _emit_trace(*, step_id: Optional[str] = None, **kwargs: Any) -> Dict[str, Any]:
                nonlocal trace_step_counter
                if step_id is None:
                    trace_step_counter += 1
                    sid = str(trace_step_counter)
                else:
                    sid = step_id
                kind = kwargs.pop("kind")
                state = kwargs.pop("state", "done")
                return _ingest_trace_event(trace_step(sid, kind, state, **kwargs))

            async def _flush_subagent_sse(timeout: float = 0.0):
                from app.services.ai.ai_subagent_sse import drain_parent_subagent_events

                events = await drain_parent_subagent_events(self, timeout=timeout)
                for ev in events:
                    if ev.get("event") == "trace_step" or ev.get("kind"):
                        yield _ingest_trace_event(ev)
                    else:
                        yield ev

            def _emit_agent_budget(
                *,
                stop_reason: Optional[str] = None,
                stop_message_fa: Optional[str] = None,
            ) -> Dict[str, Any]:
                snap = budget_snapshot(
                    budget,
                    iteration=iteration,
                    reasoning_effort=reasoning_effort,
                    stop_reason=stop_reason,
                    stop_message_fa=stop_message_fa,
                )
                return {"event": "agent_budget", **snap}

            async def _emit_answer_text(text: str, *, iter_num: int):
                stripped = sanitize_assistant_content((text or "").strip())
                if not stripped:
                    return
                # پاسخ نهایی فقط در کانال content می‌رود؛ بدنهٔ کامل را در
                # trace لایهٔ answer تکرار نکن تا در پنل تحلیل دیده نشود.
                redact_final_answer_from_reasoning_trace(trace_steps, stripped)
                yield _emit_trace(
                    kind="answer",
                    state="done",
                    title_key="aiTraceComposingAnswer",
                    body_markdown=None,
                    iteration=iter_num,
                    layer="answer",
                )
                _answer_chunk_size = 48
                for offset in range(0, len(stripped), _answer_chunk_size):
                    piece = stripped[offset : offset + _answer_chunk_size]
                    yield {
                        "delta": {"content": piece},
                        "usage": None,
                        "done": False,
                    }
                    await asyncio.sleep(0)

            async def _resolve_answer_after_budget_stop(
                *,
                prefer_llm_synthesis: bool,
            ) -> Optional[str]:
                """بازیابی پاسخ وقتی بودجه/زمان تمام شده.

                اولویت: answer موجود → narrative قابل‌قبول → (اختیاری) سنتز LLM
                → پاسخ قطعی از explored/observation. هرگز پیام خالی بودجه را
                وقتی داده داریم برنگردان.
                """
                synthesized = extract_final_content_from_trace(trace_steps)
                if synthesized:
                    return synthesized
                synthesized = extract_usable_narrative_for_answer(trace_steps)
                if synthesized:
                    return synthesized
                if prefer_llm_synthesis and trace_has_unanswered_evidence(
                    trace_steps
                ):
                    agent_run.set_phase(AGENT_RUN_PHASE_SYNTHESIZE)
                    llm_answer = await _run_forced_synthesis_round()
                    if llm_answer:
                        return llm_answer
                deterministic = build_deterministic_answer_from_trace(
                    trace_steps,
                    user_query=effective_user_query,
                    budget_note=True,
                )
                return deterministic or None

            async def _run_forced_synthesis_round() -> Optional[str]:
                """نوبت اضطراری LLM بدون ابزار برای سنتز پاسخ از explored/thought.

                فقط وقتی حلقه بدون هیچ متن/answer پایان یافته اما شواهد کافی
                (explored/thought) در trace موجود است صدا زده می‌شود — به‌جای
                نمایش مستقیم markdown خام ابزارها به کاربر (Phase 1).
                """
                from app.services.ai.ai_language_prompt import (
                    build_force_synthesis_user_content,
                )

                explored_ctx = extract_explored_context_for_synthesis(trace_steps)
                if not explored_ctx:
                    return None
                # اگر زمان دیوار از قبل تمام شده، LLM را صدا نزن — معمولاً
                # timeout می‌شود و فقط تأخیر اضافه می‌کند (session 751).
                remaining = budget.remaining_wall_clock_sec()
                if remaining is not None and remaining <= 5.0:
                    logger.info(
                        "[AI Agent][session=%s] skip LLM synthesis "
                        "(wall-clock remaining=%.1fs); use deterministic",
                        session_id,
                        remaining if remaining is not None else -1,
                    )
                    return None
                synthesis_messages = list(full_messages) + [
                    {
                        "role": "user",
                        "content": build_force_synthesis_user_content(
                            chat_language,
                            explored_ctx,
                        ),
                    }
                ]
                collected = ""

                async def _consume() -> None:
                    nonlocal collected, billed_usage
                    async for syn_chunk in provider.chat_completion_stream(
                        messages=synthesis_messages,
                        model=self.get_effective_model_api_id(),
                        max_tokens=min(
                            1200,
                            max_tokens_override or self.config.max_tokens or 1200,
                        ),
                        temperature=effective_temperature,
                        tools=None,
                        reasoning_effort="low",
                        **stream_provider_extras,
                    ):
                        syn_delta = syn_chunk.get("delta", {}) or {}
                        piece = syn_delta.get("content", "")
                        if piece:
                            collected += piece
                        if syn_chunk.get("usage"):
                            billed_usage = merge_usage(
                                billed_usage, syn_chunk.get("usage")
                            )
                            budget.add_tokens(
                                (syn_chunk.get("usage") or {}).get("total_tokens")
                            )
                        if syn_chunk.get("done"):
                            break

                try:
                    await asyncio.wait_for(
                        _consume(), timeout=FORCED_SYNTHESIS_TIMEOUT_SEC
                    )
                except Exception as exc:
                    logger.warning(
                        "[AI Agent][session=%s] Forced synthesis round failed: "
                        "%s: %s",
                        session_id,
                        type(exc).__name__,
                        exc or repr(exc),
                    )
                    return None
                return collected.strip() or None

            yield status_event("thinking")
            yield _emit_trace(
                step_id="ctx_thinking",
                kind="context",
                state="active",
                title_key="aiStatusThinking",
            )

            structured_prompt: Optional[StructuredSystemPrompt] = None
            if prebuilt_system_prompt is not None:
                structured_prompt = coerce_structured_system_prompt(
                    prebuilt_system_prompt,
                    business_id=session_business_id or self.business_id,
                )
                yield _emit_trace(
                    step_id="ctx_thinking",
                    kind="context",
                    state="done",
                    title_key="aiStatusThinking",
                )
            else:
                async for build_item in self.build_system_prompt_stream(
                    session_business_id=session_business_id,
                    session_id=session_id,
                    user_query=effective_user_query,
                    execution_mode=effective_execution_mode,
                ):
                    if build_item.get("event") == "prompt_ready":
                        sp = build_item.get("structured_prompt")
                        if isinstance(sp, StructuredSystemPrompt):
                            structured_prompt = sp
                        else:
                            structured_prompt = coerce_structured_system_prompt(
                                build_item.get("prompt") or "",
                                business_id=session_business_id or self.business_id,
                            )
                        continue
                    if build_item.get("event") == "trace_step":
                        yield _ingest_trace_event(build_item)
                        await asyncio.sleep(0)
                        continue
                    yield build_item

                yield _emit_trace(
                    step_id="ctx_thinking",
                    kind="context",
                    state="done",
                    title_key="aiStatusThinking",
                )

            if structured_prompt is None:
                structured_prompt = coerce_structured_system_prompt(
                    "",
                    business_id=session_business_id or self.business_id,
                )

            full_messages, context_meta = self._prepare_llm_messages(
                structured_prompt,
                messages,
                provider,
            )
            from app.services.ai.ai_ops_metrics import log_ai_event

            log_ai_event(
                "context_usage",
                business_id=session_business_id or self.business_id,
                session_id=session_id,
                extra={
                    "static_tokens": context_meta.get("static_tokens"),
                    "semi_static_tokens": context_meta.get("semi_static_tokens"),
                    "insights_tokens": context_meta.get("insights_tokens"),
                    "runtime_tokens": context_meta.get("runtime_tokens"),
                    "estimated_tokens": context_meta.get("estimated_tokens"),
                },
            )
            yield context_usage_event_payload(context_meta)
            await asyncio.sleep(0)

            from app.services.ai.ai_channel_policy import resolve_round_tool_offer

            offer, offered_tools = resolve_round_tool_offer(
                provided_tools=tools,
                provider_allows_tools=self._use_tools_for_request(use_function_calling),
                routing_needs_tools=self._routing_needs_tools(
                    use_function_calling, effective_user_query, messages
                ),
            )
            if offer == "none":
                tools = None
                eff_tools = False
            elif offer == "keep":
                tools = offered_tools
                eff_tools = bool(tools)
            else:
                tools = self.get_available_functions(
                    session_business_id=session_business_id,
                    user_query=effective_user_query,
                    force_tool_names=self._forced_write_tool_names(
                        approve_writes, approved_write_calls
                    ),
                    execution_mode=effective_execution_mode,
                    session_id=session_id,
                    history_messages=messages,
                )
                eff_tools = bool(tools)

            if eff_tools and tools and is_tool_discovery_query(effective_user_query):
                readonly_catalog = not exposes_write_tools(effective_execution_mode)
                catalog_section = build_tool_catalog_system_section(
                    tools,
                    readonly_only=readonly_catalog,
                )
                insert_at = 0
                for idx, msg in enumerate(full_messages):
                    if msg.get("role") == "system":
                        insert_at = idx + 1
                full_messages.insert(
                    insert_at,
                    {"role": "system", "content": catalog_section},
                )

            # حتی اگر ابزار به هر دلیلی بار نشود (eff_tools/tools خالی)، وقتی خود
            # سوال داده‌محور است باید goal_tracker وجود داشته باشد تا Plan C
            # بتواند narrative بدون evidence را به‌عنوان پاسخ نهایی قفل نکند.
            needs_tools_intent = query_expects_tool_use(effective_user_query, messages)
            goal_tracker: Optional[AgentGoalTracker] = (
                AgentGoalTracker()
                if (eff_tools and tools) or needs_tools_intent
                else None
            )
            agent_run.needs_tools = bool((eff_tools and tools) or needs_tools_intent)
            yield {"event": "agent_run", **agent_run.snapshot()}

            skills_extra = self._anthropic_skills_extra(session_business_id, effective_user_query)
            stream_provider_extras = self._provider_call_extras(
                provider, skills_extra, structured_prompt
            )

            # Planning step برای سوال‌های با کافی طول
            _query_len = len(effective_user_query or "")
            if eff_tools and tools and _query_len >= PLANNING_STEP_MIN_CHARS:
                yield _emit_trace(
                    step_id="agent_plan_root",
                    kind="plan",
                    state="done",
                    title_key="aiTracePlanningAction",
                    body_markdown=f"**هدف:** {effective_user_query[:180]}" if effective_user_query else None,
                    iteration=0,
                )
                await asyncio.sleep(0)

            if exploration_enabled:
                yield _emit_trace(
                    step_id="explore_root",
                    kind="explore",
                    state="active",
                    title_key="aiTraceExploring",
                    body_markdown=effective_user_query[:240] if effective_user_query else None,
                    iteration=0,
                )
                yield {
                    "event": "status",
                    "phase": "exploring",
                    "done": False,
                }

            budget.reset_clock()
            budget_stop_reason: Optional[str] = None
            budget_stop_message: Optional[str] = None
            agent_run.set_phase(AGENT_RUN_PHASE_AGENT_LOOP)
            while True:
                async for _sa_ev in _flush_subagent_sse():
                    yield _sa_ev
                budget_status = resolve_budget_gate(budget, iteration, goal_tracker)
                if budget_status.stop:
                    budget_stop_reason = budget_status.reason
                    budget_stop_message = budget_status.message_fa
                    break
                iteration += 1
                agent_run.iteration = iteration
                max_iterations = budget.max_iterations
                function_calls = None
                tool_call_id_map: Dict[str, str] = {}
                round_text = ""
                use_tools = bool(eff_tools and tools)
                writing_status_sent = False

                yield {
                    "event": "status",
                    "phase": "agent_progress",
                    "iteration": iteration,
                    "max_iterations": max_iterations,
                    "done": False,
                }
                yield _emit_agent_budget()

                if iteration > 1:
                    yield _emit_trace(
                        step_id=f"plan_next_{iteration}",
                        kind="plan_next",
                        state="active",
                        title_key="aiTracePlanningNext",
                        iteration=iteration,
                    )

                llm_step_id = f"llm_{iteration}"
                yield _emit_trace(
                    step_id=llm_step_id,
                    kind="context",
                    state="active",
                    title_key="aiStatusThinking",
                    iteration=iteration,
                )
                narrative_step_id = f"narrative_{iteration}"
                reasoning_step_id = f"reasoning_{iteration}"
                narrative_started = False
                reasoning_started = False
                round_reasoning = ""
                last_narrative_emit = 0.0
                last_reasoning_emit = 0.0
                llm_stream_retry_count = 0

                # نوبت اول: سوال complex بدون برنامهٔ باز → create_session_plan
                # اجباری (AGT-05). در غیر این صورت اگر سوال قطعاً به ابزار نیاز
                # دارد، tool_choice=required (OpenAI و Anthropic).
                round_tool_choice: Any = None
                if use_tools:
                    from app.services.ai.ai_session_todo_service import (
                        required_plan_tool_choice,
                        tools_include_name,
                    )
                    from app.services.ai.ai_constants import PROVIDERS_WITH_FORCED_TOOLS

                    provider_type = self.get_effective_provider_type()
                    plan_choice = required_plan_tool_choice(
                        complexity=complexity,
                        iteration=iteration,
                        has_open_todos=has_open_session_plan,
                        plan_tool_available=tools_include_name(
                            tools, "create_session_plan"
                        ),
                        provider_type=provider_type,
                    )
                    if plan_choice:
                        round_tool_choice = plan_choice
                    elif (
                        iteration == 1
                        and needs_tools_intent
                        and (provider_type or "").strip().lower()
                        in PROVIDERS_WITH_FORCED_TOOLS
                    ):
                        round_tool_choice = "required"

                llm_round_complete = False
                round_usage_this_iter: Optional[Dict[str, Any]] = None
                while not llm_round_complete:
                    try:
                        stream_source = provider.chat_completion_stream(
                            messages=full_messages,
                            model=self.get_effective_model_api_id(),
                            max_tokens=max_tokens_override or self.config.max_tokens,
                            temperature=effective_temperature,
                            tools=tools if use_tools else None,
                            reasoning_effort=reasoning_effort,
                            tool_choice=round_tool_choice,
                            **stream_provider_extras,
                        )
                        async for chunk in iter_stream_with_wall_clock(
                            stream_source,
                            budget,
                        ):
                            async for _sa_ev in _flush_subagent_sse():
                                yield _sa_ev
                            if chunk.get("event") == "tool_planning":
                                yield status_event("planning_tools")
                                yield _emit_trace(
                                    step_id=f"tool_planning_{iteration}",
                                    kind="plan",
                                    state="active",
                                    title_key="aiTracePlanningTools",
                                    iteration=iteration,
                                )
                                await asyncio.sleep(0)
                                continue
                            if chunk.get("usage"):
                                round_usage_this_iter = chunk["usage"]
                                final_usage = round_usage_this_iter
                            if chunk.get("function_calls"):
                                function_calls = chunk["function_calls"]
                                tool_call_id_map = chunk.get("tool_call_id_map", {}) or {}

                            delta = chunk.get("delta", {})
                            content_chunk = delta.get("content", "")
                            reasoning_chunk = delta.get("reasoning_content", "")
                            if reasoning_chunk:
                                round_reasoning += reasoning_chunk
                                if not reasoning_started:
                                    reasoning_started = True
                                    yield _emit_trace(
                                        step_id=reasoning_step_id,
                                        kind="reasoning",
                                        state="active",
                                        title_key="aiTraceReasoning",
                                        iteration=iteration,
                                        layer="reasoning",
                                    )
                                now_mono = time.monotonic()
                                if (
                                    now_mono - last_reasoning_emit >= 0.06
                                    or len(reasoning_chunk) > 48
                                ):
                                    last_reasoning_emit = now_mono
                                    yield _emit_trace(
                                        step_id=reasoning_step_id,
                                        kind="reasoning",
                                        state="active",
                                        title_key="aiTraceReasoning",
                                        body_markdown=visible_reasoning_markdown(
                                            round_reasoning, chat_language
                                        ),
                                        iteration=iteration,
                                        layer="reasoning",
                                    )
                                    await asyncio.sleep(0)
                            if content_chunk:
                                round_text += content_chunk
                                if not writing_status_sent:
                                    writing_status_sent = True
                                    yield status_event("writing")
                                    yield _emit_trace(
                                        step_id=llm_step_id,
                                        kind="context",
                                        state="done",
                                        title_key="aiStatusThinking",
                                        iteration=iteration,
                                    )
                                if round_text.strip():
                                    if not narrative_started:
                                        narrative_started = True
                                    now_mono = time.monotonic()
                                    if (
                                        now_mono - last_narrative_emit >= 0.04
                                        or len(content_chunk) > 64
                                    ):
                                        last_narrative_emit = now_mono
                                        yield _emit_trace(
                                            step_id=narrative_step_id,
                                            kind="narrative",
                                            state="active",
                                            body_markdown=round_text,
                                            iteration=iteration,
                                            layer="reasoning",
                                        )
                                        await asyncio.sleep(0)

                            if chunk.get("done", False):
                                break
                        llm_round_complete = True
                    except WallClockExceeded as wall_exc:
                        budget_stop_reason = STOP_REASON_WALL_CLOCK
                        budget_stop_message = wall_exc.message_fa
                        if round_text.strip() or round_reasoning.strip():
                            llm_round_complete = True
                        else:
                            break
                    except (ApiError, Exception) as stream_exc:
                        if (
                            not context_compress_retried
                            and is_context_overflow_error(stream_exc)
                        ):
                            context_compress_retried = True
                            full_messages, context_meta = self._prepare_llm_messages(
                                structured_prompt,
                                messages,
                                provider,
                                force_summarize=True,
                                use_llm_summary=True,
                            )
                            yield context_usage_event_payload(
                                context_meta,
                                history_summarized=True,
                                context_retried=True,
                            )
                            await asyncio.sleep(0)
                            if round_usage_this_iter:
                                billed_usage = merge_usage(
                                    billed_usage, round_usage_this_iter
                                )
                                budget.add_tokens(
                                    round_usage_this_iter.get("total_tokens")
                                )
                                round_usage_this_iter = None
                            round_text = ""
                            function_calls = None
                            writing_status_sent = False
                            narrative_started = False
                            continue
                        if (
                            llm_stream_retry_count < MAX_LLM_RETRIES - 1
                            and is_retryable_error(stream_exc)
                        ):
                            llm_stream_retry_count += 1
                            yield _emit_trace(
                                step_id=f"retry_{iteration}_{llm_stream_retry_count}",
                                kind="system",
                                state="active",
                                title_key="aiTraceRetrying",
                                title_params={
                                    "attempt": str(llm_stream_retry_count),
                                    "max": str(MAX_LLM_RETRIES - 1),
                                },
                                retry_attempt=llm_stream_retry_count,
                                iteration=iteration,
                            )
                            await asyncio.sleep(0.5 * llm_stream_retry_count)
                            if round_usage_this_iter:
                                billed_usage = merge_usage(
                                    billed_usage, round_usage_this_iter
                                )
                                budget.add_tokens(
                                    round_usage_this_iter.get("total_tokens")
                                )
                                round_usage_this_iter = None
                            round_text = ""
                            function_calls = None
                            writing_status_sent = False
                            narrative_started = False
                            continue
                        raise

                function_calls = resolve_round_function_calls(
                    api_function_calls=function_calls,
                    round_text=round_text,
                    round_reasoning=round_reasoning,
                )
                # Phase 3: حذف tool_callهای بدون نام (stream ناقص / delta خالی)
                if function_calls:
                    function_calls = [
                        c
                        for c in function_calls
                        if isinstance(c, dict) and str(c.get("name") or "").strip()
                    ] or None

                if reasoning_started and round_reasoning.strip():
                    from app.services.ai.ai_language_prompt import (
                        reasoning_language_mismatch,
                    )

                    if reasoning_language_mismatch(
                        round_reasoning, chat_language
                    ):
                        logger.warning(
                            "[AI Agent][session=%s] reasoning language mismatch "
                            "(expected=%s iteration=%s preview=%r)",
                            session_id,
                            chat_language,
                            iteration,
                            round_reasoning.strip()[:120],
                        )
                    yield _emit_trace(
                        step_id=reasoning_step_id,
                        kind="reasoning",
                        state="done",
                        title_key="aiTraceReasoning",
                        body_markdown=sanitize_assistant_content(
                            visible_reasoning_markdown(
                                round_reasoning.strip(), chat_language
                            )
                        ),
                        iteration=iteration,
                        layer="reasoning",
                    )

                if narrative_started and round_text.strip():
                    yield _emit_trace(
                        step_id=narrative_step_id,
                        kind="narrative",
                        state="done",
                        body_markdown=sanitize_assistant_content(round_text.strip()),
                        iteration=iteration,
                    )
                elif not narrative_started:
                    yield _emit_trace(
                        step_id=llm_step_id,
                        kind="context",
                        state="done",
                        title_key="aiStatusThinking",
                        iteration=iteration,
                    )

                if iteration > 1:
                    yield _emit_trace(
                        step_id=f"plan_next_{iteration}",
                        kind="plan_next",
                        state="done",
                        title_key="aiTracePlanningNext",
                        iteration=iteration,
                    )

                # ثبت توکن مصرف‌شدهٔ این نوبت در بودجه و صورتحساب
                if round_usage_this_iter:
                    billed_usage = merge_usage(billed_usage, round_usage_this_iter)
                    budget.add_tokens(round_usage_this_iter.get("total_tokens"))
                    yield _emit_agent_budget()

                if budget_stop_reason == STOP_REASON_WALL_CLOCK:
                    yield _emit_agent_budget(
                        stop_reason=budget_stop_reason,
                        stop_message_fa=budget_stop_message,
                    )
                    # زمان تمام شده → LLM synthesis را رد کن؛ از دادهٔ جمع‌شده
                    # پاسخ قطعی بساز (session 751: سنتز LLM دو بار timeout شد).
                    synthesized = await _resolve_answer_after_budget_stop(
                        prefer_llm_synthesis=False,
                    )
                    if synthesized:
                        async for answer_chunk in _emit_answer_text(
                            synthesized, iter_num=iteration
                        ):
                            yield answer_chunk
                        accumulated_content = synthesized
                    break

                if function_calls and use_tools:
                    accumulated_function_calls.extend(function_calls)
                    yield status_event("planning_tools")

                    bundle_id: Optional[str] = None
                    entity_refs: List[Dict[str, Any]] = []
                    if exploration_enabled and observation_store is not None:
                        bundle_id = new_bundle_id(iteration)
                        entity_refs = extract_entity_refs_from_calls(function_calls)
                        for idx, call in enumerate(function_calls):
                            target = explore_target_for_call(
                                call.get("name", "unknown"),
                                call.get("arguments", {}),
                            )
                            yield _emit_trace(
                                step_id=f"explore_{bundle_id}_{idx}",
                                kind="explore",
                                state="active",
                                title_key="aiTraceExploringTarget",
                                title_params={"target": target},
                                explore_target=target,
                                bundle_id=bundle_id,
                                entity_refs=entity_refs if idx == 0 else None,
                                iteration=iteration,
                            )

                    if narrative_started:
                        yield _emit_trace(
                            step_id=narrative_step_id,
                            kind="narrative",
                            state="done",
                            body_markdown=sanitize_assistant_content(
                                round_text.strip()
                            ),
                            iteration=iteration,
                        )
                    elif round_text.strip():
                        yield _emit_trace(
                            step_id=f"narrative_{iteration}",
                            kind="narrative",
                            state="done",
                            body_markdown=sanitize_assistant_content(
                                round_text.strip()
                            ),
                            iteration=iteration,
                        )
                    else:
                        yield _emit_trace(
                            step_id=f"plan_{iteration}",
                            kind="plan",
                            state="done",
                            title_key="aiTracePlanningAction",
                            body_markdown=format_planned_tools(function_calls),
                            iteration=iteration,
                        )

                    for idx, call in enumerate(function_calls):
                        fname = call.get("name", "unknown")
                        tc_id = _tool_call_id_for(call, iteration, idx)
                        if not call.get("id"):
                            call["id"] = tc_id
                        label = tool_label_fa(fname)
                        tool_step_id = f"tool_{tc_id}"
                        yield _emit_trace(
                            step_id=tool_step_id,
                            kind="tool",
                            state="active",
                            title_key="aiTraceRunningTool",
                            title_params={"toolName": label},
                            tool=fname,
                            tool_key=tool_l10n_key(fname),
                            iteration=iteration,
                        )
                        yield {
                            "event": "tool_start",
                            "tool": fname,
                            "tool_key": tool_l10n_key(fname),
                            "label": label,
                        }

                    from app.services.ai.ai_session_todo_events import (
                        drain_session_todo_sse,
                        reset_session_todo_sse_buffer,
                    )

                    reset_session_todo_sse_buffer()
                    tool_task = asyncio.create_task(
                        self.handle_function_calls_async(
                            function_calls,
                            session_business_id=session_business_id,
                            approve_writes=approve_writes,
                            approved_write_calls=approved_write_calls,
                            iteration=iteration,
                            session_id=session_id,
                            execution_mode=effective_execution_mode,
                        )
                    )
                    while not tool_task.done():
                        async for _sa_ev in _flush_subagent_sse(timeout=0.08):
                            yield _sa_ev
                    function_results = await tool_task
                    async for _sa_ev in _flush_subagent_sse():
                        yield _sa_ev
                    for todo_event in drain_session_todo_sse():
                        yield todo_event
                        await asyncio.sleep(0)
                    _merge_round_tool_results(
                        accumulated_function_results, function_results
                    )
                    yield {"event": "agent_run", **agent_run.snapshot()}

                    round_productive = assess_tool_round_productivity(
                        function_calls, function_results, _lookup_tool_result
                    )

                    for idx, call in enumerate(function_calls):
                        fname = call.get("name", "unknown")
                        tc_id = _tool_call_id_for(call, iteration, idx)
                        tool_step_id = f"tool_{tc_id}"
                        result = _lookup_tool_result(function_results, call)
                        needs_approval = (
                            isinstance(result, dict)
                            and result.get("error") == "APPROVAL_REQUIRED"
                        )
                        success = not (
                            isinstance(result, dict) and result.get("error")
                        )
                        # استخراج اطلاعات غنی برای trace
                        elapsed_ms: Optional[int] = None
                        result_count: Optional[int] = None
                        citations: Optional[List[str]] = None
                        if isinstance(result, dict):
                            elapsed_ms = result.get("_elapsed_ms")
                            result_count = extract_result_count(result)
                            citations = extract_citations_from_result(result) or None

                        tool_end_payload: Dict[str, Any] = {
                            "event": "tool_end",
                            "tool": fname,
                            "tool_key": tool_l10n_key(fname),
                            "label": tool_label_fa(fname),
                            "success": success,
                            "approval_required": needs_approval,
                            "elapsed_ms": elapsed_ms,
                            "result_count": result_count,
                        }
                        if needs_approval and isinstance(result, dict):
                            tool_end_payload["approval_detail"] = {
                                "function": fname,
                                "label": result.get("label") or tool_label_fa(fname),
                                "arguments": result.get("arguments")
                                or call.get("arguments", {}),
                                "message": result.get("message"),
                                "error": result.get("error"),
                            }
                        yield tool_end_payload
                        yield _emit_trace(
                            step_id=tool_step_id,
                            kind="tool",
                            state="done" if success else "error",
                            title_key="aiTraceRunningTool",
                            title_params={"toolName": tool_label_fa(fname)},
                            tool=fname,
                            tool_key=tool_l10n_key(fname),
                            iteration=iteration,
                            elapsed_ms=elapsed_ms,
                            result_count=result_count,
                        )
                        if fname == "spawn_subagent" and isinstance(result, dict):
                            sid = str(result.get("subagent_id") or "")
                            child_status = str(result.get("status") or "")
                            child_state = (
                                "active"
                                if child_status == "running"
                                else ("error" if result.get("error") else "done")
                            )
                            yield _emit_trace(
                                step_id=f"subagent_{sid or tc_id}",
                                kind="subagent",
                                state=child_state,
                                title_key="aiTraceSubagent",
                                title_params={
                                    "goal": str(result.get("goal") or "")[:120]
                                },
                                body_markdown=str(
                                    result.get("goal")
                                    or result.get("content")
                                    or ""
                                )[:800],
                                tool=fname,
                                tool_key=tool_l10n_key(fname),
                                iteration=iteration,
                                explore_target=sid or None,
                                subagent_id=sid or None,
                            )
                        yield _emit_trace(
                            step_id=f"obs_{tc_id}",
                            kind="observation",
                            state="done" if success else "error",
                            title_key="aiTraceObservation",
                            title_params={"toolName": tool_label_fa(fname)},
                            body_markdown=summarize_tool_result(fname, result),
                            tool=fname,
                            tool_key=tool_l10n_key(fname),
                            iteration=iteration,
                            citations=citations,
                            bundle_id=bundle_id,
                        )

                    round_needs_write_approval = any(
                        is_write_guard_stop_result(
                            _lookup_tool_result(function_results, call)
                        )
                        for call in function_calls
                    )

                    assistant_msg: Dict[str, Any] = {
                        "role": "assistant",
                        "tool_calls": [],
                    }
                    if round_text:
                        assistant_msg["content"] = round_text

                    for idx, call in enumerate(function_calls):
                        tc_id = _tool_call_id_for(call, iteration, idx)
                        if not call.get("id"):
                            call["id"] = tc_id
                        assistant_msg["tool_calls"].append(
                            {
                                "id": tc_id,
                                "type": "function",
                                "function": {
                                    "name": call.get("name"),
                                    "arguments": json.dumps(
                                        call.get("arguments", {}),
                                        ensure_ascii=False,
                                    ),
                                },
                            }
                        )
                    if not assistant_msg.get("content"):
                        assistant_msg.pop("content", None)

                    full_messages.append(assistant_msg)

                    for idx, call in enumerate(function_calls):
                        function_name = call.get("name") or "unknown"
                        result = _lookup_tool_result(function_results, call)
                        serialized = self._serialize_for_json(result)
                        tc_id = _tool_call_id_for(call, iteration, idx)
                        full_messages.append(
                            {
                                "role": "tool",
                                "tool_call_id": tc_id,
                                "content": summarize_tool_result_for_llm(
                                    function_name, serialized
                                ),
                            }
                        )

                    if round_needs_write_approval:
                        pause_content = build_approval_pause_content(
                            function_calls,
                            lambda c: _lookup_tool_result(function_results, c),
                        )
                        yield _emit_trace(
                            step_id=f"approval_{iteration}",
                            kind="approval",
                            state="active",
                            body_markdown=pause_content,
                            iteration=iteration,
                        )
                        yield status_event("awaiting_approval")
                        if not accumulated_content.strip():
                            accumulated_content = pause_content
                            yield {
                                "delta": {"content": pause_content},
                                "usage": None,
                                "done": False,
                            }
                            await asyncio.sleep(0)
                        break

                    # --- Exploration: Explored + Thought ---
                    if (
                        exploration_enabled
                        and observation_store is not None
                        and bundle_id
                    ):
                        bundle_observations: List[ToolObservation] = []
                        for idx, call in enumerate(function_calls):
                            fname = call.get("name", "unknown")
                            tc_id = _tool_call_id_for(call, iteration, idx)
                            result = _lookup_tool_result(function_results, call)
                            success_obs = not (
                                isinstance(result, dict) and result.get("error")
                            )
                            elapsed_obs = (
                                result.get("_elapsed_ms")
                                if isinstance(result, dict)
                                else None
                            )
                            rc = (
                                extract_result_count(result)
                                if isinstance(result, dict)
                                else None
                            )
                            cites = extract_citations_from_result(result) or None
                            bundle_observations.append(
                                ToolObservation(
                                    tool_name=fname,
                                    arguments=call.get("arguments", {}) or {},
                                    result=result,
                                    success=success_obs,
                                    elapsed_ms=elapsed_obs,
                                    citations=cites,
                                )
                            )
                            yield _emit_trace(
                                step_id=f"explore_{bundle_id}_{idx}",
                                kind="explore",
                                state="done",
                                title_key="aiTraceExploredTarget",
                                title_params={
                                    "target": explore_target_for_call(
                                        fname, call.get("arguments", {})
                                    ),
                                },
                                explore_target=explore_target_for_call(
                                    fname, call.get("arguments", {})
                                ),
                                bundle_id=bundle_id,
                                iteration=iteration,
                            )

                        bundle = ExplorationBundle(
                            bundle_id=bundle_id,
                            iteration=iteration,
                            title=bundle_title_from_calls(function_calls),
                            explore_targets=[
                                explore_target_for_call(
                                    c.get("name", "unknown"),
                                    c.get("arguments", {}),
                                )
                                for c in function_calls
                            ],
                            observations=bundle_observations,
                        )
                        observation_store.add_bundle(bundle)
                        explored_body = build_explored_body_markdown(bundle)
                        yield _emit_trace(
                            step_id=f"explored_{bundle_id}",
                            kind="explored",
                            state="done",
                            title_key="aiTraceExplored",
                            title_params={
                                "title": bundle.title,
                                "count": str(bundle.tool_count),
                            },
                            body_markdown=explored_body,
                            bundle_id=bundle_id,
                            entity_refs=entity_refs,
                            result_count=bundle.tool_count,
                            iteration=iteration,
                        )

                        thought_body, hypothesis, confidence, open_qs = (
                            build_thought_markdown_rule_based(
                                bundle,
                                effective_user_query,
                                language=chat_language,
                            )
                        )
                        if (
                            use_llm_thought
                            and bundle.tool_count >= EXPLORATION_LLM_THOUGHT_MIN_TOOLS
                        ):
                            llm_thought = await synthesize_thought_with_llm(
                                provider,
                                self.get_effective_model_api_id(
                                    operation=AI_OPERATION_THOUGHT,
                                ),
                                max_tokens_override or self.config.max_tokens,
                                effective_temperature,
                                bundle,
                                effective_user_query,
                                explored_body,
                                db=self.db,
                                language=chat_language,
                            )
                            if llm_thought:
                                thought_body = llm_thought

                        findings_count = thought_body.count("\n1.") + (
                            1 if "\n1." in thought_body else 0
                        )
                        thought_id = f"thought_{bundle_id}"
                        thought_rec = ThoughtRecord(
                            thought_id=thought_id,
                            bundle_id=bundle_id,
                            iteration=iteration,
                            body_markdown=thought_body,
                            hypothesis=hypothesis,
                            confidence=confidence,
                            open_questions=open_qs,
                        )
                        observation_store.add_thought(thought_rec)

                        yield _emit_trace(
                            step_id=thought_id,
                            kind="thought",
                            state="done",
                            title_key="aiTraceThought",
                            title_params={"count": str(max(findings_count, 1))},
                            body_markdown=thought_body,
                            bundle_id=bundle_id,
                            findings_count=max(findings_count, 1),
                            hypothesis=hypothesis,
                            confidence=confidence,
                            iteration=iteration,
                        )

                    round_assessment = None
                    if goal_tracker is not None:
                        round_assessment = goal_tracker.assess_after_tool_round(
                            function_calls,
                            function_results,
                            _lookup_tool_result,
                            user_query=effective_user_query,
                            session_todo_state=self._session_todo_goal_state(session_id),
                        )
                        if try_extend_budget_for_goal(budget, round_assessment):
                            max_iterations = budget.max_iterations
                            yield _emit_trace(
                                step_id=f"budget_extend_{budget.extensions_granted}",
                                kind="system",
                                state="done",
                                body_markdown=(
                                    f"هدف هنوز محقق نشده — بودجه تحلیل به "
                                    f"{budget.max_iterations} مرحله تمدید شد."
                                ),
                                iteration=iteration,
                            )
                            yield _emit_agent_budget()

                    if observation_store is not None:
                        thought_ctx = observation_store.context_for_llm()
                        if thought_ctx:
                            full_messages.append(
                                {
                                    "role": "user",
                                    "content": thought_ctx,
                                }
                            )
                    elif goal_tracker is not None:
                        goal_ctx = goal_tracker.continue_context_for_llm()
                        if goal_ctx:
                            full_messages.append(
                                {"role": "user", "content": goal_ctx}
                            )

                    budget.note_round(productive=round_productive)
                    continue

                if round_text.strip():
                    from app.services.ai.ai_agent_continuation import resolve_needs_tools

                    _needs_tools = resolve_needs_tools(
                        effective_user_query,
                        messages,
                        tools_enabled=bool(use_tools),
                    )
                    _continue_decision = should_agent_continue_after_text_round(
                        goal_tracker=goal_tracker,
                        exploration_enabled=exploration_enabled,
                        observation_store=observation_store,
                        iteration=iteration,
                        budget=budget,
                        round_text=round_text,
                        user_query=effective_user_query,
                        history_messages=messages,
                        needs_tools=_needs_tools,
                        tools_enabled=bool(use_tools),
                    )
                    logger.info(
                        "[AI Agent][session=%s] text-round decision: "
                        "complexity=%s needs_tools=%s eff_tools=%s "
                        "goal_tracker=%s continue=%s iteration=%s/%s",
                        session_id,
                        complexity,
                        _needs_tools,
                        bool(use_tools),
                        goal_tracker is not None,
                        _continue_decision,
                        iteration,
                        budget.max_iterations,
                    )
                    # لایهٔ ایمنی: اگر Plan C به‌اشتباه stop داده ولی متن تحویلی
                    # نیست، ادامه بده (با یا بدون evidence ابزار).
                    if (
                        not _continue_decision
                        and _needs_tools
                        and use_tools
                        and iteration < budget.max_iterations
                    ):
                        from app.services.ai.ai_deliverable_answer import (
                            is_deliverable_answer,
                        )
                        from app.services.ai.ai_exploration_service import (
                            observation_store_has_evidence,
                        )

                        _has_evidence = (
                            observation_store is not None
                            and observation_store_has_evidence(observation_store)
                        )
                        if not is_deliverable_answer(
                            round_text,
                            needs_tools=True,
                            has_tool_evidence=_has_evidence,
                        ):
                            logger.warning(
                                "[AI Agent][session=%s] deliverable-gate: "
                                "non-deliverable text blocked from final answer "
                                "(iteration=%s has_evidence=%s)",
                                session_id,
                                iteration,
                                _has_evidence,
                            )
                            _continue_decision = True

                    if _continue_decision:
                        # اگر زمان دیوار تقریباً تمام است و قبلاً پاسخ ترکیبی/شواهد
                        # داریم، به‌جای شروع نوبت جدید همان را نهایی کن.
                        from app.services.ai.ai_deliverable_answer import (
                            is_deliverable_answer as _is_deliverable_text,
                        )

                        _remaining_wc = budget.remaining_wall_clock_sec()
                        if (
                            _remaining_wc is not None
                            and _remaining_wc < 35.0
                            and use_tools
                        ):
                            _early = extract_usable_narrative_for_answer(
                                trace_steps
                            )
                            if not _early:
                                _candidate = sanitize_assistant_content(
                                    round_text.strip()
                                )
                                if _is_deliverable_text(
                                    _candidate,
                                    needs_tools=_needs_tools,
                                    has_tool_evidence=True,
                                ):
                                    _early = _candidate
                            if _early:
                                logger.info(
                                    "[AI Agent][session=%s] early-finalize before "
                                    "wall-clock (remaining=%.1fs iteration=%s)",
                                    session_id,
                                    _remaining_wc,
                                    iteration,
                                )
                                async for answer_chunk in _emit_answer_text(
                                    _early, iter_num=iteration
                                ):
                                    yield answer_chunk
                                accumulated_content = _early
                                break

                        max_iterations = budget.max_iterations
                        yield _emit_trace(
                            step_id=f"continue_explore_{iteration}",
                            kind="plan_next",
                            state="done",
                            title_key="aiTraceNeedMoreExploration",
                            iteration=iteration,
                        )
                        full_messages.append(
                            {"role": "assistant", "content": round_text.strip()}
                        )
                        continue_msg = (
                            goal_tracker.continue_context_for_llm()
                            if goal_tracker
                            else None
                        ) or (
                            "[agent_continue]\n"
                            "بر اساس یافته‌های تا اینجا، هنوز نیاز به بررسی "
                            "یا ابزار بیشتر است. قبل از پاسخ نهایی، "
                            "دادهٔ لازم را با tool_call API (نه فقط توضیح متنی) "
                            "جمع‌آوری کن."
                        )
                        full_messages.append(
                            {"role": "user", "content": continue_msg}
                        )
                        budget.note_round(productive=False)
                        continue

                    display_text = sanitize_assistant_content(round_text.strip())
                    from app.services.ai.ai_deliverable_answer import (
                        is_deliverable_answer,
                    )
                    from app.services.ai.ai_exploration_service import (
                        observation_store_has_evidence,
                    )

                    _has_evidence = (
                        (
                            observation_store is not None
                            and observation_store_has_evidence(observation_store)
                        )
                        or trace_has_unanswered_evidence(trace_steps)
                    )
                    if not is_deliverable_answer(
                        display_text,
                        needs_tools=_needs_tools,
                        has_tool_evidence=bool(_has_evidence),
                    ):
                        if _has_evidence:
                            prefer_llm = budget_stop_reason != STOP_REASON_WALL_CLOCK
                            synthesized = await _resolve_answer_after_budget_stop(
                                prefer_llm_synthesis=prefer_llm,
                            )
                            if synthesized:
                                async for answer_chunk in _emit_answer_text(
                                    synthesized, iter_num=iteration
                                ):
                                    yield answer_chunk
                                accumulated_content = synthesized
                                break
                        if iteration < budget.max_iterations:
                            from app.services.ai.ai_language_prompt import (
                                build_agent_synthesize_continue_message,
                            )

                            full_messages.append(
                                {"role": "assistant", "content": round_text.strip()}
                            )
                            full_messages.append(
                                {
                                    "role": "user",
                                    "content": build_agent_synthesize_continue_message(
                                        chat_language
                                    ),
                                }
                            )
                            budget.note_round(productive=False)
                            continue
                        display_text = ""

                    if not display_text:
                        budget.note_round(productive=False)
                        continue

                    redact_final_answer_from_reasoning_trace(
                        trace_steps, display_text
                    )
                    yield _emit_trace(
                        kind="answer",
                        state="done",
                        title_key="aiTraceComposingAnswer",
                        body_markdown=None,
                        iteration=iteration,
                        layer="answer",
                    )
                    _answer_chunk_size = 48
                    for offset in range(0, len(display_text), _answer_chunk_size):
                        piece = display_text[offset : offset + _answer_chunk_size]
                        yield {
                            "delta": {"content": piece},
                            "usage": None,
                            "done": False,
                        }
                        await asyncio.sleep(0)
                    accumulated_content = display_text
                    break

                # LLM بدون tool call و بدون متن — از یافته‌های trace پاسخ بساز
                synthesized = extract_final_content_from_trace(trace_steps)
                if synthesized:
                    async for answer_chunk in _emit_answer_text(
                        synthesized, iter_num=iteration
                    ):
                        yield answer_chunk
                    accumulated_content = synthesized
                    break

                budget.note_round(productive=False)
                continue

            if session_id and getattr(self, "_subagent_depth", 0) == 0:
                from app.services.ai.ai_constants import SUBAGENT_TIMEOUT_SEC
                from app.services.ai.ai_subagent import has_running_session_subagents

                wait_deadline = time.monotonic() + min(30.0, SUBAGENT_TIMEOUT_SEC)
                while (
                    has_running_session_subagents(session_id)
                    and time.monotonic() < wait_deadline
                ):
                    async for _sa_ev in _flush_subagent_sse(timeout=0.08):
                        yield _sa_ev
                async for _sa_ev in _flush_subagent_sse():
                    yield _sa_ev

            from app.services.ai.ai_agent_continuation import resolve_needs_tools
            from app.services.ai.ai_deliverable_answer import is_deliverable_answer
            from app.services.ai.ai_exploration_service import (
                observation_store_has_evidence,
            )

            _has_evidence = (
                (
                    observation_store is not None
                    and observation_store_has_evidence(observation_store)
                )
                or trace_has_unanswered_evidence(trace_steps)
                or bool(accumulated_function_results)
            )
            _needs_tools_final = resolve_needs_tools(
                effective_user_query,
                messages,
                tools_enabled=bool(use_tools),
            )
            _content = (accumulated_content or "").strip()
            _deliverable = bool(_content) and is_deliverable_answer(
                _content,
                needs_tools=_needs_tools_final,
                has_tool_evidence=bool(_has_evidence),
            )

            if not _deliverable and (_has_evidence or not _content):
                # پاسخ خالی یا planning-only با شواهد ابزار → سنتز اجباری
                prefer_llm = budget_stop_reason != STOP_REASON_WALL_CLOCK
                synthesized = await _resolve_answer_after_budget_stop(
                    prefer_llm_synthesis=prefer_llm,
                )
                if synthesized:
                    accumulated_content = synthesized
                    async for answer_chunk in _emit_answer_text(
                        synthesized, iter_num=iteration
                    ):
                        yield answer_chunk
                elif budget_stop_reason:
                    from app.services.ai.ai_budget import STOP_REASON_UNPRODUCTIVE

                    if budget_stop_reason == STOP_REASON_ITERATIONS:
                        accumulated_content = (
                            f"به حداکثر تعداد مراحل تحلیل ({max_iterations}) رسیدم. "
                            "با داده‌های جمع‌آوری‌شده می‌توانید سوال را دقیق‌تر تکرار کنید "
                            "یا موضوع را در چند پیام جدا بپرسید."
                        )
                    elif budget_stop_reason == STOP_REASON_UNPRODUCTIVE:
                        accumulated_content = (
                            "نتوانستم با دادهٔ کافی به سوال پاسخ دهم. "
                            "لطفاً سوال را دقیق‌تر تکرار کنید یا آن را به چند بخش کوچک‌تر تقسیم کنید."
                        )
                    else:
                        accumulated_content = (
                            budget_stop_message
                            or "تحلیل این پاسخ به سقف تعیین‌شده رسید."
                        )
                    yield {
                        "delta": {"content": accumulated_content},
                        "usage": None,
                        "done": False,
                    }
                    yield _emit_agent_budget(
                        stop_reason=budget_stop_reason,
                        stop_message_fa=budget_stop_message,
                    )
                elif _content and not _deliverable:
                    accumulated_content = ""

            elif (
                not _deliverable
                and not _has_evidence
                and _content
            ):
                from app.services.ai.ai_deliverable_answer import (
                    UNGROUNDED_TOOL_REQUIRED_MESSAGE_FA,
                    looks_like_ungrounded_business_claim,
                )

                if looks_like_ungrounded_business_claim(_content):
                    accumulated_content = UNGROUNDED_TOOL_REQUIRED_MESSAGE_FA

            agent_run.set_phase(AGENT_RUN_PHASE_DONE)
            final_agent_budget = budget_snapshot(
                budget,
                iteration=iteration,
                reasoning_effort=reasoning_effort,
                stop_reason=budget_stop_reason,
                stop_message_fa=budget_stop_message,
            )
            final_agent_budget["run_id"] = agent_run.run_id
            final_agent_budget["phase"] = agent_run.phase

            if exploration_enabled:
                yield _emit_trace(
                    step_id="explore_root",
                    kind="explore",
                    state="done",
                    title_key="aiTraceExploringDone",
                    iteration=iteration,
                )

            # ساخت citations از نتایج tool calls
            citations_context: Optional[str] = None
            citation_sources: List[Dict[str, Any]] = []
            if accumulated_function_results:
                try:
                    from app.services.ai.ai_citation_service import (
                        extract_citation_sources,
                        format_citations_for_response,
                        merge_citations_into_function_results,
                    )

                    citation_sources = extract_citation_sources(
                        accumulated_function_results
                    )
                    citations_context = format_citations_for_response(
                        accumulated_function_results
                    )
                    if citation_sources:
                        accumulated_function_results = (
                            merge_citations_into_function_results(
                                accumulated_function_results,
                                citation_sources,
                            )
                        )
                except Exception:
                    citation_sources = []

            activated_skills = list(getattr(self, "_turn_activated_skills", None) or [])
            if activated_skills:
                merged_fr = dict(accumulated_function_results or {})
                merged_fr["_activated_skills"] = activated_skills
                accumulated_function_results = merged_fr

            def _approval_result_value(entry: Any) -> Any:
                if isinstance(entry, dict) and "result" in entry and "name" in entry:
                    return entry.get("result")
                return entry

            awaiting_approval = any(
                is_write_guard_stop_result(_approval_result_value(v))
                for v in (accumulated_function_results or {}).values()
            )
            agent_run.stop_reason = budget_stop_reason
            agent_run.status = status_for_stop(
                stop_reason=budget_stop_reason,
                awaiting_approval=awaiting_approval,
                completed=not bool(budget_stop_reason),
            )
            if session_id:
                try:
                    from app.services.ai.ai_session_todo_service import (
                        list_session_todos,
                        merge_todos_into_function_results,
                        todos_dicts_from_rows,
                        todos_summary,
                    )

                    todo_rows = list_session_todos(self.db, int(session_id))
                    if todo_rows:
                        accumulated_function_results = merge_todos_into_function_results(
                            accumulated_function_results,
                            todos_dicts_from_rows(todo_rows),
                            summary=todos_summary(todo_rows),
                        )
                except Exception as exc:
                    logger.warning("Failed to merge session todos into results: %s", exc)
                    safe_db_rollback(self.db)
            # usage خلاصهٔ تاریخچه (در صورت وجود) را به صورتحساب اضافه کن
            if getattr(self, "_turn_usage", None):
                billed_usage = merge_usage(billed_usage, self._turn_usage)
            yield {
                "delta": {"content": ""},
                "usage": billed_usage
                if (
                    billed_usage.get("input_tokens")
                    or billed_usage.get("output_tokens")
                    or billed_usage.get("total_tokens")
                )
                else final_usage,
                "done": True,
                "final_content": accumulated_content or "",
                "awaiting_approval": awaiting_approval,
                "function_calls": accumulated_function_calls or None,
                "function_results": (
                    json_safe_value(accumulated_function_results)
                    if accumulated_function_results
                    else None
                ),
                "agent_trace": finalize_trace_steps_for_persist(trace_steps) or None,
                "agent_budget": final_agent_budget,
                "agent_run": agent_run.snapshot(),
                "can_continue": bool(agent_run.snapshot().get("can_continue")),
                "run_id": agent_run.run_id,
                "citations_context": citations_context or None,
                "citations": citation_sources or None,
                "activated_skills": activated_skills or None,
                "requested_model": requested_model_code,
                "resolved_model": resolved_model_code,
                "execution_mode": effective_execution_mode,
            }

        except ApiError:
            agent_run.set_phase(AGENT_RUN_PHASE_ERROR)
            raise
        except Exception as e:
            agent_run.set_phase(AGENT_RUN_PHASE_ERROR)
            logger.error(f"Unexpected error in AI streaming service: {e}", exc_info=True)
            raise ApiError(
                "AI_SERVICE_ERROR",
                f"خطا در سرویس AI: {str(e)}",
                http_status=500,
            )
        finally:
            self.clear_routing_context()
            self._turn_usage = None
    def handle_function_calls(
        self,
        function_calls: List[Dict[str, Any]],
        session_business_id: Optional[int] = None,
        approve_writes: bool = False,
        approved_write_calls: Optional[List[Dict[str, Any]]] = None,
        execution_mode: Optional[str] = None,
    ) -> Dict[str, Any]:
        """پردازش function calling (sync — سازگاری با گذشته)"""
        results = {}
        effective_business_id = session_business_id or self.business_id
        effective_execution_mode = resolve_execution_mode(execution_mode)
        context = {
            "user_context": self.ctx,
            "business_id": effective_business_id,
            "session_business_id": session_business_id,
            "calendar_type": self.ctx.get_calendar_type(),
        }

        for call in function_calls:
            function_name = call.get("name") or "unknown"
            arguments = call.get("arguments", {}) or {}

            if registry.get_function(function_name) is None:
                from app.services.ai.ai_tool_error import unknown_tool_result

                results[function_name] = unknown_tool_result(function_name)
                continue

            if is_write_function(function_name, registry):
                if should_block_write_in_analyzer(
                    effective_execution_mode, function_name, registry
                ):
                    results[function_name] = build_read_only_mode_result(
                        function_name, arguments
                    )
                    continue
                if should_require_write_approval(
                    effective_execution_mode,
                    function_name,
                    approve_writes=approve_writes,
                    registry=registry,
                ):
                    results[function_name] = build_approval_required_result(
                        function_name, arguments
                    )
                    continue
                if approve_writes:
                    ok, approved_args, _meta = resolve_approved_write(
                        function_name, arguments, approved_write_calls
                    )
                    if not ok:
                        results[function_name] = build_approval_mismatch_result(
                            function_name, arguments
                        )
                        continue
                    arguments = approved_args

            try:
                result = run_ai_registry_function(function_name, arguments, context)
                results[function_name] = result
            except Exception as e:
                logger.error(f"Error calling function {function_name}: {e}", exc_info=True)
                from app.services.ai.ai_tool_error import normalize_tool_error

                fn = registry.get_function(function_name)
                results[function_name] = normalize_tool_error(
                    function_name,
                    e,
                    schema=getattr(fn, "parameters_schema", None),
                )

        return results

    async def handle_function_calls_async(
        self,
        function_calls: List[Dict[str, Any]],
        session_business_id: Optional[int] = None,
        approve_writes: bool = False,
        approved_write_calls: Optional[List[Dict[str, Any]]] = None,
        iteration: int = 0,
        session_id: Optional[int] = None,
        execution_mode: Optional[str] = None,
    ) -> Dict[str, Any]:
        """پردازش function calling به صورت async — کلید نتیجه tool_call_id.

        ویژگی‌های جدید:
         - registry-based write detection
         - tool-level session caching (فقط read-only)
         - زمان‌بندی اجرا در نتیجه (_elapsed_ms)
         - invalidation کش بعد از عملیات نوشتنی
        """
        effective_business_id = session_business_id or self.business_id
        effective_execution_mode = resolve_execution_mode(execution_mode)
        context = {
            "user_context": self.ctx,
            "business_id": effective_business_id,
            "session_business_id": session_business_id,
            "session_id": session_id,
            "calendar_type": self.ctx.get_calendar_type(),
        }

        async def call_single_function(
            call: Dict[str, Any], index: int
        ) -> tuple[str, str, Any]:
            function_name = call.get("name") or "unknown"
            arguments = call.get("arguments", {}) or {}
            tc_id = _tool_call_id_for(call, iteration, index)
            if not call.get("id"):
                call["id"] = tc_id

            registered = registry.get_function(function_name)
            if registered is None:
                from app.services.ai.ai_tool_error import unknown_tool_result

                return tc_id, function_name, unknown_tool_result(function_name)

            # بررسی نیاز به تأیید با استفاده از registry
            if is_write_function(function_name, registry):
                if should_block_write_in_analyzer(
                    effective_execution_mode, function_name, registry
                ):
                    return tc_id, function_name, build_read_only_mode_result(
                        function_name, arguments
                    )
                if should_require_write_approval(
                    effective_execution_mode,
                    function_name,
                    approve_writes=approve_writes,
                    registry=registry,
                ):
                    return tc_id, function_name, build_approval_required_result(
                        function_name, arguments
                    )
                if approve_writes:
                    ok, approved_args, _meta = resolve_approved_write(
                        function_name, arguments, approved_write_calls
                    )
                    if not ok:
                        return tc_id, function_name, build_approval_mismatch_result(
                            function_name, arguments
                        )
                    arguments = approved_args

            # بررسی کش برای توابع read-only
            from app.services.ai.ai_subagent import (
                AWAIT_SUBAGENT_TOOL,
                CANCEL_SUBAGENT_TOOL,
                SPAWN_SUBAGENT_TOOL,
                SUBAGENT_TOOL_NAMES,
                await_subagent_async,
                cancel_subagent_async,
                spawn_subagent_async,
            )

            is_readonly = is_readonly_function(function_name, registry)
            if function_name in SUBAGENT_TOOL_NAMES:
                start_time = time.monotonic()
                try:
                    if function_name == SPAWN_SUBAGENT_TOOL:
                        result = await spawn_subagent_async(
                            self,
                            arguments,
                            session_id=session_id,
                            business_id=effective_business_id,
                        )
                    elif function_name == CANCEL_SUBAGENT_TOOL:
                        result = await cancel_subagent_async(
                            arguments.get("subagent_id") or arguments.get("id"),
                            session_id=session_id,
                        )
                    elif function_name == AWAIT_SUBAGENT_TOOL:
                        result = await await_subagent_async(
                            arguments.get("subagent_id") or arguments.get("id"),
                            session_id=session_id,
                        )
                    else:
                        result = {"ok": False, "error": "UNKNOWN_SUBAGENT_TOOL"}
                    elapsed_ms = int((time.monotonic() - start_time) * 1000)
                    if isinstance(result, dict):
                        result["_elapsed_ms"] = elapsed_ms
                    return tc_id, function_name, result
                except asyncio.CancelledError:
                    from app.services.ai.ai_subagent import cancel_session_subagents

                    await cancel_session_subagents(session_id)
                    raise
                except Exception as e:
                    elapsed_ms = int((time.monotonic() - start_time) * 1000)
                    logger.error(
                        "Error calling function %s (%s): %s",
                        function_name,
                        tc_id,
                        e,
                        exc_info=True,
                    )
                    from app.services.ai.ai_tool_error import normalize_tool_error

                    schema = getattr(registered, "parameters_schema", None)
                    payload = normalize_tool_error(
                        function_name, e, schema=schema
                    )
                    payload["_elapsed_ms"] = elapsed_ms
                    return tc_id, function_name, payload

            if is_readonly and effective_business_id and session_id:
                hit, cached_result = get_cached(
                    effective_business_id, session_id, function_name, arguments
                )
                if hit:
                    logger.debug("Tool cache hit: %s", function_name)
                    cached_with_meta = dict(cached_result) if isinstance(cached_result, dict) else {"data": cached_result}
                    cached_with_meta["_from_cache"] = True
                    return tc_id, function_name, cached_with_meta

            start_time = time.monotonic()
            try:
                loop = asyncio.get_event_loop()
                result = await loop.run_in_executor(
                    _executor,
                    lambda fn=function_name, args=arguments: run_ai_registry_function(
                        fn, args, context
                    ),
                )
                elapsed_ms = int((time.monotonic() - start_time) * 1000)

                # ذخیره در کش برای توابع read-only
                if is_readonly and effective_business_id and session_id:
                    set_cached(effective_business_id, session_id, function_name, arguments, result)
                # بعد از عملیات نوشتنی کش session را پاک کن
                elif not is_readonly and effective_business_id and session_id:
                    if not is_agent_internal_function(function_name, registry):
                        invalidate_session(effective_business_id, session_id)

                if isinstance(result, dict):
                    result["_elapsed_ms"] = elapsed_ms
                return tc_id, function_name, result
            except Exception as e:
                elapsed_ms = int((time.monotonic() - start_time) * 1000)
                logger.error(
                    "Error calling function %s (%s): %s",
                    function_name,
                    tc_id,
                    e,
                    exc_info=True,
                )
                from app.services.ai.ai_tool_error import normalize_tool_error

                schema = getattr(registered, "parameters_schema", None)
                payload = normalize_tool_error(function_name, e, schema=schema)
                payload["_elapsed_ms"] = elapsed_ms
                return tc_id, function_name, payload

        try:
            tasks_results = await run_tool_calls_partitioned(
                function_calls,
                call_single_function,
                is_write=lambda call: is_write_function(
                    call.get("name") or "", registry
                ),
            )
        except asyncio.CancelledError:
            from app.services.ai.ai_subagent import cancel_session_subagents

            await cancel_session_subagents(session_id)
            raise
        from app.services.ai.ai_ops_metrics import log_ai_event

        stats = parallel_round_stats(
            function_calls,
            lambda call: is_write_function(call.get("name") or "", registry),
        )
        log_ai_event(
            "tool_round_parallel",
            business_id=effective_business_id,
            session_id=session_id,
            extra=stats,
        )

        return {
            tc_id: {"name": fname, "result": result}
            for tc_id, fname, result in tasks_results
        }
    
    def _serialize_for_json(self, obj: Any) -> Any:
        """تبدیل datetime, date و سایر objects به JSON-serializable format"""
        return json_safe_value(obj)
    
    @staticmethod
    def _extract_chat_title_from_response(response: Dict[str, Any]) -> str:
        """استخراج عنوان از پاسخ مدل؛ برخی مدل‌های reasoning متن را در reasoning_content می‌گذارند."""
        message = response.get("message") or {}
        title = (message.get("content") or "").strip()
        if title:
            return title[:80]

        reasoning = (message.get("reasoning_content") or "").strip()
        if not reasoning:
            return ""

        first_line = reasoning.split("\n", 1)[0].strip().strip("\"'«»")
        return first_line[:80] if first_line else ""

    async def generate_chat_title(self, user_message: str) -> Optional[str]:
        """
        تولید عنوان کوتاه و هوشمند برای گفت‌وگو بر اساس اولین پیام کاربر (async version)

        در صورت نبود اشتراک/سهمیه، بدون فراخوانی provider فقط از متن کاربر عنوان می‌سازد
        تا اعتبار آروان نسوزد. در صورت فراخوانی LLM، usage شارژ می‌شود.
        """
        if not self.config or not self.config.is_active:
            return self._heuristic_chat_title(user_message)
        self.set_routing_context(
            operation=AI_OPERATION_TITLE,
            user_query=user_message,
        )
        try:
            availability = self.check_availability(
                estimated_tokens=300,
                user_query=user_message,
            )
            if not availability.get("can_use"):
                return self._heuristic_chat_title(user_message)

            provider = self._make_provider()
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                _executor,
                lambda: provider.chat_completion(
                    messages=[
                        {
                            "role": "system",
                            "content": get_prompt_by_key(self.db, "aux.chat_title"),
                        },
                        {
                            "role": "user",
                            "content": get_prompt_by_key(
                                self.db,
                                "aux.chat_title_user",
                                {"user_message": user_message},
                            ),
                        },
                    ],
                    model=self.get_effective_model_api_id(
                        operation=AI_OPERATION_TITLE,
                        user_query=user_message,
                    ),
                    max_tokens=200,
                    temperature=float(self.config.temperature),
                    tools=None,
                ),
            )
            usage = response.get("usage") if isinstance(response, dict) else None
            if usage:
                try:
                    self._charge_and_log_usage(
                        input_tokens=int(usage.get("input_tokens", 0) or 0),
                        output_tokens=int(usage.get("output_tokens", 0) or 0),
                        usage=usage,
                        model_code=self.get_effective_model_code(
                            operation=AI_OPERATION_TITLE,
                            user_query=user_message,
                        ),
                    )
                except ApiError as charge_exc:
                    logger.warning(
                        "Chat title charged failed after provider call: %s",
                        charge_exc,
                    )
            title = self._extract_chat_title_from_response(response)
            if not title:
                logger.warning(
                    "Chat title generation returned empty content (model=%s)",
                    self.get_effective_model_api_id(
                        operation=AI_OPERATION_TITLE,
                        user_query=user_message,
                    ),
                )
                return self._heuristic_chat_title(user_message)
            return title
        except Exception as exc:
            logger.warning(f"Failed to generate chat title: {exc}")
            return self._heuristic_chat_title(user_message)
        finally:
            self.clear_routing_context()

    @staticmethod
    def _heuristic_chat_title(user_message: str) -> Optional[str]:
        from app.services.ai.ai_usage_accumulate import heuristic_chat_title

        return heuristic_chat_title(user_message)
