from pathlib import Path

from app.services.legacy_sql.sql_dump_reader import (
	load_legacy_sql_dump,
	validate_legacy_dump,
)

SAMPLE = Path(__file__).resolve().parents[2] / "oldsimpleDatabase.sql"


def test_load_sample_dump():
	if not SAMPLE.is_file():
		return
	data = load_legacy_sql_dump(SAMPLE)
	errors = validate_legacy_dump(data)
	assert errors == []
	analysis = data.analyze()
	assert analysis["business_count"] >= 1
	assert analysis["document_count"] >= 100
	assert "buy" in analysis["document_types"]
