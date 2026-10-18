from __future__ import annotations

import json
import logging
import re
from datetime import date
from typing import Any, Dict, List

from sqlalchemy import and_, func, or_
from sqlalchemy.orm import Session

from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.currency import BusinessCurrency, Currency
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person, PersonType
from adapters.db.models.quick_sales_payment_button import QuickSalesPaymentButton
from adapters.db.models.quick_sales_settings import QuickSalesSetting
from app.core.responses import ApiError
from app.core.transaction_lock import acquire_transaction_lock
from app.services.person_group_service import assert_assignable_person_group
from app.services.person_service import (
    calculate_person_balances_by_currency,
    invalidate_persons_cache,
)
from app.services.user_ui_preferences_service import (
    get_quick_sales_payment_shortcuts,
    save_quick_sales_payment_shortcuts,
)

logger = logging.getLogger(__name__)

DEFAULT_SHARE_CHANNELS: List[str] = ["sms", "native"]
VALID_SHARE_CHANNEL_CODES = frozenset({"sms", "email", "native"})
DEFAULT_SHARE_EXPIRY_HOURS = 168
MIN_SHARE_EXPIRY_HOURS = 1
MAX_SHARE_EXPIRY_HOURS = 720

PAYMENT_BUTTON_TARGETS = frozenset({"cash_register", "bank", "person"})
PAYMENT_BUTTON_SCOPES = frozenset({"business", "user"})
PAYMENT_BUTTON_RESERVED_SHORTCUTS = frozenset(
    {"ENTER", "ESCAPE", "DELETE", "BACKSPACE", "F5", "+", "-"}
)
PAYMENT_BUTTON_SHORTCUT_PLATFORMS = frozenset({"windows", "web"})
PAYMENT_BUTTON_WEB_RESERVED_SHORTCUTS = frozenset(
    {
        "CTRL+D",
        "CTRL+F",
        "CTRL+H",
        "CTRL+J",
        "CTRL+L",
        "CTRL+N",
        "CTRL+P",
        "CTRL+R",
        "CTRL+S",
        "CTRL+T",
        "CTRL+U",
        "CTRL+W",
        "CTRL+SHIFT+N",
        "CTRL+SHIFT+T",
    }
)
MAX_PAYMENT_BUTTONS_PER_SCOPE = 30
PAYMENT_BUTTON_SHORTCUT_DISABLED = "__DISABLED__"


def get_quick_sales_customer_balance(
    db: Session,
    *,
    business_id: int,
    person_id: int,
    currency_id: int,
    as_of_date: date,
    fiscal_year_id: int | None = None,
) -> Dict[str, Any]:
    """Return the selected customer's native-currency balance for quick sales."""
    person = (
        db.query(Person)
        .filter(Person.id == int(person_id), Person.business_id == int(business_id))
        .first()
    )
    if not person:
        raise ApiError("PERSON_NOT_FOUND", "شخص یافت نشد", http_status=404)

    currency = (
        db.query(Currency)
        .join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
        .filter(
            Currency.id == int(currency_id),
            BusinessCurrency.business_id == int(business_id),
        )
        .first()
    )
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "ارز انتخاب‌شده یافت نشد", http_status=404)

    if fiscal_year_id is None:
        fiscal_year = (
            db.query(FiscalYear)
            .filter(
                FiscalYear.business_id == int(business_id),
                FiscalYear.is_last == True,  # noqa: E712
            )
            .first()
        )
        fiscal_year_id = int(fiscal_year.id) if fiscal_year else None

    breakdown = calculate_person_balances_by_currency(
        db,
        int(person_id),
        fiscal_year_id=fiscal_year_id,
        as_of_date=as_of_date,
    )
    selected = next(
        (
            row
            for row in breakdown.get("balances", [])
            if int(row.get("currency_id") or 0) == int(currency_id)
        ),
        None,
    )
    balance = float((selected or {}).get("balance") or 0)
    if balance > 0:
        status = "بستانکار"
    elif balance < 0:
        status = "بدهکار"
    else:
        status = "تسویه"
    return {
        "person_id": int(person_id),
        "currency_id": int(currency_id),
        "as_of_date": as_of_date.isoformat(),
        "fiscal_year_id": fiscal_year_id,
        "balance": balance,
        "status": status,
        "currency_code": getattr(currency, "code", None),
        "currency_title": getattr(currency, "title", None),
        "currency_symbol": getattr(currency, "symbol", None),
        "decimal_places": int(getattr(currency, "decimal_places", 2) or 2),
    }


def _normalize_payment_button_shortcut(
    value: Any,
    *,
    platform: str = "windows",
) -> str | None:
    if platform not in PAYMENT_BUTTON_SHORTCUT_PLATFORMS:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_PLATFORM_INVALID",
            "پلتفرم میانبر نامعتبر است",
            http_status=400,
        )
    shortcut = str(value or "").strip().upper().replace(" ", "")
    if not shortcut:
        return None
    if len(shortcut) > 32:
        raise ApiError("PAYMENT_BUTTON_SHORTCUT_INVALID", "میانبر بیش از حد طولانی است", http_status=400)
    if shortcut in PAYMENT_BUTTON_RESERVED_SHORTCUTS:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_RESERVED",
            "این کلید در فروش سریع یا مرورگر رزرو شده است",
            http_status=400,
        )
    if platform == "web":
        if shortcut in PAYMENT_BUTTON_WEB_RESERVED_SHORTCUTS:
            raise ApiError(
                "PAYMENT_BUTTON_SHORTCUT_RESERVED",
                "این ترکیب توسط مرورگر رزرو شده است",
                http_status=400,
            )
        parts = shortcut.split("+")
        modifiers = parts[:-1]
        if (
            not re.fullmatch(r"(?:(?:CTRL|ALT|SHIFT)\+)+(?:[A-Z0-9])", shortcut)
            or not any(modifier in {"CTRL", "ALT"} for modifier in modifiers)
        ):
            raise ApiError(
                "PAYMENT_BUTTON_SHORTCUT_INVALID",
                "میانبر وب باید ترکیبی مانند Alt+1 یا Ctrl+Alt+R باشد",
                http_status=400,
            )
        return shortcut
    if not re.fullmatch(
        r"(?:F(?:[1-9]|1[0-2])|(?:(?:CTRL|ALT|SHIFT)\+)+(?:[A-Z0-9]|F(?:[1-9]|1[0-2])))",
        shortcut,
    ):
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_INVALID",
            "میانبر باید یکی از کلیدهای F یا ترکیبی مانند Alt+1 باشد",
            http_status=400,
        )
    return shortcut


def _payment_button_target(
    db: Session,
    business_id: int,
    target_type: str,
    target_id: Any,
) -> tuple[Any, str]:
    try:
        parsed_id = int(target_id)
    except (TypeError, ValueError) as exc:
        raise ApiError("PAYMENT_BUTTON_TARGET_REQUIRED", "مقصد پرداخت الزامی است", http_status=400) from exc

    if target_type == "cash_register":
        target = (
            db.query(CashRegister)
            .filter(
                CashRegister.id == parsed_id,
                CashRegister.business_id == int(business_id),
                CashRegister.is_active == True,  # noqa: E712
            )
            .first()
        )
        name = getattr(target, "name", None)
    elif target_type == "bank":
        target = (
            db.query(BankAccount)
            .filter(
                BankAccount.id == parsed_id,
                BankAccount.business_id == int(business_id),
                BankAccount.is_active == True,  # noqa: E712
            )
            .first()
        )
        name = getattr(target, "name", None)
    elif target_type == "person":
        target = (
            db.query(Person)
            .filter(Person.id == parsed_id, Person.business_id == int(business_id))
            .first()
        )
        name = getattr(target, "alias_name", None)
    else:
        raise ApiError("PAYMENT_BUTTON_TARGET_TYPE_INVALID", "نوع مقصد پرداخت نامعتبر است", http_status=400)

    if not target:
        raise ApiError("PAYMENT_BUTTON_TARGET_NOT_FOUND", "مقصد پرداخت یافت نشد یا غیرفعال است", http_status=404)
    return target, str(name or "مقصد پرداخت")


def _payment_button_target_id(row: QuickSalesPaymentButton) -> int:
    if row.target_type == "cash_register":
        return int(row.cash_register_id)
    if row.target_type == "bank":
        return int(row.bank_account_id)
    return int(row.person_id)


def _payment_button_to_dict(db: Session, row: QuickSalesPaymentButton) -> Dict[str, Any]:
    target, target_name = _payment_button_target(
        db, row.business_id, row.target_type, _payment_button_target_id(row)
    )
    # برای شخص، خود نام شخص روی دکمه نمایش داده می‌شود تا عنوان مبهمی مثل «کارت شخصی» نسازیم.
    label = target_name if row.target_type == "person" else (row.label or target_name)
    return {
        "id": int(row.id),
        "business_id": int(row.business_id),
        "scope": row.scope,
        "owner_user_id": int(row.owner_user_id) if row.owner_user_id else None,
        "target_type": row.target_type,
        "target_id": _payment_button_target_id(row),
        "target_name": target_name,
        "target_currency_id": (
            int(target.currency_id)
            if row.target_type in {"cash_register", "bank"}
            else None
        ),
        "label": label,
        # Shared-button defaults are stored by platform on the button row.
        # Personal choices live in user_ui_preferences and are resolved below.
        "default_shortcuts": {
            "windows": (
                _normalize_payment_button_shortcut(row.shortcut)
                if row.scope == "business"
                else None
            ),
            "web": (
                _normalize_payment_button_shortcut(
                    row.web_shortcut,
                    platform="web",
                )
                if row.scope == "business"
                else None
            ),
        },
        "legacy_user_shortcut": (
            _normalize_payment_button_shortcut(row.shortcut)
            if row.scope == "user"
            else None
        ),
        "position": int(row.position),
        "is_active": bool(row.is_active),
        "is_system": False,
    }


def _resolve_user_payment_shortcuts(
    buttons: List[Dict[str, Any]],
    shortcuts: Dict[str, str],
    *,
    platform: str = "windows",
    prune_stale: bool = True,
) -> tuple[List[Dict[str, Any]], Dict[str, str]]:
    """Resolve personal override > business default > no shortcut.

    Personal shortcuts claim keys first. This keeps an existing personal choice
    deterministic if a manager later assigns the same key as a business default.
    The conflicting inherited default is disabled for that user and is reported
    to the UI instead of allowing two buttons to react to one key press.
    """
    visible_keys = {str(button["id"]) for button in buttons}
    stored = {
        str(key): str(value)
        for key, value in shortcuts.items()
        if not prune_stale or str(key) in visible_keys
    }
    claimed: Dict[str, str] = {}

    for button in buttons:
        key = str(button["id"])
        assigned = stored.get(key)
        if not assigned or assigned == PAYMENT_BUTTON_SHORTCUT_DISABLED:
            continue
        normalized = _normalize_payment_button_shortcut(
            assigned,
            platform=platform,
        )
        if normalized and normalized not in claimed:
            claimed[normalized] = key

    for button in buttons:
        key = str(button["id"])
        default_shortcuts = button.get("default_shortcuts") or {}
        default_shortcut = _normalize_payment_button_shortcut(
            default_shortcuts.get(platform)
            if default_shortcuts
            else button.get("default_shortcut")
            if platform == "windows"
            else None,
            platform=platform,
        )
        assigned = stored.get(key)
        user_shortcut = None
        effective_shortcut = None
        source = "none"
        conflict = False

        if assigned == PAYMENT_BUTTON_SHORTCUT_DISABLED:
            source = "disabled"
        elif assigned:
            user_shortcut = _normalize_payment_button_shortcut(
                assigned,
                platform=platform,
            )
            if user_shortcut and claimed.get(user_shortcut) == key:
                effective_shortcut = user_shortcut
                source = "user"
            else:
                source = "user"
                conflict = True
        elif default_shortcut:
            if default_shortcut not in claimed:
                claimed[default_shortcut] = key
                effective_shortcut = default_shortcut
                source = "business"
            else:
                source = "business"
                conflict = True

        button["default_shortcut"] = default_shortcut
        button["user_shortcut"] = user_shortcut
        button["user_shortcut_disabled"] = (
            assigned == PAYMENT_BUTTON_SHORTCUT_DISABLED
        )
        button["effective_shortcut"] = effective_shortcut
        button["shortcut_source"] = source
        button["shortcut_conflict"] = conflict
        # Backward-compatible alias consumed by older quick-sales clients.
        button["shortcut"] = effective_shortcut

    return buttons, stored


def _assert_user_payment_shortcut_available(
    buttons: List[Dict[str, Any]],
    *,
    shortcut: str | None,
    platform: str = "windows",
    exclude_button_key: str | None = None,
) -> None:
    if not shortcut:
        return
    for button in buttons:
        button_key = str(button["id"])
        assigned = (
            (button.get("shortcut_profiles") or {}).get(platform) or {}
        ).get("effective_shortcut", button.get("effective_shortcut"))
        if button_key != exclude_button_key and assigned == shortcut:
            raise ApiError(
                "PAYMENT_BUTTON_SHORTCUT_CONFLICT",
                "این میانبر قبلاً برای یک دکمه پرداخت استفاده شده است",
                http_status=409,
            )


def _apply_user_payment_shortcuts(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    buttons: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Resolve Windows and web shortcuts and discard stale preferences."""
    base_buttons = [dict(button) for button in buttons]
    legacy_by_key: Dict[str, str] = {}
    for button in base_buttons:
        legacy = button.pop("legacy_user_shortcut", None)
        if legacy:
            legacy_by_key[str(button["id"])] = legacy

    profiles_by_platform: Dict[str, Dict[str, Dict[str, Any]]] = {}
    for platform in ("windows", "web"):
        stored = get_quick_sales_payment_shortcuts(
            db, user_id, business_id, platform=platform
        )
        migrated = dict(stored)
        if platform == "windows":
            for key, legacy in legacy_by_key.items():
                if key not in migrated:
                    migrated[key] = legacy
        platform_buttons = [dict(button) for button in base_buttons]
        resolved, cleaned = _resolve_user_payment_shortcuts(
            platform_buttons,
            migrated,
            platform=platform,
        )
        profiles_by_platform[platform] = {
            str(button["id"]): {
                "default_shortcut": button.get("default_shortcut"),
                "user_shortcut": button.get("user_shortcut"),
                "user_shortcut_disabled": button.get(
                    "user_shortcut_disabled", False
                ),
                "effective_shortcut": button.get("effective_shortcut"),
                "shortcut_source": button.get("shortcut_source", "none"),
                "shortcut_conflict": button.get("shortcut_conflict", False),
            }
            for button in resolved
        }
        if cleaned != stored:
            save_quick_sales_payment_shortcuts(
                db,
                user_id,
                business_id,
                cleaned,
                platform=platform,
            )

    result: List[Dict[str, Any]] = []
    for button in base_buttons:
        key = str(button["id"])
        profiles = {
            platform: profiles_by_platform[platform][key]
            for platform in ("windows", "web")
        }
        windows = profiles["windows"]
        button["shortcut_profiles"] = profiles
        # Backward-compatible Windows aliases for older clients.
        button.update(windows)
        button["shortcut"] = windows.get("effective_shortcut")
        result.append(button)
    return result


def list_quick_sales_payment_buttons(
    db: Session, business_id: int, user_id: int
) -> List[Dict[str, Any]]:
    rows = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
            or_(
                QuickSalesPaymentButton.scope == "business",
                and_(
                    QuickSalesPaymentButton.scope == "user",
                    QuickSalesPaymentButton.owner_user_id == int(user_id),
                ),
            ),
        )
        .order_by(QuickSalesPaymentButton.position.asc(), QuickSalesPaymentButton.id.asc())
        .all()
    )
    result = [_payment_button_to_dict(db, row) for row in rows]
    if result:
        return _apply_user_payment_shortcuts(
            db,
            business_id=business_id,
            user_id=user_id,
            buttons=result,
        )

    settings = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    register_id = getattr(settings, "default_cash_register_id", None)
    if not register_id:
        return []
    try:
        target, name = _payment_button_target(db, business_id, "cash_register", register_id)
    except ApiError:
        return []
    return _apply_user_payment_shortcuts(db, business_id=business_id, user_id=user_id, buttons=[{
        "id": f"system-cash-{int(register_id)}",
        "business_id": int(business_id),
        "scope": "system",
        "owner_user_id": None,
        "target_type": "cash_register",
        "target_id": int(register_id),
        "target_name": name,
        "target_currency_id": int(target.currency_id),
        "label": name,
        "default_shortcuts": {"windows": None, "web": None},
        "position": 0,
        "is_active": True,
        "is_system": True,
    }])


def set_quick_sales_payment_button_shortcut(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    button_key: str,
    shortcut: Any,
    mode: str | None = None,
    platform: str = "windows",
) -> Dict[str, Any]:
    if platform not in PAYMENT_BUTTON_SHORTCUT_PLATFORMS:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_PLATFORM_INVALID",
            "پلتفرم میانبر نامعتبر است",
            http_status=400,
        )
    key = str(button_key or "").strip()
    visible = list_quick_sales_payment_buttons(db, business_id, user_id)
    button = next((row for row in visible if str(row["id"]) == key), None)
    if button is None:
        raise ApiError(
            "PAYMENT_BUTTON_NOT_FOUND",
            "دکمه پرداخت یافت نشد یا برای این کاربر قابل مشاهده نیست",
            http_status=404,
        )
    requested_mode = str(mode or "").strip().lower()
    if not requested_mode:
        # Compatibility with the first shortcut client: null meant disabled.
        requested_mode = "custom" if shortcut else "disabled"
    if requested_mode not in {"inherit", "custom", "disabled"}:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_MODE_INVALID",
            "حالت میانبر شخصی نامعتبر است",
            http_status=400,
        )
    normalized = (
        _normalize_payment_button_shortcut(shortcut, platform=platform)
        if requested_mode == "custom"
        else None
    )
    if requested_mode == "custom" and not normalized:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_REQUIRED",
            "برای حالت شخصی باید میانبر را وارد کنید",
            http_status=400,
        )
    shortcuts = get_quick_sales_payment_shortcuts(
        db, user_id, business_id, platform=platform
    )
    _assert_user_payment_shortcut_available(
        visible,
        shortcut=normalized,
        platform=platform,
        exclude_button_key=key,
    )
    if requested_mode == "custom":
        shortcuts[key] = normalized
    elif requested_mode == "disabled":
        shortcuts[key] = PAYMENT_BUTTON_SHORTCUT_DISABLED
    else:
        shortcuts.pop(key, None)
    save_quick_sales_payment_shortcuts(
        db, user_id, business_id, shortcuts, platform=platform
    )
    refreshed = list_quick_sales_payment_buttons(db, business_id, user_id)
    result = next(row for row in refreshed if str(row["id"]) == key)
    profile = (result.get("shortcut_profiles") or {}).get(platform) or {}
    return {
        "button_id": button["id"],
        "platform": platform,
        "default_shortcut": profile.get("default_shortcut"),
        "user_shortcut": profile.get("user_shortcut"),
        "effective_shortcut": profile.get("effective_shortcut"),
        "shortcut_source": profile.get("shortcut_source"),
        "shortcut_conflict": profile.get("shortcut_conflict", False),
        "shortcut": profile.get("effective_shortcut"),
    }


def set_quick_sales_payment_button_shortcuts(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    button_key: str,
    platforms: Any,
) -> Dict[str, Any]:
    """Save all requested platform overrides in one database transaction."""
    if not isinstance(platforms, dict) or not platforms:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUTS_INVALID",
            "تنظیمات میانبرها نامعتبر است",
            http_status=400,
        )
    unknown = set(platforms) - PAYMENT_BUTTON_SHORTCUT_PLATFORMS
    if unknown:
        raise ApiError(
            "PAYMENT_BUTTON_SHORTCUT_PLATFORM_INVALID",
            "پلتفرم میانبر نامعتبر است",
            http_status=400,
        )

    profiles: Dict[str, Dict[str, Any]] = {}
    for platform in ("windows", "web"):
        if platform not in platforms:
            continue
        config = platforms[platform]
        if not isinstance(config, dict):
            raise ApiError(
                "PAYMENT_BUTTON_SHORTCUTS_INVALID",
                "تنظیم میانبر هر پلتفرم باید یک شیء معتبر باشد",
                http_status=400,
            )
        profiles[platform] = set_quick_sales_payment_button_shortcut(
            db,
            business_id=business_id,
            user_id=user_id,
            button_key=button_key,
            shortcut=config.get("shortcut"),
            mode=config.get("mode"),
            platform=platform,
        )
    return {"button_id": button_key, "shortcut_profiles": profiles}


def list_quick_sales_payment_default_shortcuts(
    db: Session,
    business_id: int,
) -> List[Dict[str, Any]]:
    rows = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.scope == "business",
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .order_by(QuickSalesPaymentButton.position.asc(), QuickSalesPaymentButton.id.asc())
        .all()
    )
    result: List[Dict[str, Any]] = []
    for row in rows:
        button = _payment_button_to_dict(db, row)
        result.append(
            {
                "button_id": button["id"],
                "label": button["label"],
                "target_type": button["target_type"],
                "target_name": button["target_name"],
                "default_shortcuts": button["default_shortcuts"],
                "default_shortcut": button["default_shortcuts"]["windows"],
            }
        )
    return result


def set_quick_sales_payment_default_shortcuts(
    db: Session,
    *,
    business_id: int,
    items: Any,
) -> List[Dict[str, Any]]:
    if not isinstance(items, list):
        raise ApiError(
            "PAYMENT_BUTTON_DEFAULT_SHORTCUTS_INVALID",
            "فهرست میانبرهای پیش‌فرض نامعتبر است",
            http_status=400,
        )

    normalized_by_id: Dict[int, Dict[str, str | None]] = {}
    used: Dict[str, Dict[str, int]] = {"windows": {}, "web": {}}
    for item in items:
        if not isinstance(item, dict):
            raise ApiError(
                "PAYMENT_BUTTON_DEFAULT_SHORTCUTS_INVALID",
                "هر ردیف میانبر باید یک دکمه معتبر باشد",
                http_status=400,
            )
        try:
            button_id = int(item.get("button_id"))
        except (TypeError, ValueError) as exc:
            raise ApiError(
                "PAYMENT_BUTTON_DEFAULT_SHORTCUTS_INVALID",
                "شناسه دکمه پرداخت نامعتبر است",
                http_status=400,
            ) from exc
        if button_id in normalized_by_id:
            raise ApiError(
                "PAYMENT_BUTTON_DEFAULT_SHORTCUT_DUPLICATE_BUTTON",
                "یک دکمه بیش از یک بار در فهرست ارسال شده است",
                http_status=400,
            )
        raw_shortcuts = item.get("shortcuts")
        if raw_shortcuts is None:
            raw_shortcuts = {"windows": item.get("shortcut")}
        if not isinstance(raw_shortcuts, dict):
            raise ApiError(
                "PAYMENT_BUTTON_DEFAULT_SHORTCUTS_INVALID",
                "ساختار میانبرهای دکمه نامعتبر است",
                http_status=400,
            )
        normalized_by_id[button_id] = {}
        for platform in ("windows", "web"):
            if platform not in raw_shortcuts:
                continue
            normalized = _normalize_payment_button_shortcut(
                raw_shortcuts.get(platform), platform=platform
            )
            if normalized and normalized in used[platform]:
                raise ApiError(
                    "PAYMENT_BUTTON_SHORTCUT_CONFLICT",
                    "یک میانبر برای چند دکمه پرداخت انتخاب شده است",
                    http_status=409,
                )
            if normalized:
                used[platform][normalized] = button_id
            normalized_by_id[button_id][platform] = normalized

    if not normalized_by_id:
        return list_quick_sales_payment_default_shortcuts(db, business_id)

    rows = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.scope == "business",
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
            QuickSalesPaymentButton.id.in_(list(normalized_by_id)),
        )
        .all()
    )
    rows_by_id = {int(row.id): row for row in rows}
    missing = set(normalized_by_id) - set(rows_by_id)
    if missing:
        raise ApiError(
            "PAYMENT_BUTTON_NOT_FOUND",
            "یکی از دکمه‌های مشترک یافت نشد یا متعلق به این کسب‌وکار نیست",
            http_status=404,
        )

    # Include unchanged rows in uniqueness validation so partial API callers
    # cannot accidentally duplicate an existing business default.
    all_rows = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.scope == "business",
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .all()
    )
    all_used: Dict[str, Dict[str, int]] = {"windows": {}, "web": {}}
    for row in all_rows:
        row_id = int(row.id)
        values = {
            "windows": _normalize_payment_button_shortcut(row.shortcut),
            "web": _normalize_payment_button_shortcut(
                row.web_shortcut, platform="web"
            ),
        }
        values.update(normalized_by_id.get(row_id) or {})
        for platform, value in values.items():
            if value and value in all_used[platform]:
                raise ApiError(
                    "PAYMENT_BUTTON_SHORTCUT_CONFLICT",
                    "یک میانبر برای چند دکمه پرداخت انتخاب شده است",
                    http_status=409,
                )
            if value:
                all_used[platform][value] = row_id

    for button_id, shortcut_values in normalized_by_id.items():
        if "windows" in shortcut_values:
            rows_by_id[button_id].shortcut = shortcut_values["windows"]
        if "web" in shortcut_values:
            rows_by_id[button_id].web_shortcut = shortcut_values["web"]
    db.flush()
    return list_quick_sales_payment_default_shortcuts(db, business_id)


def create_quick_sales_payment_button(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    payload: Dict[str, Any],
    can_manage_business: bool,
) -> Dict[str, Any]:
    scope = str(payload.get("scope") or "user").strip().lower()
    if scope not in PAYMENT_BUTTON_SCOPES:
        raise ApiError("PAYMENT_BUTTON_SCOPE_INVALID", "دامنه دکمه نامعتبر است", http_status=400)
    if scope == "business" and not can_manage_business:
        raise ApiError("FORBIDDEN", "مجوز تعریف دکمه مشترک را ندارید", http_status=403)
    target_type = str(payload.get("target_type") or "").strip().lower()
    if target_type not in PAYMENT_BUTTON_TARGETS:
        raise ApiError("PAYMENT_BUTTON_TARGET_TYPE_INVALID", "نوع مقصد پرداخت نامعتبر است", http_status=400)
    target, target_name = _payment_button_target(
        db, business_id, target_type, payload.get("target_id")
    )
    owner_user_id = int(user_id) if scope == "user" else None
    count = (
        db.query(func.count(QuickSalesPaymentButton.id))
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.scope == scope,
            QuickSalesPaymentButton.owner_user_id == owner_user_id,
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .scalar()
        or 0
    )
    if int(count) >= MAX_PAYMENT_BUTTONS_PER_SCOPE:
        raise ApiError("PAYMENT_BUTTON_LIMIT", "حداکثر تعداد دکمه‌های پرداخت ثبت شده است", http_status=400)
    shortcut = _normalize_payment_button_shortcut(payload.get("shortcut"))
    max_position = (
        db.query(func.max(QuickSalesPaymentButton.position))
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.scope == scope,
            QuickSalesPaymentButton.owner_user_id == owner_user_id,
        )
        .scalar()
    )
    label = str(payload.get("label") or "").strip() or target_name
    if target_type == "person":
        label = target_name
    row = QuickSalesPaymentButton(
        business_id=int(business_id),
        scope=scope,
        owner_user_id=owner_user_id,
        target_type=target_type,
        cash_register_id=int(target.id) if target_type == "cash_register" else None,
        bank_account_id=int(target.id) if target_type == "bank" else None,
        person_id=int(target.id) if target_type == "person" else None,
        label=label[:120],
        shortcut=None,
        position=(int(max_position) + 1) if max_position is not None else 0,
        is_active=True,
        created_by_user_id=int(user_id),
    )
    db.add(row)
    db.flush()
    if shortcut:
        set_quick_sales_payment_button_shortcut(
            db,
            business_id=business_id,
            user_id=user_id,
            button_key=str(row.id),
            shortcut=shortcut,
        )
    db.commit()
    db.refresh(row)
    return next(
        button
        for button in list_quick_sales_payment_buttons(db, business_id, user_id)
        if str(button["id"]) == str(row.id)
    )


def update_quick_sales_payment_button(
    db: Session,
    *,
    business_id: int,
    button_id: int,
    user_id: int,
    payload: Dict[str, Any],
    can_manage_business: bool,
) -> Dict[str, Any]:
    row = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.id == int(button_id),
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .first()
    )
    if not row:
        raise ApiError("PAYMENT_BUTTON_NOT_FOUND", "دکمه پرداخت یافت نشد", http_status=404)
    if row.scope == "business" and not can_manage_business:
        raise ApiError("FORBIDDEN", "مجوز ویرایش دکمه مشترک را ندارید", http_status=403)
    if row.scope == "user" and int(row.owner_user_id or 0) != int(user_id):
        raise ApiError("FORBIDDEN", "این دکمه متعلق به کاربر دیگری است", http_status=403)

    requested_scope = str(payload.get("scope") or row.scope).strip().lower()
    if requested_scope not in PAYMENT_BUTTON_SCOPES:
        raise ApiError(
            "PAYMENT_BUTTON_SCOPE_INVALID",
            "دامنه دکمه نامعتبر است",
            http_status=400,
        )
    scope_changed = requested_scope != row.scope
    if scope_changed:
        if not can_manage_business:
            raise ApiError(
                "FORBIDDEN",
                "مجوز تغییر دامنه دکمه پرداخت را ندارید",
                http_status=403,
            )
        target_owner_user_id = int(user_id) if requested_scope == "user" else None
        target_count = (
            db.query(func.count(QuickSalesPaymentButton.id))
            .filter(
                QuickSalesPaymentButton.business_id == int(business_id),
                QuickSalesPaymentButton.scope == requested_scope,
                QuickSalesPaymentButton.owner_user_id == target_owner_user_id,
                QuickSalesPaymentButton.is_active == True,  # noqa: E712
            )
            .scalar()
            or 0
        )
        if int(target_count) >= MAX_PAYMENT_BUTTONS_PER_SCOPE:
            raise ApiError(
                "PAYMENT_BUTTON_LIMIT",
                "حداکثر تعداد دکمه‌های پرداخت ثبت شده است",
                http_status=400,
            )
        max_position = (
            db.query(func.max(QuickSalesPaymentButton.position))
            .filter(
                QuickSalesPaymentButton.business_id == int(business_id),
                QuickSalesPaymentButton.scope == requested_scope,
                QuickSalesPaymentButton.owner_user_id == target_owner_user_id,
                QuickSalesPaymentButton.is_active == True,  # noqa: E712
            )
            .scalar()
        )
        row.scope = requested_scope
        row.owner_user_id = target_owner_user_id
        row.position = (int(max_position) + 1) if max_position is not None else 0

    target_type = str(payload.get("target_type") or row.target_type).strip().lower()
    target_id = payload.get("target_id", _payment_button_target_id(row))
    target, target_name = _payment_button_target(db, business_id, target_type, target_id)
    row.target_type = target_type
    row.cash_register_id = int(target.id) if target_type == "cash_register" else None
    row.bank_account_id = int(target.id) if target_type == "bank" else None
    row.person_id = int(target.id) if target_type == "person" else None
    row.label = (
        target_name
        if target_type == "person"
        else (str(payload.get("label") or row.label or target_name).strip() or target_name)[:120]
    )
    if "position" in payload and not scope_changed:
        row.position = max(0, int(payload.get("position") or 0))
    db.flush()
    if "shortcut" in payload:
        set_quick_sales_payment_button_shortcut(
            db,
            business_id=business_id,
            user_id=user_id,
            button_key=str(row.id),
            shortcut=payload.get("shortcut"),
        )
    db.commit()
    db.refresh(row)
    return next(
        button
        for button in list_quick_sales_payment_buttons(db, business_id, user_id)
        if str(button["id"]) == str(row.id)
    )


def delete_quick_sales_payment_button(
    db: Session,
    *,
    business_id: int,
    button_id: int,
    user_id: int,
    can_manage_business: bool,
) -> None:
    row = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.id == int(button_id),
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .first()
    )
    if not row:
        raise ApiError("PAYMENT_BUTTON_NOT_FOUND", "دکمه پرداخت یافت نشد", http_status=404)
    if row.scope == "business" and not can_manage_business:
        raise ApiError("FORBIDDEN", "مجوز حذف دکمه مشترک را ندارید", http_status=403)
    if row.scope == "user" and int(row.owner_user_id or 0) != int(user_id):
        raise ApiError("FORBIDDEN", "این دکمه متعلق به کاربر دیگری است", http_status=403)
    row.is_active = False
    shortcuts = get_quick_sales_payment_shortcuts(db, user_id, business_id)
    if shortcuts.pop(str(row.id), None) is not None:
        save_quick_sales_payment_shortcuts(db, user_id, business_id, shortcuts)
    db.commit()


def reorder_quick_sales_payment_buttons(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    button_ids: List[Any],
    can_manage_business: bool,
) -> List[Dict[str, Any]]:
    """ترتیب مؤثر دکمه‌های مشترک و شخصی کاربر را ذخیره می‌کند."""
    try:
        ordered_ids = [int(value) for value in button_ids]
    except (TypeError, ValueError) as exc:
        raise ApiError(
            "PAYMENT_BUTTON_ORDER_INVALID",
            "ترتیب دکمه‌های پرداخت نامعتبر است",
            http_status=400,
        ) from exc
    if len(ordered_ids) != len(set(ordered_ids)):
        raise ApiError(
            "PAYMENT_BUTTON_ORDER_INVALID",
            "شناسه تکراری در ترتیب دکمه‌ها وجود دارد",
            http_status=400,
        )
    rows = (
        db.query(QuickSalesPaymentButton)
        .filter(
            QuickSalesPaymentButton.business_id == int(business_id),
            QuickSalesPaymentButton.id.in_(ordered_ids),
            QuickSalesPaymentButton.is_active == True,  # noqa: E712
        )
        .all()
    )
    by_id = {int(row.id): row for row in rows}
    if set(by_id) != set(ordered_ids):
        raise ApiError(
            "PAYMENT_BUTTON_NOT_FOUND",
            "یکی از دکمه‌های پرداخت یافت نشد",
            http_status=404,
        )
    for row in rows:
        if row.scope == "business" and not can_manage_business:
            raise ApiError(
                "FORBIDDEN",
                "مجوز تغییر ترتیب دکمه‌های مشترک را ندارید",
                http_status=403,
            )
        if row.scope == "user" and int(row.owner_user_id or 0) != int(user_id):
            raise ApiError("FORBIDDEN", "این دکمه متعلق به کاربر دیگری است", http_status=403)
    for position, button_id in enumerate(ordered_ids):
        by_id[button_id].position = position
    db.commit()
    return list_quick_sales_payment_buttons(db, business_id, user_id)


def normalize_default_share_channels(value: Any) -> List[str]:
    """نرمال‌سازی لیست کانال‌های اشتراک‌گذاری."""
    if value is None:
        return list(DEFAULT_SHARE_CHANNELS)
    parsed = value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return list(DEFAULT_SHARE_CHANNELS)
    if not isinstance(parsed, list):
        return list(DEFAULT_SHARE_CHANNELS)
    channels = [str(c).strip().lower() for c in parsed if str(c).strip()]
    filtered = [c for c in channels if c in VALID_SHARE_CHANNEL_CODES]
    return filtered or list(DEFAULT_SHARE_CHANNELS)


def normalize_share_expiry_hours(value: Any) -> int:
    try:
        hours = int(value)
    except (TypeError, ValueError):
        return DEFAULT_SHARE_EXPIRY_HOURS
    return max(MIN_SHARE_EXPIRY_HOURS, min(MAX_SHARE_EXPIRY_HOURS, hours))


def _share_settings_from_obj(obj: QuickSalesSetting | None) -> Dict[str, Any]:
    if obj is None:
        return {
            "default_share_online_payment": True,
            "default_share_gateway_id": None,
            "default_share_channels": list(DEFAULT_SHARE_CHANNELS),
            "default_share_expiry_hours": DEFAULT_SHARE_EXPIRY_HOURS,
        }
    return {
        "default_share_online_payment": bool(getattr(obj, "default_share_online_payment", True)),
        "default_share_gateway_id": (
            int(obj.default_share_gateway_id) if obj.default_share_gateway_id else None
        ),
        "default_share_channels": normalize_default_share_channels(obj.default_share_channels),
        "default_share_expiry_hours": normalize_share_expiry_hours(
            getattr(obj, "default_share_expiry_hours", DEFAULT_SHARE_EXPIRY_HOURS)
        ),
    }


def _validate_share_gateway_id(db: Session, business_id: int, gateway_id: int) -> None:
    from adapters.db.models.payment_gateway import BusinessPaymentGateway, PaymentGateway

    gw = (
        db.query(PaymentGateway)
        .filter(PaymentGateway.id == int(gateway_id), PaymentGateway.is_active == True)  # noqa: E712
        .first()
    )
    if not gw:
        raise ApiError("GATEWAY_NOT_FOUND", "درگاه پرداخت یافت نشد یا غیرفعال است", http_status=404)
    links = (
        db.query(BusinessPaymentGateway)
        .filter(
            BusinessPaymentGateway.business_id == int(business_id),
            BusinessPaymentGateway.is_active == True,  # noqa: E712
        )
        .all()
    )
    if links:
        allowed = {int(lg.gateway_id) for lg in links}
        if int(gateway_id) not in allowed:
            raise ApiError(
                "GATEWAY_NOT_LINKED",
                "این درگاه برای این کسب‌وکار فعال نیست",
                http_status=400,
            )


def get_quick_sales_settings(db: Session, business_id: int) -> Dict[str, Any]:
    """دریافت تنظیمات فروش سریع یک کسب‌وکار"""
    obj = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    
    # دریافت کسب‌وکار برای دسترسی به ارز پیش‌فرض
    business = db.query(Business).filter(Business.id == int(business_id)).first()
    business_default_currency_id = business.default_currency_id if business else None
    
    if not obj:
        # بازگشت مقادیر پیش‌فرض
        return {
            "business_id": int(business_id),
            "default_anonymous_customer_id": None,
            "auto_create_anonymous_customer": True,
            "anonymous_customer_name": "مشتری ناشناس",
            "quick_customer_group_id": None,
            "default_warehouse_id": None,
            "default_cash_register_id": None,
            "default_currency_id": business_default_currency_id,
            "default_price_list_id": None,
            "auto_print": False,
            "print_template_id": None,
            "print_paper_size": "80mm",
            "enable_warehouse_document": True,
            "warehouse_document_type": "posted",
            "auto_post_warehouse": True,
            "show_inventory": True,
            "enable_stock_shortage_override": False,
            "auto_create_payment_document": True,
            "show_purchase_price": False,
            **_share_settings_from_obj(None),
        }
    
    # اگر ارز پیش‌فرض در تنظیمات تنظیم نشده باشد، از ارز پیش‌فرض کسب‌وکار استفاده می‌کنیم
    currency_id = int(obj.default_currency_id) if obj.default_currency_id else business_default_currency_id
    
    return {
        "business_id": int(business_id),
        "default_anonymous_customer_id": int(obj.default_anonymous_customer_id) if obj.default_anonymous_customer_id else None,
        "auto_create_anonymous_customer": bool(obj.auto_create_anonymous_customer),
        "anonymous_customer_name": obj.anonymous_customer_name if obj.anonymous_customer_name else "مشتری ناشناس",
        "quick_customer_group_id": int(obj.quick_customer_group_id) if obj.quick_customer_group_id else None,
        "default_warehouse_id": int(obj.default_warehouse_id) if obj.default_warehouse_id else None,
        "default_cash_register_id": int(obj.default_cash_register_id) if obj.default_cash_register_id else None,
        "default_currency_id": currency_id,
        "default_price_list_id": int(obj.default_price_list_id) if obj.default_price_list_id else None,
        "auto_print": bool(obj.auto_print),
        "print_template_id": int(obj.print_template_id) if obj.print_template_id else None,
        "print_paper_size": (getattr(obj, "print_paper_size", None) or "80mm"),
        "enable_warehouse_document": bool(getattr(obj, 'enable_warehouse_document', True)),
        "warehouse_document_type": str(getattr(obj, 'warehouse_document_type', 'posted')),
        "auto_post_warehouse": bool(obj.auto_post_warehouse),
        "show_inventory": bool(obj.show_inventory),
        "enable_stock_shortage_override": bool(
            getattr(obj, "enable_stock_shortage_override", False)
        ),
        "auto_create_payment_document": bool(obj.auto_create_payment_document),
        "show_purchase_price": bool(obj.show_purchase_price),
        **_share_settings_from_obj(obj),
    }


def update_quick_sales_settings(db: Session, business_id: int, payload: Dict[str, Any], user_id: int | None = None) -> Dict[str, Any]:
    """به‌روزرسانی تنظیمات فروش سریع یک کسب‌وکار"""
    obj = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    
    if not obj:
        obj = QuickSalesSetting(business_id=int(business_id))
        db.add(obj)
    
    # به‌روزرسانی فیلدها
    if "default_anonymous_customer_id" in payload:
        customer_id = payload.get("default_anonymous_customer_id")
        if customer_id is not None:
            # بررسی وجود شخص
            person = db.query(Person).filter(
                and_(
                    Person.id == int(customer_id),
                    Person.business_id == int(business_id),
                    Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
                )
            ).first()
            if not person:
                raise ApiError("PERSON_NOT_FOUND", "مشتری یافت نشد", http_status=404)
        obj.default_anonymous_customer_id = int(customer_id) if customer_id is not None else None
    
    if "auto_create_anonymous_customer" in payload:
        obj.auto_create_anonymous_customer = bool(payload.get("auto_create_anonymous_customer"))
    
    if "anonymous_customer_name" in payload:
        name_data = payload.get("anonymous_customer_name")
        if name_data is not None:
            obj.anonymous_customer_name = str(name_data).strip()
        else:
            obj.anonymous_customer_name = None

    if "quick_customer_group_id" in payload:
        group_id = payload.get("quick_customer_group_id")
        if group_id is not None:
            assert_assignable_person_group(db, int(business_id), int(group_id))
        obj.quick_customer_group_id = int(group_id) if group_id is not None else None
    
    if "default_warehouse_id" in payload:
        warehouse_id = payload.get("default_warehouse_id")
        if warehouse_id is not None:
            from adapters.db.models.warehouse import Warehouse
            warehouse = db.query(Warehouse).filter(
                and_(
                    Warehouse.id == int(warehouse_id),
                    Warehouse.business_id == int(business_id),
                )
            ).first()
            if not warehouse:
                raise ApiError("WAREHOUSE_NOT_FOUND", "انبار یافت نشد", http_status=404)
        obj.default_warehouse_id = int(warehouse_id) if warehouse_id is not None else None
    
    if "default_cash_register_id" in payload:
        cash_register_id = payload.get("default_cash_register_id")
        if cash_register_id is not None:
            from adapters.db.models.cash_register import CashRegister
            cash_register = db.query(CashRegister).filter(
                and_(
                    CashRegister.id == int(cash_register_id),
                    CashRegister.business_id == int(business_id),
                )
            ).first()
            if not cash_register:
                raise ApiError("CASH_REGISTER_NOT_FOUND", "صندوق یافت نشد", http_status=404)
        obj.default_cash_register_id = int(cash_register_id) if cash_register_id is not None else None
    
    if "default_currency_id" in payload:
        currency_id = payload.get("default_currency_id")
        if currency_id is not None:
            business_currency = db.query(BusinessCurrency).filter(
                BusinessCurrency.business_id == int(business_id),
                BusinessCurrency.currency_id == int(currency_id),
            ).first()
            if not business_currency:
                raise ApiError(
                    "BUSINESS_CURRENCY_NOT_FOUND",
                    "این ارز برای کسب‌وکار فعال نیست",
                    http_status=400,
                )
        obj.default_currency_id = int(currency_id) if currency_id is not None else None
    
    if "default_price_list_id" in payload:
        price_list_id = payload.get("default_price_list_id")
        if price_list_id is not None:
            from adapters.db.models.price_list import PriceList
            price_list = db.query(PriceList).filter(
                and_(
                    PriceList.id == int(price_list_id),
                    PriceList.business_id == int(business_id),
                )
            ).first()
            if not price_list:
                raise ApiError("PRICE_LIST_NOT_FOUND", "لیست قیمت یافت نشد", http_status=404)
        obj.default_price_list_id = int(price_list_id) if price_list_id is not None else None
    
    if "auto_print" in payload:
        obj.auto_print = bool(payload.get("auto_print"))
    
    if "print_template_id" in payload:
        template_id = payload.get("print_template_id")
        if template_id is not None:
            from adapters.db.models.report_template import ReportTemplate

            template = db.query(ReportTemplate).filter(
                ReportTemplate.id == int(template_id),
                ReportTemplate.business_id == int(business_id),
                ReportTemplate.module_key == "invoices",
                ReportTemplate.status == "published",
            ).first()
            if template is None:
                raise ApiError(
                    "PRINT_TEMPLATE_NOT_FOUND",
                    "قالب چاپ منتشرشده متعلق به این کسب‌وکار نیست",
                    http_status=400,
                )
        obj.print_template_id = int(template_id) if template_id is not None else None

    if "print_paper_size" in payload:
        from app.services.pdf.page_size import is_receipt_paper

        raw = payload.get("print_paper_size")
        size = str(raw).strip() if raw not in (None, "") else None
        if size and size not in ("A4", "A5", "A6") and not is_receipt_paper(size):
            raise ApiError("INVALID_PAPER_SIZE", "سایز کاغذ چاپ نامعتبر است", http_status=400)
        obj.print_paper_size = size
    
    if "enable_warehouse_document" in payload:
        obj.enable_warehouse_document = bool(payload.get("enable_warehouse_document"))
    
    if "warehouse_document_type" in payload:
        doc_type = payload.get("warehouse_document_type")
        if doc_type not in ("draft", "posted"):
            raise ApiError("INVALID_WAREHOUSE_DOCUMENT_TYPE", "نوع سند حواله باید draft یا posted باشد", http_status=400)
        obj.warehouse_document_type = str(doc_type)
    
    if "auto_post_warehouse" in payload:
        obj.auto_post_warehouse = bool(payload.get("auto_post_warehouse"))
    
    if "show_inventory" in payload:
        obj.show_inventory = bool(payload.get("show_inventory"))

    if "enable_stock_shortage_override" in payload:
        obj.enable_stock_shortage_override = bool(
            payload.get("enable_stock_shortage_override")
        )
    
    if "auto_create_payment_document" in payload:
        obj.auto_create_payment_document = bool(payload.get("auto_create_payment_document"))
    
    if "show_purchase_price" in payload:
        obj.show_purchase_price = bool(payload.get("show_purchase_price"))

    if "default_share_online_payment" in payload:
        obj.default_share_online_payment = bool(payload.get("default_share_online_payment"))

    if "default_share_gateway_id" in payload:
        gateway_id = payload.get("default_share_gateway_id")
        if gateway_id is not None:
            _validate_share_gateway_id(db, business_id, int(gateway_id))
        obj.default_share_gateway_id = int(gateway_id) if gateway_id is not None else None

    if "default_share_channels" in payload:
        obj.default_share_channels = normalize_default_share_channels(payload.get("default_share_channels"))

    if "default_share_expiry_hours" in payload:
        obj.default_share_expiry_hours = normalize_share_expiry_hours(payload.get("default_share_expiry_hours"))
    
    db.flush()
    db.commit()
    return get_quick_sales_settings(db, business_id)


def get_or_create_anonymous_customer(
    db: Session, 
    business_id: int, 
    settings: Dict[str, Any] | None = None
) -> Person:
    """دریافت یا ایجاد مشتری ناشناس"""
    acquire_transaction_lock(db, f"quick_sales_anonymous_customer:{business_id}")
    settings_row = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    if settings is None:
        settings = get_quick_sales_settings(db, business_id)

    # شناسه ذخیره‌شده تنها مرجع تشخیص مشتری سیستمی است. نام نمایشی نباید
    # باعث شود یک مشتری واقعی به اشتباه مشتری ناشناس شناخته شود.
    customer_id = (
        settings_row.default_anonymous_customer_id
        if settings_row is not None
        else settings.get("default_anonymous_customer_id")
    )
    if customer_id:
        customer = db.query(Person).filter(
            and_(
                Person.id == int(customer_id),
                Person.business_id == int(business_id),
                Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
            )
        ).first()
        if customer:
            return customer

    customer_name = settings.get("anonymous_customer_name", "مشتری ناشناس")
    name_fa = str(customer_name) if customer_name else "مشتری ناشناس"

    if settings.get("auto_create_anonymous_customer", True):
        next_code = (
            db.query(func.max(Person.code))
            .filter(Person.business_id == int(business_id))
            .scalar()
            or 0
        ) + 1
        customer = Person(
            business_id=int(business_id),
            code=next_code,
            alias_name=name_fa,
            person_types=json.dumps([PersonType.CUSTOMER.value], ensure_ascii=False),
        )
        db.add(customer)
        db.flush()
        if settings_row is None:
            settings_row = QuickSalesSetting(business_id=int(business_id))
            db.add(settings_row)
        settings_row.default_anonymous_customer_id = customer.id
        db.flush()
        db.commit()
        db.refresh(customer)
        invalidate_persons_cache(int(business_id), fiscal_year_id=None)
        return customer
    
    raise ApiError(
        "ANONYMOUS_CUSTOMER_NOT_SET", 
        "مشتری ناشناس تعریف نشده است. لطفاً در تنظیمات فروش سریع یک مشتری پیش‌فرض انتخاب کنید.",
        http_status=400
    )


def get_configured_anonymous_customer(db: Session, business_id: int) -> Person:
    """Return the explicitly configured anonymous customer without mutation."""
    row = (
        db.query(QuickSalesSetting)
        .filter(QuickSalesSetting.business_id == int(business_id))
        .first()
    )
    customer_id = row.default_anonymous_customer_id if row is not None else None
    if customer_id is not None:
        customer = db.query(Person).filter(
            Person.id == int(customer_id),
            Person.business_id == int(business_id),
            Person.person_types.like(f'%{PersonType.CUSTOMER.value}%'),
        ).first()
        if customer is not None:
            return customer
    raise ApiError(
        "ANONYMOUS_CUSTOMER_NOT_SET",
        "مشتری ناشناس تعریف نشده است",
        http_status=404,
    )
