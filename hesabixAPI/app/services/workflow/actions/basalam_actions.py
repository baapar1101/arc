"""اکشن‌های ورک‌فلو برای یکپارچه‌سازی باسلام."""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional

from app.services.workflow.action_registry import ActionHandler
from app.services.workflow.logging_decorators import log_action_execution

logger = logging.getLogger(__name__)


def _coerce_dict_list(raw: Any, field_label: str) -> tuple[bool, List[Dict[str, Any]], Optional[str]]:
    if raw is None:
        return False, [], f"{field_label} is required"
    v = raw
    if isinstance(v, str):
        s = v.strip()
        if not s:
            return False, [], f"{field_label} is required"
        try:
            v = json.loads(s)
        except json.JSONDecodeError:
            return False, [], f"{field_label} must be JSON array or object"
    if isinstance(v, dict):
        return True, [v], None
    if isinstance(v, list):
        out = [x for x in v if isinstance(x, dict)]
        if not out and v:
            return False, [], f"{field_label} items must be objects"
        return True, out, None
    return False, [], f"{field_label} must be a list or object"


def _resolve_actor_uid(
    db: Any,
    business_id: int,
    context: Dict[str, Any],
    node_results: Dict[str, Any],
    user_id_template: Any,
) -> Optional[int]:
    from app.services.workflow.workflow_engine import WorkflowEngine
    from adapters.db.models.business import Business

    raw = WorkflowEngine._resolve_value_static(user_id_template, context, node_results)
    if raw is not None and str(raw).strip() != "":
        try:
            return int(raw)
        except (TypeError, ValueError):
            return None
    uid = context.get("user_id")
    if uid:
        return int(uid)
    biz = db.query(Business).filter(Business.id == business_id).first()
    return int(biz.owner_id) if biz and biz.owner_id else None


class BasalamSendChatReplyAction(ActionHandler):
    """ارسال پاسخ متنی به چت باسلام برای همان مکالمهٔ CRM متصل به باسلام."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "پاسخ به چت باسلام",
            "description": (
                "متن را از طرف عامل به API باسلام می‌فرستد و در CRM هم ثبت می‌کند؛ "
                "مکالمه باید قبلاً با پل باسلام ایجاد شده باشد (basalam_chat_id در متادیتا)."
            ),
            "config_schema": {
                "conversation_id": {
                    "type": "integer",
                    "description": "شناسه مکالمه CRM (مثلاً از خروجی چت پل یا نود قبلی)",
                    "required": True,
                },
                "body": {
                    "type": "string",
                    "description": "متن پیام (قابل حل با $node)",
                    "required": True,
                },
                "basalam_chat_id": {
                    "type": "string",
                    "description": "اختیاری؛ اگر خالی باشد از extra_metadata مکالمه خوانده می‌شود",
                    "required": False,
                },
                "user_id": {
                    "type": "integer",
                    "description": "کاربر عامل در حساب‌یکس؛ خالی = مالک کسب‌وکار یا اجراکننده ورک‌فلو",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services.async_isolated import run_coroutine_isolated
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "پاسخ به چت باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        conv_raw = WorkflowEngine._resolve_value_static(config.get("conversation_id"), context, node_results)
        body_raw = WorkflowEngine._resolve_value_static(config.get("body"), context, node_results)
        chat_override = WorkflowEngine._resolve_value_static(config.get("basalam_chat_id"), context, node_results)
        if conv_raw is None:
            return {"success": False, "error": "conversation_id is required"}
        try:
            conversation_id = int(conv_raw)
        except (TypeError, ValueError):
            return {"success": False, "error": "conversation_id must be an integer"}
        body = str(body_raw or "").strip()
        if not body:
            return {"success": False, "error": "body is required"}
        basalam_chat_id = str(chat_override).strip() if chat_override not in (None, "") else None

        actor = _resolve_actor_uid(db, int(business_id), context, node_results, config.get("user_id"))
        if not actor:
            return {"success": False, "error": "user_id or business owner required"}

        async def _run() -> Dict[str, Any]:
            return await bas_svc.send_chat_reply_to_basalam(
                db=db,
                business_id=int(business_id),
                conversation_id=conversation_id,
                body=body,
                user_id=int(actor),
                basalam_chat_id=basalam_chat_id,
            )

        try:
            out = run_coroutine_isolated(lambda: _run())
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err = detail.get("error")
                if isinstance(err, dict):
                    return {"success": False, "error": err.get("message", str(err)), "code": err.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_send_chat_reply failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}


class BasalamSyncOrdersAction(ActionHandler):
    """سینک دستهٔ سفارش‌های باسلام به فاکتور (همان قرارداد manual_sync_orders)."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "سینک سفارش‌های باسلام",
            "description": "لیست آبجکت سفارش را می‌گیرد و در حساب‌یکس به فاکتور تبدیل می‌کند (در صورت فعال بودن تنظیمات).",
            "config_schema": {
                "orders": {
                    "type": "array",
                    "description": "آرایه سفارش‌ها یا JSON؛ مثلاً از trigger_data.payload",
                    "required": True,
                },
                "user_id": {
                    "type": "integer",
                    "description": "کاربر عامل برای ثبت اسناد؛ خالی = مالک یا اجراکننده ورک‌فلو",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "سینک سفارش باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        raw = WorkflowEngine._resolve_value_static(config.get("orders"), context, node_results)
        ok, orders, err = _coerce_dict_list(raw, "orders")
        if not ok:
            return {"success": False, "error": err or "invalid orders"}

        actor = _resolve_actor_uid(db, int(business_id), context, node_results, config.get("user_id"))
        try:
            out = bas_svc.manual_sync_orders(
                db,
                int(business_id),
                {"orders": orders},
                user_id=actor,
            )
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err_d = detail.get("error")
                if isinstance(err_d, dict):
                    return {"success": False, "error": err_d.get("message", str(err_d)), "code": err_d.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_sync_orders failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}


class BasalamSyncProductsAction(ActionHandler):
    """سینک/ایمپورت لیست محصول از بدنهٔ باسلام به کالاهای محلی."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "سینک محصول از باسلام",
            "description": "لیست محصولات ریموت را با قرارداد manual_sync_products به‌روزرسانی یا ایجاد می‌کند.",
            "config_schema": {
                "products": {
                    "type": "array",
                    "description": "آرایه محصول یا یک شیء؛ قابل ارجاع از نود قبلی",
                    "required": True,
                },
                "user_id": {
                    "type": "integer",
                    "description": "کاربر عامل؛ خالی = مالک یا اجراکننده ورک‌فلو",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "سینک محصول باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        raw = WorkflowEngine._resolve_value_static(config.get("products"), context, node_results)
        ok, products, err = _coerce_dict_list(raw, "products")
        if not ok:
            return {"success": False, "error": err or "invalid products"}

        actor = _resolve_actor_uid(db, int(business_id), context, node_results, config.get("user_id"))
        try:
            out = bas_svc.manual_sync_products(db, int(business_id), {"products": products}, user_id=actor)
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err_d = detail.get("error")
                if isinstance(err_d, dict):
                    return {"success": False, "error": err_d.get("message", str(err_d)), "code": err_d.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_sync_products failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}


class BasalamPullProductsAction(ActionHandler):
    """دریافت صفحه‌ای از محصولات از API باسلام و سینک به محلی."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "دریافت محصول از باسلام (صفحه)",
            "description": "یک صفحه از /v1/products را می‌خواند و مانند دکمه کشیدن در تنظیمات سینک می‌کند.",
            "config_schema": {
                "page": {
                    "type": "integer",
                    "description": "شماره صفحه (پیش‌فرض ۱)",
                    "required": False,
                },
                "per_page": {
                    "type": "integer",
                    "description": "اندازه صفحه ۱–۲۰۰ (پیش‌فرض ۵۰)",
                    "required": False,
                },
                "user_id": {
                    "type": "integer",
                    "description": "کاربر عامل؛ خالی = مالک یا اجراکننده ورک‌فلو",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "دریافت محصول باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        page = WorkflowEngine._resolve_value_static(config.get("page"), context, node_results)
        per_page = WorkflowEngine._resolve_value_static(config.get("per_page"), context, node_results)
        payload: Dict[str, Any] = {}
        if page is not None and str(page).strip() != "":
            try:
                payload["page"] = int(page)
            except (TypeError, ValueError):
                return {"success": False, "error": "page must be integer"}
        if per_page is not None and str(per_page).strip() != "":
            try:
                payload["per_page"] = int(per_page)
            except (TypeError, ValueError):
                return {"success": False, "error": "per_page must be integer"}

        actor = _resolve_actor_uid(db, int(business_id), context, node_results, config.get("user_id"))
        try:
            out = bas_svc.pull_products_from_basalam(db, int(business_id), payload, user_id=actor)
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err_d = detail.get("error")
                if isinstance(err_d, dict):
                    return {"success": False, "error": err_d.get("message", str(err_d)), "code": err_d.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_pull_products failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}


class BasalamPushProductsIncrementalAction(ActionHandler):
    """انتشار افزایشی محصولات اخیراً به‌روز شده به باسلام."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "انتشار افزایشی محصول به باسلام",
            "description": "کالاهایی که در بازهٔ اخیر ویرایش شده‌اند را طبق تنظیمات به باسلام push می‌کند.",
            "config_schema": {
                "since_minutes": {
                    "type": "integer",
                    "description": "فقط کالاهای ویرایش‌شده در این چند دقیقه اخیر (پیش‌فرض ۱۲۰)",
                    "required": False,
                },
                "limit": {
                    "type": "integer",
                    "description": "حداکثر تعداد کالا در این اجرا (۱–۵۰۰، پیش‌فرض ۵۰)",
                    "required": False,
                },
                "vendor_id": {
                    "type": "integer",
                    "description": "شناسه فروشنده باسلام؛ خالی = پیش‌فرض تنظیمات",
                    "required": False,
                },
                "stock": {
                    "type": "integer",
                    "description": "مقدار پیش‌فرض موجودی در payload انتشار در صورت نیاز",
                    "required": False,
                },
                "user_id": {
                    "type": "integer",
                    "description": "کاربر عامل؛ خالی = مالک یا اجراکننده ورک‌فلو",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "انتشار افزایشی باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        payload: Dict[str, Any] = {}
        for key in ("since_minutes", "limit", "vendor_id", "stock"):
            v = WorkflowEngine._resolve_value_static(config.get(key), context, node_results)
            if v is None or str(v).strip() == "":
                continue
            try:
                payload[key] = int(v)
            except (TypeError, ValueError):
                return {"success": False, "error": f"{key} must be integer"}

        actor = _resolve_actor_uid(db, int(business_id), context, node_results, config.get("user_id"))
        try:
            out = bas_svc.push_products_incremental(db, int(business_id), payload, user_id=actor)
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err_d = detail.get("error")
                if isinstance(err_d, dict):
                    return {"success": False, "error": err_d.get("message", str(err_d)), "code": err_d.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_push_products_incremental failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}


class BasalamPublishProductsAction(ActionHandler):
    """انتشار صریح لیست کالاهای محلی به باسلام (SDK create/update)."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "انتشار محصول به باسلام",
            "description": "لیست ورودی محصول محلی را با publish_products_to_basalam منتشر می‌کند؛ vendor_id می‌تواند در تنظیمات پیش‌فرض باشد.",
            "config_schema": {
                "products": {
                    "type": "array",
                    "description": "آرایهٔ ورودی انتشار (local_product_id، فیلدهای قیمت/موجودی و …)",
                    "required": True,
                },
                "vendor_id": {
                    "type": "integer",
                    "description": "فروشنده باسلام؛ اگر خالی باشد از تنظیمات افزونه",
                    "required": False,
                },
                "user_id": {
                    "type": "integer",
                    "description": "کاربر عامل؛ خالی = مالک یا اجراکننده ورک‌فلو",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "انتشار محصول باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        raw = WorkflowEngine._resolve_value_static(config.get("products"), context, node_results)
        ok, products, err = _coerce_dict_list(raw, "products")
        if not ok:
            return {"success": False, "error": err or "invalid products"}

        payload: Dict[str, Any] = {"products": products}
        vid = WorkflowEngine._resolve_value_static(config.get("vendor_id"), context, node_results)
        if vid is not None and str(vid).strip() != "":
            try:
                payload["vendor_id"] = int(vid)
            except (TypeError, ValueError):
                return {"success": False, "error": "vendor_id must be integer"}

        actor = _resolve_actor_uid(db, int(business_id), context, node_results, config.get("user_id"))
        try:
            out = bas_svc.publish_products_to_basalam(db, int(business_id), payload, user_id=actor)
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err_d = detail.get("error")
                if isinstance(err_d, dict):
                    return {"success": False, "error": err_d.get("message", str(err_d)), "code": err_d.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_publish_products failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}


class BasalamRetryProductPublishQueueAction(ActionHandler):
    """پردازش چند آیتم اول از صف انتشار ناموفق (pending_product_publish_retries)."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "تلاش مجدد صف انتشار محصول باسلام",
            "description": (
                "همان منطق API retry_failed_product_publishes: تا سقف limit از ابتدای صف را دوباره منتشر می‌کند؛ "
                "vendor_id اختیاری برای تمام آیتم‌های بدون vendor ذخیره‌شده."
            ),
            "config_schema": {
                "limit": {
                    "type": "integer",
                    "description": "حداکثر آیتم در این اجرا (۱–۱۰۰، پیش‌فرض ۲۰)",
                    "required": False,
                },
                "vendor_id": {
                    "type": "integer",
                    "description": "فروشنده پیش‌فرض برای مقادیر قدیمی صف؛ خالی = از هر آیتم یا تنظیمات افزونه",
                    "required": False,
                },
                "user_id": {
                    "type": "integer",
                    "description": "کاربر عامل؛ خالی = مالک یا اجراکننده ورک‌فلو",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "تلاش مجدد صف انتشار باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        payload: Dict[str, Any] = {}
        lim = WorkflowEngine._resolve_value_static(config.get("limit"), context, node_results)
        if lim is not None and str(lim).strip() != "":
            try:
                payload["limit"] = int(lim)
            except (TypeError, ValueError):
                return {"success": False, "error": "limit must be integer"}
        vid = WorkflowEngine._resolve_value_static(config.get("vendor_id"), context, node_results)
        if vid is not None and str(vid).strip() != "":
            try:
                payload["vendor_id"] = int(vid)
            except (TypeError, ValueError):
                return {"success": False, "error": "vendor_id must be integer"}

        actor = _resolve_actor_uid(db, int(business_id), context, node_results, config.get("user_id"))
        try:
            out = bas_svc.retry_failed_product_publishes(db, int(business_id), payload, user_id=actor)
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err_d = detail.get("error")
                if isinstance(err_d, dict):
                    return {"success": False, "error": err_d.get("message", str(err_d)), "code": err_d.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_retry_product_publish_queue failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}


class BasalamListSyncDeadLetterAction(ActionHandler):
    """صفحه‌بندی از sync_dead_letter (خطاهای نیازمند رسیدگی سفارش/پرداخت)."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "لیست صف مردهٔ سینک باسلام",
            "description": "آیتم‌های ثبت‌شده پس از سینک ناموفق سفارش یا پرداخت (بدون تکرار صف انتشار محصول).",
            "config_schema": {
                "limit": {
                    "type": "integer",
                    "description": "تعداد در صفحه (۱–۲۰۰، پیش‌فرض ۵۰)",
                    "required": False,
                },
                "offset": {
                    "type": "integer",
                    "description": "جابجایی صفحه‌بندی",
                    "required": False,
                },
                "item_type": {
                    "type": "string",
                    "description": "فیلتر نوع: order_sync یا payment_sync؛ خالی = همه",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "لیست DLQ باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        lim_raw = WorkflowEngine._resolve_value_static(config.get("limit"), context, node_results)
        off_raw = WorkflowEngine._resolve_value_static(config.get("offset"), context, node_results)
        limit = 50
        offset = 0
        if lim_raw is not None and str(lim_raw).strip() != "":
            try:
                limit = max(1, min(200, int(lim_raw)))
            except (TypeError, ValueError):
                return {"success": False, "error": "limit must be integer"}
        if off_raw is not None and str(off_raw).strip() != "":
            try:
                offset = max(0, int(off_raw))
            except (TypeError, ValueError):
                return {"success": False, "error": "offset must be integer"}
        item_type = WorkflowEngine._resolve_value_static(config.get("item_type"), context, node_results)
        itype = str(item_type).strip() if item_type not in (None, "") else None

        out = bas_svc.list_sync_dead_letter(
            db, int(business_id), limit=limit, offset=offset, item_type=itype
        )
        return {"success": True, **out}


class BasalamClearSyncDeadLetterAction(ActionHandler):
    """پاک‌کردن بخشی یا همهٔ صف مردهٔ سینک."""

    def get_metadata(self) -> Dict[str, Any]:
        return {
            "name": "پاک‌سازی صف مردهٔ سینک باسلام",
            "description": (
                "یا همه را پاک می‌کند (clear_all=true) یا شناسه‌های dlq_id را؛ "
                "در ورک‌فلو با همان کاربر اجرا ذخیره می‌شود."
            ),
            "config_schema": {
                "clear_all": {
                    "type": "boolean",
                    "description": "اگر true باشد کل صف پاک می‌شود",
                    "required": False,
                },
                "dlq_ids": {
                    "type": "array",
                    "description": "لیست dlq_id برای حذف انتخابی؛ با clear_all هم‌زمان استفاده نکنید",
                    "required": False,
                },
            },
        }

    @log_action_execution
    def execute(self, context: Dict[str, Any], config: Dict[str, Any], node_results: Dict[str, Any]) -> Dict[str, Any]:
        from app.services.workflow.dry_run import dry_run_skip
        from app.services.workflow.workflow_engine import WorkflowEngine
        from app.core.responses import ApiError
        from app.services import basalam_integration_service as bas_svc

        sk = dry_run_skip(context, "پاک‌سازی DLQ باسلام")
        if sk is not None:
            return sk

        db = context.get("db")
        business_id = context.get("business_id")
        if not db or business_id is None:
            return {"success": False, "error": "db or business_id missing in context"}

        ca_raw = WorkflowEngine._resolve_value_static(config.get("clear_all"), context, node_results)
        clear_all = ca_raw is True or str(ca_raw).strip().lower() in ("true", "1", "yes")
        ids_raw = WorkflowEngine._resolve_value_static(config.get("dlq_ids"), context, node_results)
        dlq_ids: Optional[List[Any]] = None
        if ids_raw is not None:
            if isinstance(ids_raw, str):
                try:
                    ids_raw = json.loads(ids_raw)
                except json.JSONDecodeError:
                    return {"success": False, "error": "dlq_ids must be a JSON array"}
            if isinstance(ids_raw, list):
                dlq_ids = ids_raw
            else:
                return {"success": False, "error": "dlq_ids must be a list"}

        try:
            if clear_all:
                out = bas_svc.clear_sync_dead_letter(db, int(business_id), mode="all")
            elif dlq_ids is not None:
                out = bas_svc.clear_sync_dead_letter(db, int(business_id), mode="ids", dlq_ids=dlq_ids)
            else:
                return {"success": False, "error": "clear_all or dlq_ids is required"}
        except ApiError as e:
            detail = e.detail
            if isinstance(detail, dict):
                err_d = detail.get("error")
                if isinstance(err_d, dict):
                    return {"success": False, "error": err_d.get("message", str(err_d)), "code": err_d.get("code")}
            return {"success": False, "error": str(detail)}
        except Exception as ex:
            logger.exception("basalam_clear_sync_dead_letter failed")
            return {"success": False, "error": str(ex)}

        return {"success": True, **out}
