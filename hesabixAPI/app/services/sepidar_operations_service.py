"""Source-authoritative warehouse/cost/payment projection, without new GL posts."""
from collections import Counter, defaultdict
from datetime import datetime
from decimal import Decimal

from sqlalchemy import delete, select,func,case,cast
from sqlalchemy.dialects.postgresql import JSONB
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services.sepidar_native_service import NativeConversionError, decimal, money, source_date, fingerprint


def quantity(value):
    amount = decimal(value)
    if amount != amount.quantize(Decimal('.000001')):
        raise NativeConversionError('Source inventory precision exceeds native precision')
    return amount


def source_warehouse_stock(db,business_id,product_ids,day,warehouse_id=None):
    query=select(WarehouseDocumentLine.product_id,func.sum(case((WarehouseDocumentLine.movement=='in',WarehouseDocumentLine.quantity),else_=-WarehouseDocumentLine.quantity))).join(WarehouseDocument).where(
        WarehouseDocument.business_id==business_id,WarehouseDocument.status=='posted',WarehouseDocument.document_date<=day,
        WarehouseDocumentLine.product_id.in_(product_ids),cast(WarehouseDocument.extra_info,JSONB)['sepidar']['managed'].astext=='true')
    if warehouse_id is not None:query=query.where(WarehouseDocumentLine.warehouse_id==warehouse_id)
    return dict(db.execute(query.group_by(WarehouseDocumentLine.product_id)).all())


def source_stock_values(db,business_id,day):
    """Exact source-priced value only. A missing source price is not zero."""
    from adapters.db.models.fiscal_year import FiscalYear
    fy=db.scalars(select(FiscalYear).where(FiscalYear.business_id==business_id,FiscalYear.start_date<=day,FiscalYear.end_date>=day)).first()
    if not fy:return {}
    values={}
    for line,doc in db.execute(select(WarehouseDocumentLine,WarehouseDocument).join(WarehouseDocument).where(
        WarehouseDocument.business_id==business_id,WarehouseDocument.fiscal_year_id==fy.id,WarehouseDocument.status=='posted',
        WarehouseDocument.document_date<=day,cast(WarehouseDocument.extra_info,JSONB)['sepidar']['managed'].astext=='true')):
        info=line.extra_info or {}
        if info.get('sepidar_bridge')=='carry_reset':continue
        key=(line.product_id,line.warehouse_id)
        value,complete=values.get(key,(Decimal(0),True))
        cost=info.get('source_price')
        if cost is None:complete=False
        else:value+=decimal(cost)*(1 if line.movement=='in' else -1)
        values[key]=(value,complete)
    return values


def report_available_stock(db,business_id,pids,day,warehouse_id):
    """Batch equivalent of invoice stock plus non-mirrored manual movements."""
    from sqlalchemy.orm import aliased
    from app.services.invoice_service import get_financial_stock_bulk,SUPPORTED_INVOICE_TYPES
    stocks=get_financial_stock_bulk(db,business_id,pids,day,warehouse_id)
    source=aliased(Document)
    query=select(WarehouseDocumentLine.product_id,func.sum(case((WarehouseDocumentLine.movement=='in',WarehouseDocumentLine.quantity),else_=-WarehouseDocumentLine.quantity))).join(WarehouseDocument).outerjoin(source,
        (source.id==WarehouseDocument.source_document_id)&(source.business_id==business_id)).where(
        WarehouseDocument.business_id==business_id,WarehouseDocument.status=='posted',WarehouseDocument.document_date<=day,
        WarehouseDocumentLine.product_id.in_(pids),
        func.coalesce(cast(WarehouseDocument.extra_info,JSONB)['sepidar']['managed'].astext,'false')!='true',
        ~func.lower(func.coalesce(WarehouseDocument.source_type,'')).in_(['invoice','opening_balance']),
        (source.id.is_(None))|(~source.document_type.in_([*SUPPORTED_INVOICE_TYPES,'opening_balance'])))
    if warehouse_id is not None:query=query.where(WarehouseDocumentLine.warehouse_id==warehouse_id)
    for pid,qty in db.execute(query.group_by(WarehouseDocumentLine.product_id)):
        stocks[pid]=stocks.get(pid,Decimal(0))+qty
    return stocks


def settlement_allocations(data, target):
    """Sepidar fnInvoiceRemaining counts registered allocations, not IsSettled.

    IsSettled=False is also used for valid allocations! Entity codes come from
    RPA_PartySettlementManagement_lookups.sql. Reject unsupported allocations
    rather than guessing that unallocated cash paid an invoice.
    """
    groups=defaultdict(list)
    for row in data['RPA.PartyAccountSettlementItem']:
        groups[row['PartyAccountSettlementRef']].append(row)
    result=defaultdict(list)
    for header in data['RPA.PartyAccountSettlement']:
        rows=groups[header['PartyAccountSettlementID']]
        debits=sorted((r for r in rows if r.get('DebitEntityType') is not None),key=lambda r:r['PartyAccountSettlementItemID'])
        credits=sorted((r for r in rows if r.get('CreditEntityType') is not None),key=lambda r:r['PartyAccountSettlementItemID'])
        if sum((money(r['Amount']) for r in debits),Decimal(0)) != sum((money(r['Amount']) for r in credits),Decimal(0)):
            raise NativeConversionError('Unbalanced source settlement allocation')
        debit_remaining=[money(r['Amount']) for r in debits]
        for credit in credits:
            remaining=money(credit['Amount'])
            if remaining < 0:
                raise NativeConversionError('Negative source settlement allocation')
            for index,debit in enumerate(debits):
                allocated=min(remaining,debit_remaining[index])
                if not allocated:continue
                pair=(debit['DebitEntityType'],credit['CreditEntityType'])
                if pair == (1,23):
                    invoice=target('SLS.Invoice',debit['DebitEntityRef'])
                    payment_key=('RPA.ReceiptHeader',credit['CreditEntityRef'])
                elif pair == (2,28):
                    receipts={r['InventoryReceiptID']:r for r in data['INV.InventoryReceipt']}
                    receipt=receipts.get(credit['CreditEntityRef'])
                    if not receipt or not receipt.get('BasePurchaseInvoiceRef'):
                        raise NativeConversionError('Vendor settlement needs a linked source purchase invoice')
                    invoice=target('INV.InventoryPurchaseInvoice',receipt['BasePurchaseInvoiceRef'])
                    payment_key=('RPA.PaymentHeader',debit['DebitEntityRef'])
                else:
                    raise NativeConversionError(f'Unsupported settlement entity pair: {pair}')
                party=target('GNR.Party',header['PartyRef'])
                if invoice.extra_info.get('person_id') != party.id:
                    raise NativeConversionError('Settlement invoice party mismatch')
                result[payment_key].append({'invoice_id':invoice.id,'amount':str(allocated),
                    'currency_ref':header['CurrencyRef'],'source_settlement_id':header['PartyAccountSettlementID'],
                    'source_debit_id':debit['PartyAccountSettlementItemID'],'source_credit_id':credit['PartyAccountSettlementItemID']})
                remaining-=allocated;debit_remaining[index]-=allocated
            if remaining:
                raise NativeConversionError('Unallocated source settlement remainder')
    for rows in result.values():
        rows.sort(key=lambda r:(r['source_settlement_id'],r['source_debit_id'],r['source_credit_id']))
    return result


class OperationsProjector:
    def __init__(self, projector):
        self.p=projector;self.db=projector.db;self.data=projector.data
        self.items={r['ItemID']:r for r in self.data['INV.Item']}
        self.invoice_lines={}
        self.costs=defaultdict(list)
        for line in self.db.scalars(select(InvoiceItemLine).join(Document).where(Document.business_id==self.p.bid)):
            info=line.extra_info or {}
            if info.get('sepidar_source'):
                self.invoice_lines[info['sepidar_source'],info['sepidar_row_id']]=line

    def bank_references(self):
        self.detail_by_dl={}
        dls={r['DLId']:r for r in self.data['ACC.DL']}
        for row in self.data['RPA.BankAccount']:
            bank,_=self.p.upsert('RPA.BankAccount',row['BankAccountId'],BankAccount,row,{
                'business_id':self.p.bid,'code':f"SPD-B-{row['BankAccountId']}",
                'name':dls.get(row.get('DlRef'),{}).get('Title') or f"سپیدار {row['BankAccountId']}",
                'account_number':row.get('AccountNo'),'owner_name':row.get('Owner'),
                'currency_id':self.p.currency_ids[int(row['CurrencyRef'])],'is_active':True,'is_default':False})
            self.detail_by_dl[row.get('DlRef')]=('bank_account_id',bank.id)
        for row in self.data['RPA.Cash']:
            cash,_=self.p.upsert('RPA.Cash',row['CashId'],CashRegister,row,{'business_id':self.p.bid,
                'code':f"SPD-C-{row['CashId']}",'name':row['Title'],
                'currency_id':self.p.currency_ids[int(row['CurrencyRef'])],'is_active':True,'is_default':False})
            self.detail_by_dl[row.get('DlRef')]=('cash_register_id',cash.id)
        # Include opening vouchers, bank fees and cheque banking entries too;
        # attaching a detail must not create another accounting line.
        for line in self.db.scalars(select(DocumentLine).join(Document).where(Document.business_id==self.p.bid)):
            info=dict(line.extra_info or {})
            if 'sepidar_voucher_item_id' not in info:continue
            detail=self.detail_by_dl.get(info.get('sepidar_dl_ref'))
            if detail:setattr(line,detail[0],detail[1])
            if line.person_id:info['person_id']=line.person_id
            line.extra_info=info

    def payments(self):
        allocations=settlement_allocations(self.data,self.p.target)
        headers={(table,r[key]):r for table,key in [('RPA.ReceiptHeader','ReceiptHeaderId'),('RPA.PaymentHeader','PaymentHeaderId')] for r in self.data[table]}
        if set(allocations)-set(headers):
            raise NativeConversionError('Settlement receipt reference missing')
        for key,rows in allocations.items():
            header=headers[key]
            if header['State']!=2 or self.p.party_by_dl.get(header.get('DlRef')) is None:
                raise NativeConversionError('Settlement refers to unavailable receipt')
            if any(r['currency_ref']!=header['CurrencyRef'] for r in rows):
                raise NativeConversionError('Settlement currency mismatch')
            if sum((money(r['amount']) for r in rows),Decimal(0))>money(header['TotalAmount']):
                raise NativeConversionError('Settlement exceeds source receipt amount')
        linked=Counter(r.get('VoucherRef') for t in ('RPA.ReceiptHeader','RPA.PaymentHeader') for r in self.data[t] if r.get('VoucherRef'))
        managed_receipts=set();invoice_links=defaultdict(list)
        for table,key,doctype,prefix in [('RPA.ReceiptHeader','ReceiptHeaderId','receipt','RC'),('RPA.PaymentHeader','PaymentHeaderId','payment','PY')]:
            for row in self.data[table]:
                sid=row[key];vid=row.get('VoucherRef');voucher=self.p.vouchers.get(vid)
                ledger=self.p.target('ACC.Voucher',vid) if voucher else None
                # Keep original voucher date/year and postings intact; header date
                # remains available in operational metadata when they differ.
                reuse=ledger if ledger and linked[vid]==1 and not ledger.extra_info['sepidar'].get('invoice_table') and ledger.document_date==source_date(row['Date']) and ledger.fiscal_year_id==self.p.target('FMK.FiscalYear',row['FiscalYearRef']).id else None
                existing=self.p.target(table,sid) if (table,str(sid)) in self.p.maps else reuse
                settlements=allocations.get((table,sid),[])
                methods=[]
                for child in (['RPA.ReceiptDraft','RPA.ReceiptCheque'] if doctype=='receipt' else ['RPA.PaymentDraft','RPA.PaymentCheque','RPA.PaymentChequeOther']):
                    parent='ReceiptHeaderRef' if doctype=='receipt' else 'PaymentHeaderRef'
                    for method in self.data[child]:
                        if method.get(parent)==sid:
                            methods.append({'table':child,**{k:method.get(k) for k in ['Amount','BankAccountRef','ReceiptChequeRef','Date','State','Type'] if k in method}})
                methods.sort(key=fingerprint)
                extra=self.p.meta(existing,operational_table=table,operational_id=sid,source_date=row['Date'],
                    source_state=row['State'],ledger_document_id=ledger.id if ledger else None,
                    source_total_amount=str(money(row['TotalAmount'])),settlement_allocations=settlements,payment_methods=methods)
                extra['person_id']=self.p.party_by_dl.get(row.get('DlRef'))
                doc,_=self.p.upsert(table,sid,Document,{'row':row,'methods':methods,'allocations':settlements}, {
                    'business_id':self.p.bid,'code':f"SPD-{prefix}-{row['FiscalYearRef']}-{row['Number']}-{sid}",
                    'document_date':ledger.document_date if reuse else source_date(row['Date']),
                    'fiscal_year_id':ledger.fiscal_year_id if reuse else self.p.target('FMK.FiscalYear',row['FiscalYearRef']).id,
                    'currency_id':self.p.currency_ids[int(row['CurrencyRef'])],'document_type':doctype,
                    'created_by_user_id':self.p.business.owner_id,'description':row.get('Description'),
                    'is_proforma':row['State']==4,'extra_info':extra},reuse=reuse)
                managed_receipts.add(doc.id)
                for allocation in settlements:
                    invoice=self.p.targets['documents'][allocation['invoice_id']]
                    if invoice.extra_info.get('person_id')!=extra['person_id']:
                        raise NativeConversionError('Receipt/invoice party mismatch')
                    invoice_links[invoice.id].append(doc.id)
                if ledger:
                    person_account=self.p.target('ACC.Account',row['AccountSlRef']).id if row.get('AccountSlRef') else None
                    for line in self.db.scalars(select(DocumentLine).where(DocumentLine.document_id==ledger.id)):
                        info=dict(line.extra_info or {})
                        if line.person_id:
                            info['person_id']=line.person_id
                        direction = line.credit > 0 if doctype=='receipt' else line.debit > 0
                        is_counterparty=bool(line.person_id and line.person_id==extra['person_id'] and direction and (person_account is None or person_account==line.account_id))
                        info['sepidar_payment_role']='person' if is_counterparty else 'account'
                        detail=self.detail_by_dl.get(info.get('sepidar_dl_ref'))
                        if detail:
                            setattr(line,detail[0],detail[1])
                            info['transaction_type']='bank' if detail[0]=='bank_account_id' else 'cash'
                        line.extra_info=info
        for (table,_),mapping in self.p.maps.items():
            if table in ('SLS.Invoice','INV.InventoryPurchaseInvoice','SLS.ReturnedInvoice'):
                doc=self.p.targets['documents'][mapping.target_id]
                extra=dict(doc.extra_info or {});links=dict(extra.get('links') or {})
                ids=[sid for sid in links.get('receipt_payment_document_ids',[]) if sid not in managed_receipts]
                links['receipt_payment_document_ids']=sorted(set(ids+invoice_links[doc.id]))
                extra['links']=links;doc.extra_info=extra

    def replace_warehouse(self,table,sid,payload,fields,lines):
        # A projection version upgrades metadata/line links without changing ID.
        doc,changed=self.p.upsert(table,sid,WarehouseDocument,{'version':1,'source':payload,'lines':lines},fields)
        if changed:
            self.db.execute(delete(WarehouseDocumentLine).where(WarehouseDocumentLine.warehouse_document_id==doc.id))
            self.db.add_all([WarehouseDocumentLine(warehouse_document_id=doc.id,**line) for line in lines])
        return doc

    def inventory(self):
        source_balances=defaultdict(Decimal);movement_balances=defaultdict(Decimal)
        latest_dates={}
        self.unpriced=0;self.priced=0
        for row in self.data['INV.ItemStockSummary']:
            if row.get('Order')==1:
                source_balances[row['FiscalYearRef'],row['StockRef'],row['ItemRef']]+=quantity(row['Quantity'])
        for name,idkey in [('InventoryReceipt','InventoryReceiptID'),('InventoryDelivery','InventoryDeliveryID')]:
            table='INV.'+name;by_header=defaultdict(list)
            for row in self.data[table+'Item']:by_header[row[name+'Ref']].append(row)
            for header in self.data[table]:
                sid=header[idkey];year=self.p.target('FMK.FiscalYear',header['FiscalYearRef'])
                day=source_date(header['Date']);stock=self.p.target('INV.Stock',header['StockRef'])
                if not year.start_date<=day<=year.end_date:raise NativeConversionError('Warehouse date outside fiscal year')
                latest_dates[header['FiscalYearRef']]=max(day,latest_dates.get(header['FiscalYearRef'],day))
                lines=[];linked_invoices=set()
                for row in sorted(by_header[sid],key=lambda r:r[name+'ItemID']):
                    qty=quantity(row['Quantity'])
                    if qty<=0:raise NativeConversionError('Nonpositive source warehouse quantity')
                    incoming=(name=='InventoryReceipt')!=bool(row.get('IsReturn',header['IsReturn']))
                    product=self.p.target('INV.Item',row['ItemRef'])
                    raw_cost=row.get('Price');cost=(decimal(raw_cost)+decimal(row.get('TransportPrice'))+decimal(row.get('OtherCostsAmount'))) if raw_cost is not None else None
                    self.unpriced+=cost is None;self.priced+=cost is not None
                    info={'sepidar_source_id':row[name+'ItemID'],'source_price':str(cost) if cost is not None else None,
                          'cost_price':float(cost/qty) if cost is not None else None,'pricing_complete':cost is not None,
                          'source_cost_components':{key:row.get(key) for key in ('Price','TransportPrice','OtherCostsAmount')},
                          'source_tracing_ref':row.get('TracingRef'),'description':row.get('Description')}
                    source_line=None
                    for field,target_table in [('BaseInvoiceItem','SLS.InvoiceItem'),('BaseReturnedInvoiceItem','SLS.ReturnedInvoiceItem'),('BasePurchaseInvoiceItemRef','INV.InventoryPurchaseInvoiceItem')]:
                        if row.get(field) is not None:
                            source_line=self.invoice_lines.get((target_table,row[field]))
                            if not source_line:raise NativeConversionError('Unresolved warehouse invoice item')
                            break
                    if source_line:
                        info['invoice_item_line_id']=source_line.id;linked_invoices.add(source_line.document_id)
                        self.costs[source_line.id].append((qty,cost))
                    lines.append({'product_id':product.id,'warehouse_id':stock.id,'movement':'in' if incoming else 'out','quantity':qty,'extra_info':info})
                    movement_balances[header['FiscalYearRef'],header['StockRef'],row['ItemRef']]+=qty*(1 if incoming else -1)
                invoice_id=next(iter(linked_invoices)) if len(linked_invoices)==1 else None
                directions={line['movement'] for line in lines}
                doc_type='receipt' if directions=={'in'} else 'issue' if directions=={'out'} else 'adjustment'
                self.replace_warehouse(table,sid,header,{'business_id':self.p.bid,'code':f"SPD-W-{name}-{sid}",
                    'document_date':day,'fiscal_year_id':year.id,'status':'posted',
                    'doc_type':doc_type,
                    'warehouse_id_from':stock.id if 'out' in directions else None,
                    'warehouse_id_to':stock.id if 'in' in directions else None,
                    'source_type':'invoice' if invoice_id else 'sepidar','source_document_id':invoice_id,
                    'created_by_user_id':self.p.business.owner_id,'extra_info':self.p.meta(table=table,id=sid,source_type=header['Type'],
                        source_return=header['IsReturn'],ledger_document_id=self.p.target('ACC.Voucher',header['AccountingVoucherRef']).id if header.get('AccountingVoucherRef') in self.p.vouchers else None)},lines)
        # Native physical stock is cumulative across years; Sepidar carries its
        # opening balance forward. Explicit quantity-only resets avoid doubling.
        years=sorted(self.data['FMK.FiscalYear'],key=lambda r:r['StartDate'])
        for index,year in enumerate(years):
            fy=year['FiscalYearId'];buckets=defaultdict(list)
            for source_key in source_balances.keys()|movement_balances.keys():
                if source_key[0]!=fy:continue
                difference=source_balances[source_key]-movement_balances[source_key]
                if difference:buckets['reconciliation',source_key[1]].append((source_key[2],difference))
            if index:
                previous=years[index-1]['FiscalYearId']
                for (sy,stock,item),qty in source_balances.items():
                    if sy==previous and qty:buckets['carry_reset',stock].append((item,-qty))
            # Also update an existing correction to an empty line set after the
            # source discrepancy is resolved. Never leave stale adjustments.
            for (table,sid),mapping in self.p.maps.items():
                if table=='INV.NativeStockBridge' and sid.startswith(f'{fy}:'):
                    _,kind,stock=sid.split(':');buckets.setdefault((kind,int(stock)),[])
            for (kind,stock_id),entries in list(buckets.items()):
                stock=self.p.target('INV.Stock',stock_id);native_year=self.p.target('FMK.FiscalYear',fy)
                lines=[{'product_id':self.p.target('INV.Item',item).id,'warehouse_id':stock.id,'movement':'in' if qty>0 else 'out',
                    'quantity':abs(qty),'extra_info':{'sepidar_bridge':kind,'pricing_complete':False}} for item,qty in sorted(entries) if qty]
                self.replace_warehouse('INV.NativeStockBridge',f'{fy}:{kind}:{stock_id}',{'entries':sorted(entries)},
                    {'business_id':self.p.bid,'code':f'SPD-{kind}-{fy}-{stock_id}','document_date':native_year.start_date if kind=='carry_reset' else latest_dates.get(fy,native_year.start_date),
                     'fiscal_year_id':native_year.id,'status':'posted','doc_type':'adjustment','source_type':'sepidar',
                     'created_by_user_id':self.p.business.owner_id,'extra_info':self.p.meta(kind=kind,quantity_only=True,
                         explanation='Fiscal carry reset' if kind=='carry_reset' else 'Authoritative source stock summary versus source movements')},lines)
                if kind=='reconciliation' and lines:self.p.warnings.append(f'Source stock summary reconciliation: fiscal year {fy}, stock {stock_id}, {len(lines)} items')
        if self.unpriced:self.p.warnings.append(f'Source warehouse lines without assigned cost: {self.unpriced}; no cost fabricated')

    def invoice_costs(self):
        for line in self.invoice_lines.values():
            parts=self.costs.get(line.id,[])
            complete=parts and all(cost is not None for _,cost in parts) and sum(qty for qty,_ in parts)==line.quantity
            line.ledger_line_cogs=sum((cost for _,cost in parts),Decimal(0)) if complete else None
            line.ledger_unit_cogs=(line.ledger_line_cogs/line.quantity).quantize(Decimal('.000001')) if complete else None
            info=dict(line.extra_info or {});info['sepidar_cost_status']='priced' if complete else 'unpriced_or_partial'
            line.extra_info=info
            line.ledger_line_gross_profit=money(info['line_total'])-money(info.get('tax_amount'))-line.ledger_line_cogs if complete else None
            line.ledger_recognition_event='sepidar_pricing' if complete else None
            if complete and line.ledger_recognized_at is None:line.ledger_recognized_at=datetime.now()
            if not complete:line.ledger_recognized_at=None

    def run(self):
        self.bank_references()
        self.payments()
        self.inventory()
        self.invoice_costs()
