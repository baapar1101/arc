"""
نمونه‌های آمادهٔ مخزن ورک‌فلو برای همهٔ کسب‌وکارها.

گیرندهٔ بله عمداً خالی است تا هنگام نصب هر کسب‌وکار کاربر متصل خودش را انتخاب کند.
sanitize مخزن کلید user_id را هم حذف می‌کند.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.workflow import Workflow, WorkflowStatus
from adapters.db.models.workflow_marketplace import (
    WorkflowMarketplacePackage,
    WorkflowMarketplacePackageStatus,
)
from app.services.workflow.workflow_marketplace_service import publish_package

_BALE_NOTE = (
    "بعد از نصب، نود «ارسال به بله» را باز کنید و کاربر عضو کسب‌وکار را که به ربات بله وصل است انتخاب کنید. "
    "تا وقتی این کاربر انتخاب نشده، پیام بله ارسال نمی‌شود. "
    "اعلان داخلی، اگر در ورک‌فلو باشد، به کاربری می‌رسد که خود رویداد را ثبت کرده است."
)


def _trigger(node_id: str, label: str, trigger_type: str, extra: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    config: Dict[str, Any] = {
        "trigger_type": trigger_type,
        "enabled": True,
        "cooldown_seconds": 0,
    }
    if extra:
        config.update(extra)
    return {
        "id": node_id,
        "type": "trigger",
        "label": label,
        "key": trigger_type,
        "position": {"x": 80, "y": 140},
        "config": config,
    }


def _notify(node_id: str, title: str, message: str, *, priority: str = "normal", y: int = 40) -> Dict[str, Any]:
    return {
        "id": node_id,
        "type": "action",
        "label": "اعلان داخلی",
        "key": "create_notification",
        "position": {"x": 460, "y": y},
        "config": {
            "action_type": "create_notification",
            "event_key": f"workflow.{node_id}",
            "title": title,
            "message": message,
            "channels": ["inapp"],
            "priority": priority,
        },
    }


def _bale(node_id: str, message: str, *, y: int = 260, attachment_ref: Optional[str] = None) -> Dict[str, Any]:
    config: Dict[str, Any] = {
        "action_type": "send_bale",
        "message": message,
        "parse_mode": "None",
        "send_file_attachment": attachment_ref is not None,
        "retry_on_failure": True,
        "retry_attempts": 2,
        "retry_delay_seconds": 30,
    }
    if attachment_ref:
        config["attachment_file_id"] = attachment_ref
    return {
        "id": node_id,
        "type": "action",
        "label": "ارسال به بله",
        "key": "send_bale",
        "position": {"x": 460, "y": y},
        "config": config,
    }


def _chain(*node_ids: str) -> List[Dict[str, str]]:
    links: List[Dict[str, str]] = []
    for src, dst in zip(node_ids, node_ids[1:]):
        links.append({"source": src, "target": dst})
    return links


def _graph(nodes: List[Dict[str, Any]], connections: List[Dict[str, Any]]) -> Dict[str, Any]:
    return {"nodes": nodes, "connections": connections}


def _sample(
    *,
    title: str,
    short: str,
    long_text: str,
    tags: List[str],
    workflow_data: Dict[str, Any],
) -> Dict[str, Any]:
    return {
        "title": title,
        "short_description": short,
        "long_description": long_text,
        "tags": tags,
        "version_label": "1.0.0",
        "workflow_data": workflow_data,
    }


def starter_workflow_samples() -> List[Dict[str, Any]]:
    sales_msg = (
        "فاکتور فروش جدید\n"
        "شماره: $tr.invoice_number\n"
        "مشتری: $tr.customer_name\n"
        "مبلغ: $tr.total_amount"
    )
    purchase_msg = (
        "فاکتور خرید ثبت شد\n"
        "شماره: $tr.invoice_number\n"
        "تأمین‌کننده: $tr.customer_name\n"
        "مبلغ: $tr.total_amount"
    )
    money_msg = (
        "مبلغ: $tr.amount\n"
        "طرف حساب: $tr.person_name\n"
        "روش: $tr.payment_method\n"
        "شرح: $tr.description"
    )
    check_msg = (
        "چک شماره $tr.check_number\n"
        "مبلغ: $tr.amount\n"
        "سررسید: $tr.due_date\n"
        "روز مانده: $tr.days_until_due\n"
        "طرف حساب: $tr.person_name"
    )
    samples = [
        _sample(
            title="فاکتور فروش جدید به مدیر",
            short="با ثبت فاکتور فروش، اعلان داخلی و پیام بله با شماره، مشتری و مبلغ ارسال می‌شود.",
            long_text=_BALE_NOTE,
            tags=["فروش", "فاکتور", "اعلان"],
            workflow_data=_graph(
                [
                    _trigger("tr", "فاکتور فروش جدید", "invoice.sales.created"),
                    _notify("notify", "فاکتور فروش جدید", sales_msg),
                    _bale("bale", sales_msg),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="فاکتور فروش بالاتر از سقف",
            short="فقط اگر مبلغ فاکتور فروش از سقف تعیین‌شده بیشتر باشد به مدیر خبر می‌دهد.",
            long_text=(
                "سقف پیش‌فرض ۱۰۰٬۰۰۰٬۰۰۰ به واحد ارز سند است. بعد از نصب، در نود شرط مقدار right_value را با سقف کسب‌وکار خود عوض کنید. "
                + _BALE_NOTE
            ),
            tags=["فروش", "فاکتور", "شرط"],
            workflow_data=_graph(
                [
                    _trigger("tr", "فاکتور فروش جدید", "invoice.sales.created"),
                    {
                        "id": "gate",
                        "type": "condition",
                        "key": "condition.if",
                        "label": "مبلغ به سقف رسیده",
                        "position": {"x": 360, "y": 140},
                        "config": {
                            "condition_type": "simple",
                            "left_value": "$tr.total_amount",
                            "operator": ">=",
                            "right_value": 100000000,
                        },
                    },
                    _notify("notify", "فاکتور فروش پرمبلغ", sales_msg, priority="high", y=40),
                    _bale("bale", sales_msg, y=260),
                ],
                [
                    {"source": "tr", "target": "gate"},
                    {"source": "gate", "target": "notify", "sourceHandle": "true"},
                    {"source": "notify", "target": "bale"},
                ],
            ),
        ),
        _sample(
            title="فاکتور خرید ثبت شد",
            short="با ثبت فاکتور خرید، شماره، طرف حساب و مبلغ برای مدیر ارسال می‌شود.",
            long_text=_BALE_NOTE,
            tags=["خرید", "فاکتور", "اعلان"],
            workflow_data=_graph(
                [
                    _trigger("tr", "فاکتور خرید جدید", "invoice.purchase.created"),
                    _notify("notify", "فاکتور خرید ثبت شد", purchase_msg),
                    _bale("bale", purchase_msg),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="دریافت وجه",
            short="بعد از ثبت سند دریافت، مبلغ و طرف حساب اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["مالی", "دریافت"],
            workflow_data=_graph(
                [
                    _trigger("tr", "دریافت جدید", "receipt_payment.created", {"type": "receipt"}),
                    _notify("notify", "دریافت وجه", "دریافت جدید\n" + money_msg),
                    _bale("bale", "دریافت جدید\n" + money_msg),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="پرداخت ثبت شد",
            short="بعد از ثبت سند پرداخت، مبلغ و طرف حساب اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["مالی", "پرداخت"],
            workflow_data=_graph(
                [
                    _trigger("tr", "پرداخت جدید", "receipt_payment.created", {"type": "payment"}),
                    _notify("notify", "پرداخت ثبت شد", "پرداخت جدید\n" + money_msg),
                    _bale("bale", "پرداخت جدید\n" + money_msg),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="سررسید چک دریافتی",
            short="از سه روز مانده به سررسید چک دریافتی، شماره، مبلغ و طرف حساب اعلام می‌شود.",
            long_text="چک‌های پاس‌شده یا باطل اجرا نمی‌شوند. " + _BALE_NOTE,
            tags=["مالی", "چک"],
            workflow_data=_graph(
                [
                    _trigger(
                        "tr",
                        "سررسید چک دریافتی",
                        "check.due_date",
                        {"check_type": "received", "days_before": 3},
                    ),
                    _notify("notify", "سررسید چک دریافتی", "چک دریافتی نزدیک سررسید است\n" + check_msg, priority="high"),
                    _bale("bale", "چک دریافتی نزدیک سررسید است\n" + check_msg),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="سررسید چک پرداختی",
            short="از سه روز مانده به سررسید چک پرداختی، شماره، مبلغ و طرف حساب اعلام می‌شود.",
            long_text="چک‌های پاس‌شده یا باطل اجرا نمی‌شوند. " + _BALE_NOTE,
            tags=["مالی", "چک"],
            workflow_data=_graph(
                [
                    _trigger(
                        "tr",
                        "سررسید چک پرداختی",
                        "check.due_date",
                        {"check_type": "paid", "days_before": 3},
                    ),
                    _notify("notify", "سررسید چک پرداختی", "چک پرداختی نزدیک سررسید است\n" + check_msg, priority="high"),
                    _bale("bale", "چک پرداختی نزدیک سررسید است\n" + check_msg),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="سند هزینه یا درآمد",
            short="فقط برای سند هزینه و درآمد اعلان می‌شود؛ دریافت، پرداخت و سایر اسناد رد می‌شوند.",
            long_text=_BALE_NOTE,
            tags=["حسابداری", "هزینه", "درآمد"],
            workflow_data=_graph(
                [
                    _trigger("tr", "سند جدید", "document.created"),
                    {
                        "id": "gate",
                        "type": "condition",
                        "key": "condition.if",
                        "label": "هزینه یا درآمد",
                        "position": {"x": 340, "y": 140},
                        "config": {
                            "condition_type": "simple",
                            "left_value": "$tr.document_type",
                            "operator": "in",
                            "right_value": ["expense", "income"],
                        },
                    },
                    _notify(
                        "notify",
                        "سند هزینه یا درآمد",
                        "سند $tr.document_type_label\nمبلغ: $tr.total_amount\nطرف حساب: $tr.person_name\nشرح: $tr.description",
                    ),
                    _bale(
                        "bale",
                        "سند $tr.document_type_label\nمبلغ: $tr.total_amount\nطرف حساب: $tr.person_name\nشرح: $tr.description",
                    ),
                ],
                [
                    {"source": "tr", "target": "gate"},
                    {"source": "gate", "target": "notify", "sourceHandle": "true"},
                    {"source": "notify", "target": "bale"},
                ],
            ),
        ),
        _sample(
            title="موجودی به حد هشدار رسید",
            short="وقتی موجودی کالا به نقطهٔ سفارش یا کمتر برسد، نام کالا و مقدار فعلی اعلام می‌شود.",
            long_text="فقط کالاهایی که نقطهٔ سفارش دارند این تریگر را روشن می‌کنند. " + _BALE_NOTE,
            tags=["انبار", "موجودی"],
            workflow_data=_graph(
                [
                    _trigger("tr", "موجودی کم", "inventory.low"),
                    _notify(
                        "notify",
                        "موجودی کم",
                        "کالا: $tr.product_name\nموجودی: $tr.current_quantity\nحد سفارش: $tr.min_quantity",
                        priority="high",
                    ),
                    _bale(
                        "bale",
                        "موجودی کم شد\nکالا: $tr.product_name\nموجودی: $tr.current_quantity\nحد سفارش: $tr.min_quantity",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="کالای نزدیک انقضا",
            short="برای لات نزدیک انقضا یا منقضی، نام کالا، کد لات و تاریخ انقضا اعلام می‌شود.",
            long_text="کالا باید ردیابی تاریخ انقضا داشته باشد. " + _BALE_NOTE,
            tags=["انبار", "انقضا"],
            workflow_data=_graph(
                [
                    _trigger("tr", "نزدیک انقضا", "inventory.expires_soon"),
                    _notify(
                        "notify",
                        "کالای نزدیک انقضا",
                        "کالا: $tr.product_name\nلات: $tr.lot_code\nانقضا: $tr.expiry_date\nروز مانده: $tr.remaining_days",
                        priority="high",
                    ),
                    _bale(
                        "bale",
                        "کالای نزدیک انقضا\nکالا: $tr.product_name\nلات: $tr.lot_code\nانقضا: $tr.expiry_date\nروز مانده: $tr.remaining_days",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="پیام جدید بازدیدکننده در چت وب",
            short="متن پیام بازدیدکننده، نام و شناسهٔ گفتگو برای مدیر در بله ارسال می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "چت"],
            workflow_data=_graph(
                [
                    _trigger("tr", "پیام بازدیدکننده", "crm.chat.message.received"),
                    _bale(
                        "bale",
                        "پیام جدید در چت وب\n"
                        "فرستنده: $tr.visitor_name\n"
                        "تلفن: $tr.visitor_phone\n"
                        "پیام: $tr.message\n"
                        "شناسه گفتگو: $tr.conversation_id\n"
                        "صفحه: $tr.page_url",
                        y=140,
                    ),
                ],
                _chain("tr", "bale"),
            ),
        ),
        _sample(
            title="شروع مکالمه چت وب",
            short="به محض ثبت فرم بازدیدکننده، نام، تلفن و صفحهٔ بازدید برای مدیر ارسال می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "چت"],
            workflow_data=_graph(
                [
                    _trigger("tr", "شروع مکالمه چت", "crm.chat.conversation.started"),
                    _bale(
                        "bale",
                        "مکالمه جدید در چت وب\n"
                        "بازدیدکننده: $tr.visitor_name\n"
                        "تلفن: $tr.visitor_phone\n"
                        "ایمیل: $tr.visitor_email\n"
                        "شناسه گفتگو: $tr.conversation_id\n"
                        "صفحه: $tr.page_url",
                        y=140,
                    ),
                ],
                _chain("tr", "bale"),
            ),
        ),
        _sample(
            title="سرنخ جدید",
            short="با ساخت سرنخ، نام، کد، موبایل و شرکت در اعلان داخلی و بله می‌آید.",
            long_text=_BALE_NOTE,
            tags=["CRM", "سرنخ"],
            workflow_data=_graph(
                [
                    _trigger("tr", "سرنخ جدید", "crm.lead.created"),
                    _notify(
                        "notify",
                        "سرنخ جدید",
                        "سرنخ: $tr.name\nکد: $tr.lead_code\nموبایل: $tr.mobile\nشرکت: $tr.company_name",
                    ),
                    _bale(
                        "bale",
                        "سرنخ جدید\nنام: $tr.name\nکد: $tr.lead_code\nموبایل: $tr.mobile\nشرکت: $tr.company_name",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="معامله برنده شد",
            short="فقط وقتی فرصت فروش برنده بسته شود، عنوان و مبلغ اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "فروش"],
            workflow_data=_graph(
                [
                    _trigger("tr", "بستن معامله برنده", "crm.deal.closed", {"won_only": True}),
                    _notify(
                        "notify",
                        "معامله برنده شد",
                        "معامله: $tr.title\nمبلغ: $tr.amount\nمشتری: $tr.person_name",
                        priority="high",
                    ),
                    _bale("bale", "معامله برنده شد\nعنوان: $tr.title\nمبلغ: $tr.amount\nمشتری: $tr.person_name"),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="مشتری جدید",
            short="با ثبت شخص از نوع مشتری، نام و راه‌های تماس برای کاربر ثبت‌کننده و بله ارسال می‌شود.",
            long_text=_BALE_NOTE,
            tags=["اشخاص", "مشتری"],
            workflow_data=_graph(
                [
                    _trigger("tr", "مشتری جدید", "person.created", {"person_type": "customer"}),
                    _notify(
                        "notify",
                        "مشتری جدید",
                        "مشتری: $tr.name\nموبایل: $tr.mobile\nایمیل: $tr.email",
                    ),
                    _bale("bale", "مشتری جدید\nنام: $tr.name\nموبایل: $tr.mobile\nایمیل: $tr.email"),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="برگشت از فروش",
            short="فقط وقتی سند برگشت از فروش ثبت شود، شماره، مشتری و مبلغ اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["فروش", "برگشت"],
            workflow_data=_graph(
                [
                    _trigger(
                        "tr",
                        "برگشت از فروش",
                        "invoice.created",
                        {"invoice_type": "invoice_sales_return"},
                    ),
                    _notify(
                        "notify",
                        "برگشت از فروش",
                        "برگشت از فروش\nشماره: $tr.invoice_number\nمشتری: $tr.customer_name\nمبلغ: $tr.total_amount",
                        priority="high",
                    ),
                    _bale(
                        "bale",
                        "برگشت از فروش\nشماره: $tr.invoice_number\nمشتری: $tr.customer_name\nمبلغ: $tr.total_amount",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="ویرایش فاکتور فروش",
            short="بعد از ویرایش فاکتور فروش، شماره، مشتری و مبلغ جدید اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["فروش", "فاکتور"],
            workflow_data=_graph(
                [
                    _trigger("tr", "ویرایش فاکتور فروش", "invoice.sales.updated"),
                    _notify(
                        "notify",
                        "فاکتور فروش ویرایش شد",
                        "فاکتور فروش ویرایش شد\nشماره: $tr.invoice_number\nمشتری: $tr.customer_name\nمبلغ: $tr.total_amount",
                    ),
                    _bale(
                        "bale",
                        "فاکتور فروش ویرایش شد\nشماره: $tr.invoice_number\nمشتری: $tr.customer_name\nمبلغ: $tr.total_amount",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="ویرایش دریافت یا پرداخت",
            short="بعد از ویرایش سند دریافت یا پرداخت، نوع، مبلغ و طرف حساب اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["مالی", "دریافت", "پرداخت"],
            workflow_data=_graph(
                [
                    _trigger("tr", "ویرایش دریافت یا پرداخت", "receipt_payment.updated"),
                    _notify(
                        "notify",
                        "سند دریافت یا پرداخت ویرایش شد",
                        "$tr.type_label ویرایش شد\nمبلغ: $tr.amount\nطرف حساب: $tr.person_name\nشرح: $tr.description",
                    ),
                    _bale(
                        "bale",
                        "$tr.type_label ویرایش شد\nمبلغ: $tr.amount\nطرف حساب: $tr.person_name\nشرح: $tr.description",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="انتقال بین صندوق و بانک",
            short="فقط سند انتقال وجه بین صندوق، بانک یا تنخواه اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["مالی", "خزانه‌داری"],
            workflow_data=_graph(
                [
                    _trigger("tr", "انتقال وجه", "document.created", {"document_type": "transfer"}),
                    _notify(
                        "notify",
                        "انتقال وجه",
                        "انتقال $tr.document_type_label\nمبلغ: $tr.total_amount\nشرح: $tr.description",
                    ),
                    _bale(
                        "bale",
                        "انتقال وجه\nمبلغ: $tr.total_amount\nشرح: $tr.description",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="تغییر مرحله سرنخ",
            short="با جابه‌جایی سرنخ بین مراحل، نام سرنخ و مرحلهٔ قبل و بعد اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "سرنخ"],
            workflow_data=_graph(
                [
                    _trigger("tr", "تغییر مرحله سرنخ", "crm.lead.stage_changed"),
                    _notify(
                        "notify",
                        "مرحله سرنخ عوض شد",
                        "سرنخ: $tr.name\nاز: $tr.old_stage_name\nبه: $tr.new_stage_name",
                    ),
                    _bale("bale", "مرحله سرنخ عوض شد\nسرنخ: $tr.name\nاز: $tr.old_stage_name\nبه: $tr.new_stage_name"),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="تغییر مرحله فرصت فروش",
            short="با جابه‌جایی فرصت فروش، عنوان، مبلغ و مرحلهٔ قبل و بعد اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "فروش"],
            workflow_data=_graph(
                [
                    _trigger("tr", "تغییر مرحله فرصت", "crm.deal.stage_changed"),
                    _notify(
                        "notify",
                        "مرحله فرصت فروش عوض شد",
                        "فرصت: $tr.title\nمبلغ: $tr.amount\nاز: $tr.old_stage_name\nبه: $tr.new_stage_name",
                    ),
                    _bale(
                        "bale",
                        "مرحله فرصت فروش عوض شد\nفرصت: $tr.title\nمبلغ: $tr.amount\nاز: $tr.old_stage_name\nبه: $tr.new_stage_name",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="معامله باخت",
            short="فقط وقتی فرصت فروش بازنده بسته شود، عنوان و مبلغ اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "فروش"],
            workflow_data=_graph(
                [
                    _trigger("tr", "بستن معامله بازنده", "crm.deal.closed", {"lost_only": True}),
                    _notify(
                        "notify",
                        "معامله باخت",
                        "معامله بازنده شد\nعنوان: $tr.title\nمبلغ: $tr.amount\nمشتری: $tr.person_name",
                    ),
                    _bale("bale", "معامله بازنده شد\nعنوان: $tr.title\nمبلغ: $tr.amount\nمشتری: $tr.person_name"),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="سرنخ تبدیل شد",
            short="وقتی سرنخ به مشتری تبدیل شود، نام سرنخ و نام شخص ساخته‌شده اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "سرنخ"],
            workflow_data=_graph(
                [
                    _trigger("tr", "تبدیل سرنخ", "crm.lead.converted"),
                    _notify(
                        "notify",
                        "سرنخ به مشتری تبدیل شد",
                        "سرنخ: $tr.name\nکد: $tr.lead_code\nمشتری: $tr.person_name",
                        priority="high",
                    ),
                    _bale("bale", "سرنخ به مشتری تبدیل شد\nسرنخ: $tr.name\nکد: $tr.lead_code\nمشتری: $tr.person_name"),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="مسئول سرنخ عوض شد",
            short="با تغییر مسئول سرنخ، نام سرنخ و نام مسئول جدید اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "سرنخ"],
            workflow_data=_graph(
                [
                    _trigger("tr", "تخصیص سرنخ", "crm.lead.assigned"),
                    _notify(
                        "notify",
                        "مسئول سرنخ عوض شد",
                        "سرنخ: $tr.name\nکد: $tr.lead_code\nمسئول جدید: $tr.assigned_to_user_name",
                    ),
                    _bale(
                        "bale",
                        "مسئول سرنخ عوض شد\nسرنخ: $tr.name\nکد: $tr.lead_code\nمسئول جدید: $tr.assigned_to_user_name",
                    ),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="فرصت فروش جدید",
            short="با ساخت فرصت فروش، عنوان، مبلغ و مشتری اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "فروش"],
            workflow_data=_graph(
                [
                    _trigger("tr", "فرصت فروش جدید", "crm.deal.created"),
                    _notify(
                        "notify",
                        "فرصت فروش جدید",
                        "فرصت: $tr.title\nمبلغ: $tr.amount\nمشتری: $tr.person_name",
                    ),
                    _bale("bale", "فرصت فروش جدید\nعنوان: $tr.title\nمبلغ: $tr.amount\nمشتری: $tr.person_name"),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="تأمین‌کننده جدید",
            short="با ثبت شخص از نوع تأمین‌کننده، نام و راه‌های تماس اعلام می‌شود.",
            long_text=_BALE_NOTE,
            tags=["اشخاص", "خرید"],
            workflow_data=_graph(
                [
                    _trigger("tr", "تأمین‌کننده جدید", "person.created", {"person_type": "supplier"}),
                    _notify(
                        "notify",
                        "تأمین‌کننده جدید",
                        "تأمین‌کننده: $tr.name\nموبایل: $tr.mobile\nایمیل: $tr.email",
                    ),
                    _bale("bale", "تأمین‌کننده جدید\nنام: $tr.name\nموبایل: $tr.mobile\nایمیل: $tr.email"),
                ],
                _chain("tr", "notify", "bale"),
            ),
        ),
        _sample(
            title="مکالمه چت بسته شد",
            short="وقتی وضعیت مکالمهٔ چت وب حل‌شده شود، نام بازدیدکننده و شناسهٔ گفتگو ارسال می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "چت"],
            workflow_data=_graph(
                [
                    _trigger("tr", "حل شدن مکالمه", "crm.chat.conversation.resolved"),
                    _bale(
                        "bale",
                        "مکالمه چت بسته شد\n"
                        "بازدیدکننده: $tr.visitor_name\n"
                        "تلفن: $tr.visitor_phone\n"
                        "شناسه گفتگو: $tr.conversation_id",
                        y=140,
                    ),
                ],
                _chain("tr", "bale"),
            ),
        ),
        _sample(
            title="مکالمه چت دوباره باز شد",
            short="اگر مکالمهٔ حل‌شده دوباره باز شود، نام بازدیدکننده و وضعیت جدید ارسال می‌شود.",
            long_text=_BALE_NOTE,
            tags=["CRM", "چت"],
            workflow_data=_graph(
                [
                    _trigger("tr", "بازگشایی مکالمه", "crm.chat.conversation.reopened"),
                    _bale(
                        "bale",
                        "مکالمه چت دوباره باز شد\n"
                        "بازدیدکننده: $tr.visitor_name\n"
                        "تلفن: $tr.visitor_phone\n"
                        "وضعیت جدید: $tr.new_status\n"
                        "شناسه گفتگو: $tr.conversation_id",
                        y=140,
                    ),
                ],
                _chain("tr", "bale"),
            ),
        ),
        _sample(
            title="پشتیبان روزانه و ارسال فایل به بله",
            short="هر روز ساعت ۸ به وقت تهران فایل پشتیبان کسب‌وکار ساخته و در بله فرستاده می‌شود.",
            long_text=(
                "ورک‌فلو را بعد از نصب فعال کنید. "
                + _BALE_NOTE
                + " ساعت را از نود زمان‌بندی می‌توانید عوض کنید."
            ),
            tags=["پشتیبان", "نگهداری"],
            workflow_data=_graph(
                [
                    _trigger(
                        "tr",
                        "هر روز ساعت ۸",
                        "scheduled",
                        {
                            "schedule_mode": "simple",
                            "simple_repeat": "daily",
                            "simple_time": "08:00",
                            "timezone": "Asia/Tehran",
                        },
                    ),
                    {
                        "id": "backup",
                        "type": "action",
                        "label": "ساخت پشتیبان",
                        "key": "business_backup",
                        "position": {"x": 420, "y": 80},
                        "config": {"action_type": "business_backup", "upload_to_ftp": False},
                    },
                    _bale(
                        "bale",
                        "پشتیبان روزانه کسب‌وکار آماده است.",
                        y=260,
                        attachment_ref="$backup.file_id",
                    ),
                ],
                _chain("tr", "backup", "bale"),
            ),
        ),
    ]
    return samples


def publish_starter_samples(db: Session, *, business_id: int, user_id: int) -> List[Dict[str, Any]]:
    """ورک‌فلو منبع را پیش‌نویس می‌سازد و بسته را در مخزن منتشر می‌کند. تکرار عنوان منتشرشده را رد می‌کند."""
    results: List[Dict[str, Any]] = []
    for sample in starter_workflow_samples():
        title = sample["title"]
        existing = db.execute(
            select(WorkflowMarketplacePackage).where(
                WorkflowMarketplacePackage.publisher_business_id == int(business_id),
                WorkflowMarketplacePackage.title == title,
                WorkflowMarketplacePackage.status == WorkflowMarketplacePackageStatus.PUBLISHED.value,
            )
        ).scalar_one_or_none()
        if existing is not None:
            results.append({"title": title, "action": "skipped", "package_id": existing.id})
            continue

        wf = db.execute(
            select(Workflow).where(Workflow.business_id == int(business_id), Workflow.name == title)
        ).scalar_one_or_none()
        if wf is None:
            wf = Workflow(
                business_id=int(business_id),
                name=title,
                description=sample["short_description"],
                status=WorkflowStatus.DRAFT,
                workflow_data=sample["workflow_data"],
                settings=None,
                created_by_user_id=int(user_id),
            )
            db.add(wf)
            db.commit()
            db.refresh(wf)
        else:
            wf.description = sample["short_description"]
            wf.workflow_data = sample["workflow_data"]
            wf.status = WorkflowStatus.DRAFT
            wf.updated_at = wf.updated_at
            db.commit()
            db.refresh(wf)

        pkg = publish_package(
            db,
            business_id=int(business_id),
            user_id=int(user_id),
            workflow_id=int(wf.id),
            title=title,
            short_description=sample["short_description"],
            long_description=sample["long_description"],
            tags=sample["tags"],
            version_label=sample["version_label"],
            changelog="نمونهٔ آماده برای همهٔ کسب‌وکارها",
        )
        results.append({"title": title, "action": "published", "package_id": pkg.id, "workflow_id": wf.id})
    return results
