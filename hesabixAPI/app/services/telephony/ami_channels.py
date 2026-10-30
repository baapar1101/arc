"""کمک‌تابع‌های کانال Asterisk برای Hangup سافت‌فون."""
from __future__ import annotations

from typing import Any, Iterable, List, Optional


def local_channel_mate(channel: str) -> Optional[str]:
	"""جفت Local channel را برمی‌گرداند (;1 ↔ ;2)."""
	ch = (channel or "").strip()
	if not ch:
		return None
	if ch.endswith(";1"):
		return ch[:-2] + ";2"
	if ch.endswith(";2"):
		return ch[:-2] + ";1"
	return None


def expand_hangup_channels(*groups: Iterable[Optional[str]]) -> List[str]:
	"""کانال‌ها را یکتا می‌کند و جفت Local را هم اضافه می‌کند."""
	out: List[str] = []
	seen = set()
	for group in groups:
		if group is None:
			continue
		for raw in group:
			ch = str(raw or "").strip()
			if not ch or ch in seen:
				continue
			seen.add(ch)
			out.append(ch)
			mate = local_channel_mate(ch)
			if mate and mate not in seen:
				seen.add(mate)
				out.append(mate)
	return out


def match_softphone_relay_call(candidates: Iterable[Any], payload: dict) -> Optional[Any]:
	"""وصل رویداد AMI به تماس Softphone موجود وقتی uniqueid حسابیکس با Asterisk فرق دارد."""
	from app.services.telephony.phone_normalizer import extract_digits

	to_raw = str(payload.get("to") or payload.get("to_number") or payload.get("destination") or "")
	from_raw = str(payload.get("from") or payload.get("from_number") or "")
	channel = str(payload.get("channel") or "")
	dest_channel = str(payload.get("dest_channel") or "")
	for call in candidates:
		extra = dict(getattr(call, "extra_info", None) or {})
		if not extra.get("softphone"):
			continue
		if extra.get("asterisk_uniqueid_bound"):
			continue
		dest = getattr(call, "to_number_normalized", None) or getattr(call, "to_number_raw", None)
		if numbers_look_same(dest, to_raw) or numbers_look_same(dest, from_raw):
			return call
		digits = extract_digits(dest or "")
		if digits and len(digits) >= 7 and (digits in channel or digits in dest_channel):
			return call
	return None


def numbers_look_same(a: Optional[str], b: Optional[str]) -> bool:
	"""تطبیق شماره تماس Softphone با رویداد AMI."""
	from app.services.telephony.phone_normalizer import extract_digits, numbers_match

	if numbers_match(a, b, min_len=7):
		return True
	da = extract_digits(a or "")
	db = extract_digits(b or "")
	if not da or not db:
		return False
	n = min(len(da), len(db), 10)
	if n < 7:
		return da == db
	return da[-n:] == db[-n:]
