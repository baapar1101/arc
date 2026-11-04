"""کاتالوگ بسته حسابداری پیشرفته — گیت لایسنس فقط در UI است، API قفل نمی‌شود."""

from pathlib import Path

from adapters.db.seed_data.marketplace_plugins_seed import (
	ADVANCED_ACCOUNTING_PLUGIN_CODE,
	_DEFAULT_PLUGINS,
)


def test_seed_includes_advanced_accounting_plugin():
	plugin = next(p for p in _DEFAULT_PLUGINS if p.code == ADVANCED_ACCOUNTING_PLUGIN_CODE)
	assert plugin.code == "advanced_accounting"
	assert plugin.name == "بسته حسابداری پیشرفته"
	assert plugin.category == "accounting"
	assert plugin.trial_allowed is True
	assert plugin.trial_days == 14
	periods = {period: price for period, price in plugin.plans}
	assert periods["monthly"] == 250_000
	assert periods["yearly"] == 2_500_000
	assert periods["lifetime"] == 9_000_000
	assert "تراز آزمایشی" in plugin.description
	assert "بستن سال مالی" in plugin.description
	assert "راس‌گیری" in plugin.description
	assert "پشتیبان" in plugin.description
	assert "استودیو" in plugin.description


def test_advanced_accounting_has_no_backend_license_gate():
	"""اندپوینت‌ها باید باز بمانند؛ قفل فقط در رابط کاربری است."""
	api_root = Path(__file__).resolve().parents[1]
	forbidden_needles = (
		"require_advanced_accounting",
		"ensure_advanced_accounting",
		"check_advanced_accounting_plugin_active",
	)
	scanned = 0
	for path in (api_root / "adapters" / "api").rglob("*.py"):
		scanned += 1
		text = path.read_text(encoding="utf-8")
		for needle in forbidden_needles:
			assert needle not in text, f"{path} must not gate {needle}"
	assert scanned > 0

	core_dir = api_root / "app" / "core"
	if core_dir.exists():
		for path in core_dir.glob("*plugin_dependency.py"):
			text = path.read_text(encoding="utf-8")
			assert 'PLUGIN_CODE = "advanced_accounting"' not in text
			assert "advanced_accounting" not in text
