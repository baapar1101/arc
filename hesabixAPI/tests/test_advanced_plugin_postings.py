from datetime import date
from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import pytest
from sqlalchemy import select,func
from sqlalchemy.orm import Session
from adapters.db.models.account import Account
from adapters.db.models.business import Business,BusinessType,BusinessField
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.currency import Currency,BusinessCurrency
from adapters.db.models.advanced_plugins import AdvancedPluginPosting as Posting,AdvancedPluginPostingConfig as Config,AdvancedPluginRecord as Record
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services import advanced_plugin_posting_service as svc
from app.services.advanced_plugin_service import save_record
from app.services.advanced_plugin_operations import run_operation
from app.services.sepidar_native_service import project_native
from app.core.responses import ApiError
from tests.test_advanced_plugins import setup,create,find
from tests.test_sepidar_native_projection import native_db


@pytest.fixture(autouse=True)
def no_external_cache(monkeypatch):
    monkeypatch.setattr('app.services.document_service.invalidate_documents_cache',lambda *a,**k:None)


def seed(db):
    setup(db);project_native(db,1)
    for i in range(5):db.add(Account(id=1001+i,business_id=1,name=f'Posting account {i}',code=f'J{i}',account_type='detail'))
    db.commit()


def configure(db,code):
    return svc.save_config(db,1,code,{'revision':0,'enabled':True,'accounts':{k:1001+i for i,k in enumerate(svc.ROLES[code])},'contract_side':'customer'},1)


def event(db,code):
    if code=='fixed_assets':
        asset=create(db,code,'asset',title='local asset',cost=3650,method='straight_line',useful_life_years=1,start_date='2026-04-01')
        saved=run_operation(db,1,code,'depreciation_save',{'record_id':asset['id'],'from_date':'2026-04-01','to_date':'2026-04-10'},1)
        return db.get(Record,saved['saved_record_id'])
    if code=='contracting':
        person=db.scalars(select(Person).where(Person.business_id==1)).first()
        contract=create(db,code,'contract',retention_percent=10,advance_percent=5,tax_percent=9,person_id=person.id)
        statement=create(db,code,'statement',parent_id=contract['id'],start_date='2026-04-01')
        create(db,code,'statement_line',parent_id=statement['id'],quantity=2,unit_price=100)
        saved=run_operation(db,1,code,'certificate_save',{'record_id':statement['id']},1)
        return db.get(Record,saved['saved_record_id'])
    values={'start_date':'2026-10-23','amount':100,'direction':'increase','reason':'explicit independent adjustment'}
    if code=='payroll_calendar_tax':values['reference']='ASSESSMENT 001'
    elif code=='conditional_pricing':
        fy=db.scalars(select(FiscalYear).where(FiscalYear.is_last.is_(True))).one()
        doc=Document(business_id=1,code='LOCAL-SALE',fiscal_year_id=fy.id,currency_id=1,created_by_user_id=1,document_date=date(2026,4,1),document_type='invoice_sales',is_proforma=False)
        db.add(doc);db.flush()
        person=db.scalars(select(Person).where(Person.business_id==1)).first()
        db.add_all([DocumentLine(document_id=doc.id,account_id=1001,person_id=person.id,debit=100,credit=0),DocumentLine(document_id=doc.id,account_id=1002,debit=0,credit=100)])
        values.update(invoice_document_id=doc.id,tax_amount=9);db.commit()
    else:
        fy=db.scalars(select(FiscalYear).where(FiscalYear.is_last.is_(True))).one()
        wh=WarehouseDocument(business_id=1,code='LOCAL-OUT',fiscal_year_id=fy.id,document_date=date(2026,4,1),status='posted',doc_type='issue',source_type='manual')
        db.add(wh);db.flush();line=WarehouseDocumentLine(warehouse_document_id=wh.id,product_id=1,quantity=2,movement='out');db.add(line);db.flush();values['warehouse_document_line_id']=line.id;db.commit()
    return db.get(Record,create(db,code,svc.KINDS[code],**values)['id'])


def payload(draft,**extra):return {'revision':draft['revision'],'input_hash':draft['input_hash'],'confirmed':True,'reason':'manager reviewed the evidence',**extra}


@pytest.mark.parametrize('code',list(svc.ROLES))
def test_each_plugin_draft_approval_idempotency_balance_and_provenance(native_db,code):
    db=native_db;seed(db);configure(db,code);row=event(db,code)
    before=db.scalar(select(func.count()).select_from(Document))
    draft=svc.prepare(db,1,code,row.id,1)
    assert db.scalar(select(func.count()).select_from(Document))==before
    assert svc.prepare(db,1,code,row.id,1)['id']==draft['id']
    result=svc.decide(db,1,code,draft['id'],'approve',payload(draft),1)
    assert result['state']=='posted' and result['approved_by_user_id']==1
    repeated=svc.decide(db,1,code,draft['id'],'approve',payload(draft),1)
    assert repeated['document_id']==result['document_id']
    assert svc.prepare(db,1,code,row.id,1)['document_id']==result['document_id']
    assert db.scalar(select(func.count()).select_from(Document))==before+1
    doc=db.get(Document,result['document_id']);lines=list(db.scalars(select(DocumentLine).where(DocumentLine.document_id==doc.id)))
    assert doc.document_type=='advanced_plugin_journal' and not doc.is_proforma
    assert sum(l.debit for l in lines)==sum(l.credit for l in lines)>0
    assert all(l.debit_base==l.debit and l.credit_base==l.credit and l.exchange_rate==1 for l in lines)
    assert doc.extra_info['advanced_plugin']['input_hash']==draft['input_hash']
    assert result['proposal']['inputs']['records']


def test_contract_supplier_reverses_all_components(native_db):
    db=native_db;seed(db);cfg=configure(db,'contracting');row=event(db,'contracting')
    customer=svc.prepare(db,1,'contracting',row.id,1)
    svc.save_config(db,1,'contracting',{**cfg,'contract_side':'supplier'},1)
    supplier=svc.refresh(db,1,'contracting',customer['id'],{'revision':1},1)
    for left,right in zip(customer['proposal']['lines'],supplier['proposal']['lines']):
        assert left['debit']==right['credit'] and left['credit']==right['debit']


def test_source_events_and_source_descendants_are_never_reposted(native_db):
    db=native_db;seed(db);configure(db,'fixed_assets')
    imported=find(db,'fixed_assets','asset')
    result=run_operation(db,1,'fixed_assets','depreciation_save',{'record_id':imported.id,'from_date':'2026-04-01','to_date':'2026-04-10'},1)
    with pytest.raises(ApiError) as error:svc.prepare(db,1,'fixed_assets',result['saved_record_id'],1)
    assert error.value.status_code==409
    configure(db,'conditional_pricing')
    source=db.scalars(select(Document).where(Document.document_type=='invoice_sales')).first()
    adjustment=create(db,'conditional_pricing','price_adjustment',amount=1,start_date='2026-10-23',direction='decrease',reason='correction test',invoice_document_id=source.id)
    with pytest.raises(ApiError):svc.prepare(db,1,'conditional_pricing',adjustment['id'],1)


def test_same_event_new_record_does_not_bypass_duplicate_guard(native_db):
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax')
    svc.prepare(db,1,'payroll_calendar_tax',row.id,1)
    duplicate=create(db,'payroll_calendar_tax','tax_adjustment',reference='  assessment   001 ',start_date='2026-10-23',amount=200,direction='increase',reason='new record same financial event')
    with pytest.raises(ApiError) as error:svc.prepare(db,1,'payroll_calendar_tax',duplicate['id'],1)
    assert error.value.status_code==409
    assert db.scalar(select(func.count()).select_from(Posting))==1


@pytest.mark.parametrize('change',['amount','config','archive','fiscal'])
def test_approval_rejects_stale_or_closed_inputs(native_db,change):
    db=native_db;seed(db);cfg=configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax')
    draft=svc.prepare(db,1,'payroll_calendar_tax',row.id,1)
    if change=='amount':save_record(db,1,row.plugin_code,row.kind,{'revision':row.revision,'amount':201},1,row.id)
    elif change=='archive':save_record(db,1,row.plugin_code,row.kind,{'revision':row.revision,'status':'archived'},1,row.id)
    elif change=='config':svc.save_config(db,1,row.plugin_code,{**cfg,'accounts':{'expense':1002,'payable':1001}},1)
    else:
        db.scalars(select(FiscalYear).where(FiscalYear.is_last.is_(True))).one().is_last=False;db.commit()
    before=db.scalar(select(func.count()).select_from(Document))
    with pytest.raises(ApiError):svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(draft),1)
    assert db.scalar(select(func.count()).select_from(Document))==before
    assert db.get(Posting,draft['id']).state=='draft'


def test_exact_revision_confirmation_and_valid_config_are_required(native_db):
    db=native_db;seed(db);row=event(db,'payroll_calendar_tax')
    with pytest.raises(ApiError):svc.prepare(db,1,row.plugin_code,row.id,1)
    with pytest.raises(ApiError):svc.save_config(db,1,row.plugin_code,{'revision':0,'enabled':True,'accounts':{'expense':1001,'payable':1001}},1)
    configure(db,row.plugin_code);draft=svc.prepare(db,1,row.plugin_code,row.id,1)
    for bad in [{'confirmed':False},{'revision':999},{'input_hash':'tampered'},{'reason':'x'},{'business_id':2}]:
        with pytest.raises(ApiError):svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(draft,**bad),1)
    assert db.get(Posting,draft['id']).document_id is None


def test_rejection_refresh_and_immutable_posted_event(native_db):
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax')
    draft=svc.prepare(db,1,row.plugin_code,row.id,1)
    rejected=svc.decide(db,1,row.plugin_code,draft['id'],'reject',payload(draft),1)
    with pytest.raises(ApiError):svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(rejected),1)
    fresh=svc.refresh(db,1,row.plugin_code,draft['id'],{'revision':rejected['revision']},1)
    svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(fresh),1)
    with pytest.raises(ApiError):save_record(db,1,row.plugin_code,row.kind,{'revision':row.revision,'amount':9},1,row.id)


def test_transaction_rolls_back_header_lines_and_approval_on_failure(native_db,monkeypatch):
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax');draft=svc.prepare(db,1,row.plugin_code,row.id,1)
    original=svc.DocumentRepository.create_document;before=db.scalar(select(func.count()).select_from(Document))
    def fail_after_insert(*a,**k):original(*a,**k);raise RuntimeError('simulated interruption after document insert')
    monkeypatch.setattr(svc.DocumentRepository,'create_document',fail_after_insert)
    with pytest.raises(RuntimeError):svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(draft),1)
    db.rollback()
    assert db.scalar(select(func.count()).select_from(Document))==before
    assert db.get(Posting,draft['id']).state=='draft' and db.get(Posting,draft['id']).document_id is None


def test_reversal_is_append_only_balanced_and_idempotent(native_db):
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax');draft=svc.prepare(db,1,row.plugin_code,row.id,1)
    posted=svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(draft),1)
    reversed=svc.decide(db,1,row.plugin_code,draft['id'],'reverse',payload(posted,on_date='2026-10-23'),1)
    repeated=svc.decide(db,1,row.plugin_code,draft['id'],'reverse',payload(posted,on_date='2026-10-23'),1)
    assert reversed['reversal_document_id']==repeated['reversal_document_id']
    original=list(db.scalars(select(DocumentLine).where(DocumentLine.document_id==posted['document_id']).order_by(DocumentLine.id)))
    contra=list(db.scalars(select(DocumentLine).where(DocumentLine.document_id==reversed['reversal_document_id']).order_by(DocumentLine.id)))
    assert [(l.account_id,l.debit,l.credit) for l in original]==[(l.account_id,l.credit,l.debit) for l in contra]
    with pytest.raises(ApiError):svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(reversed),1)


def test_two_simultaneous_approvals_create_one_document(native_db):
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax');draft=svc.prepare(db,1,row.plugin_code,row.id,1)
    before=db.scalar(select(func.count()).select_from(Document));db.commit();barrier=Barrier(2)
    def worker():
        with Session(db.get_bind(),expire_on_commit=False) as session:
            barrier.wait(timeout=10)
            return svc.decide(session,1,row.plugin_code,draft['id'],'approve',payload(draft),1)['document_id']
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(lambda _:worker(),range(2)))
    db.expire_all()
    assert results[0]==results[1]
    assert db.scalar(select(func.count()).select_from(Document))==before+1


def test_cross_business_accounts_are_rejected(native_db):
    db=native_db;seed(db)
    db.add(Business(id=2,name='other',owner_id=1,business_type=BusinessType.COMPANY,business_field=BusinessField.OTHER,default_currency_id=1,default_phone_region='IR'));db.flush()
    db.add(Account(id=2001,business_id=2,name='Other',code='Other',account_type='detail'));db.commit()
    with pytest.raises(ApiError):svc.save_config(db,1,'payroll_calendar_tax',{'revision':0,'enabled':True,'accounts':{'expense':1001,'payable':2001}},1)


def test_parent_changes_invalidate_saved_depreciation(native_db):
    db=native_db;seed(db);configure(db,'fixed_assets');row=event(db,'fixed_assets')
    draft=svc.prepare(db,1,'fixed_assets',row.id,1)
    parent=db.get(Record,row.parent_id)
    save_record(db,1,'fixed_assets','asset',{'revision':parent.revision,'cost':7300},1,parent.id)
    with pytest.raises(ApiError):svc.decide(db,1,'fixed_assets',draft['id'],'approve',payload(draft),1)


def test_foreign_currency_parent_cannot_be_silently_posted_as_base(native_db):
    db=native_db;seed(db);configure(db,'fixed_assets');row=event(db,'fixed_assets')
    db.add(Currency(id=2,name='usd',title='USD',symbol='$',code='USD'));db.flush();db.add(BusinessCurrency(business_id=1,currency_id=2));db.flush()
    db.get(Record,row.parent_id).currency_id=2;db.commit()
    with pytest.raises(ApiError):svc.prepare(db,1,'fixed_assets',row.id,1)


def test_zero_net_contract_still_posts_retention_and_revenue(native_db):
    db=native_db;seed(db);configure(db,'contracting')
    person=db.scalars(select(Person).where(Person.business_id==1)).first()
    contract=create(db,'contracting','contract',person_id=person.id,retention_percent=100)
    statement=create(db,'contracting','statement',parent_id=contract['id'],start_date='2026-04-01')
    create(db,'contracting','statement_line',parent_id=statement['id'],quantity=1,unit_price=100)
    saved=run_operation(db,1,'contracting','certificate_save',{'record_id':statement['id']},1)
    draft=svc.prepare(db,1,'contracting',saved['saved_record_id'],1)
    assert draft['proposal']['total_debit']=='100.00'
    assert svc.decide(db,1,'contracting',draft['id'],'approve',payload(draft),1)['state']=='posted'


def test_posted_plugin_document_cannot_be_edited_or_deleted_as_manual(native_db):
    from app.services.document_service import delete_document,update_manual_document
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax')
    draft=svc.prepare(db,1,row.plugin_code,row.id,1);posted=svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(draft),1)
    with pytest.raises(ApiError):delete_document(db,posted['document_id'])
    with pytest.raises(ApiError):update_manual_document(db,posted['document_id'],{'description':'not allowed'})
    assert db.get(Document,posted['document_id']) is not None


def test_reserved_document_code_collision_does_not_adopt_existing_document(native_db):
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax')
    draft=svc.prepare(db,1,row.plugin_code,row.id,1)
    fy=db.scalars(select(FiscalYear).where(FiscalYear.is_last.is_(True))).one()
    existing=Document(business_id=1,code=f'ADP-{draft["id"]}',fiscal_year_id=fy.id,currency_id=1,created_by_user_id=1,document_date=date(2026,10,23),document_type='manual',is_proforma=False)
    db.add(existing);db.commit()
    with pytest.raises(ApiError) as error:svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(draft),1)
    assert error.value.status_code==409 and db.get(Posting,draft['id']).document_id is None
    assert db.get(Document,existing.id).document_type=='manual'


def test_tampered_original_ledger_stops_reversal(native_db):
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax')
    draft=svc.prepare(db,1,row.plugin_code,row.id,1);posted=svc.decide(db,1,row.plugin_code,draft['id'],'approve',payload(draft),1)
    line=db.scalars(select(DocumentLine).where(DocumentLine.document_id==posted['document_id']).order_by(DocumentLine.id)).first()
    line.debit+=1;db.commit()
    with pytest.raises(ApiError):svc.decide(db,1,row.plugin_code,draft['id'],'reverse',payload(posted,on_date='2026-10-23'),1)
    assert db.get(Posting,draft['id']).reversal_document_id is None


def test_http_employee_cannot_approve_owner_can_and_tenant_is_scoped(native_db,monkeypatch):
    from fastapi import FastAPI,Request
    from fastapi.responses import JSONResponse
    from fastapi.testclient import TestClient
    from adapters.api.v1.advanced_plugins import router
    from adapters.db.session import get_db
    from app.core.auth_dependency import get_current_user
    db=native_db;seed(db);configure(db,'payroll_calendar_tax');row=event(db,'payroll_calendar_tax')
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
    monkeypatch.setattr('app.core.permissions.get_business_permissions_for_user',lambda *a:{'payroll_calendar_tax':{'view':True,'write':True,'settings':True}})
    @app.exception_handler(ApiError)
    async def handler(request,exc):return JSONResponse(status_code=exc.status_code,content={'error':exc.code if hasattr(exc,'code') else 'denied'})
    path='/advanced-plugins/business/1/payroll_calendar_tax/finance';headers={'authorization':'TestOnly'}
    with TestClient(app) as client:
        assert client.get(path).status_code==401
        assert client.get(path.replace('/1/','/2/'),headers=headers).status_code==403
        response=client.post(path+'/drafts',headers=headers,json={'record_id':row.id});assert response.status_code==200
        draft=response.json()['data']
        assert client.put(path+'/config',headers=headers,json={}).status_code==403
        assert client.post(path+f'/{draft["id"]}/approve',headers=headers,json=payload(draft)).status_code==403
        owner['yes']=True
        approved=client.post(path+f'/{draft["id"]}/approve',headers=headers,json=payload(draft))
        assert approved.status_code==200 and approved.json()['data']['state']=='posted'
