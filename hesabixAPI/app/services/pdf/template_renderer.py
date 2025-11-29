from __future__ import annotations

from pathlib import Path
from typing import Any, Dict
import datetime

from jinja2 import Environment, FileSystemLoader, select_autoescape

_env: Environment | None = None


def _get_templates_dir() -> Path:
	# .../hesabixAPI/app/services/pdf/template_renderer.py
	# -> .../hesabixAPI/templates
	return Path(__file__).resolve().parents[3] / "templates"


def _filter_format_amount(value: Any, decimals: int = 0) -> str:
	try:
		num = float(value if value is not None else 0)
		fmt = f"{{:,.{decimals}f}}"
		return fmt.format(num)
	except Exception:
		return str(value if value is not None else "")


def _filter_ltr(text: Any) -> str:
	s = "" if text is None else str(text)
	# Wrap numeric text to ensure LTR rendering in RTL documents
	return f'<span style="direction:ltr; unicode-bidi:plaintext; font-variant-numeric: tabular-nums">{s}</span>'


def _filter_format_date(value: Any, fmt: str = "%Y/%m/%d %H:%M") -> str:
	try:
		if isinstance(value, (datetime.date, datetime.datetime)):
			dt = value
		else:
			# Try parse ISO-like strings
			dt = datetime.datetime.fromisoformat(str(value))
		return dt.strftime(fmt)
	except Exception:
		return str(value if value is not None else "")


def _filter_money(value: Any, decimals: int = 0, sep: str = ",") -> str:
	"""فیلتر فرمت مبلغ - مشابه ReportTemplateService"""
	try:
		n = float(value if value is not None else 0)
		if decimals <= 0:
			s = f"{int(round(n)):,}"
		else:
			s = f"{n:,.{decimals}f}"
		return s.replace(",", sep)
	except Exception:
		return str(value if value is not None else "")


def _create_env() -> Environment:
	env = Environment(
		loader=FileSystemLoader(str(_get_templates_dir())),
		autoescape=select_autoescape(["html", "xml"]),
		enable_async=False,
	)
	# Common filters
	env.filters["format_amount"] = _filter_format_amount
	env.filters["money"] = _filter_money  # فیلتر money برای استفاده در قالب‌ها
	env.filters["ltr"] = _filter_ltr
	env.filters["format_date"] = _filter_format_date
	return env


def get_env() -> Environment:
	global _env
	if _env is None:
		_env = _create_env()
	return _env


def render_template(template_path: str, context: Dict[str, Any]) -> str:
	"""
	Render a repository template under templates/ directory with common filters.
	Example: render_template("pdf/invoices/detail.html", ctx)
	"""
	template = get_env().get_template(template_path)
	return template.render(**context)


