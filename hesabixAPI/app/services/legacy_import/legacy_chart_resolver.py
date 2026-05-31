from __future__ import annotations

import logging
import re
from typing import Any, Dict, List, Optional

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from adapters.db.models.account import Account

logger = logging.getLogger(__name__)

# حساب‌های پیش‌فرض چارت عمومی (business_id IS NULL)
FALLBACK_EXPENSE_ACCOUNT_CODE = "70401"  # خرید خدمات
FALLBACK_INCOME_ACCOUNT_CODE = "60203"  # سایر درآمد ها


def _normalize_name(value: str | None) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", str(value).strip())


class LegacyChartResolver:
    """نگاشت ref_id / code / name حساب قدیم به Account نسخه جدید."""

    def __init__(
        self,
        db: Session,
        business_id: int,
        hesabdari_tables: List[Dict[str, Any]],
    ) -> None:
        self.db = db
        self.business_id = business_id
        self.tables_by_id: Dict[int, Dict[str, Any]] = {}
        for row in hesabdari_tables or []:
            tid = row.get("id")
            if tid is not None:
                self.tables_by_id[int(tid)] = row

        self._accounts: List[Account] = (
            db.query(Account)
            .filter(
                or_(
                    Account.business_id.is_(None),
                    Account.business_id == int(business_id),
                )
            )
            .all()
        )
        self._by_code: Dict[str, Account] = {}
        self._by_name_norm: Dict[str, Account] = {}
        for acc in self._accounts:
            code = str(acc.code or "").strip()
            if code:
                self._by_code[code] = acc
            norm = _normalize_name(acc.name)
            if norm:
                self._by_name_norm[norm] = acc

        self._fallback_expense = self._by_code.get(FALLBACK_EXPENSE_ACCOUNT_CODE)
        self._fallback_income = self._by_code.get(FALLBACK_INCOME_ACCOUNT_CODE)

    def resolve_account_id(
        self,
        ref_id: int | None,
        *,
        is_income: bool,
        hint_name: str | None = None,
        hint_code: str | None = None,
    ) -> Optional[int]:
        """یافتن account_id برای سطر calc (هزینه/درآمد)."""
        candidates: List[str] = []
        if hint_code:
            candidates.append(str(hint_code).strip())
        if ref_id is not None:
            meta = self.tables_by_id.get(int(ref_id))
            if meta:
                if meta.get("code"):
                    candidates.append(str(meta["code"]).strip())
                if meta.get("name"):
                    hint_name = hint_name or str(meta["name"])

        for code in candidates:
            if not code:
                continue
            if code in self._by_code:
                return int(self._by_code[code].id)

        norm_hint = _normalize_name(hint_name)
        if norm_hint:
            if norm_hint in self._by_name_norm:
                return int(self._by_name_norm[norm_hint].id)
            for name, acc in self._by_name_norm.items():
                if norm_hint in name or name in norm_hint:
                    return int(acc.id)

        for code in candidates:
            if not code or len(code) < 3:
                continue
            for acc_code, acc in self._by_code.items():
                if len(acc_code) < 3:
                    continue
                if acc_code.endswith(code) or code.endswith(acc_code):
                    return int(acc.id)

        fb = self._fallback_income if is_income else self._fallback_expense
        if fb:
            logger.debug(
                "legacy_chart_fallback ref_id=%s is_income=%s -> account %s",
                ref_id,
                is_income,
                fb.code,
            )
            return int(fb.id)
        return None
