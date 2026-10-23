"""Explicit manager approval; one immutable journal per canonical business event.

No source-import job calls this module. Imported Sepidar accounting is never
reposted. Accounting proposals and document insertion share a single transaction.
"""
from datetime import datetime
from decimal import Decimal
from copy import deepcopy
import unicodedata
from sqlalchemy import select,func,text,or_
from adapters.db.models.advanced_plugins import AdvancedPluginPosting as Posting,AdvancedPluginPostingConfig as Config,AdvancedPluginRecord as Record
from adapters.db.models.account import Account
from adapters.db.models.business import Business
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.sepidar_live_import import SepidarNativeMap
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from adapters.db.repositories.document_repository import DocumentRepository
from app.services.advanced_plugin_service import fail,number,day,get_record,require_license,settings_row,audit
from app.services.advanced_plugin_operations import digest,depreciation,certificate

ROLES={
 'fixed_assets':{'expense':'هزینه استهلاک','accumulated':'استهلاک انباشته'},
 'contracting':{'main':'درآمد پیمان / هزینه پیمان','settlement':'دریافتنی / پرداختنی پیمان','retention':'سپرده حسن انجام کار','advance':'پیش‌دریافت / پیش‌پرداخت','tax':'مالیات پرداختنی / دریافتنی'},
 'payroll_calendar_tax':{'expense':'طرف بدهکار تعدیل مالیات','payable':'طرف بستانکار تعدیل مالیات'},
 'conditional_pricing':{'receivable':'دریافتنی تعدیل قیمت','revenue':'درآمد تعدیل قیمت','tax':'مالیات تعدیل قیمت'},
 'inventory_trace_cost':{'cogs':'بهای تمام‌شده فروش','inventory':'موجودی کالا'},
}
KINDS={'fixed_assets':'schedule','contracting':'certificate','payroll_calendar_tax':'tax_adjustment','conditional_pricing':'price_adjustment','inventory_trace_cost':'cost_adjustment'}
POLICY='صدور فقط با تأیید مدیر؛ حساب‌های صریح، ارز پایه و سال مالی جاری. داده سپیدار دوباره ثبت نمی‌شود. تعدیل قیمت/بها/مالیات مستقل است و فاکتور، موجودی یا اجرای حقوق را بازنویسی نمی‌کند.'

def posting_lock(db,bid):
    # Transaction-scoped lock also serializes edits of local operational inputs.
    db.execute(text('SELECT pg_advisory_xact_lock(5457233,:bid)'),{'bid':bid})

def assert_event_editable(db,bid,rid):
    if db.scalar(select(Posting.id).where(Posting.business_id==bid,Posting.record_id==rid,Posting.state.in_(['posted','reversed'])).limit(1)):
        fail('رویداد دارای سند مالی صادرشده است؛ بازنویسی یا بایگانی آن مجاز نیست.','FINANCIAL_EVENT_IMMUTABLE',409)

def money(value):
    value=number(value)
    if value is None or value<0 or value>=Decimal('1e16'):
        fail('مبلغ سند باید غیرمنفی و در محدوده دفتر مالی باشد.')
    return value.quantize(Decimal('.01'))

def account(db,bid,aid):
    row=db.scalars(select(Account).where(Account.id==aid,or_(Account.business_id==bid,Account.business_id.is_(None))).with_for_update()).first()
    if not row or db.scalar(select(Account.id).where(Account.parent_id==aid,or_(Account.business_id==bid,Account.business_id.is_(None))).limit(1)):
        fail('حساب باید حساب نهایی همین کسب‌وکار یا کدینگ مشترک باشد.')
    return row

def config_row(db,bid,code):
    return db.scalars(select(Config).where(Config.business_id==bid,Config.plugin_code==code)).first()

def config_dict(row):
    return {'enabled':row.enabled if row else False,'revision':row.revision if row else 0,'accounts':row.accounts if row else {},'contract_side':row.contract_side if row else 'require_review'}

def save_config(db,bid,code,payload,actor):
    require_license(db,bid,code);posting_lock(db,bid)
    if set(payload)-{'revision','enabled','accounts','contract_side'}:fail('تنظیم مالی ناشناخته است.')
    row=config_row(db,bid,code)
    if payload.get('revision')!=(row.revision if row else 0):fail('نسخه تنظیم مالی تغییر کرده است.',status=409)
    enabled=payload.get('enabled',False);accounts=payload.get('accounts',{})
    if not isinstance(enabled,bool) or not isinstance(accounts,dict) or set(accounts)-set(ROLES[code]):fail('تنظیم حساب‌ها معتبر نیست.')
    clean={}
    for role,aid in accounts.items():
        if aid is None or aid=='':continue
        numeric=number(aid)
        if numeric!=numeric.to_integral_value():fail('شناسه حساب باید صحیح باشد.')
        clean[role]=account(db,bid,int(numeric)).id
    side=payload.get('contract_side','require_review')
    if side not in {'require_review','customer','supplier'}:fail('جهت قرارداد معتبر نیست.')
    if enabled and (set(clean)!=set(ROLES[code]) or len(set(clean.values()))<2):fail('حساب‌های لازم را کامل و با حداقل دو حساب متفاوت تنظیم کنید.')
    if enabled and code=='contracting' and side=='require_review':fail('قرارداد فروش به مشتری است یا خرید از پیمانکار؟ جهت را مشخص کنید.')
    if row is None:
        row=Config(business_id=bid,plugin_code=code,revision=0);db.add(row)
    row.enabled=enabled;row.accounts=clean;row.contract_side=side;row.revision+=1;row.updated_by_user_id=actor
    audit(db,bid,code,'financial_settings',actor,revision=row.revision)
    db.commit();return config_dict(row)

def fiscal(db,bid,on_date):
    rows=list(db.scalars(select(FiscalYear).where(FiscalYear.business_id==bid,FiscalYear.is_last.is_(True),FiscalYear.start_date<=on_date,FiscalYear.end_date>=on_date).with_for_update()))
    if len(rows)!=1:fail('تاریخ باید در تنها سال مالی جاری باشد؛ سند در سال بسته صادر نمی‌شود.','FISCAL_YEAR_LOCKED',409)
    return rows[0]

def local_chain(db,bid,code,record):
    chain=[];seen=set();current=record
    while current:
        if current.id in seen or len(seen)>=100:fail('مرجع عملیاتی دوری یا بیش از حد عمیق است.')
        seen.add(current.id)
        if current.source_table or current.source_database or current.source_deleted:
            fail('این عملیات از سپیدار آمده است؛ سند اصلی آن قبلاً منتقل شده یا باید در مبدأ ثبت شود.','SOURCE_ALREADY_ACCOUNTED',409)
        if current.status!='active':fail('عملیات یا مرجع آن فعال نیست.')
        chain.append([current.id,current.revision,current.identity,current.data,str(current.amount),str(current.quantity),str(current.start_date),str(current.end_date),current.person_id,current.currency_id])
        current=get_record(db,bid,code,current.parent_id,lock=True) if current.parent_id else None
    return chain

def native_document(db,bid,did):
    row=db.scalars(select(Document).where(Document.id==did,Document.business_id==bid).with_for_update()).first()
    if not row:fail('سند بومی متعلق به کسب‌وکار پیدا نشد.')
    if (row.extra_info or {}).get('sepidar') or db.scalar(select(SepidarNativeMap.id).where(SepidarNativeMap.business_id==bid,SepidarNativeMap.target_table=='documents',SepidarNativeMap.target_id==did).limit(1)):
        fail('ثبت مکمل برای فاکتور واردشده از سپیدار مجاز نیست؛ تغییر را در مبدأ انجام دهید.','SOURCE_ALREADY_ACCOUNTED',409)
    return row

def proposal(db,bid,code,rid):
    require_license(db,bid,code)
    setting=settings_row(db,bid,code)
    if setting and not setting.enabled:fail('افزونه غیرفعال است.')
    cfg=config_row(db,bid,code)
    if not cfg or not cfg.enabled:fail('مدیر باید ابتدا حساب‌ها و ثبت مالی افزونه را تنظیم کند.')
    row=get_record(db,bid,code,rid,lock=True)
    if row.kind!=KINDS[code]:fail('این نوع رکورد رویداد مالی قابل صدور نیست؛ محاسبه ذخیره‌شده یا تعدیل مشخص را انتخاب کنید.')
    chain=local_chain(db,bid,code,row);business=db.scalars(select(Business).where(Business.id==bid).with_for_update()).one()
    currency=row.currency_id or business.default_currency_id
    if currency!=business.default_currency_id or any(c[-1] not in (None,business.default_currency_id) for c in chain):fail('صدور این نسخه فقط به ارز پایه است؛ تسعیر حدسی انجام نمی‌شود.')
    when=row.end_date if code=='fixed_assets' else row.start_date
    if not when:fail('تاریخ رویداد مالی الزامی است.')
    fy=fiscal(db,bid,when)
    person_id=next((c[-2] for c in chain if c[-2]),None)
    if person_id and not db.scalar(select(Person.id).where(Person.id==person_id,Person.business_id==bid)):fail('شخص سند متعلق به کسب‌وکار نیست.')
    accounts={role:account(db,bid,(cfg.accounts or {}).get(role)) for role in ROLES[code]}
    lines=[];dependencies=[];amount=money(row.amount)
    if amount<=0 and code!='contracting':fail('مبلغ مثبت رویداد لازم است.')
    def line(role,value,debit):
        value=money(value)
        if value:lines.append({'account_id':accounts[role].id,'account_name':accounts[role].name,'role':ROLES[code][role],
            'person_id':person_id,'debit':str(value if debit else Decimal(0)),'credit':str(Decimal(0) if debit else value)})
    event=[code,row.identity]
    if code=='fixed_assets':
        if not row.parent_id or not row.start_date:fail('برنامه استهلاک و دارایی مرجع لازم است.')
        output=depreciation(db,bid,{'record_id':row.parent_id,'from_date':row.start_date,'to_date':row.end_date})
        if output['input_hash']!=row.data.get('input_hash') or money(output['metrics'][1]['value'])!=amount:
            fail('ورودی استهلاک تغییر کرده است؛ برنامه را دوباره محاسبه و ذخیره کنید.','STALE_CALCULATION',409)
        asset=get_record(db,bid,code,row.parent_id)
        prior=list(db.scalars(select(Posting).join(Record,Record.id==Posting.record_id).where(Posting.business_id==bid,Posting.plugin_code==code,Posting.state=='posted',Record.parent_id==asset.id,Record.kind=='schedule').order_by(Posting.id)))
        booked=sum((money(p.proposal['total_debit']) for p in prior),Decimal(0))
        dependencies=['booked_depreciation',[(p.id,p.document_id,p.proposal['total_debit']) for p in prior]]
        cap=money(asset.data.get('cost'))-money(asset.data.get('salvage') or 0)-money(asset.data.get('accumulated') or 0)-booked
        if amount>cap:fail('استهلاک پیشنهادی از ارزش دفتری باقی‌مانده پس از اسناد تأییدشده بیشتر است؛ مانده و گردکردن را بررسی کنید.',status=409)
        event=[code,chain[1][2],str(row.start_date),str(row.end_date)]
        line('expense',amount,True);line('accumulated',amount,False)
    elif code=='contracting':
        if not row.parent_id:fail('صورت‌وضعیت مرجع لازم است.')
        if not person_id:fail('طرف حساب قرارداد یا صورت‌وضعیت را مشخص کنید.')
        statement_lines=list(db.scalars(select(Record).where(Record.business_id==bid,Record.plugin_code==code,Record.kind=='statement_line',Record.parent_id==row.parent_id,Record.status=='active').order_by(Record.id).with_for_update()))
        if any(l.currency_id not in (None,currency) for l in statement_lines):fail('قلم صورت‌وضعیت دارای ارز متفاوت است؛ جمع ارزی حدسی ممنوع است.')
        dependencies=[(l.id,l.revision,l.currency_id) for l in statement_lines]
        output=certificate(db,bid,{'record_id':row.parent_id})
        if output['input_hash']!=row.data.get('input_hash'):fail('صورت‌وضعیت تغییر کرده؛ دوباره محاسبه و ذخیره کنید.','STALE_CALCULATION',409)
        gross,retention,advance,tax,net=[money(m['value']) for m in output['metrics']]
        if net!=amount:fail('مبلغ محاسبه ذخیره‌شده تغییر کرده است.')
        side=cfg.contract_side
        if side not in {'customer','supplier'}:fail('جهت مالی قرارداد تأیید نشده است.')
        customer=side=='customer';event=[code,chain[1][2]]
        line('settlement',net,customer);line('retention',retention,customer);line('advance',advance,customer)
        line('main',gross,not customer);line('tax',tax,not customer)
    else:
        direction=row.data.get('direction')
        if direction not in {'increase','decrease'}:fail('جهت تعدیل باید افزایش یا کاهش باشد.')
        increase=direction=='increase'
        if code=='payroll_calendar_tax':
            reference=' '.join(unicodedata.normalize('NFKC',str(row.data.get('reference') or '')).split()).casefold()
            if not reference:fail('شناسه یکتای مبنای تعدیل مالیات الزامی است.')
            event=[code,'tax_adjustment',reference]
            line('expense',amount,increase);line('payable',amount,not increase)
        elif code=='conditional_pricing':
            document=native_document(db,bid,row.data.get('invoice_document_id'))
            if document.document_type!='invoice_sales' or document.is_proforma or document.currency_id!=currency:fail('فاکتور فروش قطعی بومی با ارز پایه لازم است.')
            if document.fiscal_year_id!=fy.id or document.document_date>when:fail('تاریخ تعدیل یا سال مالی با فاکتور سازگار نیست.')
            event=[code,'price_adjustment',document.id]
            dependencies=[document.id,str(document.updated_at),document.extra_info,
                [(l.id,l.account_id,str(l.debit),str(l.credit)) for l in db.scalars(select(DocumentLine).where(DocumentLine.document_id==document.id).order_by(DocumentLine.id).with_for_update())]]
            source_lines=list(db.scalars(select(DocumentLine).where(DocumentLine.document_id==document.id)))
            if not source_lines or sum(l.debit for l in source_lines)<=0 or sum(l.debit for l in source_lines)!=sum(l.credit for l in source_lines):fail('فاکتور بومی هنوز ثبت مالی متوازن ندارد.')
            parties={l.person_id for l in source_lines if l.person_id}
            if person_id and parties and person_id not in parties:fail('طرف حساب تعدیل در فاکتور وجود ندارد.')
            if len(parties)==1:
                original_person=next(iter(parties))
                if person_id and person_id!=original_person:fail('طرف حساب تعدیل با فاکتور متفاوت است.')
                person_id=original_person
            if not person_id:fail('طرف حساب تعدیل قیمت را مشخص کنید.')
            if not db.scalar(select(Person.id).where(Person.id==person_id,Person.business_id==bid)):fail('طرف حساب فاکتور متعلق به کسب‌وکار نیست.')
            tax=money(row.data.get('tax_amount') or 0)
            line('receivable',amount+tax,increase);line('revenue',amount,not increase);line('tax',tax,not increase)
        else:
            native=db.execute(select(WarehouseDocumentLine,WarehouseDocument).join(WarehouseDocument).where(WarehouseDocumentLine.id==row.data.get('warehouse_document_line_id'),WarehouseDocument.business_id==bid).with_for_update()).first()
            if not native:fail('ردیف حواله بومی پیدا نشد.')
            wl,wh=native
            if wh.source_type=='sepidar' or (wh.extra_info or {}).get('sepidar') or (wl.extra_info or {}).get('sepidar_source_id') is not None:
                fail('بهای واردشده سپیدار دوباره ثبت نمی‌شود.','SOURCE_ALREADY_ACCOUNTED',409)
            if wh.status!='posted' or wl.movement!='out' or wh.doc_type not in {'issue','production_out'}:fail('تعدیل بها به خروج قطعی بومی نیاز دارد.')
            if wh.fiscal_year_id!=fy.id or wh.document_date>when:fail('سال مالی یا تاریخ حواله با تعدیل سازگار نیست.')
            if wh.source_document_id:native_document(db,bid,wh.source_document_id)
            event=[code,'cost_adjustment',wl.id]
            dependencies=[wl.id,str(wl.quantity),wl.extra_info,wh.status,str(wh.updated_at),wh.extra_info]
            line('cogs',amount,increase);line('inventory',amount,not increase)
    debit=sum((Decimal(l['debit']) for l in lines),Decimal(0));credit=sum((Decimal(l['credit']) for l in lines),Decimal(0))
    if debit<=0 or debit!=credit or len({l['account_id'] for l in lines})<2:fail('سند باید مثبت، متوازن و دارای حساب‌های متفاوت باشد.')
    result={'record_id':row.id,'title':row.title,'document_date':str(when),'fiscal_year_id':fy.id,'currency_id':currency,
        'lines':lines,'total_debit':str(debit),'total_credit':str(credit),'policy':POLICY}
    result['event_key']=digest(event)
    result['inputs']={'records':deepcopy(chain),'configuration':config_dict(cfg),'dependencies':deepcopy(dependencies)}
    result['input_hash']=digest(result)
    return result

def posting_dict(db,row):
    result={k:getattr(row,k) for k in ['id','plugin_code','record_id','state','revision','input_hash','proposal','document_id','reversal_document_id','created_by_user_id','approved_by_user_id','reversed_by_user_id','decision_reason']}
    for key in ['created_at','approved_at','reversed_at']:
        value=getattr(row,key);result[key]=value.isoformat() if value else None
    return result

def get_posting(db,bid,code,pid):
    row=db.scalars(select(Posting).where(Posting.id==pid,Posting.business_id==bid,Posting.plugin_code==code).with_for_update()).first()
    if not row:fail('پیش‌نویس مالی پیدا نشد.',status=404)
    return row

def prepare(db,bid,code,rid,actor):
    require_license(db,bid,code);posting_lock(db,bid)
    existing=db.scalars(select(Posting).where(Posting.business_id==bid,Posting.plugin_code==code,Posting.record_id==rid)).first()
    if existing:return posting_dict(db,existing)
    draft=proposal(db,bid,code,rid)
    row=db.scalars(select(Posting).where(Posting.business_id==bid,Posting.plugin_code==code,Posting.event_key==draft['event_key'])).first()
    if row:
        if row.record_id!=rid:fail('این رویداد با رکورد دیگری پیش‌نویس یا ثبت شده است؛ ایجاد رکورد جدید کنترل تکرار را دور نمی‌زند.','DUPLICATE_FINANCIAL_EVENT',409)
        return posting_dict(db,row)
    row=Posting(business_id=bid,plugin_code=code,record_id=rid,event_key=draft['event_key'],state='draft',revision=1,input_hash=draft['input_hash'],proposal=draft,created_by_user_id=actor)
    db.add(row);db.flush();audit(db,bid,code,'financial_draft',actor,record_id=rid,posting_id=row.id,input_hash=row.input_hash)
    db.commit();return posting_dict(db,row)

def refresh(db,bid,code,pid,payload,actor):
    require_license(db,bid,code)
    if set(payload)!={'revision'}:fail('فقط نسخه پیش‌نویس برای بازسازی ارسال شود.')
    posting_lock(db,bid);row=get_posting(db,bid,code,pid)
    if row.state not in {'draft','rejected'} or payload.get('revision')!=row.revision:fail('پیش‌نویس قابل بازسازی نیست یا نسخه تغییر کرده است.',status=409)
    new=proposal(db,bid,code,row.record_id)
    if new['event_key']!=row.event_key:fail('هویت رویداد تغییر کرده؛ پیش‌نویس دیگری بسازید.',status=409)
    row.proposal=new;row.input_hash=new['input_hash'];row.state='draft';row.revision+=1;row.decision_reason=None
    audit(db,bid,code,'financial_refresh',actor,posting_id=row.id)
    db.commit();return posting_dict(db,row)

def create_journal(db,bid,row,actor,*,reverse=False,on_date=None):
    p=deepcopy(row.proposal);when=day(on_date or p['document_date']);fy=fiscal(db,bid,when)
    journal_code=f'ADPR-{row.id}' if reverse else f'ADP-{row.id}'
    if db.scalar(select(Document.id).where(Document.business_id==bid,Document.code==journal_code).limit(1)):
        fail('کد رزروشده این سند قبلاً استفاده شده است؛ سند موجود را بررسی کنید. سند دیگری خودکار جایگزین یا حذف نمی‌شود.',status=409)
    if not reverse and fy.id!=p['fiscal_year_id']:fail('سال مالی پیش‌نویس تغییر کرده است.',status=409)
    business=db.get(Business,bid)
    if business.default_currency_id!=p['currency_id']:fail('ارز پایه تغییر کرده؛ ثبت مجدد بررسی شود.',status=409)
    lines=[]
    for item in p['lines']:
        account(db,bid,item['account_id'])
        if item.get('person_id') and not db.scalar(select(Person.id).where(Person.id==item['person_id'],Person.business_id==bid)):fail('شخص مرجع سند معتبر نیست.')
        debit=Decimal(item['credit'] if reverse else item['debit']);credit=Decimal(item['debit'] if reverse else item['credit'])
        lines.append({'account_id':item['account_id'],'person_id':item.get('person_id'),'debit':debit,'credit':credit,
            'exchange_rate':Decimal(1),'debit_base':debit,'credit_base':credit,'description':item['role'],
            'extra_info':{'advanced_plugin_posting_id':row.id,'reversal':reverse}})
    return DocumentRepository(db).create_document({'business_id':bid,'code':journal_code,
        'fiscal_year_id':fy.id,'currency_id':p['currency_id'],'created_by_user_id':actor,'document_date':when,
        'document_type':'advanced_plugin_reversal' if reverse else 'advanced_plugin_journal','is_proforma':False,
        'description':('برگشت: ' if reverse else '')+p['title'],
        'extra_info':{'advanced_plugin':{'posting_id':row.id,'plugin_code':row.plugin_code,'record_id':row.record_id,'input_hash':row.input_hash,'reversal_of':row.document_id if reverse else None},'locked':True},'lines':lines},auto_commit=False)

def decide(db,bid,code,pid,action,payload,actor):
    require_license(db,bid,code);posting_lock(db,bid);row=get_posting(db,bid,code,pid)
    if set(payload)-{'revision','input_hash','confirmed','reason','on_date'}:fail('درخواست مالی دارای فیلد ناشناخته است.')
    if payload.get('confirmed') is not True or payload.get('input_hash')!=row.input_hash:fail('تأیید صریح نسخه پیش‌نویس لازم است.',status=409)
    if action=='approve' and row.state=='posted':return posting_dict(db,row)
    if action=='reverse' and row.state=='reversed':return posting_dict(db,row)
    if payload.get('revision')!=row.revision:fail('نسخه پیش‌نویس تغییر کرده است.',status=409)
    reason=str(payload.get('reason') or '').strip()
    if len(reason)<5 or len(reason)>1500:fail('دلیل تصمیم مدیر را بین ۵ تا ۱۵۰۰ نویسه وارد کنید.')
    if action=='approve':
        if row.state!='draft':fail('فقط پیش‌نویس قابل تأیید است.',status=409)
        fresh=proposal(db,bid,code,row.record_id)
        if fresh['input_hash']!=row.input_hash:fail('مبلغ، حساب‌ها یا مبدأ تغییر کرده؛ پیش‌نویس را بازسازی و دوباره بررسی کنید.','STALE_FINANCIAL_DRAFT',409)
        doc=create_journal(db,bid,row,actor);row.document_id=doc.id;row.state='posted';row.approved_by_user_id=actor;row.approved_at=datetime.utcnow()
    elif action=='reject':
        if row.state!='draft':fail('فقط پیش‌نویس قابل رد است.',status=409)
        row.state='rejected'
    elif action=='reverse':
        if row.state!='posted' or not row.document_id:fail('فقط سند صادرشده قابل برگشت است.',status=409)
        original=db.scalars(select(Document).where(Document.id==row.document_id,Document.business_id==bid).with_for_update()).first()
        if not original:fail('سند اصلی پیدا نشد.',status=409)
        if original.document_type!='advanced_plugin_journal' or (original.extra_info or {}).get('advanced_plugin',{}).get('posting_id')!=row.id:
            fail('پیوند سند اصلی با رویداد مالی معتبر نیست.',status=409)
        actual=sorted((l.account_id,l.person_id,Decimal(l.debit),Decimal(l.credit)) for l in db.scalars(select(DocumentLine).where(DocumentLine.document_id==original.id)))
        expected=sorted((l['account_id'],l.get('person_id'),Decimal(l['debit']),Decimal(l['credit'])) for l in row.proposal['lines'])
        if actual!=expected:fail('سند اصلی خارج از مسیر مجاز تغییر کرده؛ برگشت خودکار متوقف شد.',status=409)
        if not payload.get('on_date'):fail('تاریخ برگشت را مشخص کنید.')
        if day(payload['on_date'])<original.document_date:fail('برگشت نمی‌تواند قبل از سند اصلی باشد.')
        doc=create_journal(db,bid,row,actor,reverse=True,on_date=payload['on_date']);row.reversal_document_id=doc.id;row.state='reversed';row.reversed_by_user_id=actor;row.reversed_at=datetime.utcnow()
    else:fail('تصمیم مالی ناشناخته است.')
    row.decision_reason=reason;row.revision+=1
    audit(db,bid,code,'financial_'+action,actor,posting_id=row.id,document_id=row.document_id,reversal_document_id=row.reversal_document_id,input_hash=row.input_hash,reason=reason)
    # The posting link, document header, all lines and audit commit together.
    db.commit()
    if action in {'approve','reverse'}:
        from app.services.document_service import invalidate_documents_cache
        invalidate_documents_cache(bid)
    return posting_dict(db,row)

def workspace(db,bid,code):
    require_license(db,bid,code)
    rows=list(db.scalars(select(Posting).where(Posting.business_id==bid,Posting.plugin_code==code).order_by(Posting.id.desc()).limit(100)))
    candidates=db.scalars(select(Record).where(Record.business_id==bid,Record.plugin_code==code,Record.kind==KINDS[code],Record.source_table.is_(None),Record.source_deleted.is_(False),Record.status=='active').order_by(Record.id.desc()).limit(100))
    return {'config':config_dict(config_row(db,bid,code)),'roles':ROLES[code],'eligible_kind':KINDS[code],'policy':POLICY,
        'items':[posting_dict(db,r) for r in rows],'candidates':[{'id':r.id,'title':r.title,'amount':str(r.amount),'date':str(r.end_date if code=='fixed_assets' else r.start_date)} for r in candidates]}
