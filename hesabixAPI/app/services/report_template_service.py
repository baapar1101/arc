from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session
from sqlalchemy import and_
from jinja2.sandbox import SandboxedEnvironment
from jinja2 import StrictUndefined, BaseLoader

from adapters.db.models.report_template import ReportTemplate
from app.core.responses import ApiError


class ReportTemplateService:
	"""سرویس مدیریت قالب‌های گزارش"""

	@staticmethod
	def list_templates(
		db: Session,
		business_id: int,
		module_key: Optional[str] = None,
		subtype: Optional[str] = None,
		status: Optional[str] = None,
		only_published: bool = False,
	) -> List[ReportTemplate]:
		try:
			q = db.query(ReportTemplate).filter(ReportTemplate.business_id == int(business_id))
			if module_key:
				q = q.filter(ReportTemplate.module_key == str(module_key))
			if subtype:
				q = q.filter(ReportTemplate.subtype == str(subtype))
			if status:
				q = q.filter(ReportTemplate.status == str(status))
			if only_published:
				q = q.filter(ReportTemplate.status == "published")
			q = q.order_by(ReportTemplate.updated_at.desc())
			return q.all()
		except Exception:
			# اگر جدول موجود نباشد، شکست نخوریم
			return []

	@staticmethod
	def get_template(db: Session, template_id: int, business_id: Optional[int] = None) -> Optional[ReportTemplate]:
		try:
			q = db.query(ReportTemplate).filter(ReportTemplate.id == int(template_id))
			if business_id is not None:
				q = q.filter(ReportTemplate.business_id == int(business_id))
			return q.first()
		except Exception:
			return None

	@staticmethod
	def create_template(db: Session, data: Dict[str, Any], user_id: int) -> ReportTemplate:
		required = ["business_id", "module_key", "name", "content_html"]
		for k in required:
			if not data.get(k):
				raise ApiError("VALIDATION_ERROR", f"Missing field: {k}", http_status=400)
		entity = ReportTemplate(
			business_id=int(data["business_id"]),
			module_key=str(data["module_key"]),
			subtype=(data.get("subtype") or None),
			name=str(data["name"]),
			description=(data.get("description") or None),
			engine=str(data.get("engine") or "jinja2"),
			status=str(data.get("status") or "draft"),
			is_default=bool(data.get("is_default") or False),
			version=int(data.get("version") or 1),
			content_html=str(data["content_html"]),
			content_css=(data.get("content_css") or None),
			header_html=(data.get("header_html") or None),
			footer_html=(data.get("footer_html") or None),
			paper_size=(data.get("paper_size") or None),
			orientation=(data.get("orientation") or None),
			margins=(data.get("margins") or None),
			assets=(data.get("assets") or None),
			created_by=int(user_id),
		)
		db.add(entity)
		db.commit()
		db.refresh(entity)
		return entity

	@staticmethod
	def update_template(db: Session, template_id: int, data: Dict[str, Any], business_id: int) -> ReportTemplate:
		entity = ReportTemplateService.get_template(db, template_id, business_id)
		if not entity:
			raise ApiError("NOT_FOUND", "Template not found", http_status=404)
		for field in [
			"module_key", "subtype", "name", "description", "engine", "status",
			"content_html", "content_css", "header_html", "footer_html",
			"paper_size", "orientation", "margins", "assets"
		]:
			if field in data:
				setattr(entity, field, data.get(field))
		# bump version on content changes
		if any(k in data for k in ("content_html", "content_css", "header_html", "footer_html")):
			entity.version = int((entity.version or 1) + 1)
		db.commit()
		db.refresh(entity)
		return entity

	@staticmethod
	def delete_template(db: Session, template_id: int, business_id: int) -> None:
		entity = ReportTemplateService.get_template(db, template_id, business_id)
		if not entity:
			return
		db.delete(entity)
		db.commit()

	@staticmethod
	def publish_template(db: Session, template_id: int, business_id: int, is_published: bool = True) -> ReportTemplate:
		entity = ReportTemplateService.get_template(db, template_id, business_id)
		if not entity:
			raise ApiError("NOT_FOUND", "Template not found", http_status=404)
		entity.status = "published" if is_published else "draft"
		db.commit()
		db.refresh(entity)
		return entity

	@staticmethod
	def set_default(db: Session, business_id: int, module_key: str, subtype: Optional[str], template_id: int) -> ReportTemplate:
		entity = ReportTemplateService.get_template(db, template_id, business_id)
		if not entity or entity.module_key != module_key or (entity.subtype or None) != (subtype or None):
			raise ApiError("VALIDATION_ERROR", "Template does not match scope", http_status=400)
		# unset other defaults in scope
		try:
			db.query(ReportTemplate).filter(
				and_(
					ReportTemplate.business_id == int(business_id),
					ReportTemplate.module_key == str(module_key),
					ReportTemplate.subtype.is_(subtype if subtype is not None else None),
					ReportTemplate.is_default.is_(True),
				)
			).update({ReportTemplate.is_default: False})
		except Exception:
			pass
		entity.is_default = True
		db.commit()
		db.refresh(entity)
		return entity

	@staticmethod
	def resolve_default(db: Session, business_id: int, module_key: str, subtype: Optional[str]) -> Optional[ReportTemplate]:
		try:
			q = db.query(ReportTemplate).filter(
				and_(
					ReportTemplate.business_id == int(business_id),
					ReportTemplate.module_key == str(module_key),
					ReportTemplate.status == "published",
					ReportTemplate.is_default.is_(True),
				)
			)
			if subtype is not None:
				q = q.filter(ReportTemplate.subtype == str(subtype))
			else:
				q = q.filter(ReportTemplate.subtype.is_(None))
			return q.first()
		except Exception:
			return None

	@staticmethod
	def render_with_template(
		template: ReportTemplate,
		context: Dict[str, Any],
	) -> str:
		"""رندر امن Jinja2"""
		if not template or not template.content_html:
			raise ApiError("INVALID_TEMPLATE", "Template HTML is empty", http_status=400)
		env = SandboxedEnvironment(
			loader=BaseLoader(),
			autoescape=True,
			undefined=StrictUndefined,
			enable_async=False,
		)
		# فیلترهای ساده کاربردی
		env.filters["default"] = lambda v, d="": v if v not in (None, "") else d
		env.filters["upper"] = lambda v: str(v).upper()
		env.filters["lower"] = lambda v: str(v).lower()

		template_obj = env.from_string(template.content_html)
		html = template_obj.render(**context)

		# تنظیمات صفحه (@page) از روی ویژگی‌های قالب
		try:
			page_css_parts = []
			size_parts = []
			if (template.paper_size or "").strip():
				size_parts.append(str(template.paper_size).strip())
			if (template.orientation or "").strip() in ("portrait", "landscape"):
				size_parts.append(str(template.orientation).strip())
			if size_parts:
				page_css_parts.append(f"size: {' '.join(size_parts)};")
			margins = template.margins or {}
			mt = margins.get("top")
			mr = margins.get("right")
			mb = margins.get("bottom")
			ml = margins.get("left")
			def _mm(v):
				try:
					if v is None:
						return None
					# اگر رشته باشد، به mm ختم شود
					s = str(v).strip()
					return s if s.endswith("mm") else f"{s}mm"
				except Exception:
					return None
			mt, mr, mb, ml = _mm(mt), _mm(mr), _mm(mb), _mm(ml)
			if all(x is not None for x in (mt, mr, mb, ml)):
				page_css_parts.append(f"margin: {mt} {mr} {mb} {ml};")
			# اگر چیزی برای @page داریم، تزریق کنیم
			if page_css_parts:
				page_css = "@page { " + " ".join(page_css_parts) + " }"
				if "</head>" in html:
					html = html.replace("</head>", f"<style>{page_css}</style></head>")
				else:
					html = f"<head><style>{page_css}</style></head>{html}"
		except Exception:
			# اگر مشکلی بود، رندر را متوقف نکنیم
			pass

		# درج CSS سفارشی در <style>
		css = (template.content_css or "").strip()
		if css:
			# ساده: تزریق داخل head اگر وجود دارد
			if "</head>" in html:
				html = html.replace("</head>", f"<style>{css}</style></head>")
			else:
				html = f"<head><style>{css}</style></head>{html}"
		return html

	@staticmethod
	def try_render_resolved(
		db: Session,
		business_id: int,
		module_key: str,
		subtype: Optional[str],
		context: Dict[str, Any],
		explicit_template_id: Optional[int] = None,
	) -> Optional[str]:
		"""اگر قالبی مشخص/پیش‌فرض باشد، HTML رندر شده را برمی‌گرداند؛ در غیر این صورت None."""
		template: Optional[ReportTemplate] = None
		if explicit_template_id is not None:
			t = ReportTemplateService.get_template(db, int(explicit_template_id), business_id)
			# فقط قالب‌های published برای استفاده عمومی
			if t and t.status == "published":
				template = t
		if template is None:
			template = ReportTemplateService.resolve_default(db, business_id, module_key, subtype)
		if template is None:
			return None
		try:
			return ReportTemplateService.render_with_template(template, context)
		except Exception:
			# خطای قالب نباید خروجی را کاملاً متوقف کند
			return None


