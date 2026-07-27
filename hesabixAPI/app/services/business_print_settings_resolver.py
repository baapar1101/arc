from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.business_print_settings import BusinessPrintSettings
from app.services.print_stamp_scale import STAMP_SCALE_DEFAULT, clamp_scale_percent
from app.services.print_tax_discount_display import (
    DEFAULT_TAX_DISCOUNT_DISPLAY_SETTINGS,
    normalize_display_mode,
)


def _row_to_print_settings_dict(row: BusinessPrintSettings) -> Dict[str, Any]:
    return {
        "show_logo": bool(getattr(row, "show_logo", True)),
        "show_stamp": bool(getattr(row, "show_stamp", True)),
        "show_payments": bool(getattr(row, "show_payments", True)),
        "show_installment_plan": bool(getattr(row, "show_installment_plan", True)),
        "show_share_qr": bool(getattr(row, "show_share_qr", False)),
        "show_footer_print_time": bool(getattr(row, "show_footer_print_time", True)),
        "show_footer_preparer": bool(getattr(row, "show_footer_preparer", True)),
        "footer_note": getattr(row, "footer_note", None),
        "show_customer_balance": bool(getattr(row, "show_customer_balance", True)),
        "show_seller_signature_area": bool(
            getattr(row, "show_seller_signature_area", True)
        ),
        "show_buyer_signature_area": bool(
            getattr(row, "show_buyer_signature_area", True)
        ),
        "stamp_scale_percent": clamp_scale_percent(
            getattr(row, "stamp_scale_percent", STAMP_SCALE_DEFAULT)
        ),
        "signature_scale_percent": clamp_scale_percent(
            getattr(row, "signature_scale_percent", STAMP_SCALE_DEFAULT)
        ),
        **{
            key: normalize_display_mode(getattr(row, key, None))
            for key in DEFAULT_TAX_DISCOUNT_DISPLAY_SETTINGS
        },
    }


def default_print_settings_dict() -> Dict[str, Any]:
    return {
        "show_logo": True,
        "show_stamp": True,
        "show_payments": True,
        "show_installment_plan": True,
        "show_share_qr": False,
        "show_footer_print_time": True,
        "show_footer_preparer": True,
        "footer_note": None,
        "show_customer_balance": True,
        "show_seller_signature_area": True,
        "show_buyer_signature_area": True,
        "stamp_scale_percent": STAMP_SCALE_DEFAULT,
        "signature_scale_percent": STAMP_SCALE_DEFAULT,
        **DEFAULT_TAX_DISCOUNT_DISPLAY_SETTINGS,
    }


def pick_print_settings(
    print_rows: List[BusinessPrintSettings],
    document_type: Optional[str],
    *,
    base: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    default_cfg = dict(base or default_print_settings_dict())
    per_type_cfg: Optional[Dict[str, Any]] = None
    doc_type = str(document_type or "").strip()

    for row in print_rows:
        if row.document_type == "all":
            default_cfg = _row_to_print_settings_dict(row)
        elif doc_type and row.document_type == doc_type:
            per_type_cfg = _row_to_print_settings_dict(row)

    if per_type_cfg is None:
        return default_cfg

    merged = dict(default_cfg)
    merged.update({k: v for k, v in per_type_cfg.items() if v is not None})
    return merged


def load_print_settings(
    db: Session,
    business_id: int,
    document_type: Optional[str] = None,
) -> Dict[str, Any]:
    try:
        print_rows = (
            db.query(BusinessPrintSettings)
            .filter(BusinessPrintSettings.business_id == business_id)
            .all()
        )
    except Exception:
        print_rows = []
    return pick_print_settings(print_rows, document_type)
