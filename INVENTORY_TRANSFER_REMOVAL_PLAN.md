# برنامه حذف Inventory Transfers و جایگزینی با Warehouse Documents

## ⚠️ نکته مهم: تفکیک حسابداری و انبارداری

**موجودی حسابداری ≠ موجودی انبارداری**

- **کاردکس و محاسبات حسابداری**: باید از اسناد حسابداری (`documents` و `document_lines`) استفاده شود
- **موجودی فیزیکی انبار**: از `warehouse_documents` استفاده می‌شود
- این دو ممکن است متفاوت باشند (مثلاً کالاهای گم‌شده، ضایعات، خطاهای شمارش)

## وضعیت فعلی

### Inventory Transfers (سیستم قدیمی - باید حذف شود)
- **جدول**: `documents` با `document_type = 'inventory_transfer'`
- **خطوط**: `document_lines` با `extra_info.inventory_tracked: True`
- **استفاده در محاسبات موجودی حسابداری**: ✅ بله (از طریق `_iter_product_movements`)
- **استفاده در کاردکس**: ✅ بله (از طریق `kardex_service`)
- **نیاز به currency_id و fiscal_year_id**: ✅ بله
- **مشکل**: یک سیستم جداگانه برای انتقال موجودی که باید حذف شود

### Warehouse Documents (سیستم جدید)
- **جدول**: `warehouse_documents` و `warehouse_document_lines`
- **نوع انتقال**: `doc_type = 'transfer'`
- **استفاده در محاسبات موجودی حسابداری**: ❌ خیر (نباید مستقیماً استفاده شود)
- **استفاده در کاردکس**: ❌ خیر (نباید مستقیماً استفاده شود)
- **نیاز به currency_id و fiscal_year_id**: ❌ خیر
- **هدف**: مدیریت فیزیکی انبار (مستقل از حسابداری)

## راه‌حل پیشنهادی

**وقتی یک Warehouse Document با `doc_type='transfer'` پست می‌شود:**

1. **ایجاد سند حسابداری**: یک سند حسابداری (`Document`) با `document_type='inventory_transfer'` ایجاد شود
2. **ایجاد خطوط حسابداری**: خطوط `DocumentLine` با `extra_info.inventory_tracked: True` ایجاد شود
3. **لینک بین دو سیستم**: سند حسابداری به Warehouse Document لینک شود (از طریق `extra_info`)
4. **استفاده در کاردکس**: این سند حسابداری در کاردکس و محاسبات موجودی حسابداری استفاده شود
5. **مدیریت فیزیکی**: Warehouse Document فقط برای مدیریت فیزیکی انبار باقی بماند

**نتیجه:**
- کاردکس و محاسبات حسابداری از اسناد حسابداری استفاده می‌کنند ✅
- موجودی فیزیکی انبار از Warehouse Documents استفاده می‌کند ✅
- این دو می‌توانند متفاوت باشند ✅

## فایل‌های درگیر

### Backend

#### فایل‌های حذف شونده:
1. `hesabixAPI/app/services/inventory_transfer_service.py` - سرویس ایجاد انتقال
2. `hesabixAPI/adapters/api/v1/inventory_transfers.py` - API endpoints
3. `hesabixAPI/app/main.py` - حذف router

#### فایل‌های نیاز به تغییر:
1. `hesabixAPI/app/services/warehouse_service.py`
   - **تغییر در `post_warehouse_document`**: 
     - اگر `doc_type='transfer'` باشد، یک سند حسابداری ایجاد شود
     - خطوط `DocumentLine` با `inventory_tracked: True` ایجاد شود
     - لینک بین سند حسابداری و Warehouse Document برقرار شود

2. `hesabixAPI/app/services/kardex_service.py`
   - حذف `inventory_transfer` از mapping (اما همچنان از `document_type='inventory_transfer'` استفاده می‌شود)

3. `hesabixAPI/adapters/db/repositories/document_repository.py`
   - حذف `inventory_transfer` از mapping (اما همچنان از `document_type='inventory_transfer'` استفاده می‌شود)

### Frontend

#### فایل‌های حذف شونده:
1. `hesabixUI/hesabix_ui/lib/services/inventory_transfer_service.dart`
2. `hesabixUI/hesabix_ui/lib/widgets/transfer/inventory_transfer_form_dialog.dart`
3. `hesabixUI/hesabix_ui/lib/pages/business/inventory_transfers_page.dart`

#### فایل‌های نیاز به تغییر:
1. `hesabixUI/hesabix_ui/lib/main.dart` - حذف route `/business/:business_id/inventory-transfers`
2. `hesabixUI/hesabix_ui/lib/pages/business/business_shell.dart` - حذف منوی "حواله‌ها" (shipments)
3. `hesabixUI/hesabix_ui/lib/pages/business/kardex_page.dart` - حذف فیلتر `inventory_transfer` (اما همچنان از `document_type='inventory_transfer'` استفاده می‌شود)
4. `hesabixUI/hesabix_ui/lib/l10n/app_fa.arb` و `app_en.arb` - حذف رشته‌های مربوط به `shipments` و `inventory_transfer`

## تغییرات اصلی

### 1. تغییر `post_warehouse_document` برای ایجاد سند حسابداری

**فایل**: `hesabixAPI/app/services/warehouse_service.py`

**تغییر در `post_warehouse_document`**:
```python
def post_warehouse_document(db: Session, wh_id: int) -> Dict[str, Any]:
    """پست حواله: کنترل کسری برای خروج‌ها و به‌روزرسانی موجودی انبار.
    اگر doc_type='transfer' باشد، یک سند حسابداری هم ایجاد می‌شود.
    """
    from app.services.invoice_service import _ensure_stock_sufficient, _get_current_fiscal_year
    from adapters.db.models.document import Document
    from adapters.db.models.document_line import DocumentLine
    from adapters.db.models.currency import Currency
    from app.services.document_monetization_service import ensure_document_policy_allows_creation
    
    wh = db.query(WarehouseDocument).filter(WarehouseDocument.id == wh_id).first()
    if not wh:
        raise ApiError("NOT_FOUND", "Warehouse document not found", http_status=404)
    if wh.status == "posted":
        return {"id": wh.id, "status": wh.status}
    
    lines = db.query(WarehouseDocumentLine).filter(WarehouseDocumentLine.warehouse_document_id == wh.id).all()
    if not lines:
        raise ApiError("NO_LINES", "حواله باید حداقل یک خط داشته باشد", http_status=400)
    
    # کنترل کسری برای خروج‌ها (کد موجود)
    # ...
    
    # تغییر وضعیت به posted
    wh.status = "posted"
    wh.touch()
    db.flush()
    
    # اگر doc_type='transfer' باشد، یک سند حسابداری ایجاد کن
    if wh.doc_type == "transfer":
        # دریافت currency_id (از business یا default)
        currency = db.query(Currency).filter(Currency.business_id == wh.business_id).first()
        if not currency:
            # استفاده از currency پیش‌فرض
            currency = db.query(Currency).filter(Currency.code == "IRR").first()
        if not currency:
            raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)
        
        fiscal_year = _get_current_fiscal_year(db, wh.business_id)
        
        # ساخت کد سند
        from datetime import datetime
        today = datetime.now().date()
        prefix = f"ITR-{today.strftime('%Y%m%d')}"
        last_doc = db.query(Document).filter(
            and_(
                Document.business_id == wh.business_id,
                Document.code.like(f"{prefix}-%"),
            )
        ).order_by(Document.code.desc()).first()
        if last_doc:
            try:
                last_num = int(last_doc.code.split("-")[-1])
                next_num = last_num + 1
            except Exception:
                next_num = 1
        else:
            next_num = 1
        doc_code = f"{prefix}-{next_num:04d}"
        
        # بررسی policy
        ensure_document_policy_allows_creation(
            db,
            wh.business_id,
            document_type="inventory_transfer",
            document_date=wh.document_date,
            amount=Decimal(0),
        )
        
        # ایجاد سند حسابداری
        accounting_doc = Document(
            business_id=wh.business_id,
            fiscal_year_id=fiscal_year.id,
            code=doc_code,
            document_type="inventory_transfer",
            document_date=wh.document_date,
            currency_id=currency.id,
            created_by_user_id=wh.created_by_user_id,
            registered_at=datetime.utcnow(),
            is_proforma=False,
            description=wh.extra_info.get("description") if wh.extra_info else None,
            extra_info={
                "source": "warehouse_document",
                "warehouse_document_id": wh.id,
            },
        )
        db.add(accounting_doc)
        db.flush()
        
        # ایجاد خطوط حسابداری از خطوط حواله
        # برای transfer: یک خط out از مبدا و یک خط in به مقصد
        for wline in lines:
            if wline.movement == "out":
                # خط خروج از انبار مبدا
                db.add(DocumentLine(
                    document_id=accounting_doc.id,
                    product_id=wline.product_id,
                    quantity=wline.quantity,
                    debit=Decimal(0),
                    credit=Decimal(0),
                    description=None,
                    extra_info={
                        "movement": "out",
                        "warehouse_id": wline.warehouse_id,
                        "inventory_tracked": True,
                    },
                ))
            elif wline.movement == "in":
                # خط ورود به انبار مقصد
                db.add(DocumentLine(
                    document_id=accounting_doc.id,
                    product_id=wline.product_id,
                    quantity=wline.quantity,
                    debit=Decimal(0),
                    credit=Decimal(0),
                    description=None,
                    extra_info={
                        "movement": "in",
                        "warehouse_id": wline.warehouse_id,
                        "inventory_tracked": True,
                    },
                ))
        
        # لینک سند حسابداری به Warehouse Document
        if not wh.extra_info:
            wh.extra_info = {}
        wh.extra_info["accounting_document_id"] = accounting_doc.id
        db.flush()
    
    db.commit()
    return {"id": wh.id, "status": wh.status}
```

### 2. حذف فایل‌ها و ارجاعات

**مراحل**:
1. حذف فایل‌های Backend
2. حذف router از `main.py`
3. حذف فایل‌های Frontend
4. حذف route از `main.dart`
5. حذف منو از `business_shell.dart`
6. حذف رشته‌های ترجمه
7. حذف از `kardex_page.dart` (اما همچنان از `document_type='inventory_transfer'` استفاده می‌شود)
8. حذف از `document_repository.py` (اما همچنان از `document_type='inventory_transfer'` استفاده می‌شود)

## نکات مهم

1. **Migration داده‌ها**: اگر داده‌های موجودی از Inventory Transfers وجود دارد، باید migration script نوشته شود که:
   - Inventory Transfers موجود را به Warehouse Documents تبدیل کند
   - سند حسابداری مرتبط را حفظ کند

2. **Backward Compatibility**: بررسی کنید که آیا API‌های خارجی از Inventory Transfers استفاده می‌کنند

3. **Testing**: بعد از تغییرات، تست‌های کامل برای:
   - ایجاد Warehouse Document با doc_type='transfer'
   - پست کردن و ایجاد سند حسابداری
   - نمایش در کاردکس
   - محاسبات موجودی حسابداری

## خلاصه تغییرات

### Backend
- ✅ تغییر `post_warehouse_document` برای ایجاد سند حسابداری در صورت `doc_type='transfer'`
- ❌ حذف `inventory_transfer_service.py`
- ❌ حذف `inventory_transfers.py` (API)
- ❌ حذف router از `main.py`
- ⚠️ حذف `inventory_transfer` از mapping‌ها (اما همچنان از `document_type='inventory_transfer'` استفاده می‌شود)

### Frontend
- ❌ حذف `inventory_transfer_service.dart`
- ❌ حذف `inventory_transfer_form_dialog.dart`
- ❌ حذف `inventory_transfers_page.dart`
- ❌ حذف route از `main.dart`
- ❌ حذف منو از `business_shell.dart`
- ⚠️ حذف فیلتر از `kardex_page.dart` (اما همچنان از `document_type='inventory_transfer'` استفاده می‌شود)
- ❌ حذف رشته‌های ترجمه
