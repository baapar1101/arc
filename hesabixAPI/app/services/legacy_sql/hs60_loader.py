from __future__ import annotations

import gzip
import io
import os
import tempfile
import zipfile
from pathlib import Path
from typing import List, Tuple


class LegacyImportFileError(ValueError):
	"""فایل قابل تبدیل به دامپ SQL نیست."""


def materialize_legacy_sql_path(path: str | Path) -> Tuple[str, List[str]]:
	"""
	مسیر فایل آپلودشده را به فایل .sql (یا .sql.gz) قابل پارس تبدیل می‌کند.

	پشتیبانی:
	- .sql / plain SQL
	- .sql.gz / .gz (gzip)
	- .zip حاوی حداقل یک فایل .sql
	- .hs60 (اغلب همان دامپ SQL فشرده یا داخل ZIP است)
	"""
	path = Path(path)
	if not path.is_file():
		raise LegacyImportFileError(f"فایل یافت نشد: {path}")

	raw = path.read_bytes()
	if len(raw) < 20:
		raise LegacyImportFileError("فایل خیلی کوچک است.")

	cleanup: List[str] = [str(path)]
	suffix = path.suffix.lower()
	name_lower = path.name.lower()

	# gzip
	if raw[:2] == b"\x1f\x8b" or name_lower.endswith(".gz"):
		return str(path), cleanup

	# ZIP / hs60 container
	if raw[:4] == b"PK\x03\x04" or suffix == ".zip" or suffix == ".hs60":
		sql_path = _extract_sql_from_zip(raw)
		cleanup.append(sql_path)
		return sql_path, cleanup

	# plain SQL (شامل فایل .hs60 که در واقع متن SQL است)
	if _looks_like_sql(raw):
		return str(path), cleanup

	raise LegacyImportFileError(
		"فرمت فایل شناخته نشد. فایل باید دامپ SQL، .sql.gz، .zip یا .hs60 حاوی SQL باشد."
	)


def _looks_like_sql(raw: bytes) -> bool:
	sample = raw[:8192].upper()
	return b"INSERT INTO" in sample or b"CREATE TABLE" in sample


def _extract_sql_from_zip(raw: bytes) -> str:
	try:
		zf = zipfile.ZipFile(io.BytesIO(raw))
	except zipfile.BadZipFile as exc:
		raise LegacyImportFileError("آرشیو ZIP معتبر نیست.") from exc

	candidates: List[str] = []
	for name in zf.namelist():
		lower = name.lower()
		if lower.endswith(".sql") or lower.endswith(".sql.gz"):
			candidates.append(name)
	if not candidates:
		raise LegacyImportFileError("در آرشیو فایل .sql یافت نشد.")

	best = max(candidates, key=lambda n: zf.getinfo(n).file_size)
	data = zf.read(best)
	if best.lower().endswith(".gz") or data[:2] == b"\x1f\x8b":
		data = gzip.decompress(data)

	fd, temp_path = tempfile.mkstemp(suffix=".sql")
	try:
		with os.fdopen(fd, "wb") as fh:
			fh.write(data)
	except Exception:
		os.close(fd)
		raise

	if not _looks_like_sql(data):
		try:
			os.unlink(temp_path)
		except OSError:
			pass
		raise LegacyImportFileError("محتوای استخراج‌شده شبیه دامپ MySQL نیست.")

	return temp_path
