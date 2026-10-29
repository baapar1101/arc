"""MCP tools for daily treasury ops: bank, cash, petty cash, and opening balance."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

_MAX_BULK = 100
_MAX_LINES = 200


def _schema(properties: Dict[str, Any], required: list[str]) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": False,
    }


def _raise_service(exc: BaseException) -> None:
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


def _unique_ids(raw: List[Any], *, field: str) -> List[int]:
    ids = [int(value) for value in raw]
    if len(ids) != len(set(ids)):
        raise ValueError(f"{field} نباید شناسهٔ تکراری داشته باشد")
    return ids


def _require_perm(ctx, db, business_id: int, section: str, action: str, label: str) -> None:
    from app.core.permissions import has_business_permission_for_business

    if not has_business_permission_for_business(ctx, db, int(business_id), section, action):
        raise ValueError(f"مجوز {label} لازم است")


def _tenant_row(db, model, pk: int, business_id: int, missing: str):
    row = db.query(model).filter(model.id == int(pk), model.business_id == int(business_id)).first()
    if not row:
        raise ValueError(missing)
    return row


def _code_name_currency(*, extra: Optional[Dict[str, Any]] = None, update: bool = False) -> Dict[str, Any]:
    props: Dict[str, Any] = {
        "code": {
            "type": ["string", "null"],
            "minLength": 3,
            "maxLength": 50,
            "description": "کد عددی حداقل ۳ رقم؛ اگر خالی باشد خودکار تولید می‌شود",
        },
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "description": {"type": ["string", "null"], "maxLength": 500},
        "currency_id": {"type": "integer", "minimum": 1, "description": "شناسه ارز از list_currencies"},
        "is_active": {"type": "boolean"},
        "is_default": {"type": "boolean"},
    }
    if extra:
        props.update(extra)
    if update:
        for key in ("name", "currency_id"):
            if key in props and key != "code":
                continue
        props["name"] = {"type": "string", "minLength": 1, "maxLength": 255}
        props["currency_id"] = {"type": "integer", "minimum": 1}
    return props


BANK_EXTRA = {
    "branch": {"type": ["string", "null"], "maxLength": 255},
    "account_number": {"type": ["string", "null"], "maxLength": 50},
    "sheba_number": {"type": ["string", "null"], "maxLength": 30},
    "card_number": {"type": ["string", "null"], "maxLength": 20},
    "owner_name": {"type": ["string", "null"], "maxLength": 255},
    "pos_number": {"type": ["string", "null"], "maxLength": 50},
    "payment_id": {"type": ["string", "null"], "maxLength": 100},
}
CASH_EXTRA = {
    "payment_switch_number": {"type": ["string", "null"], "maxLength": 50},
    "payment_terminal_number": {"type": ["string", "null"], "maxLength": 50},
    "merchant_id": {"type": ["string", "null"], "maxLength": 50},
}

CREATE_BANK_ACCOUNT_SCHEMA = _schema(_code_name_currency(extra=BANK_EXTRA), ["name", "currency_id"])
UPDATE_BANK_ACCOUNT_SCHEMA = _schema(
    {"bank_account_id": {"type": "integer", "minimum": 1}, **_code_name_currency(extra=BANK_EXTRA, update=True)},
    ["bank_account_id"],
)
CREATE_CASH_REGISTER_SCHEMA = _schema(_code_name_currency(extra=CASH_EXTRA), ["name", "currency_id"])
UPDATE_CASH_REGISTER_SCHEMA = _schema(
    {"cash_register_id": {"type": "integer", "minimum": 1}, **_code_name_currency(extra=CASH_EXTRA, update=True)},
    ["cash_register_id"],
)
CREATE_PETTY_CASH_SCHEMA = _schema(_code_name_currency(), ["name", "currency_id"])
UPDATE_PETTY_CASH_SCHEMA = _schema(
    {"petty_cash_id": {"type": "integer", "minimum": 1}, **_code_name_currency(update=True)},
    ["petty_cash_id"],
)

_ACCOUNT_LINE = {
    "type": "object",
    "properties": {
        "account_id": {"type": "integer", "minimum": 1},
        "person_id": {"type": ["integer", "null"], "minimum": 1},
        "bank_account_id": {"type": ["integer", "null"], "minimum": 1},
        "cash_register_id": {"type": ["integer", "null"], "minimum": 1},
        "petty_cash_id": {"type": ["integer", "null"], "minimum": 1},
        "debit": {"type": "number", "minimum": 0},
        "credit": {"type": "number", "minimum": 0},
        "description": {"type": ["string", "null"], "maxLength": 500},
    },
    "required": ["account_id"],
    "additionalProperties": False,
}
_INVENTORY_LINE = {
    "type": "object",
    "properties": {
        "product_id": {"type": "integer", "minimum": 1},
        "warehouse_id": {"type": "integer", "minimum": 1},
        "quantity": {"type": "number", "exclusiveMinimum": 0},
        "cost_price": {"type": ["number", "null"], "minimum": 0},
        "description": {"type": ["string", "null"], "maxLength": 500},
    },
    "required": ["product_id", "warehouse_id", "quantity"],
    "additionalProperties": False,
}
OPENING_BALANCE_WRITE_SCHEMA = _schema(
    {
        "fiscal_year_id": {"type": "integer", "minimum": 1, "description": "اگر خالی باشد سال مالی جاری استفاده می‌شود"},
        "document_date": {"type": "string", "format": "date"},
        "currency_id": {"type": "integer", "minimum": 1},
        "description": {"type": ["string", "null"], "maxLength": 1000},
        "account_lines": {"type": "array", "maxItems": _MAX_LINES, "items": _ACCOUNT_LINE},
        "inventory_lines": {"type": "array", "maxItems": _MAX_LINES, "items": _INVENTORY_LINE},
        "inventory_account_id": {"type": ["integer", "null"], "minimum": 1},
        "auto_balance_to_equity": {"type": "boolean"},
        "equity_account_id": {"type": ["integer", "null"], "minimum": 1},
    },
    ["currency_id"],
)
OPENING_BALANCE_FY_SCHEMA = _schema(
    {"fiscal_year_id": {"type": "integer", "minimum": 1}},
    [],
)


def _id_schema(field: str) -> Dict[str, Any]:
    return _schema({field: {"type": "integer", "minimum": 1}}, [field])


def _bulk_ids_schema(field: str) -> Dict[str, Any]:
    return _schema(
        {
            field: {
                "type": "array",
                "minItems": 1,
                "maxItems": _MAX_BULK,
                "uniqueItems": True,
                "items": {"type": "integer", "minimum": 1},
            }
        },
        [field],
    )


GET_BANK_ACCOUNT_SCHEMA = _id_schema("bank_account_id")
DELETE_BANK_ACCOUNT_SCHEMA = GET_BANK_ACCOUNT_SCHEMA
BULK_DELETE_BANK_ACCOUNTS_SCHEMA = _bulk_ids_schema("bank_account_ids")
GET_CASH_REGISTER_SCHEMA = _id_schema("cash_register_id")
DELETE_CASH_REGISTER_SCHEMA = GET_CASH_REGISTER_SCHEMA
BULK_DELETE_CASH_REGISTERS_SCHEMA = _bulk_ids_schema("cash_register_ids")
GET_PETTY_CASH_SCHEMA = _id_schema("petty_cash_id")
DELETE_PETTY_CASH_SCHEMA = GET_PETTY_CASH_SCHEMA
BULK_DELETE_PETTY_CASH_SCHEMA = _bulk_ids_schema("petty_cash_ids")


def _opening_payload(args: Dict[str, Any]) -> Dict[str, Any]:
    inventory = []
    for line in args.get("inventory_lines") or []:
        info: Dict[str, Any] = {"movement": "in", "warehouse_id": int(line["warehouse_id"])}
        if line.get("cost_price") is not None:
            info["cost_price"] = line.get("cost_price")
        inventory.append(
            {
                "product_id": int(line["product_id"]),
                "quantity": line.get("quantity"),
                "description": line.get("description"),
                "extra_info": info,
            }
        )
    return {
        "fiscal_year_id": args.get("fiscal_year_id"),
        "document_date": args.get("document_date"),
        "currency_id": args.get("currency_id"),
        "description": args.get("description"),
        "account_lines": list(args.get("account_lines") or []),
        "inventory_lines": inventory,
        "inventory_account_id": args.get("inventory_account_id"),
        "auto_balance_to_equity": bool(args.get("auto_balance_to_equity", False)),
        "equity_account_id": args.get("equity_account_id"),
    }


def get_bank_account_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.bank_account import BankAccount
    from app.services.bank_account_service import get_bank_account_by_id

    db, bid = context["db"], int(context["business_id"])
    pk = int(args["bank_account_id"])
    _tenant_row(db, BankAccount, pk, bid, "حساب بانکی در کسب‌وکار متصل پیدا نشد")
    return get_bank_account_by_id(db, pk)


def create_bank_account_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.bank_account_service import create_bank_account

    try:
        return create_bank_account(context["db"], int(context["business_id"]), dict(args))
    except Exception as exc:
        _raise_service(exc)


def update_bank_account_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.bank_account import BankAccount
    from app.services.bank_account_service import update_bank_account

    db, bid = context["db"], int(context["business_id"])
    pk = int(args["bank_account_id"])
    _tenant_row(db, BankAccount, pk, bid, "حساب بانکی در کسب‌وکار متصل پیدا نشد")
    data = {key: value for key, value in args.items() if key != "bank_account_id"}
    try:
        result = update_bank_account(db, pk, data)
    except Exception as exc:
        _raise_service(exc)
    if result is None:
        raise ValueError("حساب بانکی در کسب‌وکار متصل پیدا نشد")
    return result


def delete_bank_account_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.bank_account import BankAccount
    from app.services.bank_account_service import delete_bank_account

    db, bid = context["db"], int(context["business_id"])
    _require_perm(context["user_context"], db, bid, "bank_accounts", "delete", "bank_accounts.delete")
    pk = int(args["bank_account_id"])
    _tenant_row(db, BankAccount, pk, bid, "حساب بانکی در کسب‌وکار متصل پیدا نشد")
    success, error = delete_bank_account(db, pk)
    if not success:
        raise ValueError(error or "حذف حساب بانکی انجام نشد")
    return {"deleted": True, "bank_account_id": pk}


def bulk_delete_bank_accounts_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.bank_account import BankAccount
    from app.services.bank_account_service import bulk_delete_bank_accounts

    db, bid = context["db"], int(context["business_id"])
    ids = _unique_ids(args["bank_account_ids"], field="bank_account_ids")
    _require_perm(context["user_context"], db, bid, "bank_accounts", "delete", "bank_accounts.delete")
    found = db.query(BankAccount).filter(BankAccount.id.in_(ids), BankAccount.business_id == bid).all()
    if len(found) != len(ids):
        raise ValueError("همهٔ شناسه‌ها باید متعلق به کسب‌وکار متصل باشند")
    return bulk_delete_bank_accounts(db, bid, ids)


def get_cash_register_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.cash_register import CashRegister
    from app.services.cash_register_service import get_cash_register_by_id

    db, bid = context["db"], int(context["business_id"])
    pk = int(args["cash_register_id"])
    _tenant_row(db, CashRegister, pk, bid, "صندوق در کسب‌وکار متصل پیدا نشد")
    return get_cash_register_by_id(db, pk)


def create_cash_register_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.cash_register_service import create_cash_register

    try:
        return create_cash_register(context["db"], int(context["business_id"]), dict(args))
    except Exception as exc:
        _raise_service(exc)


def update_cash_register_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.cash_register import CashRegister
    from app.services.cash_register_service import update_cash_register

    db, bid = context["db"], int(context["business_id"])
    pk = int(args["cash_register_id"])
    _tenant_row(db, CashRegister, pk, bid, "صندوق در کسب‌وکار متصل پیدا نشد")
    data = {key: value for key, value in args.items() if key != "cash_register_id"}
    try:
        result = update_cash_register(db, pk, data)
    except Exception as exc:
        _raise_service(exc)
    if result is None:
        raise ValueError("صندوق در کسب‌وکار متصل پیدا نشد")
    return result


def delete_cash_register_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.cash_register import CashRegister
    from app.services.cash_register_service import delete_cash_register

    db, bid = context["db"], int(context["business_id"])
    _require_perm(context["user_context"], db, bid, "cash", "delete", "cash_registers.delete")
    pk = int(args["cash_register_id"])
    _tenant_row(db, CashRegister, pk, bid, "صندوق در کسب‌وکار متصل پیدا نشد")
    success, error = delete_cash_register(db, pk)
    if not success:
        raise ValueError(error or "حذف صندوق انجام نشد")
    return {"deleted": True, "cash_register_id": pk}


def bulk_delete_cash_registers_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.cash_register import CashRegister
    from app.services.cash_register_service import bulk_delete_cash_registers

    db, bid = context["db"], int(context["business_id"])
    ids = _unique_ids(args["cash_register_ids"], field="cash_register_ids")
    _require_perm(context["user_context"], db, bid, "cash", "delete", "cash_registers.delete")
    found = db.query(CashRegister).filter(CashRegister.id.in_(ids), CashRegister.business_id == bid).all()
    if len(found) != len(ids):
        raise ValueError("همهٔ شناسه‌ها باید متعلق به کسب‌وکار متصل باشند")
    return bulk_delete_cash_registers(db, bid, ids)


def get_petty_cash_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.petty_cash import PettyCash
    from app.services.petty_cash_service import get_petty_cash_by_id

    db, bid = context["db"], int(context["business_id"])
    pk = int(args["petty_cash_id"])
    _tenant_row(db, PettyCash, pk, bid, "تنخواه در کسب‌وکار متصل پیدا نشد")
    return get_petty_cash_by_id(db, pk)


def create_petty_cash_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.petty_cash_service import create_petty_cash

    try:
        return create_petty_cash(context["db"], int(context["business_id"]), dict(args))
    except Exception as exc:
        _raise_service(exc)


def update_petty_cash_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.db.models.petty_cash import PettyCash
    from app.services.petty_cash_service import update_petty_cash

    db, bid = context["db"], int(context["business_id"])
    pk = int(args["petty_cash_id"])
    _tenant_row(db, PettyCash, pk, bid, "تنخواه در کسب‌وکار متصل پیدا نشد")
    data = {key: value for key, value in args.items() if key != "petty_cash_id"}
    try:
        result = update_petty_cash(db, pk, data)
    except Exception as exc:
        _raise_service(exc)
    if result is None:
        raise ValueError("تنخواه در کسب‌وکار متصل پیدا نشد")
    return result


def delete_petty_cash_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.petty_cash import PettyCash
    from app.services.petty_cash_service import delete_petty_cash

    db, bid = context["db"], int(context["business_id"])
    _require_perm(context["user_context"], db, bid, "petty_cash", "delete", "petty_cash.delete")
    pk = int(args["petty_cash_id"])
    _tenant_row(db, PettyCash, pk, bid, "تنخواه در کسب‌وکار متصل پیدا نشد")
    success, error = delete_petty_cash(db, pk)
    if not success:
        raise ValueError(error or "حذف تنخواه انجام نشد")
    return {"deleted": True, "petty_cash_id": pk}


def bulk_delete_petty_cash_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.petty_cash import PettyCash
    from app.services.petty_cash_service import bulk_delete_petty_cash

    db, bid = context["db"], int(context["business_id"])
    ids = _unique_ids(args["petty_cash_ids"], field="petty_cash_ids")
    _require_perm(context["user_context"], db, bid, "petty_cash", "delete", "petty_cash.delete")
    found = db.query(PettyCash).filter(PettyCash.id.in_(ids), PettyCash.business_id == bid).all()
    if len(found) != len(ids):
        raise ValueError("همهٔ شناسه‌ها باید متعلق به کسب‌وکار متصل باشند")
    return bulk_delete_petty_cash(db, bid, ids)


def upsert_opening_balance_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.opening_balance_service import upsert_opening_balance

    try:
        return upsert_opening_balance(
            context["db"],
            int(context["business_id"]),
            int(context["user_context"].get_user_id()),
            _opening_payload(args),
        )
    except Exception as exc:
        _raise_service(exc)


def preview_opening_balance_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.opening_balance_service import preview_opening_balance

    try:
        return preview_opening_balance(context["db"], int(context["business_id"]), _opening_payload(args))
    except Exception as exc:
        _raise_service(exc)


def post_opening_balance_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.opening_balance_service import post_opening_balance

    try:
        return post_opening_balance(
            context["db"],
            int(context["business_id"]),
            int(context["user_context"].get_user_id()),
            args.get("fiscal_year_id"),
        )
    except Exception as exc:
        _raise_service(exc)


def unpost_opening_balance_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from app.services.opening_balance_service import unpost_opening_balance

    try:
        return unpost_opening_balance(
            context["db"],
            int(context["business_id"]),
            int(context["user_context"].get_user_id()),
            args.get("fiscal_year_id"),
        )
    except Exception as exc:
        _raise_service(exc)


def register_mcp_treasury_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}

    registry.register(AIFunction(
        name="get_bank_account",
        description="جزئیات یک حساب بانکی متعلق به کسب‌وکار متصل.",
        parameters_schema=GET_BANK_ACCOUNT_SCHEMA,
        handler=get_bank_account_handler, allowed_roles=roles,
        required_permissions=["bank_accounts.view"], category="financial", is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_bank_account",
        description="ایجاد حساب بانکی برای کسب‌وکار متصل. name و currency_id الزامی است؛ کد در صورت خالی بودن خودکار است. نیاز به تأیید.",
        parameters_schema=CREATE_BANK_ACCOUNT_SCHEMA, handler=create_bank_account_handler, allowed_roles=roles,
        required_permissions=["bank_accounts.write"], category="financial",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_bank_account",
        description="ویرایش حساب بانکی متعلق به کسب‌وکار متصل. فقط فیلدهای ارسال‌شده عوض می‌شوند. نیاز به تأیید.",
        parameters_schema=UPDATE_BANK_ACCOUNT_SCHEMA, handler=update_bank_account_handler, allowed_roles=roles,
        required_permissions=["bank_accounts.write"], category="financial",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_bank_account",
        description="حذف حساب بانکی بدون سند مرتبط. اگر سند حسابداری داشته باشد رد می‌شود. برگشت‌ناپذیر و نیازمند تأیید.",
        parameters_schema=DELETE_BANK_ACCOUNT_SCHEMA,
        handler=delete_bank_account_handler, allowed_roles=roles,
        required_permissions=["bank_accounts.delete"], category="financial",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="bulk_delete_bank_accounts",
        description=f"حذف حداکثر {_MAX_BULK} حساب بانکی کسب‌وکار متصل. اگر حتی یک شناسه خارج از tenant باشد کل درخواست رد می‌شود. نیازمند تأیید.",
        parameters_schema=BULK_DELETE_BANK_ACCOUNTS_SCHEMA,
        handler=bulk_delete_bank_accounts_handler, allowed_roles=roles,
        required_permissions=["bank_accounts.delete"], category="financial",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    registry.register(AIFunction(
        name="get_cash_register",
        description="جزئیات یک صندوق متعلق به کسب‌وکار متصل.",
        parameters_schema=GET_CASH_REGISTER_SCHEMA,
        handler=get_cash_register_handler, allowed_roles=roles,
        required_permissions=["cash_registers.view"], category="financial", is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_cash_register",
        description="ایجاد صندوق برای کسب‌وکار متصل. name و currency_id الزامی است. نیاز به تأیید.",
        parameters_schema=CREATE_CASH_REGISTER_SCHEMA, handler=create_cash_register_handler, allowed_roles=roles,
        required_permissions=["cash_registers.write"], category="financial",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_cash_register",
        description="ویرایش صندوق متعلق به کسب‌وکار متصل. نیاز به تأیید.",
        parameters_schema=UPDATE_CASH_REGISTER_SCHEMA, handler=update_cash_register_handler, allowed_roles=roles,
        required_permissions=["cash_registers.write"], category="financial",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_cash_register",
        description="حذف صندوق بدون سند مرتبط. برگشت‌ناپذیر و نیازمند تأیید.",
        parameters_schema=DELETE_CASH_REGISTER_SCHEMA,
        handler=delete_cash_register_handler, allowed_roles=roles,
        required_permissions=["cash_registers.delete"], category="financial",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="bulk_delete_cash_registers",
        description=f"حذف حداکثر {_MAX_BULK} صندوق کسب‌وکار متصل؛ رد کامل اگر شناسه خارج از tenant باشد. نیازمند تأیید.",
        parameters_schema=BULK_DELETE_CASH_REGISTERS_SCHEMA,
        handler=bulk_delete_cash_registers_handler, allowed_roles=roles,
        required_permissions=["cash_registers.delete"], category="financial",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    registry.register(AIFunction(
        name="get_petty_cash",
        description="جزئیات یک تنخواه متعلق به کسب‌وکار متصل.",
        parameters_schema=GET_PETTY_CASH_SCHEMA,
        handler=get_petty_cash_handler, allowed_roles=roles,
        required_permissions=["petty_cash.view"], category="financial", is_readonly=True,
    ))
    registry.register(AIFunction(
        name="create_petty_cash",
        description="ایجاد تنخواه گردان برای کسب‌وکار متصل. name و currency_id الزامی است. نیاز به تأیید.",
        parameters_schema=CREATE_PETTY_CASH_SCHEMA, handler=create_petty_cash_handler, allowed_roles=roles,
        required_permissions=["petty_cash.write"], category="financial",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_petty_cash",
        description="ویرایش تنخواه متعلق به کسب‌وکار متصل. نیاز به تأیید.",
        parameters_schema=UPDATE_PETTY_CASH_SCHEMA, handler=update_petty_cash_handler, allowed_roles=roles,
        required_permissions=["petty_cash.write"], category="financial",
        requires_approval=True, risk_level="medium", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="delete_petty_cash",
        description="حذف تنخواه بدون سند مرتبط. برگشت‌ناپذیر و نیازمند تأیید.",
        parameters_schema=DELETE_PETTY_CASH_SCHEMA,
        handler=delete_petty_cash_handler, allowed_roles=roles,
        required_permissions=["petty_cash.delete"], category="financial",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="bulk_delete_petty_cash",
        description=f"حذف حداکثر {_MAX_BULK} تنخواه کسب‌وکار متصل؛ رد کامل اگر شناسه خارج از tenant باشد. نیازمند تأیید.",
        parameters_schema=BULK_DELETE_PETTY_CASH_SCHEMA,
        handler=bulk_delete_petty_cash_handler, allowed_roles=roles,
        required_permissions=["petty_cash.delete"], category="financial",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))

    registry.register(AIFunction(
        name="upsert_opening_balance",
        description=(
            "ذخیره یا به‌روزرسانی تراز افتتاحیه سال مالی کسب‌وکار متصل. "
            "اگر نهایی شده باشد رد می‌شود. extra_info پذیرفته نمی‌شود؛ برای موجودی warehouse_id و cost_price را جدا بفرستید. نیاز به تأیید."
        ),
        parameters_schema=OPENING_BALANCE_WRITE_SCHEMA, handler=upsert_opening_balance_handler, allowed_roles=roles,
        required_permissions=["opening_balance.edit"], category="accounting",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="preview_opening_balance",
        description="پیش‌نمایش تراز افتتاحیه بدون ذخیره. همان فیلدهای upsert_opening_balance را می‌گیرد.",
        parameters_schema=OPENING_BALANCE_WRITE_SCHEMA, handler=preview_opening_balance_handler, allowed_roles=roles,
        required_permissions=["opening_balance.edit"], category="accounting", is_readonly=True,
    ))
    registry.register(AIFunction(
        name="post_opening_balance",
        description="نهایی‌سازی تراز افتتاحیه سال مالی. پس از آن ویرایش ممکن نیست مگر unpost. نیازمند تأیید.",
        parameters_schema=OPENING_BALANCE_FY_SCHEMA, handler=post_opening_balance_handler, allowed_roles=roles,
        required_permissions=["opening_balance.edit"], category="accounting",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
    registry.register(AIFunction(
        name="unpost_opening_balance",
        description="لغو نهایی‌سازی تراز افتتاحیه فقط اگر در همان سال مالی سند دیگری ثبت نشده باشد. نیازمند تأیید.",
        parameters_schema=OPENING_BALANCE_FY_SCHEMA, handler=unpost_opening_balance_handler, allowed_roles=roles,
        required_permissions=["opening_balance.edit"], category="accounting",
        requires_approval=True, risk_level="high", is_readonly=False,
    ))
