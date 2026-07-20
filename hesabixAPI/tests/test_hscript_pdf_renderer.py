"""تست رندر HTML امن Report Spec."""

from __future__ import annotations

from app.services.hscript.pdf_renderer import spec_to_html


def test_spec_to_html_escapes_xss():
	spec = {
		"version": 1,
		"title": '<script>alert(1)</script>',
		"blocks": [
			{"type": "text", "text": "<img src=x onerror=alert(1)>"},
			{"type": "kpi", "label": "فروش", "value": 1000, "format": "currency"},
			{
				"type": "table",
				"columns": ["name", "total"],
				"rows": [{"name": "A&B", "total": 12}],
			},
			{
				"type": "chart",
				"chart_type": "bar",
				"title": "Chart",
				"data": [{"x": "A", "y": 3}, {"x": "B", "y": 7}],
			},
		],
	}
	html = spec_to_html(spec, business_name="Demo Co")
	assert "<script>" not in html
	assert "&lt;script&gt;" in html
	assert "<img" not in html
	assert "A&amp;B" in html
	assert "Demo Co" in html
	assert "chart-bar" in html


def test_unknown_block_skipped():
	html = spec_to_html({"blocks": [{"type": "evil", "text": "x"}]})
	assert "evil" not in html
