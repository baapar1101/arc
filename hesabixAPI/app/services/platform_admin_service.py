"""Curated platform controls, not a generic database editor.

Wallet corrections are internal credits/debits, never bank payouts. Every write
is audited in the same transaction; balances are exact decimals and locked.
"""
from __future__ import annotations

import base64
import hashlib
import io
import json
from decimal import Decimal

from PIL import Image, UnidentifiedImageError
from sqlalchemy import func, or_, select, text
from sqlalchemy.orm import Session

from adapters.db.models.activity_log import ActivityLog
from adapters.db.models.business import Business
from adapters.db.models.user import User
from adapters.db.models.wallet import WalletAccount, WalletTransaction, WalletSetting, WalletPayout
from adapters.db.models.system_setting import SystemSetting
from app.core.responses import ApiError
from app.services.system_settings_service import get_wallet_settings, get_system_configuration, set_system_configuration

BRANDING_KEY = 'platform_branding_v1'
LOGO_KEY = 'platform_logo_v1'
ADVANCED_FIELDS = {
    'max_file_size', 'max_users', 'mcp_oauth_session_days', 'default_timezone',
    'support_tickets_enabled', 'support_tickets_disabled_message',
    'legacy_api_import_enabled', 'legacy_api_import_disabled_message',
}


def audit(db, actor_id, action, entity, entity_id, before, after, reason, business_id=None):
    db.add(ActivityLog(user_id=actor_id, business_id=business_id, category='platform',
        action=action, entity_type=entity, entity_id=str(entity_id), description=reason,
        before_data=before, after_data=after))


def setting_json(db, key):
    row = db.scalars(select(SystemSetting).where(SystemSetting.key == key)).first()
    return json.loads(row.value_json) if row and row.value_json else {}


def save_json(db, key, data):
    row = db.scalars(select(SystemSetting).where(SystemSetting.key == key)).first()
    if row is None:
        row = SystemSetting(key=key)
        db.add(row)
    row.value_json = json.dumps(data, ensure_ascii=False)
    db.flush()


def branding(db):
    data = setting_json(db, BRANDING_KEY)
    logo = setting_json(db, LOGO_KEY)
    return {'name_fa': data.get('name_fa', ''), 'name_en': data.get('name_en', ''),
            'tagline': data.get('tagline', ''),
            'logo_url': '/api/v1/platform/logo?v=' + logo['sha256'] if logo else None}


def update_branding(db, actor_id, data, reason):
    db.execute(text('SELECT pg_advisory_xact_lock(5457233, 0)'))
    before = branding(db)
    save_json(db, BRANDING_KEY, data)
    set_system_configuration(db, commit=False, app_name=data['name_fa'])
    after = branding(db)
    audit(db, actor_id, 'update', 'platform_branding', 0, before, after, reason)
    return after


def update_logo(db, actor_id, raw, reason):
    if len(raw) > 2 * 1024 * 1024:
        raise ApiError('INVALID_LOGO', 'حجم لوگو حداکثر ۲ مگابایت است.', http_status=400)
    try:
        image = Image.open(io.BytesIO(raw))
        if image.format not in {'PNG', 'JPEG', 'WEBP'} or image.width * image.height > 4_000_000:
            raise ValueError('unsupported logo')
        image.load()
        image = image.convert('RGBA')
        image.thumbnail((512, 512))
        out = io.BytesIO()
        image.save(out, format='PNG', optimize=True)
        png = out.getvalue()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise ApiError('INVALID_LOGO', 'لوگوی PNG، JPEG یا WebP معتبر، حداکثر ۴ میلیون پیکسل انتخاب کنید.', http_status=400) from exc
    db.execute(text('SELECT pg_advisory_xact_lock(5457233, 0)'))
    before = branding(db)
    sha = hashlib.sha256(png).hexdigest()
    save_json(db, LOGO_KEY, {'sha256': sha, 'data': base64.b64encode(png).decode()})
    after = branding(db)
    audit(db, actor_id, 'update', 'platform_logo', 0, {'logo_url': before['logo_url']},
          {'logo_url': after['logo_url']}, reason)
    return after


def overview(db):
    wallet = db.execute(select(func.count(WalletAccount.id),
        func.coalesce(func.sum(WalletAccount.available_balance), 0),
        func.coalesce(func.sum(WalletAccount.pending_balance), 0))).one()
    return {'businesses': db.scalar(select(func.count()).select_from(Business).where(Business.deleted_at.is_(None))),
        'users': db.scalar(select(func.count()).select_from(User)), 'wallets': wallet[0],
        'available_balance': str(wallet[1]), 'pending_balance': str(wallet[2]),
        'suspended_wallets': db.scalar(select(func.count()).select_from(WalletAccount).where(WalletAccount.status == 'suspended')),
        'pending_payouts': db.scalar(select(func.count()).select_from(WalletPayout).where(WalletPayout.status.in_(['requested','approved','processing']))),
        'currency': get_wallet_settings(db)['wallet_base_currency_code']}


def wallet_dict(account):
    return {'available_balance': str(account.available_balance if account else 0),
            'pending_balance': str(account.pending_balance if account else 0),
            'status': account.status if account else 'not_created'}


def list_business_wallets(db, q='', skip=0, limit=25):
    query = select(Business, WalletAccount, User.email).outerjoin(WalletAccount, WalletAccount.business_id == Business.id).join(User, User.id == Business.owner_id).where(Business.deleted_at.is_(None))
    if q:
        filters = [Business.name.ilike('%' + q + '%'), User.email.ilike('%' + q + '%')]
        if q.isdecimal():
            filters.append(Business.id == int(q))
        query = query.where(or_(*filters))
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = [{'business_id': b.id, 'business_name': b.name, 'owner_email': email, **wallet_dict(w)}
             for b, w, email in db.execute(query.order_by(Business.id.desc()).offset(skip).limit(limit))]
    return {'items': items, 'total': total, 'skip': skip, 'limit': limit}


def require_business(db, business_id, lock=False):
    query = select(Business).where(Business.id == business_id, Business.deleted_at.is_(None))
    business = db.scalars(query.with_for_update() if lock else query).first()
    if business is None:
        raise ApiError('NOT_FOUND', 'کسب‌وکار یافت نشد.', http_status=404)
    return business


def wallet_detail(db, business_id):
    business = require_business(db, business_id)
    account = db.scalars(select(WalletAccount).where(WalletAccount.business_id == business_id)).first()
    setting = db.scalars(select(WalletSetting).where(WalletSetting.business_id == business_id)).first()
    from adapters.db.models.bank_account import BankAccount
    banks = db.scalars(select(BankAccount).where(BankAccount.business_id == business_id, BankAccount.is_active.is_(True))).all()
    transactions = db.scalars(select(WalletTransaction).where(WalletTransaction.business_id == business_id).order_by(WalletTransaction.id.desc()).limit(50)).all()
    return {'business_id': business_id, 'business_name': business.name, **wallet_dict(account),
        'settings': {'mode': setting.mode if setting else 'manual', 'frequency': setting.frequency if setting else None,
            'threshold_amount': str(setting.threshold_amount or 0) if setting else '0',
            'min_reserve': str(setting.min_reserve or 0) if setting else '0',
            'default_bank_account_id': setting.default_bank_account_id if setting else None},
        'bank_accounts': [{'id': bank.id, 'name': bank.name} for bank in banks],
        'transactions': [{'id': t.id, 'type': t.type, 'status': t.status, 'amount': str(t.amount),
            'description': t.description, 'document_id': t.document_id, 'created_at': t.created_at} for t in transactions]}


def adjust_wallet(db, business_id, actor_id, *, delta, expected_balance, request_id, reason):
    # Parent lock covers account creation and serializes idempotency checks.
    require_business(db, business_id, lock=True)
    reference = 'platform:' + str(request_id)
    existing = db.scalars(select(WalletTransaction).where(WalletTransaction.business_id == business_id,
        WalletTransaction.external_ref == reference)).first()
    if existing:
        metadata = json.loads(existing.extra_info)
        if Decimal(metadata['delta']) != delta or metadata['reason'] != reason or metadata['actor_id'] != actor_id:
            raise ApiError('REQUEST_CONFLICT', 'شناسه درخواست قبلاً برای عملیات دیگری استفاده شده است.', http_status=409)
        return {'transaction_id': existing.id, 'available_balance': metadata['after'], 'replayed': True}
    account = db.scalars(select(WalletAccount).where(WalletAccount.business_id == business_id).with_for_update().execution_options(populate_existing=True)).first()
    if account is None:
        account = WalletAccount(business_id=business_id, available_balance=Decimal('0'), pending_balance=Decimal('0'), status='active')
        db.add(account)
    before = Decimal(str(account.available_balance))
    if before != expected_balance:
        raise ApiError('BALANCE_CHANGED', 'موجودی تغییر کرده است؛ صفحه را تازه کنید.', http_status=409)
    after = before + delta
    if after < 0 or after >= Decimal('10000000000000000'):
        raise ApiError('INVALID_BALANCE', 'مانده نهایی نمی‌تواند منفی یا خارج از محدوده باشد.', http_status=400)
    account.available_balance = after
    metadata = {'actor_id': actor_id, 'reason': reason, 'delta': str(delta), 'before': str(before), 'after': str(after)}
    transaction = WalletTransaction(business_id=business_id, type='admin_credit' if delta > 0 else 'admin_debit',
        status='succeeded', amount=abs(delta), fee_amount=0, description=reason, external_ref=reference,
        extra_info=json.dumps(metadata))
    db.add(transaction)
    db.flush()
    audit(db, actor_id, 'adjust', 'platform_wallet', business_id, {'balance': str(before)},
          {'balance': str(after), 'delta': str(delta), 'transaction_id': transaction.id}, reason, business_id)
    return {'transaction_id': transaction.id, 'available_balance': str(after), 'replayed': False}


def update_wallet_controls(db, business_id, actor_id, data, reason):
    require_business(db, business_id, lock=True)
    before = wallet_detail(db, business_id)
    from adapters.db.models.bank_account import BankAccount
    bank_id = data.get('default_bank_account_id')
    if bank_id:
        bank = db.get(BankAccount, bank_id)
        if not bank or bank.business_id != business_id or not bank.is_active:
            raise ApiError('INVALID_BANK', 'حساب بانکی فعال همین کسب‌وکار را انتخاب کنید.', http_status=400)
    if data['mode'] == 'auto' and (not bank_id or not data.get('frequency') or data['threshold_amount'] <= 0):
        raise ApiError('INVALID_AUTO_SETTINGS', 'تسویه خودکار به حساب بانکی، دوره و حداقل مبلغ مثبت نیاز دارد.', http_status=400)
    account = db.scalars(select(WalletAccount).where(WalletAccount.business_id == business_id).with_for_update().execution_options(populate_existing=True)).first()
    if account is None:
        account = WalletAccount(business_id=business_id, available_balance=0, pending_balance=0)
        db.add(account)
    account.status = data.pop('status')
    setting = db.scalars(select(WalletSetting).where(WalletSetting.business_id == business_id)).first()
    if setting is None:
        setting = WalletSetting(business_id=business_id)
        db.add(setting)
    for key, value in data.items():
        setattr(setting, key, value)
    db.flush()
    after = wallet_detail(db, business_id)
    compact = lambda d: {'status': d['status'], 'settings': d['settings']}
    audit(db, actor_id, 'update', 'platform_wallet_controls', business_id, compact(before), compact(after), reason, business_id)
    return after


def advanced_settings(db):
    values = get_system_configuration(db)
    return {key: values[key] for key in ADVANCED_FIELDS}


def update_advanced(db, actor_id, data, reason):
    db.execute(text('SELECT pg_advisory_xact_lock(5457233, 0)'))
    before = advanced_settings(db)
    if not set(data).issubset(ADVANCED_FIELDS):
        raise ApiError('INVALID_SETTING', 'فیلد غیرمجاز.', http_status=400)
    set_system_configuration(db, commit=False, **data)
    after = advanced_settings(db)
    audit(db, actor_id, 'update', 'platform_advanced', 0, before, after, reason)
    return after


def audit_events(db, skip=0, limit=30):
    query = select(ActivityLog, User.email).outerjoin(User, User.id == ActivityLog.user_id).where(ActivityLog.category == 'platform')
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = [{'id': row.id, 'actor_email': email, 'action': row.action, 'entity': row.entity_type,
        'entity_id': row.entity_id, 'business_id': row.business_id, 'reason': row.description,
        'before': row.before_data, 'after': row.after_data, 'created_at': row.created_at}
        for row, email in db.execute(query.order_by(ActivityLog.id.desc()).offset(skip).limit(limit))]
    return {'items': items, 'total': total}
