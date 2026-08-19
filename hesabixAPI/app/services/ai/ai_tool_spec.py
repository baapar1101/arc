"""انواع و قرارداد Metadata ابزار AI — مستقل از Provider و Handler.

این ماژول عمداً Registry را import نمی‌کند تا Intent / Index / تست‌ها
بتوانند بدون بالا آوردن سرویس لایه، روی کاتالوگ کار کنند.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional, Tuple


class ToolSideEffect(str, Enum):
    NONE = "none"
    WRITE = "write"
    DELETE = "delete"
    EXECUTE = "execute"
    EXPORT = "export"


class ToolCapability(str, Enum):
    """گروه درشت برای Discovery دو مرحله‌ای آینده — امروز فقط برچسب است."""

    ACCOUNTING = "accounting"
    INVENTORY = "inventory"
    PEOPLE = "people"
    CRM = "crm"
    TAX = "tax"
    AUTOMATION = "automation"
    INTEGRATIONS = "integrations"
    PLATFORM = "platform"
    AGENT = "agent"
    QUERY = "query"
    MISC = "misc"


TOOL_DOMAINS: frozenset[str] = frozenset({
    "financial",
    "warehouse",
    "crm",
    "customer_club",
    "tax",
    "projects",
    "integration",
    "workflow",
    "misc",
    "agent",
    "people",
    "products_write",
    "query",
    "reports_meta",
    "report_templates",
    "marketplace",
    "hscript",
    "memory",
})

DOMAIN_TO_CAPABILITY: dict[str, str] = {
    "financial": ToolCapability.ACCOUNTING.value,
    "reports_meta": ToolCapability.ACCOUNTING.value,
    "report_templates": ToolCapability.ACCOUNTING.value,
    "warehouse": ToolCapability.INVENTORY.value,
    "products_write": ToolCapability.INVENTORY.value,
    "people": ToolCapability.PEOPLE.value,
    "customer_club": ToolCapability.PEOPLE.value,
    "crm": ToolCapability.CRM.value,
    "tax": ToolCapability.TAX.value,
    "workflow": ToolCapability.AUTOMATION.value,
    "integration": ToolCapability.INTEGRATIONS.value,
    "marketplace": ToolCapability.INTEGRATIONS.value,
    "hscript": ToolCapability.PLATFORM.value,
    "agent": ToolCapability.AGENT.value,
    "memory": ToolCapability.AGENT.value,
    "query": ToolCapability.QUERY.value,
    "projects": ToolCapability.ACCOUNTING.value,
    "misc": ToolCapability.MISC.value,
}

REGISTRY_CATEGORY_TO_DOMAINS: dict[str, Tuple[str, ...]] = {
    "business": ("misc",),
    "invoices": ("financial",),
    "products": ("products_write",),
    "persons": ("people",),
    "financial": ("financial",),
    "crm": ("crm",),
    "integration": ("integration",),
    "query": ("query",),
    "reports": ("reports_meta",),
    "warehouse": ("warehouse",),
    "checks": ("financial",),
    "accounting": ("financial",),
    "workflow": ("workflow",),
    "hscript": ("hscript",),
    "agent": ("agent",),
    "user": ("misc",),
    "export": ("reports_meta",),
    "report_templates": ("report_templates",),
    "customer_club": ("customer_club",),
    "sales": ("financial",),
    "audit": ("misc",),
    "credit": ("financial",),
    "marketplace": ("marketplace",),
    "projects": ("projects",),
    "production": ("warehouse",),
    "repair": ("misc",),
    "tax": ("tax",),
    "distribution": ("misc",),
    "warranty": ("misc",),
    "memory": ("memory",),
}


def capability_for_domains(domains: Tuple[str, ...]) -> str:
    for domain in domains:
        mapped = DOMAIN_TO_CAPABILITY.get(domain)
        if mapped:
            return mapped
    return ToolCapability.MISC.value


def infer_side_effect(name: str, *, intent_write: bool, always_confirm: bool) -> str:
    if (name or "").startswith("delete_"):
        return ToolSideEffect.DELETE.value
    if name in {"execute_workflow", "test_workflow"} or (name or "").startswith("invoke_"):
        return ToolSideEffect.EXECUTE.value
    if name == "export_business_data" or (name or "").startswith("export_"):
        return ToolSideEffect.EXPORT.value
    if intent_write or always_confirm:
        return ToolSideEffect.WRITE.value
    return ToolSideEffect.NONE.value


@dataclass(frozen=True)
class ToolManifestEntry:
    """Metadata پایدار یک Tool — بدون handler و بدون JSON Schema کامل."""

    domains: Tuple[str, ...] = ()
    capability: str = ToolCapability.MISC.value
    namespace: str = ""
    aliases: Tuple[str, ...] = ()
    keywords: Tuple[str, ...] = ()
    examples: Tuple[str, ...] = ()
    companion_tools: Tuple[str, ...] = ()
    is_core: bool = False
    intent_write: bool = False
    always_confirm: bool = False
    side_effect: str = ToolSideEffect.NONE.value
    permission_policy: str = "required"
    enabled: bool = True
    deprecated: bool = False
    replacement: Optional[str] = None
    version: str = "1"
    schema_version: str = "1"

    def search_text(self, name: str, description: str = "") -> str:
        parts = [
            name,
            description,
            self.capability,
            self.namespace,
            *self.domains,
            *self.aliases,
            *self.keywords,
            *self.examples,
        ]
        return " ".join(part for part in parts if part)
