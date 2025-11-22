# سناریو کامل رفع مشکل شماره 1: ثبت حسابداری مصرف مستقیم، ضایعات و تولید

## خلاصه مشکل

فاکتورهای **مصرف مستقیم**، **ضایعات** و **تولید** هیچ ثبت حسابداری در فاکتور ایجاد نمی‌کنند. ثبت‌های حسابداری فقط در پست حواله انبار انجام می‌شود که می‌تواند منجر به عدم ثبت هزینه/درآمد شود.

---

## اطلاعات حساب‌ها از میگریشن

از فایل `20251011_010001_replace_accounts_chart_seed.py`:

### حساب‌های مربوطه:

1. **70406** - "هزینه ملزومات مصرفی" (Direct Consumption Expense)
   - نوع: هزینه عملیاتی
   - استفاده: برای مصرف مستقیم

2. **70407** - "هزینه کسری و ضایعات کالا" (Waste Expense)
   - نوع: هزینه عملیاتی
   - استفاده: برای ضایعات

3. **10106** - "موجودی کالای در جریان ساخت" (Work In Progress - WIP)
   - نوع: دارایی جاری
   - استفاده: برای تولید (مواد اولیه → WIP → محصول نهایی)

4. **10102** - "موجودی کالا" (Inventory)
   - نوع: دارایی جاری
   - استفاده: برای موجودی کالا

5. **40001** - "بهای تمام شده کالای فروخته شده" (COGS)
   - نوع: بهای تمام شده
   - استفاده: برای COGS

---

## سناریو 1: فاکتور مصرف مستقیم (Direct Consumption)

### توضیح:
مصرف مستقیم یعنی استفاده از کالا برای اهداف داخلی (مثلاً مصرف ملزومات اداری، مواد اولیه برای تعمیرات، و غیره).

### منطق حسابداری:

**وقتی کالا از انبار خارج می‌شود:**
```
Dr. هزینه ملزومات مصرفی (70406) - مبلغ بهای تمام‌شده
Cr. موجودی کالا (10102) - مبلغ بهای تمام‌شده
```

### پیاده‌سازی:

**در تابع `create_invoice` برای `INVOICE_DIRECT_CONSUMPTION`:**

```python
elif invoice_type == INVOICE_DIRECT_CONSUMPTION:
    # محاسبه COGS برای خطوط
    # توجه: COGS باید از حواله انبار محاسبه شود (FIFO/Average)
    # اما برای ثبت اولیه در فاکتور، می‌توان از cost_price استفاده کرد
    
    # محاسبه مجموع COGS از خطوط
    total_cogs = Decimal(0)
    for line in lines_input:
        extra_info = line.get("extra_info") or {}
        qty = Decimal(str(line.get("quantity", 0) or 0))
        
        # اولویت: cogs_amount > cost_price > unit_price
        if extra_info.get("cogs_amount") is not None:
            cogs_line = Decimal(str(extra_info.get("cogs_amount")))
        elif extra_info.get("cost_price") is not None:
            cogs_line = qty * Decimal(str(extra_info.get("cost_price")))
        else:
            # fallback: استفاده از unit_price (اگر موجود باشد)
            unit_price = extra_info.get("unit_price")
            if unit_price:
                cogs_line = qty * Decimal(str(unit_price))
            else:
                cogs_line = Decimal(0)
        
        total_cogs += cogs_line
    
    # ثبت حسابداری
    if total_cogs > 0:
        # بدهکار: هزینه مصرف مستقیم
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["direct_consumption"].id,  # 70406
            debit=total_cogs,
            credit=Decimal(0),
            description="هزینه مصرف مستقیم کالا",
        ))
        
        # بستانکار: موجودی کالا
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["inventory"].id,  # 10102
            debit=Decimal(0),
            credit=total_cogs,
            description="خروج کالا از موجودی (مصرف مستقیم)",
        ))
```

### مثال عددی:

**فاکتور مصرف مستقیم:**
- کالا: کاغذ A4 - 100 برگ
- موجودی: 1000 برگ با بهای تمام‌شده 500,000 ریال
- مصرف: 100 برگ
- COGS: 50,000 ریال (100 * 500)

**ثبت حسابداری:**
```
Dr. هزینه ملزومات مصرفی (70406)    50,000
Cr. موجودی کالا (10102)             50,000
```

---

## سناریو 2: فاکتور ضایعات (Waste)

### توضیح:
ضایعات یعنی کالاهایی که به دلایل مختلف (خرابی، تاریخ مصرف گذشته، و غیره) از بین رفته‌اند.

### منطق حسابداری:

**وقتی کالا به عنوان ضایعات از انبار خارج می‌شود:**
```
Dr. هزینه کسری و ضایعات کالا (70407) - مبلغ بهای تمام‌شده
Cr. موجودی کالا (10102) - مبلغ بهای تمام‌شده
```

### پیاده‌سازی:

**در تابع `create_invoice` برای `INVOICE_WASTE`:**

```python
elif invoice_type == INVOICE_WASTE:
    # محاسبه COGS برای خطوط (مشابه مصرف مستقیم)
    total_cogs = Decimal(0)
    for line in lines_input:
        extra_info = line.get("extra_info") or {}
        qty = Decimal(str(line.get("quantity", 0) or 0))
        
        if extra_info.get("cogs_amount") is not None:
            cogs_line = Decimal(str(extra_info.get("cogs_amount")))
        elif extra_info.get("cost_price") is not None:
            cogs_line = qty * Decimal(str(extra_info.get("cost_price")))
        else:
            unit_price = extra_info.get("unit_price")
            if unit_price:
                cogs_line = qty * Decimal(str(unit_price))
            else:
                cogs_line = Decimal(0)
        
        total_cogs += cogs_line
    
    # ثبت حسابداری
    if total_cogs > 0:
        # بدهکار: هزینه ضایعات
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["waste_expense"].id,  # 70407
            debit=total_cogs,
            credit=Decimal(0),
            description="هزینه کسری و ضایعات کالا",
        ))
        
        # بستانکار: موجودی کالا
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["inventory"].id,  # 10102
            debit=Decimal(0),
            credit=total_cogs,
            description="خروج کالا از موجودی (ضایعات)",
        ))
```

### مثال عددی:

**فاکتور ضایعات:**
- کالا: محصول منقضی شده - 50 عدد
- موجودی: 500 عدد با بهای تمام‌شده 1,000,000 ریال
- ضایعات: 50 عدد
- COGS: 100,000 ریال (50 * 2,000)

**ثبت حسابداری:**
```
Dr. هزینه کسری و ضایعات کالا (70407)    100,000
Cr. موجودی کالا (10102)                 100,000
```

---

## سناریو 3: فاکتور تولید (Production)

### توضیح:
تولید یعنی تبدیل مواد اولیه به محصول نهایی. این فرآیند شامل دو مرحله است:
1. **خروج مواد اولیه** از موجودی
2. **ورود محصول نهایی** به موجودی

### منطق حسابداری:

**مرحله 1: خروج مواد اولیه (movement: "out")**
```
Dr. موجودی کالای در جریان ساخت (10106) - مبلغ بهای تمام‌شده مواد اولیه
Cr. موجودی کالا (10102) - مبلغ بهای تمام‌شده مواد اولیه
```

**مرحله 2: ورود محصول نهایی (movement: "in")**
```
Dr. موجودی کالا (10102) - مبلغ بهای تمام‌شده محصول نهایی
Cr. موجودی کالای در جریان ساخت (10106) - مبلغ بهای تمام‌شده محصول نهایی
```

**نکته:** مبلغ محصول نهایی معمولاً برابر با مجموع هزینه مواد اولیه + هزینه‌های تولید (دستمزد، سربار) است.

### پیاده‌سازی:

**در تابع `create_invoice` برای `INVOICE_PRODUCTION`:**

```python
elif invoice_type == INVOICE_PRODUCTION:
    # جداسازی خطوط ورودی و خروجی
    out_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "out"]
    in_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "in"]
    
    # محاسبه COGS برای مواد اولیه (خروج)
    total_materials_cost = Decimal(0)
    for line in out_lines:
        extra_info = line.get("extra_info") or {}
        qty = Decimal(str(line.get("quantity", 0) or 0))
        
        if extra_info.get("cogs_amount") is not None:
            cogs_line = Decimal(str(extra_info.get("cogs_amount")))
        elif extra_info.get("cost_price") is not None:
            cogs_line = qty * Decimal(str(extra_info.get("cost_price")))
        else:
            unit_price = extra_info.get("unit_price")
            if unit_price:
                cogs_line = qty * Decimal(str(unit_price))
            else:
                cogs_line = Decimal(0)
        
        total_materials_cost += cogs_line
    
    # محاسبه هزینه محصول نهایی (ورود)
    total_finished_cost = Decimal(0)
    for line in in_lines:
        extra_info = line.get("extra_info") or {}
        qty = Decimal(str(line.get("quantity", 0) or 0))
        
        # برای محصول نهایی، cost_price باید شامل مواد اولیه + هزینه‌های تولید باشد
        if extra_info.get("cost_price") is not None:
            cost_line = qty * Decimal(str(extra_info.get("cost_price")))
        elif extra_info.get("unit_price") is not None:
            # اگر cost_price موجود نباشد، از unit_price استفاده می‌کنیم
            cost_line = qty * Decimal(str(extra_info.get("unit_price")))
        else:
            # اگر هیچکدام موجود نباشد، از مجموع هزینه مواد اولیه استفاده می‌کنیم
            cost_line = total_materials_cost if len(in_lines) == 1 else Decimal(0)
        
        total_finished_cost += cost_line
    
    # ثبت حسابداری برای مواد اولیه (خروج)
    if total_materials_cost > 0:
        # بدهکار: WIP
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["wip"].id,  # 10106
            debit=total_materials_cost,
            credit=Decimal(0),
            description="انتقال مواد اولیه به WIP",
        ))
        
        # بستانکار: موجودی کالا
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["inventory"].id,  # 10102
            debit=Decimal(0),
            credit=total_materials_cost,
            description="خروج مواد اولیه از موجودی",
        ))
    
    # ثبت حسابداری برای محصول نهایی (ورود)
    if total_finished_cost > 0:
        # بدهکار: موجودی کالا
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["inventory"].id,  # 10102
            debit=total_finished_cost,
            credit=Decimal(0),
            description="ورود محصول نهایی به موجودی",
        ))
        
        # بستانکار: WIP
        db.add(DocumentLine(
            document_id=document.id,
            account_id=accounts["wip"].id,  # 10106
            debit=Decimal(0),
            credit=total_finished_cost,
            description="انتقال محصول نهایی از WIP",
        ))
```

### مثال عددی:

**فاکتور تولید:**
- **مواد اولیه (خروج):**
  - آرد: 100 کیلوگرم با بهای تمام‌شده 500,000 ریال
  - شکر: 20 کیلوگرم با بهای تمام‌شده 100,000 ریال
  - مجموع: 600,000 ریال

- **محصول نهایی (ورود):**
  - نان: 200 عدد با بهای تمام‌شده 3,500 ریال (شامل مواد اولیه + دستمزد + سربار)
  - مجموع: 700,000 ریال

**ثبت حسابداری:**

**مرحله 1: خروج مواد اولیه**
```
Dr. موجودی کالای در جریان ساخت (10106)    600,000
Cr. موجودی کالا (10102)                   600,000
```

**مرحله 2: ورود محصول نهایی**
```
Dr. موجودی کالا (10102)                    700,000
Cr. موجودی کالای در جریان ساخت (10106)    700,000
```

**نتیجه:**
- WIP: 600,000 بدهکار - 700,000 بستانکار = 100,000 بستانکار (زیان تولید)
- موجودی: 600,000 بستانکار - 700,000 بدهکار = 100,000 بدهکار (افزایش موجودی)

**نکته:** اگر هزینه تولید بیشتر از مواد اولیه باشد، این تفاوت باید از حساب‌های هزینه تولید (دستمزد، سربار) تأمین شود. اما در فاکتور تولید فعلی، این هزینه‌ها در فاکتور ثبت نمی‌شوند و باید در اسناد جداگانه ثبت شوند.

---

## نکات مهم پیاده‌سازی

### 1. محاسبه COGS

**اولویت محاسبه COGS:**
1. `cogs_amount` از `extra_info` (اگر از حواله انبار محاسبه شده باشد)
2. `cost_price` از `extra_info` (قیمت تمام‌شده)
3. `unit_price` از `extra_info` (قیمت واحد - fallback)

**نکته:** برای دقت بیشتر، COGS باید از حواله انبار محاسبه شود (FIFO/Average). اما برای ثبت اولیه در فاکتور، می‌توان از `cost_price` استفاده کرد.

### 2. بررسی موجودی

**قبل از ثبت حسابداری:**
- باید بررسی شود که موجودی کافی وجود دارد
- این بررسی در پست حواله انبار انجام می‌شود
- اما در فاکتور، می‌توان هشدار داد

### 3. هماهنگی با حواله انبار

**رویکرد پیشنهادی:**
- ثبت حسابداری در فاکتور انجام می‌شود (برای اطمینان از ثبت)
- در پست حواله انبار، COGS دقیق محاسبه می‌شود (FIFO/Average)
- اگر COGS در حواله متفاوت باشد، باید تعدیل انجام شود

**یا:**
- ثبت حسابداری فقط در پست حواله انبار انجام می‌شود
- اما باید اطمینان حاصل شود که حواله حتماً پست می‌شود

### 4. پروفرما

**برای فاکتورهای پروفرما:**
- ثبت حسابداری انجام نمی‌شود (مشابه سایر فاکتورها)
- فقط در فاکتورهای قطعی ثبت می‌شود

---

## کد کامل برای اضافه کردن

**در تابع `create_invoice`، بخش ثبت حسابداری (خط 1266-1269):**

```python
# Direct consumption / Waste / Production
elif invoice_type in (INVOICE_DIRECT_CONSUMPTION, INVOICE_WASTE, INVOICE_PRODUCTION):
    # برای این انواع، ثبت‌های موجودی و بهای تمام‌شده در فاکتور انجام می‌شود
    # (نه فقط در پست حواله)
    
    if invoice_type == INVOICE_DIRECT_CONSUMPTION:
        # محاسبه COGS
        total_cogs = _extract_cogs_total(lines_input)
        
        if total_cogs > 0:
            # بدهکار: هزینه مصرف مستقیم
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["direct_consumption"].id,
                debit=total_cogs,
                credit=Decimal(0),
                description="هزینه مصرف مستقیم کالا",
            ))
            
            # بستانکار: موجودی کالا
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["inventory"].id,
                debit=Decimal(0),
                credit=total_cogs,
                description="خروج کالا از موجودی (مصرف مستقیم)",
            ))
    
    elif invoice_type == INVOICE_WASTE:
        # محاسبه COGS
        total_cogs = _extract_cogs_total(lines_input)
        
        if total_cogs > 0:
            # بدهکار: هزینه ضایعات
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["waste_expense"].id,
                debit=total_cogs,
                credit=Decimal(0),
                description="هزینه کسری و ضایعات کالا",
            ))
            
            # بستانکار: موجودی کالا
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["inventory"].id,
                debit=Decimal(0),
                credit=total_cogs,
                description="خروج کالا از موجودی (ضایعات)",
            ))
    
    elif invoice_type == INVOICE_PRODUCTION:
        # جداسازی خطوط ورودی و خروجی
        out_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "out"]
        in_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "in"]
        
        # محاسبه COGS برای مواد اولیه (خروج)
        total_materials_cost = _extract_cogs_total(out_lines)
        
        # محاسبه هزینه محصول نهایی (ورود)
        # برای محصول نهایی، از cost_price استفاده می‌کنیم
        total_finished_cost = Decimal(0)
        for line in in_lines:
            extra_info = line.get("extra_info") or {}
            qty = Decimal(str(line.get("quantity", 0) or 0))
            
            if extra_info.get("cost_price") is not None:
                cost_line = qty * Decimal(str(extra_info.get("cost_price")))
            elif extra_info.get("unit_price") is not None:
                cost_line = qty * Decimal(str(extra_info.get("unit_price")))
            else:
                # fallback: استفاده از مجموع هزینه مواد اولیه
                cost_line = total_materials_cost if len(in_lines) == 1 else Decimal(0)
            
            total_finished_cost += cost_line
        
        # ثبت حسابداری برای مواد اولیه (خروج)
        if total_materials_cost > 0:
            # بدهکار: WIP
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["wip"].id,
                debit=total_materials_cost,
                credit=Decimal(0),
                description="انتقال مواد اولیه به WIP",
            ))
            
            # بستانکار: موجودی کالا
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["inventory"].id,
                debit=Decimal(0),
                credit=total_materials_cost,
                description="خروج مواد اولیه از موجودی",
            ))
        
        # ثبت حسابداری برای محصول نهایی (ورود)
        if total_finished_cost > 0:
            # بدهکار: موجودی کالا
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["inventory"].id,
                debit=total_finished_cost,
                credit=Decimal(0),
                description="ورود محصول نهایی به موجودی",
            ))
            
            # بستانکار: WIP
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["wip"].id,
                debit=Decimal(0),
                credit=total_finished_cost,
                description="انتقال محصول نهایی از WIP",
            ))
```

---

## خلاصه تغییرات

### فایل: `hesabixAPI/app/services/invoice_service.py`

**بخش:** تابع `create_invoice`، خط 1266-1269

**تغییر:**
- به جای `pass`، منطق ثبت حسابداری برای مصرف مستقیم، ضایعات و تولید اضافه می‌شود

**تابع کمکی:**
- استفاده از `_extract_cogs_total` که قبلاً وجود دارد
- این تابع COGS را از خطوط محاسبه می‌کند

---

## تست سناریوها

### تست 1: مصرف مستقیم
1. ایجاد فاکتور مصرف مستقیم با یک کالا
2. بررسی ثبت حسابداری:
   - بدهکار: 70406
   - بستانکار: 10102
3. بررسی تعادل: بدهکار = بستانکار

### تست 2: ضایعات
1. ایجاد فاکتور ضایعات با یک کالا
2. بررسی ثبت حسابداری:
   - بدهکار: 70407
   - بستانکار: 10102
3. بررسی تعادل: بدهکار = بستانکار

### تست 3: تولید
1. ایجاد فاکتور تولید با مواد اولیه (out) و محصول نهایی (in)
2. بررسی ثبت حسابداری:
   - خروج مواد: Dr. 10106, Cr. 10102
   - ورود محصول: Dr. 10102, Cr. 10106
3. بررسی تعادل: مجموع بدهکار = مجموع بستانکار

---

**تاریخ:** 2025-01-XX
**تهیه کننده:** AI Assistant

