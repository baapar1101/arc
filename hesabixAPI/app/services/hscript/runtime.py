"""Runtime سطح بالا: parse → interpret → Report Spec."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any, Optional

from sqlalchemy.orm.session import Session

from app.services.hscript.builtins import build_builtins
from app.services.hscript.errors import HScriptError, SecurityErrorHS
from app.services.hscript.gateway import build_gateway_modules, build_params_module
from app.services.hscript.gateway.context import GatewayContext
from app.services.hscript.interpreter import Interpreter
from app.services.hscript.lexer import Lexer
from app.services.hscript.limits import ResourceLimits
from app.services.hscript.parser import Parser
from app.services.hscript.report_builder import ReportBuilder
from app.services.hscript.values import HModule, sanitize_jsonish


HSCRIPT_LANGUAGE_VERSION = "1.0.0"


@dataclass
class RunResult:
	ok: bool
	spec: Optional[dict[str, Any]] = None
	error: Optional[dict[str, Any]] = None
	stats: Optional[dict[str, Any]] = None
	source_hash: Optional[str] = None


def source_hash(source: str) -> str:
	return hashlib.sha256(source.encode("utf-8")).hexdigest()


def parse_script(source: str, *, limits: ResourceLimits | None = None) -> Any:
	lim = limits or ResourceLimits.default()
	tokens = Lexer(source, max_source_bytes=lim.max_source_bytes).tokenize()
	return Parser(tokens).parse()


def validate_script(source: str, *, limits: ResourceLimits | None = None) -> dict[str, Any]:
	"""اعتبارسنجی نحوی بدون اجرا."""
	try:
		parse_script(source, limits=limits)
		return {"ok": True, "source_hash": source_hash(source), "language_version": HSCRIPT_LANGUAGE_VERSION}
	except HScriptError as exc:
		return {"ok": False, "error": exc.to_dict(), "source_hash": source_hash(source)}


def run_script(
	source: str,
	*,
	db: Session,
	business_id: int,
	user_id: int,
	fiscal_year_id: Optional[int] = None,
	params: Optional[dict[str, Any]] = None,
	limits: ResourceLimits | None = None,
	preview: bool = False,
) -> RunResult:
	"""اجرای امن اسکریپت برای یک کسب‌وکار قفل‌شده."""
	lim = limits or (ResourceLimits.preview() if preview else ResourceLimits.default())
	sh = source_hash(source)

	# دفاع: جلوگیری از تزریق business_id از params
	safe_params = dict(params or {})
	for banned in ("business_id", "user_id", "db", "session", "settings", "token", "api_key"):
		safe_params.pop(banned, None)

	try:
		module_ast = parse_script(source, limits=lim)
		ctx = GatewayContext(
			db=db,
			business_id=int(business_id),
			user_id=int(user_id),
			fiscal_year_id=fiscal_year_id,
			limits=lim,
			params=safe_params,
		)
		report = ReportBuilder(max_blocks=lim.max_report_blocks, max_output_bytes=lim.max_output_bytes)
		env: dict[str, Any] = {}
		env.update(build_builtins(lim))
		env.update(build_gateway_modules(ctx))
		params_mod = build_params_module(safe_params)
		env["params"] = params_mod
		# دسترسی راحت params["start"] — dict موازی فقط‌خواندنی
		env["param"] = sanitize_jsonish(safe_params)

		# report به‌صورت ماژول متددار
		report_methods = {
			"title": report.title,
			"heading": report.heading,
			"paragraph": report.paragraph,
			"text": report.text,
			"kpi": report.kpi,
			"card": report.card,
			"table": report.table,
			"bar_chart": report.bar_chart,
			"line_chart": report.line_chart,
			"pie_chart": report.pie_chart,
			"area_chart": report.area_chart,
			"scatter_chart": report.scatter_chart,
			"gauge": report.gauge,
			"section": report.section,
			"page_break": report.page_break,
			"row_break": report.row_break,
			"qr": report.qr,
			"barcode": report.barcode,
			"dashboard": report.dashboard,
			"set_meta": report.set_meta,
		}
		env["report"] = HModule(name="report", methods=report_methods)

		# مسدود کردن نام‌های خطرناک حتی اگر کسی بخواهد override کند — بعد از build دوباره قفل
		for banned_name in ("__builtins__", "__import__", "open", "eval", "exec", "compile", "globals", "locals", "vars", "dir"):
			env.pop(banned_name, None)

		interp = Interpreter(globals_env=env, limits=lim)
		interp.run(module_ast)
		spec = report.to_spec()
		return RunResult(
			ok=True,
			spec=spec,
			stats={
				"steps": interp.steps,
				"gateway_calls": ctx.gateway_calls,
				"blocks": len(report.blocks),
				"language_version": HSCRIPT_LANGUAGE_VERSION,
			},
			source_hash=sh,
		)
	except HScriptError as exc:
		return RunResult(ok=False, error=exc.to_dict(), source_hash=sh)
	except Exception as exc:  # noqa: BLE001 — مرز sandbox
		# هرگز traceback داخلی را به کلاینت نده
		return RunResult(
			ok=False,
			error=SecurityErrorHS(f"اجرا متوقف شد: {type(exc).__name__}").to_dict(),
			source_hash=sh,
		)
