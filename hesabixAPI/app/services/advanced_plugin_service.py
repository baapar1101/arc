"""Validated native workspaces; no provider calls, charges or implicit GL posting."""
from copy import deepcopy
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from hashlib import sha256
from uuid import uuid4
from sqlalchemy import select, func, or_
from adapters.db.models.advanced_plugins import AdvancedPluginSetting as Setting, AdvancedPluginRecord as Record, AdvancedPluginAudit as Audit
from adapters.db.models.business import Business
from adapters.db.models.product import Product
from adapters.db.models.person import Person
from adapters.db.models.warehouse import Warehouse
from adapters.db.models.currency import Currency, BusinessCurrency
from adapters.db.models.marketplace import MarketplacePlugin, BusinessPlugin
from app.core.responses import ApiError
from app.services.advanced_plugin_catalog import MODULES, default_options, public_catalog


def fail(message, code='ADVANCED_PLUGIN_VALIDATION', status=400):
    raise ApiError(code, message, http_status=status)


def number(value, default=None):
    if value is None or value=='':
        return default
    try:
        out=Decimal(str(value))
        if not out.is_finite() or abs(out)>=Decimal('1e18'):
            fail('عدد خارج از محدوده یا نامعتبر است.')
        return out
    except (InvalidOperation, ValueError, TypeError):
        fail('عدد معتبر وارد کنید.')


def day(value):
    if isinstance(value, date):return value.date() if isinstance(value,datetime) else value
    try:return date.fromisoformat(str(value)[:10])
    except (ValueError,TypeError):fail('تاریخ باید به شکل YYYY-MM-DD باشد.')


def module(code):
    if code not in MODULES:fail('افزونه تخصصی شناخته نشد.',status=404)
    return MODULES[code]


def licensed(db,bid,code):
    now=datetime.utcnow()
    return db.scalar(select(BusinessPlugin.id).join(MarketplacePlugin).where(
        BusinessPlugin.business_id==bid, MarketplacePlugin.code==code,MarketplacePlugin.is_active.is_(True),
        BusinessPlugin.status=='active',BusinessPlugin.starts_at<=now,
        or_(BusinessPlugin.ends_at.is_(None),BusinessPlugin.ends_at>=now))) is not None


def require_license(db,bid,code):
    module(code)
    if not licensed(db,bid,code):fail('افزونه برای این کسب‌وکار فعال نیست.','ADVANCED_PLUGIN_NOT_ACTIVE',403)


def settings_row(db,bid,code,*,create=False,lock=False):
    module(code)
    q=select(Setting).where(Setting.business_id==bid,Setting.plugin_code==code)
    if lock:q=q.with_for_update()
    row=db.scalars(q).first()
    if row is None and create:
        row=Setting(business_id=bid,plugin_code=code,enabled=True,sync_enabled=False,options=default_options(code))
        db.add(row);db.flush()
    return row


def settings(db,bid,code):
    row=settings_row(db,bid,code)
    options={**default_options(code),**(row.options or {} if row else {})}
    # Approval hashes are server-controlled, not writable via the settings form.
    options.pop('approved_tax_tables',None)
    return {'enabled':row.enabled if row else True,'sync_enabled':row.sync_enabled if row else False,
        'options':options,'revision':row.revision if row else 0,
        'last_synced_at':row.last_synced_at.isoformat() if row and row.last_synced_at else None,
        'sync_summary':row.sync_summary if row else None}


def audit(db,bid,code,action,actor=None,record=None,**details):
    db.add(Audit(business_id=bid,plugin_code=code,action=action,actor_user_id=actor,
        record_id=record.id if record else None,details=details))


def _reference(db,bid,code,name,value,typ):
    target={'product':Product,'person':Person,'warehouse':Warehouse,'parent':Record,'currency':Currency}[typ]
    obj=db.get(target,value)
    if not obj or (typ!='currency' and obj.business_id!=bid):fail(f'مرجع {name} متعلق به این کسب‌وکار نیست.')
    if typ=='parent' and (obj.plugin_code!=code or obj.source_deleted or obj.status=='archived'):
        fail('رکورد مرجع غیرفعال یا متعلق به افزونه دیگری است.')
    if typ=='currency' and not db.scalar(select(BusinessCurrency.id).where(BusinessCurrency.business_id==bid,BusinessCurrency.currency_id==value)):
        business=db.get(Business,bid)
        if not business or business.default_currency_id!=value:fail('ارز در کسب‌وکار فعال نیست.')
    if name in {'tax_group_id','trace_id'} and obj.kind!=('tax_group' if name=='tax_group_id' else 'trace'):
        fail('نوع مرجع انتخاب‌شده صحیح نیست.')
    return value


def validate_fields(db,bid,code,definitions,payload,*,partial=False):
    if not isinstance(payload,dict):fail('ساختار فرم معتبر نیست.')
    unknown=set(payload)-set(definitions)
    if unknown:fail('فیلد ناشناخته: '+', '.join(sorted(unknown)))
    result={}
    for name,spec in definitions.items():
        if name not in payload:
            if not partial and spec.get('required'):fail(f"{spec['label']} الزامی است.")
            continue
        value=payload[name]
        if value is None or value=='':
            if spec.get('required'):fail(f"{spec['label']} الزامی است.")
            result[name]=None;continue
        typ=spec['type']
        if typ=='boolean':
            if not isinstance(value,bool):fail('مقدار انتخابی باید بله/خیر باشد.')
        elif typ=='date':value=day(value).isoformat()
        elif typ in {'integer','decimal','product','person','warehouse','parent','currency'}:
            numeric=number(value)
            if typ!='decimal' and numeric!=numeric.to_integral_value():fail('شناسه / مقدار باید عدد صحیح باشد.')
            if 'min' in spec and numeric<Decimal(str(spec['min'])):fail(f"{spec['label']} کمتر از حد مجاز است.")
            if 'max' in spec and numeric>Decimal(str(spec['max'])):fail(f"{spec['label']} بیش از حد مجاز است.")
            if typ=='decimal' and numeric!=numeric.quantize(Decimal('.000001')):fail('حداکثر شش رقم اعشار پشتیبانی می‌شود.')
            value=str(numeric) if typ=='decimal' else int(numeric)
            if typ in {'product','person','warehouse','parent','currency'}:
                _reference(db,bid,code,name,value,typ)
        else:
            value=str(value).strip()
            if len(value)>500:fail('متن بیش از حد طولانی است.')
            if typ=='choice' and value not in spec.get('choices',[]):fail('گزینه انتخابی معتبر نیست.')
        result[name]=value
    return result


def save_settings(db,bid,code,payload,actor):
    require_license(db,bid,code)
    if set(payload)-{'revision','enabled','sync_enabled','options'}:fail('تنظیم ناشناخته است.')
    row=settings_row(db,bid,code,create=True,lock=True)
    if payload.get('revision')!=row.revision and not (row.revision==1 and payload.get('revision')==0):
        fail('تنظیمات هم‌زمان تغییر کرده؛ صفحه را تازه کنید.','ADVANCED_PLUGIN_CONFLICT',409)
    values=validate_fields(db,bid,code,MODULES[code]['options'],payload.get('options',{}),partial=True)
    for name in ['enabled','sync_enabled']:
        if name in payload and not isinstance(payload[name],bool):fail('وضعیت تنظیم باید بله/خیر باشد.')
    if payload.get('sync_enabled'):
        from adapters.db.models.sepidar_live_import import SepidarImportSetting
        source=db.scalars(select(SepidarImportSetting).where(SepidarImportSetting.business_id==bid)).first()
        if not source or not source.enabled or not source.native_enabled or not source.plugins_enabled or source.included_schemas or source.included_tables:
            fail('اتصال سپیدار، تبدیل بومی، پل افزونه‌ها و Snapshot کامل باید فعال باشند.')
        if not licensed(db,bid,'sepidar_live_import'):fail('مجوز اتصال سپیدار فعال نیست.')
        if code=='inventory_trace_cost' and not source.operations_enabled:fail('همگام‌سازی انبار بومی را هم فعال کنید.')
    row.options={**default_options(code),**(row.options or {}),**values}
    for name in ['enabled','sync_enabled']:
        if name in payload:setattr(row,name,payload[name])
    row.revision+=1
    audit(db,bid,code,'settings',actor,revision=row.revision)
    db.commit()
    return settings(db,bid,code)


TOP={'title','code','start_date','end_date','amount','quantity','currency_id','product_id','person_id','parent_id'}


def record_dict(row,*,detail=False):
    out={name:getattr(row,name) for name in ['id','plugin_code','kind','status','revision','source_deleted',*TOP]}
    for name in ['start_date','end_date']:
        if out[name]:out[name]=out[name].isoformat()
    for name in ['amount','quantity']:
        if out[name] is not None:out[name]=str(out[name])
    out.update(data=row.data or {},managed=bool(row.source_table),source_table=row.source_table,
        source_database=row.source_database,updated_at=row.updated_at.isoformat() if row.updated_at else None)
    if detail:out.update(source_key=row.source_key,source_payload=row.source_payload)
    return out


def get_record(db,bid,code,rid,*,lock=False):
    q=select(Record).where(Record.id==rid,Record.business_id==bid,Record.plugin_code==code)
    if lock:q=q.with_for_update()
    row=db.scalars(q).first()
    if not row:fail('رکورد پیدا نشد.','NOT_FOUND',404)
    return row


def list_records(db,bid,code,kind=None,q='',skip=0,take=50,parent_id=None,include_archived=False):
    require_license(db,bid,code)
    query=select(Record).where(Record.business_id==bid,Record.plugin_code==code)
    if kind:
        if kind not in module(code)['kinds']:fail('نوع رکورد معتبر نیست.')
        query=query.where(Record.kind==kind)
    if parent_id is not None:query=query.where(Record.parent_id==parent_id)
    if not include_archived:query=query.where(Record.status!='archived',Record.source_deleted.is_(False))
    if q:query=query.where(or_(Record.title.ilike('%'+q[:150]+'%'),Record.code.ilike('%'+q[:150]+'%')))
    total=db.scalar(select(func.count()).select_from(query.subquery()))
    return {'items':[record_dict(r) for r in db.scalars(query.order_by(Record.id).offset(skip).limit(take))],'total':total}


def _validate_domain(db,bid,code,kind,values):
    start,end=values.get('start_date'),values.get('end_date')
    if start and end and day(start)>day(end):fail('پایان بازه قبل از شروع است.')
    if values.get('amount') is not None and number(values['amount'])!=number(values['amount']).quantize(Decimal('.0001')):
        fail('مبلغ حداکثر چهار رقم اعشار دارد.')
    if kind=='asset':
        cost=number(values.get('cost'),Decimal(0));salvage=number(values.get('salvage'),Decimal(0));acc=number(values.get('accumulated'),Decimal(0))
        if salvage+acc>cost:fail('اسقاط و استهلاک انباشته از بهای تحصیل بیشتر است.')
    if kind=='tax_bracket':
        if not values.get('parent_id'):fail('جدول مالیات مرجع الزامی است.')
        if get_record(db,bid,code,values['parent_id']).kind!='tax_table':fail('مرجع پله باید جدول مالیات باشد.')
        if values.get('to_amount') is not None and number(values['to_amount'])<=number(values.get('from_amount'),Decimal(0)):
            fail('سقف پله باید از کف بیشتر باشد.')
    if kind in {'statement','guarantee','statement_line'} and values.get('parent_id'):
        expected='statement' if kind=='statement_line' else 'contract'
        if get_record(db,bid,code,values['parent_id']).kind!=expected:fail('نوع رکورد مرجع مناسب نیست.')
    if kind=='price_rule':
        if not values.get('product_id') or not values.get('currency_id') or values.get('amount') is None:fail('کالا، ارز و قیمت قاعده الزامی است.')
        if values.get('max_qty') is not None and number(values['max_qty'])<number(values.get('min_qty'),Decimal(0)):fail('بازه مقدار معتبر نیست.')
    if kind in {'receipt_layer','issue'}:
        from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
        from adapters.db.models.warehouse_document import WarehouseDocument
        line=db.scalars(select(WarehouseDocumentLine).join(WarehouseDocument).where(
            WarehouseDocumentLine.id==values.get('warehouse_document_line_id'),WarehouseDocument.business_id==bid,
            WarehouseDocument.status=='posted').with_for_update(of=WarehouseDocumentLine)).first()
        if not line or line.movement!=('in' if kind=='receipt_layer' else 'out'):fail('رسید/حواله بومی متناسب پیدا نشد.')
        if values.get('product_id') not in (None,line.product_id) or values.get('warehouse_id') not in (None,line.warehouse_id):fail('کالا یا انبار با ردیف بومی تطابق ندارد.')
        _reference(db,bid,code,'product_id',line.product_id,'product')
        _reference(db,bid,code,'warehouse_id',line.warehouse_id,'warehouse')
        if values.get('fiscal_year_id') not in (None,line.document.fiscal_year_id):fail('سال مالی با رسید/حواله بومی تطابق ندارد.')
        if values.get('start_date') and day(values['start_date'])!=line.document.document_date:fail('تاریخ لایه باید تاریخ ردیف انبار بومی باشد.')
        values.update(product_id=line.product_id,warehouse_id=line.warehouse_id,fiscal_year_id=line.document.fiscal_year_id,start_date=line.document.document_date)
        if not values.get('quantity') or number(values['quantity'])<=0 or number(values['quantity'])>line.quantity:fail('مقدار باید مثبت و حداکثر مقدار ردیف بومی باشد.')
        others=db.scalars(select(Record).where(Record.business_id==bid,Record.plugin_code==code,Record.kind.in_(['receipt_layer','issue']),Record.status!='archived')).all()
        used=sum((number(r.quantity,Decimal(0)) for r in others if r.data.get('warehouse_document_line_id')==line.id and r.id!=values.get('_id')),Decimal(0))
        if used+number(values['quantity'])>line.quantity:fail('تخصیص بچ‌ها از مقدار ردیف بومی بیشتر می‌شود.')


def save_record(db,bid,code,kind,payload,actor,rid=None):
    require_license(db,bid,code)
    cfg=settings_row(db,bid,code)
    if cfg and not cfg.enabled:fail('افزونه در تنظیمات غیرفعال است.')
    spec=module(code)['kinds'].get(kind)
    if not spec or not spec.get('local'):fail('این نوع رکورد فقط توسط عملیات یا همگام‌سازی ساخته می‌شود.')
    row=get_record(db,bid,code,rid,lock=True) if rid else None
    if row and row.kind!=kind:fail('نوع رکورد قابل تغییر نیست.')
    if row and row.source_table:fail('رکورد تحت مدیریت سپیدار است؛ تغییر را در مبدأ انجام دهید.','SEPIDAR_SOURCE_MANAGED',409)
    if row and payload.get('revision')!=row.revision:fail('نسخه رکورد تغییر کرده؛ دوباره بارگذاری کنید.','ADVANCED_PLUGIN_CONFLICT',409)
    values=validate_fields(db,bid,code,spec['fields'],{k:v for k,v in payload.items() if k not in {'revision','status'}},partial=bool(row))
    if row:values={**{k:getattr(row,k) for k in TOP},**(row.data or {}),**values}
    validation_values={**values,'_id':rid}
    _validate_domain(db,bid,code,kind,validation_values)
    values={k:v for k,v in validation_values.items() if k!='_id'}
    status=payload.get('status',row.status if row else 'active')
    if status not in {'active','draft','archived'}:fail('وضعیت رکورد معتبر نیست.')
    if not row:
        row=Record(business_id=bid,plugin_code=code,kind=kind,identity=sha256(uuid4().bytes).hexdigest(),title=values['title'],data={})
        db.add(row)
    parent=values.get('parent_id')
    seen={row.id} if row.id else set()
    for _ in range(100):
        if not parent:break
        if parent in seen:fail('رابطه مرجع دوری است.')
        seen.add(parent);parent=get_record(db,bid,code,parent).parent_id
    else:fail('عمق مرجع بیش از حد مجاز است.')
    for key in TOP:
        if key in values:setattr(row,key,day(values[key]) if key in {'start_date','end_date'} and values[key] else values[key])
    row.data={k:v for k,v in values.items() if k not in TOP}
    row.status=status;row.revision=(row.revision or 0)+1
    db.flush();audit(db,bid,code,'update' if rid else 'create',actor,row,revision=row.revision)
    db.commit();return record_dict(row,detail=True)


def overview(db,bid):
    result=[]
    for spec in public_catalog():
        code=spec['code'];allowed=licensed(db,bid,code)
        counts=dict(db.execute(select(Record.kind,func.count()).where(Record.business_id==bid,Record.plugin_code==code,Record.source_deleted.is_(False),Record.status!='archived').group_by(Record.kind)).all()) if allowed else {}
        result.append({**spec,'licensed':allowed,'settings':settings(db,bid,code) if allowed else None,'counts':counts})
    return {'items':result,'policy':'Source managed; no automatic ledger, stock or wallet posting'}


def references(db,bid,code,typ,q=''):
    require_license(db,bid,code)
    if typ=='parent':
        rows=db.scalars(select(Record).where(Record.business_id==bid,Record.plugin_code==code,Record.status!='archived',Record.source_deleted.is_(False),Record.title.ilike('%'+q[:100]+'%')).order_by(Record.id.desc()).limit(60))
        return [{'id':r.id,'label':f'{module(code)["kinds"].get(r.kind,{}).get("label",r.kind)} — {r.title}','kind':r.kind} for r in rows]
    model={'product':Product,'person':Person,'warehouse':Warehouse,'currency':Currency}.get(typ)
    if not model:fail('نوع مرجع معتبر نیست.')
    query=select(model)
    if typ=='currency':
        business=db.get(Business,bid)
        ids=list(db.scalars(select(BusinessCurrency.currency_id).where(BusinessCurrency.business_id==bid)))+[business.default_currency_id]
        query=query.where(Currency.id.in_(ids))
    else:query=query.where(model.business_id==bid)
    if q:
        if typ=='person':query=query.where(or_(Person.first_name.ilike('%'+q[:100]+'%'),Person.last_name.ilike('%'+q[:100]+'%')))
        else:query=query.where((Currency.title if typ=='currency' else model.name).ilike('%'+q[:100]+'%'))
    rows=db.scalars(query.order_by(model.id).limit(60))
    return [{'id':r.id,'label':(' '.join(filter(None,[r.first_name,r.last_name])) if typ=='person' else getattr(r,'name',None) or getattr(r,'title',None) or str(r.id))} for r in rows]
