"""Review/apply payroll accounts and owner-only approval. Never issue a journal.

Default is read-only. --apply changes settings only, with an owner audit entry.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
from sqlalchemy import select, text

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adapters.db.session import SessionLocal
from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.payroll import PayrollSettings
from adapters.db.models.sepidar_live_import import SepidarImportSetting, SepidarImportRow, SepidarNativeMap
from adapters.db.models.advanced_plugins import AdvancedPluginSetting, AdvancedPluginPostingConfig
from app.services.payroll_service import update_settings


def reviewed_accounts(db, bid):
    source = db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id == bid)).one()
    assert source.database_name == 'Sepidar01', 'Only the reviewed current source is supported'
    rows = list(db.scalars(select(SepidarImportRow.payload).where(SepidarImportRow.business_id == bid,
        SepidarImportRow.source_schema == 'ACC', SepidarImportRow.source_table == 'Account', SepidarImportRow.is_deleted.is_(False))))
    chart = {r['AccountId']: r for r in rows}
    def full(r):
        parent = chart.get(r.get('ParentAccountRef'))
        return (full(parent) if parent and parent['Type'] else '') + r['Code']
    mapping = {int(m.source_id): m.target_id for m in db.scalars(select(SepidarNativeMap).where(
        SepidarNativeMap.business_id == bid, SepidarNativeMap.database_name == 'Sepidar01', SepidarNativeMap.source_table == 'ACC.Account'))}
    accounts = {}
    evidence = []
    for field, code in [('payroll_expense_account_id', '611023'), ('tax_payable_account_id', '211128')]:
        candidates = [r for r in rows if full(r) == code and r['Type'] == 3 and r.get('IsActive')]
        assert len(candidates) == 1, 'Missing/ambiguous reviewed source account: ' + code
        r = candidates[0]
        a = db.get(Account, mapping[r['AccountId']])
        assert a and a.business_id == bid, 'Missing business-owned native account'
        assert not db.scalars(select(Account.id).where(Account.parent_id == a.id)).first(), 'Posting account must be a leaf'
        accounts[field] = a.id
        evidence.append({'field': field, 'source_id': r['AccountId'], 'code': code, 'title': r['Title'], 'native_id': a.id})
    return accounts, evidence


def configure(bid, apply=False):
    with SessionLocal() as db:
        db.execute(text('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ' + ('' if apply else ', READ ONLY')))
        accounts, evidence = reviewed_accounts(db, bid)
        for code in ('contracting', 'fixed_assets'):
            s = db.scalars(select(AdvancedPluginSetting).where(AdvancedPluginSetting.business_id == bid, AdvancedPluginSetting.plugin_code == code)).one()
            f = db.scalars(select(AdvancedPluginPostingConfig).where(AdvancedPluginPostingConfig.business_id == bid, AdvancedPluginPostingConfig.plugin_code == code)).one()
            assert not s.enabled and not s.sync_enabled and not f.enabled and not f.accounts, 'Deferred plugin changed; investigate'
        row = db.scalars(select(PayrollSettings).where(PayrollSettings.business_id == bid)).one()
        before = {k: getattr(row, k) for k in (*accounts, 'require_approval', 'auto_post_on_finalize')}
        policy = {'owner_only': True, 'reason': 'Explicit owner approval required; no automatic posting'}
        expected = {**accounts, 'require_approval': True, 'auto_post_on_finalize': False}
        changed = any(before[k] != v for k, v in expected.items()) or (row.extra_settings or {}).get('financial_approval_policy') != policy
        if apply and changed:
            owner = db.get(Business, bid).owner_id
            extra = deepcopy(row.extra_settings or {})
            extra['financial_approval_policy'] = policy
            update_settings(db, bid, {**expected, 'extra_settings': extra}, owner)
        actual = {k: getattr(row, k) for k in expected}
        valid = actual == expected and (row.extra_settings or {}).get('financial_approval_policy') == policy
        return {'business_id': bid, 'mode': 'apply-settings-only' if apply else 'read-only', 'changed': bool(apply and changed),
                'accounts': evidence, 'before': before, 'actual': actual, 'configured': valid, 'owner_only': (row.extra_settings or {}).get('financial_approval_policy', {}).get('owner_only') is True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--business-id', type=int, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    print(json.dumps(configure(args.business_id, args.apply), ensure_ascii=False, default=str))
