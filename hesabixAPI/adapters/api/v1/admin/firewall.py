from __future__ import annotations

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError, success_response
from app.services import firewall_service as fw

router = APIRouter(prefix="/admin/firewall", tags=["فایروال داخلی"])


def _perm(ctx: AuthContext) -> None:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)


class FirewallRuleCreatePayload(BaseModel):
	action: str = Field(..., description="allow یا deny")
	ip_cidr: str
	path_prefix: Optional[str] = None
	http_methods: Optional[str] = Field(None, description="مثال GET,POST یا خالی برای همه")
	priority: int = 100
	expires_at: Optional[datetime] = Field(None, description="UTC؛ خالی = بدون انقضا")
	note: Optional[str] = None
	source: str = Field(default="manual", max_length=32)


class FirewallRuleUpdatePayload(BaseModel):
	enabled: Optional[bool] = None
	action: Optional[str] = None
	ip_cidr: Optional[str] = None
	path_prefix: Optional[str] = None
	http_methods: Optional[str] = None
	priority: Optional[int] = None
	expires_at: Optional[datetime] = None
	note: Optional[str] = None


class FirewallBanPayload(BaseModel):
	ip: str = Field(..., description="IP یا CIDR")
	duration_seconds: Optional[int] = Field(None, ge=1, description="خالی یا null = بن دائم (تا حذف دستی)")
	note: str = ""
	path_prefix: Optional[str] = None
	http_methods: Optional[str] = None
	priority: int = Field(10, description="اولویت کمتر = قوی‌تر")


class FirewallUnbanPayload(BaseModel):
	ip: str
	only_source: Optional[str] = Field(None, description="فقط قوانین با این source")


class FirewallRatePolicyCreatePayload(BaseModel):
	enabled: bool = True
	priority: int = 100
	path_prefix: str = Field(..., description="مثال /api/v1/public/crm-chat")
	http_methods: Optional[str] = Field(None, description="GET,POST یا خالی = همه")
	max_requests: int = Field(..., ge=1)
	window_seconds: int = Field(..., ge=1)
	note: Optional[str] = None


class FirewallRatePolicyUpdatePayload(BaseModel):
	enabled: Optional[bool] = None
	priority: Optional[int] = None
	path_prefix: Optional[str] = None
	http_methods: Optional[str] = None
	max_requests: Optional[int] = Field(None, ge=1)
	window_seconds: Optional[int] = Field(None, ge=1)
	note: Optional[str] = None


@router.get("/rules", summary="لیست قوانین فایروال")
def list_rules(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	active_only: bool = Query(False, description="فقط قوانین فعال (enabled و غیرمنقضی)"),
) -> dict:
	_perm(ctx)
	items = fw.list_rules(db)
	if active_only:
		now = datetime.utcnow()
		items = [
			x
			for x in items
			if x.get("enabled")
			and (not x.get("expires_at") or datetime.fromisoformat(x["expires_at"]) > now)
		]
	return success_response({"items": items, "count": len(items)}, request)


@router.post("/rules", summary="ایجاد قانون")
def create_rule_endpoint(
	request: Request,
	payload: FirewallRuleCreatePayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	try:
		row = fw.create_rule(
			db,
			action=payload.action,
			ip_cidr=payload.ip_cidr,
			path_prefix=payload.path_prefix,
			http_methods=payload.http_methods,
			priority=payload.priority,
			expires_at=payload.expires_at,
			note=payload.note,
			source=payload.source,
			created_by_user_id=ctx.get_user_id(),
		)
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400)
	fw.invalidate_rules_cache()
	return success_response(fw.rule_to_dict(row), request, message="FIREWALL_RULE_CREATED")


@router.put("/rules/{rule_id}", summary="ویرایش قانون")
def update_rule_endpoint(
	request: Request,
	rule_id: int,
	payload: FirewallRuleUpdatePayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	try:
		row = fw.update_rule(
			db,
			rule_id,
			enabled=payload.enabled,
			action=payload.action,
			ip_cidr=payload.ip_cidr,
			path_prefix=payload.path_prefix,
			http_methods=payload.http_methods,
			priority=payload.priority,
			expires_at=payload.expires_at,
			note=payload.note,
			actor_user_id=ctx.get_user_id(),
		)
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400)
	if not row:
		raise ApiError("NOT_FOUND", "Rule not found", http_status=404)
	fw.invalidate_rules_cache()
	return success_response(fw.rule_to_dict(row), request, message="FIREWALL_RULE_UPDATED")


@router.delete("/rules/{rule_id}", summary="حذف قانون")
def delete_rule_endpoint(
	request: Request,
	rule_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	ok = fw.delete_rule(db, rule_id, ctx.get_user_id())
	if not ok:
		raise ApiError("NOT_FOUND", "Rule not found", http_status=404)
	fw.invalidate_rules_cache()
	return success_response({"deleted": True, "id": rule_id}, request, message="FIREWALL_RULE_DELETED")


@router.post("/ban", summary="مسدودسازی IP (موقت یا دائم)")
def ban_endpoint(
	request: Request,
	payload: FirewallBanPayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	try:
		row = fw.ban_ip(
			db,
			payload.ip,
			duration_seconds=payload.duration_seconds,
			note=payload.note,
			path_prefix=payload.path_prefix,
			http_methods=payload.http_methods,
			priority=payload.priority,
			created_by_user_id=ctx.get_user_id(),
			source="api_ban",
		)
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400)
	fw.invalidate_rules_cache()
	return success_response(fw.rule_to_dict(row), request, message="FIREWALL_BAN_APPLIED")


@router.post("/unban", summary="رفع مسدودیت برای IP / CIDR")
def unban_endpoint(
	request: Request,
	payload: FirewallUnbanPayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	try:
		n = fw.unban_ip(db, payload.ip, actor_user_id=ctx.get_user_id(), only_source=payload.only_source)
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400)
	fw.invalidate_rules_cache()
	return success_response({"removed_rules": n}, request, message="FIREWALL_UNBAN_APPLIED")


@router.get("/rate-policies", summary="سیاست‌های نرخ (فایروال مرکزی / دیتابیس)")
def list_rate_policies(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	items = fw.list_rate_policies(db)
	return success_response({"items": items, "count": len(items)}, request)


@router.post("/rate-policies", summary="ایجاد سیاست نرخ")
def create_rate_policy_endpoint(
	request: Request,
	payload: FirewallRatePolicyCreatePayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	try:
		row = fw.create_rate_policy(
			db,
			enabled=payload.enabled,
			priority=payload.priority,
			path_prefix=payload.path_prefix,
			http_methods=payload.http_methods,
			max_requests=payload.max_requests,
			window_seconds=payload.window_seconds,
			note=payload.note,
		)
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400) from e
	fw.invalidate_rate_policies_cache()
	return success_response(fw.rate_policy_to_dict(row), request, message="FIREWALL_RATE_POLICY_CREATED")


@router.put("/rate-policies/{policy_id}", summary="ویرایش سیاست نرخ")
def update_rate_policy_endpoint(
	request: Request,
	policy_id: int,
	payload: FirewallRatePolicyUpdatePayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	try:
		row = fw.update_rate_policy(
			db,
			policy_id,
			enabled=payload.enabled,
			priority=payload.priority,
			path_prefix=payload.path_prefix,
			http_methods=payload.http_methods,
			max_requests=payload.max_requests,
			window_seconds=payload.window_seconds,
			note=payload.note,
		)
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400) from e
	if not row:
		raise ApiError("NOT_FOUND", "Policy not found", http_status=404)
	fw.invalidate_rate_policies_cache()
	return success_response(fw.rate_policy_to_dict(row), request, message="FIREWALL_RATE_POLICY_UPDATED")


@router.delete("/rate-policies/{policy_id}", summary="حذف سیاست نرخ")
def delete_rate_policy_endpoint(
	request: Request,
	policy_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_perm(ctx)
	ok = fw.delete_rate_policy(db, policy_id)
	if not ok:
		raise ApiError("NOT_FOUND", "Policy not found", http_status=404)
	fw.invalidate_rate_policies_cache()
	return success_response({"deleted": True, "id": policy_id}, request, message="FIREWALL_RATE_POLICY_DELETED")


@router.get("/logs/requests", summary="لاگ درخواست‌های مسدود شده")
def request_logs(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	skip: int = Query(0, ge=0),
	limit: int = Query(50, ge=1, le=200),
	client_ip: Optional[str] = None,
	hours: Optional[int] = Query(None, ge=1, le=720, description="فیلتر از N ساعت اخیر"),
) -> dict:
	_perm(ctx)
	since = None
	if hours:
		from datetime import timedelta

		since = datetime.utcnow() - timedelta(hours=hours)
	items, total = fw.list_request_logs(db, skip=skip, limit=limit, client_ip=client_ip, since=since)
	return success_response({"items": items, "total": total, "skip": skip, "limit": limit}, request)


@router.get("/logs/audit", summary="لاگ ممیزی مدیریتی")
def audit_logs(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	skip: int = Query(0, ge=0),
	limit: int = Query(50, ge=1, le=200),
	hours: Optional[int] = Query(None, ge=1, le=720),
) -> dict:
	_perm(ctx)
	since = None
	if hours:
		from datetime import timedelta

		since = datetime.utcnow() - timedelta(hours=hours)
	items, total = fw.list_audit_logs(db, skip=skip, limit=limit, since=since)
	return success_response({"items": items, "total": total, "skip": skip, "limit": limit}, request)


@router.get("/reports/summary", summary="گزارش خلاصه مسدودسازی‌ها")
def reports_summary(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	days: int = Query(7, ge=1, le=90),
) -> dict:
	_perm(ctx)
	data = fw.reports_summary(db, days=days)
	return success_response(data, request)
