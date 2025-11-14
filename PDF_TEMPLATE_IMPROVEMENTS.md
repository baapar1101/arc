# تحلیل و پیشنهادات بهبود سیستم قالب‌های PDF

## 📋 خلاصه وضعیت فعلی

سیستم فعلی شامل:
- **Backend**: سرویس `ReportTemplateService` برای مدیریت قالب‌های ذخیره‌شده در دیتابیس
- **Template Engine**: Jinja2 با پشتیبانی از Builder و HTML مستقیم
- **PDF Generator**: WeasyPrint
- **Frontend**: رابط کاربری Flutter برای مدیریت قالب‌ها

---

## 🔧 پیشنهادات بهبود فنی

### 1. مدیریت خطا و اعتبارسنجی

**مشکل فعلی:**
- خطاهای قالب به صورت silent نادیده گرفته می‌شوند
- اعتبارسنجی محدود برای قالب‌ها
- عدم وجود لاگ مناسب برای خطاهای رندر

**پیشنهادات:**
```python
# در report_template_service.py
@staticmethod
def render_with_template(
    template: ReportTemplate,
    context: Dict[str, Any],
) -> str:
    try:
        # ... کد فعلی
    except TemplateSyntaxError as e:
        logger.error(f"Template syntax error in {template.id}: {e}")
        raise ApiError("TEMPLATE_SYNTAX_ERROR", f"خطای دستور در قالب: {e}", http_status=400)
    except UndefinedError as e:
        logger.warning(f"Undefined variable in template {template.id}: {e}")
        # می‌توانیم مقدار پیش‌فرض برگردانیم یا خطا بدهیم
        raise ApiError("TEMPLATE_VARIABLE_ERROR", f"متغیر تعریف نشده: {e}", http_status=400)
    except Exception as e:
        logger.exception(f"Template rendering error: {e}")
        raise ApiError("TEMPLATE_RENDER_ERROR", "خطا در رندر قالب", http_status=500)
```

**اعتبارسنجی قالب:**
```python
@staticmethod
def validate_template(content_html: str, context: Dict[str, Any] = None) -> List[str]:
    """اعتبارسنجی قالب و برگرداندن لیست خطاها"""
    errors = []
    try:
        env = SandboxedEnvironment(loader=BaseLoader(), autoescape=True)
        template_obj = env.from_string(content_html)
        # تست رندر با context خالی یا نمونه
        test_context = context or {}
        template_obj.render(**test_context)
    except TemplateSyntaxError as e:
        errors.append(f"خطای دستور: {e.message} در خط {e.lineno}")
    except Exception as e:
        errors.append(f"خطای رندر: {str(e)}")
    return errors
```

---

### 2. بهبود مدیریت فونت‌ها

**مشکل فعلی:**
- استفاده از Tahoma به جای Vazirmatn (طبق README)
- عدم پشتیبانی از فونت‌های سفارشی
- FontConfiguration بدون تنظیمات خاص

**پیشنهادات:**
```python
# در documents.py
from weasyprint.text.fonts import FontConfiguration

def get_font_config() -> FontConfiguration:
    """پیکربندی فونت برای PDF فارسی"""
    font_config = FontConfiguration()
    # می‌توان فونت‌های سفارشی را اضافه کرد
    return font_config

# در base.html - بهبود CSS
@font-face {
  font-family: 'Vazirmatn';
  src: url('/static/fonts/Vazirmatn-Regular.woff2') format('woff2');
  font-weight: normal;
  font-style: normal;
}

body {
  font-family: 'Vazirmatn', 'Tahoma', 'Arial', sans-serif;
  font-size: 12px;
  line-height: 1.6; /* بهبود خوانایی */
}
```

---

### 3. سیستم کش برای قالب‌ها

**پیشنهاد:**
```python
from functools import lru_cache
from typing import Optional

class ReportTemplateService:
    _template_cache: Dict[int, Tuple[ReportTemplate, float]] = {}
    CACHE_TTL = 300  # 5 دقیقه
    
    @staticmethod
    def get_template_cached(
        db: Session, 
        template_id: int, 
        business_id: Optional[int] = None
    ) -> Optional[ReportTemplate]:
        """دریافت قالب با کش"""
        import time
        cache_key = template_id
        
        if cache_key in ReportTemplateService._template_cache:
            template, cached_time = ReportTemplateService._template_cache[cache_key]
            if time.time() - cached_time < ReportTemplateService.CACHE_TTL:
                return template
        
        template = ReportTemplateService.get_template(db, template_id, business_id)
        if template:
            ReportTemplateService._template_cache[cache_key] = (template, time.time())
        return template
    
    @staticmethod
    def invalidate_cache(template_id: int):
        """پاک کردن کش یک قالب"""
        ReportTemplateService._template_cache.pop(template_id, None)
```

---

### 4. بهبود فیلترهای Jinja2

**پیشنهادات فیلترهای جدید:**
```python
# در report_template_service.py - render_with_template

# فیلتر فرمت اعداد فارسی
def _persian_number(v):
    """تبدیل اعداد انگلیسی به فارسی"""
    persian_digits = '۰۱۲۳۴۵۶۷۸۹'
    english_digits = '0123456789'
    s = str(v)
    for en, fa in zip(english_digits, persian_digits):
        s = s.replace(en, fa)
    return s
env.filters["persian"] = _persian_number

# فیلتر فرمت شماره حساب
def _account_number(v, format_type="standard"):
    """فرمت شماره حساب: 1234-567-890"""
    s = str(v).replace("-", "").replace(" ", "")
    if format_type == "standard" and len(s) >= 9:
        return f"{s[:4]}-{s[4:7]}-{s[7:]}"
    return s
env.filters["account"] = _account_number

# فیلتر خلاصه متن
def _truncate(v, length=50, suffix="..."):
    """کوتاه کردن متن"""
    s = str(v)
    if len(s) <= length:
        return s
    return s[:length] + suffix
env.filters["truncate"] = _truncate

# فیلتر شرطی برای نمایش/مخفی کردن
def _show_if(condition, true_val, false_val=""):
    """نمایش شرطی"""
    return true_val if condition else false_val
env.filters["show_if"] = _show_if
```

---

### 5. پشتیبانی از تصاویر و Assets

**مشکل فعلی:**
- عدم پشتیبانی مناسب از تصاویر در قالب‌های document
- Assets فقط در builder پشتیبانی می‌شود

**پیشنهاد:**
```python
# در documents.py - get_document_pdf_endpoint
# اضافه کردن پشتیبانی از assets
business_logo = None
try:
    if hasattr(business, 'logo_url') and business.logo_url:
        business_logo = business.logo_url
except Exception:
    pass

template_context = {
    # ... موجود
    "assets": {
        "images": {
            "logo": business_logo or "",
            # می‌توان تصاویر دیگر را اضافه کرد
        }
    }
}
```

---

### 6. بهبود مدیریت تاریخ و تقویم

**پیشنهاد:**
```python
# در documents.py
from app.core.calendar import CalendarConverter, CalendarType

# تبدیل تاریخ سند به تقویم شمسی
document_date_jalali = None
if doc.get("document_date"):
    try:
        dt = datetime.datetime.fromisoformat(str(doc.get("document_date")))
        formatted = CalendarConverter.format_datetime(dt, "jalali")
        document_date_jalali = formatted['formatted']
    except Exception:
        pass

template_context = {
    # ... موجود
    "document_date_jalali": document_date_jalali,
    "document_date_miladi": doc.get("document_date"),
}
```

---

### 7. بهبود ساختار کد endpoint

**پیشنهاد:**
```python
# استخراج منطق به یک تابع جداگانه
async def _generate_document_pdf(
    db: Session,
    document_id: int,
    business_id: int,
    template_id: Optional[int] = None,
    locale: str = "fa",
    paper_size: Optional[str] = None,
    orientation: Optional[str] = None,
) -> bytes:
    """تولید PDF سند - منطق اصلی"""
    # ... تمام منطق تولید PDF
    return pdf_bytes

@router.get("/documents/{document_id}/pdf")
async def get_document_pdf_endpoint(...):
    """Endpoint wrapper"""
    # بررسی دسترسی
    doc = get_document(db, document_id)
    # ...
    
    # تولید PDF
    pdf_bytes = await _generate_document_pdf(
        db=db,
        document_id=document_id,
        business_id=business_id,
        template_id=template_id,
        locale=locale,
        paper_size=paper_size,
        orientation=orientation,
    )
    
    return Response(...)
```

---

## 🎨 پیشنهادات بهبود ظاهری

### 1. بهبود قالب base.html

**پیشنهادات CSS:**
```css
/* بهبود رنگ‌بندی و تم */
:root {
  --primary: #366092;
  --primary-dark: #2a4a6f;
  --secondary: #6c757d;
  --success: #28a745;
  --danger: #dc3545;
  --border: #dee2e6;
  --text: #212529;
  --muted: #6c757d;
  --zebra: #f8f9fa;
  --background: #ffffff;
}

/* بهبود جدول */
table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  box-shadow: 0 1px 3px rgba(0,0,0,0.1);
}

thead {
  background: linear-gradient(to bottom, var(--primary), var(--primary-dark));
  color: #fff;
}

th {
  padding: 12px 8px;
  font-weight: 600;
  text-transform: uppercase;
  font-size: 10px;
  letter-spacing: 0.5px;
}

tbody tr {
  transition: background-color 0.2s;
}

tbody tr:hover {
  background-color: #e9ecef;
}

/* بهبود header */
.header {
  background: linear-gradient(to right, #f8f9fa, #ffffff);
  padding: 20px;
  border-radius: 8px;
  margin-bottom: 20px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.title {
  font-size: 24px;
  font-weight: 700;
  margin-bottom: 8px;
}
```

---

### 2. بهبود قالب detail.html برای اسناد

**پیشنهادات:**
```html
{% extends "pdf/base.html" %}
{% block content %}
  <div class="document-header">
    <div class="header-left">
      <div class="document-type-badge">
        {{ document.document_type_name or ('سند' if is_fa else 'Document') }}
      </div>
      <div class="document-info">
        <div class="info-row">
          <span class="info-label">{{ 'کد سند' if is_fa else 'Code' }}:</span>
          <span class="info-value">{{ code or '-' }}</span>
        </div>
        <div class="info-row">
          <span class="info-label">{{ 'تاریخ' if is_fa else 'Date' }}:</span>
          <span class="info-value">{{ document_date_jalali or document_date or '-' }}</span>
        </div>
        {% if description %}
        <div class="info-row">
          <span class="info-label">{{ 'توضیحات' if is_fa else 'Description' }}:</span>
          <span class="info-value">{{ description }}</span>
        </div>
        {% endif %}
      </div>
    </div>
    <div class="header-right">
      <div class="business-info">
        <div class="business-name">{{ business_name or '-' }}</div>
        <div class="generated-at">
          {{ 'تولید شده در' if is_fa else 'Generated at' }}: {{ generated_at }}
        </div>
      </div>
    </div>
  </div>

  <div class="table-container">
    <table class="document-lines">
      <thead>
        <tr>
          <th style="width: 50%;">{{ 'شرح' if is_fa else 'Description' }}</th>
          <th style="width: 25%;">{{ 'بدهکار' if is_fa else 'Debit' }}</th>
          <th style="width: 25%;">{{ 'بستانکار' if is_fa else 'Credit' }}</th>
        </tr>
      </thead>
      <tbody>
        {% for line in lines or [] %}
          <tr>
            <td>{{ line.description or '-' }}</td>
            <td class="amount">{{ line.debit | money(0) | ltr | safe if line.debit else '-' }}</td>
            <td class="amount">{{ line.credit | money(0) | ltr | safe if line.credit else '-' }}</td>
          </tr>
        {% endfor %}
      </tbody>
      <tfoot>
        <tr class="totals-row">
          <td><strong>{{ 'جمع' if is_fa else 'Total' }}</strong></td>
          <td class="amount">
            <strong>{{ lines | sum(attribute='debit') | money(0) | ltr | safe }}</strong>
          </td>
          <td class="amount">
            <strong>{{ lines | sum(attribute='credit') | money(0) | ltr | safe }}</strong>
          </td>
        </tr>
      </tfoot>
    </table>
  </div>

  {% if document.notes %}
  <div class="notes-section">
    <h4>{{ 'یادداشت‌ها' if is_fa else 'Notes' }}</h4>
    <p>{{ document.notes }}</p>
  </div>
  {% endif %}
{% endblock %}
```

**CSS اضافی:**
```css
.document-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 24px;
  padding: 20px;
  background: #f8f9fa;
  border-radius: 8px;
}

.document-type-badge {
  display: inline-block;
  padding: 6px 12px;
  background: var(--primary);
  color: white;
  border-radius: 4px;
  font-weight: 600;
  font-size: 14px;
  margin-bottom: 12px;
}

.info-row {
  margin: 6px 0;
}

.info-label {
  font-weight: 600;
  color: var(--muted);
  margin-inline-end: 8px;
}

.info-value {
  color: var(--text);
}

.table-container {
  margin: 20px 0;
  overflow-x: auto;
}

.totals-row {
  background: #e9ecef;
  font-weight: 600;
  border-top: 2px solid var(--primary);
}

.notes-section {
  margin-top: 24px;
  padding: 16px;
  background: #fff3cd;
  border-right: 4px solid #ffc107;
  border-radius: 4px;
}
```

---

### 3. پشتیبانی از تم‌های مختلف

**پیشنهاد:**
```python
# اضافه کردن فیلد theme به ReportTemplate
# themes: 'default', 'minimal', 'professional', 'colorful'

# در render_with_template
theme = getattr(template, 'theme', 'default') or 'default'
context['theme'] = theme

# در قالب
{% if theme == 'minimal' %}
  <!-- استایل مینیمال -->
{% elif theme == 'professional' %}
  <!-- استایل حرفه‌ای -->
{% endif %}
```

---

### 4. بهبود صفحه‌بندی و Break Points

**پیشنهادات CSS:**
```css
/* جلوگیری از شکستن ردیف‌های جدول */
tbody tr {
  page-break-inside: avoid;
  break-inside: avoid;
}

/* Header و Footer در هر صفحه */
thead {
  display: table-header-group;
}

tfoot {
  display: table-footer-group;
}

/* بهبود فاصله‌گذاری صفحات */
@page {
  margin: 2cm 1.5cm;
  size: A4 portrait;
  
  @top-center {
    content: "{{ business_name }}";
    font-size: 10px;
    color: #666;
  }
  
  @bottom-center {
    content: "صفحه " counter(page) " از " counter(pages);
    font-size: 10px;
    color: #666;
  }
}
```

---

## 📱 پیشنهادات بهبود Frontend (Flutter)

### 1. بهبود DocumentService

**پیشنهاد:**
```dart
// در document_service.dart
Future<Uint8List> downloadPdf({
  required int documentId,
  int? templateId,
  String? paperSize,
  String? orientation,
}) async {
  try {
    final queryParams = <String, dynamic>{};
    if (templateId != null) queryParams['template_id'] = templateId;
    if (paperSize != null) queryParams['paper_size'] = paperSize;
    if (orientation != null) queryParams['orientation'] = orientation;
    
    final response = await _apiClient.get(
      '/documents/$documentId/pdf',
      queryParameters: queryParams,
      options: Options(
        responseType: ResponseType.bytes,
      ),
    );
    
    return response.data as Uint8List;
  } catch (e) {
    if (e is DioException) {
      throw Exception(e.response?.data['message'] ?? 'خطا در دریافت فایل PDF');
    }
    rethrow;
  }
}

// ذخیره فایل
Future<String> savePdfToFile(Uint8List pdfBytes, String filename) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(pdfBytes);
  return file.path;
}
```

---

### 2. UI برای انتخاب قالب

**پیشنهاد:**
```dart
// Dialog برای انتخاب قالب قبل از دانلود PDF
Future<int?> showTemplateSelectorDialog(
  BuildContext context,
  int businessId,
  String moduleKey,
  String? subtype,
) async {
  final service = ReportTemplateService(apiClient);
  final templates = await service.listTemplates(
    businessId: businessId,
    moduleKey: moduleKey,
    subtype: subtype,
    status: 'published',
  );
  
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('انتخاب قالب'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: templates.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                title: const Text('قالب پیش‌فرض'),
                leading: const Icon(Icons.description),
                onTap: () => Navigator.pop(context, null),
              );
            }
            final template = templates[index - 1];
            return ListTile(
              title: Text(template['name'] ?? ''),
              subtitle: Text(template['description'] ?? ''),
              leading: template['is_default'] == true
                  ? const Icon(Icons.star, color: Colors.amber)
                  : const Icon(Icons.description_outlined),
              onTap: () => Navigator.pop(context, template['id'] as int),
            );
          },
        ),
      ),
    ),
  );
}
```

---

## 🚀 پیشنهادات بهبود عملکرد

### 1. تولید PDF به صورت Async

**پیشنهاد:**
```python
from celery import shared_task

@shared_task
def generate_document_pdf_async(
    document_id: int,
    template_id: Optional[int] = None,
    user_id: int = None,
) -> str:
    """تولید PDF در پس‌زمینه و ذخیره در storage"""
    # تولید PDF
    # ذخیره در S3 یا local storage
    # برگرداندن URL
    pass

# در endpoint
@router.post("/documents/{document_id}/pdf/async")
async def generate_pdf_async(...):
    """درخواست تولید PDF در پس‌زمینه"""
    task = generate_document_pdf_async.delay(document_id, template_id)
    return {"task_id": task.id, "status": "processing"}
```

---

### 2. فشرده‌سازی PDF

**پیشنهاد:**
```python
from weasyprint import HTML
import io

def optimize_pdf(pdf_bytes: bytes) -> bytes:
    """فشرده‌سازی PDF (اختیاری)"""
    # می‌توان از PyPDF2 یا pypdf استفاده کرد
    try:
        from pypdf import PdfWriter, PdfReader
        reader = PdfReader(io.BytesIO(pdf_bytes))
        writer = PdfWriter()
        for page in reader.pages:
            writer.add_page(page)
        # فشرده‌سازی
        output = io.BytesIO()
        writer.write(output)
        return output.getvalue()
    except Exception:
        return pdf_bytes  # در صورت خطا، فایل اصلی را برگردان
```

---

## 📝 خلاصه اولویت‌ها

### اولویت بالا (فوری):
1. ✅ بهبود مدیریت خطا و لاگ‌گذاری
2. ✅ اضافه کردن فیلترهای مفید Jinja2
3. ✅ بهبود CSS و ظاهر قالب‌ها
4. ✅ پشتیبانی از تقویم شمسی در قالب

### اولویت متوسط:
5. ✅ سیستم کش برای قالب‌ها
6. ✅ بهبود DocumentService در Flutter
7. ✅ UI انتخاب قالب
8. ✅ پشتیبانی از Assets و تصاویر

### اولویت پایین (آینده):
9. ⏳ تولید PDF به صورت Async
10. ⏳ پشتیبانی از تم‌های مختلف
11. ⏳ فشرده‌سازی PDF
12. ⏳ Preview قالب در UI

---

## 📚 منابع و مراجع

- [WeasyPrint Documentation](https://weasyprint.org/)
- [Jinja2 Template Designer Documentation](https://jinja.palletsprojects.com/)
- [CSS Paged Media](https://www.w3.org/TR/css-page-3/)

