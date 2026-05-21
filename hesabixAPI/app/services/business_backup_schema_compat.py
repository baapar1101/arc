"""
سازگاری اسکیمای بکاپ کسب‌وکار — مبتنی بر introspection دیتابیس، بدون وابستگی به جدول خاص.

- مقایسه snapshot بکاپ با اسکیمای فعلی (information_schema + SQLAlchemy inspector)
- تعیین استراتژی هر ستون: از بکاپ / حذف از INSERT (default DB) / مقدار استنتاجی از نوع
- اعتبارسنجی و sanitize ردیف‌ها قبل از INSERT
"""
from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, Iterable, List, Optional, Set

from sqlalchemy import text as sa_text

logger = logging.getLogger(__name__)

_SENTINEL_NO_VALUE = object()
_SENTINEL_OMIT = object()

# حداکثر ردیف برای اسکن union ستون‌های بکاپ (کارایی)
_BACKUP_COLUMN_SCAN_LIMIT = 200


class ColumnFillStrategy(str, Enum):
    FROM_BACKUP = "from_backup"
    OMIT_USE_DB_DEFAULT = "omit_use_db_default"
    FILL_PARSED_DEFAULT = "fill_parsed_default"
    FILL_TYPE_INFERENCE = "fill_type_inference"
    UNSUPPORTED = "unsupported"


@dataclass(frozen=True)
class ColumnMeta:
    name: str
    nullable: bool
    has_server_default: bool
    has_client_default: bool
    server_default_raw: Optional[str]
    client_default: Any
    type_name: str
    type_category: str
    is_autoincrement: bool


@dataclass
class ColumnPlan:
    name: str
    strategy: ColumnFillStrategy
    include_in_insert: bool
    fill_value: Any = None


@dataclass
class TableRestorePlan:
    table: str
    insert_columns: List[str]
    backup_columns: Set[str]
    column_meta: Dict[str, ColumnMeta]
    column_plans: Dict[str, ColumnPlan]
    warnings: List[str] = field(default_factory=list)

    def enrich_row(self, rec: Dict[str, Any]) -> Dict[str, Any]:
        out = sanitize_backup_row(rec, self.column_meta)
        for col in self.insert_columns:
            if col in out:
                continue
            plan = self.column_plans.get(col)
            if not plan or plan.strategy not in (
                ColumnFillStrategy.FILL_PARSED_DEFAULT,
                ColumnFillStrategy.FILL_TYPE_INFERENCE,
            ):
                continue
            if plan.fill_value is not _SENTINEL_NO_VALUE:
                out[col] = plan.fill_value
        return out


def _type_name(col: Dict[str, Any]) -> str:
    typ = col.get("type")
    if typ is None:
        return ""
    return (type(typ).__name__ + " " + str(typ)).upper()


def _categorize_type(type_name: str) -> str:
    tn = type_name.upper()
    if "BOOL" in tn:
        return "bool"
    if "JSON" in tn:
        return "json"
    if "UUID" in tn:
        return "uuid"
    if "DATETIME" in tn or "TIMESTAMP" in tn or "DATE" in tn:
        return "datetime"
    if "ENUM" in tn:
        return "enum"
    if any(x in tn for x in ("INT", "SMALLINT", "BIGINT", "SERIAL")):
        return "int"
    if any(x in tn for x in ("NUMERIC", "DECIMAL", "FLOAT", "DOUBLE", "REAL")):
        return "numeric"
    if any(x in tn for x in ("CHAR", "TEXT", "STRING", "CITEXT", "VARCHAR")):
        return "str"
    if "BYTEA" in tn or "BLOB" in tn or "BINARY" in tn:
        return "bytes"
    return "other"


def _normalize_server_default_text(sd: Any) -> Optional[str]:
    if sd is None:
        return None
    text = str(sd).strip()
    if not text or text.upper() in ("NONE", "NULL"):
        return None
    return text


def _column_has_server_default(col: Dict[str, Any]) -> bool:
    return _normalize_server_default_text(col.get("server_default")) is not None


def _column_has_client_default(col: Dict[str, Any]) -> bool:
    return col.get("default") is not None


def parse_default_expression(raw: Optional[str], type_category: str = "other") -> Any:
    """
    تبدیل عبارت default بازتاب‌شده از PostgreSQL به مقدار Python.
    در صورت عدم اطمینان _SENTINEL_OMIT برمی‌گردد (ستون از INSERT حذف شود).
    """
    if raw is None:
        return _SENTINEL_NO_VALUE
    text = raw.strip()
    upper = text.upper()

    if upper in ("TRUE", "FALSE"):
        return upper == "TRUE"
    if upper == "NULL":
        return None

    # nextval، sequence، now() — به DB واگذار می‌شود
    if "NEXTVAL(" in upper or "GEN_RANDOM_UUID(" in upper or "UUID_GENERATE" in upper:
        return _SENTINEL_OMIT
    if "NOW()" in upper or "CURRENT_TIMESTAMP" in upper or "CURRENT_DATE" in upper:
        return _SENTINEL_OMIT

    # 'literal'::type
    m = re.match(r"^'((?:''|[^'])*)'(::\w+)?$", text)
    if m:
        inner = m.group(1).replace("''", "'")
        cast = (m.group(2) or "").lower()
        if type_category == "json" or "json" in cast:
            try:
                return json.loads(inner)
            except json.JSONDecodeError:
                return inner if inner else {}
        return inner

    # عددی ساده
    if re.match(r"^-?\d+$", text):
        return int(text)
    if re.match(r"^-?\d+\.\d+$", text):
        return float(text)

    # boolean cast
    if "::BOOLEAN" in upper or "::BOOL" in upper:
        if "TRUE" in upper:
            return True
        if "FALSE" in upper:
            return False

    # json
    if type_category == "json" or "::JSON" in upper:
        if text in ("{}", "'{}'"):
            return {}
        if text in ("[]", "'[]'"):
            return []
        try:
            if text.startswith("'") and text.endswith("'"):
                text = text[1:-1]
            return json.loads(text)
        except json.JSONDecodeError:
            return _SENTINEL_OMIT

    # بدون کوتیشن
    if text.isdigit():
        return int(text)

    return _SENTINEL_OMIT


def infer_value_from_type_category(category: str) -> Any:
    if category == "bool":
        return False
    if category == "int":
        return 0
    if category == "numeric":
        return 0
    if category == "json":
        return {}
    if category == "str":
        return ""
    if category == "enum":
        return _SENTINEL_NO_VALUE
    if category == "uuid":
        return _SENTINEL_NO_VALUE
    if category == "datetime":
        return _SENTINEL_NO_VALUE
    if category == "bytes":
        return _SENTINEL_NO_VALUE
    return _SENTINEL_NO_VALUE


def load_table_column_meta(schema_inspector, table: str, conn: Any = None) -> Dict[str, ColumnMeta]:
    """بارگذاری متادیتای ستون از inspector؛ در صورت وجود conn تکمیل از information_schema."""
    out: Dict[str, ColumnMeta] = {}
    try:
        for col in schema_inspector.get_columns(table):
            name = col["name"]
            tn = _type_name(col)
            cat = _categorize_type(tn)
            sd_raw = _normalize_server_default_text(col.get("server_default"))
            out[name] = ColumnMeta(
                name=name,
                nullable=bool(col.get("nullable", True)),
                has_server_default=sd_raw is not None,
                has_client_default=_column_has_client_default(col),
                server_default_raw=sd_raw,
                client_default=col.get("default"),
                type_name=tn,
                type_category=cat,
                is_autoincrement=bool(col.get("autoincrement", False)),
            )
    except Exception as e:
        logger.warning("load_table_column_meta inspector failed table=%s: %s", table, e)

    if conn is not None:
        _merge_information_schema_defaults(conn, table, out)
    return out


def _merge_information_schema_defaults(conn: Any, table: str, meta: Dict[str, ColumnMeta]) -> None:
    """تکمیل/اصلاح default و nullable از information_schema (دقیق‌تر برای PostgreSQL)."""
    try:
        rows = conn.execute(
            sa_text(
                """
                SELECT column_name, is_nullable, column_default, data_type, udt_name
                FROM information_schema.columns
                WHERE table_schema = current_schema()
                  AND table_name = :t
                ORDER BY ordinal_position
                """
            ),
            {"t": table},
        ).fetchall()
    except Exception as e:
        logger.debug("information_schema read failed table=%s: %s", table, e)
        return

    for row in rows:
        name = row[0]
        is_nullable = str(row[1]).upper() == "YES"
        col_default = row[2]
        data_type = (row[3] or "") + " " + (row[4] or "")
        cat = _categorize_type(data_type)
        sd_raw = _normalize_server_default_text(col_default)
        existing = meta.get(name)
        if existing:
            meta[name] = ColumnMeta(
                name=name,
                nullable=is_nullable,
                has_server_default=sd_raw is not None or existing.has_server_default,
                has_client_default=existing.has_client_default,
                server_default_raw=sd_raw or existing.server_default_raw,
                client_default=existing.client_default,
                type_name=existing.type_name or data_type,
                type_category=existing.type_category or cat,
                is_autoincrement=existing.is_autoincrement,
            )
        else:
            meta[name] = ColumnMeta(
                name=name,
                nullable=is_nullable,
                has_server_default=sd_raw is not None,
                has_client_default=False,
                server_default_raw=sd_raw,
                client_default=None,
                type_name=data_type,
                type_category=cat,
                is_autoincrement=False,
            )


def resolve_column_plan(
    column: str,
    *,
    in_backup: bool,
    meta: Optional[ColumnMeta],
) -> ColumnPlan:
    if in_backup:
        return ColumnPlan(
            name=column,
            strategy=ColumnFillStrategy.FROM_BACKUP,
            include_in_insert=True,
        )

    if meta is None:
        return ColumnPlan(
            name=column,
            strategy=ColumnFillStrategy.UNSUPPORTED,
            include_in_insert=False,
        )

    if meta.is_autoincrement:
        return ColumnPlan(
            name=column,
            strategy=ColumnFillStrategy.OMIT_USE_DB_DEFAULT,
            include_in_insert=False,
        )

    # nullable یا default سطح دیتابیس → ستون در INSERT نمی‌آید
    if meta.nullable or meta.has_server_default:
        return ColumnPlan(
            name=column,
            strategy=ColumnFillStrategy.OMIT_USE_DB_DEFAULT,
            include_in_insert=False,
        )

    if meta.has_client_default and meta.client_default is not None:
        return ColumnPlan(
            name=column,
            strategy=ColumnFillStrategy.FILL_PARSED_DEFAULT,
            include_in_insert=True,
            fill_value=meta.client_default,
        )

    inferred = infer_value_from_type_category(meta.type_category)
    if inferred is not _SENTINEL_NO_VALUE:
        return ColumnPlan(
            name=column,
            strategy=ColumnFillStrategy.FILL_TYPE_INFERENCE,
            include_in_insert=True,
            fill_value=inferred,
        )

    return ColumnPlan(
        name=column,
        strategy=ColumnFillStrategy.UNSUPPORTED,
        include_in_insert=False,
    )


def build_table_restore_plan(
    table: str,
    db_columns: List[str],
    backup_columns: Set[str],
    pk_omit: Iterable[str],
    column_meta: Dict[str, ColumnMeta],
) -> TableRestorePlan:
    omit = set(pk_omit)
    plans: Dict[str, ColumnPlan] = {}
    insert_cols: List[str] = []
    warnings: List[str] = []

    for c in db_columns:
        if c in omit:
            continue
        plan = resolve_column_plan(
            c,
            in_backup=c in backup_columns,
            meta=column_meta.get(c),
        )
        plans[c] = plan
        if plan.include_in_insert:
            insert_cols.append(c)
        elif plan.strategy == ColumnFillStrategy.UNSUPPORTED:
            warnings.append(
                f"{table}.{c}: ستون اجباری بدون default شناخته‌شده و در بکاپ نیست"
            )

    removed_from_db = backup_columns - set(column_meta.keys())
    if removed_from_db:
        warnings.append(
            f"{table}: ستون‌های حذف‌شده از اسکیما (نادیده گرفته می‌شوند): "
            + ", ".join(sorted(removed_from_db)[:15])
        )

    return TableRestorePlan(
        table=table,
        insert_columns=insert_cols,
        backup_columns=backup_columns,
        column_meta=column_meta,
        column_plans=plans,
        warnings=warnings,
    )


def sanitize_backup_row(rec: Dict[str, Any], column_meta: Dict[str, ColumnMeta]) -> Dict[str, Any]:
    valid = set(column_meta.keys())
    return {k: v for k, v in rec.items() if k in valid}


def validate_row_for_insert(
    table: str,
    rec: Dict[str, Any],
    plan: TableRestorePlan,
) -> List[str]:
    """بررسی ردیف نسبت به اسکیما؛ لیست هشدار (خالی = OK)."""
    issues: List[str] = []
    for col in plan.insert_columns:
        meta = plan.column_meta.get(col)
        if meta is None:
            continue
        val = rec.get(col)
        if val is None and not meta.nullable:
            cp = plan.column_plans.get(col)
            if cp and cp.strategy == ColumnFillStrategy.FROM_BACKUP:
                issues.append(f"{table}.{col}: مقدار NULL در بکاپ برای ستون NOT NULL")
    extra = set(rec.keys()) - set(plan.column_meta.keys())
    if extra:
        issues.append(f"{table}: کلیدهای خارج از اسکیما: {', '.join(sorted(extra)[:10])}")
    return issues


def scan_backup_columns_from_rows(rows: Iterable[Dict[str, Any]]) -> Set[str]:
    cols: Set[str] = set()
    for i, row in enumerate(rows):
        if i >= _BACKUP_COLUMN_SCAN_LIMIT:
            break
        cols.update(row.keys())
    return cols


def iter_jsonl_rows(zf: Any, table: str, limit: int = _BACKUP_COLUMN_SCAN_LIMIT) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    try:
        with zf.open(f"tables/{table}.jsonl", "r") as f:
            for raw in f:
                if not raw:
                    continue
                rows.append(json.loads(raw.decode("utf-8")))
                if len(rows) >= limit:
                    break
    except KeyError:
        pass
    return rows


def backup_columns_for_table(
    table: str,
    metadata: Dict[str, Any],
    scanned_rows: Optional[List[Dict[str, Any]]] = None,
) -> Set[str]:
    schemas = metadata.get("table_schemas") or {}
    if table in schemas and schemas[table]:
        backed = set(schemas[table])
    else:
        backed = set()
    if scanned_rows:
        backed |= scan_backup_columns_from_rows(scanned_rows)
    return backed


def build_table_schemas_snapshot(
    tables_info: Dict[str, Dict[str, Any]],
    tables_data: Dict[str, List[Dict[str, Any]]],
) -> Dict[str, List[str]]:
    schemas: Dict[str, List[str]] = {}
    for table_name, rows in tables_data.items():
        if rows:
            schemas[table_name] = sorted(scan_backup_columns_from_rows(rows))
        elif table_name in tables_info:
            schemas[table_name] = list(tables_info[table_name]["columns"])
        else:
            schemas[table_name] = []
    return schemas


def analyze_schema_diff(
    metadata: Dict[str, Any],
    tables_info: Dict[str, Dict[str, Any]],
    target_tables: Iterable[str],
    column_meta_cache: Dict[str, Dict[str, ColumnMeta]],
) -> Dict[str, Dict[str, Any]]:
    """
    مقایسه table_schemas بکاپ با DB فعلی و دسته‌بندی ستون‌های جدید.
    """
    backup_schemas = metadata.get("table_schemas") or {}
    report: Dict[str, Dict[str, Any]] = {}
    for table in target_tables:
        current_cols = tables_info.get(table, {}).get("columns", [])
        current = set(current_cols)
        backed = set(backup_schemas.get(table, []))
        added = sorted(current - backed)
        removed = sorted(backed - current)
        if not added and not removed:
            continue
        meta = column_meta_cache.get(table) or {}
        added_detail: List[Dict[str, str]] = []
        for col in added:
            m = meta.get(col)
            if m is None:
                added_detail.append({"column": col, "strategy": "unknown"})
            elif m.nullable or m.has_server_default:
                added_detail.append({"column": col, "strategy": "omit_db_default"})
            else:
                cp = resolve_column_plan(col, in_backup=False, meta=m)
                added_detail.append({"column": col, "strategy": cp.strategy.value})
        report[table] = {
            "added_in_db": added,
            "removed_from_db": removed,
            "added_column_strategies": added_detail,
        }
        logger.info(
            "backup_schema_diff table=%s added=%s removed=%s",
            table,
            added[:15],
            removed[:15],
        )
    return report


def log_restore_plan_warnings(plan: TableRestorePlan) -> None:
    for w in plan.warnings:
        logger.warning("backup_restore: %s", w)


# --- API سازگار با نسخه قبل (delegate به plan) ---


def resolve_table_insert_columns(
    table: str,
    db_columns: List[str],
    backup_columns: Set[str],
    pk_omit: Iterable[str],
    column_meta: Dict[str, ColumnMeta],
) -> List[str]:
    plan = build_table_restore_plan(table, db_columns, backup_columns, pk_omit, column_meta)
    return plan.insert_columns


def enrich_restore_record(
    table: str,
    rec: Dict[str, Any],
    insert_col_list: List[str],
    backup_columns: Set[str],
    column_meta: Dict[str, ColumnMeta],
) -> Dict[str, Any]:
    plan = TableRestorePlan(
        table=table,
        insert_columns=insert_col_list,
        backup_columns=backup_columns,
        column_meta=column_meta,
        column_plans={
            c: resolve_column_plan(c, in_backup=c in backup_columns, meta=column_meta.get(c))
            for c in insert_col_list
        },
    )
    return plan.enrich_row(rec)


def log_schema_diff(
    metadata: Dict[str, Any],
    tables_info: Dict[str, Dict[str, Any]],
    target_tables: Iterable[str],
    column_meta_cache: Optional[Dict[str, Dict[str, ColumnMeta]]] = None,
) -> Dict[str, Dict[str, Any]]:
    return analyze_schema_diff(
        metadata,
        tables_info,
        target_tables,
        column_meta_cache or {},
    )


# نام‌های قدیمی تست‌ها
def infer_column_default(meta: Optional[ColumnMeta]) -> Any:
    if meta is None:
        return _SENTINEL_NO_VALUE
    if meta.nullable or meta.has_server_default:
        return _SENTINEL_NO_VALUE
    return infer_value_from_type_category(meta.type_category)


def resolve_missing_column_value(
    table: str,
    column: str,
    meta: Optional[ColumnMeta],
) -> Any:
    plan = resolve_column_plan(column, in_backup=False, meta=meta)
    if plan.strategy == ColumnFillStrategy.FILL_PARSED_DEFAULT:
        return plan.fill_value
    if plan.strategy == ColumnFillStrategy.FILL_TYPE_INFERENCE:
        return plan.fill_value
    return _SENTINEL_NO_VALUE
