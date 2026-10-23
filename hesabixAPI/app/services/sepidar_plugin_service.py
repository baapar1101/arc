"""Source-backed plugin bridges. No credentials, bank sends or external side effects."""
from collections import Counter
from copy import deepcopy
from datetime import datetime
from decimal import Decimal
from sqlalchemy import select,func
from adapters.db.models.marketplace import MarketplacePlugin,BusinessPlugin
from adapters.db.models.sepidar_live_import import SepidarImportRow,SepidarNativeMap,SepidarImportSetting
from adapters.db.models.payroll import PayrollSettings
from adapters.db.models.distribution import DistributionTerritory,DistributionRoute
from adapters.db.models.price_list import PriceList,PriceItem
from app.services.sepidar_native_service import decimal,money,NativeConversionError,fingerprint
from app.core.responses import ApiError


def assert_plugin_entity_editable(db,bid,target_table,target_id):
    imported=db.scalars(select(SepidarNativeMap.id).where(SepidarNativeMap.business_id==bid,
        SepidarNativeMap.target_table==target_table,SepidarNativeMap.target_id==target_id,
        SepidarNativeMap.source_table.in_(['SLS.PriceNote','SLS.PriceNoteItem','DST.AreaAndPath']))).first()
    if imported:
        raise ApiError('SEPIDAR_SOURCE_MANAGED','این اطلاعات از سپیدار همگام می‌شود؛ تغییر را در مبدأ ثبت کنید.',http_status=409)

PLUGIN_TABLES={'DST.AreaAndPath','PAY.PayrollConfiguration','PAY.PayrollCalendar','PAY.DailyHourMinute',
    'PAY.TaxGroup','PAY.TaxTable','PAY.TaxTableItem','SLS.PriceNote','SLS.PriceNoteItem','SLS.SaleType'}

def active_plugins(db,bid):
    now=datetime.utcnow()
    return set(db.scalars(select(MarketplacePlugin.code).join(BusinessPlugin).where(
        BusinessPlugin.business_id==bid,BusinessPlugin.status=='active',MarketplacePlugin.is_active.is_(True),
        BusinessPlugin.starts_at<=now,(BusinessPlugin.ends_at.is_(None)) | (BusinessPlugin.ends_at>=now))))


SPECS={
 'product_warranty':(['INV.Tracing','INV.TracingCategory'],'no_operational_source','ردیابی کالا به معنی گارانتی فروخته‌شده نیست؛ CNT.Warranty ضمانت‌نامه قرارداد است.'),
 'repair_shop_management':([], 'no_direct_equivalent','در این نسخه/دیتابیس سپیدار دستور تعمیر و تعمیرکار معادل پیدا نشد.'),
 'basalam_connector':([], 'shared_native','اشخاص، کالاها و فاکتورهای مشترک بومی‌اند؛ سپیدار توکن یا شناسه سفارش باسلام ندارد و ارسال خارجی انجام نمی‌شود.'),
 'distribution':(['DST.AreaAndPath','DST.Order','DST.ColdDistribution','DST.HotDistribution'],'native_bridge','منطقه و مسیر پشتیبانی می‌شوند؛ ریشه Type=0 مسیر واقعی محسوب نمی‌شود. سفارش/اعزام نیازمند نگاشت جداست.'),
 'woocommerce_hesabix':([], 'shared_native','داده مشترک بومی قابل استفاده است؛ اتصال فروشگاه و سفارش ووکامرس مستقل از سپیدار است.'),
 'moadian_tax_integration':(['INV.Item','GNR.Party','SLS.Invoice','GNR.TaxPayerUnit'],'shared_native','شناسه کالا/اشخاص و مالیات فاکتور بومی است؛ رسید ارسال و گواهی مالیاتی جعل یا ارسال مجدد نمی‌شود.'),
 'customer_club':(['SLS.Invoice','SLS.ReturnedInvoice'],'native_bridge','امتیاز با قوانین موجود همین کسب‌وکار و فاکتورهای سال جاری به‌صورت تفاضلی محاسبه می‌شود؛ امتیاز سپیدار فرض نمی‌شود.'),
 'payroll':(['PAY.PayrollConfiguration','PAY.PayrollCalendar','PAY.TaxTable','PAY.Personnel','PAY.Calculation'],'native_bridge','تنظیمات بیمه/حساب‌های مرجع و آرشیو تقویم/جدول مالیات منتقل می‌شوند؛ جدول مالیات تاریخی خودکار فعال نمی‌شود.'),
 'hscript_custom_reports':(['ACC.Voucher','INV.Item','SLS.Invoice'],'shared_native','گزارش‌های حسابیکس از داده بومی همگام‌شده می‌خوانند؛ کد اجرایی/مجوز کاربران سپیدار وارد نمی‌شود.'),
 'asterisk_issabel_connector':([], 'no_direct_equivalent','PBX، فایل صوت و شناسه تماس معادل در سپیدار فعلی یافت نشد.'),
 'barcode_label_studio':(['INV.Item'],'shared_native','کد و بارکد کالا بومی است؛ قالب چاپ سپیدار همان قالب استودیوی حسابیکس نیست.'),
 'sepidar_live_import':(['ACC.Voucher','INV.Item','GNR.Party'],'native_bridge','Snapshot فقط‌خواندنی، تبدیل بومی و پل افزونه‌ها با هویت پایدار.'),
}

def coverage(db,bid):
    counts={f'{s}.{t}':n for s,t,n in db.execute(select(SepidarImportRow.source_schema,SepidarImportRow.source_table,func.count()).where(
        SepidarImportRow.business_id==bid,SepidarImportRow.is_deleted.is_(False)).group_by(SepidarImportRow.source_schema,SepidarImportRow.source_table))}
    licensed=active_plugins(db,bid)
    setting=db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id==bid)).first()
    rows=[]
    for plugin in db.scalars(select(MarketplacePlugin).order_by(MarketplacePlugin.id)):
        tables,status,note=SPECS.get(plugin.code,([], 'not_mapped','نگاشت تأییدشده‌ای تعریف نشده است.'))
        rows.append({'code':plugin.code,'name':plugin.name,'licensed':plugin.code in licensed,'status':status,
            'source_rows':{table:counts.get(table,0) for table in tables},'note':note})
    return {'database':setting.database_name if setting else None,'enabled':bool(setting and setting.plugins_enabled),
        'plugins':rows,'latest':(setting.native_summary or {}).get('plugins') if setting else None,
        'missing_features':[
            {'feature':'دارایی ثابت و استهلاک تخصصی','source':'AST.*','note':'قواعد استهلاک موجود است، اما دارایی عملیاتی در snapshot فعلی نیست؛ دفتر معادل زیرسیستم دارایی نیست.'},
            {'feature':'پیمانکاری، صورت‌وضعیت و ضمانت‌نامه قرارداد','source':'CNT.*','note':'ضرایب/هزینه/نوع ضمانت‌نامه موجودند؛ گارانتی کالا جایگزین این زیرسیستم نیست.'},
            {'feature':'تقویم حقوق، مرخصی و جداول مالیات تاریخ‌دار/چندگروهی','source':'PAY.PayrollCalendar / PAY.TaxTable','note':'حسابیکس قواعد عمومی حقوق دارد؛ معادل کامل آرشیو گروهی/تاریخی و مرخصی سپیدار ندارد.'},
            {'feature':'شرایط چندبعدی اعلامیه قیمت','source':'SLS.PriceNoteItem','note':'قیمت پایه قابل انتقال است؛ شرط ردیابی/گروه مشتری/افزوده غیرصفر بدون معادل روشن اعمال نمی‌شود.'},
            {'feature':'ردیابی و قیمت‌گذاری بچ/محموله','source':'INV.Tracing / INV.InventoryPricing','note':'سریال/بارکد حسابیکس معادل کامل ردیابی و لایه‌های قیمت‌گذاری سپیدار نیست.'},
        ]}


class PluginProjector:
    def __init__(self,p):
        self.p=p;self.db=p.db;self.bid=p.bid;self.active=active_plugins(self.db,self.bid)
        for table,key in [('PAY.PayrollConfiguration','PayrollConfigurationId'),('DST.AreaAndPath','AreaAndPathId'),('SLS.PriceNote','PriceNoteID'),('SLS.PriceNoteItem','PriceNoteItemID')]:
            ids=[str(row[key]) for row in p.data[table]]
            if len(ids)!=len(set(ids)):raise NativeConversionError(f'Duplicate source plugin identity: {table}')
        for model in (PayrollSettings,DistributionTerritory,DistributionRoute,PriceList):
            p.targets[model.__tablename__]={row.id:row for row in self.db.scalars(select(model).where(model.business_id==self.bid))}
        p.targets[PriceItem.__tablename__]={row.id:row for row in self.db.scalars(select(PriceItem).join(PriceList).where(PriceList.business_id==self.bid))}
        self.result={'payroll_settings':0,'distribution_regions':0,'distribution_routes':0,'price_items':0,'price_skipped':0,'loyalty_invoices':0}

    def payroll(self):
        p=self.p
        if 'payroll' not in self.active:return
        rows=p.data['PAY.PayrollConfiguration']
        if len(rows)>1:raise NativeConversionError('Ambiguous source payroll configuration')
        if not rows:return
        row=rows[0]
        existing=next(iter(p.targets[PayrollSettings.__tablename__].values()),None)
        extra=deepcopy(existing.extra_settings or {}) if existing else {}
        rules=deepcopy(extra.get('statutory_rules',{}));insurance=dict(rules.get('insurance',{}))
        for src,dst in [('EmployeeInsurancePercent','employee_rate_percent'),('EmployerInsurancePercent','employer_rate_percent'),('UnemploymentInsurancePercent','unemployment_employer_rate_percent')]:
            rate=decimal(row.get(src))
            if not 0<=rate<=100:raise NativeConversionError('Invalid source insurance percent')
            insurance[dst]=str(rate)
        rules['insurance']=insurance
        # Preserve enablement and locally configured current tax rules. Historical
        # source tax tables must not become today's statutory table by inference.
        extra['statutory_rules']=rules
        archive={name:sorted(p.data['PAY.'+name],key=lambda r:fingerprint(r)) for name in ['PayrollCalendar','DailyHourMinute','TaxGroup','TaxTable','TaxTableItem']}
        extra['sepidar']={'managed':True,'configuration':row,'reference_catalog':archive,
            'note':'Historical source tax tables are archived, not activated; daily ceilings are not monthly ceilings.'}
        fields={'business_id':self.bid,'extra_settings':extra}
        for src,dst in [('PaymentAccountRef','wages_payable_account_id'),('SocialSecurityAccountRef','insurance_payable_account_id')]:
            account=p.target('ACC.Account',row.get(src),optional=True)
            fields[dst]=account.id if account else None
        p.upsert('PAY.PayrollConfiguration',row['PayrollConfigurationId'],PayrollSettings,{'row':row,'archive':archive},fields,reuse=existing)
        self.result['payroll_settings']=1
        p.warnings.append('Source payroll tax tables are historical reference only; no payslip or statutory tax was fabricated')

    def distribution(self):
        p=self.p
        if 'distribution' not in self.active:return
        rows={r['AreaAndPathId']:r for r in p.data['DST.AreaAndPath'] if r['Type'] in [1,2]}
        for typ,model in [(1,DistributionTerritory),(2,DistributionRoute)]:
            for sid,row in sorted(rows.items()):
                if row['Type']!=typ:continue
                mapping=p.maps.get(('DST.AreaAndPath',str(sid)))
                if mapping and mapping.target_table!=model.__tablename__:
                    raise NativeConversionError('Source area/path type changed; reconciliation required')
                fields={'business_id':self.bid,'code':f'SPD-{sid}-{row["Code"]}'[:50],'name':row['Title'],'is_active':bool(row.get('IsActive',True)),
                    'description':'همگام از سپیدار؛ ویرایش در مبدأ.'}
                if typ==2:
                    parent=rows.get(row.get('ParentAreaAndPathRef'))
                    if not parent or parent['Type']!=1:raise NativeConversionError('Source route needs an area parent')
                    fields['territory_id']=p.target('DST.AreaAndPath',parent['AreaAndPathId']).id
                p.upsert('DST.AreaAndPath',sid,model,row,fields)
                self.result['distribution_regions' if typ==1 else 'distribution_routes']+=1
        for (table,sid),mapping in list(p.maps.items()):
            if table=='DST.AreaAndPath' and sid not in {str(i) for i in rows}:
                target=p.targets[mapping.target_table][mapping.target_id]
                if target.is_active:
                    target.is_active=False;mapping.source_hash=fingerprint({'deleted':sid});p.stats[table]['updated']+=1

    def prices(self):
        p=self.p
        source_items={row['ItemID']:row for row in p.data['INV.Item']}
        sale_types={row['SaleTypeId']:row for row in p.data['SLS.SaleType']}
        identities=set()
        parents={row['PriceNoteID'] for row in p.data['SLS.PriceNote']}
        if any(item['PriceNoteRef'] not in parents for item in p.data['SLS.PriceNoteItem']):
            raise NativeConversionError('Source price header unavailable')
        allowed=set()
        for row in sorted(p.data['SLS.PriceNote'],key=lambda r:r['PriceNoteID']):
            price_list,_=p.upsert('SLS.PriceNote',row['PriceNoteID'],PriceList,row,{
                'business_id':self.bid,'name':f'سپیدار {row["PriceNoteID"]} — {row["Title"]}'[:255],'is_active':True})
            for item in sorted(p.data['SLS.PriceNoteItem'],key=lambda r:r['PriceNoteItemID']):
                if item['PriceNoteRef']!=row['PriceNoteID']:continue
                product=p.target('INV.Item',item['ItemRef'])
                if item['ItemRef'] not in source_items:
                    raise NativeConversionError('Source price product unavailable')
                if item.get('UnitRef') != source_items.get(item['ItemRef'],{}).get('UnitRef') or item.get('TracingRef') or item.get('CustomerGroupingRef') or any(decimal(item.get(k)) for k in ['Discount','AdditionRate','LowerMargin','UpperMargin']):
                    self.result['price_skipped']+=1;continue
                currency=p.currency_ids.get(item.get('CurrencyRef') or 1)
                if not currency:raise NativeConversionError('Unmapped source price currency')
                value=money(item['Fee'])
                if value<0:raise NativeConversionError('Negative source price')
                sid=item['PriceNoteItemID'];allowed.add(str(sid))
                tier=f'SPD-{item["SaleTypeRef"]} {sale_types.get(item["SaleTypeRef"],{}).get("Title", "")}'[:64]
                identity=(price_list.id,product.id,currency,tier)
                if identity in identities:raise NativeConversionError('Ambiguous duplicate source price tier')
                identities.add(identity)
                p.upsert('SLS.PriceNoteItem',sid,PriceItem,{'item':item,'list':row}, {'price_list_id':price_list.id,'product_id':product.id,
                    'unit_id':None,'currency_id':currency,'tier_name':tier, 'min_qty':Decimal('0'),'price':value})
                self.result['price_items']+=1
        for (table,sid),mapping in list(p.maps.items()):
            if table=='SLS.PriceNote' and sid not in {str(r['PriceNoteID']) for r in p.data['SLS.PriceNote']}:
                target=p.targets[mapping.target_table][mapping.target_id]
                if target.is_active:
                    target.is_active=False;mapping.source_hash=fingerprint({'deleted':sid});p.stats[table]['updated']+=1
            if table=='SLS.PriceNoteItem' and sid not in allowed:
                self.db.delete(p.targets[mapping.target_table][mapping.target_id]);self.db.delete(mapping);del p.maps[(table,sid)]
        if self.result['price_skipped']:p.warnings.append(f'Source price rules without a lossless native equivalent skipped: {self.result["price_skipped"]}')

    def loyalty(self):
        if 'customer_club' not in self.active:return
        from app.services.customer_club_service import sync_customer_club_for_invoice
        # Reuse existing delta/snapshot semantics; no SMS, GL, cash redemption or
        # historical-year points are posted by this bridge.
        for (table,sid),mapping in self.p.maps.items():
            if table not in {'SLS.Invoice','SLS.ReturnedInvoice'}:continue
            document=self.p.targets['documents'][mapping.target_id]
            from adapters.db.models.customer_club import CustomerClubInvoiceSnapshot
            snapshot=self.db.scalars(select(CustomerClubInvoiceSnapshot).where(CustomerClubInvoiceSnapshot.document_id==document.id)).first()
            person_id=(document.extra_info or {}).get('person_id')
            if snapshot and (document.is_proforma or snapshot.person_id != person_id):
                from app.services.customer_club_service import reverse_customer_club_on_invoice_delete
                reverse_customer_club_on_invoice_delete(self.db,document.id,self.bid)
                snapshot.accrued_points=Decimal('0')
                if hasattr(snapshot,'redeemed_points'):snapshot.redeemed_points=Decimal('0')
                snapshot.person_id=person_id
                self.db.flush()
            sync_customer_club_for_invoice(self.db,mapping.target_id)
            self.result['loyalty_invoices']+=1

    def run(self):
        self.payroll();self.distribution();self.prices();self.db.flush();self.loyalty()
        return self.result
