# Reviewed Sepidar reconciliation

Ordinary live conversion stops if an already mapped source identity disappears.
Do not delete mappings or run `delete_invoice`: local deletion can remove cash,
warehouse and loyalty records that need independent review.

After the owner confirms the source deletions were intentional, use
`scripts/reconcile_sepidar_source.py --business-id BID` to obtain the current
plan. The CLI acquires the same advisory business lock as the importer. A full,
finished snapshot is required. To apply an already-authorized plan, pass
`--apply --plan-hash HASH --approved-by OWNER_ID --reason REASON`. Any changed
source content or affected native row invalidates the plan. The owner ID must
match the destination business owner. This is an operator CLI, not a scheduler
or an automatic approval endpoint.

Application is one transaction with downstream projection. It archives complete
before-images in `sepidar_reconciliation_audits`, retires the original mappings,
retains document identities, removes archived documents' active financial and
invoice rows, and cancels affected warehouse documents. Archived document
headers remain source-managed with type `sepidar_archived`; invoice DTOs return
410 for direct access. Loyalty uses the existing reversal/delta rules and keeps
its ledger history. Live cash allocations, unrelated plugin references, and
ambiguous financial aliases block reconciliation. No generated or reversal GL
documents and no external sends are invoked.

A surviving invoice whose original source voucher was replaced keeps its native
ID. A later initial posting in Sepidar also attaches to the existing empty native
invoice or receipt, provided the source voucher reference is unique, date/year/
currency agree and there is no prior active financial alias or ledger. A new
unreviewed source deletion still blocks; a retired identity that reappears also
requires review. Repeating the same approved plan is a no-op.

Reviewed replacements also cover `RPA.ReceiptHeader` and `RPA.PaymentHeader`:
retain the original cash document identity and rebuild its ledger from the new
source voucher. Existing settlement allocations are retained and refreshed by
the normal source projection. Source header and voucher date/year and base
currency must agree; ambiguous aliases or allocations to deleted invoices still
require separate review. A replacement must never archive a surviving receipt
or payment merely because its former voucher disappeared.

In mixed income/expense sections, Sepidar `BalanceType=3` means "Don't Care"
(`Sepidar/SqlScripts/StaticData/AccountManagement_Lookups.sql`). A neutral child
inherits the nearest GL/SL ancestor's explicitly declared normal side for report
classification. The mixed group root and live balances never decide it; missing
or ambiguous GL/SL classification still stops conversion for review.
