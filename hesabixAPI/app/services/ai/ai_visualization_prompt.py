"""
دستورالعمل نمایش نمودار و جدول در پاسخ چت (فاز ۱ visualization).
"""
from __future__ import annotations

VISUALIZATION_PROMPT_BLOCK = """
نمایش بصری در پاسخ (فقط JSON معتبر داخل بلوک‌های جدا):

**نمودار** — بلوک ```chart
انواع: bar (مقایسه)، line (روند زمانی)، pie (سهم درصد)
فیلدهای مشترک: type, title, labels[], unit (اختیاری)
- تک‌سری: "values":[100,200]
- چندسری (bar/line): "series":[{"name":"فروش","values":[...]},{"name":"خرید","values":[...]}]
حداکثر ۱۵ برچسب؛ اعداد از خروجی tool بگیرید نه حدس.

مثال میله‌ای:
```chart
{"type":"bar","title":"فروش ماهانه","labels":["فروردین","اردیبهشت"],"values":[1200000,980000],"unit":"ریال"}
```

مثال خطی چندسری:
```chart
{"type":"line","title":"فروش و خرید","labels":["هفته۱","هفته۲"],"series":[{"name":"فروش","values":[10,14]},{"name":"خرید","values":[8,9]}],"unit":"میلیون"}
```

مثال دایره‌ای:
```chart
{"type":"pie","title":"سهم مشتریان","labels":["علی","رضا"],"values":[60,40]}
```

**جدول** — بلوک ```table
ستون‌ها: headers (ساده) یا columns با key/label/align (right|left|center)
ردیف‌ها: آرایهٔ object با همان keyها، یا آرایهٔ آرایه هم‌ترتیب با headers

مثال با headers:
```table
{"title":"۵ بدهکار برتر","headers":["نام","مانده"],"rows":[["علی احمدی",1500000],["شرکت الف",980000]]}
```

مثال با columns:
```table
{"title":"فاکتورهای امروز","columns":[{"key":"code","label":"شماره","align":"right"},{"key":"amount","label":"مبلغ","align":"right"}],"rows":[{"code":"#1024","amount":2500000}]}
```

قوانین:
- برای لیست‌های بیش از ۵ ردیف یا مقایسهٔ چند شاخص، حتماً نمودار یا جدول بگذار.
- پس از get_sales_report، get_debtors_report، get_cash_flow و مشابه، داده را به chart/table تبدیل کن.
- برای جدول حتماً از بلوک ```table با JSON استفاده کن؛ از جدول مارک‌داون با | استفاده نکن.
- JSON را در یک خط یا چند خط بنویس؛ کلیدها انگلیسی، مقادیر متنی فارسی.
""".strip()
