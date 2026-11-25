"""MCP tools for business AI voice catalog and settings (no STT/TTS audio)."""
from __future__ import annotations

from datetime import datetime

from app.services.ai.ai_mcp_tool_util import mcp_bid, mcp_db, mcp_jsonable, mcp_schema

EMPTY = mcp_schema({})
CATALOG = mcp_schema({"kind": {"type": "string", "enum": ["stt", "tts"]}})
UPDATE = mcp_schema(
    {
        "allow_cloud_audio": {"type": "boolean"},
        "preferred_stt_code": {"type": ["string", "null"], "maxLength": 80},
        "preferred_tts_code": {"type": ["string", "null"], "maxLength": 80},
    }
)


def _public_model(item: dict) -> dict:
    out = dict(item)
    out.pop("extra", None)
    return out


def list_ai_voice_catalog_handler(args, context):
    from app.services.voice.voice_catalog import list_voice_models_for_user

    data = list_voice_models_for_user(
        mcp_db(context),
        business_id=mcp_bid(context),
        kind=args.get("kind"),
    )
    return mcp_jsonable(
        {
            **data,
            "stt": [_public_model(x) for x in (data.get("stt") or [])],
            "tts": [_public_model(x) for x in (data.get("tts") or [])],
        }
    )


def get_business_voice_settings_handler(args, context):
    from adapters.db.repositories.ai_voice_model_repository import (
        AIVoicePolicyRepository,
        BusinessAIVoiceSettingsRepository,
    )
    from app.services.voice.voice_catalog import cloud_audio_allowed, serialize_business_voice_settings

    db = mcp_db(context)
    bid = mcp_bid(context)
    row = BusinessAIVoiceSettingsRepository(db).get_or_create(bid)
    policy = AIVoicePolicyRepository(db).get_or_create()
    out = serialize_business_voice_settings(row)
    out["policy_allow_cloud_audio"] = bool(policy.allow_cloud_audio)
    out["effective_allow_cloud_audio"] = cloud_audio_allowed(db, bid)
    return mcp_jsonable(out)


def update_business_voice_settings_handler(args, context):
    from adapters.db.repositories.ai_voice_model_repository import (
        AIVoicePolicyRepository,
        BusinessAIVoiceSettingsRepository,
    )
    from app.services.voice.voice_catalog import cloud_audio_allowed, serialize_business_voice_settings

    db = mcp_db(context)
    bid = mcp_bid(context)
    ctx = context["user_context"]
    is_admin = bool(ctx.is_superadmin()) if callable(getattr(ctx, "is_superadmin", None)) else bool(getattr(ctx, "is_superadmin", False))
    is_owner = bool(ctx.is_business_owner(bid)) if callable(getattr(ctx, "is_business_owner", None)) else False
    if not (is_admin or is_owner):
        raise ValueError("فقط مالک کسب‌وکار می‌تواند تنظیمات صوت را تغییر دهد")
    row = BusinessAIVoiceSettingsRepository(db).get_or_create(bid)
    policy = AIVoicePolicyRepository(db).get_or_create()
    if "allow_cloud_audio" in args:
        want = bool(args.get("allow_cloud_audio"))
        if want and not policy.allow_cloud_audio and not is_admin:
            raise ValueError("ارسال صوت به ابر در سطح سیستم خاموش است")
        row.allow_cloud_audio = want
    if "preferred_stt_code" in args:
        row.preferred_stt_code = args.get("preferred_stt_code") or None
    if "preferred_tts_code" in args:
        row.preferred_tts_code = args.get("preferred_tts_code") or None
    row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    out = serialize_business_voice_settings(row)
    out["policy_allow_cloud_audio"] = bool(policy.allow_cloud_audio)
    out["effective_allow_cloud_audio"] = cloud_audio_allowed(db, bid)
    return mcp_jsonable(out)


def register_mcp_ops23_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(
        AIFunction(
            name="list_ai_voice_catalog",
            description="کاتالوگ مدل‌های STT/TTS مجاز همین کسب‌وکار بدون کلید ارائه‌دهنده و بدون بایت صدا.",
            parameters_schema=CATALOG,
            handler=list_ai_voice_catalog_handler,
            allowed_roles=roles,
            required_permissions=["settings.join"],
            category="misc",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="get_business_voice_settings",
            description="تنظیمات صوت کسب‌وکار متصل: ابر، مدل ترجیحی STT/TTS. کلید و فایل صدا برنمی‌گردد.",
            parameters_schema=EMPTY,
            handler=get_business_voice_settings_handler,
            allowed_roles=roles,
            required_permissions=["settings.join"],
            category="misc",
            is_readonly=True,
        )
    )
    registry.register(
        AIFunction(
            name="update_business_voice_settings",
            description="ذخیره ترجیح STT/TTS و اجازه ارسال صوت به ابر برای کسب‌وکار متصل؛ فقط مالک. نیازمند تأیید. دیکته و بلندخوانی باینری در MCP نیست.",
            parameters_schema=UPDATE,
            handler=update_business_voice_settings_handler,
            allowed_roles=roles,
            required_permissions=["settings.business"],
            category="misc",
            requires_approval=True,
            risk_level="medium",
            is_readonly=False,
        )
    )
