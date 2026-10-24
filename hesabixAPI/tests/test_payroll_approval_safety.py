"""Real disposable-PostgreSQL acceptance. No production DSN is accepted."""
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from decimal import Decimal
from threading import Barrier
import pytest
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.user import User
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.payroll import (PayrollSettings, PayrollDepartment, PayrollItemCategory, PayrollItemDefinition,
    PayrollEmployee, PayrollPeriod, PayrollRun, PayrollRunLine, PayrollRunLineItem, PayrollDocumentLink, PayrollAuditLog)
from app.core.responses import ApiError
from app.services import payroll_accounting as accounting, payroll_service as svc
from tests.test_sepidar_native_projection import native_db
from tests.test_sepidar_plugin_bridge import license, source, edit
from app.services.sepidar_native_service import project_native

MODELS = (BusinessPermission, PayrollDepartment, PayrollItemCategory, PayrollItemDefinition, PayrollEmployee, PayrollPeriod,
          PayrollRun, PayrollRunLine, PayrollRunLineItem, PayrollDocumentLink, PayrollAuditLog)


@pytest.fixture
def payroll_db(native_db, monkeypatch):
    db = native_db
    for model in MODELS: model.__table__.create(db.get_bind(), checkfirst=True)
    license(db, 'payroll')
    db.add(User(id=2, password_hash='test', referral_code='staff-test'))
    db.flush()
    db.add(BusinessPermission(business_id=1,user_id=2,business_permissions={'payroll':{'view':True,'operate':True,'approve':True,'post':True,'manage':True}}))
    for aid, code in [(518, '611023'), (389, '211128'), (369, '211101'), (300, '111005')]:
        db.add(Account(id=aid, business_id=1, code=code, name=code, account_type='detail'))
    db.add(FiscalYear(id=1, business_id=1, title='1405', start_date=date(2026,3,21), end_date=date(2027,3,20), is_last=True))
    db.add(PayrollSettings(business_id=1, default_currency_id=1, payroll_expense_account_id=518,
        tax_payable_account_id=389, wages_payable_account_id=369, require_approval=True, auto_post_on_finalize=False,
        extra_settings={'financial_approval_policy': {'owner_only':True}}))
    db.add(Person(id=1,business_id=1,alias_name='Test',code=1,person_types='["employee"]'))
    db.flush()
    db.add(PayrollEmployee(id=1,business_id=1,person_id=1,employee_code='T1'))
    db.add_all([PayrollItemDefinition(id=1,business_id=1,code='base',name='Base',item_kind='earning'),
                PayrollItemDefinition(id=2,business_id=1,code='tax',name='Tax',item_kind='deduction')])
    run=PayrollRun(id=1,business_id=1,code='PAY-T1',title='Test',run_date=date(2026,10,24),status='draft',gross_total=1000,deduction_total=100,net_total=900)
    db.add(run);db.flush()
    db.add(PayrollRunLine(id=1,run_id=1,employee_id=1,person_id=1,gross_amount=1000,deduction_amount=100,net_amount=900))
    db.flush()
    db.add_all([PayrollRunLineItem(run_line_id=1,item_definition_id=1,amount=1000),PayrollRunLineItem(run_line_id=1,item_definition_id=2,amount=100)])
    db.commit()
    monkeypatch.setattr(accounting,'ensure_document_policy_allows_creation',lambda *a,**k:None)
    monkeypatch.setattr(accounting,'process_document_usage_for_document',lambda *a,**k:None)
    monkeypatch.setattr(accounting,'invalidate_documents_cache',lambda *a,**k:None)
    monkeypatch.setattr(accounting,'generate_document_code',lambda db,*a: 'TEST-'+str(db.scalar(select(func.count()).select_from(Document))+1))
    try: yield db
    finally:
        db.rollback()
        for model in reversed(MODELS): model.__table__.drop(db.get_bind(), checkfirst=True)


def countdocs(db): return db.scalar(select(func.count()).select_from(Document))


def test_finalize_waits_for_owner_approval_and_does_not_post(payroll_db):
    db=payroll_db
    result=svc.finalize_run(db,1,1,2)
    assert result['status']=='pending_approval' and countdocs(db)==0
    with pytest.raises(ApiError) as exc: svc.approve_run(db,1,1,2)
    assert exc.value.status_code==403
    db.rollback()
    result=svc.approve_run(db,1,1,1)
    assert result['status']=='finalized' and result['approved_at'] and countdocs(db)==0


@pytest.mark.parametrize('kind',['accrual','payment','service-accrual','service-payment'])
@pytest.mark.parametrize('status',['draft','pending_approval','finalized','posted'])
def test_missing_approval_cannot_be_bypassed_by_status_or_direct_service(payroll_db,kind,status):
    db=payroll_db;run=db.get(PayrollRun,1);run.status=status;db.commit()
    settings=db.scalars(select(PayrollSettings)).one()
    with pytest.raises(ApiError) as exc:
        if kind=='accrual':accounting.post_payroll_accrual_document(db,1,1,run,settings)
        elif kind=='payment':accounting.post_payroll_payment_document(db,1,1,run,settings,300)
        elif kind=='service-accrual':svc.post_run_to_accounting(db,1,1,1)
        else:svc.post_run_payment(db,1,1,1,300)
    assert exc.value.code=='PAYROLL_APPROVAL_REQUIRED' and countdocs(db)==0


def test_owner_approved_accrual_uses_configured_expense_tax_and_no_duplicate(payroll_db):
    db=payroll_db;svc.finalize_run(db,1,1,2);svc.approve_run(db,1,1,1)
    result=svc.post_run_to_accounting(db,1,1,1)
    assert result['status']=='posted' and countdocs(db)==1
    lines=list(db.scalars(select(DocumentLine)))
    assert {(l.account_id,l.debit,l.credit) for l in lines}=={(518,Decimal(1000),Decimal(0)),(389,Decimal(0),Decimal(100)),(369,Decimal(0),Decimal(900))}
    with pytest.raises(ApiError):svc.post_run_to_accounting(db,1,1,1)
    assert countdocs(db)==1
    with pytest.raises(ApiError):svc.post_run_payment(db,1,1,2,300)
    assert countdocs(db)==1
    svc.post_run_payment(db,1,1,1,300)
    with pytest.raises(ApiError):svc.post_run_payment(db,1,1,1,300)
    assert countdocs(db)==2


@pytest.mark.parametrize('payload',[{'require_approval':False},{'auto_post_on_finalize':True}])
def test_protected_policy_cannot_be_disabled(payroll_db,payload):
    with pytest.raises(ApiError) as exc:svc.update_settings(payroll_db,1,payload,1)
    assert exc.value.code=='PAYROLL_APPROVAL_POLICY_LOCKED'


def test_policy_survives_settings_json_replacement_and_staff_cannot_change_it(payroll_db):
    db=payroll_db
    with pytest.raises(ApiError):svc.update_settings(db,1,{'tax_payable_account_id':369},2)
    db.rollback()
    svc.update_settings(db,1,{'extra_settings':{'financial_approval_policy':{'owner_only':False}}},1)
    assert db.scalars(select(PayrollSettings)).one().extra_settings['financial_approval_policy']['owner_only'] is True


def test_automatic_post_is_denied_even_after_owner_approval(payroll_db):
    db=payroll_db;svc.finalize_run(db,1,1,1);svc.approve_run(db,1,1,1)
    with pytest.raises(ApiError) as exc:svc.post_run_to_accounting(db,1,1,1,auto=True)
    assert exc.value.code=='PAYROLL_MANUAL_POST_REQUIRED' and countdocs(db)==0


def test_pending_or_approved_run_cannot_be_edited_and_rejection_clears_approval(payroll_db):
    db=payroll_db;svc.finalize_run(db,1,1,1)
    with pytest.raises(ApiError):svc.update_run(db,1,1,{'title':'changed'},2)
    db.rollback()
    svc.reject_run(db,1,1,1,reason='review again')
    run=db.get(PayrollRun,1)
    assert run.status=='draft' and run.approved_at is None and run.approved_by_user_id is None
    svc.finalize_run(db,1,1,1);svc.approve_run(db,1,1,1)
    with pytest.raises(ApiError):svc.update_run(db,1,1,{'title':'changed'},1)
    assert countdocs(db)==0


@pytest.mark.parametrize('kind',['accrual','payment'])
def test_concurrent_requests_issue_one_document(payroll_db,kind):
    db=payroll_db;svc.finalize_run(db,1,1,1);svc.approve_run(db,1,1,1)
    if kind=='payment':svc.post_run_to_accounting(db,1,1,1)
    barrier=Barrier(2);engine=db.get_bind()
    def post():
        with Session(engine,expire_on_commit=False,autoflush=False) as other:
            barrier.wait()
            try:
                if kind=='payment':svc.post_run_payment(other,1,1,1,300)
                else:svc.post_run_to_accounting(other,1,1,1)
                return 'posted'
            except ApiError as exc:
                other.rollback();return exc.code
    with ThreadPoolExecutor(max_workers=2) as executor: results=list(executor.map(lambda _:post(),range(2)))
    db.expire_all()
    assert sorted(results)==[kind.upper()+'_ALREADY_POSTED','posted']
    assert countdocs(db)==(2 if kind=='payment' else 1)


def test_nonowner_approval_marker_and_disabled_boolean_cannot_bypass_policy(payroll_db):
    db=payroll_db;run=db.get(PayrollRun,1);run.status='finalized';run.approved_at=datetime.utcnow();run.approved_by_user_id=2
    settings=db.scalars(select(PayrollSettings)).one();settings.require_approval=False;db.commit()
    with pytest.raises(ApiError) as exc:svc.post_run_to_accounting(db,1,1,1)
    assert exc.value.code=='PAYROLL_OWNER_APPROVAL_REQUIRED' and countdocs(db)==0


def test_unprotected_business_keeps_existing_optional_approval_flow(payroll_db):
    db=payroll_db;settings=db.scalars(select(PayrollSettings)).one()
    settings.extra_settings={};settings.require_approval=False;db.commit()
    result=svc.finalize_run(db,1,1,2)
    assert result['status']=='finalized' and result['approved_at'] is None
    svc.post_run_to_accounting(db,1,1,2)
    assert countdocs(db)==1


def test_explicit_tax_item_override_still_precedes_default_setting(payroll_db):
    db=payroll_db;item=db.get(PayrollItemDefinition,2);item.account_id=300;db.commit()
    settings=db.scalars(select(PayrollSettings)).one()
    assert accounting._resolve_deduction_account(db,1,item,settings).id==300


def test_http_owner_approval_gate_even_if_staff_has_all_payroll_permissions(payroll_db,monkeypatch):
    from fastapi import FastAPI,Request
    from fastapi.responses import JSONResponse
    from fastapi.testclient import TestClient
    from adapters.api.v1.payroll import router
    from adapters.db.session import get_db
    from app.core.auth_dependency import get_current_user
    db=payroll_db;svc.finalize_run(db,1,1,2)
    actor={'id':2}
    class Context:
        def get_user_id(self):return actor['id']
        def is_superadmin(self):return False
        def is_business_owner(self,bid):return actor['id']==1 and bid==1
        def can_access_business(self,bid):return bid==1
        def _normalize_permissions_value(self,value):return value
    def auth(request:Request):
        if request.headers.get('authorization')!='TestOnly':raise ApiError('UNAUTHORIZED','test auth required',http_status=401)
        return Context()
    app=FastAPI();app.include_router(router)
    app.dependency_overrides[get_db]=lambda:db;app.dependency_overrides[get_current_user]=auth
    monkeypatch.setattr('app.core.permissions.get_current_user',lambda request,db:auth(request))
    monkeypatch.setattr('app.core.permissions.get_business_permissions_for_user',lambda *a:{'payroll':{'view':True,'operate':True,'approve':True,'post':True,'settings':True}})
    @app.exception_handler(ApiError)
    async def handler(request,exc):return JSONResponse(status_code=exc.status_code,content={'error':exc.code})
    path='/payroll/business/1/runs/1';headers={'authorization':'TestOnly'}
    with TestClient(app) as client:
        assert client.post(path+'/approve').status_code==401
        assert client.post(path.replace('/1/','/2/',1)+'/approve',headers=headers).status_code==403
        assert client.post(path+'/approve',headers=headers).status_code==403
        db.rollback()
        assert client.post(path+'/post',headers=headers).status_code==409
        db.rollback();actor['id']=1
        assert client.post(path+'/approve',headers=headers).status_code==200
        assert countdocs(db)==0
        actor['id']=2
        assert client.post(path+'/post',headers=headers).status_code==403
        db.rollback();actor['id']=1
        assert client.post(path+'/post',headers=headers).status_code==200
        assert client.post(path+'/post',headers=headers).status_code==409
        assert countdocs(db)==1


def test_source_sync_preserves_reviewed_accounts_and_owner_policy(native_db):
    db=native_db;source(db);project_native(db,1)
    settings=db.scalars(select(PayrollSettings)).one()
    settings.payroll_expense_account_id=settings.wages_payable_account_id
    settings.tax_payable_account_id=settings.wages_payable_account_id
    expected=settings.payroll_expense_account_id
    settings.require_approval=True;settings.auto_post_on_finalize=False
    settings.extra_settings={**settings.extra_settings,'financial_approval_policy':{'owner_only':True}}
    edit(db,'PAY.PayrollConfiguration',{'EmployeeInsurancePercent':'8'});db.commit()
    project_native(db,1)
    db.refresh(settings)
    assert settings.payroll_expense_account_id==settings.tax_payable_account_id==expected
    assert settings.require_approval and not settings.auto_post_on_finalize
    assert settings.extra_settings['financial_approval_policy']=={'owner_only':True}
