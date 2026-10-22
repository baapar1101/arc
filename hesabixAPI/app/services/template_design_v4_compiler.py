from __future__ import annotations

from html import escape
import math
from typing import Any

from app.services.report_template_gallery import get_family
from app.services.report_template_v4_service import (
	COMPILER_NAME,
	COMPILER_VERSION,
	active_variant_key,
	is_v4_design,
	resolved_root,
	v4_to_v3_projection,
)
from app.services.template_design_v3_compiler import (
	_compile_block_content,
	compile_v3_design_to_jinja_html,
)


def _number(value: Any, default: float, minimum: float, maximum: float) -> float:
	try:
		return max(minimum, min(maximum, float(value)))
	except (TypeError, ValueError):
		return default


def _component_html(design: dict[str, Any], node: dict[str, Any], *, receipt: bool) -> str:
	if node.get("visible", True) is False:
		return ""
	component = str(node.get("component") or "")
	block = {
		"id": node.get("id"),
		"type": component,
		"visible": node.get("visible", True),
		"props": node.get("props") or {},
		"style": node.get("style") or {},
	}
	content = _compile_block_content(design, block, receipt=receipt)
	if not content:
		return ""
	style = node.get("style") or {}
	align = str(style.get("text_align") or "").lower()
	if not align and component == "custom_text":
		align = str((node.get("props") or {}).get("align") or "").lower()
	classes = ["rt-node", "rt-component", f"rt-component-{component.replace('_', '-')}"]
	if align in ("right", "center", "left"):
		classes.append(f"rt-block-align-{align}")
	return (
		f'<div class="{" ".join(classes)}" '
		f'data-template-node-id="{escape(str(node.get("id") or ""), quote=True)}">{content}</div>'
	)


def _grid_container(design: dict[str, Any], node: dict[str, Any], *, receipt: bool) -> str:
	layout = node.get("layout") or {}
	gap = _number(layout.get("gap_mm"), 0, 0, 50)
	height_mode = str(layout.get("height_mode") or "auto")
	height_css = ""
	if height_mode in ("minimum", "fixed"):
		height = _number(layout.get("height_mm"), 20, 4, 500)
		height_css = f"{'height' if height_mode == 'fixed' else 'min-height'}:{height:g}mm;"
	children: list[str] = []
	for child in node.get("children") or []:
		if not isinstance(child, dict) or child.get("kind") != "component":
			continue
		placement = child.get("placement") or {}
		span = int(_number(placement.get("column_span"), 60, 1, 60))
		child_html = _component_html(design, child, receipt=receipt)
		if child_html:
			children.append(f'<div class="rt-grid-cell" style="grid-column:span {span};">{child_html}</div>')
	return (
		f'<div class="rt-node rt-container rt-container-grid" data-template-node-id="{escape(str(node.get("id") or ""), quote=True)}" '
		f'style="gap:{gap:g}mm;{height_css}">{"".join(children)}</div>'
	)


def _freeform_container(design: dict[str, Any], node: dict[str, Any], *, receipt: bool) -> str:
	layout = node.get("layout") or {}
	height = _number(layout.get("height_mm"), 40, 4, 500)
	children: list[str] = []
	for child in node.get("children") or []:
		if not isinstance(child, dict) or child.get("kind") != "component":
			continue
		if child.get("component") in ("invoice_lines", "invoice_totals", "payments"):
			raise ValueError(f"Dynamic component '{child.get('component')}' cannot be compiled in freeform")
		placement = child.get("placement") or {}
		x = _number(placement.get("x_mm"), 0, 0, 500)
		y = _number(placement.get("y_mm"), 0, 0, height)
		width = _number(placement.get("width_mm"), 30, 1, 500)
		child_height = _number(placement.get("height_mm"), 15, 1, height)
		child_html = _component_html(design, child, receipt=receipt)
		if child_html:
			children.append(
				f'<div class="rt-freeform-item" style="left:{x:g}mm;top:{y:g}mm;width:{width:g}mm;height:{child_height:g}mm;">{child_html}</div>'
			)
	return (
		f'<div class="rt-node rt-container rt-container-freeform" data-template-node-id="{escape(str(node.get("id") or ""), quote=True)}" '
		f'style="height:{height:g}mm;">{"".join(children)}</div>'
	)


def _flow_or_stack_container(design: dict[str, Any], node: dict[str, Any], *, receipt: bool) -> str:
	layout = node.get("layout") or {}
	layout_type = str(layout.get("type") or "flow")
	gap = _number(layout.get("gap_mm"), 0, 0, 50)
	children = "".join(_node_html(design, child, receipt=receipt) for child in node.get("children") or [] if isinstance(child, dict))
	return (
		f'<div class="rt-node rt-container rt-container-{layout_type}" data-template-node-id="{escape(str(node.get("id") or ""), quote=True)}" '
		f'style="gap:{gap:g}mm;">{children}</div>'
	)


def _node_html(design: dict[str, Any], node: dict[str, Any], *, receipt: bool) -> str:
	if node.get("kind") == "component":
		return _component_html(design, node, receipt=receipt)
	layout_type = str((node.get("layout") or {}).get("type") or "flow")
	if layout_type == "grid":
		return _grid_container(design, node, receipt=receipt)
	if layout_type == "freeform":
		return _freeform_container(design, node, receipt=receipt)
	return _flow_or_stack_container(design, node, receipt=receipt)


def _page_grid_components(
	node: dict[str, Any],
	*,
	region: str = "body",
) -> list[tuple[str, dict[str, Any]]]:
	if node.get("kind") == "component":
		return [(region, node)]
	next_region = str(node.get("region") or region)
	items: list[tuple[str, dict[str, Any]]] = []
	for child in node.get("children") or []:
		if isinstance(child, dict):
			items.extend(_page_grid_components(child, region=next_region))
	return items


def _page_grid_container(design: dict[str, Any], root: dict[str, Any], *, receipt: bool) -> str:
	layout = root.get("layout") or {}
	grid_mm = int(_number(layout.get("grid_mm"), 1, 1, 5))
	width_mm = _number(layout.get("width_mm"), 190, 10, 1000)
	height_mm = _number(layout.get("height_mm"), 277, 20, 5000)
	columns = max(1, math.ceil(width_mm / grid_mm))
	rows = max(1, math.ceil(height_mm / grid_mm))
	items: list[str] = []
	for region, component in _page_grid_components(root):
		if component.get("visible", True) is False:
			continue
		placement = component.get("placement") or {}
		x = _number(placement.get("x_mm"), 0, 0, width_mm)
		y = _number(placement.get("y_mm"), 0, 0, height_mm)
		width = _number(placement.get("width_mm"), 30, 1, width_mm)
		height = _number(placement.get("height_mm"), 15, 1, height_mm)
		column_start = max(1, min(columns, math.floor(x / grid_mm) + 1))
		row_start = max(1, min(rows, math.floor(y / grid_mm) + 1))
		column_span = max(1, min(columns - column_start + 1, math.ceil(width / grid_mm)))
		row_span = max(1, min(rows - row_start + 1, math.ceil(height / grid_mm)))
		component_html = _component_html(design, component, receipt=receipt)
		if not component_html:
			continue
		component_type = str(component.get("component") or "")
		dynamic_class = " rt-page-grid-item-dynamic" if component_type in ("invoice_lines", "invoice_totals", "payments", "note") else ""
		items.append(
			f'<div class="rt-page-grid-item{dynamic_class}" data-template-region="{escape(region, quote=True)}" '
			f'style="grid-column:{column_start}/span {column_span};grid-row:{row_start}/span {row_span};'
			f'min-height:{height:g}mm;">{component_html}</div>'
		)
	return (
		f'<main class="rt-layout rt-layout-v4 rt-page-grid" data-template-node-id="{escape(str(root.get("id") or ""), quote=True)}" '
		f'style="--rt-page-grid-mm:{grid_mm};--rt-page-grid-width:{width_mm:g}mm;--rt-page-grid-height:{height_mm:g}mm;'
		f'grid-template-columns:repeat({columns},minmax(0,1fr));grid-template-rows:repeat({rows},minmax({grid_mm:g}mm,auto));">'
		f'{"".join(items)}</main>'
	)


def _region_html(design: dict[str, Any], root: dict[str, Any], region: str, *, receipt: bool) -> str:
	for node in root.get("children") or []:
		if isinstance(node, dict) and node.get("region") == region:
			return _node_html(design, node, receipt=receipt)
	return ""


def compile_v4_design_to_jinja_html(design: dict[str, Any]) -> tuple[str, str, str, str]:
	if not is_v4_design(design):
		raise ValueError("Not a v4 design schema")
	contract = design.get("compiler_contract") or {}
	if contract.get("name") != COMPILER_NAME or int(contract.get("version") or 0) != COMPILER_VERSION:
		raise ValueError("Unsupported compiler contract")
	if contract.get("output") != "html_css":
		raise ValueError("Studio v4 compiler output must be html_css")
	family = get_family(str(design.get("family_id") or ""))
	if not family or family.layout not in ("invoice_detail", "invoice_receipt"):
		raise ValueError("Studio v4 supports invoice detail and receipt layouts")
	receipt = family.layout == "invoice_receipt"
	direction = str((design.get("theme") or {}).get("direction") or "rtl").lower()
	if direction not in ("rtl", "ltr"):
		direction = "rtl"
	# Reuse the established theme/table CSS. Only layout markup is compiled here.
	_, base_css, _, _ = compile_v3_design_to_jinja_html(v4_to_v3_projection(design))
	root = resolved_root(design)
	page_grid = str((root.get("layout") or {}).get("type") or "") == "page_grid"
	if page_grid:
		header = ""
		body = _page_grid_container(design, root, receipt=receipt)
		footer = ""
	else:
		header = _region_html(design, root, "header", receipt=receipt)
		body = _region_html(design, root, "body", receipt=receipt)
		footer = _region_html(design, root, "footer", receipt=receipt)
	profile = active_variant_key(design)
	rendered_body = body if page_grid else f'<main class="rt-layout rt-layout-v4">{body}</main>'
	html = (
		f'<!doctype html><html dir="{direction}" data-template-schema="4" '
		f'data-template-variant="{escape(profile, quote=True)}"><head></head><body>'
		f'{rendered_body}</body></html>'
	)
	css = base_css + """
.rt-layout-v4, .rt-layout-v4 * { box-sizing:border-box; }
.rt-container-flow { display:flex; flex-direction:column; width:100%; }
.rt-container-grid { display:grid; grid-template-columns:repeat(60,minmax(0,1fr)); align-items:start; width:100%; }
.rt-grid-cell, .rt-component { min-width:0; max-width:100%; }
.rt-container-freeform { position:relative; width:100%; overflow:hidden; }
.rt-freeform-item { position:absolute; min-width:0; overflow:hidden; }
.rt-freeform-item > .rt-component { width:100%; height:100%; }
.rt-container-stack { display:grid; width:100%; }
.rt-container-stack > .rt-node { grid-area:1 / 1; }
.rt-page-grid { display:grid; width:100%; min-height:var(--rt-page-grid-height); align-items:stretch; }
.rt-page-grid-item { min-width:0; overflow:visible; align-self:stretch; }
.rt-page-grid-item > .rt-component { width:100%; min-height:100%; }
.rt-page-grid-item-dynamic { height:auto; align-self:start; }
@media screen and (max-width:720px) {
  .rt-layout-v4 { max-width:100%; overflow-x:auto; }
}
"""
	return html, css.strip(), header, footer
