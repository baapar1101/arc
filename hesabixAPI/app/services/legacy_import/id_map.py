from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional


@dataclass
class LegacyIdMap:
    """Maps legacy entity IDs to new database IDs within one import run."""

    persons: Dict[int, int] = field(default_factory=dict)
    products: Dict[int, int] = field(default_factory=dict)
    categories: Dict[int, int] = field(default_factory=dict)
    warehouses: Dict[int, int] = field(default_factory=dict)
    bank_accounts: Dict[int, int] = field(default_factory=dict)
    fiscal_years: Dict[int, int] = field(default_factory=dict)
    documents: Dict[int, int] = field(default_factory=dict)

    def set(self, bucket: str, old_id: int | None, new_id: int | None) -> None:
        if old_id is None or new_id is None:
            return
        getattr(self, bucket)[int(old_id)] = int(new_id)

    def get(self, bucket: str, old_id: int | None) -> Optional[int]:
        if old_id is None:
            return None
        return getattr(self, bucket).get(int(old_id))

    def summary(self) -> Dict[str, int]:
        return {
            "persons": len(self.persons),
            "products": len(self.products),
            "categories": len(self.categories),
            "warehouses": len(self.warehouses),
            "bank_accounts": len(self.bank_accounts),
            "fiscal_years": len(self.fiscal_years),
            "documents": len(self.documents),
        }


@dataclass
class LegacyImportStats:
    """Counters and non-fatal warnings collected during import."""

    persons_imported: int = 0
    persons_skipped: int = 0
    products_imported: int = 0
    products_skipped: int = 0
    categories_imported: int = 0
    warehouses_imported: int = 0
    bank_accounts_imported: int = 0
    documents_imported: int = 0
    documents_skipped: int = 0
    files_imported: int = 0
    warnings: list[str] = field(default_factory=list)

    def add_warning(self, message: str, *, limit: int = 200) -> None:
        if len(self.warnings) >= limit:
            return
        self.warnings.append(message[:2000])

    def to_dict(self) -> Dict[str, Any]:
        return {
            "persons_imported": self.persons_imported,
            "persons_skipped": self.persons_skipped,
            "products_imported": self.products_imported,
            "products_skipped": self.products_skipped,
            "categories_imported": self.categories_imported,
            "warehouses_imported": self.warehouses_imported,
            "bank_accounts_imported": self.bank_accounts_imported,
            "documents_imported": self.documents_imported,
            "documents_skipped": self.documents_skipped,
            "files_imported": self.files_imported,
            "warnings_count": len(self.warnings),
            "warnings": self.warnings[:50],
        }
