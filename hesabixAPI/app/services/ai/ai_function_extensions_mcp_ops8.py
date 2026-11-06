"""MCP leftovers: office automation extras, telephony extras, business soft-delete/restore."""
from __future__ import annotations

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_run, mcp_schema, mcp_uid

EMPTY = mcp_schema({})
PAYLOAD = mcp_schema({"payload": {"type": "object"}}, ["payload"])
POS = {"as_position_id": {"type": "integer", "minimum": 1}}
LETTER = mcp_schema({**POS, "letter_id": {"type": "integer", "minimum": 1}}, ["letter_id"])
LETTER_POS = mcp_schema({**POS, "letter_id": {"type": "integer", "minimum": 1}}, ["letter_id", "as_position_id"])
SID = mcp_schema({"secretariat_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["secretariat_id", "payload"])
ORG = mcp_schema({"org_id": {"type": "integer", "minimum": 1}, "payload": {"type": "object"}}, ["org_id", "payload"])
NOTE = mcp_schema({**POS, "letter_id": {"type": "integer", "minimum": 1}, "note": {"type": "string", "maxLength": 2000}}, ["letter_id", "as_position_id"])
DISPATCH = mcp_schema({**POS, "dispatch_id": {"type": "integer", "minimum": 1}}, ["dispatch_id", "as_position_id"])
REF = mcp_schema({**POS, "referral_id": {"type": "integer", "minimum": 1}, "note": {"type": "string", "maxLength": 2000}}, ["referral_id", "as_position_id"])
RULE_ID = mcp_schema({"rule_id": {"type": "integer", "minimum": 1}}, ["rule_id"])
ECE_DIR = mcp_schema({"direction": {"type": "string", "enum": ["in", "out"]}})
ARCH_LETTER = mcp_schema({**POS, "letter_id": {"type": "integer", "minimum": 1}, "folder_id": {"type": "integer", "minimum": 1}}, ["letter_id", "as_position_id"])
DELETE_BIZ = mcp_schema({"deletion_reason": {"type": "string", "maxLength": 500}, "skip_restore_period": {"type": "boolean"}})
CALL_ID = mcp_schema({"call_id": {"type": "integer", "minimum": 1}}, ["call_id"])
DATE_RANGE = mcp_schema({"date_from": {"type": "string"}, "date_to": {"type": "string"}})
PBX_SYNC = mcp_schema(
    {
        "pbx_id": {"type": "integer", "minimum": 1},
        "items": {"type": "array", "maxItems": 200, "items": {"type": "object"}},
    },
    ["pbx_id", "items"],
)
CONTROL = mcp_schema(
    {
        "call_id": {"type": "integer", "minimum": 1},
        "action": {"type": "string", "minLength": 1, "maxLength": 40},
        "target": {"type": ["string", "null"], "maxLength": 64},
    },
    ["call_id", "action"],
)
DLQ = mcp_schema({"dlq_id": {"type": "integer", "minimum": 1}}, ["dlq_id"])


def _lang(context) -> str:
    return str(context.get("locale") or "fa")


def _pid(args) -> int:
    raw = args.get("as_position_id")
    if raw in (None, ""):
        raise ValueError("سمت فعال الزامی است (as_position_id)")
    pid = int(raw)
    if pid < 1:
        raise ValueError("سمت فعال الزامی است (as_position_id)")
    return pid


def _opt_pid(args):
    raw = args.get("as_position_id")
    if raw in (None, ""):
        return None
    pid = int(raw)
    return pid if pid > 0 else None


def _ext():
    from app.services import office_automation_extended_service as ext

    return ext


def update_oa_secretariat_handler(args, context):
    return mcp_jsonable(
        mcp_run(_ext().update_secretariat, mcp_db(context), mcp_bid(context), int(args["secretariat_id"]), args["payload"], mcp_uid(context), lang=_lang(context))
    )


def update_oa_external_org_handler(args, context):
    return mcp_jsonable(
        mcp_run(_ext().update_external_org, mcp_db(context), mcp_bid(context), int(args["org_id"]), args["payload"], mcp_uid(context), lang=_lang(context))
    )


def list_oa_signatures_handler(args, context):
    return mcp_jsonable({"items": mcp_run(_ext().list_signatures, mcp_db(context), mcp_bid(context), mcp_uid(context))})


def upsert_oa_signature_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().upsert_signature, mcp_db(context), mcp_bid(context), mcp_uid(context), args["payload"]))


def list_oa_sign_paths_handler(args, context):
    return mcp_jsonable({"items": mcp_run(_ext().list_sign_path_templates, mcp_db(context), mcp_bid(context), lang=_lang(context))})


def save_oa_sign_path_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().save_sign_path_template, mcp_db(context), mcp_bid(context), args["payload"], mcp_uid(context), lang=_lang(context)))


def reject_oa_letter_sign_handler(args, context):
    return mcp_jsonable(
        mcp_run(_ext().reject_sign_step, mcp_db(context), mcp_bid(context), int(args["letter_id"]), {"note": args.get("note")}, mcp_uid(context), _pid(args), lang=_lang(context))
    )


def acknowledge_oa_dispatch_handler(args, context):
    return mcp_jsonable(
        mcp_run(_ext().acknowledge_dispatch, mcp_db(context), mcp_bid(context), int(args["dispatch_id"]), mcp_uid(context), _pid(args), lang=_lang(context))
    )


def cancel_oa_referral_handler(args, context):
    return mcp_jsonable(
        mcp_run(_ext().cancel_referral, mcp_db(context), mcp_bid(context), int(args["referral_id"]), {"note": args.get("note")}, mcp_uid(context), _pid(args), lang=_lang(context))
    )


def unarchive_oa_letter_handler(args, context):
    return mcp_jsonable(
        mcp_run(_ext().unarchive_letter, mcp_db(context), mcp_bid(context), int(args["letter_id"]), mcp_uid(context), _pid(args), lang=_lang(context))
    )


def list_oa_letter_versions_handler(args, context):
    return mcp_jsonable(
        {
            "items": mcp_run(
                _ext().list_letter_versions,
                mcp_db(context),
                mcp_bid(context),
                int(args["letter_id"]),
                mcp_uid(context),
                _opt_pid(args),
                lang=_lang(context),
                is_admin=False,
            )
        }
    )


def list_oa_ece_messages_handler(args, context):
    rows = mcp_run(_ext().list_ece_messages, mcp_db(context), mcp_bid(context), direction=args.get("direction"))
    items = []
    for row in rows or []:
        item = dict(row)
        item.pop("xml_content", None)
        items.append(item)
    return mcp_jsonable({"items": items})


def list_oa_cartable_rules_handler(args, context):
    return mcp_jsonable({"items": mcp_run(_ext().list_cartable_rules, mcp_db(context), mcp_bid(context))})


def save_oa_cartable_rule_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().save_cartable_rule, mcp_db(context), mcp_bid(context), args["payload"], mcp_uid(context)))


def delete_oa_cartable_rule_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().delete_cartable_rule, mcp_db(context), mcp_bid(context), int(args["rule_id"]), mcp_uid(context)))


def save_oa_archive_folder_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().save_archive_folder, mcp_db(context), mcp_bid(context), args["payload"], mcp_uid(context), lang=_lang(context)))


def archive_oa_letter_to_folder_handler(args, context):
    payload = {"folder_id": args.get("folder_id")}
    return mcp_jsonable(
        mcp_run(_ext().archive_to_folder, mcp_db(context), mcp_bid(context), int(args["letter_id"]), payload, mcp_uid(context), _pid(args), lang=_lang(context))
    )


def get_oa_volume_report_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().volume_report, mcp_db(context), mcp_bid(context)))


def get_oa_performance_report_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().performance_report, mcp_db(context), mcp_bid(context), lang=_lang(context)))


def notify_oa_due_followups_handler(args, context):
    return mcp_jsonable(mcp_run(_ext().notify_due_followups, mcp_db(context), mcp_bid(context)))


def soft_delete_connected_business_handler(args, context):
    from app.services.business_service import delete_business_soft

    return mcp_jsonable(
        mcp_run(
            delete_business_soft,
            mcp_db(context),
            mcp_bid(context),
            mcp_uid(context),
            deletion_reason=args.get("deletion_reason"),
            requested_by=mcp_uid(context),
            skip_restore_period=bool(args.get("skip_restore_period") or False),
        )
    )


def restore_connected_business_handler(args, context):
    from app.services.business_service import restore_business

    return mcp_jsonable(mcp_run(restore_business, mcp_db(context), mcp_bid(context), mcp_uid(context)))


def _tel_plugin(db, bid):
    from app.core.telephony_plugin_dependency import check_telephony_plugin_active

    if not check_telephony_plugin_active(db, int(bid)):
        raise ValueError("افزونه تلفن برای این کسب‌وکار فعال نیست")


def get_telephony_my_context_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    data = mcp_run(svc.get_my_extension_context, db, bid, mcp_uid(context), auth_ctx=context.get("user_context"))
    if isinstance(data, dict):
        data = dict(data)
        data.pop("connector_token", None)
        data.pop("sip_password", None)
        data.pop("secret", None)
    return mcp_jsonable(data)


def list_telephony_assignable_users_handler(args, context):
    from app.services.telephony.telephony_access import list_assignable_users

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable({"items": mcp_run(list_assignable_users, db, bid)})


def list_telephony_team_supervisors_handler(args, context):
    from app.services.telephony.telephony_access import list_team_supervisors

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable({"items": mcp_run(list_team_supervisors, db, bid)})


def sync_telephony_extensions_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(svc.sync_extensions, db, bid, int(args["pbx_id"]), args.get("items") or []))


def get_telephony_screen_pop_handler(args, context):
    from app.services.telephony import telephony_service as svc

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(svc.screen_pop_context, db, bid, int(args["call_id"]), auth_ctx=context.get("user_context")))


def get_telephony_operators_report_handler(args, context):
    from app.services.telephony.reports_service import operators_report

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(operators_report, db, bid, date_from=args.get("date_from"), date_to=args.get("date_to"), auth_ctx=context.get("user_context")))


def get_telephony_person_report_handler(args, context):
    from app.services.telephony.reports_service import by_person_report

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(by_person_report, db, bid, date_from=args.get("date_from"), date_to=args.get("date_to"), auth_ctx=context.get("user_context")))


def get_telephony_extension_report_handler(args, context):
    from app.services.telephony.reports_service import by_extension_report

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(by_extension_report, db, bid, date_from=args.get("date_from"), date_to=args.get("date_to"), auth_ctx=context.get("user_context")))


def get_telephony_live_snapshot_handler(args, context):
    from app.services.telephony.live_service import live_snapshot

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(live_snapshot, db, bid, auth_ctx=context.get("user_context")))


def control_telephony_call_handler(args, context):
    from app.services.telephony.live_service import enqueue_control_command

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(
        mcp_run(
            enqueue_control_command,
            db,
            bid,
            mcp_uid(context),
            command_type=str(args.get("action") or ""),
            auth_ctx=context.get("user_context"),
            call_id=int(args["call_id"]),
            target=args.get("target"),
        )
    )


def get_telephony_ops_metrics_handler(args, context):
    from app.services.telephony.recording_service import metrics_summary

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(metrics_summary, db, bid))


def list_telephony_dead_letters_handler(args, context):
    from app.services.telephony.recording_service import list_dead_letters

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable({"items": mcp_run(list_dead_letters, db, bid)})


def resolve_telephony_dead_letter_handler(args, context):
    from app.services.telephony.recording_service import resolve_dead_letter

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    return mcp_jsonable(mcp_run(resolve_dead_letter, db, bid, int(args["dlq_id"])))


def get_telephony_softphone_health_handler(args, context):
    from app.services.telephony.softphone_service import softphone_health

    db, bid = mcp_db(context), mcp_bid(context)
    _tel_plugin(db, bid)
    data = mcp_run(softphone_health, db, bid, mcp_uid(context))
    if isinstance(data, dict):
        data = dict(data)
        for key in ("sip_password", "password", "secret", "token"):
            data.pop(key, None)
    return mcp_jsonable(data)


def register_mcp_ops8_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(name="update_oa_secretariat", description="ویرایش دبیرخانه اتوماسیون اداری. نیازمند تأیید.", parameters_schema=SID, handler=update_oa_secretariat_handler, allowed_roles=roles, required_permissions=["office_automation.admin"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="update_oa_external_org", description="ویرایش سازمان خارجی مکاتبات. نیازمند تأیید.", parameters_schema=ORG, handler=update_oa_external_org_handler, allowed_roles=roles, required_permissions=["office_automation.admin"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_oa_signatures", description="امضاهای کاربر جاری در اتوماسیون بدون بایت تصویر.", parameters_schema=EMPTY, handler=list_oa_signatures_handler, allowed_roles=roles, required_permissions=["office_automation.view"], category="office_automation", is_readonly=True))
    registry.register(AIFunction(name="upsert_oa_signature", description="ایجاد یا ویرایش امضای کاربر جاری با شناسه فایل موجود. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=upsert_oa_signature_handler, allowed_roles=roles, required_permissions=["office_automation.view"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_oa_sign_paths", description="قالب‌های مسیر امضای نامه.", parameters_schema=EMPTY, handler=list_oa_sign_paths_handler, allowed_roles=roles, required_permissions=["office_automation.view"], category="office_automation", is_readonly=True))
    registry.register(AIFunction(name="save_oa_sign_path", description="ذخیره قالب مسیر امضا. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=save_oa_sign_path_handler, allowed_roles=roles, required_permissions=["office_automation.admin"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="reject_oa_letter_sign", description="رد مرحله جاری امضای نامه. نیازمند تأیید.", parameters_schema=NOTE, handler=reject_oa_letter_sign_handler, allowed_roles=roles, required_permissions=["office_automation.refer"], category="office_automation", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="acknowledge_oa_dispatch", description="رسید ابلاغ نامه برای سمت فعال. نیازمند تأیید.", parameters_schema=DISPATCH, handler=acknowledge_oa_dispatch_handler, allowed_roles=roles, required_permissions=["office_automation.refer"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="cancel_oa_referral", description="لغو ارجاع ارسال‌شده از سمت فعال. نیازمند تأیید.", parameters_schema=REF, handler=cancel_oa_referral_handler, allowed_roles=roles, required_permissions=["office_automation.refer"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="unarchive_oa_letter", description="خروج نامه از بایگانی. نیازمند تأیید.", parameters_schema=LETTER_POS, handler=unarchive_oa_letter_handler, allowed_roles=roles, required_permissions=["office_automation.archive"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="list_oa_letter_versions", description="نسخه‌های ذخیره‌شده یک نامه.", parameters_schema=LETTER, handler=list_oa_letter_versions_handler, allowed_roles=roles, required_permissions=["office_automation.view"], category="office_automation", is_readonly=True))
    registry.register(AIFunction(name="list_oa_ece_messages", description="فهرست پیام‌های ECE وارد و صادر کسب‌وکار متصل.", parameters_schema=ECE_DIR, handler=list_oa_ece_messages_handler, allowed_roles=roles, required_permissions=["office_automation.secretariat"], category="office_automation", is_readonly=True))
    registry.register(AIFunction(name="list_oa_cartable_rules", description="قوانین خودکار کارتابل.", parameters_schema=EMPTY, handler=list_oa_cartable_rules_handler, allowed_roles=roles, required_permissions=["office_automation.admin"], category="office_automation", is_readonly=True))
    registry.register(AIFunction(name="save_oa_cartable_rule", description="ایجاد یا ویرایش قانون کارتابل. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=save_oa_cartable_rule_handler, allowed_roles=roles, required_permissions=["office_automation.admin"], category="office_automation", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="delete_oa_cartable_rule", description="حذف قانون کارتابل. نیازمند تأیید.", parameters_schema=RULE_ID, handler=delete_oa_cartable_rule_handler, allowed_roles=roles, required_permissions=["office_automation.admin"], category="office_automation", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="save_oa_archive_folder", description="ایجاد یا ویرایش پوشه بایگانی. نیازمند تأیید.", parameters_schema=PAYLOAD, handler=save_oa_archive_folder_handler, allowed_roles=roles, required_permissions=["office_automation.archive"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="archive_oa_letter_to_folder", description="بایگانی نامه در پوشه مشخص. نیازمند تأیید.", parameters_schema=ARCH_LETTER, handler=archive_oa_letter_to_folder_handler, allowed_roles=roles, required_permissions=["office_automation.archive"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_oa_volume_report", description="گزارش حجم مکاتبات اتوماسیون.", parameters_schema=EMPTY, handler=get_oa_volume_report_handler, allowed_roles=roles, required_permissions=["office_automation.view"], category="office_automation", is_readonly=True))
    registry.register(AIFunction(name="get_oa_performance_report", description="گزارش عملکرد ارجاع‌های کارتابل.", parameters_schema=EMPTY, handler=get_oa_performance_report_handler, allowed_roles=roles, required_permissions=["office_automation.view"], category="office_automation", is_readonly=True))
    registry.register(AIFunction(name="notify_oa_due_followups", description="ارسال اعلان پیگیری‌های سررسیدشده همین کسب‌وکار. نیازمند تأیید.", parameters_schema=EMPTY, handler=notify_oa_due_followups_handler, allowed_roles=roles, required_permissions=["office_automation.refer"], category="office_automation", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="soft_delete_connected_business", description="حذف نرم کسب‌وکار متصل با بکاپ خودکار؛ فقط مالک. نیازمند تأیید.", parameters_schema=DELETE_BIZ, handler=soft_delete_connected_business_handler, allowed_roles=roles, required_permissions=["settings.business"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="restore_connected_business", description="بازیابی کسب‌وکار حذف‌شده در مهلت ۳۰ روز؛ فقط مالک. نیازمند تأیید.", parameters_schema=EMPTY, handler=restore_connected_business_handler, allowed_roles=roles, required_permissions=["settings.business"], category="business", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_telephony_my_context", description="داخلی و زمینه تلفن کاربر جاری بدون توکن کانکتور.", parameters_schema=EMPTY, handler=get_telephony_my_context_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="list_telephony_assignable_users", description="کاربران قابل اتصال به داخلی تلفن.", parameters_schema=EMPTY, handler=list_telephony_assignable_users_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="list_telephony_team_supervisors", description="ناظران تیم تلفن کسب‌وکار متصل.", parameters_schema=EMPTY, handler=list_telephony_team_supervisors_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="sync_telephony_extensions", description="همگام‌سازی فهرست داخلی‌ها با مرکز تلفن ذخیره‌شده. نیازمند تأیید.", parameters_schema=PBX_SYNC, handler=sync_telephony_extensions_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_telephony_screen_pop", description="زمینه پاپ‌آپ صفحه برای یک تماس.", parameters_schema=CALL_ID, handler=get_telephony_screen_pop_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_telephony_operators_report", description="گزارش عملکرد اپراتورهای تلفن در بازه تاریخ.", parameters_schema=DATE_RANGE, handler=get_telephony_operators_report_handler, allowed_roles=roles, required_permissions=["telephony.reports"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_telephony_person_report", description="گزارش تماس‌ها به‌تفکیک شخص.", parameters_schema=DATE_RANGE, handler=get_telephony_person_report_handler, allowed_roles=roles, required_permissions=["telephony.reports"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_telephony_extension_report", description="گزارش تماس‌ها به‌تفکیک داخلی.", parameters_schema=DATE_RANGE, handler=get_telephony_extension_report_handler, allowed_roles=roles, required_permissions=["telephony.reports"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="get_telephony_live_snapshot", description="نمای زنده صف و تماس‌های جاری بدون رسانه.", parameters_schema=EMPTY, handler=get_telephony_live_snapshot_handler, allowed_roles=roles, required_permissions=["telephony.live_monitor"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="control_telephony_call", description="ارسال فرمان کنترل تماس به سانترال. نیازمند تأیید.", parameters_schema=CONTROL, handler=control_telephony_call_handler, allowed_roles=roles, required_permissions=["telephony.control_calls"], category="crm", requires_approval=True, risk_level="high", is_readonly=False))
    registry.register(AIFunction(name="get_telephony_ops_metrics", description="متریک عملیاتی ضبط و صف تلفن بدون فایل صوت.", parameters_schema=EMPTY, handler=get_telephony_ops_metrics_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="list_telephony_dead_letters", description="صف مرده رویدادهای تلفن.", parameters_schema=EMPTY, handler=list_telephony_dead_letters_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", is_readonly=True))
    registry.register(AIFunction(name="resolve_telephony_dead_letter", description="بستن یک آیتم صف مرده تلفن. نیازمند تأیید.", parameters_schema=DLQ, handler=resolve_telephony_dead_letter_handler, allowed_roles=roles, required_permissions=["telephony.manage"], category="crm", requires_approval=True, risk_level="medium", is_readonly=False))
    registry.register(AIFunction(name="get_telephony_softphone_health", description="سلامت سافت‌فون کاربر جاری بدون رمز SIP.", parameters_schema=EMPTY, handler=get_telephony_softphone_health_handler, allowed_roles=roles, required_permissions=["telephony.view"], category="crm", is_readonly=True))
