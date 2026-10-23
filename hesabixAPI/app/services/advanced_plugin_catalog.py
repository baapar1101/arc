"""Server-owned domain schemas, UI forms and explicit Sepidar field mappings."""

def field(label, type='text', required=False, **kwargs):
    return dict(label=label, type=type, required=required, **kwargs)


COMMON = {
    'title': field('عنوان', required=True), 'code': field('کد'),
    'start_date': field('تاریخ شروع / مؤثر', 'date'), 'end_date': field('تاریخ پایان / سررسید', 'date'),
    'amount': field('مبلغ', 'decimal', min='0'), 'quantity': field('مقدار', 'decimal', min='0'),
    'currency_id': field('واحد پول', 'currency'), 'product_id': field('کالا', 'product'),
    'person_id': field('شخص', 'person'), 'parent_id': field('رکورد مرجع همین افزونه', 'parent'),
}


def entity(label, fields=None, *, local=True):
    return dict(label=label, fields={**COMMON, **(fields or {})}, local=local)


MODULES = {
    'fixed_assets': dict(name='دارایی ثابت و استهلاک', category='operations', description='دفتر دارایی، گروه و محل، بهای تحصیل و رویدادها، برنامه استهلاک و اتصال AST سپیدار.', kinds={
        'asset': entity('دارایی', {'cost':field('بهای تحصیل','decimal',True,min='0'), 'salvage':field('ارزش اسقاط','decimal',min='0'), 'accumulated':field('استهلاک انباشته ابتدای دوره','decimal',min='0'), 'useful_life_years':field('عمر مفید (سال)','decimal',min='0.01'), 'annual_rate':field('نرخ سالانه (%)','decimal',min='0',max='100'), 'method':field('روش استهلاک','choice',choices=['straight_line','declining']), 'location':field('محل استقرار')}),
        'rule': entity('قاعده استهلاک', {'annual_rate':field('نرخ (%)','decimal',min='0',max='100'),'useful_life_years':field('عمر مفید (سال)','decimal',min='0'),'method':field('روش','choice',choices=['none','straight_line','declining'])}),
        'asset_group':entity('گروه دارایی'), 'asset_class':entity('طبقه دارایی'), 'location':entity('محل استقرار'),
        'cost_part':entity('جزء بهای دارایی'), 'acquisition':entity('رسید تحصیل'), 'acquisition_line':entity('قلم تحصیل',local=False),
        'asset_event':entity('گردش دارایی',local=False), 'depreciation':entity('عملیات استهلاک',local=False),
        'depreciation_line':entity('جزئیات استهلاک',local=False), 'schedule':entity('برنامه محاسبه‌شده استهلاک',local=False),
        'source_event':entity('سایر عملیات و سوابق مبدأ',local=False),
    }, options={'day_basis':field('مبنای سال محاسبه استهلاک','integer',min=360,max=366,default=365)}),
    'contracting': dict(name='پیمانکاری و صورت‌وضعیت', category='operations', description='پروژه، قرارداد، صورت‌وضعیت و کسور، ضمانت‌نامه و سررسید، همگام‌سازی CNT سپیدار.', kinds={
        'project':entity('پروژه'),
        'contract':entity('قرارداد',{'retention_percent':field('کسور حسن انجام کار (%)','decimal',min='0',max='100'),'advance_percent':field('استهلاک پیش‌پرداخت (%)','decimal',min='0',max='100'),'tax_percent':field('مالیات / افزوده توافقی (%)','decimal',min='0',max='100')}),
        'statement':entity('صورت‌وضعیت',{'retention_percent':field('کسور (%)','decimal',min='0',max='100'),'advance_amount':field('استهلاک پیش‌پرداخت','decimal',min='0'),'tax_percent':field('افزوده (%)','decimal',min='0',max='100')}),
        'statement_line':entity('قلم صورت‌وضعیت',{'unit_price':field('فی','decimal',True,min='0')}),
        'guarantee':entity('ضمانت‌نامه',{'bank':field('بانک / صادرکننده'),'guarantee_type':field('نوع ضمانت‌نامه')}),
        'coefficient':entity('ضریب',{'rate':field('ضریب (%)','decimal')}), 'cost_type':entity('نوع هزینه'),
        'warranty_type':entity('نوع ضمانت‌نامه'), 'contract_type':entity('نوع قرارداد'),
        'certificate':entity('محاسبه صورت‌وضعیت',local=False), 'source_event':entity('سوابق، هزینه و تسویه مبدأ',local=False),
    }, options={'due_warning_days':field('هشدار سررسید ضمانت‌نامه (روز)','integer',min=0,max=365,default=30)}),
    'payroll_calendar_tax': dict(name='تقویم حقوق، مرخصی و مالیات تاریخ‌دار', category='hr_payroll', description='تقویم سال/ماه، مانده مرخصی، گروه مالیات و جداول دارای تاریخ اعتبار و تأیید مستقل؛ بدون فعال‌سازی مالیات تاریخی.', kinds={
        'calendar':entity('تقویم حقوق',{'solar_year':field('سال شمسی','integer',True,min=1300,max=1600),'month':field('ماه','integer',True,min=1,max=12),'days':field('روز کاری','integer',min=0,max=31),'daily_minutes':field('دقیقه کار روزانه','integer',min=0,max=1440)}),
        'daily_hours':entity('ساعات روزانه سال',{'solar_year':field('سال','integer',True,min=1300,max=1600),'daily_minutes':field('دقیقه روزانه','integer',True,min=0,max=1440)}),
        'leave':entity('مانده مرخصی',{'solar_year':field('سال','integer',min=1300,max=1600),'month':field('ماه','integer',min=1,max=12),'minutes':field('مانده مرخصی (واحد مبدأ؛ نه گردش)','decimal')}),
        'tax_group':entity('گروه مالیات'),
        'tax_table':entity('جدول مالیات',{'tax_group_id':field('شناسه گروه مالیات','parent'),'tax_scope':field('نوع درآمد','choice',choices=['salary','bonus'],default='salary'),'tax_type':field('روش محاسبه','choice',choices=['progressive'])}),
        'tax_bracket':entity('پله مالیات',{'from_amount':field('از مبلغ','decimal',True,min='0'),'to_amount':field('تا مبلغ؛ خالی یعنی بدون سقف','decimal',min='0'),'rate':field('نرخ (%)','decimal',True,min='0',max='100')}),
        'personnel':entity('پرسنل مبدأ',local=False), 'source_event':entity('سوابق حقوق مبدأ',local=False),
    }, options={'max_tax_age_days':field('حداکثر عمر جدول مالیات بدون تاریخ پایان (روز)','integer',min=1,max=366,default=366),'auto_apply_tax':field('اعمال جدول تأییدشده در محاسبه حقوق بومی','boolean',default=False),'tax_group_id':field('شناسه گروه مالیات پیش‌فرض','parent')}),
    'conditional_pricing': dict(name='قیمت‌گذاری شرطی و چندبعدی', category='sales', description='قیمت بر اساس کالا، ارز، نوع فروش، گروه مشتری، ردیابی، مقدار و تاریخ؛ ارزیابی قابل توضیح بدون تغییر خودکار فاکتور.', kinds={
        'price_book':entity('اعلامیه قیمت'),
        'price_rule':entity('قاعده قیمت',{'unit_ref':field('شناسه واحد مبدأ','integer',min=1),'sale_type_ref':field('نوع فروش مبدأ','integer'),'customer_group_ref':field('گروه مشتری مبدأ','integer'),'tracing_ref':field('ردیابی مبدأ','integer'),'min_qty':field('حداقل مقدار','decimal',min='0'),'max_qty':field('حداکثر مقدار','decimal',min='0'),'discount_percent':field('تخفیف (%)','decimal',min='0',max='100'),'addition_percent':field('افزوده (%)','decimal',min='0',max='100'),'priority':field('اولویت','integer',min=0,max=1000),'lower_margin':field('حاشیه پایین مبدأ (مرز مجاز ویرایش، نه مقدار خرید)','decimal'),'upper_margin':field('حاشیه بالا مبدأ','decimal')}),
        'sale_type':entity('نوع فروش'), 'customer_group':entity('گروه مشتری'),
        'discount_window':entity('بازه تخفیف مبدأ',local=False), 'source_event':entity('شرایط تکمیلی مبدأ',local=False),
    }, options={'reject_ambiguous':field('رد قواعد هم‌اولویت مبهم','boolean',default=True),
        'source_adjustment_order':field('ترتیب تخفیف/افزوده مبدأ پس از بررسی قرارداد','choice',choices=['require_review','discount_then_addition','parallel_on_base'],default='require_review')}),
    'inventory_trace_cost': dict(name='ردیابی بچ و بهای لایه‌ای انبار', category='product_management', description='بچ/ردیابی، ارتباط رسید و حواله بومی، لایه هزینه و گزارش FIFO؛ بدون دوباره‌شماری موجودی یا ساخت بهای نامعلوم.', kinds={
        'trace_category':entity('گروه ردیابی'), 'trace':entity('بچ / ردیابی',{'expires_on':field('تاریخ انقضا','date')}),
        'receipt_layer':entity('لایه رسید',{'warehouse_document_line_id':field('شناسه ردیف رسید بومی','integer',True,min=1),'warehouse_id':field('انبار','warehouse'),'trace_id':field('بچ / ردیابی','parent'),'unit_cost':field('بهای واحد؛ خالی یعنی نامعلوم','decimal',min='0'),'fiscal_year_id':field('شناسه سال مالی','integer',min=1)}),
        'issue':entity('تخصیص حواله',{'warehouse_document_line_id':field('شناسه ردیف حواله بومی','integer',True,min=1),'warehouse_id':field('انبار','warehouse'),'trace_id':field('بچ / ردیابی','parent'),'fiscal_year_id':field('شناسه سال مالی','integer',min=1)}),
        'pricing_period':entity('دوره قیمت‌گذاری انبار',local=False), 'pricing_voucher':entity('سند قیمت‌گذاری مبدأ',local=False),
        'source_event':entity('جزئیات قیمت‌گذاری مبدأ',local=False),
    }, options={'cost_method':field('روش گزارش لایه‌ای','choice',choices=['fifo'],default='fifo')}),
}


# table -> (native kind, source primary key, normalized field -> source field)
# Raw fields remain in source_payload for inspection and exact lossless history.
SOURCE = {
 'fixed_assets': {
  'AST.DepreciationRule':('rule','DepreciationRuleID',{'title':'Description','code':'GroupNo','annual_rate':'DepreciationRate','useful_life_years':'UsefulLife','method':'DepreciationMethod'}),
  'AST.AssetClass':('asset_class','AssetClassID',{'title':'Title','code':'Code'}),
  'AST.AssetGroup':('asset_group','AssetGroupID',{'title':'Title','code':'Code','annual_rate':'DepreciationRate','useful_life_years':'UsefulLife','method':'DepreciationMethod'}),
  'AST.Emplacement':('location','EmplacementId',{'title':'Title','code':'Code'}),
  'AST.Asset':('asset','AssetId',{'title':'Title','code':'PlaqueNumber','person_id':'ReceiverPartyRef','status':'State'}),
  'AST.CostPart':('cost_part','CostPartID',{'amount':'TotalCost','cost':'TotalCost','start_date':'EffectiveDate','accumulated':'AccumulatedDepreciation','salvage':'SalvageValue','annual_rate':'DepreciationRate','useful_life_years':'UsefulLife','method':'DepreciationMethodType','max_depreciable_book_value':'MaxDepreciableBookValue'}),
  'AST.AcquisitionReceipt':('acquisition','AcquisitionReceiptID',{'title':'Description','code':'Number','start_date':'Date','currency_id':'CurrencyRef'}),
  'AST.AcquisitionReceiptItem':('acquisition_line','AcquisitionReceiptItemID',{'title':'Title','code':'PlaqueNumber','amount':'TotalCostInBasecurrency','start_date':'UtilizationDate','cost':'TotalCostInBasecurrency','salvage':'SalvageValue','accumulated':'AccumulatedDepreciation','annual_rate':'DepreciationRate','useful_life_years':'UsefulLife','method':'DepreciationMethodType'}),
  'AST.AssetTransaction':('asset_event','AssetTransactionID',{'start_date':'ActivityDate','code':'ActivityNumber','status':'AssetState'}),
  'AST.Depreciation':('depreciation','DepreciationID',{'start_date':'Date'}),
  'AST.DepreciationItem':('depreciation_line','DepreciationItemID',{'start_date':'CalculationDate','amount':'DepreciationValue','accumulated':'AccumulatedDepreciation'}),
  'AST.CostPartTransaction':('source_event','CostPartTransactionID',{}),
 },
 'contracting': {
  'CNT.Project':('project','ProjectID',{'title':'Title','code':'Code'}),
  'CNT.Contract':('contract','ContractID',{'title':'Title','code':'DocumentNumber','start_date':'StartDate','end_date':'EndDate','amount':'Cost','person_id':'ContractorPartyRef'}),
  'CNT.Status':('statement','StatusID',{'code':'Number','start_date':'Date','amount':'ConfirmedCost','status':'ConfirmationState'}),
  'CNT.StatusItem':('statement_line','StatusItemID',{'title':'ItemTitle','quantity':'ConfirmedQuantity','amount':'ConfirmedPrice','unit_price':'ConfirmedFee','product_id':'ItemRef'}),
  'CNT.Guarantee':('guarantee','GuaranteeID',{'title':'Description','code':'Number','start_date':'Date','end_date':'DueDate','amount':'Price','status':'State'}),
  'CNT.Coefficient':('coefficient','CoefficientID',{'title':'Title','code':'Code','rate':'Percent'}),
  'CNT.Cost':('cost_type','CostID',{'title':'Title'}),
  'CNT.Warranty':('warranty_type','WarrantyID',{'title':'Title'}),
  'CNT.ContractType':('contract_type','ContractTypeID',{'title':'Title'}),
 },
 'payroll_calendar_tax': {
  'PAY.PayrollCalendar':('calendar','PayrollCalendarId',{'solar_year':'Year','month':'Month','days':'Day','daily_minutes':'HourMinute'}),
  'PAY.DailyHourMinute':('daily_hours','DailyHourMinuteId',{'solar_year':'Year','daily_minutes':'DailyHourMinute'}),
  'PAY.Leave':('leave','LeaveId',{'start_date':'Date','solar_year':'Solaryear','month':'Month','minutes':'SystemRemainder'}),
  'PAY.TaxGroup':('tax_group','TaxGroupId',{'title':'Title'}),
  'PAY.TaxTable':('tax_table','TaxTableId',{'title':'Title','start_date':'Date','tax_scope':'TaxType'}),
  'PAY.TaxTableItem':('tax_bracket','TaxTableItemId',{'from_amount':'FromAmount','to_amount':'ToAmount','rate':'Rate'}),
  'PAY.Personnel':('personnel','PersonnelId',{'person_id':'PartyRef'}),
 },
 'conditional_pricing': {
  'SLS.PriceNote':('price_book','PriceNoteID',{'title':'Title','start_date':'Date'}),
  'SLS.PriceNoteItem':('price_rule','PriceNoteItemID',{'amount':'Fee','product_id':'ItemRef','currency_id':'CurrencyRef','unit_ref':'UnitRef','sale_type_ref':'SaleTypeRef','customer_group_ref':'CustomerGroupingRef','tracing_ref':'TracingRef','discount_percent':'Discount','addition_percent':'AdditionRate','lower_margin':'LowerMargin','upper_margin':'UpperMargin'}),
  'SLS.SaleType':('sale_type','SaleTypeId',{'title':'Title'}),
  'SLS.CustomerGrouping':('customer_group','CustomerGroupingID',{'title':'Title'}),
  'SLS.PriceNoteItemDiscount':('discount_window','PriceNoteItemDiscountID',{'start_date':'StartDate','end_date':'EndDate'}),
 },
 'inventory_trace_cost': {
  'INV.TracingCategory':('trace_category','TracingCategoryID',{'title':'Title'}),
  'INV.Tracing':('trace','TracingID',{'title':'Title'}),
  'INV.InventoryReceiptItem':('receipt_layer','InventoryReceiptItemID',{'product_id':'ItemRef','quantity':'Quantity','amount':'Price'}),
  'INV.InventoryDeliveryItem':('issue','InventoryDeliveryItemID',{'product_id':'ItemRef','quantity':'Quantity','amount':'Price'}),
  'INV.InventoryPricing':('pricing_period','InventoryPricingID',{'start_date':'StartDate','end_date':'EndDate'}),
  'INV.InventoryPricingVoucher':('pricing_voucher','InventoryPricingVoucherID',{}),
  'INV.InventoryPricingVoucherItem':('source_event','InventoryPricingVoucherItemID',{}),
 },
}


# Native parent links are separate from original source foreign keys.
PARENTS = {
 'AST.AssetGroup':('AssetClassRef','AST.AssetClass'),
 'AST.Asset':('AssetGroupRef','AST.AssetGroup'),
 'AST.CostPart':('AssetRef','AST.Asset'),
 'AST.AcquisitionReceiptItem':('AssetRef','AST.Asset'),
 'AST.AssetTransaction':('AssetRef','AST.Asset'),
 'AST.Depreciation':('AssetRef','AST.Asset'),
 'AST.DepreciationItem':('DepreciationRef','AST.Depreciation'),
 'AST.CostPartTransaction':('CostPartRef','AST.CostPart'),
 'CNT.Contract':('ProjectRef','CNT.Project'),
 'CNT.Status':('ContractRef','CNT.Contract'),
 'CNT.StatusItem':('StatusRef','CNT.Status'),
 'CNT.Guarantee':('ContractRef','CNT.Contract'),
 'PAY.TaxTable':('TaxGroupRef','PAY.TaxGroup'),
 'PAY.TaxTableItem':('TaxTableRef','PAY.TaxTable'),
 'PAY.Leave':('PersonnelRef','PAY.Personnel'),
 'SLS.PriceNoteItem':('PriceNoteRef','SLS.PriceNote'),
 'SLS.PriceNoteItemDiscount':('PriceNoteItemRef','SLS.PriceNoteItem'),
 'INV.Tracing':('TracingCategoryRef','INV.TracingCategory'),
}

ADVANCED_TABLES = {t for module in SOURCE.values() for t in module} | {'INV.InventoryReceipt','INV.InventoryDelivery','GNR.Currency'}

# Explicit local delta events; importing a rule/calendar/FIFO report is not a
# financial event and never creates these records or journals automatically.
for _code,_kind,_label,_fields in [
 ('payroll_calendar_tax','tax_adjustment','تعدیل مستقل مالیات (نه صدور مجدد حقوق)',{'reference':field('شناسه یکتای مبنای تعدیل','text',True)}),
 ('conditional_pricing','price_adjustment','تعدیل مستقل قیمت فاکتور فروش بومی',{'invoice_document_id':field('شناسه سند فاکتور فروش بومی','integer',True,min=1),'tax_amount':field('مالیات تعدیل تأییدشده؛ خالی یعنی صفر','decimal',min='0')}),
 ('inventory_trace_cost','cost_adjustment','تعدیل مستقل بهای خروج بومی',{'warehouse_document_line_id':field('شناسه ردیف خروج بومی','integer',True,min=1)}),
]:
    MODULES[_code]['kinds'][_kind]=entity(_label,{
        **_fields,'direction':field('جهت تعدیل','choice',True,choices=['increase','decrease']),
        'reason':field('شرح و مستند مبنای تعدیل','text',True),
        'amount':field('مبلغ خالص تعدیل (نه مبلغ کل عملیات)','decimal',True,min='0.01'),
        'start_date':field('تاریخ ثبت تعدیل','date',True),
    })


def default_options(code):
    return {key:value['default'] for key,value in MODULES[code]['options'].items() if 'default' in value}


def public_catalog():
    return [{'code':code,**spec,'defaults':default_options(code)} for code,spec in MODULES.items()]
