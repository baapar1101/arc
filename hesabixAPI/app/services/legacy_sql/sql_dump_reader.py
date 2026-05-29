from __future__ import annotations

import gzip
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


INSERT_HEADER_RE = re.compile(
	r"INSERT\s+INTO\s+`(?P<table>[^`]+)`\s*\((?P<cols>[^)]+)\)\s*VALUES\s*",
	re.IGNORECASE,
)

REQUIRED_TABLES = frozenset({
	"user",
	"business",
	"year",
	"person",
	"commodity",
	"hesabdari_doc",
	"hesabdari_row",
	"money",
})


@dataclass
class LegacySqlData:
	tables: Dict[str, List[Dict[str, Any]]] = field(default_factory=dict)

	def rows(self, table: str) -> List[Dict[str, Any]]:
		return self.tables.get(table, [])

	def count(self, table: str) -> int:
		return len(self.rows(table))

	def analyze(self) -> Dict[str, Any]:
		doc_types: Dict[str, int] = {}
		for doc in self.rows("hesabdari_doc"):
			t = str(doc.get("type") or "").strip()
			if t:
				doc_types[t] = doc_types.get(t, 0) + 1
		return {
			"tables": {t: len(rows) for t, rows in sorted(self.tables.items())},
			"business_count": self.count("business"),
			"user_count": self.count("user"),
			"document_count": self.count("hesabdari_doc"),
			"document_row_count": self.count("hesabdari_row"),
			"document_types": doc_types,
		}


def _parse_column_list(cols_raw: str) -> List[str]:
	return [c.strip().strip("`").strip() for c in cols_raw.split(",")]


def _parse_sql_value(text: str, pos: int) -> Tuple[Any, int]:
	n = len(text)
	while pos < n and text[pos] in " \t\n\r":
		pos += 1
	if pos >= n:
		raise ValueError("unexpected end while parsing value")

	ch = text[pos]
	if ch == "N" and text[pos : pos + 4].upper() == "NULL":
		return None, pos + 4
	if ch == "'":
		pos += 1
		buf: List[str] = []
		while pos < n:
			c = text[pos]
			if c == "\\" and pos + 1 < n:
				nxt = text[pos + 1]
				escapes = {"n": "\n", "r": "\r", "t": "\t", "'": "'", "\\": "\\"}
				buf.append(escapes.get(nxt, nxt))
				pos += 2
				continue
			if c == "'":
				if pos + 1 < n and text[pos + 1] == "'":
					buf.append("'")
					pos += 2
					continue
				return "".join(buf), pos + 1
			buf.append(c)
			pos += 1
		raise ValueError("unterminated string in SQL value")
	if ch in "-0123456789.":
		j = pos
		while j < n and text[j] in "0123456789.-+eE":
			j += 1
		raw = text[pos:j]
		if "." in raw or "e" in raw.lower():
			try:
				return float(raw), j
			except ValueError:
				return raw, j
		try:
			return int(raw), j
		except ValueError:
			return raw, j
	raise ValueError(f"unsupported SQL value at {pos}: {text[pos : pos + 20]!r}")


def _parse_tuple(text: str, pos: int) -> Tuple[List[Any], int]:
	while pos < len(text) and text[pos] in " \t\n\r":
		pos += 1
	if pos >= len(text) or text[pos] != "(":
		raise ValueError("expected '('")
	pos += 1
	values: List[Any] = []
	while True:
		while pos < len(text) and text[pos] in " \t\n\r":
			pos += 1
		if pos < len(text) and text[pos] == ")":
			return values, pos + 1
		val, pos = _parse_sql_value(text, pos)
		values.append(val)
		while pos < len(text) and text[pos] in " \t\n\r":
			pos += 1
		if pos < len(text) and text[pos] == ",":
			pos += 1
			continue
		if pos < len(text) and text[pos] == ")":
			return values, pos + 1
		raise ValueError("expected ',' or ')' in tuple")


def _iter_insert_statements(sql: str):
	pos = 0
	n = len(sql)
	while pos < n:
		m = INSERT_HEADER_RE.search(sql, pos)
		if not m:
			break
		table = m.group("table")
		columns = _parse_column_list(m.group("cols"))
		pos = m.end()
		# read tuples until semicolon outside strings
		row_values: List[List[Any]] = []
		while pos < n:
			while pos < n and sql[pos] in " \t\n\r":
				pos += 1
			if pos >= n:
				break
			if sql[pos] == ";":
				pos += 1
				break
			if sql[pos] == "(":
				vals, pos = _parse_tuple(sql, pos)
				row_values.append(vals)
				while pos < n and sql[pos] in " \t\n\r":
					pos += 1
				if pos < n and sql[pos] == ",":
					pos += 1
					continue
				continue
			# skip garbage between statements
			pos += 1
		yield table, columns, row_values


def load_legacy_sql_dump(path: str | Path) -> LegacySqlData:
	path = Path(path)
	raw = path.read_bytes()
	if path.suffix == ".gz" or raw[:2] == b"\x1f\x8b":
		sql = gzip.decompress(raw).decode("utf-8", errors="replace")
	else:
		sql = raw.decode("utf-8", errors="replace")

	data = LegacySqlData()
	for table, columns, tuples in _iter_insert_statements(sql):
		rows = data.tables.setdefault(table, [])
		for tup in tuples:
			if len(tup) != len(columns):
				# برخی دامپ‌ها ستون/مقدار ناهم‌تراز دارند؛ تا حد امکان نادیده می‌گیریم
				continue
			rows.append(dict(zip(columns, tup)))
	return data


def validate_legacy_dump(data: LegacySqlData) -> List[str]:
	errors: List[str] = []
	missing = REQUIRED_TABLES - set(data.tables.keys())
	if missing:
		errors.append(f"جداول اجباری یافت نشد: {', '.join(sorted(missing))}")
	if data.count("business") < 1:
		errors.append("حداقل یک ردیف business لازم است")
	if data.count("user") < 1:
		errors.append("حداقل یک ردیف user لازم است")
	return errors
