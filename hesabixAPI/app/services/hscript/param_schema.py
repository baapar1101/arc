"""استنتاج و پارس schema پارامترهای گزارش HScript برای فرم UI."""

from __future__ import annotations

import re
from typing import Any, Optional


_PARAM_ANNOTATION_RE = re.compile(
	r"""^\s*\#\s*@param\s+
	(?P<name>[A-Za-z_][A-Za-z0-9_]*)
	(?:\s+(?P<type>date|datetime|number|integer|boolean|string|text|select))?
	(?:\s+(?P<label>"[^"]*"|'[^']*'))?
	(?P<rest>.*)$
	""",
	re.VERBOSE,
)

_DEFAULT_RE = re.compile(r"""\bdefault\s*=\s*(?P<val>"[^"]*"|'[^']*'|true|false|null|-?\d+(?:\.\d+)?)""", re.I)
_OPTIONS_RE = re.compile(r"""\boptions\s*=\s*\[(?P<body>[^\]]*)\]""", re.I)
_REQUIRED_RE = re.compile(r"\brequired\b", re.I)
_PARAMS_GET_RE = re.compile(
	r"""params\.get\(\s*['\"](?P<name>[A-Za-z_][A-Za-z0-9_]*)['\"]\s*(?:,\s*(?P<default>[^)]+))?\)"""
)
_PARAM_INDEX_RE = re.compile(r"""param\[\s*['\"](?P<name>[A-Za-z_][A-Za-z0-9_]*)['\"]\s*\]""")


def _strip_quotes(value: str) -> str:
	s = value.strip()
	if len(s) >= 2 and s[0] == s[-1] and s[0] in {"'", '"'}:
		return s[1:-1]
	return s


def _parse_literal(raw: str) -> Any:
	s = raw.strip()
	low = s.lower()
	if low == "true":
		return True
	if low == "false":
		return False
	if low == "null" or low == "none":
		return None
	if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
		return _strip_quotes(s)
	try:
		if "." in s:
			return float(s)
		return int(s)
	except ValueError:
		return s


def _guess_type(name: str, value: Any) -> str:
	n = name.lower()
	if isinstance(value, bool):
		return "boolean"
	if isinstance(value, int) and not isinstance(value, bool):
		if n.endswith("_id") or n in {"limit", "take", "top", "page", "skip"}:
			return "integer"
		return "number"
	if isinstance(value, float):
		return "number"
	if isinstance(value, str):
		if n.endswith("_date") or n in {"from_date", "to_date", "date_from", "date_to", "start", "end"}:
			return "date"
		if len(value) > 80:
			return "text"
		return "string"
	if value is None:
		if n.endswith("_date") or "date" in n:
			return "date"
		if n.endswith("_id") or n in {"limit", "take", "top"}:
			return "integer"
		if n.startswith("is_") or n.startswith("include_") or n.startswith("with_"):
			return "boolean"
		return "string"
	return "string"


def _friendly_label(name: str) -> str:
	known = {
		"from_date": "از تاریخ",
		"to_date": "تا تاریخ",
		"date_from": "از تاریخ",
		"date_to": "تا تاریخ",
		"start": "شروع",
		"end": "پایان",
		"limit": "سقف ردیف",
		"take": "تعداد",
		"top": "تعداد برتر",
		"person_id": "شناسه شخص",
		"search": "جستجو",
		"warehouse_id": "شناسه انبار",
		"document_type": "نوع سند",
		"kind": "نوع دریافت/پرداخت",
		"include_proforma": "شامل پیش‌فاکتور",
		"min_balance": "حداقل مانده",
	}
	if name in known:
		return known[name]
	return name.replace("_", " ")


def _field_from_annotation(line: str) -> Optional[dict[str, Any]]:
	m = _PARAM_ANNOTATION_RE.match(line)
	if not m:
		return None
	name = m.group("name")
	ftype = (m.group("type") or "string").lower()
	label_raw = m.group("label")
	rest = m.group("rest") or ""
	label = _strip_quotes(label_raw) if label_raw else _friendly_label(name)
	field: dict[str, Any] = {
		"name": name,
		"type": ftype if ftype != "datetime" else "date",
		"label": label,
		"required": bool(_REQUIRED_RE.search(rest)),
	}
	dm = _DEFAULT_RE.search(rest)
	if dm:
		field["default"] = _parse_literal(dm.group("val"))
	om = _OPTIONS_RE.search(rest)
	if om:
		opts = []
		for part in om.group("body").split(","):
			part = part.strip()
			if not part:
				continue
			opts.append(_parse_literal(part))
		if opts:
			field["options"] = opts
			field["type"] = "select"
	return field


def infer_param_schema(
	*,
	source_code: str | None = None,
	default_params: dict[str, Any] | None = None,
	runtime_params: dict[str, Any] | None = None,
) -> dict[str, Any]:
	"""
	ساخت schema فرم پارامتر.
	اولویت: annotationهای @param در سورس → کلیدهای default_params / استفاده در کد.
	"""
	fields_by_name: dict[str, dict[str, Any]] = {}
	order: list[str] = []

	def upsert(field: dict[str, Any], *, prefer: bool = False) -> None:
		name = str(field["name"])
		if name.startswith("_"):
			return
		if name not in fields_by_name:
			fields_by_name[name] = field
			order.append(name)
			return
		if prefer:
			merged = dict(fields_by_name[name])
			merged.update({k: v for k, v in field.items() if v is not None})
			fields_by_name[name] = merged

	code = source_code or ""
	for line in code.splitlines():
		ann = _field_from_annotation(line)
		if ann:
			upsert(ann, prefer=True)

	for m in _PARAMS_GET_RE.finditer(code):
		name = m.group("name")
		default_raw = m.group("default")
		default_val = _parse_literal(default_raw) if default_raw else None
		upsert(
			{
				"name": name,
				"type": _guess_type(name, default_val),
				"label": _friendly_label(name),
				"required": False,
				**({"default": default_val} if default_raw is not None else {}),
			}
		)

	for m in _PARAM_INDEX_RE.finditer(code):
		name = m.group("name")
		upsert(
			{
				"name": name,
				"type": _guess_type(name, None),
				"label": _friendly_label(name),
				"required": False,
			}
		)

	merged_defaults = dict(default_params or {})
	merged_defaults.update(runtime_params or {})
	for key, value in merged_defaults.items():
		name = str(key)
		if name.startswith("_"):
			continue
		upsert(
			{
				"name": name,
				"type": _guess_type(name, value),
				"label": _friendly_label(name),
				"required": False,
				"default": value,
			},
			prefer=True,
		)
		if name in fields_by_name and "default" not in fields_by_name[name] and value is not None:
			fields_by_name[name]["default"] = value
		elif name in fields_by_name and value is not None:
			# مقدار فعلی را به‌عنوان value پیشنهاد بده
			fields_by_name[name]["value"] = value

	fields = []
	for name in order:
		f = dict(fields_by_name[name])
		if "value" not in f and "default" in f:
			f["value"] = f["default"]
		fields.append(f)

	return {
		"version": 1,
		"fields": fields,
		"has_annotations": any(line.strip().startswith("# @param") for line in code.splitlines()),
	}
