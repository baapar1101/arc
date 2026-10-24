# Sepidar core payroll: account mapping and owner approval

This change concerns core payroll, not the independent salary-tax adjustment
addon. Historical source tax tables are not enabled or treated as current law.

## Reviewed mapping (business 4955 / Sepidar01)

| Core setting | Source account | Code | Native account |
| --- | --- | --- | --- |
| Default payroll expense | 484, هزینه حقوق و دستمزد | 611023 | 518 |
| Employee salary tax payable | 224, مالیات حقوق پرداختنی کارکنان | 211128 | 389 |

Base salary account 611001 is a narrower account than the reviewed aggregate
payroll-expense default. Wages/insurance source-managed accounts and independent
addon mappings are unchanged. Explicit per-item accounts retain precedence.
The tax deduction resolver now respects the configured tax account before the
standard-chart fallback (the old branch bypassed that setting).

## Approval boundary

`extra_settings.financial_approval_policy.owner_only=true` opts this business into
an enforced policy. `require_approval=true`, `auto_post_on_finalize=false`.
Protected settings changes, approval, accrual posting and payment posting require
the current business owner, not merely a delegated `payroll.approve/post` right.
Superadmin is not a substitute for this owner approval in the service layer.

Finalization goes to `pending_approval`. Owner approval records actor/time and
does **not** issue a document. A separate explicit owner post operation is needed.
Preexisting `finalized`/`posted` status without an approval actor/time cannot bypass
the guard. Checks also run at direct accounting-service entry points, including
payments. Protected automatic posting is denied. Replacing the settings JSON or
trying to disable approval cannot remove the policy through the settings API.

Settings/run row locks use a consistent order. Accrual/payment link checks are
serialized on the run to prevent concurrent duplicate issuance. Draft edits,
Excel imports, cancellation and rejection use the same lock order as approval.
This does not introduce a global unique constraint on historical payroll links.
Source synchronization preserves locally reviewed expense/tax accounts and policy.

## Safe configuration and verification

Read-only by default, using the already authorized application environment:

```sh
PYTHONPATH=. .venv/bin/python scripts/configure_sepidar_payroll.py --business-id 4955
```

After review, `--apply` updates settings with an owner audit record; it never
creates a payroll run, draft journal, approval, document or payment. Repeating
the command with the expected state is a no-op. It validates the unique active
source leaf codes and native business ownership, and refuses if contracting or
fixed assets are enabled or assigned unreviewed finance accounts.

```sh
PYTHONPATH=. .venv/bin/python scripts/configure_sepidar_payroll.py --business-id 4955 --apply
PYTHONPATH=. .venv/bin/python scripts/verify_sepidar_posting_release.py --business-id 4955 --expect-no-postings --require-payroll-approval
```

## Acceptance tests

`tests/test_payroll_approval_safety.py` uses an explicit disposable PostgreSQL
`*_sepidar_test` database, never production. It checks pending approval, owner vs
delegated staff, direct-service and forged-state rejection, manual-only posting,
configured debit/tax credit and balance, sequential/concurrent duplicate requests,
payment restrictions, policy persistence, rejection/edit boundaries, HTTP paths
and source-sync preservation. Existing payroll, plugin-bridge and configured-addon
tests should be run alongside it. Policy/billing/cache integrations are stubbed
only in the disposable accounting fixture, not in production.

No production journal or payroll calculation is needed for these tests.

With `SEPIDAR_TEST_DSN` explicitly set to a disposable PostgreSQL database:

```sh
PYTHONPATH=. python scripts/run_payroll_safety_acceptance.py
```

The runner refuses the application database or a name without `_sepidar_test`.

### Verified on 2026-10-24

- Regression suite: 72 passed in 185.36 seconds on the disposable test database.
- Final expanded payroll safety suite: 30 passed in 105.67 seconds, including
  concurrent accrual/payment, delegated HTTP permissions, legacy optional-approval
  compatibility and explicit per-item tax-account precedence.
- These runs cover 76 distinct related tests (the 26 original safety cases were
  repeated in the final 30-case suite); no production payroll document was used.
