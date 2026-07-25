from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional, Tuple

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.business_currency_rate import BusinessCurrencyRate
from adapters.db.models.currency import BusinessCurrency, Currency
from adapters.db.models.fx_rate_provider import FxGlobalRate, FxRateProvider
from app.core.responses import ApiError
from app.services.encryption_service import get_encryption_service

logger = logging.getLogger(__name__)

ENV_BRSAPI_KEY = "HESABIX_FX_BRSAPI_API_KEY"
ENV_MESGHAL_KEY = "HESABIX_FX_MESGHAL_API_KEY"
DEFAULT_BRS_BASE = "https://Api.BrsApi.ir"
DEFAULT_BRS_PATH = "/Market/Gold_Currency.php"
DEFAULT_MESGHAL_BASE = "https://api.tala.ir"
DEFAULT_MESGHAL_PATH = "/v1/rates"
DEFAULT_MESGHAL_SYMBOL_MAP = {
	"USD": "USD",
	"DOLLAR": "USD",
	"USDT": "USD",
	"EUR": "EUR",
	"EURO": "EUR",
	"GBP": "GBP",
	"AED": "AED",
	"TRY": "TRY",
	"CNY": "CNY",
	"JPY": "JPY",
	"CAD": "CAD",
	"AUD": "AUD",
	"CHF": "CHF",
	"IQD": "IQD",
	"SAR": "SAR",
	"KWD": "KWD",
	"QAR": "QAR",
	"OMR": "OMR",
	"BHD": "BHD",
	"RUB": "RUB",
}


def business_is_multi_currency(db: Session, business_id: int) -> bool:
	"""حداقل یک ارز فرعی غیر از ارز اصلی = چندارزی."""
	b = db.get(Business, int(business_id))
	if not b or b.default_currency_id is None:
		return False
	default_id = int(b.default_currency_id)
	q = select(BusinessCurrency.id).where(
		BusinessCurrency.business_id == int(business_id),
		BusinessCurrency.currency_id != default_id,
	).limit(1)
	return db.execute(q).scalar_one_or_none() is not None


def assert_multi_currency(db: Session, business_id: int) -> None:
	if not business_is_multi_currency(db, business_id):
		raise ApiError(
			"MULTI_CURRENCY_REQUIRED",
			"این قابلیت فقط برای کسب‌وکارهای چندارزی فعال است. ابتدا ارز فرعی اضافه کنید.",
			http_status=400,
		)


def _parse_config(raw: str | None) -> Dict[str, Any]:
	if not raw:
		return {}
	try:
		data = json.loads(raw)
		return data if isinstance(data, dict) else {}
	except Exception:
		return {}


def _encrypt_key(plain: str) -> str:
	return get_encryption_service().encrypt(plain)


def _decrypt_key(enc: str | None) -> str:
	if not enc:
		return ""
	try:
		return get_encryption_service().decrypt(enc)
	except Exception:
		# ممکن است مقدار قدیمی plaintext باشد
		return enc


def resolve_provider_api_key(provider: FxRateProvider) -> str:
	key = _decrypt_key(provider.api_key_encrypted)
	if key.strip():
		return key.strip()
	if provider.code == "brsapi":
		env_key = (os.getenv(ENV_BRSAPI_KEY) or "").strip()
		if env_key:
			return env_key
	if provider.code == "mesghal":
		env_key = (os.getenv(ENV_MESGHAL_KEY) or "").strip()
		if env_key:
			return env_key
	return ""


def serialize_provider(provider: FxRateProvider, *, include_sensitive: bool = False) -> Dict[str, Any]:
	has_db_key = bool(_decrypt_key(provider.api_key_encrypted).strip())
	has_resolved = bool(resolve_provider_api_key(provider))
	out: Dict[str, Any] = {
		"id": provider.id,
		"code": provider.code,
		"display_name": provider.display_name,
		"api_base_url": provider.api_base_url,
		"is_active": bool(provider.is_active),
		"fetch_interval_seconds": int(provider.fetch_interval_seconds or 900),
		"config": _parse_config(provider.config_json),
		"has_api_key": has_resolved,
		"has_db_api_key": has_db_key,
		"api_key_source": ("db" if has_db_key else ("env" if has_resolved else None)),
		"api_key": "***" if has_resolved else None,
		"last_fetch_at": provider.last_fetch_at,
		"last_fetch_status": provider.last_fetch_status,
		"last_fetch_error": provider.last_fetch_error,
		"last_fetch_http_status": provider.last_fetch_http_status,
		"created_at": provider.created_at,
		"updated_at": provider.updated_at,
	}
	if include_sensitive:
		out["api_key_resolved_len"] = len(resolve_provider_api_key(provider))
	return out



def list_providers(db: Session) -> List[Dict[str, Any]]:
	rows = db.execute(select(FxRateProvider).order_by(FxRateProvider.id)).scalars().all()
	return [serialize_provider(r) for r in rows]


def get_provider_by_code(db: Session, code: str) -> FxRateProvider:
	row = db.execute(
		select(FxRateProvider).where(FxRateProvider.code == code.strip().lower())
	).scalar_one_or_none()
	if not row:
		raise ApiError("FX_PROVIDER_NOT_FOUND", "ارائه‌دهنده یافت نشد", http_status=404)
	return row


def upsert_provider(db: Session, code: str, data: Dict[str, Any]) -> Dict[str, Any]:
	code_n = code.strip().lower()
	row = db.execute(select(FxRateProvider).where(FxRateProvider.code == code_n)).scalar_one_or_none()
	now = datetime.now(timezone.utc)
	if row is None:
		row = FxRateProvider(
			code=code_n,
			display_name=str(data.get("display_name") or code_n),
			api_base_url=data.get("api_base_url"),
			is_active=bool(data.get("is_active", True)),
			fetch_interval_seconds=int(data.get("fetch_interval_seconds") or 900),
			config_json=None,
			created_at=now,
			updated_at=now,
		)
		db.add(row)

	if data.get("display_name"):
		row.display_name = str(data["display_name"]).strip()
	if "api_base_url" in data:
		row.api_base_url = (str(data["api_base_url"]).strip() or None) if data["api_base_url"] is not None else None
	if "is_active" in data and data["is_active"] is not None:
		row.is_active = bool(data["is_active"])
	if "fetch_interval_seconds" in data and data["fetch_interval_seconds"] is not None:
		iv = int(data["fetch_interval_seconds"])
		if iv < 60:
			raise ApiError("FX_INTERVAL_INVALID", "بازه واکشی نباید کمتر از ۶۰ ثانیه باشد", http_status=400)
		if iv > 86400:
			raise ApiError("FX_INTERVAL_INVALID", "بازه واکشی بیش از حد بزرگ است", http_status=400)
		row.fetch_interval_seconds = iv
	if "config" in data and data["config"] is not None:
		if not isinstance(data["config"], dict):
			raise ApiError("FX_CONFIG_INVALID", "config باید شیء JSON باشد", http_status=400)
		row.config_json = json.dumps(data["config"], ensure_ascii=False)
	# api_key خالی = حفظ قبلی
	raw_key = data.get("api_key")
	if raw_key is not None and str(raw_key).strip() and str(raw_key).strip() != "***":
		row.api_key_encrypted = _encrypt_key(str(raw_key).strip())

	row.updated_at = now
	db.flush()
	db.refresh(row)
	return serialize_provider(row)


def serialize_global_rate(row: FxGlobalRate, *, provider_code: str | None = None) -> Dict[str, Any]:
	return {
		"id": row.id,
		"provider_id": row.provider_id,
		"provider_code": provider_code,
		"symbol": row.symbol,
		"currency_code": row.currency_code,
		"price_quote": str(row.price_quote),
		"quote_unit": row.quote_unit,
		"price_irr": str(row.price_irr),
		"name_fa": row.name_fa,
		"name_en": row.name_en,
		"source_time": row.source_time,
		"fetched_at": row.fetched_at,
	}


def list_global_rates(
	db: Session,
	*,
	provider_code: Optional[str] = None,
	currency_code: Optional[str] = None,
) -> List[Dict[str, Any]]:
	q = select(FxGlobalRate, FxRateProvider.code).join(
		FxRateProvider, FxGlobalRate.provider_id == FxRateProvider.id
	)
	if provider_code:
		q = q.where(FxRateProvider.code == provider_code.strip().lower())
	if currency_code:
		q = q.where(FxGlobalRate.currency_code == currency_code.strip().upper())
	q = q.order_by(FxGlobalRate.currency_code, FxGlobalRate.symbol)
	rows = db.execute(q).all()
	return [serialize_global_rate(r, provider_code=code) for r, code in rows]


def _to_decimal(v: Any) -> Decimal:
	try:
		return Decimal(str(v).replace(",", "").strip())
	except (InvalidOperation, ValueError, TypeError) as exc:
		raise ApiError("FX_PRICE_INVALID", f"قیمت نامعتبر: {v}", http_status=400) from exc


def _quote_to_irr(price_quote: Decimal, quote_unit: str, divisor: Decimal) -> Decimal:
	unit = (quote_unit or "IRT").upper()
	per_unit = price_quote / divisor if divisor != 0 else price_quote
	if unit in ("IRT", "TOMAN", "TMN"):
		return per_unit * Decimal(10)
	if unit in ("IRR", "RIAL"):
		return per_unit
	# پیش‌فرض: تومان
	return per_unit * Decimal(10)


def _normalize_currency_items(
	items: List[Dict[str, Any]],
	config: Dict[str, Any],
) -> List[Dict[str, Any]]:
	symbol_map: Dict[str, str] = dict(config.get("symbol_map") or {})
	divisors: Dict[str, Any] = dict(config.get("symbol_divisors") or {})
	default_quote = str(config.get("quote_unit") or "IRT").upper()
	out: List[Dict[str, Any]] = []
	for it in items:
		symbol = str(it.get("symbol") or "").strip().upper()
		if not symbol:
			continue
		mapped = symbol_map.get(symbol) or symbol_map.get(it.get("symbol") or "") or symbol
		# USDT_IRT etc.
		if mapped == symbol and "_" in symbol:
			mapped = symbol_map.get(symbol) or symbol.split("_")[0]
		div = Decimal(str(divisors.get(symbol) or divisors.get(mapped) or 1))
		price = _to_decimal(it.get("price"))
		unit_raw = str(it.get("unit") or default_quote)
		quote_unit = "IRT" if "تومان" in unit_raw or unit_raw.upper() in ("IRT", "TOMAN", "TMN") else (
			"IRR" if "ریال" in unit_raw or unit_raw.upper() in ("IRR", "RIAL") else default_quote
		)
		price_irr = _quote_to_irr(price, quote_unit, div)
		source_time = None
		tu = it.get("time_unix")
		if tu is not None:
			try:
				source_time = datetime.fromtimestamp(int(tu), tz=timezone.utc)
			except Exception:
				source_time = None
		out.append(
			{
				"symbol": symbol,
				"currency_code": str(mapped).upper(),
				"price_quote": price,
				"quote_unit": quote_unit,
				"price_irr": price_irr,
				"name_fa": it.get("name"),
				"name_en": it.get("name_en"),
				"source_time": source_time,
				"raw": it,
			}
		)
	return out


def fetch_brsapi_currency_payload(api_key: str, base_url: str, path: str) -> Tuple[Dict[str, Any], int]:
	base = (base_url or DEFAULT_BRS_BASE).rstrip("/")
	p = path if path.startswith("/") else f"/{path}"
	url = f"{base}{p}"
	headers = {
		"User-Agent": "HesabixFX/1.0 (+https://hesabix.ir)",
		"Accept": "application/json,text/plain,*/*",
	}
	last_exc: Exception | None = None
	with httpx.Client(timeout=45.0, headers=headers, follow_redirects=True) as client:
		for attempt in range(3):
			try:
				resp = client.get(url, params={"key": api_key})
				http_status = int(resp.status_code)
				try:
					payload = resp.json()
				except Exception as exc:
					raise ApiError(
						"FX_PROVIDER_BAD_RESPONSE",
						f"پاسخ JSON نامعتبر از ارائه‌دهنده (HTTP {http_status})",
						http_status=502,
					) from exc
				if http_status >= 400:
					msg = payload.get("message_error") if isinstance(payload, dict) else None
					raise ApiError(
						"FX_PROVIDER_HTTP_ERROR",
						msg or f"خطای HTTP {http_status} از ارائه‌دهنده",
						http_status=502,
					)
				if isinstance(payload, dict) and payload.get("successful") is False:
					raise ApiError(
						"FX_PROVIDER_REJECTED",
						str(payload.get("message_error") or "درخواست توسط ارائه‌دهنده رد شد"),
						http_status=502,
					)
				if not isinstance(payload, dict):
					raise ApiError("FX_PROVIDER_BAD_RESPONSE", "ساختار پاسخ نامعتبر است", http_status=502)
				return payload, http_status
			except ApiError:
				raise
			except Exception as exc:
				last_exc = exc
				if attempt < 2:
					continue
	raise ApiError(
		"FX_PROVIDER_NETWORK",
		f"خطای شبکه هنگام تماس با ارائه‌دهنده: {last_exc}",
		http_status=502,
	) from last_exc


def _dig_path(payload: Any, path: str) -> Any:
	"""استخراج مقدار از مسیر نقطه‌ای مثل rates یا data.items."""
	cur = payload
	for part in (path or "").split("."):
		part = part.strip()
		if not part:
			continue
		if not isinstance(cur, dict):
			return None
		cur = cur.get(part)
	return cur


def _map_raw_items_to_currency_shape(
	raw_items: List[Any],
	cfg: Dict[str, Any],
) -> List[Dict[str, Any]]:
	"""نرمال‌سازی آیتم‌های خام به شکل BRS-like برای _normalize_currency_items."""
	symbol_field = str(cfg.get("item_symbol_field") or "symbol")
	price_field = str(cfg.get("item_price_field") or "price")
	name_field = str(cfg.get("item_name_field") or "name")
	unit_field = str(cfg.get("item_unit_field") or "unit")
	out: List[Dict[str, Any]] = []
	for it in raw_items:
		if not isinstance(it, dict):
			continue
		# BRS native already has symbol/price
		if "symbol" in it and "price" in it and symbol_field == "symbol":
			out.append(it)
			continue
		symbol = it.get(symbol_field) or it.get("symbol") or it.get("key") or it.get("code")
		price = it.get(price_field) or it.get("price") or it.get("value") or it.get("sell")
		if symbol is None or price is None:
			continue
		unit = it.get(unit_field) or it.get("unit") or it.get("currency") or cfg.get("quote_unit") or "IRT"
		out.append(
			{
				"symbol": str(symbol).strip().upper(),
				"price": price,
				"name": it.get(name_field) or it.get("title") or it.get("name"),
				"name_en": it.get("name_en"),
				"unit": unit,
				"time_unix": it.get("time_unix"),
			}
		)
	return out


def extract_currency_items_from_provider_payload(
	payload: Dict[str, Any],
	cfg: Dict[str, Any],
) -> List[Dict[str, Any]]:
	"""استخراج لیست ارز از پاسخ JSON عمومی (BRS / Tala / سفارشی)."""
	items_path = str(cfg.get("items_path") or "").strip()
	raw: Any = None
	if items_path:
		raw = _dig_path(payload, items_path)
	if raw is None and isinstance(payload.get("currency"), list):
		raw = payload["currency"]
	if raw is None and isinstance(payload.get("rates"), list):
		raw = payload["rates"]
	if raw is None and isinstance(payload.get("data"), list):
		raw = payload["data"]
	if not isinstance(raw, list):
		raise ApiError(
			"FX_PROVIDER_BAD_RESPONSE",
			"لیست نرخ ارز در پاسخ ارائه‌دهنده یافت نشد (items_path را در config بررسی کنید)",
			http_status=502,
		)
	return _map_raw_items_to_currency_shape(raw, cfg)


def fetch_mesghal_currency_payload(
	api_key: str,
	base_url: str,
	path: str,
	*,
	auth_type: str = "header",
	auth_name: str = "x-api-key",
) -> Tuple[Dict[str, Any], int]:
	"""
	واکشی JSON عمومی برای provider دوم (mesghal).
	پیش‌فرض سازگار با api.tala.ir (x-api-key) و قابل پیکربندی برای سایر APIها.
	"""
	base = (base_url or DEFAULT_MESGHAL_BASE).rstrip("/")
	p = path if path.startswith("/") else f"/{path}"
	url = f"{base}{p}"
	headers = {
		"User-Agent": "HesabixFX/1.0 (+https://hesabix.ir)",
		"Accept": "application/json,text/plain,*/*",
	}
	params: Dict[str, str] = {}
	atype = (auth_type or "header").strip().lower()
	aname = (auth_name or "x-api-key").strip() or "x-api-key"
	if api_key:
		if atype == "query":
			params[aname] = api_key
		else:
			headers[aname] = api_key

	last_exc: Exception | None = None
	with httpx.Client(timeout=45.0, headers=headers, follow_redirects=True) as client:
		for attempt in range(3):
			try:
				resp = client.get(url, params=params or None)
				http_status = int(resp.status_code)
				try:
					payload = resp.json()
				except Exception as exc:
					raise ApiError(
						"FX_PROVIDER_BAD_RESPONSE",
						f"پاسخ JSON نامعتبر از مثقال/ارائه‌دهنده دوم (HTTP {http_status})",
						http_status=502,
					) from exc
				if http_status >= 400:
					msg = None
					if isinstance(payload, dict):
						msg = payload.get("message") or payload.get("error") or payload.get("message_error")
					raise ApiError(
						"FX_PROVIDER_HTTP_ERROR",
						str(msg or f"خطای HTTP {http_status} از ارائه‌دهنده دوم"),
						http_status=502,
					)
				if not isinstance(payload, dict):
					raise ApiError("FX_PROVIDER_BAD_RESPONSE", "ساختار پاسخ نامعتبر است", http_status=502)
				return payload, http_status
			except ApiError:
				raise
			except Exception as exc:
				last_exc = exc
				if attempt < 2:
					continue
	raise ApiError(
		"FX_PROVIDER_NETWORK",
		f"خطای شبکه هنگام تماس با ارائه‌دهنده دوم: {last_exc}",
		http_status=502,
	) from last_exc


def _mesghal_effective_config(provider: FxRateProvider) -> Dict[str, Any]:
	cfg = _parse_config(provider.config_json)
	# پیش‌فرض‌های سازگار با Tala API اگر ادمین هنوز config خالی گذاشته
	if not cfg.get("symbol_map"):
		cfg["symbol_map"] = dict(DEFAULT_MESGHAL_SYMBOL_MAP)
	else:
		merged = dict(DEFAULT_MESGHAL_SYMBOL_MAP)
		merged.update({str(k).upper(): str(v).upper() for k, v in dict(cfg["symbol_map"]).items()})
		cfg["symbol_map"] = merged
	cfg.setdefault("quote_unit", "IRT")
	cfg.setdefault("endpoint_path", DEFAULT_MESGHAL_PATH)
	cfg.setdefault("items_path", "rates")
	cfg.setdefault("item_symbol_field", "key")
	cfg.setdefault("item_price_field", "value")
	cfg.setdefault("item_name_field", "title")
	cfg.setdefault("item_unit_field", "currency")
	cfg.setdefault("auth_type", "header")
	cfg.setdefault("auth_name", "x-api-key")
	return cfg


def upsert_global_rates_from_normalized(
	db: Session,
	provider: FxRateProvider,
	normalized: List[Dict[str, Any]],
	*,
	fetched_at: datetime,
) -> int:
	count = 0
	for item in normalized:
		existing = db.execute(
			select(FxGlobalRate).where(
				FxGlobalRate.provider_id == provider.id,
				FxGlobalRate.symbol == item["symbol"],
			)
		).scalar_one_or_none()
		raw_s = None
		try:
			raw_s = json.dumps(item.get("raw") or {}, ensure_ascii=False, default=str)
		except Exception:
			raw_s = None
		if existing is None:
			existing = FxGlobalRate(
				provider_id=provider.id,
				symbol=item["symbol"],
				currency_code=item["currency_code"],
				price_quote=item["price_quote"],
				quote_unit=item["quote_unit"],
				price_irr=item["price_irr"],
				name_fa=item.get("name_fa"),
				name_en=item.get("name_en"),
				source_time=item.get("source_time"),
				fetched_at=fetched_at,
				raw_json=raw_s,
			)
			db.add(existing)
		else:
			existing.currency_code = item["currency_code"]
			existing.price_quote = item["price_quote"]
			existing.quote_unit = item["quote_unit"]
			existing.price_irr = item["price_irr"]
			existing.name_fa = item.get("name_fa")
			existing.name_en = item.get("name_en")
			existing.source_time = item.get("source_time")
			existing.fetched_at = fetched_at
			existing.raw_json = raw_s
		count += 1
	db.flush()
	return count


def fetch_and_store_provider(db: Session, provider: FxRateProvider) -> Dict[str, Any]:
	"""واکشی از provider و ذخیره اسنپ‌شات. فقط مسیرهای پیاده‌سازی‌شده."""
	now = datetime.now(timezone.utc)
	code = provider.code
	try:
		if code == "brsapi":
			api_key = resolve_provider_api_key(provider)
			if not api_key:
				raise ApiError(
					"FX_API_KEY_MISSING",
					"کلید API برای BRS تنظیم نشده است (ادمین یا متغیر محیطی HESABIX_FX_BRSAPI_API_KEY)",
					http_status=400,
				)
			cfg = _parse_config(provider.config_json)
			path = str(cfg.get("endpoint_path") or DEFAULT_BRS_PATH)
			payload, http_status = fetch_brsapi_currency_payload(
				api_key,
				provider.api_base_url or DEFAULT_BRS_BASE,
				path,
			)
			currency_items = payload.get("currency") if isinstance(payload.get("currency"), list) else []
			normalized = _normalize_currency_items(currency_items, cfg)
			n = upsert_global_rates_from_normalized(db, provider, normalized, fetched_at=now)
			provider.last_fetch_at = now
			provider.last_fetch_status = "ok"
			provider.last_fetch_error = None
			provider.last_fetch_http_status = http_status
			provider.updated_at = now
			db.flush()
			return {
				"provider": provider.code,
				"status": "ok",
				"http_status": http_status,
				"rates_upserted": n,
				"fetched_at": now,
			}
		if code == "mesghal":
			api_key = resolve_provider_api_key(provider)
			if not api_key:
				raise ApiError(
					"FX_API_KEY_MISSING",
					"کلید API برای مثقال/ارائه‌دهنده دوم تنظیم نشده است (ادمین یا HESABIX_FX_MESGHAL_API_KEY)",
					http_status=400,
				)
			cfg = _mesghal_effective_config(provider)
			path = str(cfg.get("endpoint_path") or DEFAULT_MESGHAL_PATH)
			base = provider.api_base_url or DEFAULT_MESGHAL_BASE
			payload, http_status = fetch_mesghal_currency_payload(
				api_key,
				base,
				path,
				auth_type=str(cfg.get("auth_type") or "header"),
				auth_name=str(cfg.get("auth_name") or "x-api-key"),
			)
			currency_items = extract_currency_items_from_provider_payload(payload, cfg)
			# فقط نمادهایی که به ارز نگاشت می‌شوند (نه طلا/سکه) — یا همه با map
			normalized = _normalize_currency_items(currency_items, cfg)
			# فیلتر: فقط currency_codeهای شناخته‌شده ۳ حرفی رایج مگر include_all
			if not bool(cfg.get("include_all_symbols")):
				normalized = [
					n for n in normalized
					if len(str(n.get("currency_code") or "")) == 3
					and str(n.get("currency_code")).upper() not in ("IRR", "IRT", "XAU")
				]
			n = upsert_global_rates_from_normalized(db, provider, normalized, fetched_at=now)
			provider.last_fetch_at = now
			provider.last_fetch_status = "ok"
			provider.last_fetch_error = None
			provider.last_fetch_http_status = http_status
			if not provider.api_base_url:
				provider.api_base_url = DEFAULT_MESGHAL_BASE
			provider.updated_at = now
			db.flush()
			return {
				"provider": provider.code,
				"status": "ok",
				"http_status": http_status,
				"rates_upserted": n,
				"fetched_at": now,
			}
		raise ApiError(
			"FX_PROVIDER_NOT_IMPLEMENTED",
			f"واکشی برای ارائه‌دهنده «{code}» پیاده‌سازی نشده است",
			http_status=501,
		)
	except ApiError as e:
		provider.last_fetch_at = now
		provider.last_fetch_status = "error"
		detail = getattr(e, "detail", None)
		msg = None
		if isinstance(detail, dict) and isinstance(detail.get("error"), dict):
			msg = detail["error"].get("message")
		provider.last_fetch_error = msg or str(e)
		provider.last_fetch_http_status = None
		provider.updated_at = now
		db.flush()
		raise


def test_provider_connection(db: Session, provider: FxRateProvider) -> Dict[str, Any]:
	"""تست سبک: fetch بدون الزام به commit جدا — caller commit می‌کند."""
	result = fetch_and_store_provider(db, provider)
	sample = list_global_rates(db, provider_code=provider.code)[:5]
	return {**result, "sample_rates": sample}


def providers_due_for_fetch(db: Session, *, now: Optional[datetime] = None) -> List[FxRateProvider]:
	now = now or datetime.now(timezone.utc)
	rows = db.execute(
		select(FxRateProvider).where(FxRateProvider.is_active == True)  # noqa: E712
	).scalars().all()
	due: List[FxRateProvider] = []
	for p in rows:
		if p.code not in ("brsapi", "mesghal"):  # فقط پیاده‌سازی‌شده‌ها
			continue
		if not resolve_provider_api_key(p):
			continue
		interval = int(p.fetch_interval_seconds or 900)
		if p.last_fetch_at is None:
			due.append(p)
			continue
		last = p.last_fetch_at
		if last.tzinfo is None:
			last = last.replace(tzinfo=timezone.utc)
		elapsed = (now - last).total_seconds()
		if elapsed >= interval:
			due.append(p)
	return due


def rate_to_business_base(
	*,
	price_irr: Decimal,
	base_currency_code: str,
) -> Decimal:
	"""تبدیل قیمت نرمال‌شده ریالی به واحد ارز پایه کسب‌وکار."""
	code = (base_currency_code or "IRR").upper()
	if code in ("IRR", "RIAL"):
		return price_irr
	if code in ("IRT", "TMN", "TOMAN"):
		return price_irr / Decimal(10)
	# ارز پایه غیرریالی: فعلاً فقط IRR/IRT پشتیبانی شفاف دارند
	raise ApiError(
		"FX_BASE_UNSUPPORTED",
		f"تبدیل اسنپ‌شات برای ارز پایه «{code}» پشتیبانی نمی‌شود؛ ارز پایه باید ریال یا تومان باشد.",
		http_status=400,
	)


def list_business_relevant_global_rates(db: Session, business_id: int) -> Dict[str, Any]:
	assert_multi_currency(db, business_id)
	b = db.get(Business, int(business_id))
	assert b is not None
	default_id = int(b.default_currency_id) if b.default_currency_id else None
	secondary = db.execute(
		select(Currency)
		.join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
		.where(
			BusinessCurrency.business_id == int(business_id),
			Currency.id != default_id if default_id is not None else True,
		)
	).scalars().all()
	codes = {str(c.code).upper() for c in secondary}
	# اولویت: ارائه‌دهنده فعال، سپس تازه‌ترین fetched_at؛ یک ردیف per currency_code
	q = (
		select(FxGlobalRate, FxRateProvider)
		.join(FxRateProvider, FxGlobalRate.provider_id == FxRateProvider.id)
		.where(FxGlobalRate.currency_code.in_(list(codes)))
		.order_by(
			FxRateProvider.is_active.desc(),
			FxGlobalRate.fetched_at.desc(),
			FxGlobalRate.id.desc(),
		)
	)
	rows = db.execute(q).all()
	base = b.default_currency
	base_code = base.code if base else "IRR"
	seen: set[str] = set()
	enriched = []
	stalest_age_hours: float | None = None
	now = datetime.now(timezone.utc)
	for g_row, provider in rows:
		code = str(g_row.currency_code).upper()
		if code in seen:
			continue
		seen.add(code)
		try:
			rate_base = rate_to_business_base(
				price_irr=Decimal(str(g_row.price_irr)),
				base_currency_code=base_code,
			)
		except ApiError:
			rate_base = None
		cur = next((c for c in secondary if str(c.code).upper() == code), None)
		fetched = g_row.fetched_at
		if fetched is not None:
			if fetched.tzinfo is None:
				fetched = fetched.replace(tzinfo=timezone.utc)
			age_h = (now - fetched).total_seconds() / 3600.0
			if stalest_age_hours is None or age_h > stalest_age_hours:
				stalest_age_hours = age_h
		item = serialize_global_rate(g_row, provider_code=provider.code)
		item.update(
			{
				"rate_to_base": str(rate_base) if rate_base is not None else None,
				"base_currency_code": base_code,
				"business_currency_id": cur.id if cur else None,
				"provider_active": bool(provider.is_active),
			}
		)
		enriched.append(item)

	stale = bool(stalest_age_hours is not None and stalest_age_hours > 24)
	return {
		"is_multi_currency": True,
		"base_currency_code": base_code,
		"items": enriched,
		"stale": stale,
		"max_age_hours": round(stalest_age_hours, 2) if stalest_age_hours is not None else None,
		"secondary_currencies": [
			{"id": c.id, "code": c.code, "title": c.title, "symbol": c.symbol} for c in secondary
		],
	}


def apply_global_rates_to_business(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	"""ثبت سریع نرخ تسعیر کسب‌وکار از اسنپ‌شات مرکزی."""
	assert_multi_currency(db, business_id)
	b = db.get(Business, int(business_id))
	if not b or not b.default_currency_id:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی کسب‌وکار تعریف نشده است", http_status=400)
	base = db.get(Currency, int(b.default_currency_id))
	if not base:
		raise ApiError("BUSINESS_CURRENCY", "ارز اصلی یافت نشد", http_status=400)
	base_code = base.code

	items = payload.get("items") or []
	if not isinstance(items, list) or not items:
		raise ApiError("FX_APPLY_ITEMS_REQUIRED", "لیست items الزامی است", http_status=400)

	note_prefix = (str(payload.get("note")).strip() if payload.get("note") else "") or "از نرخ روز (اسنپ‌شات مرکزی)"
	now = datetime.now(timezone.utc)
	created: List[Dict[str, Any]] = []
	seen_currency_ids: set[int] = set()

	for raw in items:
		if not isinstance(raw, dict):
			continue
		currency_id = raw.get("currency_id")
		currency_code = (str(raw.get("currency_code") or "").strip().upper() or None)
		symbol = (str(raw.get("symbol") or "").strip().upper() or None)

		cur: Currency | None = None
		if currency_id is not None:
			try:
				cur = db.get(Currency, int(currency_id))
			except (TypeError, ValueError) as exc:
				raise ApiError("CURRENCY_ID_INVALID", "شناسه ارز نامعتبر است", http_status=400) from exc
		elif currency_code:
			cur = db.execute(select(Currency).where(Currency.code == currency_code)).scalar_one_or_none()
		if not cur:
			raise ApiError("CURRENCY_NOT_FOUND", "ارز کسب‌وکار یافت نشد", http_status=404)
		if int(cur.id) in seen_currency_ids:
			continue
		if int(cur.id) == int(b.default_currency_id):
			raise ApiError("CURRENCY_IS_BASE", "برای ارز اصلی نرخ ثبت نمی‌شود", http_status=400)
		bc = db.execute(
			select(BusinessCurrency.id).where(
				BusinessCurrency.business_id == int(business_id),
				BusinessCurrency.currency_id == int(cur.id),
			).limit(1)
		).scalar_one_or_none()
		if bc is None:
			raise ApiError("CURRENCY_NOT_ALLOWED", "این ارز برای کسب‌وکار فعال نیست", http_status=400)

		gq = (
			select(FxGlobalRate)
			.join(FxRateProvider, FxGlobalRate.provider_id == FxRateProvider.id)
			.where(FxGlobalRate.currency_code == cur.code.upper())
		)
		if symbol:
			gq = gq.where(FxGlobalRate.symbol == symbol)
		gq = gq.order_by(FxRateProvider.is_active.desc(), FxGlobalRate.fetched_at.desc(), FxGlobalRate.id.desc())
		g_row = db.execute(gq).scalars().first()
		if not g_row:
			raise ApiError(
				"FX_GLOBAL_RATE_NOT_FOUND",
				f"نرخ اسنپ‌شات برای {cur.code} یافت نشد. ابتدا ادمین واکشی را انجام دهد.",
				http_status=404,
			)

		rate = rate_to_business_base(price_irr=Decimal(str(g_row.price_irr)), base_currency_code=base_code)
		if rate <= 0:
			raise ApiError("RATE_INVALID", "نرخ نامعتبر است", http_status=400)

		note = f"{note_prefix} | {g_row.symbol} @ {g_row.fetched_at.isoformat() if g_row.fetched_at else ''}"
		row = BusinessCurrencyRate(
			business_id=int(business_id),
			currency_id=int(cur.id),
			effective_at=now,
			rate=rate,
			note=note[:2000],
			created_by_user_id=int(user_id),
			created_at=now,
			updated_at=now,
		)
		db.add(row)
		db.flush()
		seen_currency_ids.add(int(cur.id))
		created.append(
			{
				"id": row.id,
				"currency_id": row.currency_id,
				"currency_code": cur.code,
				"rate": str(row.rate),
				"effective_at": row.effective_at,
				"note": row.note,
				"source_symbol": g_row.symbol,
				"source_fetched_at": g_row.fetched_at,
			}
		)

	return {"created": created, "count": len(created)}
