from __future__ import annotations

from typing import Any, Dict, List, Tuple


def _escape_html(s: str) -> str:
	try:
		import html
		return html.escape(s)
	except Exception:
		return s


def compile_design_to_jinja_html(design: Dict[str, Any]) -> Tuple[str, str, str, str]:
	"""
	یک کامپایلر ساده برای تبدیل طراحی Builder به Jinja2 HTML/CSS/Header/Footer.
	MVP پشتیبانی می‌کند از:
	- blocks: [ {type: 'text'|'image'|'table', props: {...}} ]
	- text.props.text (می‌تواند شامل {{ }} باشد)
	- image.props.src (می‌تواند شامل {{ }} باشد), width/height اختیاری
	- table.props.items (نام آرایه مثلا 'items')، columns: [{key,title}]
	- header/footer اختیاری در design['header']/['footer'] با فهرست بلوک‌ها
	"""
	def render_block(block: Dict[str, Any]) -> str:
		bt = (block.get("type") or "").lower()
		props = block.get("props") or {}
		show_if = (props.get("showIf") or "").strip()
		def wrap_conditional(inner: str) -> str:
			if show_if:
				return f"{{% if {show_if} %}}{inner}{{% endif %}}"
			return inner
		if bt == "text":
			text = str(props.get("text") or "")
			align = str(props.get("align") or "")
			style = []
			if align in ("left", "right", "center"):
				style.append(f"text-align:{align};")
			style_str = f' style="{" ".join(style)}"' if style else ""
			return wrap_conditional(f"<div{style_str}>{text}</div>")
		if bt == "image":
			src = str(props.get("src") or "")
			if src.startswith("asset:"):
				name = _escape_html(src.split("asset:", 1)[1].strip())
				# ارجاع به Jinja: انتظار می‌رود assets.images[name] در context موجود باشد
				src = f"{{{{ assets.images['{name}'] }}}}"
			w = props.get("width")
			h = props.get("height")
			size = []
			if w: size.append(f'width="{_escape_html(str(w))}"')
			if h: size.append(f'height="{_escape_html(str(h))}"')
			size_str = (" " + " ".join(size)) if size else ""
			alt = _escape_html(str(props.get("alt") or ""))
			return wrap_conditional(f'<img src="{_escape_html(src)}"{size_str} alt="{alt}" />')
		if bt == "table":
			items_var = str(props.get("items") or "items")
			columns = props.get("columns") or []
			headers = "".join(f"<th>{_escape_html(str(c.get('title') or c.get('key') or ''))}</th>" for c in columns)
			cell_exprs = []
			for c in columns:
				key = _escape_html(str(c.get("key") or ""))
				fmt = str(c.get("format") or "").lower()
				if fmt == "money":
					cell_exprs.append(f"{{{{ row.{key}|money }}}}")
				elif fmt == "date":
					cell_exprs.append(f"{{{{ row.{key}|date }}}}")
				else:
					cell_exprs.append(f"{{{{ row.{key} }}}}")
			row_cells = "".join(f"<td>{expr}</td>" for expr in cell_exprs)
			body = f"{{% for row in {items_var} %}}<tr>{row_cells}</tr>{{% endfor %}}"
			return wrap_conditional(f"<table><thead><tr>{headers}</tr></thead><tbody>{body}</tbody></table>")
		if bt == "totals":
			# props.items: [{title, expr, format}]
			items = props.get("items") or []
			rows_html = []
			for it in items:
				title = _escape_html(str(it.get("title") or ""))
				expr = str(it.get("expr") or "")
				fmt = str(it.get("format") or "").lower()
				if fmt == "money":
					val = f"{{{{ {expr}|money }}}}"
				elif fmt == "date":
					val = f"{{{{ {expr}|date }}}}"
				else:
					val = f"{{{{ {expr} }}}}"
				rows_html.append(f"<tr><td>{title}</td><td style=\"text-align:right;\">{val}</td></tr>")
			return wrap_conditional(f"<table class=\"totals\"><tbody>{''.join(rows_html)}</tbody></table>")
		if bt == "qr":
			# props.src: URL یا data URI شامل متغیر
			src = str(props.get("src") or "")
			size = props.get("size") or 120
			return wrap_conditional(f'<img src="{_escape_html(src)}" width="{_escape_html(str(size))}" height="{_escape_html(str(size))}" alt="QR" />')
		return "<!-- unsupported block -->"

	def render_blocks(blocks: List[Dict[str, Any]]) -> str:
		return "".join(render_block(b) for b in (blocks or []))

	header_html = render_blocks(design.get("header") or [])
	footer_html = render_blocks(design.get("footer") or [])
	body_html = render_blocks(design.get("blocks") or [])
	css = str(design.get("css") or "")
	html = f"<!doctype html><html><head></head><body>{body_html}</body></html>"
	return html, css, header_html, footer_html


