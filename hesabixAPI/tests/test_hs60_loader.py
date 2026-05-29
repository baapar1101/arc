import gzip
import io
import tempfile
import zipfile
from pathlib import Path

from app.services.legacy_sql.hs60_loader import materialize_legacy_sql_path


def test_materialize_plain_sql():
	with tempfile.NamedTemporaryFile(suffix=".sql", delete=False) as f:
		f.write(b"INSERT INTO `user` (`id`) VALUES (1);\n")
		path = f.name
	sql_path, cleanup = materialize_legacy_sql_path(path)
	assert sql_path == path
	assert Path(sql_path).read_bytes().startswith(b"INSERT")


def test_materialize_sql_inside_zip():
	raw = io.BytesIO()
	with zipfile.ZipFile(raw, "w") as zf:
		zf.writestr("dump/database.sql", b"CREATE TABLE `business` (id int);\n")
	with tempfile.NamedTemporaryFile(suffix=".hs60", delete=False) as f:
		f.write(raw.getvalue())
		path = f.name
	sql_path, cleanup = materialize_legacy_sql_path(path)
	assert b"CREATE TABLE" in Path(sql_path).read_bytes()
	for p in cleanup:
		if p != path:
			Path(p).unlink(missing_ok=True)
	Path(path).unlink(missing_ok=True)


def test_materialize_gzip_sql():
	payload = gzip.compress(b"INSERT INTO `money` (`id`) VALUES (1);")
	with tempfile.NamedTemporaryFile(suffix=".sql.gz", delete=False) as f:
		f.write(payload)
		path = f.name
	sql_path, _ = materialize_legacy_sql_path(path)
	assert gzip.decompress(Path(sql_path).read_bytes()).startswith(b"INSERT")
	Path(path).unlink(missing_ok=True)
