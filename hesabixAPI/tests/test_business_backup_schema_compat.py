"""تست سازگاری اسکیمای بکاپ — مبتنی بر introspection، بدون جدول خاص."""
from __future__ import annotations

from app.services.business_backup_schema_compat import (
    ColumnMeta,
    ColumnFillStrategy,
    analyze_schema_diff,
    backup_columns_for_table,
    build_table_restore_plan,
    build_table_schemas_snapshot,
    parse_default_expression,
    resolve_column_plan,
    scan_backup_columns_from_rows,
    infer_value_from_type_category,
)


def _meta(
    *,
    name: str = "col",
    nullable: bool = True,
    has_server_default: bool = False,
    server_default_raw: str | None = None,
    has_client_default: bool = False,
    client_default=None,
    type_category: str = "str",
    is_autoincrement: bool = False,
) -> ColumnMeta:
    return ColumnMeta(
        name=name,
        nullable=nullable,
        has_server_default=has_server_default,
        has_client_default=has_client_default,
        server_default_raw=server_default_raw,
        client_default=client_default,
        type_name=type_category.upper(),
        type_category=type_category,
        is_autoincrement=is_autoincrement,
    )


def test_parse_postgresql_boolean_default():
    assert parse_default_expression("true", "bool") is True
    assert parse_default_expression("false::boolean", "bool") is False


def test_parse_postgresql_numeric_default():
    assert parse_default_expression("0", "int") == 0
    assert parse_default_expression("'{}'::jsonb", "json") == {}


def test_scan_union_columns_from_multiple_rows():
    rows = [{"id": 1, "a": 1}, {"id": 2, "b": 2}]
    assert scan_backup_columns_from_rows(rows) == {"id", "a", "b"}


def test_build_table_schemas_snapshot_unions_all_rows():
    tables_info = {"t1": {"columns": ["id", "x", "y"]}}
    data = {"t1": [{"id": 1, "x": 1}, {"id": 2, "y": 2}]}
    assert set(build_table_schemas_snapshot(tables_info, data)["t1"]) == {"id", "x", "y"}


def test_plan_omits_new_column_with_server_default():
    db_cols = ["id", "flag"]
    backup_cols = {"id"}
    meta = {
        "id": _meta(name="id", type_category="int"),
        "flag": _meta(
            name="flag",
            nullable=False,
            has_server_default=True,
            server_default_raw="true",
            type_category="bool",
        ),
    }
    plan = build_table_restore_plan("any_table", db_cols, backup_cols, [], meta)
    assert plan.insert_columns == ["id"]
    assert plan.column_plans["flag"].strategy == ColumnFillStrategy.OMIT_USE_DB_DEFAULT


def test_plan_omits_nullable_new_column():
    meta = {
        "id": _meta(name="id", type_category="int"),
        "expires_at": _meta(name="expires_at", nullable=True, type_category="datetime"),
    }
    plan = build_table_restore_plan("t", ["id", "expires_at"], {"id"}, [], meta)
    assert plan.insert_columns == ["id"]


def test_plan_fills_not_null_bool_via_type_inference():
    meta = {
        "id": _meta(name="id", type_category="int"),
        "active": _meta(name="active", nullable=False, type_category="bool"),
    }
    plan = build_table_restore_plan("t", ["id", "active"], {"id"}, [], meta)
    assert "active" in plan.insert_columns
    row = plan.enrich_row({"id": 1})
    assert row["active"] is False


def test_plan_uses_client_default_when_no_server_default():
    meta = {
        "id": _meta(name="id", type_category="int"),
        "score": _meta(
            name="score",
            nullable=False,
            has_client_default=True,
            client_default=10,
            type_category="int",
        ),
    }
    plan = build_table_restore_plan("t", ["id", "score"], {"id"}, [], meta)
    assert plan.column_plans["score"].strategy == ColumnFillStrategy.FILL_PARSED_DEFAULT
    assert plan.enrich_row({"id": 1})["score"] == 10


def test_plan_from_backup_includes_all_backed_columns():
    db_cols = ["id", "name", "extra"]
    backup_cols = {"id", "name"}
    meta = {c: _meta(name=c, type_category="int" if c == "id" else "str") for c in db_cols}
    plan = build_table_restore_plan("t", db_cols, backup_cols, [], meta)
    assert plan.insert_columns == ["id", "name"]


def test_analyze_schema_diff_reports_strategies():
    tables_info = {"items": {"columns": ["id", "new_flag"]}}
    metadata = {"table_schemas": {"items": ["id"]}}
    meta = {
        "id": _meta(name="id", type_category="int"),
        "new_flag": _meta(
            name="new_flag",
            nullable=False,
            has_server_default=True,
            server_default_raw="true",
            type_category="bool",
        ),
    }
    report = analyze_schema_diff(metadata, tables_info, ["items"], {"items": meta})
    assert "items" in report
    assert "new_flag" in report["items"]["added_in_db"]
    strategies = {x["column"]: x["strategy"] for x in report["items"]["added_column_strategies"]}
    assert strategies["new_flag"] == "omit_db_default"


def test_infer_bool_default_generic():
    assert infer_value_from_type_category("bool") is False


def test_backup_columns_merges_metadata_and_scanned_rows():
    meta = {"table_schemas": {"t": ["id"]}}
    rows = [{"id": 1, "extra_col": "x"}]
    assert backup_columns_for_table("t", meta, rows) == {"id", "extra_col"}
