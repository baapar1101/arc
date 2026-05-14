"""تنظیمات و پروکسی پل REST ووکامرس (ArcWOC) از طریق BusinessPlugin.extra_info."""

from __future__ import annotations

import json
import os
from datetime import datetime
from typing import Any, Dict, Optional, Tuple
from urllib.parse import urlparse

import httpx
import structlog
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from adapters.db.models.marketplace import BusinessPlugin, MarketplacePlugin
from app.core.responses import ApiError
from app.core.woocommerce_dev_flags import (
	woocommerce_bridge_token_encrypt_enabled,
	woocommerce_bridge_tls_verify_enabled,
)
from app.core.woocommerce_bridge_rate_limit import enforce_woocommerce_bridge_rate_limit
from app.core.woocommerce_bridge_security import validate_woocommerce_store_base_url
from app.core.woocommerce_plugin_dependency import PLUGIN_CODE, check_woocommerce_plugin_active
from app.services.encryption_service import get_encryption_service

logger = structlog.get_logger(__name__)

EXTRA_INFO_KEY = "woocommerce_hesabix"
BRIDGE_HEADER = "X-Hesabix-Bridge-Token"
BRIDGE_REST_PREFIX = "/wp-json/hesabix/v1"
# پیشوند توکن ذخیره‌شدهٔ رمزشده (توکن‌های بدون این پیشوند به‌صورت متن سادهٔ قدیمی در نظر گرفته می‌شوند)
_WOOCOMMERCE_TOKEN_STORE_PREFIX = "wootok1:"


def _json_loads_safe(value: Optional[str]) -> Dict[str, Any]:
	if not value:
		return {}
	try:
		loaded = json.loads(value)
	except Exception:
		return {}
	return loaded if isinstance(loaded, dict) else {}


def _json_dumps_safe(value: Dict[str, Any]) -> str:
	return json.dumps(value, ensure_ascii=False)


def _encrypt_bridge_token_for_storage(plain: str) -> str:
	"""ذخیرهٔ توکن پل به‌صورت رمزشده در JSON (سازگار با دادهٔ قدیمی بدون پیشوند)."""
	s = (plain or "").strip()
	if not s:
		return ""
	if not woocommerce_bridge_token_encrypt_enabled():
		return s
	if s.startswith(_WOOCOMMERCE_TOKEN_STORE_PREFIX):
		return s
	try:
		enc = get_encryption_service().encrypt(s)
	except Exception as exc:
		logger.error("woocommerce_bridge_token_encrypt_failed", error=str(exc))
		raise ApiError(
			"WOOCOMMERCE_TOKEN_ENCRYPT_FAILED",
			"رمزنگاری توکن پل انجام نشد؛ تنظیمات سرور را بررسی کنید.",
			http_status=500,
		) from exc
	return _WOOCOMMERCE_TOKEN_STORE_PREFIX + enc


def _encrypt_bridge_token_always(plain: str) -> str:
	"""همیشه رمز می‌کند (مهاجرت دیتابیس؛ مستقل از پرچم dev)."""
	s = (plain or "").strip()
	if not s:
		return ""
	if s.startswith(_WOOCOMMERCE_TOKEN_STORE_PREFIX):
		return s
	try:
		enc = get_encryption_service().encrypt(s)
	except Exception as exc:
		logger.error("woocommerce_bridge_token_encrypt_failed", error=str(exc))
		raise ApiError(
			"WOOCOMMERCE_TOKEN_ENCRYPT_FAILED",
			"رمزنگاری توکن پل انجام نشد؛ تنظیمات سرور را بررسی کنید.",
			http_status=500,
		) from exc
	return _WOOCOMMERCE_TOKEN_STORE_PREFIX + enc


def _decrypt_bridge_token_for_use(stored: str) -> str:
	"""بازگرداندن توکن ساده برای هدر HTTP؛ دادهٔ قدیمی بدون پیشوند دست‌نخورده برمی‌گردد."""
	s = (stored or "").strip()
	if not s:
		return ""
	if s.startswith(_WOOCOMMERCE_TOKEN_STORE_PREFIX):
		payload = s[len(_WOOCOMMERCE_TOKEN_STORE_PREFIX) :]
		return get_encryption_service().decrypt(payload).strip()
	return s


def _find_plugin_row(db: Session) -> MarketplacePlugin:
	plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == PLUGIN_CODE).first()
	if not plugin:
		raise ApiError(
			"WOOCOMMERCE_PLUGIN_NOT_REGISTERED",
			"افزونهٔ ووکامرس در بازار ثبت نشده است.",
			http_status=404,
		)
	return plugin


def _find_business_plugin(db: Session, business_id: int) -> BusinessPlugin:
	plugin = _find_plugin_row(db)
	row = (
		db.query(BusinessPlugin)
		.filter(
			BusinessPlugin.business_id == int(business_id),
			BusinessPlugin.plugin_id == plugin.id,
		)
		.first()
	)
	if row:
		return row
	raise ApiError(
		"WOOCOMMERCE_LICENSE_NOT_FOUND",
		"افزونهٔ ووکامرس برای این کسب‌وکار از بازار فعال یا ثبت نشده است؛ ابتدا از «بازار افزونه‌ها» آن را فعال کنید.",
		http_status=403,
	)


def _default_settings() -> Dict[str, Any]:
	return {
		"store_base_url": "",
		"bridge_token": "",
		"updated_at": None,
	}


def _normalize_store_url(raw: str) -> str:
	u = (raw or "").strip().rstrip("/")
	if not u.startswith(("http://", "https://")):
		raise ApiError(
			"INVALID_STORE_URL",
			"آدرس فروشگاه باید با https:// یا http:// شروع شود.",
			http_status=400,
		)
	parsed = urlparse(u)
	if not parsed.netloc:
		raise ApiError("INVALID_STORE_URL", "آدرس فروشگاه نامعتبر است.", http_status=400)
	return u


def _normalize_settings(payload: Dict[str, Any], previous: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
	prev = previous if isinstance(previous, dict) else _default_settings()
	base = {**_default_settings(), **prev}
	base["store_base_url"] = str(payload.get("store_base_url") if "store_base_url" in payload else base.get("store_base_url") or "").strip().rstrip("/")
	if base["store_base_url"]:
		base["store_base_url"] = _normalize_store_url(base["store_base_url"])
		validate_woocommerce_store_base_url(base["store_base_url"])

	tok_in = payload.get("bridge_token") if "bridge_token" in payload else None
	if tok_in is not None:
		tok_s = str(tok_in).strip()
		if tok_s == "":
			base["bridge_token"] = ""
		elif tok_s == "***":
			base["bridge_token"] = str(prev.get("bridge_token") or "")
		else:
			base["bridge_token"] = tok_s
	base["updated_at"] = datetime.utcnow().isoformat()
	return base


def _mask_settings_for_client(settings: Dict[str, Any]) -> Dict[str, Any]:
	out = dict(settings)
	raw = str(out.get("bridge_token") or "")
	plain = _decrypt_bridge_token_for_use(raw) if raw else ""
	out["bridge_token_set"] = bool(plain)
	out["bridge_token"] = "***" if plain else ""
	return out


def get_settings(db: Session, business_id: int) -> Dict[str, Any]:
	if not check_woocommerce_plugin_active(db, int(business_id)):
		raise ApiError(
			"WOOCOMMERCE_PLUGIN_NOT_ACTIVE",
			"افزونهٔ ووکامرس برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": PLUGIN_CODE},
		)
	row = _find_business_plugin(db, business_id)
	extra = _json_loads_safe(row.extra_info)
	saved = extra.get(EXTRA_INFO_KEY)
	if not isinstance(saved, dict):
		saved = _default_settings()
	norm = _normalize_settings(saved, saved)
	return _mask_settings_for_client(norm)


def update_settings(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	if not check_woocommerce_plugin_active(db, int(business_id)):
		raise ApiError(
			"WOOCOMMERCE_PLUGIN_NOT_ACTIVE",
			"افزونهٔ ووکامرس برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": PLUGIN_CODE},
		)
	row = _find_business_plugin(db, business_id)
	extra = _json_loads_safe(row.extra_info)
	prev = extra.get(EXTRA_INFO_KEY) if isinstance(extra.get(EXTRA_INFO_KEY), dict) else _default_settings()
	settings = _normalize_settings(payload or {}, prev)
	# رمزنگاری توکن تازهٔ ارسالی از کلاینت (نه *** و نه خالی)
	if isinstance(payload, dict) and "bridge_token" in payload:
		raw_bt = payload.get("bridge_token")
		rs = str(raw_bt if raw_bt is not None else "").strip()
		if rs and rs != "***":
			if woocommerce_bridge_token_encrypt_enabled():
				settings["bridge_token"] = _encrypt_bridge_token_for_storage(rs)
			else:
				settings["bridge_token"] = rs
	extra[EXTRA_INFO_KEY] = settings
	row.extra_info = _json_dumps_safe(extra)
	flag_modified(row, "extra_info")
	row.updated_at = datetime.utcnow()
	db.add(row)
	db.commit()
	db.refresh(row)
	return _mask_settings_for_client(settings)


def _load_bridge_credentials(db: Session, business_id: int) -> Tuple[str, str]:
	if not check_woocommerce_plugin_active(db, int(business_id)):
		raise ApiError(
			"WOOCOMMERCE_PLUGIN_NOT_ACTIVE",
			"افزونهٔ ووکامرس برای این کسب‌وکار فعال نیست.",
			http_status=403,
			details={"plugin_code": PLUGIN_CODE},
		)
	row = _find_business_plugin(db, business_id)
	extra = _json_loads_safe(row.extra_info)
	saved = extra.get(EXTRA_INFO_KEY)
	if not isinstance(saved, dict):
		saved = _default_settings()
	settings = _normalize_settings(saved, saved)
	store = str(settings.get("store_base_url") or "").strip().rstrip("/")
	token_raw = str(settings.get("bridge_token") or "").strip()
	token = _decrypt_bridge_token_for_use(token_raw)
	if os.getenv("WOOCOMMERCE_BRIDGE_LOG_TOKEN_LEN", "").strip() == "1":
		logger.debug(
			"woocommerce_bridge_credentials_loaded",
			business_id=int(business_id),
			store_host=urlparse(store).hostname if store else None,
			token_len=len(token),
		)
	if store:
		validate_woocommerce_store_base_url(store)
	if not store or not token:
		raise ApiError(
			"WOOCOMMERCE_BRIDGE_NOT_CONFIGURED",
			"آدرس فروشگاه یا توکن پل در تنظیمات ذخیره نشده است.",
			http_status=400,
		)
	return _normalize_store_url(store), token


def _bridge_get(db: Session, business_id: int, path: str, params: Dict[str, Any]) -> Dict[str, Any]:
	enforce_woocommerce_bridge_rate_limit(int(business_id), path or "/")
	store, token = _load_bridge_credentials(db, business_id)
	url = store + BRIDGE_REST_PREFIX + path
	headers = {BRIDGE_HEADER: token, "Accept": "application/json"}
	try:
		with httpx.Client(
			timeout=45.0,
			follow_redirects=True,
			verify=woocommerce_bridge_tls_verify_enabled(),
		) as client:
			resp = client.get(url, headers=headers, params=params)
	except httpx.RequestError as exc:
		logger.warning(
			"woocommerce_bridge_network_error",
			business_id=int(business_id),
			path=path,
			error=str(exc),
		)
		raise ApiError(
			"WOOCOMMERCE_BRIDGE_NETWORK",
			f"خطا در اتصال به فروشگاه: {exc!s}",
			http_status=502,
		) from exc

	if resp.status_code == 401:
		logger.warning(
			"woocommerce_bridge_unauthorized",
			business_id=int(business_id),
			path=path,
		)
		raise ApiError("WOOCOMMERCE_BRIDGE_UNAUTHORIZED", "توکن پل نامعتبر است یا پل در وردپرس غیرفعال است.", http_status=401)
	if resp.status_code == 403:
		logger.warning(
			"woocommerce_bridge_forbidden",
			business_id=int(business_id),
			path=path,
		)
		raise ApiError("WOOCOMMERCE_BRIDGE_FORBIDDEN", "پل REST در وردپرس غیرفعال است.", http_status=403)
	if resp.status_code >= 400:
		logger.warning(
			"woocommerce_bridge_http_error",
			business_id=int(business_id),
			path=path,
			status_code=resp.status_code,
			body_len=len(resp.text or ""),
		)
		raise ApiError(
			"WOOCOMMERCE_BRIDGE_HTTP",
			f"پاسخ فروشگاه: HTTP {resp.status_code}",
			http_status=502,
			details={"body_preview": (resp.text or "")[:500]},
		)

	try:
		data = resp.json()
	except Exception as exc:
		logger.warning(
			"woocommerce_bridge_bad_json",
			business_id=int(business_id),
			path=path,
			error=str(exc),
		)
		raise ApiError("WOOCOMMERCE_BRIDGE_BAD_JSON", "پاسخ فروشگاه JSON معتبر نیست.", http_status=502) from exc

	if not isinstance(data, dict):
		raise ApiError("WOOCOMMERCE_BRIDGE_BAD_JSON", "ساختار پاسخ فروشگاه نامعتبر است.", http_status=502)
	return data


def _bridge_post(
	db: Session,
	business_id: int,
	path: str,
	json_body: Optional[Dict[str, Any]] = None,
	*,
	timeout_sec: float = 120.0,
) -> Dict[str, Any]:
	enforce_woocommerce_bridge_rate_limit(int(business_id), path or "/")
	store, token = _load_bridge_credentials(db, business_id)
	url = store + BRIDGE_REST_PREFIX + path
	headers = {BRIDGE_HEADER: token, "Accept": "application/json", "Content-Type": "application/json"}
	payload = json_body if isinstance(json_body, dict) else {}
	try:
		with httpx.Client(
			timeout=timeout_sec,
			follow_redirects=True,
			verify=woocommerce_bridge_tls_verify_enabled(),
		) as client:
			resp = client.post(url, headers=headers, json=payload)
	except httpx.RequestError as exc:
		logger.warning(
			"woocommerce_bridge_network_error",
			business_id=int(business_id),
			path=path,
			error=str(exc),
		)
		raise ApiError(
			"WOOCOMMERCE_BRIDGE_NETWORK",
			f"خطا در اتصال به فروشگاه: {exc!s}",
			http_status=502,
		) from exc

	if resp.status_code == 401:
		raise ApiError("WOOCOMMERCE_BRIDGE_UNAUTHORIZED", "توکن پل نامعتبر است یا پل در وردپرس غیرفعال است.", http_status=401)
	if resp.status_code == 403:
		raise ApiError("WOOCOMMERCE_BRIDGE_FORBIDDEN", "پل REST در وردپرس غیرفعال است.", http_status=403)
	if resp.status_code >= 400:
		logger.warning(
			"woocommerce_bridge_http_error",
			business_id=int(business_id),
			path=path,
			status_code=resp.status_code,
			body_len=len(resp.text or ""),
		)
		raise ApiError(
			"WOOCOMMERCE_BRIDGE_HTTP",
			f"پاسخ فروشگاه: HTTP {resp.status_code}",
			http_status=502,
			details={"body_preview": (resp.text or "")[:500]},
		)

	try:
		data = resp.json()
	except Exception as exc:
		logger.warning(
			"woocommerce_bridge_bad_json",
			business_id=int(business_id),
			path=path,
			error=str(exc),
		)
		raise ApiError("WOOCOMMERCE_BRIDGE_BAD_JSON", "پاسخ فروشگاه JSON معتبر نیست.", http_status=502) from exc

	if not isinstance(data, dict):
		raise ApiError("WOOCOMMERCE_BRIDGE_BAD_JSON", "ساختار پاسخ فروشگاه نامعتبر است.", http_status=502)
	return data


def _unwrap_bridge_body(body: Dict[str, Any], *, business_id: Optional[int] = None, path: str = "") -> Dict[str, Any]:
	if not body.get("success"):
		if business_id is not None:
			logger.warning(
				"woocommerce_bridge_logical_failure",
				business_id=int(business_id),
				path=path,
				message=str(body.get("message") or "")[:200],
			)
		raise ApiError(
			"WOOCOMMERCE_BRIDGE_FAILED",
			str(body.get("message") or "پاسخ ناموفق از فروشگاه."),
			http_status=502,
			details=body,
		)
	inner = body.get("data")
	if not isinstance(inner, dict):
		if business_id is not None:
			logger.warning(
				"woocommerce_bridge_bad_shape",
				business_id=int(business_id),
				path=path,
			)
		raise ApiError("WOOCOMMERCE_BRIDGE_BAD_SHAPE", "ساختار پاسخ فروشگاه نامعتبر است.", http_status=502)
	return inner


def test_bridge(db: Session, business_id: int) -> Dict[str, Any]:
	body = _bridge_get(db, business_id, "/health", {})
	inner = _unwrap_bridge_body(body, business_id=business_id, path="/health")
	return {"ok": True, "remote": inner}


def list_orders(
	db: Session,
	business_id: int,
	page: int = 1,
	per_page: int = 20,
	status: Optional[str] = None,
	after: Optional[str] = None,
	before: Optional[str] = None,
	customer_id: Optional[int] = None,
	search: Optional[str] = None,
	orderby: Optional[str] = None,
	order: Optional[str] = None,
) -> Dict[str, Any]:
	params: Dict[str, Any] = {"page": max(1, page), "per_page": max(1, min(50, per_page))}
	if status and str(status).strip():
		params["status"] = str(status).strip()
	if after and str(after).strip():
		params["after"] = str(after).strip()
	if before and str(before).strip():
		params["before"] = str(before).strip()
	if customer_id is not None and int(customer_id) > 0:
		params["customer_id"] = int(customer_id)
	if search and str(search).strip():
		params["search"] = str(search).strip()
	ob = (orderby or "").strip().lower()
	if ob in ("date", "modified", "id"):
		params["orderby"] = ob
	od = (order or "").strip().upper()
	if od in ("ASC", "DESC"):
		params["order"] = od
	return _unwrap_bridge_body(_bridge_get(db, business_id, "/orders", params), business_id=business_id, path="/orders")


def list_products(
	db: Session,
	business_id: int,
	page: int = 1,
	per_page: int = 20,
	search: Optional[str] = None,
) -> Dict[str, Any]:
	params: Dict[str, Any] = {"page": max(1, page), "per_page": max(1, min(50, per_page))}
	if search:
		params["search"] = search
	return _unwrap_bridge_body(_bridge_get(db, business_id, "/products", params), business_id=business_id, path="/products")


def list_customers(
	db: Session,
	business_id: int,
	page: int = 1,
	per_page: int = 20,
	search: Optional[str] = None,
) -> Dict[str, Any]:
	params: Dict[str, Any] = {"page": max(1, page), "per_page": max(1, min(50, per_page))}
	if search:
		params["search"] = search
	return _unwrap_bridge_body(_bridge_get(db, business_id, "/customers", params), business_id=business_id, path="/customers")


def reports_summary(
	db: Session,
	business_id: int,
	after: Optional[str] = None,
	before: Optional[str] = None,
) -> Dict[str, Any]:
	params: Dict[str, Any] = {}
	if after and str(after).strip():
		params["after"] = str(after).strip()
	if before and str(before).strip():
		params["before"] = str(before).strip()
	return _unwrap_bridge_body(
		_bridge_get(db, business_id, "/reports/summary", params),
		business_id=business_id,
		path="/reports/summary",
	)


def control_sync_stats(db: Session, business_id: int) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_get(db, business_id, "/control/sync-stats", {}),
		business_id=business_id,
		path="/control/sync-stats",
	)


def control_settings_summary(db: Session, business_id: int) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_get(db, business_id, "/control/settings-summary", {}),
		business_id=business_id,
		path="/control/settings-summary",
	)


def control_logs(
	db: Session,
	business_id: int,
	page: int = 1,
	per_page: int = 20,
	action: Optional[str] = None,
) -> Dict[str, Any]:
	params: Dict[str, Any] = {"page": max(1, page), "per_page": max(1, min(100, per_page))}
	if action and str(action).strip():
		params["action"] = str(action).strip()
	return _unwrap_bridge_body(
		_bridge_get(db, business_id, "/control/logs", params),
		business_id=business_id,
		path="/control/logs",
	)


def control_connection(db: Session, business_id: int) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_get(db, business_id, "/control/connection", {}),
		business_id=business_id,
		path="/control/connection",
	)


def control_plugin(db: Session, business_id: int) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_get(db, business_id, "/control/plugin", {}),
		business_id=business_id,
		path="/control/plugin",
	)


def post_control_sync_product(
	db: Session,
	business_id: int,
	*,
	product_id: int,
	variation_id: Optional[int] = None,
) -> Dict[str, Any]:
	body: Dict[str, Any] = {"product_id": int(product_id)}
	if variation_id is not None and int(variation_id) > 0:
		body["variation_id"] = int(variation_id)
	return _unwrap_bridge_body(
		_bridge_post(db, business_id, "/control/sync/product", body, timeout_sec=120.0),
		business_id=business_id,
		path="/control/sync/product",
	)


def post_control_sync_orders(db: Session, business_id: int, order_ids: list) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_post(db, business_id, "/control/sync/orders", {"order_ids": list(order_ids)}, timeout_sec=120.0),
		business_id=business_id,
		path="/control/sync/orders",
	)


def post_control_sync_products(db: Session, business_id: int, product_ids: list) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_post(db, business_id, "/control/sync/products", {"product_ids": list(product_ids)}, timeout_sec=120.0),
		business_id=business_id,
		path="/control/sync/products",
	)


def post_control_sync_customers(db: Session, business_id: int, customer_ids: list) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_post(db, business_id, "/control/sync/customers", {"customer_ids": list(customer_ids)}, timeout_sec=120.0),
		business_id=business_id,
		path="/control/sync/customers",
	)


def control_queue_snapshot(db: Session, business_id: int) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_get(db, business_id, "/control/queue/snapshot", {}),
		business_id=business_id,
		path="/control/queue/snapshot",
	)


def post_control_queue_process_once(db: Session, business_id: int) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_post(db, business_id, "/control/queue/process-once", {}, timeout_sec=120.0),
		business_id=business_id,
		path="/control/queue/process-once",
	)


def post_control_plugin_update_check(db: Session, business_id: int, *, force: bool = False) -> Dict[str, Any]:
	return _unwrap_bridge_body(
		_bridge_post(db, business_id, "/control/plugin/update-check", {"force": bool(force)}, timeout_sec=90.0),
		business_id=business_id,
		path="/control/plugin/update-check",
	)


def post_control_settings_patch(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	body = payload if isinstance(payload, dict) else {}
	return _unwrap_bridge_body(
		_bridge_post(db, business_id, "/control/settings/patch", body, timeout_sec=45.0),
		business_id=business_id,
		path="/control/settings/patch",
	)


def migrate_plaintext_woocommerce_bridge_tokens(db: Session) -> Dict[str, Any]:
	"""
	تمام ردیف‌های BusinessPlugin مربوط به افزونهٔ ووکامرس را اسکن می‌کند و
	توکن‌های بدون پیشوند ``wootok1:`` را با رمزنگاری Fernet ذخیره می‌کند.
	مستقل از ``WOOCOMMERCE_DEV_MODE`` است (برای پروداکشن پس از ارتقا).
	"""
	plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == PLUGIN_CODE).first()
	if not plugin:
		return {"ok": False, "error": "WOOCOMMERCE_PLUGIN_NOT_REGISTERED", "updated": 0, "scanned": 0}
	rows = db.query(BusinessPlugin).filter(BusinessPlugin.plugin_id == plugin.id).all()
	updated = 0
	scanned = 0
	for row in rows:
		scanned += 1
		extra = _json_loads_safe(row.extra_info)
		block = extra.get(EXTRA_INFO_KEY)
		if not isinstance(block, dict):
			continue
		tok = str(block.get("bridge_token") or "").strip()
		if not tok or tok.startswith(_WOOCOMMERCE_TOKEN_STORE_PREFIX):
			continue
		try:
			block["bridge_token"] = _encrypt_bridge_token_always(tok)
		except Exception as exc:
			logger.error(
				"woocommerce_token_migrate_row_failed",
				business_id=int(row.business_id),
				error=str(exc),
			)
			continue
		extra[EXTRA_INFO_KEY] = block
		row.extra_info = _json_dumps_safe(extra)
		flag_modified(row, "extra_info")
		row.updated_at = datetime.utcnow()
		db.add(row)
		updated += 1
	if updated:
		db.commit()
	logger.info("woocommerce_token_migrate_done", scanned=scanned, updated=updated)
	return {"ok": True, "scanned": scanned, "updated": updated}
