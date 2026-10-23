"""Acceptance of Sepidar account mappings, using ONLY disposable test data.

Never import production SessionLocal; native_db asserts a *_sepidar_test database.
"""
from decimal import Decimal
import pytest
from sqlalchemy import select,func
from adapters.db.models.account import Account
from adapters.db.models.currency import Currency,BusinessCurrency
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.advanced_plugins import AdvancedPluginRecord as Record,AdvancedPluginPosting as Posting
from adapters.db.models.warehouse_document import WarehouseDocument
from app.core.responses import ApiError
from app.services import advanced_plugin_posting_service as svc
from app.services.advanced_plugin_service import save_record
from tests.test_advanced_plugin_postings import seed,event,payload
from tests.test_advanced_plugins import create
from tests.test_sepidar_native_projection import native_db

MAPPINGS={
 'payroll_calendar_tax':{'expense':369,'payable':389},
 'conditional_pricing':{'receivable':312,'revenue':410,'tax':391},
 'inventory_trace_cost':{'cogs':422,'inventory':517},
}
ACCOUNTS={369:('211101','حقوق و دستمزد پرداختنی'),389:('211128','مالیات حقوق پرداختنی کارکنان'),
 312:('111201','حساب‌های دریافتنی تجاری'),410:('411001','فروش داخلی محصولات'),391:('211130','مالیات ارزش افزوده پرداختی'),
 422:('511001','بهای تمام‌شده فروش داخلی محصولات'),517:('111501','موجودی انبار')}

@pytest.fixture(autouse=True)
def no_external_cache(monkeypatch):
    monkeypatch.setattr('app.services.document_service.invalidate_documents_cache',lambda *a,**k:None)

def configured(db,code):
    seed(db)
    for aid,(number,name) in ACCOUNTS.items():
        db.add(Account(id=aid,business_id=1,code=number,name=name,account_type='detail'))
    db.commit()
    return svc.save_config(db,1,code,{'revision':0,'enabled':True,'accounts':MAPPINGS[code],'contract_side':'require_review'},1)

def countdocs(db):return db.scalar(select(func.count()).select_from(Document))

@pytest.mark.parametrize('code',MAPPINGS)
@pytest.mark.parametrize('direction',['increase','decrease'])
def test_actual_mapping_direction_balanced_draft_and_no_automatic_post(native_db,code,direction):
    db=native_db;configured(db,code);row=event(db,code)
    save_record(db,1,code,row.kind,{'revision':row.revision,'direction':direction},1,row.id)
    before=countdocs(db);draft=svc.prepare(db,1,code,row.id,1)
    assert countdocs(db)==before and draft['state']=='draft' and draft['document_id'] is None
    assert draft['approved_by_user_id'] is None
    assert svc.prepare(db,1,code,row.id,1)['id']==draft['id']
    lines={x['account_id']:x for x in draft['proposal']['lines']}
    assert set(lines)==set(MAPPINGS[code].values())
    amounts={'payroll_calendar_tax':{'expense':100,'payable':100},
             'conditional_pricing':{'receivable':109,'revenue':100,'tax':9},
             'inventory_trace_cost':{'cogs':100,'inventory':100}}[code]
    debit_role={'payroll_calendar_tax':'expense','conditional_pricing':'receivable','inventory_trace_cost':'cogs'}[code]
    for role,aid in MAPPINGS[code].items():
        is_debit=(role==debit_role)==(direction=='increase')
        assert Decimal(lines[aid]['debit' if is_debit else 'credit'])==amounts[role]
        assert Decimal(lines[aid]['credit' if is_debit else 'debit'])==0
    assert draft['proposal']['total_debit']==draft['proposal']['total_credit']
    # No implicit confirmation, forged snapshot or stale revision can issue it.
    for bad in [{'confirmed':False},{'confirmed':None},{'input_hash':'invalid'},{'revision':999}]:
        with pytest.raises(ApiError):svc.decide(db,1,code,draft['id'],'approve',payload(draft,**bad),1)
        assert countdocs(db)==before and db.get(Posting,draft['id']).state=='draft'

@pytest.mark.parametrize('code',MAPPINGS)
def test_same_semantic_event_cannot_create_second_draft(native_db,code):
    db=native_db;configured(db,code);row=event(db,code)
    first=svc.prepare(db,1,code,row.id,1);before=countdocs(db)
    values={**row.data,'amount':str(row.amount),'start_date':str(row.start_date)}
    duplicate=create(db,code,row.kind,**values)
    with pytest.raises(ApiError) as exc:svc.prepare(db,1,code,duplicate['id'],1)
    assert exc.value.status_code==409
    assert db.scalar(select(func.count()).select_from(Posting))==1
    assert countdocs(db)==before and db.get(Posting,first['id']).document_id is None

@pytest.mark.parametrize('code',MAPPINGS)
def test_source_record_and_source_native_reference_cannot_be_reposted(native_db,code):
    db=native_db;configured(db,code);row=event(db,code);before=countdocs(db)
    row.source_database='Sepidar01';row.source_table='source_event';db.commit()
    with pytest.raises(ApiError) as exc:svc.prepare(db,1,code,row.id,1)
    assert exc.value.status_code==409
    row.source_database=None;row.source_table=None;db.commit()
    if code=='conditional_pricing':
        doc=db.get(Document,row.data['invoice_document_id']);doc.extra_info={'sepidar':{'source':'test-only'}};db.commit()
        with pytest.raises(ApiError):svc.prepare(db,1,code,row.id,1)
    elif code=='inventory_trace_cost':
        from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
        line=db.get(WarehouseDocumentLine,row.data['warehouse_document_line_id'])
        db.get(WarehouseDocument,line.warehouse_document_id).source_type='sepidar';db.commit()
        with pytest.raises(ApiError):svc.prepare(db,1,code,row.id,1)
    assert countdocs(db)==before and db.scalar(select(func.count()).select_from(Posting))==0

@pytest.mark.parametrize('code',MAPPINGS)
def test_disable_closed_year_foreign_currency_and_changed_mapping_are_safe(native_db,code):
    db=native_db;cfg=configured(db,code);row=event(db,code);before=countdocs(db)
    cfg=svc.save_config(db,1,code,{**cfg,'enabled':False},1)
    with pytest.raises(ApiError):svc.prepare(db,1,code,row.id,1)
    cfg=svc.save_config(db,1,code,{**cfg,'enabled':True},1)
    fy=db.scalars(select(FiscalYear).where(FiscalYear.is_last.is_(True))).one();fy.is_last=False;db.commit()
    with pytest.raises(ApiError):svc.prepare(db,1,code,row.id,1)
    fy.is_last=True;db.commit()
    db.add(Currency(id=2,name='usd',title='USD',symbol='$',code='USD'));db.flush();db.add(BusinessCurrency(business_id=1,currency_id=2));db.flush()
    row.currency_id=2;db.commit()
    with pytest.raises(ApiError):svc.prepare(db,1,code,row.id,1)
    row.currency_id=None;db.commit()
    draft=svc.prepare(db,1,code,row.id,1)
    # Even a save of the same mapping changes the reviewed revision.
    svc.save_config(db,1,code,cfg,1)
    with pytest.raises(ApiError):svc.decide(db,1,code,draft['id'],'approve',payload(draft),1)
    assert countdocs(db)==before and db.get(Posting,draft['id']).state=='draft'

@pytest.mark.parametrize('code',['fixed_assets','contracting'])
def test_unconfigured_deferred_plugins_cannot_prepare_or_post(native_db,code):
    db=native_db;seed(db)
    svc.save_config(db,1,code,{'revision':0,'enabled':False,'accounts':{},'contract_side':'require_review'},1)
    row=event(db,code);before=countdocs(db)
    with pytest.raises(ApiError):svc.prepare(db,1,code,row.id,1)
    assert countdocs(db)==before and db.scalar(select(func.count()).select_from(Posting))==0

@pytest.mark.parametrize('code',MAPPINGS)
def test_http_draft_does_not_post_and_staff_or_unconfirmed_owner_cannot_issue(native_db,monkeypatch,code):
    from fastapi import FastAPI,Request
    from fastapi.responses import JSONResponse
    from fastapi.testclient import TestClient
    from adapters.api.v1.advanced_plugins import router
    from adapters.db.session import get_db
    from app.core.auth_dependency import get_current_user
    db=native_db;configured(db,code);row=event(db,code);before=countdocs(db)
    owner={'yes':False}
    class Context:
        def get_user_id(self):return 1
        def is_superadmin(self):return False
        def is_business_owner(self,bid):return owner['yes'] and bid==1
        def can_access_business(self,bid):return bid==1
    def auth(request:Request):
        if request.headers.get('authorization')!='TestOnly':raise ApiError('UNAUTHORIZED','test auth required',http_status=401)
        return Context()
    app=FastAPI();app.include_router(router)
    app.dependency_overrides[get_db]=lambda:db;app.dependency_overrides[get_current_user]=auth
    monkeypatch.setattr('app.core.permissions.get_current_user',lambda request,db:auth(request))
    monkeypatch.setattr('app.core.permissions.get_business_permissions_for_user',lambda *a:{code:{'view':True,'write':True,'settings':True}})
    @app.exception_handler(ApiError)
    async def handler(request,exc):return JSONResponse(status_code=exc.status_code,content={'error':'denied'})
    path=f'/advanced-plugins/business/1/{code}/finance';headers={'authorization':'TestOnly'}
    with TestClient(app) as client:
        assert client.get(path).status_code==401
        assert client.get(path.replace('/1/','/2/'),headers=headers).status_code==403
        view=client.get(path,headers=headers);assert view.status_code==200
        assert view.json()['data']['config']['accounts']==MAPPINGS[code]
        created=client.post(path+'/drafts',headers=headers,json={'record_id':row.id})
        assert created.status_code==200
        draft=created.json()['data'];assert draft['state']=='draft' and draft['document_id'] is None
        assert client.put(path+'/config',headers=headers,json={}).status_code==403
        assert client.post(path+f'/{draft["id"]}/approve',headers=headers,json=payload(draft)).status_code==403
        owner['yes']=True
        for bad in [False,None]:
            assert client.post(path+f'/{draft["id"]}/approve',headers=headers,json=payload(draft,confirmed=bad)).status_code==409
        omitted=payload(draft);omitted.pop('confirmed')
        assert client.post(path+f'/{draft["id"]}/approve',headers=headers,json=omitted).status_code==409
        assert countdocs(db)==before and db.get(Posting,draft['id']).state=='draft'
