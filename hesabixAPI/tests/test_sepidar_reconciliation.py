"""Real PostgreSQL tests on the guarded disposable native fixture."""
from copy import deepcopy
from decimal import Decimal
import pytest
from sqlalchemy import select, func
from tests.test_sepidar_native_projection import native_db,seed,edit,count
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.sepidar_live_import import SepidarImportRow, SepidarImportRun, SepidarNativeMap, SepidarReconciliationAudit
from app.services.sepidar_native_service import project_native, NativeConversionError, fingerprint
from app.services.sepidar_reconciliation_service import build_plan,apply_reviewed_plan

def add_raw(db,table,payload,key):
    schema,name=table.split('.')
    db.add(SepidarImportRow(business_id=1,source_schema=schema,source_table=name,source_key=key,payload=payload,content_hash=fingerprint(payload)))

def remove(db,table):
    schema,name=table.split('.')
    for row in db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_schema==schema,SepidarImportRow.source_table==name)):
        row.is_deleted=True

def deletion_case(db):
    seed(db)
    add_raw(db,'ACC.Voucher',{'VoucherId':51,'Number':21,'FiscalYearRef':4,'Date':'2026-10-22'},'keeper')
    add_raw(db,'ACC.VoucherItem',{'VoucherItemId':3,'VoucherRef':51,'AccountSLRef':2,'Debit':30,'Credit':0},'keeper1')
    add_raw(db,'ACC.VoucherItem',{'VoucherItemId':4,'VoucherRef':51,'AccountSLRef':2,'Debit':0,'Credit':30},'keeper2')
    db.commit();project_native(db,1)
    retired=db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.source_table=='SLS.Invoice')).one().target_id
    for table in ('SLS.Invoice','SLS.InvoiceItem'):remove(db,table)
    for row in db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_schema=='ACC')):
        if row.source_table=='Voucher' and row.payload.get('VoucherId')==50:row.is_deleted=True
        if row.source_table=='VoucherItem' and row.payload.get('VoucherRef')==50:row.is_deleted=True
    db.commit()
    return retired

def test_reviewed_delete_archives_rows_keeps_ids_and_repeat_is_noop(native_db):
    db=native_db;did=deletion_case(db)
    with pytest.raises(NativeConversionError,match='Source identity missing'):project_native(db,1)
    plan,_=build_plan(db,1)
    with db.begin_nested():result=apply_reviewed_plan(db,1,1,plan['plan_hash'],'Owner confirmed intentional deletion')
    db.commit()
    assert result['changed'] and db.get(Document,did).document_type=='sepidar_archived'
    assert db.get(Document,did).is_proforma
    from app.services.invoice_service import invoice_document_to_dict
    from app.core.responses import ApiError
    with pytest.raises(ApiError,match='SEPIDAR_SOURCE_ARCHIVED'):
        invoice_document_to_dict(db,db.get(Document,did))
    assert count(db,Document)==2 and count(db,DocumentLine)==2 and count(db,InvoiceItemLine)==0
    assert len(list(db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.retired_at.is_not(None)))))==2
    audit=db.scalars(select(SepidarReconciliationAudit)).one()
    assert len(audit.before_images['document_lines'])==2
    assert Decimal(audit.before_images['document_lines'][0]['debit'])==100
    assert not apply_reviewed_plan(db,1,1,plan['plan_hash'],'same approval')['changed']
    summary=project_native(db,1)
    assert all(s['created']==s['updated']==0 for s in summary['entities'].values())
    assert count(db,SepidarReconciliationAudit)==1

def test_resurrected_source_requires_review_and_keeps_retired_identity(native_db):
    db=native_db;did=deletion_case(db);plan,_=build_plan(db,1)
    apply_reviewed_plan(db,1,1,plan['plan_hash'],'reviewed');db.commit()
    for row in db.scalars(select(SepidarImportRow)):row.is_deleted=False
    db.commit()
    with pytest.raises(NativeConversionError,match='reappeared'):project_native(db,1)
    assert db.get(Document,did).document_type=='sepidar_archived' and count(db,Document)==2

def test_replacement_preserves_native_invoice_and_changes_original_ledger_once(native_db):
    db=native_db;seed(db);project_native(db,1);did=db.scalars(select(Document.id)).one()
    remove(db,'ACC.Voucher');remove(db,'ACC.VoucherItem')
    add_raw(db,'ACC.Voucher',{'VoucherId':60,'Number':22,'FiscalYearRef':4,'Date':'2026-10-22'},'new')
    add_raw(db,'ACC.VoucherItem',{'VoucherItemId':5,'VoucherRef':60,'AccountSLRef':2,'DLRef':7,'Debit':120,'Credit':0},'new1')
    add_raw(db,'ACC.VoucherItem',{'VoucherItemId':6,'VoucherRef':60,'AccountSLRef':2,'Debit':0,'Credit':120},'new2')
    db.commit();edit(db,'SLS.Invoice',0,VoucherRef=60,Price='120',NetPrice='120')
    edit(db,'SLS.InvoiceItem',0,Fee='60',Price='120',NetPrice='120')
    plan,_=build_plan(db,1)
    assert plan['replacements'][0]['document_id']==did and not plan['retire_document_ids']
    apply_reviewed_plan(db,1,1,plan['plan_hash'],'reviewed replacement');db.commit()
    assert count(db,Document)==1 and count(db,DocumentLine)==2
    assert db.scalar(select(func.sum(DocumentLine.debit)))==120
    assert db.get(Document,did).extra_info['totals']['net']==120
    assert db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.source_table=='ACC.Voucher',SepidarNativeMap.source_id=='60')).one().target_id==did
    summary=project_native(db,1)
    assert all(s['created']==s['updated']==0 for s in summary['entities'].values())

def test_owner_and_current_preview_required(native_db):
    db=native_db;deletion_case(db);plan,_=build_plan(db,1)
    with pytest.raises(NativeConversionError,match='owner'):apply_reviewed_plan(db,1,999,plan['plan_hash'],'reviewed')
    edit(db,'GNR.Party',0,Name='new source snapshot')
    with pytest.raises(NativeConversionError,match='preview changed'):apply_reviewed_plan(db,1,1,plan['plan_hash'],'reviewed')
    assert count(db,SepidarReconciliationAudit)==0

def test_downstream_failure_rolls_back_archive_and_audit(native_db):
    db=native_db;did=deletion_case(db)
    # Keep the retained voucher unbalanced: the entire reviewed operation must fail.
    row=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='VoucherItem',SepidarImportRow.source_key=='keeper1')).one()
    row.payload={**row.payload,'Debit':31};row.content_hash=fingerprint(row.payload);db.commit()
    plan,_=build_plan(db,1)
    with pytest.raises(NativeConversionError,match='not balanced'):
        with db.begin_nested():apply_reviewed_plan(db,1,1,plan['plan_hash'],'reviewed')
    db.rollback()
    assert db.get(Document,did).document_type=='invoice_sales'
    assert count(db,DocumentLine)==4 and count(db,SepidarReconciliationAudit)==0
    assert not db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.retired_at.is_not(None))).first()

def test_native_allocation_blocks_deletion_without_silently_removing_cash(native_db):
    db=native_db;did=deletion_case(db)
    keeper=db.scalars(select(Document).where(Document.id!=did)).one()
    keeper.extra_info={**keeper.extra_info,'sepidar':{**keeper.extra_info['sepidar'],'settlement_allocations':[{'invoice_id':did,'amount':'10'}]}}
    db.commit()
    with pytest.raises(NativeConversionError,match='payment allocations'):build_plan(db,1)
    assert count(db,DocumentLine)==4

def test_partial_source_snapshot_cannot_be_reviewed(native_db):
    db=native_db;deletion_case(db)
    db.add(SepidarImportRun(business_id=1,status='failed',tables_total=3,tables_completed=2));db.commit()
    with pytest.raises(NativeConversionError,match='finished complete'):build_plan(db,1)
    assert count(db,SepidarReconciliationAudit)==0

def test_later_source_posting_attaches_original_voucher_to_existing_invoice(native_db):
    db=native_db;seed(db)
    edit(db,'SLS.Invoice',0,VoucherRef=None)
    # Keep another voucher so that required source ledger is available.
    project_native(db,1)
    invoice=db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.source_table=='SLS.Invoice')).one()
    did=invoice.target_id
    assert db.scalar(select(func.count()).select_from(DocumentLine).where(DocumentLine.document_id==did))==0
    add_raw(db,'ACC.Voucher',{'VoucherId':60,'Number':22,'FiscalYearRef':4,'Date':'2026-10-22'},'posted')
    add_raw(db,'ACC.VoucherItem',{'VoucherItemId':5,'VoucherRef':60,'AccountSLRef':2,'DLRef':7,'Debit':100,'Credit':0},'posted1')
    add_raw(db,'ACC.VoucherItem',{'VoucherItemId':6,'VoucherRef':60,'AccountSLRef':2,'Debit':0,'Credit':100},'posted2')
    db.commit();edit(db,'SLS.Invoice',0,VoucherRef=60)
    previous_count=count(db,Document)
    project_native(db,1)
    assert count(db,Document)==previous_count
    assert db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.source_table=='ACC.Voucher',SepidarNativeMap.source_id=='60')).one().target_id==did
    assert db.scalar(select(func.count()).select_from(DocumentLine).where(DocumentLine.document_id==did))==2
    summary=project_native(db,1)
    assert all(s['created']==s['updated']==0 for s in summary['entities'].values())
