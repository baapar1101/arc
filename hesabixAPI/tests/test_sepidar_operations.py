from copy import deepcopy
from decimal import Decimal
import pytest
from sqlalchemy import select,func
from tests.test_sepidar_native_projection import native_db,seed,edit,count
from adapters.db.models.sepidar_live_import import SepidarImportRow,SepidarImportSetting,SepidarNativeMap
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services.sepidar_native_service import project_native,fingerprint,NativeConversionError
from app.services.warehouse_service import get_physical_stock
from app.services.invoice_service import _sum_receipt_doc_payments_for_invoice


def add(db,table,rows):
    schema,name=table.split('.')
    offset=db.scalar(select(func.count()).select_from(SepidarImportRow).where(SepidarImportRow.source_schema==schema,SepidarImportRow.source_table==name))
    for i,payload in enumerate(rows):
        db.add(SepidarImportRow(business_id=1,source_schema=schema,source_table=name,source_key=f'op:{offset+i}',payload=payload,content_hash=fingerprint(payload)))


def operations(db):
    seed(db)
    db.scalars(select(SepidarImportSetting)).one().operations_enabled=True
    add(db,'ACC.DL',[{'DLId':8,'Code':'200','Title':'صندوق'}])
    add(db,'ACC.Voucher',[{'VoucherId':51,'Number':21,'FiscalYearRef':4,'Date':'2026-10-22','State':1}])
    add(db,'ACC.VoucherItem',[{'VoucherItemId':3,'VoucherRef':51,'AccountSLRef':2,'DLRef':8,'Debit':'100','Credit':0},
                              {'VoucherItemId':4,'VoucherRef':51,'AccountSLRef':2,'DLRef':7,'Debit':0,'Credit':'100'}])
    add(db,'RPA.Cash',[{'CashId':1,'Title':'صندوق','CurrencyRef':1,'DlRef':8}])
    add(db,'RPA.ReceiptHeader',[{'ReceiptHeaderId':30,'Number':1,'FiscalYearRef':4,'Date':'2026-10-22','CurrencyRef':1,
                                'DlRef':7,'State':2,'TotalAmount':'100','VoucherRef':51}])
    add(db,'RPA.PartyAccountSettlement',[{'PartyAccountSettlementID':1,'PartyRef':3,'State':1,'CurrencyRef':1}])
    add(db,'RPA.PartyAccountSettlementItem',[
        {'PartyAccountSettlementItemID':1,'PartyAccountSettlementRef':1,'DebitEntityType':1,'DebitEntityRef':10,'Amount':'30','IsSettled':False},
        {'PartyAccountSettlementItemID':2,'PartyAccountSettlementRef':1,'CreditEntityType':23,'CreditEntityRef':30,'Amount':'30','IsSettled':False}])
    add(db,'INV.InventoryReceipt',[{'InventoryReceiptID':10,'Number':1,'Date':'2026-10-22','StockRef':1,'Type':1,'IsReturn':False,'FiscalYearRef':4}])
    add(db,'INV.InventoryReceiptItem',[{'InventoryReceiptItemID':1,'InventoryReceiptRef':10,'Quantity':'10','Price':'500','ItemRef':5,'IsReturn':False}])
    add(db,'INV.InventoryDelivery',[{'InventoryDeliveryID':20,'Number':2,'Date':'2026-10-22','StockRef':1,'Type':1,'IsReturn':False,'FiscalYearRef':4}])
    add(db,'INV.InventoryDeliveryItem',[{'InventoryDeliveryItemID':2,'InventoryDeliveryRef':20,'Quantity':'2','Price':'60','ItemRef':5,'IsReturn':False,'BaseInvoiceItem':1}])
    add(db,'INV.ItemStockSummary',[{'FiscalYearRef':4,'StockRef':1,'ItemRef':5,'Order':1,'Quantity':'8'}])
    db.commit()


def receipt(db):return db.scalars(select(Document).where(Document.document_type=='receipt')).one()


def test_operations_reconcile_stock_cost_partial_payment_and_keep_gl_once(native_db):
    db=native_db;operations(db);project_native(db,1)
    line=db.scalars(select(InvoiceItemLine)).one()
    assert get_physical_stock(db,1,line.product_id)==8
    from app.services.invoice_service import _compute_available_stock,get_financial_stock_bulk
    from datetime import date
    assert _compute_available_stock(db,1,line.product_id,None,date(2026,10,23))==8
    assert get_financial_stock_bulk(db,1,[line.product_id])[line.product_id]==8
    from app.services.invoice_service import invoice_document_to_dict
    response=invoice_document_to_dict(db,db.get(Document,line.document_id),include_tags=False,persist_link_cleanup=False)
    assert response['profit_calculation_context']=='sepidar_priced' and response['gross_profit']==40
    assert line.ledger_line_cogs==60 and line.ledger_line_gross_profit==40
    assert count(db,DocumentLine)==4  # original two vouchers only
    assert _sum_receipt_doc_payments_for_invoice(receipt(db),line.document_id,via_person_line=False)==30
    ids={(m.source_table,m.source_id):(m.target_table,m.target_id) for m in db.scalars(select(SepidarNativeMap))}
    summary=project_native(db,1)
    assert all(s['created']==s['updated']==0 for s in summary['entities'].values())
    assert ids=={(m.source_table,m.source_id):(m.target_table,m.target_id) for m in db.scalars(select(SepidarNativeMap))}
    assert count(db,DocumentLine)==4 and count(db,WarehouseDocumentLine)==2
    from app.services.warehouse_reports_service import get_inventory_valuation_report
    value=get_inventory_valuation_report(db,1,as_of_date='2026-10-23')
    assert value['total_value']==440 and value['items'][0]['valuation_complete'] is True


def test_source_cost_removed_and_settlement_changed_update_existing_targets(native_db):
    db=native_db;operations(db);project_native(db,1)
    line=db.scalars(select(InvoiceItemLine)).one();rid=receipt(db).id
    r=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='InventoryDeliveryItem')).one()
    r.payload={**r.payload,'Price':None}
    for s in db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='PartyAccountSettlementItem')):s.payload={**s.payload,'Amount':'40'}
    db.commit();project_native(db,1)
    assert db.get(InvoiceItemLine,line.id).ledger_line_cogs is None
    assert receipt(db).id==rid
    assert _sum_receipt_doc_payments_for_invoice(receipt(db),line.document_id,via_person_line=False)==40
    assert count(db,DocumentLine)==4
    from app.services.warehouse_reports_service import get_inventory_valuation_report
    value=get_inventory_valuation_report(db,1,as_of_date='2026-10-23')
    assert value['total_value'] is None and value['items'][0]['value'] is None


def test_source_allocation_deleted_clears_old_native_invoice_link(native_db):
    db=native_db;operations(db);project_native(db,1)
    for row in db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table.in_(['PartyAccountSettlement','PartyAccountSettlementItem']))):row.is_deleted=True
    db.commit();project_native(db,1)
    line=db.scalars(select(InvoiceItemLine)).one()
    assert db.get(Document,line.document_id).extra_info['links']['receipt_payment_document_ids']==[]
    assert _sum_receipt_doc_payments_for_invoice(receipt(db),line.document_id,via_person_line=False)==0


def test_shared_receipt_applies_only_explicit_amount_per_invoice(native_db):
    db=native_db;operations(db)
    original=db.scalars(select(SepidarImportRow.payload).where(SepidarImportRow.source_table=='Invoice')).one()
    add(db,'SLS.Invoice',[{**original,'InvoiceId':11,'Number':2,'VoucherRef':None,'Price':'50','NetPrice':'50'}])
    original_line=db.scalars(select(SepidarImportRow.payload).where(SepidarImportRow.source_table=='InvoiceItem')).one()
    add(db,'SLS.InvoiceItem',[{**original_line,'InvoiceItemID':2,'InvoiceRef':11,'Quantity':'1','Price':'50','NetPrice':'50'}])
    credit=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='PartyAccountSettlementItem',SepidarImportRow.source_key=='op:1')).one()
    credit.payload={**credit.payload,'Amount':'50'}
    add(db,'RPA.PartyAccountSettlementItem',[{'PartyAccountSettlementItemID':3,'PartyAccountSettlementRef':1,'DebitEntityType':1,'DebitEntityRef':11,'Amount':'20'}])
    db.commit();project_native(db,1)
    ids={m.source_id:m.target_id for m in db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.source_table=='SLS.Invoice'))}
    assert _sum_receipt_doc_payments_for_invoice(receipt(db),ids['10'],via_person_line=False)==30
    assert _sum_receipt_doc_payments_for_invoice(receipt(db),ids['11'],via_person_line=False)==20
    assert count(db,DocumentLine)==4


def test_live_quantity_change_updates_same_warehouse_document(native_db):
    db=native_db;operations(db);project_native(db,1)
    ids=list(db.scalars(select(WarehouseDocument.id)))
    row=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='InventoryReceiptItem')).one()
    row.payload={**row.payload,'Quantity':'12','Price':'600'}
    stock=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='ItemStockSummary')).one()
    stock.payload={**stock.payload,'Quantity':'10'}
    db.commit();project_native(db,1)
    assert ids==list(db.scalars(select(WarehouseDocument.id)))
    assert get_physical_stock(db,1,db.scalars(select(InvoiceItemLine.product_id)).one())==10
    assert count(db,DocumentLine)==4


def test_payment_header_date_does_not_move_original_voucher_date(native_db):
    from datetime import date
    from app.services.receipt_payment_service import document_to_dict
    db=native_db;operations(db)
    row=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='ReceiptHeader')).one()
    row.payload={**row.payload,'Date':'2026-10-21'};db.commit();project_native(db,1)
    doc=receipt(db)
    assert doc.document_date==date(2026,10,21)
    ledger=db.get(Document,doc.extra_info['sepidar']['ledger_document_id'])
    assert ledger.document_date==date(2026,10,22) and ledger.id!=doc.id
    response=document_to_dict(db,doc)
    assert response['total_amount']==100 and len(response['person_lines'])==1
    assert count(db,DocumentLine)==4


def test_fiscal_opening_carry_is_not_counted_twice(native_db):
    db=native_db;operations(db)
    add(db,'FMK.FiscalYear',[{'FiscalYearId':1,'Title':'1404','StartDate':'2025-03-21','EndDate':'2026-03-20'}])
    add(db,'INV.InventoryReceipt',[{'InventoryReceiptID':11,'Number':2,'Date':'2025-03-21','StockRef':1,'Type':4,'IsReturn':False,'FiscalYearRef':1}])
    add(db,'INV.ItemStockSummary',[{'FiscalYearRef':1,'StockRef':1,'ItemRef':5,'Order':1,'Quantity':'10'}])
    add(db,'INV.InventoryReceiptItem',[{'InventoryReceiptItemID':3,'InventoryReceiptRef':11,'Quantity':'10','Price':'500','ItemRef':5,'IsReturn':False}])
    db.commit();project_native(db,1)
    line=db.scalars(select(InvoiceItemLine)).one()
    assert get_physical_stock(db,1,line.product_id)==8
    assert count(db,WarehouseDocument)==4


def test_unbalanced_settlement_rolls_back_warehouse_and_payment_projection(native_db):
    db=native_db;operations(db)
    row=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='PartyAccountSettlementItem',SepidarImportRow.source_key=='op:0')).one()
    row.payload={**row.payload,'Amount':'31'};db.commit()
    with pytest.raises(NativeConversionError,match='Unbalanced source settlement'):project_native(db,1)
    assert count(db,Document)==count(db,WarehouseDocument)==0


def test_local_profit_backfill_cannot_overwrite_source_cost(native_db):
    from app.services.invoice_profit_ledger_service import apply_recognized_profit_to_invoice_lines
    db=native_db;operations(db);project_native(db,1)
    line=db.scalars(select(InvoiceItemLine)).one()
    assert apply_recognized_profit_to_invoice_lines(db,1,line.document_id,recognition_event='warehouse_document_posting') is False
    assert line.ledger_line_cogs==60


def test_vendor_settlement_links_only_explicit_purchase_amount(native_db):
    db=native_db;operations(db)
    add(db,'INV.InventoryPurchaseInvoice',[{'InventoryPurchaseInvoiceID':40,'Number':1,'Date':'2026-10-22','FiscalYearRef':4,
        'CurrencyRef':1,'VendorDLRef':7,'TotalPrice':'100','TotalNetPrice':'100','AccountingVoucherRef':None}])
    add(db,'INV.InventoryPurchaseInvoiceItem',[{'InventoryPurchaseInvoiceItemID':40,'InventoryPurchaseInvoiceRef':40,'ItemRef':5,
        'Quantity':'2','Fee':'50','Price':'100','NetPrice':'100'}])
    stock=db.scalars(select(SepidarImportRow).where(SepidarImportRow.source_table=='InventoryReceipt')).one()
    stock.payload={**stock.payload,'BasePurchaseInvoiceRef':40}
    add(db,'RPA.PaymentHeader',[{'PaymentHeaderId':41,'Number':2,'Date':'2026-10-22','FiscalYearRef':4,'CurrencyRef':1,'DlRef':7,'State':2,'TotalAmount':'100','VoucherRef':None}])
    add(db,'RPA.PartyAccountSettlement',[{'PartyAccountSettlementID':2,'PartyRef':3,'State':1,'CurrencyRef':1}])
    add(db,'RPA.PartyAccountSettlementItem',[
        {'PartyAccountSettlementItemID':3,'PartyAccountSettlementRef':2,'DebitEntityType':2,'DebitEntityRef':41,'Amount':'25'},
        {'PartyAccountSettlementItemID':4,'PartyAccountSettlementRef':2,'CreditEntityType':28,'CreditEntityRef':10,'Amount':'25'}])
    db.commit();project_native(db,1)
    purchase=db.scalars(select(Document).where(Document.document_type=='invoice_purchase')).one()
    payment=db.scalars(select(Document).where(Document.document_type=='payment')).one()
    assert purchase.extra_info['links']['receipt_payment_document_ids']==[payment.id]
    assert _sum_receipt_doc_payments_for_invoice(payment,purchase.id,via_person_line=False)==25


def test_source_managed_payments_and_warehouses_reject_local_mutations(native_db):
    from app.core.responses import ApiError
    from app.services.receipt_payment_service import delete_receipt_payment,update_receipt_payment
    from app.services.warehouse_service import update_warehouse_document,cancel_warehouse_document
    db=native_db;operations(db);project_native(db,1)
    with pytest.raises(ApiError):delete_receipt_payment(db,receipt(db).id)
    with pytest.raises(ApiError):update_receipt_payment(db,receipt(db).id,1,{})
    wh=db.scalars(select(WarehouseDocument)).first()
    with pytest.raises(ApiError):update_warehouse_document(db,1,wh.id,1,{})
    with pytest.raises(ApiError):cancel_warehouse_document(db,1,wh.id,1)
