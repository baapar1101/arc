"""کمک‌تابع‌های ایمپورت اکسل اشخاص (اعتبارسنجی، نرمال‌سازی، شبیه‌سازی dry-run)."""
from __future__ import annotations

import logging
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple

from pydantic import ValidationError

from adapters.api.v1.schema_models.person import PersonCreateRequest, PersonUpdateRequest, PersonType

logger = logging.getLogger(__name__)

MAX_PERSON_IMPORT_FILE_BYTES = 15 * 1024 * 1024  # 15 MiB
MAX_PERSON_IMPORT_DATA_ROWS = 5000

ALLOWED_MATCH_BY = frozenset({"code", "national_id", "email"})
ALLOWED_CONFLICT_POLICY = frozenset({"insert", "update", "upsert"})


def _blank_to_none(v: Any) -> Any:
    if v is None:
        return None
    if isinstance(v, str):
        st = v.strip()
        return None if st == "" else st
    return v


def parse_positive_int_code(v: Any) -> Optional[int]:
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v if v >= 1 else None
    if isinstance(v, float):
        if v != v or abs(v - round(v)) > 1e-9:
            return None
        i = int(round(v))
        return i if i >= 1 else None
    s = str(v).strip()
    if not s:
        return None
    try:
        f = float(s)
        i = int(f)
        if abs(f - i) > 1e-9:
            return None
        return i if i >= 1 else None
    except ValueError:
        return None


def _parse_optional_int(v: Any) -> Optional[int]:
    v = _blank_to_none(v)
    if v is None:
        return None
    if isinstance(v, bool):
        raise ValueError("انتظار عدد صحیح است")
    if isinstance(v, int):
        return v
    if isinstance(v, float):
        if v != v or abs(v - round(v)) > 1e-9:
            raise ValueError("انتظار عدد صحیح است")
        return int(round(v))
    try:
        f = float(str(v).strip())
        i = int(f)
        if abs(f - i) > 1e-9:
            raise ValueError("انتظار عدد صحیح است")
        return i
    except (ValueError, TypeError):
        raise ValueError("عدد صحیح نامعتبر") from None


def _parse_optional_float(v: Any) -> Optional[float]:
    v = _blank_to_none(v)
    if v is None:
        return None
    if isinstance(v, bool):
        raise ValueError("انتظار عدد است")
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v != v:
            raise ValueError("عدد نامعتبر")
        return float(v)
    if isinstance(v, Decimal):
        return float(v)
    try:
        return float(Decimal(str(v).strip()))
    except (InvalidOperation, ValueError):
        raise ValueError("عدد اعشاری نامعتبر") from None


def _parse_optional_bool(v: Any) -> Optional[bool]:
    v = _blank_to_none(v)
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    s = str(v).strip().lower()
    if s in ("1", "true", "yes", "on", "بله"):
        return True
    if s in ("0", "false", "no", "off"):
        return False
    raise ValueError("مقدار بولی نامعتبر")


def _format_pydantic_errors(e: ValidationError) -> List[str]:
    out: List[str] = []
    try:
        for er in e.errors():
            loc = ".".join(str(x) for x in er.get("loc", ()) if isinstance(x, (str, int)))
            msg = str(er.get("msg", "خطای اعتبارسنجی"))
            prefix = f"{loc}: " if loc else ""
            out.append(f"{prefix}{msg}")
    except Exception:
        out.append("خطای اعتبارسنجی داده شخص")
    return out


def prepare_person_import_item(item: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str]]:
    row_errors: List[str] = []
    out: Dict[str, Any] = dict(item)

    optional_str_keys = [
        "first_name",
        "last_name",
        "company_name",
        "payment_id",
        "national_id",
        "registration_number",
        "economic_id",
        "country",
        "province",
        "city",
        "address",
        "postal_code",
        "phone",
        "mobile",
        "mobile_2",
        "mobile_3",
        "fax",
        "email",
        "website",
    ]
    for k in optional_str_keys:
        if k in out:
            out[k] = _blank_to_none(out.get(k))
    if "alias_name" in out:
        out["alias_name"] = _blank_to_none(out.get("alias_name"))

    pc = parse_positive_int_code(out.get("code"))
    out.pop("code", None)
    if pc is not None:
        out["code"] = pc

    if "person_group_id" in item:
        pg = item.get("person_group_id")
        pg = _blank_to_none(pg)
        if pg is None:
            out["person_group_id"] = None
        else:
            try:
                out["person_group_id"] = _parse_optional_int(pg)
            except ValueError:
                row_errors.append("person_group_id نامعتبر است")

    sc_raw = item.get("share_count")
    if sc_raw is not None and str(sc_raw).strip() != "":
        try:
            out["share_count"] = _parse_optional_int(sc_raw)
        except ValueError:
            row_errors.append("share_count نامعتبر است")
    else:
        out.pop("share_count", None)

    for nk in (
        "commission_sale_percent",
        "commission_sales_return_percent",
        "commission_sales_amount",
        "commission_sales_return_amount",
        "credit_limit",
    ):
        if nk not in item:
            continue
        if item.get(nk) is None or (isinstance(item.get(nk), str) and not str(item.get(nk)).strip()):
            out.pop(nk, None)
            continue
        try:
            out[nk] = _parse_optional_float(item.get(nk))
        except ValueError:
            row_errors.append(f"{nk} نامعتبر است")

    for bk in (
        "commission_exclude_discounts",
        "commission_exclude_additions_deductions",
        "commission_post_in_invoice_document",
    ):
        if bk not in item:
            continue
        try:
            parsed = _parse_optional_bool(item.get(bk))
            if parsed is None:
                out.pop(bk, None)
            else:
                out[bk] = parsed
        except ValueError:
            row_errors.append(f"{bk} نامعتبر است")

    return out, row_errors


def _has_person_kind(req: PersonCreateRequest) -> bool:
    types_list = list(req.person_types) if req.person_types else []
    pt = getattr(req, "person_type", None)
    if types_list:
        return True
    if pt is not None:
        return True
    return False


def validate_row_as_create_request(
    prepped_item: Dict[str, Any],
) -> Tuple[Optional[PersonCreateRequest], List[str]]:
    try:
        req = PersonCreateRequest.model_validate(prepped_item)
    except ValidationError as e:
        return None, _format_pydantic_errors(e)
    if not _has_person_kind(req):
        return None, ["نوع شخص الزامی است (person_type یا person_types)"]
    # Pydantic v2: اعتبارسنجی root قدیمی کلاس PersonCreateRequest اعمال نمی‌شود
    types_list = list(req.person_types) if req.person_types else []
    pt = req.person_type
    is_sh = (pt == PersonType.SHAREHOLDER) or (PersonType.SHAREHOLDER in types_list)
    if is_sh:
        sc = req.share_count
        if sc is None or (isinstance(sc, int) and sc <= 0):
            return None, ["برای سهامدار، مقدار تعداد سهام الزامی و باید بزرگتر از صفر باشد"]
    return req, []


def build_person_update_request_for_import(
    headers_row: List[str],
    create_req: PersonCreateRequest,
) -> PersonUpdateRequest:
    """فقط فیلدهای موجود در تمپلیت/هدر اکسل؛ بدون پاک‌کردن حساب‌های بانکی/شبکه‌های اجتماعی با لیست تهی."""
    allowed = PersonUpdateRequest.model_fields.keys()
    skip_relations = frozenset({"bank_accounts", "social_contacts"})
    hdrs = [str(h).strip() for h in headers_row if h and str(h).strip()]
    dump = create_req.model_dump(mode="python")
    partial: Dict[str, Any] = {}
    for h in hdrs:
        if h not in allowed or h in skip_relations:
            continue
        partial[h] = dump.get(h)
    return PersonUpdateRequest.model_validate(partial)


def match_key_for_row(match_by: str, data: Dict[str, Any]) -> Optional[str]:
    if match_by == "code":
        c = parse_positive_int_code(data.get("code"))
        return str(c) if c is not None else None
    if match_by == "national_id":
        nid = data.get("national_id")
        if nid is None or str(nid).strip() == "":
            return None
        return str(nid).strip()
    if match_by == "email":
        em = _blank_to_none(data.get("email"))
        return em.strip().lower() if em else None
    return None
