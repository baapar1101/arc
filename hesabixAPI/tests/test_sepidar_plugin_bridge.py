from datetime import datetime,timedelta
from decimal import Decimal
import pytest
from sqlalchemy import select,func
from tests.test_sepidar_native_projection import native_db,seed
from tests.test_sepidar_operations import add
from adapters.db.models.sepidar_live_import import SepidarImportSetting,SepidarNativeMap,SepidarImportRow
from adapters.db.models.marketplace import MarketplacePlugin,MarketplacePluginPlan,BusinessPlugin
from adapters.db.models.payroll import PayrollSettings
from adapters.db.models.distribution import DistributionTerritory,DistributionRoute
from adapters.db.models.price_list import PriceList,PriceItem
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.document import Document
from adapters.db.models.customer_club import CustomerClubSettings,CustomerClubBalance,CustomerClubLedger,CustomerClubInvoiceSnapshot
from app.services.sepidar_native_service import Projector,project_native,NativeConversionError,fingerprint
from app.services.sepidar_plugin_service import coverage,PluginProjector,assert_plugin_entity_editable
from app.core.responses import ApiError


def edit(db,table,change):
    schema,name=table.split('.')
    row=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_schema==schema,SepidarImportRow.source_table==name).order_by(SepidarImportRow.id)).first()
    row.payload={**row.payload,**change};row.content_hash=fingerprint(row.payload)


def license(db,code):
    plugin=MarketplacePlugin(code=code,name=code,is_active=True);db.add(plugin);db.flush()
    plan=MarketplacePluginPlan(plugin_id=plugin.id,period='yearly',currency_id=1,price=0);db.add(plan);db.flush()
    db.add(BusinessPlugin(business_id=1,plugin_id=plugin.id,plan_id=plan.id,status='active',starts_at=datetime.utcnow()-timedelta(days=1)))
    db.flush()


def source(db,licensed=True):
    seed(db)
    db.scalars(select(SepidarImportSetting)).one().plugins_enabled=True
    if licensed:
        for code in ['payroll','distribution','customer_club']:license(db,code)
    add(db,'PAY.PayrollConfiguration',[{'PayrollConfigurationId':1,'EmployeeInsurancePercent':'7','EmployerInsurancePercent':'20','UnemploymentInsurancePercent':'3','PaymentAccountRef':2,'SocialSecurityAccountRef':2}])
    add(db,'PAY.TaxTable',[{'TaxTableId':1,'Date':'2023-03-21','TaxGroupRef':1}])
    add(db,'DST.AreaAndPath',[{'AreaAndPathId':-5,'Type':0,'Code':'0','Title':'root'},
        {'AreaAndPathId':1,'Type':1,'Code':'1','Title':'region','IsActive':True},
        {'AreaAndPathId':2,'Type':2,'Code':'2','Title':'route','IsActive':True,'ParentAreaAndPathRef':1}])
    add(db,'SLS.PriceNote',[{'PriceNoteID':1,'Title':'standard','Date':'2026-01-01'}])
    add(db,'SLS.SaleType',[{'SaleTypeId':1,'Title':'Retail'}])
    add(db,'SLS.PriceNoteItem',[{'PriceNoteItemID':1,'PriceNoteRef':1,'ItemRef':5,'UnitRef':1,'CurrencyRef':1,'SaleTypeRef':1,'Fee':'50','Discount':'0','AdditionRate':'0'}])
    db.add(CustomerClubSettings(business_id=1,enabled=True,earn_mode='percent_basis',amount_basis='net',percent_of_basis=Decimal('1'),rounding_mode='floor',min_basis_amount=0,require_customer_person_type=False))
    db.commit()


def test_plugins_project_repeat_without_duplicate_or_new_gl(native_db):
    db=native_db;source(db)
    summary=project_native(db,1)
    assert summary['plugins']['payroll_settings']==1 and summary['plugins']['price_items']==1
    assert summary['plugins']['distribution_regions']==summary['plugins']['distribution_routes']==1
    settings=db.scalars(select(PayrollSettings)).one()
    assert settings.extra_settings['statutory_rules']['insurance']['employee_rate_percent']=='7'
    assert 'tax' not in settings.extra_settings['statutory_rules']
    assert len(settings.extra_settings['sepidar']['reference_catalog']['TaxTable'])==1
    assert db.scalars(select(PriceItem)).one().price==50
    assert db.scalar(select(func.count()).select_from(DocumentLine))==2
    maps=[(m.id,m.target_id) for m in db.scalars(select(SepidarNativeMap))]
    entries=db.scalar(select(func.count()).select_from(CustomerClubLedger))
    assert entries==1
    repeat=project_native(db,1)
    assert all(s['created']==s['updated']==0 for s in repeat['entities'].values())
    assert [(m.id,m.target_id) for m in db.scalars(select(SepidarNativeMap))]==maps
    assert db.scalar(select(func.count()).select_from(CustomerClubLedger))==entries


def test_live_updates_prices_regions_and_insurance_keep_local_tax(native_db):
    db=native_db;source(db);project_native(db,1)
    price=db.scalars(select(PriceItem)).one();pid=price.id
    settings=db.scalars(select(PayrollSettings)).one()
    extra=dict(settings.extra_settings);rules=dict(extra['statutory_rules']);rules['tax']={'mode':'flat_percent','flat_rate_percent':15};extra['statutory_rules']=rules;settings.extra_settings=extra
    edit(db,'SLS.PriceNoteItem',{'Fee':'65'})
    edit(db,'PAY.PayrollConfiguration',{'EmployeeInsurancePercent':'8'})
    db.commit();project_native(db,1)
    assert db.get(PriceItem,pid).price==65
    assert settings.extra_settings['statutory_rules']['insurance']['employee_rate_percent']=='8'
    assert settings.extra_settings['statutory_rules']['tax']['flat_rate_percent']==15


def test_missing_license_does_not_create_paid_plugin_rows(native_db):
    db=native_db;source(db,licensed=False);summary=project_native(db,1)
    assert summary['plugins']['payroll_settings']==summary['plugins']['distribution_routes']==0
    assert db.scalar(select(func.count()).select_from(CustomerClubLedger))==0
    assert db.scalar(select(func.count()).select_from(PayrollSettings))==0
    assert summary['plugins']['price_items']==1  # Native catalog, not a paid plugin.


def test_sale_type_title_live_update_keeps_price_identity(native_db):
    db=native_db;source(db);project_native(db,1)
    pid=db.scalars(select(PriceItem.id)).one()
    edit(db,'SLS.SaleType',{'Title':'Wholesale'});db.commit()
    project_native(db,1)
    assert db.get(PriceItem,pid).tier_name=='SPD-1 Wholesale'
    repeat=project_native(db,1)
    assert repeat['entities']['SLS.PriceNoteItem']['updated']==0


def test_unresolved_sale_type_fails_without_inventing_tier(native_db):
    db=native_db;source(db)
    edit(db,'SLS.PriceNoteItem',{'SaleTypeRef':999});db.commit()
    with pytest.raises(NativeConversionError):project_native(db,1)
    assert db.scalar(select(func.count()).select_from(PriceItem))==0


def test_unsupported_price_rule_removes_stale_price_and_deletes_are_idempotent(native_db):
    db=native_db;source(db);project_native(db,1)
    edit(db,'SLS.PriceNoteItem',{'Discount':'10'});db.commit()
    summary=project_native(db,1)
    assert summary['plugins']['price_skipped']==1
    assert db.scalar(select(func.count()).select_from(PriceItem))==0
    row=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_schema=='DST',SepidarImportRow.source_table=='AreaAndPath').order_by(SepidarImportRow.id.desc())).first();row.is_deleted=True;db.commit()
    project_native(db,1)
    route=db.scalars(select(DistributionRoute)).one();assert not route.is_active
    project_native(db,1);assert not route.is_active
    row.is_deleted=False;db.commit();project_native(db,1);assert route.is_active


def test_bad_reference_rolls_back_entire_bridge(native_db):
    db=native_db;source(db);edit(db,'SLS.PriceNoteItem',{'ItemRef':999});db.commit()
    with pytest.raises(NativeConversionError):project_native(db,1)
    assert db.scalar(select(func.count()).select_from(PayrollSettings))==0
    assert db.scalar(select(func.count()).select_from(Document))==0


def test_source_managed_price_cannot_be_locally_edited(native_db):
    db=native_db;source(db);project_native(db,1)
    price_list=db.scalars(select(PriceList)).one()
    with pytest.raises(ApiError):assert_plugin_entity_editable(db,1,'price_lists',price_list.id)
    assert_plugin_entity_editable(db,2,'price_lists',price_list.id)
    report=coverage(db,1)
    assert len(report['plugins'])==3 and len(report['missing_features'])>=4


def test_cancelled_source_invoice_reverses_loyalty_only_once(native_db):
    db=native_db;source(db);project_native(db,1)
    edit(db,'SLS.Invoice',{'State':2});db.commit()
    project_native(db,1)
    assert db.scalars(select(CustomerClubBalance)).one().balance_points==0
    assert db.scalars(select(CustomerClubInvoiceSnapshot)).one().accrued_points==0
    count=db.scalar(select(func.count()).select_from(CustomerClubLedger))
    project_native(db,1)
    assert db.scalar(select(func.count()).select_from(CustomerClubLedger))==count
