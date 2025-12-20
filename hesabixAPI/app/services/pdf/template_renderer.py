from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Tuple
import datetime
import base64
import logging

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


def _filter_smart_number(value: Any, max_decimals: int = 2) -> str:
	"""نمایش عدد با جداکننده هزارگان و حذف .0 های اضافی. None => رشته خالی"""
	if value is None:
		return ""
	try:
		n = float(value)
		# If it's effectively an integer, show without decimals
		if abs(n - round(n)) < 1e-9:
			return f"{int(round(n)):,}"
		# Otherwise show up to max_decimals, trimming trailing zeros
		s = f"{n:,.{max_decimals}f}"
		if "." in s:
			s = s.rstrip("0").rstrip(".")
		return s
	except Exception:
		# Non-numeric => string, but never "None"
		return "" if value is None else str(value)


def load_farsi_font_data_uris() -> Tuple[str | None, str | None]:
	"""Load preferred Persian fonts as data:font/ttf;base64 URIs.

	Order:
	- YekanBakhFaNum-Regular/Bold
	- Vazirmatn-Regular/Bold (fallback)
	"""
	logger = logging.getLogger(__name__)
	try:
		project_root = Path(__file__).resolve().parents[4]
		fonts_dir = project_root / "hesabixUI" / "hesabix_ui" / "assets" / "fonts"
		regular_candidates = [
			fonts_dir / "YekanBakhFaNum-Regular.ttf",
			fonts_dir / "Vazirmatn-Regular.ttf",
		]
		bold_candidates = [
			fonts_dir / "YekanBakhFaNum-Bold.ttf",
			fonts_dir / "Vazirmatn-Bold.ttf",
		]
		reg = next((p for p in regular_candidates if p.is_file()), None)
		bold = next((p for p in bold_candidates if p.is_file()), None)
		logger.debug(
			"load_farsi_font_data_uris: fonts_dir=%s regular=%s bold=%s",
			fonts_dir,
			str(reg) if reg else None,
			str(bold) if bold else None,
		)
		reg_uri = None
		bold_uri = None
		if reg:
			reg_uri = f"data:font/ttf;base64,{base64.b64encode(reg.read_bytes()).decode('ascii')}"
		if bold:
			bold_uri = f"data:font/ttf;base64,{base64.b64encode(bold.read_bytes()).decode('ascii')}"
		logger.debug(
			"load_farsi_font_data_uris: uri_lengths regular=%s bold=%s",
			len(reg_uri or ""),
			len(bold_uri or ""),
		)
		return reg_uri, bold_uri
	except Exception:
		logger.exception("load_farsi_font_data_uris: failed")
		return None, None


def _create_env() -> Environment:
	env = Environment(
		loader=FileSystemLoader(str(_get_templates_dir())),
		autoescape=select_autoescape(["html", "xml"]),
		enable_async=False,
	)
	# Common filters
	env.filters["format_amount"] = _filter_format_amount
	env.filters["money"] = _filter_money  # فیلتر money برای استفاده در قالب‌ها
	env.filters["smart_number"] = _filter_smart_number
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
