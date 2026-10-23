"""Deterministic, Decimal-only specialist operations. No financial side effects."""
from collections import defaultdict, deque
from copy import deepcopy
from datetime import date,timedelta
from decimal import Decimal
from hashlib import sha256
import json
from types import SimpleNamespace
from sqlalchemy import select
from adapters.db.models.advanced_plugins import AdvancedPluginRecord as Record
from app.services.advanced_plugin_service import fail,number,day,get_record,settings_row,require_license,audit,settings
from app.services.advanced_plugin_catalog import field


OPERATIONS={
 'fixed_assets':{
  'depreciation_preview':{'label':'پیش‌نمایش استهلاک','fields':{'record_id':field('دارایی','parent',True),'from_date':field('از تاریخ','date',True),'to_date':field('تا تاریخ','date',True)}},
  'depreciation_save':{'label':'ذخیره پیش‌نویس برنامه استهلاک (بدون سند مالی)','fields':{'record_id':field('دارایی','parent',True),'from_date':field('از تاریخ','date',True),'to_date':field('تا تاریخ','date',True)}},
 },
 'contracting':{
  'certificate_preview':{'label':'محاسبه صورت‌وضعیت','fields':{'record_id':field('صورت‌وضعیت','parent',True)}},
  'certificate_save':{'label':'ذخیره محاسبه صورت‌وضعیت (بدون سند مالی)','fields':{'record_id':field('صورت‌وضعیت','parent',True)}},
  'guarantee_due':{'label':'سررسید ضمانت‌نامه‌ها','fields':{'on_date':field('تاریخ بررسی','date',True)}},
 },
 'payroll_calendar_tax':{
  'tax_preview':{'label':'محاسبه مالیات در تاریخ مشخص','fields':{'on_date':field('تاریخ محاسبه','date',True),'taxable_amount':field('مبلغ مشمول','decimal',True,min='0'),'group_id':field('گروه مالیات','parent'),'tax_scope':field('نوع درآمد','choice',choices=['salary','bonus'],default='salary')}},
  'calendar_lookup':{'label':'تقویم سال و ماه حقوق','fields':{'solar_year':field('سال شمسی','integer',True,min=1300,max=1600),'month':field('ماه','integer',True,min=1,max=12)}},
  'leave_balance':{'label':'مانده مرخصی شخص در تاریخ','fields':{'person_id':field('شخص بومی','person',True),'on_date':field('تا تاریخ','date',True)}},
  'approve_tax_table':{'label':'تأیید نسخه مشخص جدول و پله‌ها','fields':{'record_id':field('جدول مالیات','parent',True)}},
 },
 'conditional_pricing':{
  'price_quote':{'label':'ارزیابی قیمت و توضیح شروط','fields':{'product_id':field('کالا','product',True),'currency_id':field('واحد پول','currency',True),'quantity':field('مقدار','decimal',True,min='0.000001'),'on_date':field('تاریخ','date',True),'sale_type_ref':field('نوع فروش مبدأ','integer'),'customer_group_ref':field('گروه مشتری مبدأ','integer'),'tracing_ref':field('ردیابی مبدأ','integer'),'unit_ref':field('واحد مبدأ','integer')}},
 },
 'inventory_trace_cost':{
  'fifo_report':{'label':'مانده لایه‌ها و بهای FIFO','fields':{'product_id':field('کالا','product',True),'warehouse_id':field('انبار','warehouse',True),'on_date':field('تا تاریخ','date',True),'fiscal_year_id':field('سال مالی بومی؛ خالی یعنی آخرین سال','integer'),'trace_id':field('بچ / ردیابی؛ اختیاری','parent'),'quote_quantity':field('مقدار برای برآورد خروج','decimal',min='0.000001')}},
 },
}


def digest(value):
    return sha256(json.dumps(value,sort_keys=True,ensure_ascii=False,default=str,separators=(',',':')).encode()).hexdigest()


def active_records(db,bid,code,kind=None):
    q=select(Record).where(Record.business_id==bid,Record.plugin_code==code,Record.status=='active',Record.source_deleted.is_(False))
    if kind:q=q.where(Record.kind==kind)
    return list(db.scalars(q))


def result(title,metrics,rows=None,warnings=None,**extra):
    return {'title':title,'metrics':[{'label':label,'value':str(value) if value is not None else 'نامعلوم'} for label,value in metrics],
        'rows':rows or [],'warnings':warnings or [],'financial_posted':False,**extra}


def _save_result(db,bid,code,kind,parent,start,end,value,output,identity_parts,actor):
    identity=digest(['calculation',*identity_parts])
    row=db.scalars(select(Record).where(Record.business_id==bid,Record.plugin_code==code,Record.identity==identity).with_for_update()).first()
    if row and row.data.get('input_hash')==output['input_hash']:
        return {**output,'saved_record_id':row.id,'unchanged':True}
    if row:
        from app.services.advanced_plugin_posting_service import assert_event_editable
        assert_event_editable(db,bid,row.id)
    if row is None:
        row=Record(business_id=bid,plugin_code=code,kind=kind,identity=identity,title=output['title'],parent_id=parent,status='active',data={})
        db.add(row)
    row.start_date=start;row.end_date=end;row.amount=value;row.data=output;row.revision=(row.revision or 0)+1
    db.flush();audit(db,bid,code,'calculate',actor,row,input_hash=output['input_hash'],financial_posted=False)
    db.commit();return {**output,'saved_record_id':row.id,'unchanged':False}


def depreciation(db,bid,payload,save=False,actor=None):
    code='fixed_assets';asset=get_record(db,bid,code,payload['record_id'],lock=save)
    if asset.kind!='asset' or asset.source_deleted or asset.status!='active':fail('دارایی فعال انتخاب کنید.')
    start,end=day(payload['from_date']),day(payload['to_date'])
    if start>end or (end-start).days>=366:fail('بازه استهلاک باید حداکثر یک سال و صعودی باشد.')
    if asset.start_date and start<asset.start_date:fail('شروع محاسبه قبل از بهره‌برداری دارایی است.')
    specs=[asset]
    if asset.source_table:
        specs=[r for r in active_records(db,bid,code,'cost_part') if r.parent_id==asset.id]
        if not specs:fail('اجزای بهای تحصیل دارایی هنوز در مبدأ موجود نیست.')
    previous=[r for r in active_records(db,bid,code,'schedule') if r.parent_id==asset.id]
    overlaps=[r for r in previous if r.start_date<=end and r.end_date>=start and not (r.start_date==start and r.end_date==end)]
    if overlaps:fail('این دوره با برنامه ذخیره‌شده قبلی همپوشانی دارد.','DEPRECIATION_OVERLAP',409)
    prior=sum((number(r.amount,Decimal(0)) for r in previous if r.end_date<start),Decimal(0))
    if len(specs)>1 and prior:fail('محاسبه مجدد چندجزئی پس از برنامه قبلی نیازمند تفکیک اجزا است؛ بازه یکپارچه انتخاب کنید.')
    rows=[];total=Decimal(0);cfg=settings(db,bid,code)['options']
    for part in specs:
        data=part.data or {};cost=number(data.get('cost'),part.amount)
        if cost is None:fail('بهای تحصیل مشخص نیست؛ هزینه صفر فرض نمی‌شود.')
        salvage=number(data.get('salvage'),Decimal(0));acc=number(data.get('accumulated'),Decimal(0))+prior
        if acc+salvage>cost:fail('مانده دارایی ناسازگار است.')
        if number(data.get('max_depreciable_book_value'),Decimal(0)):
            fail('دارایی مبدأ شرط ویژه سقف ارزش دفتری دارد؛ بدون بررسی قاعده، استهلاک حدسی محاسبه نمی‌شود.')
        latest=day(data['last_calculated_on']) if data.get('last_calculated_on') else None
        if latest and start<=latest:fail('دوره انتخابی با استهلاک ثبت‌شده سپیدار همپوشانی دارد.')
        method=data.get('method');book=cost-acc
        basis=Decimal((end-start).days+1)/Decimal(cfg.get('day_basis',365))
        if method=='straight_line':
            life=number(data.get('useful_life_years'))
            if life is None or life<=0:fail('عمر مفید مثبت برای خط مستقیم الزامی است.')
            annual=(cost-salvage)/life
        elif method=='declining':
            rate=number(data.get('annual_rate'))
            if rate is None or not 0<=rate<=100:fail('نرخ معتبر نزولی الزامی است.')
            annual=book*rate/100
        else:fail('روش دارایی بدون محاسبه یا نیازمند بررسی است.')
        value=min(max(Decimal(0),book-salvage),annual*basis).quantize(Decimal('.0001'))
        total+=value;rows.append({'جزء':part.title,'استهلاک':str(value),'ارزش دفتری پایان':str(book-value)})
    output=result('برنامه استهلاک '+asset.title,[('مدت (روز)',(end-start).days+1),('استهلاک دوره',total)],rows,
        ['پیش‌نویس عملیاتی است؛ سند مالی یا استهلاک ثبت‌شده سپیدار دوباره صادر نمی‌شود.'],
        input_hash=digest([[(p.id,p.revision,p.data,p.amount) for p in specs],start,end,prior,cfg]))
    if save:return _save_result(db,bid,code,'schedule',asset.id,start,end,total,output,[asset.id,start,end],actor)
    return output


def certificate(db,bid,payload,save=False,actor=None):
    code='contracting';statement=get_record(db,bid,code,payload['record_id'],lock=save)
    if statement.kind!='statement' or statement.status!='active' or statement.source_deleted:fail('صورت‌وضعیت فعال انتخاب کنید.')
    lines=[r for r in active_records(db,bid,code,'statement_line') if r.parent_id==statement.id]
    if not lines:fail('قلم صورت‌وضعیت وجود ندارد.')
    gross=Decimal(0);rows=[]
    for line in lines:
        qty=number(line.quantity,Decimal(0));fee=number(line.data.get('unit_price'),Decimal(0))
        value=number(line.amount) if line.source_table else qty*fee
        if value is None:fail('مبلغ قلم مبدأ مشخص نیست.')
        gross+=value;rows.append({'شرح':line.title,'مقدار':str(qty),'مبلغ':str(value)})
    contract=get_record(db,bid,code,statement.parent_id) if statement.parent_id else None
    if contract and (contract.source_deleted or contract.status!='active'):fail('قرارداد مرجع فعال نیست.')
    rules={**(contract.data or {} if contract else {}),**(statement.data or {})}
    retention=gross*number(rules.get('retention_percent'),Decimal(0))/100
    advance=number(rules.get('advance_amount'),gross*number(rules.get('advance_percent'),Decimal(0))/100)
    tax=gross*number(rules.get('tax_percent'),Decimal(0))/100
    net=(gross+tax-retention-advance).quantize(Decimal('.0001'))
    if net<0:fail('کسور از مبلغ صورت‌وضعیت بیشتر است.')
    warnings=['محاسبه بر اساس قواعد صریح همین قرارداد است؛ نرخ قانونی فرض نمی‌شود و سند مالی خودکار ندارد.']
    if statement.source_table:warnings.append('این محاسبه مبلغ تأییدشده مبدأ را تغییر نمی‌دهد؛ ضرایب مبدأ در اصل داده قابل بررسی‌اند.')
    output=result('محاسبه '+statement.title,[('ناخالص',gross),('کسور',retention),('استهلاک پیش‌پرداخت',advance),('افزوده',tax),('خالص',net)],rows,warnings,
        input_hash=digest([statement.revision,[(l.id,l.revision,l.amount,l.quantity,l.data) for l in lines],rules]))
    if save:return _save_result(db,bid,code,'certificate',statement.id,statement.start_date,statement.end_date,net,output,[statement.id],actor)
    return output


def tax_brackets(db,bid,table):
    rows=[r for r in active_records(db,bid,'payroll_calendar_tax','tax_bracket') if r.parent_id==table.id]
    rows.sort(key=lambda r:number(r.data.get('from_amount'),Decimal(0)))
    if not rows:fail('پله مالیاتی وجود ندارد.')
    last=Decimal(0);out=[]
    for row in rows:
        lower=number(row.data.get('from_amount'));upper=number(row.data.get('to_amount'));rate=number(row.data.get('rate'))
        if lower is None or lower!=last or (upper is not None and upper<=lower) or rate is None or not 0<=rate<=100:
            fail('پله‌های مالیات باید پیوسته، بدون همپوشانی و از صفر باشند.')
        out.append({'from':lower,'to':upper,'rate':rate});last=upper
        if upper is None and row is not rows[-1]:fail('پله نامحدود باید آخر باشد.')
    stamp=digest([table.id,table.source_hash,table.start_date,table.end_date,table.data,[(r.id,r.source_hash,r.data) for r in rows]])
    return out,stamp


def select_tax(db,bid,on_date,group_id=None,*,check_approved=True,tax_scope='salary'):
    code='payroll_calendar_tax';cfg=settings_row(db,bid,code)
    opts=settings(db,bid,code)['options'];on_date=day(on_date)
    group_id=group_id or opts.get('tax_group_id')
    choices=[]
    for table in active_records(db,bid,code,'tax_table'):
        if table.data.get('tax_scope','salary')!=tax_scope:continue
        group=table.parent_id or table.data.get('tax_group_id')
        if group_id and group!=group_id:continue
        if not table.start_date or table.start_date>on_date or (table.end_date and table.end_date<on_date):continue
        if not table.end_date and (on_date-table.start_date).days>=opts.get('max_tax_age_days',366):continue
        choices.append(table)
    if not choices:fail('جدول معتبر برای این تاریخ وجود ندارد؛ جدول تاریخی خودکار جایگزین نمی‌شود.','NO_EFFECTIVE_TAX_TABLE')
    if not group_id and len({r.parent_id or r.data.get('tax_group_id') for r in choices})>1:fail('گروه مالیات را مشخص کنید.')
    latest=max(r.start_date for r in choices);chosen=[r for r in choices if r.start_date==latest]
    if len(chosen)!=1:fail('چند جدول مالیات هم‌تاریخ وجود دارد؛ ابهام را رفع کنید.')
    table=chosen[0]
    if table.data.get('tax_type') not in {None,1,'1','progressive'}:fail('نوع مالیات مبدأ نیازمند بررسی است.')
    brackets,stamp=tax_brackets(db,bid,table)
    approvals=(cfg.options or {}).get('approved_tax_tables',{}) if cfg else {}
    if check_approved and approvals.get(str(table.id))!=stamp:
        fail('این نسخه جدول و پله‌های مالیات هنوز تأیید نشده است.','TAX_TABLE_NOT_APPROVED')
    return table,brackets,stamp


def tax_preview(db,bid,payload):
    table,brackets,stamp=select_tax(db,bid,payload['on_date'],payload.get('group_id'),tax_scope=payload.get('tax_scope','salary'))
    basis=number(payload['taxable_amount']);total=Decimal(0)
    for bracket in brackets:
        chunk=max(Decimal(0),(min(basis,bracket['to']) if bracket['to'] is not None else basis)-bracket['from'])
        total+=chunk*bracket['rate']/100
    if brackets[-1]['to'] is not None and basis>brackets[-1]['to']:fail('مبلغ از آخرین پله جدول بیشتر است.')
    return result('مالیات — '+table.title,[('پایه مشمول',basis),('مالیات',total.quantize(Decimal('.0001')))],
        [{'از':str(b['from']),'تا':str(b['to']) if b['to'] is not None else 'نامحدود','نرخ':str(b['rate'])} for b in brackets],
        ['محاسبه از جدول تأییدشده کسب‌وکار است؛ تأیید صحت قانونی نرخ بر عهده مدیر است.'],table_id=table.id,input_hash=stamp)


def effective_payroll_settings(db,bid,on_date,original):
    """Opt-in bridge used by native payroll calculation, never mutates settings."""
    code='payroll_calendar_tax'
    from app.services.advanced_plugin_service import licensed
    if not licensed(db,bid,code):return original
    cfg=settings_row(db,bid,code)
    if not cfg or not cfg.enabled or not (cfg.options or {}).get('auto_apply_tax'):return original
    table,brackets,stamp=select_tax(db,bid,on_date)
    # Native payroll's progressive routine must have full coverage, not an
    # unbounded silent zero rate after a finite last bracket.
    if brackets[-1]['to'] is not None:fail('برای اعمال خودکار، آخرین پله مالیات باید بدون سقف باشد.')
    extra=deepcopy(original.extra_settings or {});rules=extra.setdefault('statutory_rules',{})
    rules['_advanced_tax_only']=not bool(rules.get('enabled',False));rules['enabled']=True
    rules['tax']={'mode':'progressive','exemption_amount':0,'brackets':[{'up_to':str(b['to']) if b['to'] is not None else None,'rate_percent':str(b['rate'])} for b in brackets]}
    extra['advanced_tax_applied']={'table_id':table.id,'input_hash':stamp,'on_date':str(on_date)}
    return SimpleNamespace(**{c.name:(extra if c.name=='extra_settings' else getattr(original,c.name)) for c in original.__table__.columns})


def price_quote(db,bid,payload):
    from adapters.db.models.product import Product
    product=db.get(Product,payload['product_id'])
    if not product or product.business_id!=bid or not product.is_active:fail('کالا فعال نیست یا متعلق به کسب‌وکار نیست.')
    when=day(payload['on_date']);qty=number(payload['quantity']);matches=[]
    parents={r.id:r for r in active_records(db,bid,'conditional_pricing','price_book')}
    for rule in active_records(db,bid,'conditional_pricing','price_rule'):
        if rule.product_id!=payload['product_id'] or rule.currency_id!=payload['currency_id']:continue
        parent=parents.get(rule.parent_id) if rule.parent_id else None
        if rule.parent_id and not parent:continue
        start=rule.start_date or (parent.start_date if parent else None)
        end=rule.end_date or (parent.end_date if parent else None)
        if (start and start>when) or (end and end<when):continue
        data=rule.data or {}
        if qty<number(data.get('min_qty'),Decimal(0)) or (data.get('max_qty') is not None and qty>number(data['max_qty'])):continue
        score=0
        for key in ['sale_type_ref','customer_group_ref','tracing_ref','unit_ref']:
            condition=data.get(key)
            if condition not in (None,0,'0',''):
                if payload.get(key)!=int(condition):break
                score+=1
        else:
            matches.append(((int(data.get('priority') or 0),score,start or date.min),rule))
    if not matches:fail('قاعده قیمت منطبق پیدا نشد؛ واحد و شروط مشتری/ردیابی را نیز مشخص کنید.','NO_MATCHING_PRICE')
    matches.sort(key=lambda r:(r[0],r[1].id),reverse=True)
    best=matches[0][0];tied=[r for rank,r in matches if rank==best]
    if len(tied)>1 and settings(db,bid,'conditional_pricing')['options'].get('reject_ambiguous',True):
        fail('چند قاعده هم‌اولویت منطبق‌اند؛ قیمت خودکار انتخاب نشد.','AMBIGUOUS_PRICE',409)
    rule=tied[0];base=number(rule.amount)
    if rule.data.get('needs_review'):fail('قاعده منطبق نیازمند بررسی است؛ قیمت جایگزین حدسی انتخاب نشد.')
    for window in active_records(db,bid,'conditional_pricing','discount_window'):
        if window.parent_id==rule.id and (not window.start_date or window.start_date<=when) and (not window.end_date or window.end_date>=when):
            fail('این قاعده تخفیف زمان‌دار مبدأ دارد؛ قواعد حجمی آن را بررسی و قاعده صریح با اولویت بالاتر ثبت کنید.')
    if base is None:fail('قیمت پایه مشخص نیست.')
    discount=number(rule.data.get('discount_percent'),Decimal(0));addition=number(rule.data.get('addition_percent'),Decimal(0))
    order=settings(db,bid,'conditional_pricing')['options'].get('source_adjustment_order','require_review') if rule.source_table else 'discount_then_addition'
    if rule.source_table and order=='require_review' and (discount or addition):fail('ترتیب تعدیل قیمت مبدأ را در تنظیمات این افزونه تأیید کنید.')
    value=(base*(1-discount/100+addition/100) if order=='parallel_on_base' else base*(1-discount/100)*(1+addition/100)).quantize(Decimal('.0001'))
    return result('قیمت شرطی — '+rule.title,[('قیمت پایه',base),('تخفیف (%)',discount),('افزوده (%)',addition),('قیمت نهایی واحد',value),('جمع',value*qty)],
        warnings=['این پیشنهاد فاکتور را خودکار تغییر نمی‌دهد؛ حاشیه‌های مبدأ مجوز تخفیف یا حداقل مقدار فرض نمی‌شوند.'],
        rule_id=rule.id,matched_rule_ids=[r.id for _,r in matches],input_hash=digest([rule.id,rule.revision,payload]))


def fifo_report(db,bid,payload):
    from adapters.db.models.fiscal_year import FiscalYear
    from adapters.db.models.warehouse_document import WarehouseDocument
    from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
    from sqlalchemy import func,case
    code='inventory_trace_cost';when=day(payload['on_date'])
    fyid=payload.get('fiscal_year_id')
    fy=db.scalars(select(FiscalYear).where(FiscalYear.business_id==bid,FiscalYear.id==fyid)).first() if fyid else db.scalars(select(FiscalYear).where(FiscalYear.business_id==bid,FiscalYear.is_last.is_(True))).first()
    if not fy:fail('سال مالی انتخاب‌شده متعلق به کسب‌وکار نیست یا موجود نیست.')
    events=[r for r in active_records(db,bid,code) if r.kind in {'receipt_layer','issue'} and r.product_id==payload['product_id']
        and r.data.get('warehouse_id')==payload['warehouse_id'] and r.data.get('fiscal_year_id')==fy.id and r.start_date and r.start_date<=when]
    native={line.id:(line,doc) for line,doc in db.execute(select(WarehouseDocumentLine,WarehouseDocument).join(WarehouseDocument).where(
        WarehouseDocument.business_id==bid,WarehouseDocument.fiscal_year_id==fy.id,WarehouseDocument.status=='posted',WarehouseDocument.document_date<=when,
        WarehouseDocumentLine.product_id==payload['product_id'],WarehouseDocumentLine.warehouse_id==payload['warehouse_id']))}
    valid=[];invalid=0
    for event in events:
        linked=native.get(event.data.get('warehouse_document_line_id'))
        if not linked or event.quantity>linked[0].quantity or linked[0].movement!=('in' if event.kind=='receipt_layer' else 'out'):
            invalid+=1;continue
        valid.append(event)
    events=valid
    events.sort(key=lambda r:(r.start_date,0 if r.kind=='receipt_layer' else 1,r.id))
    queues=defaultdict(deque);unallocated=Decimal(0)
    for event in events:
        trace=event.data.get('trace_id');qty=number(event.quantity,Decimal(0))
        if event.kind=='receipt_layer':queues[trace].append({'record':event,'quantity':qty,'cost':number(event.data.get('unit_cost'))})
        else:
            # Do not consume a different batch when source explicitly identifies one.
            queue=queues[trace]
            while qty>0 and queue:
                layer=queue[0];taken=min(qty,layer['quantity']);layer['quantity']-=taken;qty-=taken
                if layer['quantity']==0:queue.popleft()
            unallocated+=qty
    layers=[l for trace,queue in queues.items() for l in queue if not payload.get('trace_id') or trace==payload['trace_id']]
    layers.sort(key=lambda l:(l['record'].start_date,l['record'].id))
    quantity=sum((l['quantity'] for l in layers),Decimal(0));known=sum((l['quantity']*l['cost'] for l in layers if l['cost'] is not None),Decimal(0))
    unknown=sum((l['quantity'] for l in layers if l['cost'] is None),Decimal(0))
    # Native physical stock is cumulative: the fiscal carry-reset offsets prior
    # years. FIFO layers stay scoped to the selected fiscal year, not this total.
    from app.services.warehouse_service import get_physical_stock
    core=get_physical_stock(db,bid,payload['product_id'],payload['warehouse_id'],when)
    metrics=[('مقدار لایه‌های باقی‌مانده',quantity),('ارزش بخش دارای بها',known.quantize(Decimal('.0001'))),('مقدار با بهای نامعلوم',unknown),('خروج بدون لایه منطبق',unallocated),('موجودی دفتر انبار بومی',core),('پیوندهای بومی نامعتبر / لغوشده',invalid)]
    if payload.get('quote_quantity') is not None:
        qty=number(payload['quote_quantity']);value=Decimal(0)
        if invalid or unallocated or qty>core:fail('پیش از برآورد، پیوند نامعتبر، خروج بدون لایه و اختلاف با دفتر بومی را رفع کنید.')
        if qty>quantity:fail('لایه کافی برای برآورد خروج وجود ندارد.')
        for layer in layers:
            take=min(qty,layer['quantity'])
            if take and layer['cost'] is None:fail('بهای یک لایه خروج نامعلوم است؛ صفر فرض نمی‌شود.')
            if take:value+=take*layer['cost'];qty-=take
            if qty==0:break
        metrics.append(('برآورد FIFO خروج',value.quantize(Decimal('.0001'))))
    return result('گزارش ردیابی و لایه‌های FIFO',metrics,
        [{'رسید':l['record'].title,'مقدار':str(l['quantity']),'بهای واحد':str(l['cost']) if l['cost'] is not None else 'نامعلوم','بچ':str(l['record'].data.get('trace_id') or 'بدون ردیابی')} for l in layers[:500]],
        ['این گزارش تخصیص/برآورد است، نه بازثبت موجودی یا بهای صادرشده سپیدار. اختلاف با دفتر بومی، از جمله تعدیلات بدون بچ، صریح نمایش داده می‌شود.'])


def run_operation(db,bid,code,action,payload,actor=None):
    if action.endswith('_save') or action=='approve_tax_table':
        from app.services.advanced_plugin_posting_service import posting_lock
        posting_lock(db,bid)
    from app.services.advanced_plugin_service import validate_fields
    require_license(db,bid,code)
    spec=OPERATIONS.get(code,{}).get(action)
    if not spec:fail('عملیات افزونه شناخته نشد.')
    payload=validate_fields(db,bid,code,spec['fields'],payload)
    cfg=settings_row(db,bid,code)
    if cfg and not cfg.enabled:fail('افزونه در تنظیمات غیرفعال است.')
    if action.startswith('depreciation_'):return depreciation(db,bid,payload,action.endswith('_save'),actor)
    if action.startswith('certificate_'):return certificate(db,bid,payload,action.endswith('_save'),actor)
    if action=='tax_preview':return tax_preview(db,bid,payload)
    if action=='price_quote':return price_quote(db,bid,payload)
    if action=='fifo_report':return fifo_report(db,bid,payload)
    if action=='guarantee_due':
        when=day(payload['on_date']);limit=when+timedelta(days=settings(db,bid,code)['options'].get('due_warning_days',30))
        rows=[r for r in active_records(db,bid,code,'guarantee') if r.end_date and r.end_date<=limit]
        rows.sort(key=lambda r:(r.end_date,r.id))
        return result('سررسید ضمانت‌نامه‌های فعال',[('در بازه هشدار',len(rows)),('سررسید گذشته',sum(r.end_date<when for r in rows))],
            [{'عنوان':r.title,'سررسید':str(r.end_date),'روز باقی‌مانده':(r.end_date-when).days,'مبلغ':str(r.amount),'ارز':r.currency_id} for r in rows],['اطلاع‌رسانی فقط در پنل است؛ پیامک یا عملیات بانکی خودکار انجام نمی‌شود.'])
    if action=='calendar_lookup':
        rows=[r for r in active_records(db,bid,code,'calendar') if r.data.get('solar_year')==payload['solar_year'] and r.data.get('month')==payload['month']]
        if len(rows)!=1:fail('تقویم این سال/ماه وجود ندارد یا چند رکورد متعارض دارد؛ روزکاری فرضی ساخته نمی‌شود.')
        row=rows[0];return result(row.title,[('روزهای کاری',row.data.get('days')),('واحد زمان روزانه مبدأ',row.data.get('daily_minutes'))],warnings=['مقدار مبدأ بدون تبدیل تقویمی یا فرض روزکاری حفظ شده است.'])
    if action=='leave_balance':
        when=day(payload['on_date']);personnel={r.id for r in active_records(db,bid,code,'personnel') if r.person_id==payload['person_id']}
        rows=[r for r in active_records(db,bid,code,'leave') if (r.person_id==payload['person_id'] or r.parent_id in personnel) and r.start_date and r.start_date<=when]
        if not rows:fail('مانده مرخصی در این تاریخ موجود نیست؛ صفر فرض نمی‌شود.')
        latest=max(r.start_date for r in rows);matches=[r for r in rows if r.start_date==latest]
        if len(matches)!=1:fail('مانده‌های مرخصی هم‌تاریخ متعارض‌اند.')
        return result('مانده مرخصی در تاریخ '+str(latest),[('مانده (واحد مبدأ)',matches[0].data.get('minutes'))])
    table=get_record(db,bid,code,payload['record_id'],lock=True)
    if table.kind!='tax_table' or not table.start_date or table.source_deleted or table.status!='active':fail('جدول مالیات فعال با تاریخ مؤثر انتخاب کنید.')
    brackets,stamp=tax_brackets(db,bid,table)
    cfg=settings_row(db,bid,code,create=True,lock=True);opts=deepcopy(cfg.options or {})
    opts.setdefault('approved_tax_tables',{})[str(table.id)]=stamp;cfg.options=opts;cfg.revision+=1
    audit(db,bid,code,'approve_tax',actor,table,input_hash=stamp);db.commit()
    return result('نسخه جدول و پله‌ها تأیید شد',[('جدول',table.id),('تعداد پله',len(brackets))],warnings=['تأیید به معنی فعال‌سازی مالیات جاری نیست؛ تاریخ اعتبار همچنان بررسی می‌شود.'])
