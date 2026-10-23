from datetime import date,datetime,timedelta
from decimal import Decimal
from types import SimpleNamespace
import pytest
from sqlalchemy import select,func
from adapters.db.models.advanced_plugins import AdvancedPluginSetting as Setting,AdvancedPluginRecord as Record
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.sepidar_live_import import SepidarImportSetting,SepidarImportRow
from adapters.db.models.payroll import PayrollSettings
from tests.test_sepidar_native_projection import native_db
from tests.test_sepidar_operations import operations,add
from tests.test_sepidar_plugin_bridge import license,edit
from app.services.advanced_plugin_catalog import MODULES,default_options
from app.services.advanced_plugin_service import save_record,save_settings,list_records,get_record,overview,number,licensed
from app.services.advanced_plugin_operations import run_operation,effective_payroll_settings,tax_brackets
from app.services.sepidar_native_service import project_native,NativeConversionError
from app.core.responses import ApiError


def setup(db):
    operations(db)
    db.scalars(select(SepidarImportSetting)).one().plugins_enabled=True
    for code in MODULES:
        license(db,code)
        db.add(Setting(business_id=1,plugin_code=code,enabled=True,sync_enabled=True,options=default_options(code)))
    add(db,'AST.DepreciationRule',[{'DepreciationRuleID':1,'GroupNo':1,'Description':'test rule','UsefulLife':'5','DepreciationMethod':2}])
    add(db,'AST.AssetClass',[{'AssetClassID':1,'Title':'class'}])
    add(db,'AST.AssetGroup',[{'AssetGroupID':1,'AssetClassRef':1,'Title':'group'}])
    add(db,'AST.Asset',[{'AssetId':1,'AssetGroupRef':1,'Title':'machine','PlaqueNumber':'A1'}])
    add(db,'AST.CostPart',[{'CostPartId':1,'AssetRef':1,'TotalCost':'3650','SalvageValue':0,'AccumulatedDepreciation':0,'UsefulLife':1,'DepreciationMethodType':2,'EffectiveDate':'2026-01-01'}])
    add(db,'CNT.Project',[{'ProjectID':1,'Title':'project'}])
    add(db,'CNT.Contract',[{'ContractID':1,'ProjectRef':1,'Title':'contract','Cost':'100','ContractorPartyRef':3}])
    add(db,'CNT.Status',[{'StatusID':1,'ContractRef':1,'Number':1,'ConfirmedCost':'100'}])
    add(db,'CNT.StatusItem',[{'StatusItemID':1,'StatusRef':1,'ItemTitle':'work','ConfirmedQuantity':'2','ConfirmedFee':'50','ConfirmedPrice':'100'}])
    add(db,'PAY.PayrollCalendar',[{'PayrollCalendarId':1,'Year':1405,'Month':1,'Day':31,'HourMinute':440}])
    add(db,'PAY.TaxGroup',[{'TaxGroupId':1,'Title':'tax group'}])
    add(db,'PAY.TaxTable',[{'TaxTableId':1,'TaxGroupRef':1,'Title':'tax table','Date':'2026-03-21','TaxType':1}])
    add(db,'PAY.TaxTableItem',[{'TaxTableItemId':1,'TaxTableRef':1,'FromAmount':0,'ToAmount':1000,'Rate':10}])
    add(db,'SLS.PriceNote',[{'PriceNoteID':1,'Title':'prices','Date':'2026-01-01'}])
    add(db,'SLS.SaleType',[{'SaleTypeId':1,'Title':'retail'}])
    add(db,'SLS.PriceNoteItem',[{'PriceNoteItemID':1,'PriceNoteRef':1,'ItemRef':5,'UnitRef':1,'CurrencyRef':1,'SaleTypeRef':1,'Fee':'50','Discount':0,'AdditionRate':0,'CustomerGroupingRef':10}])
    add(db,'INV.TracingCategory',[{'TracingCategoryID':1,'Title':'batch category'}])
    add(db,'INV.Tracing',[{'TracingID':1,'TracingCategoryRef':1,'Title':'batch one'}])
    edit(db,'INV.InventoryReceiptItem',{'TracingRef':1})
    edit(db,'INV.InventoryDeliveryItem',{'TracingRef':1})
    db.commit()


def find(db,code,kind):return db.scalars(select(Record).where(Record.plugin_code==code,Record.kind==kind)).one()


def create(db,code,kind,**values):return save_record(db,1,code,kind,{'title':kind,**values},1)


def test_five_source_modules_repeat_stable_and_keep_financial_rows(native_db):
    db=native_db;setup(db);first=project_native(db,1)
    summary=first['plugins']['specialist_addons']
    assert set(summary)==set(MODULES)
    ids=[(r.id,r.identity,r.revision) for r in db.scalars(select(Record).order_by(Record.id))]
    gl=db.scalar(select(func.count()).select_from(DocumentLine))
    second=project_native(db,1)
    assert [(r.id,r.identity,r.revision) for r in db.scalars(select(Record).order_by(Record.id))]==ids
    assert all(not s['created'] and not s['updated'] for s in second['plugins']['specialist_addons'].values())
    assert db.scalar(select(func.count()).select_from(DocumentLine))==gl
    assert find(db,'fixed_assets','asset').parent_id==find(db,'fixed_assets','asset_group').id
    assert find(db,'inventory_trace_cost','receipt_layer').data['unit_cost']=='50'


def test_source_change_archive_restore_and_protection(native_db):
    db=native_db;setup(db);project_native(db,1)
    rule=find(db,'conditional_pricing','price_rule');rid=rule.id
    with pytest.raises(ApiError):save_record(db,1,'conditional_pricing','price_rule',{'title':'hijack','revision':rule.revision},1,rid)
    edit(db,'SLS.PriceNoteItem',{'Fee':'60'});db.commit();project_native(db,1)
    assert db.get(Record,rid).amount==60
    source=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_schema=='AST',SepidarImportRow.source_table=='DepreciationRule')).one()
    old=find(db,'fixed_assets','rule').id;source.is_deleted=True;db.commit();project_native(db,1)
    assert db.get(Record,old).source_deleted
    source.is_deleted=False;db.commit();project_native(db,1)
    assert not db.get(Record,old).source_deleted


def test_source_bad_parent_rolls_back_all_domains(native_db):
    db=native_db;setup(db);edit(db,'CNT.Status',{'ContractRef':999});db.commit()
    with pytest.raises(NativeConversionError):project_native(db,1)
    assert db.scalar(select(func.count()).select_from(Record))==0
    assert db.scalar(select(func.count()).select_from(DocumentLine))==0


def test_local_validation_revision_and_cross_tenant(native_db):
    db=native_db;setup(db);project_native(db,1)
    row=create(db,'fixed_assets','asset',cost='1000',salvage='100',method='straight_line',useful_life_years='5')
    with pytest.raises(ApiError):get_record(db,2,'fixed_assets',row['id'])
    with pytest.raises(ApiError):save_record(db,1,'fixed_assets','asset',{'title':'stale','revision':0},1,row['id'])
    with pytest.raises(ApiError):create(db,'fixed_assets','asset',cost='100',salvage='101')
    with pytest.raises(ApiError):create(db,'fixed_assets','asset',cost='NaN')
    with pytest.raises(ApiError):create(db,'fixed_assets','asset',cost=10,business_id=2)
    with pytest.raises(ApiError):create(db,'contracting','statement_line',unit_price=2,parent_id=row['id'])


def test_depreciation_clamp_idempotency_overlap_and_unknown_cost(native_db):
    db=native_db;setup(db);project_native(db,1)
    asset=find(db,'fixed_assets','asset')
    payload={'record_id':asset.id,'from_date':'2026-01-01','to_date':'2026-01-10'}
    first=run_operation(db,1,'fixed_assets','depreciation_save',payload,1)
    assert first['metrics'][1]['value']=='100.0000'
    assert run_operation(db,1,'fixed_assets','depreciation_save',payload,1)['unchanged']
    with pytest.raises(ApiError):run_operation(db,1,'fixed_assets','depreciation_save',{**payload,'to_date':'2026-01-11'},1)
    assert db.scalar(select(func.count()).select_from(Record).where(Record.kind=='schedule'))==1


def test_contract_certificate_native_values_and_repeat(native_db):
    db=native_db;setup(db);project_native(db,1)
    payload={'record_id':find(db,'contracting','statement').id}
    a=run_operation(db,1,'contracting','certificate_save',payload,1)
    b=run_operation(db,1,'contracting','certificate_save',payload,1)
    assert a['saved_record_id']==b['saved_record_id'] and b['unchanged']
    assert a['metrics'][-1]['value']=='100.0000' and not a['financial_posted']


def test_tax_explicit_approval_effective_dates_and_changed_bracket(native_db):
    db=native_db;setup(db);project_native(db,1)
    table=find(db,'payroll_calendar_tax','tax_table')
    payload={'on_date':'2026-04-01','taxable_amount':'100'}
    with pytest.raises(ApiError):run_operation(db,1,'payroll_calendar_tax','tax_preview',payload)
    run_operation(db,1,'payroll_calendar_tax','approve_tax_table',{'record_id':table.id},1)
    assert run_operation(db,1,'payroll_calendar_tax','tax_preview',payload)['metrics'][1]['value']=='10.0000'
    with pytest.raises(ApiError):run_operation(db,1,'payroll_calendar_tax','tax_preview',{**payload,'on_date':'2027-04-01'})
    edit(db,'PAY.TaxTableItem',{'Rate':15});db.commit();project_native(db,1)
    with pytest.raises(ApiError):run_operation(db,1,'payroll_calendar_tax','tax_preview',payload)


def test_conditional_quote_honors_all_dimensions_and_ambiguity(native_db):
    db=native_db;setup(db);project_native(db,1)
    product=find(db,'conditional_pricing','price_rule').product_id
    payload={'product_id':product,'currency_id':1,'quantity':2,'on_date':'2026-04-01','sale_type_ref':1,'unit_ref':1,'customer_group_ref':10}
    output=run_operation(db,1,'conditional_pricing','price_quote',payload)
    assert output['metrics'][-1]['value']=='100.0000'
    with pytest.raises(ApiError):run_operation(db,1,'conditional_pricing','price_quote',{**payload,'customer_group_ref':11})
    create(db,'conditional_pricing','price_rule',product_id=product,currency_id=1,amount=55,sale_type_ref=1,unit_ref=1,customer_group_ref=10,start_date='2026-01-01')
    with pytest.raises(ApiError):run_operation(db,1,'conditional_pricing','price_quote',payload)


def test_fifo_uses_native_moves_and_does_not_treat_unknown_cost_as_zero(native_db):
    db=native_db;setup(db);project_native(db,1)
    layer=find(db,'inventory_trace_cost','receipt_layer')
    payload={'product_id':layer.product_id,'warehouse_id':layer.data['warehouse_id'],'on_date':'2026-10-23','quote_quantity':2}
    report=run_operation(db,1,'inventory_trace_cost','fifo_report',payload)
    assert report['metrics'][0]['value']=='8.000000'
    assert report['metrics'][-1]['value']=='100.0000'
    layer.data={**layer.data,'unit_cost':None};db.commit()
    with pytest.raises(ApiError):run_operation(db,1,'inventory_trace_cost','fifo_report',payload)


def test_license_expiry_settings_and_server_owned_approvals(native_db):
    from adapters.db.models.marketplace import BusinessPlugin,MarketplacePlugin
    db=native_db;setup(db);project_native(db,1)
    cfg=db.scalars(select(Setting).where(Setting.plugin_code=='fixed_assets')).one()
    with pytest.raises(ApiError):save_settings(db,1,'fixed_assets',{'revision':cfg.revision,'options':{'approved_tax_tables':{}}},1)
    plugin=db.scalars(select(MarketplacePlugin).where(MarketplacePlugin.code=='fixed_assets')).one()
    lic=db.scalars(select(BusinessPlugin).where(BusinessPlugin.plugin_id==plugin.id)).one()
    lic.ends_at=datetime.utcnow()-timedelta(seconds=1);db.commit()
    assert not licensed(db,1,'fixed_assets')
    with pytest.raises(ApiError):list_records(db,1,'fixed_assets')
    assert not next(r for r in overview(db,1)['items'] if r['code']=='fixed_assets')['licensed']


def test_local_tax_table_requires_approval_and_does_not_enable_insurance(native_db):
    from app.services.payroll_statutory import apply_statutory_rules
    db=native_db;setup(db);project_native(db,1)
    group=create(db,'payroll_calendar_tax','tax_group',title='current group')
    table=create(db,'payroll_calendar_tax','tax_table',title='current table',parent_id=group['id'],tax_scope='salary',start_date='2026-03-21',end_date='2027-03-20')
    create(db,'payroll_calendar_tax','tax_bracket',parent_id=table['id'],from_amount=0,to_amount=100,rate=0)
    create(db,'payroll_calendar_tax','tax_bracket',parent_id=table['id'],from_amount=100,rate=10)
    run_operation(db,1,'payroll_calendar_tax','approve_tax_table',{'record_id':table['id']},1)
    cfg=db.scalars(select(Setting).where(Setting.plugin_code=='payroll_calendar_tax')).one()
    cfg.options={**cfg.options,'auto_apply_tax':True,'tax_group_id':group['id']}
    original=PayrollSettings(business_id=1,round_amounts_to=0,extra_settings={'statutory_rules':{'enabled':False}});db.add(original);db.commit()
    effective=effective_payroll_settings(db,1,date(2026,10,23),original)
    def item(i,code,kind):return SimpleNamespace(id=i,code=code,item_kind=kind,affects_insurance=kind=='earning',is_taxable=kind=='earning',affects_taxable=False,calculation_type='statutory' if kind!='earning' else 'manual')
    pending=[(item(1,'salary','earning'),Decimal(1000),False),(item(2,'tax','deduction'),Decimal(0),False),(item(3,'insurance_employee','deduction'),Decimal(0),False)]
    calculated=apply_statutory_rules(pending,{},effective)
    assert calculated[1][1]==90 and calculated[2][1]==0
    assert original.extra_settings=={'statutory_rules':{'enabled':False}}
    with pytest.raises(ApiError):effective_payroll_settings(db,1,date(2028,1,1),original)
    with pytest.raises(ApiError):create(db,'payroll_calendar_tax','tax_table',approved=True)


def test_tax_salary_and_bonus_are_not_mixed(native_db):
    db=native_db;setup(db)
    add(db,'PAY.TaxTable',[{'TaxTableId':2,'TaxGroupRef':1,'Title':'bonus','Date':'2026-03-21','TaxType':2}])
    add(db,'PAY.TaxTableItem',[{'TaxTableItemId':2,'TaxTableRef':2,'FromAmount':0,'ToAmount':1000,'Rate':20}]);db.commit()
    project_native(db,1)
    tables=list(db.scalars(select(Record).where(Record.kind=='tax_table')))
    for table in tables:run_operation(db,1,'payroll_calendar_tax','approve_tax_table',{'record_id':table.id},1)
    payload={'on_date':'2026-04-01','taxable_amount':'100'}
    assert run_operation(db,1,'payroll_calendar_tax','tax_preview',payload)['metrics'][1]['value']=='10.0000'
    assert run_operation(db,1,'payroll_calendar_tax','tax_preview',{**payload,'tax_scope':'bonus'})['metrics'][1]['value']=='20.0000'


def test_calendar_and_person_leave_latest_balance(native_db):
    db=native_db;setup(db)
    add(db,'PAY.Personnel',[{'PersonnelId':10,'PartyRef':3}])
    add(db,'PAY.Leave',[{'LeaveId':1,'PersonnelRef':10,'Date':'2026-04-01','SystemRemainder':100,'UserRemainder':90}]);db.commit();project_native(db,1)
    person=find(db,'payroll_calendar_tax','personnel').person_id
    assert run_operation(db,1,'payroll_calendar_tax','calendar_lookup',{'solar_year':1405,'month':1})['metrics'][0]['value']=='31'
    assert run_operation(db,1,'payroll_calendar_tax','leave_balance',{'person_id':person,'on_date':'2026-05-01'})['metrics'][0]['value']=='90'
    with pytest.raises(ApiError):run_operation(db,1,'payroll_calendar_tax','calendar_lookup',{'solar_year':1406,'month':1})


def test_revoked_statement_and_disposed_asset_are_inactive(native_db):
    db=native_db;setup(db);edit(db,'CNT.Status',{'ConfirmationState':3});edit(db,'AST.Asset',{'State':3});db.commit();project_native(db,1)
    statement=find(db,'contracting','statement');asset=find(db,'fixed_assets','asset')
    assert statement.status==asset.status=='inactive'
    with pytest.raises(ApiError):run_operation(db,1,'contracting','certificate_preview',{'record_id':statement.id})
    with pytest.raises(ApiError):run_operation(db,1,'fixed_assets','depreciation_preview',{'record_id':asset.id,'from_date':'2026-01-01','to_date':'2026-01-10'})


def test_native_layer_cannot_be_allocated_twice(native_db):
    db=native_db;setup(db);project_native(db,1)
    layer=find(db,'inventory_trace_cost','receipt_layer')
    with pytest.raises(ApiError):create(db,'inventory_trace_cost','receipt_layer',warehouse_document_line_id=layer.data['warehouse_document_line_id'],warehouse_id=layer.data['warehouse_id'],product_id=layer.product_id,quantity=1)


def test_api_authorization_and_tenant_boundary(native_db,monkeypatch):
    from fastapi import FastAPI,Request
    from fastapi.responses import JSONResponse
    from fastapi.testclient import TestClient
    from adapters.api.v1.advanced_plugins import router
    from adapters.db.session import get_db
    from app.core.auth_dependency import get_current_user
    db=native_db;setup(db);project_native(db,1)
    class Owner:
        def get_user_id(self):return 1
        def is_superadmin(self):return False
        def is_business_owner(self,bid):return bid==1
        def can_access_business(self,bid):return bid==1
    def auth(request:Request):
        if request.headers.get('authorization')!='TestOnly':raise ApiError('UNAUTHORIZED','test auth required',http_status=401)
        return Owner()
    app=FastAPI();app.include_router(router)
    app.dependency_overrides[get_current_user]=auth;app.dependency_overrides[get_db]=lambda:db
    monkeypatch.setattr('app.core.permissions.get_current_user',lambda request,db:auth(request))
    @app.exception_handler(ApiError)
    async def handler(request,exc):return JSONResponse(status_code=exc.status_code,content={'error':'denied'})
    with TestClient(app) as client:
        assert client.get('/advanced-plugins/business/1').status_code==401
        assert client.get('/advanced-plugins/business/2',headers={'authorization':'TestOnly'}).status_code==403
        assert client.get('/advanced-plugins/business/1',headers={'authorization':'TestOnly'}).status_code==200
        response=client.post('/advanced-plugins/business/1/fixed_assets/records/asset',headers={'authorization':'TestOnly'},json={'title':'x','cost':'100','business_id':2})
        assert response.status_code==400


def test_payroll_date_change_requires_recalculation_for_dated_tax(monkeypatch):
    from app.services import payroll_service as svc
    run=SimpleNamespace(run_date=date(2026,4,1),extra_info={'advanced_tax_applied':{'table_id':1}})
    monkeypatch.setattr(svc,'_ensure_plugin',lambda *a:None)
    monkeypatch.setattr(svc,'_get_or_create_settings',lambda *a:None)
    monkeypatch.setattr(svc,'_get_run_row',lambda *a:run)
    monkeypatch.setattr(svc,'_ensure_run_editable',lambda *a:None)
    monkeypatch.setattr(svc,'_run_to_dict',lambda *a:{})
    monkeypatch.setattr('app.services.advanced_plugin_service.settings_row',lambda *a:None)
    with pytest.raises(ApiError) as error:svc.update_run(None,1,1,{'run_date':'2026-05-01'})
    assert error.value.status_code==400
