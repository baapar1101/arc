"""ایمپورت دیتابیس قدیمی MySQL (دامپ .sql)."""

__all__ = [
	"LegacyImportOptions",
	"LegacySqlImportService",
]


def __getattr__(name: str):
	if name in ("LegacyImportOptions", "LegacySqlImportService"):
		from app.services.legacy_sql.legacy_sql_import_service import (
			LegacyImportOptions,
			LegacySqlImportService,
		)

		return LegacyImportOptions if name == "LegacyImportOptions" else LegacySqlImportService
	raise AttributeError(name)
