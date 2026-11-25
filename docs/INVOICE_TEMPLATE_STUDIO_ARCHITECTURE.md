# معماری آینده‌نگر استودیوی طراحی فاکتور

> وضعیت: فاز ۰ و فاز ۱ پیاده‌سازی شده؛ آماده بازبینی تیم حسابیکس
> تاریخ: ۱۴۰۵/۰۷/۲۹ (2026-10-21)
> دامنه: استودیوی قالب فاکتور، خروجی HTML/CSS، PDF و آمادگی برای اتصال AI/MCP

## ۱. تصمیم اصلی

استودیوی فاکتور باید یک **Design Document ساختاریافته و نسخه‌بندی‌شده** را ویرایش کند. این سند توسط compiler رسمی حسابیکس به HTML/CSS تبدیل می‌شود و همان HTML/CSS منبع تولید PDF و چاپ فیزیکی است.

```text
کاربر، UI یا AI
       ↓
Design Document با گرید تمام‌صفحه
       ↓
Validator + Normalizer
       ↓
Deterministic HTML/CSS Compiler
       ↓
HTML نهایی
       ↓
PDF Renderer موجود
       ↓
پرینتر فیزیکی
```

اصول غیرقابل نقض:

1. خروجی رسمی فاکتور فقط HTML/CSS است.
2. موتور مستقل برای تولید PDF فاکتور ساخته نمی‌شود.
3. PDF فقط از HTML/CSS تولیدشده توسط compiler رسمی ساخته می‌شود.
4. ویرایشگر بصری، موتور خروجی محسوب نمی‌شود و نباید خروجی چاپی مستقلی تولید کند.
5. کاربر و AI هر دو یک Design Document مشترک را تغییر می‌دهند.
6. AI یا MCP اجازه تولید JavaScript، Jinja یا CSS دلخواه برای استودیوی ساختاریافته ندارد.
7. حالت پیشرفته HTML/CSS از استودیوی ساختاریافته و مسیر AI جدا باقی می‌ماند.

## ۲. تفاوت منبع طراحی و خروجی

ذخیره مستقیم HTML/CSS به‌عنوان تنها منبع طراحی برای drag-and-drop، migration، responsive layout و AI مناسب نیست. در عوض:

- **منبع طراحی:** JSON معنایی، محدود و نسخه‌بندی‌شده؛
- **خروجی کامپایل‌شده:** HTML/CSS؛
- **خروجی چاپی:** PDF حاصل از همان HTML/CSS.

این تفکیک باعث می‌شود UI، REST API و MCP قواعد یکسانی داشته باشند، بدون آنکه موتور چاپ جدیدی ایجاد شود.

## ۳. وضعیت فعلی

استودیوی فعلی این قابلیت‌ها را دارد:

- schema نسخه ۳ و نواحی `header`، `body` و `footer`؛
- بلوک‌های معنایی فاکتور و کاتالوگ bindingهای کنترل‌شده؛
- انتخاب A3، A4، A5، A6، Letter، Legal و رول سفارشی؛
- RTL/LTR و تراز متن؛
- گرید میلی‌متری یکپارچه روی کل سطح قابل چاپ؛
- حرکت و تغییر اندازهٔ همهٔ بلوک‌ها در دو محور؛
- Anchor پایدار بلوک‌به‌بلوک با فاصلهٔ میلی‌متری و offset مستقل هر variant؛
- Pin به چپ، راست، بالا، پایین و مرکز صفحهٔ قابل چاپ؛
- زوم بوم با کنترل‌های UI و `Ctrl + Wheel` بدون اثر بر اندازهٔ چاپ؛
- HTML preview و PDF بر پایه compiler موجود؛
- سازگاری با قالب‌های قبلی.

مواردی که هنوز پایه معماری پایدار ندارند:

- containerهای تو‌در‌تو؛
- freeform layout محدود و امن؛
- عملیات patch اتمیک و revision-based؛
- API دامنه‌ای مناسب برای اتصال MCP؛
- audit منشأ تغییرات کاربر یا AI.

## ۴. مدل مفهومی نسخه بعدی

نام کاری نسخه بعدی در این سند `schema_version: 4` است. شماره نهایی باید هنگام تصویب تیم تثبیت شود.

Design Document باید یک درخت از container و component باشد:

```json
{
  "schema_version": 4,
  "document": {
    "direction": "rtl",
    "default_media_profile": "a4_portrait"
  },
  "root": {
    "id": "invoice-root",
    "kind": "container",
    "layout": {
      "type": "page_grid",
      "grid_mm": 1,
      "snap": true,
      "width_mm": 190,
      "height_mm": 277
    },
    "children": []
  },
  "variants": {
    "base": {},
    "a4_portrait": {},
    "a5_portrait": {},
    "roll_80": {}
  }
}
```

### ۴.۱. انواع container

| نوع | کاربرد | نمونه |
|---|---|---|
| `page_grid` | چیدمان اصلی و قابل‌مشاهدهٔ کل صفحه | تمام اجزای فاکتور |
| `flow` | گروه‌بندی معنایی داخلی و سازگاری با قالب قدیمی؛ در UI حالت طراحی نیست | ناحیه‌های داده‌ای قدیمی |
| `grid` | چیدمان ستونی و responsive | فروشنده و خریدار کنار هم |
| `freeform` | موقعیت آزاد در محدوده کنترل‌شده | لوگو، QR، مهر و متن ثابت |
| `stack` | قرارگیری لایه‌ای | واترمارک و عناصر پس‌زمینه |

هر node باید `id` پایدار داشته باشد. این شناسه نباید با reorder، تغییر عنوان یا migration بی‌دلیل عوض شود.

### ۴.۲. نمونه grid

```json
{
  "id": "buyer-info",
  "kind": "component",
  "component": "invoice.party_info",
  "placement": {
    "column_start": 31,
    "column_span": 30,
    "min_height_mm": 22
  },
  "content": {
    "role": "buyer",
    "title": "خریدار"
  }
}
```

### ۴.۳. نمونه جای‌گذاری روی گرید صفحه

```json
{
  "id": "invoice-qr",
  "kind": "component",
  "component": "invoice.qr",
  "placement": {
    "x_mm": 160,
    "y_mm": 5,
    "width_mm": 25,
    "height_mm": 25
  },
  "content": {
    "binding": "invoice.public_url"
  }
}
```

مختصات هر component نسبت به سطح قابل چاپ صفحه تعریف می‌شوند، نه نسبت به viewport مرورگر. جهت متن RTL/LTR نباید معنای هندسه فیزیکی را مبهم کند.

## ۵. محدودیت مهم محتوای پویا

همه اجزای فاکتور، از جمله جدول اقلام، روی گرید تمام‌صفحه جای‌گذاری می‌شوند. component پویا درون خانهٔ گرید می‌تواند از حداقل ارتفاع طراحی‌شده بزرگ‌تر شود. جابه‌جایی بلوک‌های وابسته نباید به هم‌پوشانی اتفاقی خانه‌های CSS Grid متکی باشد؛ رابطه باید به‌صورت Anchor صریح در Design Document ذخیره شود.

قواعد پیشنهادی:

- جدول اقلام یک component پویا روی `page_grid` است و ارتفاع تنظیم‌شده برای آن حداقل ارتفاع محسوب می‌شود.
- اتصال `top` یک بلوک به `bottom` بلوک دیگر یک زنجیرهٔ محتوایی می‌سازد؛ compiler آن را به ترتیب طبیعی HTML تبدیل می‌کند تا ارتفاع واقعی داده در زمان چاپ تعیین‌کننده باشد.
- فاصلهٔ اتصال با `offset_mm` و override هر media profile ذخیره می‌شود؛ مثلاً پرداخت همیشه ۵ میلی‌متر بعد از انتهای واقعی جدول قرار می‌گیرد.
- جمع‌بندی، پرداخت، توضیحات و امضا می‌توانند زنجیره شوند و بلوک‌های مستقل همچنان مختصات آزاد خود را حفظ کنند.
- header و footer تکرارشونده توسط compiler و CSS چاپ مدیریت شوند.
- ردیف جدول تا حد امکان با `break-inside: avoid` نصف نشود.
- عنوان ستون‌ها در صفحه بعد تکرار شود.
- حالت row-level freeform در UI وجود ندارد؛ کل صفحه بوم واحد است.

این مرز جلوی هم‌پوشانی داده پویا با جمع‌بندی و پاورقی را می‌گیرد.

## ۶. responsive layout برای چاپ

ریسپانسیو بودن فاکتور باید براساس **پروفایل رسانه چاپی** باشد، نه عرض viewport مرورگر.

پروفایل‌های پایه:

- `a3_portrait` و `a3_landscape`
- `a4_portrait`
- `a4_landscape`
- `a5_portrait`
- `a5_landscape`
- `a6_portrait` و `a6_landscape`
- `letter_portrait` و `letter_landscape`
- `legal_portrait` و `legal_landscape`
- `roll_80`
- `roll_58`
- `roll_60` و `roll_100`
- `custom_sheet_portrait` و `custom_sheet_landscape`
- `custom_roll`

هر variant فقط override هندسی nodeها را نگه می‌دارد و محتوا در درخت canonical باقی می‌ماند. همه پروفایل‌های پشتیبانی‌شده override صریح دارند؛ برای مثال اطلاعات فروشنده و خریدار در A4 می‌توانند دو ستون باشند و روی رول تمام عرض شوند.

انتخاب variant باید پیش از compile انجام شود. تکیه کامل بر media query مرورگر یا قابلیت‌های غیرقطعی PDF Renderer مجاز نیست.

## ۷. معماری ویرایشگر

ویرایشگر می‌تواند برای تعامل سریع، هندسه nodeها را در Flutter نمایش دهد؛ اما این صحنه نباید خروجی چاپی تولید کند.

چرخه صحیح ویرایش:

1. UI یک عملیات ساختاریافته روی Design Document اعمال می‌کند.
2. تغییر در history محلی ثبت می‌شود.
3. Design Document اعتبارسنجی می‌شود.
4. compiler رسمی HTML/CSS پیش‌نمایش را تولید می‌کند.
5. PDF backend مرجع نهایی تطبیق چاپ است.

در صورت پایداری فنی، می‌توان در آینده interaction را مستقیماً روی DOM خروجی انجام داد؛ اما این انتخاب نباید شرط schema یا compiler باشد.

دو سطح پیش‌نمایش لازم است:

- **HTML Preview:** سریع و مناسب ویرایش روزمره؛
- **PDF Preview:** معتبر برای کنترل نهایی صفحه‌بندی و چاپ.

مرورگر و PDF Renderer ممکن است یک CSS مشترک را با تفاوت‌های جزئی نمایش دهند؛ بنابراین HTML preview نباید تنها مرجع صحت چاپ باشد.

## ۸. Snap هوشمند

Snap باید در فضای مختصات container و فقط میان siblingهای قابل مقایسه انجام شود.

### ۸.۱. نامزدهای Snap

- لبه ابتدا و انتهای عنصر؛
- مرکز افقی و عمودی؛
- baseline متن در فاز بعدی؛
- حاشیه امن container؛
- guideهای دستی؛
- گرید ۱، ۳ یا ۵ میلی‌متری؛
- فاصله مساوی میان عناصر در فاز بعدی.

### ۸.۲. قواعد تعامل

- حرکت حین drag باید روان و بدون پرش باشد.
- Snap به‌صورت زنده همراه خط راهنما نمایش داده شود.
- آستانه Snap در screen pixel تعریف و با Zoom به میلی‌متر تبدیل شود.
- محور X و Y جداگانه resolve شوند.
- برای جلوگیری از لرزش روی مرز، hysteresis وجود داشته باشد.
- کاربر بتواند Snap را موقتاً با کلید modifier غیرفعال کند.
- در پایان drag فقط یک history entry ایجاد شود.
- مختصات و اندازه نهایی داخل محدوده container clamp شوند.

اولویت پیشنهادی:

```text
Guide دستی
→ لبه یا مرکز siblingها
→ حاشیه امن
→ فاصله مساوی
→ گرید
```

Snap معمولی همچنان فقط مختصات عددی تولید می‌کند. اتصال پایدار فقط از دستگیره‌های Anchor ساخته می‌شود تا هم‌ترازی ساده ناخواسته به وابستگی تبدیل نشود. هر component می‌تواند یک `constraints` اختیاری داشته باشد:

```json
{
  "constraints": {
    "links": [
      {
        "axis": "vertical",
        "source_anchor": "top",
        "target": {
          "type": "node",
          "id": "invoice-lines",
          "anchor": "bottom"
        },
        "offset_mm": 5,
        "variant_offsets": {
          "a4_portrait": 5,
          "roll_80": 2
        }
      }
    ],
    "pins": {
      "left": true,
      "right": true
    },
    "keep_together": true
  }
}
```

روابط یک گراف بدون دور هستند. validator هدف حذف‌شده، نقطهٔ نامعتبر، چند رابطهٔ متناقض روی یک محور و cycle را رد می‌کند. اتصال چپ و راست هم‌زمان عرض responsive می‌سازد و اتصال بالا و پایین هم‌زمان ارتفاع ناحیه را Stretch می‌کند.

## ۹. compiler رسمی HTML/CSS

compiler باید:

- قطعی و نسخه‌بندی‌شده باشد؛
- فقط CSS پشتیبانی‌شده توسط PDF Renderer پروژه تولید کند؛
- برای تمام nodeها markup پایدار و قابل ردیابی تولید کند؛
- واحدهای چاپی را با `mm` یا `pt` تولید کند؛
- فونت فارسی حسابیکس را embed کند؛
- RTL/LTR را مستقل از هندسه مدیریت کند؛
- CSS و Jinja دلخواه را از schema ساختاریافته قبول نکند؛
- diagnostics قابل استفاده توسط UI و AI برگرداند.

نمونه markup قابل ردیابی:

```html
<section
  class="rt-node rt-party-info"
  data-template-node-id="buyer-info"
>
  ...
</section>
```

برای بازتولید خروجی منتشرشده بهتر است snapshot انتشار شامل این موارد باشد:

- Design Document؛
- `schema_version`؛
- `compiler_version`؛
- HTML/CSS کامپایل‌شده؛
- assetها و فونت‌های مؤثر؛
- زمان و کاربر منتشرکننده.

## ۱۰. آمادگی برای AI و MCP

MCP نباید مستقیماً به دیتابیس یا compiler داخلی دسترسی داشته باشد. ابتدا باید domain serviceهای پایدار ایجاد شوند:

- Draft Service
- Validation Service
- Patch Service
- Compilation Service
- Preview Service
- Publication Service

سپس UI، REST API و MCP همگی از همان serviceها استفاده می‌کنند:

```text
Flutter UI ─┐
REST API ───┼→ Template Domain Services
MCP Server ─┘
```

### ۱۰.۱. عملیات patch

AI و UI باید عملیات کوچک و معنایی ارسال کنند، نه HTML کامل:

```json
{
  "template_id": 42,
  "base_revision": 17,
  "operation_id": "uuid",
  "operations": [
    {
      "op": "move_node",
      "node_id": "business-logo",
      "x_mm": 8,
      "y_mm": 5
    }
  ]
}
```

عملیات باید:

- اتمیک؛
- idempotent؛
- revision-based؛
- قابل audit؛
- قابل Undo؛
- محدود به draft؛
- دارای validation قبل از commit

باشند.

انتشار از طریق AI باید همیشه نیازمند تأیید صریح کاربر و permission مناسب باشد.

### ۱۰.۲. ساخت قالب از روی عکس

جریان آینده:

1. کاربر تصویر نمونه فاکتور را به AI می‌دهد.
2. AI schema و کاتالوگ componentها و bindingها را دریافت می‌کند.
3. ساختار تصویر را به componentهای حسابیکس نگاشت می‌کند.
4. موارد نامطمئن را همراه confidence اعلام می‌کند.
5. یک draft ایجاد می‌کند.
6. حسابیکس draft را validate و compile می‌کند.
7. AI یا کاربر preview را بررسی و patchهای اصلاحی اعمال می‌کنند.
8. انتشار فقط پس از تأیید کاربر انجام می‌شود.

AI نباید عبارت دیده‌شده در تصویر را بدون کنترل به متغیر Jinja تبدیل کند. نگاشت باید فقط به binding catalog رسمی انجام شود.

## ۱۱. امنیت

مسیر استودیوی ساختاریافته و MCP نباید این موارد را بپذیرد:

- JavaScript؛
- Jinja expression آزاد؛
- CSS دلخواه؛
- URL خارجی تأییدنشده؛
- فونت یا asset ثبت‌نشده؛
- نام binding خارج از catalog؛
- component ناشناخته؛
- مختصات یا اندازه خارج از محدوده؛
- انتشار بدون permission و تأیید کاربر.

styleها باید از propertyهای whitelist‌شده و design tokenهای حسابیکس ساخته شوند.

## ۱۲. نسخه‌بندی، migration و هم‌زمانی

- schema باید migration یک‌طرفه و تست‌شده داشته باشد.
- مهاجرت قالب v3 به نسخه بعدی نباید قالب قبلی را overwrite کند.
- هنگام بازکردن قالب قدیمی، migration در حافظه یا روی draft جدید انجام شود.
- هر draft باید `revision` داشته باشد.
- patch با `base_revision` قدیمی باید conflict برگرداند.
- منشأ تغییر باید `user`، `migration`، `api` یا `ai` ثبت شود.
- قالب منتشرشده immutable باشد و ویرایش بعدی draft جدید بسازد.

## ۱۳. محدوده پیشنهادی اجرای فعلی

پیشنهاد این سند این است که اجرای فعلی در پایان **فاز ۱** متوقف و برای تست واقعی کاربران تحویل شود.

### فاز ۰ — قرارداد معماری و schema

این فاز باید قبل از توسعه بیشتر UI انجام شود:

- [ ] تصویب نهایی اصول این سند توسط تیم؛
- [x] تعریف schema نسخه بعدی و JSON Schema رسمی؛
- [x] تعریف container tree و component node؛
- [x] تعریف component catalog و binding catalog؛
- [x] تعریف media profile و variant inheritance؛
- [x] تثبیت قرارداد compiler با خروجی انحصاری HTML/CSS؛
- [x] تعریف migration از v3 به‌صورت copy-on-write و بدون overwrite؛
- [x] تعریف diagnostics استاندارد validator/compiler.

### فاز ۱ — MVP ویرایشگر آینده‌نگر

- [x] پشتیبانی compiler از schema جدید؛
- [x] تبدیل سطح طراحی v4 به گرید تمام‌صفحه؛
- [x] حفظ grouping معنایی header/body/footer بدون شکستن بوم به سه Flow قابل‌مشاهده؛
- [x] پشتیبانی از componentهای ثابت و پویا روی همان گرید؛
- [x] drag و resize میلی‌متری همهٔ عناصر؛
- [x] انتخاب گرید ۱، ۳ و ۵ میلی‌متری؛
- [x] Snap به گرید، حاشیه، لبه و مرکز siblingها؛
- [x] نمایش guide هنگام Snap؛
- [x] clamp کامل حرکت و resize داخل container؛
- [x] Undo/Redo با یک entry برای هر gesture؛
- [x] پنل عددی X/Y/W/H؛
- [x] تولید HTML preview از compiler رسمی؛
- [x] کنترل نهایی با PDF preview موجود؛
- [x] variant مستقل برای تمام کاغذهای صفحه‌ای، رول و سفارشی؛
- [x] تست migration، validation، compiler، A4، رول ۸۰ و تعامل ویرایشگر.

### موارد خارج از اجرای فعلی

این موارد باید پس از دریافت بازخورد فاز ۱ انجام شوند:

- multi-select و group؛
- equal-spacing و baseline snapping؛
- constraint solver؛
- collaboration هم‌زمان؛
- patch API عمومی؛
- revision conflict و audit کامل AI؛
- MCP server؛
- تحلیل تصویر و تولید قالب توسط vision AI؛
- انتشار قالب توسط AI؛
- marketplace برای componentهای شخص ثالث.

## ۱۴. معیار پذیرش فاز ۱

فاز ۱ زمانی کامل است که:

1. قالب v3 بدون از دست رفتن محتوا به draft جدید مهاجرت کند.
2. خروجی رسمی همچنان فقط HTML/CSS باشد.
3. HTML و PDF از یک Design Document و compiler واحد تولید شوند.
4. جدول با تعداد اقلام متغیر باعث هم‌پوشانی جمع‌بندی نشود.
5. عنصر ثابت با ماوس حرکت و resize شود.
6. Snap گرید و Snap لبه/مرکز قابل مشاهده و قابل غیرفعال‌کردن باشند.
7. موقعیت و اندازه خارج از محدوده ذخیره نشود.
8. RTL/LTR هندسه فیزیکی را تغییر ناخواسته ندهد.
9. هر gesture فقط یک مرحله Undo بسازد.
10. A4 و رول ۸۰ میلی‌متری با PDF واقعی آزمایش شوند.
11. قالب‌های قدیمی بدون overwrite باقی بمانند.
12. schema و compiler تست‌های deterministic داشته باشند.

## ۱۵. تصمیم پیشنهادی برای اکنون

در حال حاضر نباید MCP یا تولید قالب از روی عکس پیاده‌سازی شود. اقدام درست این است که ابتدا فاز ۰ و فاز ۱ تکمیل شوند؛ زیرا MCP بدون schema پایدار و patch service معتبر، فقط بدهی فنی را از UI به AI منتقل می‌کند.

ترتیب پیشنهادی اجرای نزدیک:

1. تصویب این سند و تثبیت schema؛
2. نوشتن validator، normalizer و migration؛
3. تکمیل compiler HTML/CSS؛
4. ساخت گرید تمام‌صفحه و Snap MVP؛
5. تست با A4 و رول ۸۰؛
6. تحویل به کاربران منتخب و دریافت بازخورد؛
7. تصمیم‌گیری درباره responsive variant و patch API؛
8. سپس طراحی MCP.

این مرزبندی باعث می‌شود قابلیت فعلی قابل استفاده باقی بماند و در عین حال پایه‌ای ساخته شود که بعداً بدون بازنویسی کامل، AI و MCP روی آن قرار بگیرند.
