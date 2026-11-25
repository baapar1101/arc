# Hesabix Product Variant integration gate — 2026-11-22

Status: **BLOCKED for bulk import**, safe upstream reconciliation continues in small, independently tested commits.

## Evidence from GitHub mirror

Reviewed `hesabix-upstream` at `76aa6f568e11e61338e149bbdb2dfa2268fe9b9c` and the integration branch `integration/resolve-hesabix-conflicts-20261102`. The mirror is a historical snapshot; the current upstream Git endpoint had failed to respond to the scheduled three-attempt fetch. Do not equate mirror contents with verified latest upstream.

The following foundational modules exist in the mirror but **not** in the integration branch:

| Kind | Missing integration file |
| --- | --- |
| Models | `hesabixAPI/adapters/db/models/product_variant.py` |
| Models | `hesabixAPI/adapters/db/models/product_variant_allocation.py` |
| Models | `hesabixAPI/adapters/db/models/inventory_variant_balance.py` |
| Services | `hesabixAPI/app/services/product_variant_service.py` |
| Services | `hesabixAPI/app/services/product_variant_enable_service.py` |
| Services | `hesabixAPI/app/services/variant_allocation_service.py` |
| Services | `hesabixAPI/app/services/variant_inventory_service.py` |
| Services | `hesabixAPI/app/services/invoice_unit_conversion_service.py` |

The upstream opening-inventory and warehouse-transfer fixes at `8e7ad3d396`, `762001dc9a`, and `2554d36fc8` call these modules and depend on their variant allocation semantics. Applying just their warehouse edits would fail imports or corrupt product/variant balances. This audit does **not** assert that these are the only missing prerequisites.

### Migration graph divergence

- Upstream `20261101_000002_product_variants_core.py` declares `down_revision = "20261101_000001_digipay_credit_plugin"`.
- Upstream `20261101_000003_product_variant_prices.py` depends on the core revision.
- Both the core migration and its `20261101_000001_digipay_credit_plugin` parent are absent from this integration branch.
- The integration branch currently contains `20261101_000001_sepidar_reconciliation`, with publication migrations continuing as `20261121_000001_dist_plan_locks` and `20261121_000002_plan_snapshot`.
- Therefore, copying the upstream migration files without reviewing and reconnecting their dependency chain is **not** safe. Do not rewrite or reset deployed Alembic history; preserve existing financial and Sepidar reconciliation records.

## Required staging / acceptance criteria

1. Inventory every upstream variant migration, referenced table, enum, FK and index, and compare it with the branch's current tables and Alembic heads. Plan additive revisions or a reviewed merge revision as appropriate.
2. Port the **complete** model and service dependency cluster, including units, allocations, stock readers, and cross-tenant validation. Keep variant behavior opt-in or guarded until fixtures and migrations pass.
3. Test baseline non-variant invoices, opening balances, warehouse receipts, transfers, adjustments, cancellations, returns and WooCommerce paths alongside variant-specific multi-line and main-unit scenarios.
4. Run migration upgrade/downgrade checks on disposable PostgreSQL and SQL Server 2022 instances; specifically check SQL Server multiple-cascade-path restrictions and identical business isolation.
5. Prove balanced accounting postings, no double-counted inventory, rollback atomicity, idempotent retries, and no loss of previously posted inventory movements.
6. Review Flutter/API contract changes separately. Preserve CRM task/project modules, custom logos and glass/transparency theme; do not copy upstream UI wholesale.
7. Keep the integration PR **DRAFT**, `master` and Vercel Production untouched until the full dependency and conflict review passes.

## Independently integrated upstream fixes

- `081c6ea585`: opening-balance post/unpost finalization now follows the caller's transaction; local CI `45011691959` passed five regression tests.
- `29f0f253fd`: voucher posting checks refreshed status under a transaction row lock. Our integration also adds a SQL Server `UPDLOCK, HOLDLOCK` path because MSSQL does not implement PostgreSQL's `SELECT FOR UPDATE`. SQLite regression CI `45013219264`: 2 passed, 1 SQL Server-only test skipped. SQL Server CI `45013208644`: 7 passed.
- Both are independent of the missing Product Variant schema. No master or production deployments have been performed.

## Explicitly unresolved

- The GitHub mirror is divergent from the integration history; upstream fetch availability is not verified.
- Distribution daily-plan publication with `locked=true` stays disabled pending complete mutation-path coverage.
- Release and Vercel production checks must occur only after the PR is no longer draft and all required validations pass.
