"""Explicitly reviewed source deletions; no generated GL, cash or external sends.

Keep native document identities and complete before-images. Retired financial
documents have no active ledger/invoice rows; warehouse documents are cancelled.
Unknown future deletions and resurrected source identities still stop conversion.
The caller must hold the import business lock and commit the whole operation.
"""
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
import json
from sqlalchemy import delete, select, text, tuple_
from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.models.customer_club import CustomerClubInvoiceSnapshot, CustomerClubBalance, CustomerClubLedger
from adapters.db.models.sepidar_live_import import SepidarImportSetting, SepidarImportRow, SepidarImportRun, SepidarNativeMap, SepidarReconciliationAudit
from app.services.sepidar_native_service import SOURCE_IDS, OPERATION_IDS, INVOICES, NativeConversionError, fingerprint, source_date, Projector


def serialized(obj):
    return json.loads(json.dumps({c.name:getattr(obj,c.name) for c in obj.__table__.columns},default=str))


def build_plan(db, business_id):
    setting=db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id==business_id)).one()
    if setting.included_schemas or setting.included_tables:
        raise NativeConversionError('Reconciliation requires a complete source snapshot')
    latest=db.scalars(select(SepidarImportRun).where(SepidarImportRun.business_id==business_id).order_by(SepidarImportRun.id.desc())).first()
    if latest and (latest.status=='running' or not latest.tables_total or latest.tables_completed!=latest.tables_total):
        raise NativeConversionError('Reconciliation requires a finished complete source snapshot')
    ids={**SOURCE_IDS, **(OPERATION_IDS if setting.operations_enabled else {})}
    data=defaultdict(list)
    needed=set(ids)|{'RPA.PartyAccountSettlementItem'}
    for schema,table,payload in db.execute(select(SepidarImportRow.source_schema,SepidarImportRow.source_table,SepidarImportRow.payload).where(
        SepidarImportRow.business_id==business_id,SepidarImportRow.is_deleted.is_(False),
        tuple_(SepidarImportRow.source_schema,SepidarImportRow.source_table).in_([tuple(t.split('.')) for t in needed]))):
        data[schema+'.'+table].append(payload)
    source_markers=list(db.execute(select(SepidarImportRow.source_schema,SepidarImportRow.source_table,
        SepidarImportRow.source_key,SepidarImportRow.content_hash,SepidarImportRow.is_deleted).where(SepidarImportRow.business_id==business_id)))
    live={table:{str(r[key]) for r in data[table]} for table,key in ids.items()}
    mappings=list(db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.business_id==business_id,
        SepidarNativeMap.database_name==setting.database_name,SepidarNativeMap.retired_at.is_(None))))
    maps={(m.source_table,m.source_id):m for m in mappings}
    missing=[m for m in mappings if m.source_table in ids and m.source_id not in live[m.source_table]]
    supported={'ACC.Voucher',*(s[0] for s in INVOICES),'INV.InventoryReceipt','INV.InventoryDelivery'}
    if any(m.source_table not in supported for m in missing):
        raise NativeConversionError('Source master-data deletion requires a separate review')
    document_ids={m.target_id for m in missing if m.target_table=='documents'}
    warehouse_ids={m.target_id for m in missing if m.target_table=='warehouse_documents'}
    replacements=[];preserved=set()
    vouchers={r['VoucherId']:r for r in data['ACC.Voucher']}
    references=[(s[0],s[1],s[7]) for s in INVOICES if s[7]]
    if setting.operations_enabled:
        references += [('RPA.ReceiptHeader','ReceiptHeaderId','VoucherRef'),('RPA.PaymentHeader','PaymentHeaderId','VoucherRef')]
    for table,key,voucher_key in references:
        for row in data[table]:
            old=maps.get((table,str(row[key])))
            if not old or old.target_id not in document_ids:continue
            vid=row.get(voucher_key)
            if not vid or vid not in vouchers:
                raise NativeConversionError('Surviving source document needs an available replacement voucher')
            if table.startswith('RPA.') and (source_date(row['Date'])!=source_date(vouchers[vid]['Date'])
                or row['FiscalYearRef']!=vouchers[vid]['FiscalYearRef'] or int(row.get('CurrencyRef') or 1)!=1):
                raise NativeConversionError('Replacement bank voucher needs matching source date, fiscal year and base currency')
            vm=maps.get(('ACC.Voucher',str(vid)))
            if vm and vm.target_id!=old.target_id:
                raise NativeConversionError('Replacement voucher already belongs to another native document')
            if old.target_id in preserved:
                raise NativeConversionError('Ambiguous replacement source aliases')
            preserved.add(old.target_id)
            reference_fields=({'operational_table':table,'operational_id':str(row[key])} if table.startswith('RPA.')
                              else {'invoice_table':table,'invoice_id':str(row[key])})
            replacements.append({'document_id':old.target_id,**reference_fields,'voucher_id':str(vid)})
    retired=document_ids-preserved
    missing_ids={m.id for m in missing}
    if any(m.target_table=='documents' and m.target_id in retired and m.id not in missing_ids for m in mappings):
        raise NativeConversionError('A deleted financial document still has a live native alias')
    docs=list(db.scalars(select(Document).where(Document.business_id==business_id)))
    warehouse_docs=list(db.scalars(select(WarehouseDocument).where(WarehouseDocument.business_id==business_id)))
    for doc in docs:
        allocations=(doc.extra_info or {}).get('sepidar',{}).get('settlement_allocations',[])
        if any(a.get('invoice_id') in retired for a in allocations):
            raise NativeConversionError('Deleted invoice has native payment allocations; review required')
    source_invoice_ids={int(m.source_id) for m in missing if m.source_table=='SLS.Invoice'}
    if any(r.get('DebitEntityType')==1 and r.get('DebitEntityRef') in source_invoice_ids for r in data['RPA.PartyAccountSettlementItem']):
        raise NativeConversionError('Deleted invoice still has live source settlements')
    for doc in warehouse_docs:
        ledger=(doc.extra_info or {}).get('sepidar',{}).get('ledger_document_id')
        if doc.status=='posted' and doc.id not in warehouse_ids and (doc.source_document_id in retired or ledger in retired):
            raise NativeConversionError('Deleted financial document still has a posted warehouse dependency')
    # Preserve FK histories, but do not silently invalidate unrelated live plugins.
    foreign_keys=db.execute(text("""SELECT ns.nspname schema_name,rel.relname table_name,attr.attname column_name
       FROM pg_constraint con JOIN pg_class rel ON rel.oid=con.conrelid
       JOIN pg_namespace ns ON ns.oid=rel.relnamespace
       JOIN pg_attribute attr ON attr.attrelid=con.conrelid AND attr.attnum=con.conkey[1]
       WHERE con.contype='f' AND con.confrelid='documents'::regclass AND array_length(con.conkey,1)=1""")).mappings().all()
    allowed={'document_lines','invoice_item_lines','customer_club_invoice_snapshots','customer_club_ledger'}
    quote=db.get_bind().dialect.identifier_preparer.quote
    for fk in foreign_keys:
        if not retired or fk['table_name'] in allowed:continue
        count=db.scalar(text(f"SELECT count(*) FROM {quote(fk['schema_name'])}.{quote(fk['table_name'])} WHERE {quote(fk['column_name'])}=ANY(:ids)"),{'ids':list(retired)})
        if count:raise NativeConversionError('Deleted financial document has another plugin dependency; review required')
    selected=[d for d in docs if d.id in document_ids]
    if len(selected)!=len(document_ids) or any(not (d.extra_info or {}).get('sepidar',{}).get('managed') for d in selected):
        raise NativeConversionError('Reconciliation target is missing or not source managed')
    snapshots={
        'documents':[serialized(d) for d in sorted(selected,key=lambda d:d.id)],
        'document_lines':[serialized(r) for r in db.scalars(select(DocumentLine).where(DocumentLine.document_id.in_(document_ids)).order_by(DocumentLine.id))],
        'invoice_item_lines':[serialized(r) for r in db.scalars(select(InvoiceItemLine).where(InvoiceItemLine.document_id.in_(document_ids)).order_by(InvoiceItemLine.id))],
        'warehouse_documents':[serialized(d) for d in sorted(warehouse_docs,key=lambda d:d.id) if d.id in warehouse_ids],
        'warehouse_document_lines':[serialized(r) for r in db.scalars(select(WarehouseDocumentLine).where(WarehouseDocumentLine.warehouse_document_id.in_(warehouse_ids)).order_by(WarehouseDocumentLine.id))],
        'mappings':[serialized(m) for m in sorted(missing,key=lambda m:m.id)],
        'club_snapshots':[serialized(r) for r in db.scalars(select(CustomerClubInvoiceSnapshot).where(CustomerClubInvoiceSnapshot.document_id.in_(document_ids)).order_by(CustomerClubInvoiceSnapshot.document_id))],
        'club_ledger':[serialized(r) for r in db.scalars(select(CustomerClubLedger).where(CustomerClubLedger.reference_document_id.in_(document_ids)).order_by(CustomerClubLedger.id))],
    }
    club_pids={r['person_id'] for r in snapshots['club_snapshots'] if r['person_id']}
    snapshots['club_balances']=[serialized(r) for r in db.scalars(select(CustomerClubBalance).where(CustomerClubBalance.business_id==business_id,CustomerClubBalance.person_id.in_(club_pids)).order_by(CustomerClubBalance.id))]
    plan={'business_id':business_id,'database_name':setting.database_name,
        'missing':sorted([{'table':m.source_table,'source_id':m.source_id,'map_id':m.id,'target_table':m.target_table,'target_id':m.target_id} for m in missing],key=lambda r:(r['table'],r['source_id'])),
        'retire_document_ids':sorted(retired),'cancel_warehouse_ids':sorted(warehouse_ids),'replacements':sorted(replacements,key=lambda r:r['document_id']),
        'before_hash':fingerprint(snapshots),
        # Exclude last_seen_at: a no-op full snapshot is not a changed approval.
        'source_hash':fingerprint(sorted(tuple(r) for r in source_markers))}
    plan['plan_hash']=fingerprint(plan)
    return plan,snapshots


def apply_reviewed_plan(db,business_id,approved_by_user_id,expected_hash,reason):
    owner=db.get(Business,business_id)
    if not owner or owner.owner_id!=approved_by_user_id:
        raise NativeConversionError('Only the destination business owner can approve reconciliation')
    if not reason.strip():raise NativeConversionError('Reconciliation requires a recorded reason')
    setting=db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id==business_id)).one()
    prior=db.scalars(select(SepidarReconciliationAudit).where(SepidarReconciliationAudit.business_id==business_id,
        SepidarReconciliationAudit.database_name==setting.database_name,SepidarReconciliationAudit.plan_hash==expected_hash)).first()
    if prior:return {'changed':False,'audit_id':prior.id,'summary':prior.summary}
    plan,before=build_plan(db,business_id)
    if plan['plan_hash']!=expected_hash:raise NativeConversionError('Reconciliation preview changed; review the current plan')
    if not plan['missing']:return {'changed':False,'summary':plan}
    audit=SepidarReconciliationAudit(business_id=business_id,database_name=setting.database_name,plan_hash=expected_hash,
        approved_by_user_id=approved_by_user_id,reason=reason,before_images=before,summary=plan)
    db.add(audit);db.flush()
    now=datetime.utcnow()
    for entry in plan['missing']:
        mapping=db.get(SepidarNativeMap,entry['map_id']);mapping.retired_at=now
    for wid in plan['cancel_warehouse_ids']:
        doc=db.get(WarehouseDocument,wid);doc.status='cancelled'
        extra=dict(doc.extra_info or {});extra['sepidar']={**extra.get('sepidar',{}),'retired':True,'reconciliation_audit_id':audit.id}
        doc.extra_info=extra
    for did in plan['retire_document_ids']:
        doc=db.get(Document,did)
        snap=db.get(CustomerClubInvoiceSnapshot,did)
        if snap:
            from app.services.customer_club_service import reverse_customer_club_on_invoice_delete,check_customer_club_plugin_active
            if (snap.accrued_points or snap.redeemed_points) and not check_customer_club_plugin_active(db,business_id):
                raise NativeConversionError('Loyalty history requires an active reviewed club reversal')
            reverse_customer_club_on_invoice_delete(db,did,business_id)
            snap.accrued_points=Decimal(0);snap.redeemed_points=Decimal(0)
        db.execute(delete(DocumentLine).where(DocumentLine.document_id==did))
        db.execute(delete(InvoiceItemLine).where(InvoiceItemLine.document_id==did))
        doc.document_type='sepidar_archived';doc.is_proforma=True
        doc.extra_info={'sepidar':{**(doc.extra_info or {}).get('sepidar',{}),'retired':True,'reconciliation_audit_id':audit.id}}
    for replacement in plan['replacements']:
        existing=db.scalars(select(SepidarNativeMap).where(SepidarNativeMap.business_id==business_id,
            SepidarNativeMap.database_name==setting.database_name,SepidarNativeMap.source_table=='ACC.Voucher',SepidarNativeMap.source_id==replacement['voucher_id'])).first()
        if existing:
            if existing.retired_at or existing.target_id!=replacement['document_id']:
                raise NativeConversionError('Replacement mapping no longer matches reviewed plan')
            existing.source_hash='0'*64
        else:
            db.add(SepidarNativeMap(business_id=business_id,database_name=setting.database_name,source_table='ACC.Voucher',
                source_id=replacement['voucher_id'],target_table='documents',target_id=replacement['document_id'],source_hash='0'*64))
    db.flush()
    # One transaction: all downstream validation, stock bridges, settlements and
    # loyalty deltas must pass before a caller may commit the reconciliation.
    summary=Projector(db,setting).run()
    setting.native_summary=summary;setting.native_last_error=None;setting.last_error=None
    db.flush()
    return {'changed':True,'audit_id':audit.id,'summary':plan,'native_summary':summary}
