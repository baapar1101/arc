from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
import time
import logging

from sqlalchemy.orm import Session
from sqlalchemy import and_
from jinja2.sandbox import SandboxedEnvironment
from jinja2 import StrictUndefined, BaseLoader, TemplateSyntaxError, UndefinedError

from adapters.db.models.report_template import ReportTemplate
from app.core.responses import ApiError
from app.services.template_builder_compiler import compile_design_to_jinja_html

logger = logging.getLogger(__name__)


class ReportTemplateService:
	"""سرویس مدیریت قالب‌های گزارش"""
	
	# سیستم کش برای قالب‌ها
	_template_cache: Dict[int, Tuple[ReportTemplate, float]] = {}
	CACHE_TTL = 300  # 5 دقیقه

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
		except Exception as e:
			logger.error(f"Error getting template {template_id}: {e}", exc_info=True)
			return None
	
	@staticmethod
	def get_template_cached(
		db: Session, 
		template_id: int, 
		business_id: Optional[int] = None
	) -> Optional[ReportTemplate]:
		"""دریافت قالب با کش"""
		cache_key = template_id
		
		if cache_key in ReportTemplateService._template_cache:
			template, cached_time = ReportTemplateService._template_cache[cache_key]
			if time.time() - cached_time < ReportTemplateService.CACHE_TTL:
				return template
		
		template = ReportTemplateService.get_template(db, template_id, business_id)
		if template:
			ReportTemplateService._template_cache[cache_key] = (template, time.time())
		return template
	
	@staticmethod
	def invalidate_cache(template_id: int):
		"""پاک کردن کش یک قالب"""
		ReportTemplateService._template_cache.pop(template_id, None)

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
		# پاک کردن کش
		ReportTemplateService.invalidate_cache(template_id)
		return entity

	@staticmethod
	def delete_template(db: Session, template_id: int, business_id: int) -> None:
		entity = ReportTemplateService.get_template(db, template_id, business_id)
		if not entity:
			return
		db.delete(entity)
		db.commit()
		# پاک کردن کش
		ReportTemplateService.invalidate_cache(template_id)

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
		# اگر engine=builder باشد، ابتدا از design داخل assets خروجی HTML/CSS/Header/Footer تولید می‌کنیم
		try:
			if str(getattr(template, "engine", "") or "").lower() == "builder":
				assets = getattr(template, "assets", None) or {}
				design = assets.get("builder_design") or assets.get("design") or {}
				html, css, header_html, footer_html = compile_design_to_jinja_html(design)
				# یک نمونه موقت با مقادیر تولیدی
				class _Temp:
					pass
				tmp = _Temp()
				tmp.content_html = html
				tmp.content_css = css or template.content_css
				tmp.header_html = header_html or template.header_html
				tmp.footer_html = footer_html or template.footer_html
				tmp.paper_size = template.paper_size
				tmp.orientation = template.orientation
				tmp.margins = template.margins
				template = tmp  # type: ignore[assignment]
		except Exception:
			# مشکلی در کامپایل: اجازه می‌دهیم مسیر معمول اجرا شود تا خطا در مرحله رندر گزارش گردد
			pass
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
		def _money(v, decimals: int = 0, sep: str = ","):
			try:
				n = float(v)
			except Exception:
				return str(v)
			if decimals <= 0:
				s = f"{int(round(n)):,}"
			else:
				s = f"{n:,.{decimals}f}"
			return s.replace(",", sep)
		env.filters["money"] = _money
		def _date(v, fmt: str = "%Y/%m/%d"):
			try:
				import datetime
				if isinstance(v, (int, float)):
					dt = datetime.datetime.fromtimestamp(v)
				elif isinstance(v, str):
					# تلاش ساده: ISO یا yyyy-mm-dd
					try:
						dt = datetime.datetime.fromisoformat(v.replace("Z", "+00:00"))
					except Exception:
						try:
							parts = v.split("-")
							dt = datetime.datetime(int(parts[0]), int(parts[1]), int(parts[2][:2]))
						except Exception:
							return v
				elif hasattr(v, "strftime"):
					dt = v  # type: ignore[assignment]
				else:
					return str(v)
				return dt.strftime(fmt)
			except Exception:
				return str(v)
		env.filters["date"] = _date
		
		# فیلتر اعداد فارسی
		def _persian_number(v):
			"""تبدیل اعداد انگلیسی به فارسی"""
			persian_digits = '۰۱۲۳۴۵۶۷۸۹'
			english_digits = '0123456789'
			s = str(v)
			for en, fa in zip(english_digits, persian_digits):
				s = s.replace(en, fa)
			return s
		env.filters["persian"] = _persian_number
		
		# فیلتر فرمت شماره حساب
		def _account_number(v, format_type="standard"):
			"""فرمت شماره حساب: 1234-567-890"""
			s = str(v).replace("-", "").replace(" ", "")
			if format_type == "standard" and len(s) >= 9:
				return f"{s[:4]}-{s[4:7]}-{s[7:]}"
			return s
		env.filters["account"] = _account_number
		
		# فیلتر خلاصه متن
		def _truncate(v, length=50, suffix="..."):
			"""کوتاه کردن متن"""
			s = str(v)
			if len(s) <= length:
				return s
			return s[:length] + suffix
		env.filters["truncate"] = _truncate
		
		# فیلتر شرطی برای نمایش/مخفی کردن
		def _show_if(condition, true_val, false_val=""):
			"""نمایش شرطی"""
			return true_val if condition else false_val
		env.filters["show_if"] = _show_if

		# تزریق assets به context برای دسترسی در قالب‌ها (مثلاً assets.images['logo'])
		try:
			if hasattr(template, "assets") and getattr(template, "assets"):
				ctx = dict(context or {})
				ctx.setdefault("assets", getattr(template, "assets"))
			else:
				ctx = context
		except Exception:
			ctx = context
		try:
			template_obj = env.from_string(template.content_html)
			html = template_obj.render(**ctx)
		except TemplateSyntaxError as e:
			logger.error(f"Template syntax error in template {getattr(template, 'id', 'unknown')}: {e}", exc_info=True)
			raise ApiError("TEMPLATE_SYNTAX_ERROR", f"خطای دستور در قالب: {e.message} (خط {e.lineno})", http_status=400)
		except UndefinedError as e:
			logger.warning(f"Undefined variable in template {getattr(template, 'id', 'unknown')}: {e}", exc_info=True)
			raise ApiError("TEMPLATE_VARIABLE_ERROR", f"متغیر تعریف نشده در قالب: {e.message}", http_status=400)
		except Exception as e:
			logger.exception(f"Template rendering error for template {getattr(template, 'id', 'unknown')}: {e}")
			raise ApiError("TEMPLATE_RENDER_ERROR", f"خطا در رندر قالب: {str(e)}", http_status=500)

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
			# اگر هر چهار مقدار موجود بود از shorthand استفاده کن؛ در غیر این صورت هرکدام جداگانه
			if all(x is not None for x in (mt, mr, mb, ml)):
				page_css_parts.append(f"margin: {mt} {mr} {mb} {ml};")
			else:
				if mt is not None:
					page_css_parts.append(f"margin-top: {mt};")
				if mr is not None:
					page_css_parts.append(f"margin-right: {mr};")
				if mb is not None:
					page_css_parts.append(f"margin-bottom: {mb};")
				if ml is not None:
					page_css_parts.append(f"margin-left: {ml};")
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
		# درج Header/Footer ساده در بدنه (در صورت وجود). طراح می‌تواند با CSS آن‌ها را به fixed تبدیل کند.
		try:
			header_html = (template.header_html or "").strip()
			footer_html = (template.footer_html or "").strip()
			if header_html:
				insertion = f'<div class="__tpl-header">{header_html}</div>'
				if "<body" in html and "</body>" in html:
					html = html.replace("<body", "<body", 1)  # no-op anchor
					body_start = html.find(">") + 1 if html.startswith("<body") else html.find("<body")
					# ساده: دقیقا بعد از تگ <body> درج می‌کنیم
					html = html.replace("<body>", f"<body>{insertion}", 1)
				else:
					html = f"{insertion}{html}"
			if footer_html:
				insertion = f'<div class="__tpl-footer">{footer_html}</div>'
				if "</body>" in html:
					html = html.replace("</body>", f"{insertion}</body>", 1)
				else:
					html = f"{html}{insertion}"
		except Exception:
			pass
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
		except ApiError:
			# خطاهای API را propagate کنیم
			raise
		except Exception as e:
			# خطای قالب نباید خروجی را کاملاً متوقف کند، اما لاگ می‌کنیم
			logger.warning(f"Template rendering failed for template {template.id if template else 'unknown'}: {e}", exc_info=True)
			return None
	
	@staticmethod
	def validate_template(content_html: str, context: Dict[str, Any] = None) -> List[str]:
		"""اعتبارسنجی قالب و برگرداندن لیست خطاها"""
		errors = []
		try:
			env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True, undefined=StrictUndefined)
			template_obj = env.from_string(content_html)
			# تست رندر با context خالی یا نمونه
			test_context = context or {}
			template_obj.render(**test_context)
		except TemplateSyntaxError as e:
			errors.append(f"خطای دستور: {e.message} در خط {e.lineno}")
		except UndefinedError as e:
			errors.append(f"متغیر تعریف نشده: {e.message}")
		except Exception as e:
			errors.append(f"خطای رندر: {str(e)}")
		return errors


