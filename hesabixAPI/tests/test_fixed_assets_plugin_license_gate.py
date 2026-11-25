"""ثابت کد افزونه اموال — گیت لایسنس کامل به FastAPI وابسته است و در محیط بدون fastapi جدا اجرا می‌شود."""

from app.core.fixed_asset_accounts import COST_FURNITURE, PARENT_COST, SYSTEM_CLASSES


def test_plugin_code_constant_without_fastapi():
	# این فایل dependency را ایمپورت نمی‌کند تا روی مفسر بدون fastapi هم سبز بماند.
	from pathlib import Path

	src = Path(__file__).resolve().parents[1] / "app" / "core" / "fixed_assets_plugin_dependency.py"
	text = src.read_text(encoding="utf-8")
	assert 'PLUGIN_CODE = "fixed_assets"' in text


def test_system_coa_parents_are_standard_prefixes():
	assert PARENT_COST == "107"
	assert COST_FURNITURE.startswith(PARENT_COST)
	assert {c["code"] for c in SYSTEM_CLASSES} == {"land", "building", "vehicle", "furniture"}
