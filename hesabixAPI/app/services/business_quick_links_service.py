from __future__ import annotations

import re
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.business_user_quick_links import BusinessUserQuickLink

# کاتالوگ Presetها: id یکتا — route_name مطابق go_router name در hesabix_ui
QUICK_LINK_PRESETS: List[Dict[str, Any]] = [
	{
		"id": "new_invoice",
		"title": "فاکتور جدید",
		"icon": "note_add",
		"route_name": "business_new_invoice",
		"permissions_required": ["invoices.add"],
	},
	{
		"id": "invoices_list",
		"title": "فاکتورها",
		"icon": "receipt_long",
		"route_name": "business_invoice",
		"permissions_required": ["invoices.view"],
	},
	{
		"id": "receipts_payments",
		"title": "دریافت و پرداخت",
		"icon": "payments",
		"route_name": "business_receipts_payments",
		"permissions_required": ["people_transactions.view"],
	},
	{
		"id": "persons",
		"title": "اشخاص",
		"icon": "people",
		"route_name": "business_persons",
		"permissions_required": ["people.view"],
	},
	{
		"id": "products",
		"title": "کالاها",
		"icon": "inventory_2",
		"route_name": "business_products",
		"permissions_required": ["products.view"],
	},
	{
		"id": "documents",
		"title": "اسناد",
		"icon": "description",
		"route_name": "business_documents",
		"permissions_required": ["accounting_documents.view"],
	},
	{
		"id": "expense_income",
		"title": "هزینه و درآمد",
		"icon": "account_balance",
		"route_name": "business_expense_income",
		"permissions_required": ["expenses_income.view"],
	},
	{
		"id": "transfers",
		"title": "انتقال وجه",
		"icon": "swap_horiz",
		"route_name": "business_transfers",
		"permissions_required": ["transfers.view"],
	},
	{
		"id": "reports",
		"title": "گزارش‌ها",
		"icon": "assessment",
		"route_name": "business_reports",
		"permissions_required": ["reports.view"],
	},
	{
		"id": "bank_accounts",
		"title": "حساب‌های بانکی",
		"icon": "account_balance_wallet",
		"route_name": "business_accounts",
		"permissions_required": ["bank_accounts.view"],
	},
	{
		"id": "checks",
		"title": "چک‌ها",
		"icon": "request_quote",
		"route_name": "business_checks",
		"permissions_required": ["checks.view"],
	},
	{
		"id": "warehouses",
		"title": "انبارها",
		"icon": "warehouse",
		"route_name": "business_warehouses",
		"permissions_required": ["warehouses.view"],
	},
	{
		"id": "warehouse_docs",
		"title": "حواله انبار",
		"icon": "local_shipping",
		"route_name": "business_warehouse_docs",
		"permissions_required": ["warehouse_transfers.view"],
	},
	{
		"id": "quick_sales",
		"title": "فروش سریع",
		"icon": "point_of_sale",
		"route_name": "business_quick_sales",
		"permissions_required": ["invoices.add"],
	},
	{
		"id": "settings",
		"title": "تنظیمات",
		"icon": "settings",
		"route_name": "business_settings",
		"permissions_required": ["settings.join"],
	},
	{
		"id": "crm_dashboard",
		"title": "CRM",
		"icon": "hub",
		"route_name": "business_crm_dashboard_page",
		"permissions_required": ["crm.view"],
	},
]

_PRESET_BY_ID: Dict[str, Dict[str, Any]] = {p["id"]: p for p in QUICK_LINK_PRESETS}


def _check_preset_permissions(permissions_required: List[str], ctx: Any) -> bool:
	if not permissions_required:
		return True
	if ctx is None:
		return True
	if ctx.is_superadmin() or ctx.is_business_owner():
		return True
	for perm_str in permissions_required:
		if "." not in perm_str:
			continue
		section, action = perm_str.split(".", 1)
		if not ctx.has_business_permission(section, action):
			return False
	return True


def get_quick_link_presets_catalog(ctx: Any) -> Dict[str, Any]:
	"""فقط presetهایی که کاربر مجاز است."""
	items: List[Dict[str, Any]] = []
	for p in QUICK_LINK_PRESETS:
		perms = p.get("permissions_required") or []
		if not _check_preset_permissions(perms, ctx):
			continue
		items.append(
			{
				"id": p["id"],
				"title": p["title"],
				"icon": p.get("icon") or "link",
			}
		)
	return {"items": items}


def _default_seed_items() -> List[Dict[str, Any]]:
	"""مقادیر اولیه پس از ایجاد رکورد."""
	ids_order = [
		"new_invoice",
		"receipts_payments",
		"invoices_list",
		"persons",
		"products",
		"documents",
		"expense_income",
		"reports",
	]
	out: List[Dict[str, Any]] = []
	for pid in ids_order:
		if pid not in _PRESET_BY_ID:
			continue
		out.append(
			{
				"id": str(uuid.uuid4()),
				"kind": "preset",
				"preset_id": pid,
			}
		)
	return out


_MAX_ITEMS = 32
_MAX_URL_LEN = 2048
_URL_RE = re.compile(r"^https?://", re.IGNORECASE)


def _sanitize_url(url: str) -> Optional[str]:
	if not url or not isinstance(url, str):
		return None
	s = url.strip()
	if len(s) > _MAX_URL_LEN:
		return None
	if not _URL_RE.match(s):
		return None
	return s


def _sanitize_stored_item(raw: Dict[str, Any], ctx: Any) -> Optional[Dict[str, Any]]:
	kind = str(raw.get("kind") or "")
	iid = str(raw.get("id") or "").strip() or str(uuid.uuid4())
	if kind == "preset":
		pid = str(raw.get("preset_id") or "")
		if pid not in _PRESET_BY_ID:
			return None
		p = _PRESET_BY_ID[pid]
		if not _check_preset_permissions(p.get("permissions_required") or [], ctx):
			return None
		out: Dict[str, Any] = {
			"id": iid,
			"kind": "preset",
			"preset_id": pid,
		}
		ov = raw.get("title_override")
		if isinstance(ov, str) and ov.strip():
			out["title_override"] = ov.strip()[:128]
		return out
	if kind == "external":
		url = _sanitize_url(str(raw.get("url") or ""))
		if url is None:
			return None
		title = str(raw.get("title") or "لینک")
		return {
			"id": iid,
			"kind": "external",
			"url": url,
			"title": title[:200],
		}
	return None


def _row_to_api_dict(row: BusinessUserQuickLink) -> Dict[str, Any]:
	return {
		"items": list(row.items) if row.items else [],
		"updated_at": row.updated_at.isoformat() + "Z" if row.updated_at else "",
	}


def get_or_create_quick_links(
	db: Session,
	business_id: int,
	user_id: int,
) -> Dict[str, Any]:
	row = (
		db.query(BusinessUserQuickLink)
		.filter(
			BusinessUserQuickLink.business_id == business_id,
			BusinessUserQuickLink.user_id == user_id,
		)
		.first()
	)
	now = datetime.utcnow()
	if row is None:
		row = BusinessUserQuickLink(
			business_id=business_id,
			user_id=user_id,
			items=_default_seed_items(),
			created_at=now,
			updated_at=now,
		)
		db.add(row)
		db.flush()
	return _row_to_api_dict(row)


def save_quick_links(
	db: Session,
	business_id: int,
	user_id: int,
	items_in: List[Dict[str, Any]],
	ctx: Any,
) -> Dict[str, Any]:
	now = datetime.utcnow()
	clean: List[Dict[str, Any]] = []
	for raw in (items_in or [])[:_MAX_ITEMS]:
		if not isinstance(raw, dict):
			continue
		one = _sanitize_stored_item(raw, ctx)
		if one is not None:
			clean.append(one)

	row = (
		db.query(BusinessUserQuickLink)
		.filter(
			BusinessUserQuickLink.business_id == business_id,
			BusinessUserQuickLink.user_id == user_id,
		)
		.first()
	)
	if row is None:
		row = BusinessUserQuickLink(
			business_id=business_id,
			user_id=user_id,
			items=clean,
			created_at=now,
			updated_at=now,
		)
		db.add(row)
	else:
		row.items = clean
		row.updated_at = now
	db.flush()
	return _row_to_api_dict(row)


def _resolve_item_for_client(stored: Dict[str, Any], ctx: Any) -> Optional[Dict[str, Any]]:
	kind = stored.get("kind")
	if kind == "preset":
		pid = str(stored.get("preset_id") or "")
		p = _PRESET_BY_ID.get(pid)
		if p is None:
			return None
		if not _check_preset_permissions(p.get("permissions_required") or [], ctx):
			return None
		title = p["title"]
		ov = stored.get("title_override")
		if isinstance(ov, str) and ov.strip():
			title = ov.strip()[:128]
		return {
			"id": stored.get("id"),
			"kind": "internal",
			"title": title,
			"icon": p.get("icon") or "link",
			"route_name": p["route_name"],
		}
	if kind == "external":
		url = _sanitize_url(str(stored.get("url") or ""))
		if url is None:
			return None
		return {
			"id": stored.get("id"),
			"kind": "external",
			"title": str(stored.get("title") or "لینک")[:200],
			"icon": "link",
			"url": url,
		}
	return None


def build_quick_links_widget_data(
	db: Session,
	business_id: int,
	user_id: int,
	ctx: Any,
) -> Dict[str, Any]:
	"""داده برای ویجت داشبورد و بچ دیتا."""
	data = get_or_create_quick_links(db, business_id, user_id)
	raw_items: List[Dict[str, Any]] = list(data.get("items") or [])
	resolved: List[Dict[str, Any]] = []
	for it in raw_items:
		if not isinstance(it, dict):
			continue
		r = _resolve_item_for_client(it, ctx)
		if r is not None:
			resolved.append(r)
	return {
		"items": resolved,
		"updated_at": data.get("updated_at") or "",
	}
