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


def _anchor_coordinate(rect: dict[str, float], anchor: str) -> float:
	if anchor == "left":
		return rect["x"]
	if anchor == "right":
		return rect["x"] + rect["width"]
	if anchor == "center_x":
		return rect["x"] + rect["width"] / 2
	if anchor == "top":
		return rect["y"]
	if anchor == "bottom":
		return rect["y"] + rect["height"]
	return rect["y"] + rect["height"] / 2


def _link_offset(link: dict[str, Any], profile: str) -> float:
	variant_offsets = link.get("variant_offsets") or {}
	return _number(
		variant_offsets.get(profile) if isinstance(variant_offsets, dict) else None,
		_number(link.get("offset_mm"), 0, -1000, 1000),
		-1000,
		1000,
	)


def _page_pin_offsets(constraints: dict[str, Any], profile: str) -> dict[str, float]:
	offsets = constraints.get("pin_offsets_mm") or {}
	variant_offsets = constraints.get("variant_pin_offsets") or {}
	if isinstance(variant_offsets, dict) and isinstance(variant_offsets.get(profile), dict):
		offsets = {**offsets, **variant_offsets[profile]}
	return {
		key: _number(offsets.get(key), 0, -5000, 5000)
		for key in ("left", "right", "top", "bottom", "center_x", "center_y")
	}


def _resolved_page_rect(
	component: dict[str, Any],
	*,
	width_mm: float,
	height_mm: float,
	profile: str,
) -> dict[str, float]:
	placement = component.get("placement") or {}
	rect = {
		"x": _number(placement.get("x_mm"), 0, 0, width_mm),
		"y": _number(placement.get("y_mm"), 0, 0, height_mm),
		"width": _number(placement.get("width_mm"), 30, 1, width_mm),
		"height": _number(placement.get("height_mm"), 15, 1, height_mm),
	}
	constraints = component.get("constraints") or {}
	pins = constraints.get("pins") or {}
	if not isinstance(pins, dict):
		return rect
	offsets = _page_pin_offsets(constraints, profile)
	if pins.get("left") and pins.get("right"):
		rect["x"] = offsets["left"]
		rect["width"] = max(1, width_mm - offsets["left"] - offsets["right"])
	elif pins.get("right"):
		rect["x"] = width_mm - offsets["right"] - rect["width"]
	elif pins.get("left"):
		rect["x"] = offsets["left"]
	elif pins.get("center_x"):
		rect["x"] = (width_mm - rect["width"]) / 2 + offsets["center_x"]
	if pins.get("top") and pins.get("bottom"):
		rect["y"] = offsets["top"]
		rect["height"] = max(1, height_mm - offsets["top"] - offsets["bottom"])
	elif pins.get("bottom"):
		rect["y"] = height_mm - offsets["bottom"] - rect["height"]
	elif pins.get("top"):
		rect["y"] = offsets["top"]
	elif pins.get("center_y"):
		rect["y"] = (height_mm - rect["height"]) / 2 + offsets["center_y"]
	rect["x"] = max(0, min(width_mm - rect["width"], rect["x"]))
	rect["y"] = max(0, min(height_mm - rect["height"], rect["y"]))
	return rect


def _grid_position(rect: dict[str, float], *, grid_mm: float, columns: int, rows: int) -> tuple[int, int, int, int]:
	column_start = max(1, min(columns, math.floor(rect["x"] / grid_mm) + 1))
	row_start = max(1, min(rows, math.floor(rect["y"] / grid_mm) + 1))
	column_span = max(1, min(columns - column_start + 1, math.ceil(rect["width"] / grid_mm)))
	row_span = max(1, min(rows - row_start + 1, math.ceil(rect["height"] / grid_mm)))
	return column_start, row_start, column_span, row_span


def _page_grid_container(design: dict[str, Any], root: dict[str, Any], *, receipt: bool) -> str:
	layout = root.get("layout") or {}
	grid_mm = int(_number(layout.get("grid_mm"), 1, 1, 5))
	width_mm = _number(layout.get("width_mm"), 190, 10, 1000)
	height_mm = _number(layout.get("height_mm"), 277, 20, 5000)
	columns = max(1, math.ceil(width_mm / grid_mm))
	rows = max(1, math.ceil(height_mm / grid_mm))
	profile = active_variant_key(design)
	components = [
		(region, component)
		for region, component in _page_grid_components(root)
		if component.get("visible", True) is not False
	]
	by_id = {str(component.get("id") or ""): component for _, component in components}
	regions = {str(component.get("id") or ""): region for region, component in components}
	rects = {
		node_id: _resolved_page_rect(component, width_mm=width_mm, height_mm=height_mm, profile=profile)
		for node_id, component in by_id.items()
	}
	# Static sibling anchors are resolved from variant geometry. A top-to-bottom
	# vertical anchor is intentionally left for normal HTML flow below, because
	# the target may grow after Jinja data is rendered.
	for _ in range(max(1, len(by_id))):
		changed = False
		for node_id, component in by_id.items():
			constraints = component.get("constraints") or {}
			for link in constraints.get("links") or []:
				if not isinstance(link, dict):
					continue
				target = link.get("target") or {}
				target_id = str(target.get("id") or "")
				if target_id not in rects:
					continue
				axis = str(link.get("axis") or "")
				source_anchor = str(link.get("source_anchor") or "")
				target_anchor = str(target.get("anchor") or "")
				if axis == "vertical" and source_anchor == "top" and target_anchor == "bottom":
					continue
				desired = _anchor_coordinate(rects[target_id], target_anchor) + _link_offset(link, profile)
				current = _anchor_coordinate(rects[node_id], source_anchor)
				if abs(desired - current) < 0.001:
					continue
				if axis == "horizontal":
					rects[node_id]["x"] += desired - current
					rects[node_id]["x"] = max(0, min(width_mm - rects[node_id]["width"], rects[node_id]["x"]))
				elif axis == "vertical":
					rects[node_id]["y"] += desired - current
					rects[node_id]["y"] = max(0, min(height_mm - rects[node_id]["height"], rects[node_id]["y"]))
				changed = True
		if not changed:
			break
	# Dynamic follow links form normal-flow chains. This is the essential part:
	# a follower is emitted after the target, so rendered content height—not the
	# design-time rectangle—determines its print position.
	follows: dict[str, tuple[str, dict[str, Any]]] = {}
	followers: dict[str, list[str]] = {}
	for node_id, component in by_id.items():
		for link in (component.get("constraints") or {}).get("links") or []:
			if not isinstance(link, dict) or link.get("axis") != "vertical":
				continue
			target = link.get("target") or {}
			if link.get("source_anchor") == "top" and target.get("anchor") == "bottom":
				target_id = str(target.get("id") or "")
				if target_id in by_id:
					follows[node_id] = (target_id, link)
					followers.setdefault(target_id, []).append(node_id)
	emitted: set[str] = set()
	items: list[str] = []
	def component_markup(node_id: str, *, chain_x: float | None = None, gap: float = 0) -> str:
		component = by_id[node_id]
		component_html = _component_html(design, component, receipt=receipt)
		if not component_html:
			return ""
		component_type = str(component.get("component") or "")
		dynamic_class = " rt-page-grid-item-dynamic" if component_type in ("invoice_lines", "invoice_totals", "payments", "note") else ""
		rect = rects[node_id]
		keep_together = (component.get("constraints") or {}).get("keep_together")
		if keep_together is None:
			keep_together = component_type in ("invoice_totals", "payments", "signatures")
		keep = " rt-anchor-keep-together" if keep_together else ""
		if chain_x is not None:
			return (
				f'<div class="rt-anchor-chain-member{dynamic_class}{keep}" data-template-node-ref="{escape(node_id, quote=True)}" '
				f'style="margin-top:{gap:g}mm;margin-left:{rect["x"] - chain_x:g}mm;width:{rect["width"]:g}mm;'
				f'min-height:{rect["height"]:g}mm;">{component_html}</div>'
			)
		column_start, row_start, column_span, row_span = _grid_position(rect, grid_mm=grid_mm, columns=columns, rows=rows)
		constraints = component.get("constraints") or {}
		bottom_mode = str(constraints.get("bottom_mode") or "last_page")
		bottom_pinned = (constraints.get("pins") or {}).get("bottom")
		bottom_class = f" rt-pin-bottom-{bottom_mode.replace('_', '-')}" if bottom_pinned else ""
		fixed_style = ""
		if bottom_pinned and bottom_mode == "every_page":
			bottom_offset = _page_pin_offsets(constraints, profile)["bottom"]
			fixed_style = f"left:{rect['x']:g}mm;bottom:{bottom_offset:g}mm;width:{rect['width']:g}mm;"
		return (
			f'<div class="rt-page-grid-item{dynamic_class}{keep}{bottom_class}" data-template-region="{escape(regions[node_id], quote=True)}" '
			f'style="grid-column:{column_start}/span {column_span};grid-row:{row_start}/span {row_span};'
			f'min-height:{rect["height"]:g}mm;{fixed_style}">{component_html}</div>'
		)

	for node_id in by_id:
		if node_id in emitted or node_id in follows:
			continue
		chain = [node_id]
		cursor = node_id
		while len(followers.get(cursor, [])) == 1:
			next_id = followers[cursor][0]
			if next_id in chain:
				break
			chain.append(next_id)
			cursor = next_id
		if len(chain) == 1:
			markup = component_markup(node_id)
			if markup:
				items.append(markup)
			emitted.add(node_id)
			continue
		chain_x = min(rects[item_id]["x"] for item_id in chain)
		chain_right = max(rects[item_id]["x"] + rects[item_id]["width"] for item_id in chain)
		root_rect = rects[node_id]
		chain_rect = {"x": chain_x, "y": root_rect["y"], "width": chain_right - chain_x, "height": root_rect["height"]}
		column_start, row_start, column_span, row_span = _grid_position(chain_rect, grid_mm=grid_mm, columns=columns, rows=rows)
		members: list[str] = []
		for index, item_id in enumerate(chain):
			gap = 0 if index == 0 else _link_offset(follows[item_id][1], profile)
			members.append(component_markup(item_id, chain_x=chain_x, gap=gap))
			emitted.add(item_id)
		items.append(
			f'<div class="rt-page-grid-item rt-anchor-chain" data-template-anchor-chain="{escape(node_id, quote=True)}" '
			f'style="grid-column:{column_start}/span {column_span};grid-row:{row_start}/span {row_span};'
			f'min-height:{root_rect["height"]:g}mm;">{"".join(members)}</div>'
		)
	# Invalid/legacy branched followers are emitted independently as a safe
	# fallback. Validation requires authors to express them as a serial chain.
	for node_id in by_id:
		if node_id not in emitted:
			markup = component_markup(node_id)
			if markup:
				items.append(markup)
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
.rt-anchor-chain { display:block; align-self:start; overflow:visible; }
.rt-anchor-chain-member { display:block; box-sizing:border-box; }
.rt-anchor-chain-member:first-child { margin-top:0 !important; }
.rt-anchor-chain-member > .rt-component { width:100%; min-height:100%; }
.rt-anchor-keep-together { break-inside:avoid; page-break-inside:avoid; }
.rt-pin-bottom-every-page { position:fixed; bottom:0; }
.rt-component-invoice-lines thead { display:table-header-group; }
.rt-component-invoice-lines tfoot { display:table-footer-group; }
.rt-component-invoice-lines tr { break-inside:avoid; page-break-inside:avoid; }
@media screen and (max-width:720px) {
  .rt-layout-v4 { max-width:100%; overflow-x:auto; }
}
"""
	return html, css.strip(), header, footer
