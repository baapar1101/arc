"""Source-authoritative projection into specialist native records.

Runs inside Projector's existing transaction/business lock. Does not post stock,
GL, notifications or wallet transactions. Source deletes archive, never erase.
"""
from collections import Counter
from datetime import datetime
from decimal import Decimal
from hashlib import sha256
from sqlalchemy import select,or_
from adapters.db.models.advanced_plugins import AdvancedPluginRecord as Record,AdvancedPluginSetting as Setting
from adapters.db.models.sepidar_live_import import SepidarImportRow
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.services.advanced_plugin_catalog import MODULES,SOURCE,PARENTS
from app.services.advanced_plugin_service import licensed,number,day,TOP
from app.services.sepidar_native_service import NativeConversionError,fingerprint


def value(row,key,default=None):
    if key in row:return row[key]
    key=key.lower()
    return next((v for k,v in row.items() if k.lower()==key),default)


class AdvancedProjector:
    def __init__(self,p):
        self.p,self.db,self.bid=p,p.db,p.bid
        self.records=list(self.db.scalars(select(Record).where(Record.business_id==self.bid)))
        self.existing={(r.plugin_code,r.identity):r for r in self.records}
        self.warehouse_lines={}
        self.summary={}

    def native(self,table,ref,*,required=False):
        if ref in (None,0,'0',''):return None
        mapping=self.p.maps.get((table,str(ref)))
        if not mapping:
            if required:raise NativeConversionError(f'Unresolved specialist native reference: {table}/{ref}')
            return None
        return mapping.target_id

    def normalize(self,code,table,row,definition):
        kind,key,mapping=definition
        fields={};data={}
        for target,source in mapping.items():
            item=value(row,source)
            if item is None:continue
            if target=='status':data['source_state']=item;continue
            if target in {'product_id','person_id'}:
                item=self.native('INV.Item' if target=='product_id' else 'GNR.Party',item,required=True)
            elif target=='currency_id':
                item=self.p.currency_ids.get(int(item or 1))
                if not item:raise NativeConversionError('Unmapped specialist source currency')
            elif target in {'start_date','end_date'}:item=day(item)
            elif target in {'amount','quantity'}:item=number(item)
            elif target=='method':item={1:'none',2:'straight_line',3:'declining'}.get(item,'needs_review')
            elif target=='tax_scope':item={1:'salary',2:'bonus'}.get(item,'needs_review')
            elif target in {'title','code'}:item=str(item)[:500 if target=='title' else 120]
            if target in TOP:fields[target]=item
            else:data[target]=str(item) if isinstance(item,Decimal) else item
        sid=value(row,key)
        fields.setdefault('title',str(value(row,'Title') or value(row,'Description') or value(row,'Name') or f'{MODULES[code]["kinds"][kind]["label"]} {sid}')[:500])
        fields.setdefault('code',str(sid)[:120])
        fields.setdefault('currency_id',self.p.business.default_currency_id)
        for field in ['FiscalYearRef','VoucherRef','AccountingVoucherRef','SLRef','AccountingSLRef','AssetSLRef','DepreciationSLRef','AccumulatedDepreciationSLRef']:
            ref=value(row,field)
            target='FMK.FiscalYear' if field=='FiscalYearRef' else 'ACC.Voucher' if 'Voucher' in field else 'ACC.Account'
            if ref is not None:data.setdefault('native_links',{})[field]={'source_id':ref,'target_id':self.native(target,ref),'table':target}
        if kind=='tax_table':data.update(tax_type='progressive')
        if kind=='personnel' and fields.get('person_id'):
            person=self.p.targets['persons'][fields['person_id']]
            fields['title']=' '.join(filter(None,[person.first_name,person.last_name])) or f'پرسنل {sid}'
        if kind in {'calendar','daily_hours'}:
            fields['title']=f'{MODULES[code]["kinds"][kind]["label"]} {data.get("solar_year", "")} / {data.get("month", "")}'
            # Keep exact source time units. Never reinterpret HHMM as minutes.
            data['source_time_unit']='sepidar_raw; verify before using for time arithmetic'
        if table=='PAY.Leave' and value(row,'UserRemainder') is not None:
            data['system_minutes']=data.get('minutes');data['minutes']=value(row,'UserRemainder')
        if table=='SLS.PriceNoteItem':
            data['can_change_fee']=value(row,'CanChangeInvoiceFee')
            data['can_change_discount']=value(row,'CanChangeInvoiceDiscount')
        status='active' if value(row,'IsActive',True) is not False else 'inactive'
        if table=='AST.Asset' and value(row,'State',1)!=1:status='inactive'
        if table=='CNT.Status' and value(row,'ConfirmationState')==3:status='inactive'
        if table=='CNT.Guarantee' and value(row,'State')==2:status='inactive'
        if table=='CNT.Contract' and value(row,'CancelDate'):status='inactive'
        return kind,fields,data,status

    def inventory(self):
        for line,document in self.db.execute(select(WarehouseDocumentLine,WarehouseDocument).join(WarehouseDocument).where(WarehouseDocument.business_id==self.bid)):
            table=(document.extra_info or {}).get('sepidar',{}).get('table')
            sid=(line.extra_info or {}).get('sepidar_source_id')
            if table in {'INV.InventoryReceipt','INV.InventoryDelivery'} and sid is not None:
                self.warehouse_lines[(table+'Item',str(sid))]=(line,document)

    def run_module(self,code,setting):
        definitions=SOURCE[code]
        conditions=[(SepidarImportRow.source_schema+'.'+SepidarImportRow.source_table).in_(list(definitions))]
        if code in {'fixed_assets','contracting'}:
            conditions.append(SepidarImportRow.source_schema==('AST' if code=='fixed_assets' else 'CNT'))
        rows=self.db.scalars(select(SepidarImportRow).where(SepidarImportRow.business_id==self.bid,SepidarImportRow.is_deleted.is_(False),or_(*conditions)).order_by(SepidarImportRow.id)).all()
        seen=set();by_source={};pending=[];counts=Counter();changes=Counter()
        for source in rows:
            table=source.source_schema+'.'+source.source_table
            definition=definitions.get(table)
            if not definition:
                # Ancillary histories stay browseable without pretending a generic
                # row is a complete contract/asset transaction implementation.
                definition=('source_event','',{})
            kind,key,mapping=definition;row=source.payload
            sid=value(row,key) if key else source.source_key
            if sid is None:raise NativeConversionError(f'Missing specialist source identity: {table}/{key}')
            sid=str(sid);source_id=(table,sid)
            if source_id in by_source:raise NativeConversionError(f'Duplicate specialist identity: {table}/{sid}')
            identity=sha256(f'{self.p.setting.database_name}\0{table}\0{sid}'.encode()).hexdigest()
            record=self.existing.get((code,identity));new=record is None
            if new:
                record=Record(business_id=self.bid,plugin_code=code,kind=kind,identity=identity,title='',data={},source_database=self.p.setting.database_name,source_table=table,source_key=sid,source_deleted=False)
                self.db.add(record);self.existing[code,identity]=record
            seen.add(identity);by_source[source_id]=record
            kind,fields,data,status=self.normalize(code,table,row,definition)
            pending.append((record,kind,fields,data,status,source,row,new))
        # Stable IDs for all parents, independent of source scan order.
        self.db.flush()
        last_depreciation={}
        for record,kind,fields,data,status,source,row,new in pending:
            if record.source_table=='AST.DepreciationItem' and value(row,'CostPartRef') is not None and value(row,'CalculationDate'):
                key=str(value(row,'CostPartRef'));calculated=day(value(row,'CalculationDate'))
                last_depreciation[key]=max(calculated,last_depreciation.get(key,calculated))
        if code=='inventory_trace_cost':
            if not self.p.setting.operations_enabled:raise NativeConversionError('Specialist tracing requires native warehouse operations')
            self.inventory()
        for record,kind,fields,data,status,source,row,new in pending:
            table=record.source_table
            if table=='AST.CostPart' and record.source_key in last_depreciation:
                data['last_calculated_on']=str(last_depreciation[record.source_key])
            parent=PARENTS.get(table)
            fields['parent_id']=None
            if parent:
                ref=value(row,parent[0])
                if ref not in (None,0,'0',''):
                    target=by_source.get((parent[1],str(ref)))
                    if not target:raise NativeConversionError(f'Unresolved specialist parent: {table}/{record.source_key}')
                    fields['parent_id']=target.id
            if table=='SLS.PriceNoteItem':
                header=by_source.get(('SLS.PriceNote',str(value(row,'PriceNoteRef'))))
                source_header=next((s.payload for s in rows if s.source_table=='PriceNote' and str(value(s.payload,'PriceNoteID'))==str(value(row,'PriceNoteRef'))),None)
                if not header or not source_header:raise NativeConversionError('Specialist price header unavailable')
                fields['start_date']=day(value(source_header,'Date'))
                windows=[s for s in rows if s.source_table=='PriceNoteItemDiscount' and str(value(s.payload,'PriceNoteItemRef'))==record.source_key]
                if windows:data['needs_review']='Source scheduled discount requires explicit reviewed rule; base rule not automatically applied'
                if windows:
                    data.pop('needs_review',None)
                    data['has_scheduled_discounts']=True
                product=self.p.targets['products'].get(fields.get('product_id'))
                if product:fields['title']=product.name[:500]
            if code=='inventory_trace_cost' and table in {'INV.InventoryReceiptItem','INV.InventoryDeliveryItem'}:
                native=self.warehouse_lines.get((table,record.source_key))
                if not native:raise NativeConversionError('Native warehouse line missing for specialist trace')
                line,document=native;kind='receipt_layer' if line.movement=='in' else 'issue'
                fields.update(start_date=document.document_date,quantity=line.quantity,product_id=line.product_id)
                product=self.p.targets['products'].get(line.product_id)
                if product:fields['title']=f'{product.name} — {document.code}'[:500]
                trace=value(row,'TracingRef');trace_record=by_source.get(('INV.Tracing',str(trace))) if trace not in (None,0,'0','') else None
                if trace not in (None,0,'0','') and not trace_record:raise NativeConversionError('Unresolved source inventory trace')
                cost=(line.extra_info or {}).get('source_price')
                fields['amount']=number(cost)
                data.update(warehouse_document_line_id=line.id,warehouse_document_id=document.id,
                    warehouse_id=line.warehouse_id,fiscal_year_id=document.fiscal_year_id,trace_id=trace_record.id if trace_record else None,
                    source_tracing_ref=trace,unit_cost=format(number(cost)/line.quantity,'f') if cost is not None else None)
            payload_hash=fingerprint({'source':source.payload,'fields':fields,'data':data,'kind':kind,'status':status})
            if new or record.source_hash!=payload_hash or record.source_deleted:
                for name in TOP:setattr(record,name,fields.get(name))
                record.kind=kind;record.data=data;record.status=status;record.source_deleted=False
                record.source_payload=source.payload;record.source_hash=payload_hash;record.revision=(record.revision or 0)+1
                changes['created' if new else 'updated']+=1
            else:changes['unchanged']+=1
            counts[kind]+=1
        for record in self.records:
            if record.plugin_code==code and record.source_database==self.p.setting.database_name and record.identity not in seen and not record.source_deleted:
                record.source_deleted=True;record.status='archived';record.revision+=1;changes['archived']+=1
        setting.last_synced_at=datetime.utcnow();setting.sync_summary={'counts':dict(counts),**{k:changes[k] for k in ['created','updated','unchanged','archived']}}
        self.summary[code]=setting.sync_summary

    def run(self):
        for code in MODULES:
            if not licensed(self.db,self.bid,code):continue
            setting=self.db.scalars(select(Setting).where(Setting.business_id==self.bid,Setting.plugin_code==code)).first()
            if not setting or not setting.enabled or not setting.sync_enabled:continue
            self.run_module(code,setting)
        self.db.flush()
        return self.summary
