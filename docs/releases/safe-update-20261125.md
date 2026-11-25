# Safe upstream integration — 2026-11-25

Integrates upstream `9868b75efa4ba26540a9d45099b5c882527081c6` into fork master `e4de639af330ba57190b83276222bc7589cd7d9e`. Preserves Sepidar import/projection/reconciliation, reviewed account mappings and approval controls, platform administration, Payamresan settings, glass UI and custom navigation.

## Verified release gates

- PostgreSQL backup restored to an isolated database; migration and repeat migration succeeded. Business 4955 financial/source hashes, wallet state, reviewed payroll configuration and approval policies stayed unchanged.
- Final Sepidar/native/operations/reconciliation/plugin/payroll suite: **139 passed** on a newly created disposable PostgreSQL database.
- Independent configured-posting, platform administration, SMS, repair, inventory transfer/count and AI regression groups: **100 passed**. Configured posting tests cover owner confirmation, balance, source deduplication and disabled modules. Five further goods/opening-stock checks passed.
- Flutter analysis: no errors. Flutter tests: **323 passed, 1 skipped**. Production web build succeeded with the production API URL.
- Candidate API health and unauthenticated business-access rejection passed against the restored copy. Import under the production service user (`www-data`) succeeded.
- Production Python package versions were preserved by cloning the existing runtime rather than upgrading dependencies. Test tooling was added to the candidate runtime only.

## Repairs made while integrating

- Unified the migration heads through an explicit merge revision.
- Kept the existing specialist fixed-assets route distinct from upstream's native route; the native permission gate honors an explicit disabled specialist policy.
- Removed duplicate ORM index declarations without removing physical indexes; registered the missing report-template model.
- Classified the new CRM AI mutation as a write requiring confirmation.
- Updated native projection fixtures for upstream lot/loyalty schemas; restored test module state after repair-shop mocks. Kept the Sepidar-managed stock predicate portable across SQL dialects.
- Resolved UI conflicts, regenerated localization, retained reviewed dependency resolution and adapted shared navigation labels.

## Test limitations and pre-existing issues

The entire test collection is **not green**. A diagnostic core run recorded 1,746 passes; subsequent isolated reruns resolved new stock failures, leaked mocks, duplicate indexes and disposable-database fixture collisions. **30 remaining failed cases were reproduced on pristine upstream using the same runtime and empty test data**, including SQLite/PostgreSQL JSONB incompatibilities, environment-dependent/old mocks, Windows DLL assumptions and PDF footer expectations. Exhaustive AI performance/discovery benchmarks are outside this release gate. Detailed private logs and the baseline comparison are retained with the deployment backup; no credentials are included in this report.

The existing Sepidar error `Source identity missing; reconciliation required: ACC.Voucher/5351` is retained and reported separately. This deployment does not approve or run source reconciliation.

## Deployment boundaries

- Never write to the source SQL Server.
- Keep `contracting` and `fixed_assets` disabled for the reviewed business.
- Do not approve, issue or reverse any accounting document. Preserve explicit owner/manager approval controls.
- Preserve original dirty checkouts and runtime configuration. Take a fresh database/frontend backup before switching the release; verify financial counters across migration and health after startup.
- Keep the previous code/frontend for rollback. A code rollback retains rehearsed additive schema rather than restoring an old database over live financial data.

This report records rehearsal evidence. The private deployment-state and final verification files establish whether production cutover completed.
