import io
import os
from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import ValidationError
from sqlalchemy import MetaData, select, func, create_engine, ForeignKeyConstraint
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from adapters.db.models.wallet import WalletAccount, WalletTransaction, WalletSetting, WalletPayout
from adapters.db.models.activity_log import ActivityLog
from adapters.db.models.system_setting import SystemSetting
from adapters.db.models.user import User
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.business import Business, BusinessType, BusinessField
from adapters.db.models.currency import Currency
from adapters.db.models.document import Document
from adapters.db.models.api_key import ApiKey
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import ApiError
from app.services import platform_admin_service as service
from adapters.api.v1.admin.platform import router, public_router, platform_admin, AdjustmentPayload, BrandingPayload


@pytest.fixture
def platform_db():
    dsn = os.getenv('SEPIDAR_TEST_DSN')
    if not dsn: pytest.skip('SEPIDAR_TEST_DSN is not set')
    assert make_url(dsn).database.endswith('_sepidar_test')
    engine = create_engine(dsn)
    models = (User, ApiKey, Currency, Business, Document, BankAccount, WalletAccount, WalletTransaction, WalletSetting, WalletPayout, ActivityLog, SystemSetting)
    metadata = MetaData()
    for model in models:
        model.__table__.to_metadata(metadata)
    for table in metadata.tables.values():
        for index, constraint in enumerate(list(table.constraints)):
            if isinstance(constraint, ForeignKeyConstraint) and any(f.target_fullname.split('.')[0] not in metadata.tables for f in constraint.elements):
                for fk in constraint.elements:
                    table.foreign_keys.discard(fk);fk.parent.foreign_keys.discard(fk)
                table.constraints.remove(constraint)
            elif isinstance(constraint, ForeignKeyConstraint) and constraint.name is None:
                constraint.name=f'platform_test_{table.name[:24]}_{index}'
    metadata.create_all(engine)
    try:
        with Session(engine, expire_on_commit=False, autoflush=False) as db:
            db.add(User(id=1,password_hash='test',referral_code='platform-test'))
            db.add(Currency(id=1,name='rial',title='ریال',symbol='ریال',code='IRR'))
            db.flush()
            db.add(Business(id=1,name='Platform test',owner_id=1,business_type=BusinessType.COMPANY,business_field=BusinessField.OTHER,default_currency_id=1))
            db.commit()
            yield db
    finally:
        metadata.drop_all(engine)
        engine.dispose()


def seed_wallet(db, balance='100'):
    db.add(WalletAccount(business_id=1, available_balance=Decimal(balance), pending_balance=Decimal('20'), status='active'))
    db.commit()


def test_adjustment_exact_idempotent_audited_and_no_pending_change(platform_db):
    db = platform_db; seed_wallet(db)
    args = dict(delta=Decimal('0.15'), expected_balance=Decimal('100'), request_id=uuid4(), reason='اصلاح آزمایشی اعتبار')
    first = service.adjust_wallet(db, 1, 1, **args); db.commit()
    second = service.adjust_wallet(db, 1, 1, **args); db.commit()
    assert first['transaction_id'] == second['transaction_id'] and second['replayed']
    wallet = db.scalars(select(WalletAccount)).one()
    assert wallet.available_balance == Decimal('100.15') and wallet.pending_balance == 20
    assert db.scalar(select(func.count()).select_from(WalletTransaction)) == 1
    assert db.scalar(select(func.count()).select_from(ActivityLog)) == 1
    assert service.audit_events(db)['items'][0]['after']['balance'] == '100.15'


def test_adjustment_rejects_stale_negative_and_reused_id(platform_db):
    db = platform_db; seed_wallet(db)
    args = dict(delta=Decimal('-10'), expected_balance=Decimal('100'), request_id=uuid4(), reason='اصلاح کسری اعتبار')
    service.adjust_wallet(db, 1, 1, **args); db.commit()
    for change in [dict(delta=Decimal('-11')), dict(request_id=uuid4()),
                   dict(request_id=uuid4(), expected_balance=Decimal('90'), delta=Decimal('-91'))]:
        with pytest.raises(ApiError): service.adjust_wallet(db, 1, 1, **(args | change))
        db.rollback()
    assert db.scalars(select(WalletAccount)).one().available_balance == 90
    assert db.scalar(select(func.count()).select_from(WalletTransaction)) == 1


def test_rollback_covers_wallet_transaction_and_audit(platform_db):
    db = platform_db; seed_wallet(db)
    service.adjust_wallet(db, 1, 1, delta=Decimal('25'), expected_balance=Decimal('100'), request_id=uuid4(), reason='آزمون بازگشت تراکنش')
    db.rollback()
    assert db.scalars(select(WalletAccount)).one().available_balance == 100
    assert db.scalar(select(func.count()).select_from(WalletTransaction)) == 0
    assert db.scalar(select(func.count()).select_from(ActivityLog)) == 0


def test_wallet_controls_tenant_bank_and_auto_validation(platform_db):
    db = platform_db; seed_wallet(db)
    db.add(Business(id=2, owner_id=1, name='Other', business_type=BusinessType.COMPANY, business_field=BusinessField.OTHER))
    db.flush(); db.add(BankAccount(id=99,business_id=2,name='Other bank',currency_id=1)); db.commit()
    data = dict(status='suspended',mode='auto',frequency='daily',threshold_amount=Decimal('10'),min_reserve=Decimal('3'),default_bank_account_id=99)
    with pytest.raises(ApiError): service.update_wallet_controls(db,1,1,data.copy(),'آزمون حساب دیگر')
    db.rollback()
    with pytest.raises(ApiError): service.update_wallet_controls(db,1,1,data | {'default_bank_account_id': None},'آزمون تسویه خودکار')
    db.rollback()
    result = service.update_wallet_controls(db,1,1,data | {'mode':'manual','default_bank_account_id':None},'توقف برداشت آزمایشی'); db.commit()
    assert result['status'] == 'suspended' and Decimal(result['settings']['min_reserve']) == 3
    assert len(result['transactions']) == 0
    from app.services.wallet_service import charge_wallet_for_service, credit_wallet_for_service
    with pytest.raises(ApiError) as exc: charge_wallet_for_service(db,1,Decimal('1'),description='test')
    assert exc.value.code == 'WALLET_SUSPENDED'
    db.rollback()
    credit_wallet_for_service(db,1,Decimal('1'),description='confirmed incoming credit'); db.commit()
    assert db.scalars(select(WalletAccount)).one().available_balance == 101


def test_branding_and_safe_logo_do_not_expose_settings(platform_db):
    db=platform_db
    db.add(SystemSetting(key='sms_api_key',value_string='secret-do-not-return')); db.commit()
    result=service.update_branding(db,1,{'name_fa':'آزمون','name_en':'Test','tagline':'Test tagline'},'آزمون نام پلتفرم'); db.commit()
    assert result['name_fa']=='آزمون' and 'secret' not in str(result)
    raw=io.BytesIO();Image.new('RGBA',(20,20),(10,20,30,0)).save(raw,format='PNG')
    result=service.update_logo(db,1,raw.getvalue(),'آزمون لوگوی پلتفرم'); db.commit()
    assert '/api/v1/platform/logo?v=' in result['logo_url']
    assert 'data' not in result
    assert db.scalar(select(func.count()).select_from(ActivityLog))==2
    with pytest.raises(ApiError): service.update_logo(db,1,b'<svg onload="evil"/>','آزمون فایل غیرمجاز')
    with pytest.raises(ApiError): service.update_logo(db,1,b'x'*(2*1024*1024+1),'آزمون فایل بزرگ')


def test_branding_rollback_and_advanced_atomic(platform_db):
    db=platform_db
    service.update_advanced(db,1,{'max_users':10},'آزمون محدودیت کاربر')
    assert service.advanced_settings(db)['max_users']==10
    db.rollback()
    assert service.advanced_settings(db)['max_users']==0
    assert db.scalar(select(func.count()).select_from(ActivityLog))==0
    with pytest.raises(ApiError): service.update_advanced(db,1,{'sms_api_key':'overwrite'},'آزمون فیلد مخفی')
    with pytest.raises(ApiError): service.update_advanced(db,1,{'default_timezone':'Invalid/Zone'},'آزمون منطقه زمانی')
    db.rollback()


def test_superadmin_required_not_email_or_system_settings():
    for permissions in [{},{'system_settings':True}]:
        ctx=AuthContext(User(id=1,email='baapar1101@gmail.com',app_permissions=permissions),1)
        with pytest.raises(ApiError) as exc:platform_admin(ctx)
        assert exc.value.status_code==403
    assert platform_admin(AuthContext(User(id=1,app_permissions={'superadmin':True}),1))


def test_platform_requires_live_direct_session_not_delegated_key(platform_db):
    from datetime import datetime,timedelta
    db=platform_db
    user=db.get(User,1);user.app_permissions={'superadmin':True}
    key=ApiKey(id=1,user_id=1,key_hash='test-only-key-hash',key_type='personal')
    db.add(key);db.commit()
    ctx=AuthContext(user,1,db=db)
    with pytest.raises(ApiError): platform_admin(ctx)
    key.key_type='session';db.commit()
    assert platform_admin(ctx) is ctx
    key.revoked_at=datetime.utcnow();db.commit()
    with pytest.raises(ApiError): platform_admin(ctx)
    key.revoked_at=None;key.expires_at=datetime.utcnow()-timedelta(seconds=1);db.commit()
    with pytest.raises(ApiError): platform_admin(ctx)


@pytest.mark.parametrize('delta',['0','NaN','Infinity','0.001','10000000000000000.00'])
def test_decimal_validation(delta):
    with pytest.raises(ValidationError): AdjustmentPayload(delta=delta,expected_balance='0',request_id=uuid4(),reason='valid reason')


def test_forbid_extra_fields_and_short_reason():
    with pytest.raises(ValidationError):BrandingPayload(name_fa='a',name_en='b',reason='x')
    with pytest.raises(ValidationError):BrandingPayload(name_fa='a',name_en='b',reason='valid reason',sms_api_key='x')


def test_api_roles_public_boundary_and_serialized_response(platform_db):
    db=platform_db;seed_wallet(db)
    app=FastAPI();app.include_router(router,prefix='/api/v1');app.include_router(public_router,prefix='/api/v1')
    app.dependency_overrides[get_db]=lambda:db
    app.dependency_overrides[get_current_user]=lambda:AuthContext(User(id=1,app_permissions={'system_settings':True}),1)
    client=TestClient(app)
    assert client.get('/api/v1/admin/platform/overview').status_code==403
    assert client.get('/api/v1/platform/branding').status_code==200
    assert client.get('/api/v1/platform/logo').status_code==404
    app.dependency_overrides[get_current_user]=lambda:AuthContext(User(id=1,app_permissions={'superadmin':True}),1)
    assert client.get('/api/v1/admin/platform/overview').json()['data']['wallets']==1
    body=client.get('/api/v1/admin/platform/wallets').json()['data']
    assert body['total']==1 and body['items'][0]['business_id']==1
    assert client.get('/api/v1/admin/platform/wallets/9999').status_code==404
    assert client.get('/api/v1/admin/platform/wallets/1').json()['data']['available_balance']=='100.00'
    payload={'delta':'10.00','expected_balance':'100.00','request_id':str(uuid4()),'reason':'اصلاح از مسیر API'}
    first=client.post('/api/v1/admin/platform/wallets/1/adjustments',json=payload)
    assert first.status_code==200 and first.json()['data']['available_balance']=='110.00'
    repeat=client.post('/api/v1/admin/platform/wallets/1/adjustments',json=payload)
    assert repeat.json()['data']['replayed']
    db.commit()
    assert client.get('/api/v1/admin/platform/audit').json()['data']['total']==1
    raw=io.BytesIO();Image.new('RGBA',(10,10)).save(raw,format='PNG')
    assert client.post('/api/v1/admin/platform/logo',files={'file':('logo.png',raw.getvalue(),'image/png')},data={'reason':'     '}).status_code==400
    assert client.post('/api/v1/admin/platform/logo',files={'file':('logo.png',raw.getvalue(),'image/png')},data={'reason':'آزمون ارسال لوگو'}).status_code==200
    assert client.get('/api/v1/platform/logo').headers['content-type']=='image/png'


def test_concurrent_balance_corrections_cannot_overwrite_each_other(platform_db):
    from concurrent.futures import ThreadPoolExecutor
    db=platform_db;seed_wallet(db)
    engine=db.get_bind()
    def correction(request_id):
        with Session(engine) as session:
            try:
                result=service.adjust_wallet(session,1,1,delta=Decimal('10'),expected_balance=Decimal('100'),request_id=request_id,reason='اصلاح همزمان آزمایشی')
                session.commit()
                return result
            except ApiError as exc:
                session.rollback()
                return exc.code
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(correction,[uuid4(),uuid4()]))
    assert sum(isinstance(r,dict) for r in results)==1 and 'BALANCE_CHANGED' in results
    db.expire_all()
    assert db.scalars(select(WalletAccount)).one().available_balance==110
    assert db.scalar(select(func.count()).select_from(WalletTransaction))==1


def test_concurrent_duplicate_request_is_applied_once(platform_db):
    from concurrent.futures import ThreadPoolExecutor
    db=platform_db;seed_wallet(db)
    engine=db.get_bind();request_id=uuid4()
    def correction(_):
        with Session(engine) as session:
            result=service.adjust_wallet(session,1,1,delta=Decimal('10'),expected_balance=Decimal('100'),request_id=request_id,reason='اصلاح تکراری آزمایشی')
            session.commit();return result
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(correction,[1,2]))
    assert {r['replayed'] for r in results}=={True,False}
    assert len({r['transaction_id'] for r in results})==1
