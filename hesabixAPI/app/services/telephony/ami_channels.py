"""کمک‌تابع‌های کانال Asterisk برای Hangup سافت‌فون."""
from __future__ import annotations

from typing import Any, FrozenSet, Iterable, List, Optional

_TERMINAL_AMI_EVENT_TYPES: FrozenSet[str] = frozenset(
	{
		"call.ended",
		"ended",
		"hangup",
		"call.missed",
		"missed",
		"call.busy",
		"busy",
		"call.failed",
		"failed",
		"cancelled",
	}
)
_ANSWER_AMI_EVENT_TYPES: FrozenSet[str] = frozenset({"call.answered", "answered"})
_RINGING_AMI_EVENT_TYPES: FrozenSet[str] = frozenset({"call.ringing", "ringing"})


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


def collect_call_ami_ids(call: Any) -> set[str]:
	"""uniqueid/linkedid ذخیره‌شدهٔ تماس به‌همراه uniqueidهای AMI جانبی."""
	ids: set[str] = set()
	for raw in (getattr(call, "asterisk_uniqueid", None), getattr(call, "asterisk_linkedid", None)):
		s = str(raw or "").strip()
		if s:
			ids.add(s)
	extra = dict(getattr(call, "extra_info", None) or {})
	for raw in extra.get("ami_uniqueids") or []:
		s = str(raw or "").strip()
		if s:
			ids.add(s)
	return ids


def match_call_by_ami_ids(
	candidates: Iterable[Any],
	uniqueid: Optional[str],
	linkedid: Optional[str] = None,
) -> Optional[Any]:
	"""پیدا کردن تماس از روی uniqueidهای AMI که در extra_info جمع شده‌اند."""
	uid = str(uniqueid or "").strip()
	lid = str(linkedid or "").strip()
	if not uid and not lid:
		return None
	for call in candidates:
		ids = collect_call_ami_ids(call)
		if uid and uid in ids:
			return call
		if lid and lid in ids:
			return call
	return None


def append_ami_uniqueid(extra: Optional[dict], uniqueid: Optional[str]) -> dict:
	"""uniqueid فرعی AMI را بدون تکرار در extra_info نگه می‌دارد."""
	out = dict(extra or {})
	uid = str(uniqueid or "").strip()
	if not uid:
		return out
	ids = [str(x).strip() for x in (out.get("ami_uniqueids") or []) if str(x).strip()]
	if uid not in ids:
		ids.append(uid)
	out["ami_uniqueids"] = ids
	return out


def should_create_call_from_ami_event(event_type: str) -> bool:
	"""فقط زنگ اولیه مجاز است رکورد تماس جدید بسازد."""
	return str(event_type or "").strip().lower() in _RINGING_AMI_EVENT_TYPES


def should_skip_unmatched_ami_event(event_type: str) -> bool:
	"""Answer/Hangup بدون تماس قبلی نباید رکورد جعلی بسازد."""
	t = str(event_type or "").strip().lower()
	return t in _TERMINAL_AMI_EVENT_TYPES or t in _ANSWER_AMI_EVENT_TYPES


def is_local_secondary_leg(channel: Optional[str]) -> bool:
	"""پای Local/;2 در Originate معمولاً زود قطع می‌شود و پایان کل تماس نیست."""
	ch = str(channel or "").strip()
	return "Local/" in ch and ch.endswith(";2")


def is_softphone_outbound_call(call: Any) -> bool:
	extra = dict(getattr(call, "extra_info", None) or {})
	return bool(extra.get("softphone")) and str(getattr(call, "direction", "") or "").lower() == "outbound"


def should_ignore_softphone_outbound_hangup(call: Any, payload: dict, event_type: str) -> bool:
	"""Hangup پایهٔ Local/;2 را به‌عنوان قطع تماس خروجی Softphone حساب نکن."""
	if not is_softphone_outbound_call(call):
		return False
	t = str(event_type or "").strip().lower()
	if t not in _TERMINAL_AMI_EVENT_TYPES:
		return False
	if str(getattr(call, "status", "") or "") not in ("ringing", "answered"):
		return False
	if getattr(call, "ended_at", None) is not None:
		return False
	return is_local_secondary_leg((payload or {}).get("channel"))


def match_softphone_relay_call(candidates: Iterable[Any], payload: dict) -> Optional[Any]:
	"""وصل رویداد AMI به تماس Softphone موجود وقتی uniqueid حسابیکس با Asterisk فرق دارد."""
	from app.services.telephony.phone_normalizer import extract_digits

	to_raw = str(payload.get("to") or payload.get("to_number") or payload.get("destination") or "")
	from_raw = str(payload.get("from") or payload.get("from_number") or "")
	channel = str(payload.get("channel") or "")
	dest_channel = str(payload.get("dest_channel") or "")
	session_id = str(payload.get("session_id") or "")
	for call in candidates:
		extra = dict(getattr(call, "extra_info", None) or {})
		if not extra.get("softphone"):
			continue
		if session_id and str(extra.get("session_id") or "") == session_id:
			return call
		dest = getattr(call, "to_number_normalized", None) or getattr(call, "to_number_raw", None)
		src = getattr(call, "from_number_normalized", None) or getattr(call, "from_number_raw", None)
		ext = getattr(call, "extension", None)
		if numbers_look_same(dest, to_raw) or numbers_look_same(dest, from_raw):
			return call
		if numbers_look_same(src, to_raw) or numbers_look_same(src, from_raw):
			return call
		if numbers_look_same(ext, to_raw) or numbers_look_same(ext, from_raw):
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
