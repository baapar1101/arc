"""READ ONLY: verify the reviewed Sepidar deployment and emit comparison hashes.

No settings mutation, draft preparation, approval, reversal or source SQL writes.
This is an acceptance profile for the existing business, not an auto-seeding job.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
import sys

from sqlalchemy import select, text

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adapters.db.session import SessionLocal
from adapters.db.models.advanced_plugins import AdvancedPluginSetting, AdvancedPluginPostingConfig, AdvancedPluginPosting, AdvancedPluginRecord
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.sepidar_live_import import SepidarImportSetting, SepidarImportRun, SepidarNativeMap
from app.services.sepidar_native_service import fingerprint

SOURCE_ACCOUNTS = {
    'payroll_calendar_tax': {'expense': 197, 'payable': 224},
    'conditional_pricing': {'receivable': 117, 'revenue': 249, 'tax': 226},
    'inventory_trace_cost': {'cogs': 262, 'inventory': 383},
}
DEFERRED = ('contracting', 'fixed_assets')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify(bid, expect_no_postings=False):
    with SessionLocal() as db:
        db.execute(text('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY'))
        source = db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id == bid)).one()
        require(source.database_name == 'Sepidar01', 'Unexpected source database')
        require(source.enabled and source.native_enabled and source.operations_enabled and source.plugins_enabled, 'Source integration disabled')
        require(not source.last_error and not source.native_last_error, 'Source integration has an error')
        maps = {int(m.source_id): m.target_id for m in db.scalars(select(SepidarNativeMap).where(
            SepidarNativeMap.business_id == bid, SepidarNativeMap.database_name == 'Sepidar01', SepidarNativeMap.source_table == 'ACC.Account'))}
        settings = {r.plugin_code: r for r in db.scalars(select(AdvancedPluginSetting).where(AdvancedPluginSetting.business_id == bid))}
        configs = {r.plugin_code: r for r in db.scalars(select(AdvancedPluginPostingConfig).where(AdvancedPluginPostingConfig.business_id == bid))}
        for code, roles in SOURCE_ACCOUNTS.items():
            require(code in settings and code in configs, 'Missing configuration: ' + code)
            require(settings[code].enabled and settings[code].sync_enabled and configs[code].enabled, 'Configured plugin disabled: ' + code)
            require(configs[code].accounts == {role: maps[sid] for role, sid in roles.items()}, 'Reviewed mapping changed: ' + code)
        for code in DEFERRED:
            require(code in settings and code in configs, 'Missing deferred plugin configuration: ' + code)
            require(not settings[code].enabled and not settings[code].sync_enabled and not configs[code].enabled, 'Deferred plugin unexpectedly enabled: ' + code)
            require(not configs[code].accounts, 'Unreviewed accounts assigned: ' + code)
        postings = list(db.scalars(select(AdvancedPluginPosting).where(AdvancedPluginPosting.business_id == bid).order_by(AdvancedPluginPosting.id)))
        docs = list(db.scalars(select(Document).where(Document.business_id == bid).order_by(Document.id)))
        addon_docs = [d for d in docs if d.document_type in ('advanced_plugin_journal', 'advanced_plugin_reversal')]
        if expect_no_postings:
            require(not postings and not addon_docs, 'Expected no financial posting history; investigate, never delete it')
        lines = list(db.scalars(select(DocumentLine).join(Document).where(Document.business_id == bid)))
        records = list(db.scalars(select(AdvancedPluginRecord).where(AdvancedPluginRecord.business_id == bid).order_by(AdvancedPluginRecord.id)))
        wallet = list(map(tuple, db.execute(text('SELECT id,available_balance,pending_balance,status FROM wallet_accounts WHERE business_id=:bid ORDER BY id'), {'bid': bid})))
        wallet_tx = db.scalar(text('SELECT count(*) FROM wallet_transactions WHERE business_id=:bid'), {'bid': bid})
        run = db.scalars(select(SepidarImportRun).where(SepidarImportRun.business_id == bid, SepidarImportRun.status == 'success').order_by(SepidarImportRun.id.desc())).first()
        require(run is not None, 'No successful source synchronization')
        return {
            'verified_at': datetime.now(timezone.utc).isoformat(), 'business_id': bid,
            'policy': 'Explicit permitted-manager confirmation required; this verifier never issues documents.',
            'settings': {c: {'enabled': settings[c].enabled, 'sync_enabled': settings[c].sync_enabled,
                              'finance_enabled': configs[c].enabled, 'accounts': configs[c].accounts,
                              'settings_revision': settings[c].revision, 'finance_revision': configs[c].revision}
                         for c in (*SOURCE_ACCOUNTS, *DEFERRED)},
            'invariants': {
                'ledger_lines': len(lines),
                'ledger_hash': fingerprint(sorted((l.id,l.document_id,l.account_id,l.person_id,l.debit,l.credit) for l in lines)),
                'document_count': len(docs),
                'documents_hash': fingerprint([(d.id,d.code,d.document_type,d.updated_at) for d in docs]),
                'wallet_hash': fingerprint([wallet,wallet_tx]),
                'record_count': len(records),
                'records_hash': fingerprint([(r.id,r.plugin_code,r.identity,r.revision,r.source_hash,r.source_deleted) for r in records]),
                'postings': len(postings), 'addon_documents': len(addon_docs),
            },
            'latest_successful_sync': {k: getattr(run,k) for k in ('id','finished_at','tables_completed','tables_total','rows_changed')},
        }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--business-id', type=int, required=True)
    parser.add_argument('--expect-no-postings', action='store_true', help='Fail, never mutate, if any real financial posting already exists.')
    args = parser.parse_args()
    print(json.dumps(verify(args.business_id, args.expect_no_postings), ensure_ascii=False, default=str), flush=True)
