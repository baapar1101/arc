"""سقف‌های تجاری HScript بر اساس لایسنس افزونه Marketplace."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin, MarketplacePluginPlan
from app.services.hscript.limits import ResourceLimits

PLUGIN_CODE = "hscript_custom_reports"

# tier: free | trial | monthly | yearly | lifetime
_TIER_LIMITS: dict[str, dict[str, Any]] = {
	"free": {
		"max_saved_reports": 25,
		"runs_per_minute": 8,
		"async_allowed": True,
		"excel_allowed": True,
		"pdf_allowed": True,
		"resource": ResourceLimits.default(),
		"preview_resource": ResourceLimits.preview(),
	},
	"trial": {
		"max_saved_reports": 100,
		"runs_per_minute": 20,
		"async_allowed": True,
		"excel_allowed": True,
		"pdf_allowed": True,
		"resource": ResourceLimits(
			max_execution_ms=20_000,
			max_steps=400_000,
			max_loop_iterations=20_000,
			max_gateway_calls=100,
			max_gateway_rows_per_call=8_000,
			max_output_bytes=4_000_000,
			max_report_blocks=400,
		),
		"preview_resource": ResourceLimits.preview(),
	},
	"monthly": {
		"max_saved_reports": 200,
		"runs_per_minute": 30,
		"async_allowed": True,
		"excel_allowed": True,
		"pdf_allowed": True,
		"resource": ResourceLimits(
			max_execution_ms=30_000,
			max_steps=600_000,
			max_loop_iterations=30_000,
			max_gateway_calls=150,
			max_gateway_rows_per_call=10_000,
			max_output_bytes=5_000_000,
			max_report_blocks=500,
		),
		"preview_resource": ResourceLimits(
			max_execution_ms=8_000,
			max_steps=120_000,
			max_loop_iterations=4_000,
			max_gateway_calls=40,
			max_gateway_rows_per_call=1_000,
			max_output_bytes=1_000_000,
		),
	},
	"yearly": {
		"max_saved_reports": 500,
		"runs_per_minute": 40,
		"async_allowed": True,
		"excel_allowed": True,
		"pdf_allowed": True,
		"resource": ResourceLimits(
			max_execution_ms=45_000,
			max_steps=800_000,
			max_loop_iterations=40_000,
			max_gateway_calls=200,
			max_gateway_rows_per_call=12_000,
			max_output_bytes=8_000_000,
			max_report_blocks=800,
		),
		"preview_resource": ResourceLimits(
			max_execution_ms=10_000,
			max_steps=160_000,
			max_loop_iterations=5_000,
			max_gateway_calls=50,
			max_gateway_rows_per_call=2_000,
			max_output_bytes=1_500_000,
		),
	},
	"lifetime": {
		"max_saved_reports": 1_000,
		"runs_per_minute": 60,
		"async_allowed": True,
		"excel_allowed": True,
		"pdf_allowed": True,
		"resource": ResourceLimits(
			max_execution_ms=60_000,
			max_steps=1_000_000,
			max_loop_iterations=50_000,
			max_gateway_calls=300,
			max_gateway_rows_per_call=15_000,
			max_output_bytes=10_000_000,
			max_report_blocks=1_000,
		),
		"preview_resource": ResourceLimits(
			max_execution_ms=12_000,
			max_steps=200_000,
			max_loop_iterations=8_000,
			max_gateway_calls=60,
			max_gateway_rows_per_call=3_000,
			max_output_bytes=2_000_000,
		),
	},
}


@dataclass(frozen=True)
class HScriptPlanEntitlement:
	"""وضعیت لایسنس و سقف‌های قابل اعمال برای یک کسب‌وکار."""

	tier: str
	plugin_active: bool
	plugin_code: str
	plan_period: Optional[str]
	is_trial: bool
	max_saved_reports: int
	runs_per_minute: int
	async_allowed: bool
	excel_allowed: bool
	pdf_allowed: bool
	resource: ResourceLimits
	preview_resource: ResourceLimits

	def resource_for(self, *, preview: bool) -> ResourceLimits:
		return self.preview_resource if preview else self.resource

	def to_public_dict(self) -> dict[str, Any]:
		return {
			"tier": self.tier,
			"plugin_active": self.plugin_active,
			"plugin_code": self.plugin_code,
			"plan_period": self.plan_period,
			"is_trial": self.is_trial,
			"max_saved_reports": self.max_saved_reports,
			"runs_per_minute": self.runs_per_minute,
			"async_allowed": self.async_allowed,
			"excel_allowed": self.excel_allowed,
			"pdf_allowed": self.pdf_allowed,
			"upgrade_hint": None
			if self.plugin_active
			else "برای سقف بالاتر، افزونه گزارش‌ساز اسکریپتی را از بازار افزونه‌ها فعال کنید.",
		}


def _license_row(db: Session, business_id: int) -> tuple[Optional[BusinessPlugin], Optional[MarketplacePluginPlan]]:
	plugin = (
		db.query(MarketplacePlugin)
		.filter(
			MarketplacePlugin.code == PLUGIN_CODE,
			MarketplacePlugin.is_active.is_(True),
		)
		.first()
	)
	if not plugin:
		return None, None
	row = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == business_id,
			BusinessPlugin.plugin_id == plugin.id,
			BusinessPlugin.status == "active",
		)
		.first()
	)
	if not row:
		return None, None
	if row.ends_at:
		ea = row.ends_at
		ends_at_val = ea.date() if isinstance(ea, datetime) else ea
		if ends_at_val < datetime.utcnow().date():
			return None, None
	plan = db.query(MarketplacePluginPlan).filter(MarketplacePluginPlan.id == row.plan_id).first()
	return row, plan


def resolve_hscript_entitlement(db: Session, business_id: int) -> HScriptPlanEntitlement:
	"""بدون لایسنس = free؛ با لایسنس فعال = سقف بر اساس period پلن."""
	license_row, plan = _license_row(db, business_id)
	if not license_row:
		cfg = _TIER_LIMITS["free"]
		return HScriptPlanEntitlement(
			tier="free",
			plugin_active=False,
			plugin_code=PLUGIN_CODE,
			plan_period=None,
			is_trial=False,
			max_saved_reports=int(cfg["max_saved_reports"]),
			runs_per_minute=int(cfg["runs_per_minute"]),
			async_allowed=bool(cfg["async_allowed"]),
			excel_allowed=bool(cfg["excel_allowed"]),
			pdf_allowed=bool(cfg["pdf_allowed"]),
			resource=cfg["resource"],
			preview_resource=cfg["preview_resource"],
		)

	period = (plan.period if plan else "monthly") or "monthly"
	is_trial = bool(license_row.is_trial)
	tier = "trial" if is_trial else (period if period in _TIER_LIMITS else "monthly")
	cfg = _TIER_LIMITS[tier]
	return HScriptPlanEntitlement(
		tier=tier,
		plugin_active=True,
		plugin_code=PLUGIN_CODE,
		plan_period=period,
		is_trial=is_trial,
		max_saved_reports=int(cfg["max_saved_reports"]),
		runs_per_minute=int(cfg["runs_per_minute"]),
		async_allowed=bool(cfg["async_allowed"]),
		excel_allowed=bool(cfg["excel_allowed"]),
		pdf_allowed=bool(cfg["pdf_allowed"]),
		resource=cfg["resource"],
		preview_resource=cfg["preview_resource"],
	)


def check_hscript_plugin_active(db: Session, business_id: int) -> bool:
	return resolve_hscript_entitlement(db, business_id).plugin_active
