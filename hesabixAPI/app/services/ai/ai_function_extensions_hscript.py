"""ابزارهای AI برای HScript (تولید/توضیح/اعتبارسنجی/پیش‌نمایش)."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Optional

from app.services.hscript.docs_catalog import list_doc_manifest, read_doc_by_id, retrieve_docs_for_rag, search_docs
from app.services.hscript import validate_script

if TYPE_CHECKING:
	from app.services.ai.function_registry import AIFunctionRegistry
	from sqlalchemy.orm import Session


def register_hscript_ai_functions(registry: "AIFunctionRegistry") -> None:
	# import تأخیری برای جلوگیری از circular import با function_registry singleton
	from app.services.ai.function_registry import AIFunction, AIRole

	create_handler = registry._create_handler

	# امضاها مطابق _create_handler: service_func(db=db, **args)

	def hscript_search_docs_handler(db: "Session", query: str = "", limit: int = 5, **kwargs: Any) -> dict[str, Any]:
		return {
			"items": search_docs(str(query or ""), limit=max(1, min(int(limit or 5), 10))),
			"manifest_version": list_doc_manifest()["language_version"],
		}

	def hscript_retrieve_docs_handler(db: "Session", query: str = "", limit: int = 5, **kwargs: Any) -> dict[str, Any]:
		return {"docs": retrieve_docs_for_rag(str(query or ""), limit=max(1, min(int(limit or 5), 8)))}

	def hscript_read_doc_handler(db: "Session", doc_id: str = "", **kwargs: Any) -> dict[str, Any]:
		doc = read_doc_by_id(str(doc_id or ""))
		if not doc:
			return {"ok": False, "error": "DOC_NOT_FOUND", "doc_id": doc_id}
		content = doc.get("content") or ""
		if len(content) > 6000:
			content = content[:6000] + "\n\n...[truncated]..."
		return {"ok": True, "doc": {**doc, "content": content}}

	def hscript_validate_handler(db: "Session", source_code: str = "", **kwargs: Any) -> dict[str, Any]:
		return validate_script(str(source_code or ""))

	def hscript_language_guide_handler(db: "Session", **kwargs: Any) -> dict[str, Any]:
		return {
			"language": "HScript",
			"version": "1.0.0",
			"style": "python-like subset",
			"modules": ["invoices", "customers", "products", "payments", "report", "params"],
			"forbidden": ["import", "class", "eval", "open", "sql", "http", "os", "env"],
			"example": (
				"report.title(\"فروش ماه\")\n"
				"rows = invoices.this_month()\n"
				"report.kpi(\"تعداد فاکتور\", rows.count())\n"
				"report.table(rows.limit(20))\n"
			),
			"hint": "برای جزئیات از hscript_retrieve_docs و hscript_read_doc استفاده کن. اسکریپت نهایی را در ```hscript بگذار.",
		}

	def hscript_run_preview_handler(
		db: "Session",
		business_id: int,
		user_id: int,
		source_code: str = "",
		params: Optional[dict[str, Any]] = None,
		**kwargs: Any,
	) -> dict[str, Any]:
		from app.services import hscript_report_service as svc

		result = svc.run_report(
			db,
			int(business_id),
			user_id=int(user_id),
			source_code=str(source_code or ""),
			params=params if isinstance(params, dict) else {},
			fiscal_year_id=kwargs.get("fiscal_year_id"),
			preview=True,
			persist=False,
		)
		spec = result.get("spec")
		if isinstance(spec, dict):
			blocks = spec.get("blocks") or []
			if isinstance(blocks, list) and len(blocks) > 30:
				spec = {**spec, "blocks": blocks[:30], "_truncated": True}
		return {
			"ok": result.get("ok"),
			"error": result.get("error"),
			"stats": result.get("stats"),
			"spec": spec,
		}

	def hscript_fix_script_handler(
		db: "Session",
		source_code: str = "",
		goal: str = "",
		error_message: str = "",
		**kwargs: Any,
	) -> dict[str, Any]:
		validation = validate_script(str(source_code or ""))
		docs = retrieve_docs_for_rag(str(goal or error_message or "hscript fix"), limit=4)
		return {
			"validation": validation,
			"hint": (
				"اگر validation.ok=false است، خطا را با docs مرتبط اصلاح کن و اسکریپت کامل را در ```hscript برگردان."
				if not validation.get("ok")
				else "اسکریپت از نظر نحوی معتبر است؛ در صورت نیاز بهینه‌سازی یا توضیح بده."
			),
			"docs": docs,
		}

	common_roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}

	registry.register(
		AIFunction(
			name="hscript_search_docs",
			description="جستجو در مستندات زبان گزارش‌نویسی HScript حسابیکس بر اساس موضوع کاربر.",
			parameters_schema={
				"type": "object",
				"properties": {
					"query": {"type": "string", "description": "موضوع جستجو مثل invoices filter یا chart"},
					"limit": {"type": "integer", "description": "حداکثر نتایج", "default": 5},
				},
				"required": ["query"],
			},
			handler=create_handler(hscript_search_docs_handler),
			allowed_roles=common_roles,
			required_permissions=["reports.read"],
			business_context_required=True,
			category="hscript",
			is_readonly=True,
		)
	)
	registry.register(
		AIFunction(
			name="hscript_retrieve_docs",
			description="بازیابی محتوای قطعات مستند HScript برای تولید/اصلاح اسکریپت (RAG).",
			parameters_schema={
				"type": "object",
				"properties": {
					"query": {"type": "string"},
					"limit": {"type": "integer", "default": 5},
				},
				"required": ["query"],
			},
			handler=create_handler(hscript_retrieve_docs_handler),
			allowed_roles=common_roles,
			required_permissions=["reports.read"],
			business_context_required=True,
			category="hscript",
			is_readonly=True,
		)
	)
	registry.register(
		AIFunction(
			name="hscript_read_doc",
			description="خواندن یک قطعه مستند HScript با doc_id پایدار برای تولید یا اصلاح اسکریپت.",
			parameters_schema={
				"type": "object",
				"properties": {
					"doc_id": {"type": "string", "description": "شناسه مثل hscript.api.invoices"},
				},
				"required": ["doc_id"],
			},
			handler=create_handler(hscript_read_doc_handler),
			allowed_roles=common_roles,
			required_permissions=["reports.read"],
			business_context_required=True,
			category="hscript",
			is_readonly=True,
		)
	)
	registry.register(
		AIFunction(
			name="hscript_validate_script",
			description="اعتبارسنجی نحوی اسکریپت HScript بدون اجرا روی داده واقعی.",
			parameters_schema={
				"type": "object",
				"properties": {
					"source_code": {"type": "string", "description": "متن کامل اسکریپت"},
				},
				"required": ["source_code"],
			},
			handler=create_handler(hscript_validate_handler),
			allowed_roles=common_roles,
			required_permissions=["reports.read"],
			business_context_required=True,
			category="hscript",
			is_readonly=True,
		)
	)
	registry.register(
		AIFunction(
			name="hscript_language_guide",
			description="راهنمای فشرده زبان HScript برای تولید اسکریپت گزارش سفارشی حسابیکس.",
			parameters_schema={"type": "object", "properties": {}, "required": []},
			handler=create_handler(hscript_language_guide_handler),
			allowed_roles=common_roles,
			required_permissions=["reports.read"],
			business_context_required=True,
			category="hscript",
			is_readonly=True,
		)
	)
	registry.register(
		AIFunction(
			name="hscript_run_preview",
			description="اجرای پیش‌نمایش فقط‌خواندنی اسکریپت HScript با سقف سخت و برگرداندن Report Spec.",
			parameters_schema={
				"type": "object",
				"properties": {
					"source_code": {"type": "string"},
					"params": {"type": "object"},
				},
				"required": ["source_code"],
			},
			handler=create_handler(hscript_run_preview_handler),
			allowed_roles=common_roles,
			required_permissions=["reports.read"],
			business_context_required=True,
			category="hscript",
			is_readonly=True,
			risk_level="medium",
		)
	)
	registry.register(
		AIFunction(
			name="hscript_fix_script",
			description="تحلیل خطا/هدف و برگرداندن validation + مستندات مرتبط برای اصلاح اسکریپت HScript.",
			parameters_schema={
				"type": "object",
				"properties": {
					"source_code": {"type": "string"},
					"goal": {"type": "string"},
					"error_message": {"type": "string"},
				},
				"required": ["source_code"],
			},
			handler=create_handler(hscript_fix_script_handler),
			allowed_roles=common_roles,
			required_permissions=["reports.read"],
			business_context_required=True,
			category="hscript",
			is_readonly=True,
		)
	)
