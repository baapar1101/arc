# معماری hesabixUI

سند معرفی معماری اپلیکیشن Flutter حسابداری «MarkStreet / hesabixUI». این سند با کمک بررسی خودکار گراف کد (ابزار [Graphify](https://github.com/Graphify-Labs/graphify)، خروجی در `graphify-out/`) و بازبینی دستی ساختار پروژه تهیه شده است.

تاریخ تهیه: 2026-08-17 · بر اساس کامیت `759a5d12` · برنچ `feat/m3-alignment`

---

## ۱. نمای کلی

| | |
|---|---|
| فریم‌ورک | Flutter 3.44.8 / Dart ^3.9.2 |
| پلتفرم‌ها | Web، Android، iOS، Windows، Linux، macOS (multi-platform واحد) |
| مسیریابی | `go_router` — یک `GoRouter` مرکزی در `main.dart` با بیش از ۲۵۰ `GoRoute` |
| HTTP | `dio` از طریق کلاس singleton-مانند `ApiClient` |
| ذخیره‌سازی محلی | `shared_preferences` (تنظیمات) + `flutter_secure_storage` (توکن/کلید API) |
| زبان رابط | فارسی (RTL) به‌عنوان زبان پیش‌فرض؛ انگلیسی هم پشتیبانی می‌شود (`l10n/`) |
| تقویم | هجری شمسی به‌صورت پیش‌فرض (`shamsi_date`, `persian_datetime_picker`) |
| مقیاس | ~806 فایل Dart در `lib/` · ۱۲۵ صفحهٔ کسب‌وکار · ۱۲۸ سرویس · ۵۵ مدل · ۵۹ گروه ویجت |

اپ یک **پنل مدیریتی حسابداری/ERP چندمستأجری (multi-tenant)** است: یک کاربر می‌تواند به چند «کسب‌وکار» (business) دسترسی داشته باشد و هر کسب‌وکار مجموعهٔ کاملی از ماژول‌ها (فاکتور، انبار، بانک، CRM، حقوق‌ودستمزد-مانند gestion موجودی، گزارش‌های مالی، هوش مصنوعی، مارکت‌پلیس افزونه و غیره) را در اختیار می‌گذارد.

---

## ۲. ساختار پوشه‌ها (`lib/`)

```
lib/
├── main.dart          نقطهٔ ورود + تعریف کامل روت‌ها (GoRouter)
├── core/               زیرساخت مشترک: API client، Auth، روتینگ، تقویم، locale
├── config/             AppConfig (API base URL و غیره، از dart-define)
├── theme/              قانون طلایی پروژه — تنها منبع مجاز مقادیر خام UI (رنگ/شعاع/فونت)
├── models/             کلاس‌های داده (DTO) متناظر با پاسخ API
├── services/           لایهٔ دسترسی به API به تفکیک دامنه (یک سرویس به‌ازای هر resource تقریباً)
├── pages/              صفحات به تفکیک ناحیه: admin / business / profile / public / mobile_launcher / warehouse / system_settings
├── widgets/            ویجت‌های قابل استفادهٔ مجدد، به تفکیک دامنه (invoice، document، crm، workflow، …)
├── controllers/         کنترلرهای فرم پیچیده (فعلاً فقط product_form_controller)
├── constants/           ثابت‌های سطح اپ
├── extensions/          Dart extensionها
├── utils/               کمک‌تابع‌های عمومی (date, number, responsive, route prefetch, …)
└── l10n/                ARB + کلاس‌های تولیدشدهٔ ترجمه (fa/en)
```

معماری، لایه‌بندی کلاسیک **UI ← Service ← ApiClient ← Backend REST** است؛ الگوی state management سنگین (BLoC/Riverpod/Provider tree) استفاده نشده — به‌جایش `ChangeNotifier` روی چند Controller/Store سراسری (`AuthStore`, `ThemeController`, `LocaleController`, `CalendarController`) و `setState` محلی در صفحات.

---

## ۳. هستهٔ مشترک (`lib/core/`)

این فایل‌ها «God Node»های واقعی گراف کد هستند (بیشترین تعداد یال ورودی/خروجی):

| فایل | نقش | یال‌های گراف |
|---|---|---|
| `calendar_controller.dart` → `CalendarController` | مدیریت تقویم جاری (شمسی/میلادی)، سراسری، `ChangeNotifier` | ۱۴۳ (بیشترین در کل پروژه) |
| `api_client.dart` → `ApiClient` | Wrapper سراسری روی `Dio`؛ bind شده به `AuthStore`/`CalendarController`/locale؛ افزودن هدر Authorization، نرمال‌سازی اعداد، مدیریت خطا و redirect به `/login` روی 401 | ۱۲۸ |
| `auth_store.dart` → `AuthStore` | نگهداری apiKey، دستگاه، کاربر جاری، کسب‌وکار جاری، دسترسی‌ها (app-level و business-level)، ارز انتخابی؛ persist با `flutter_secure_storage`/`shared_preferences` | ۱۲۰ |
| `route_registry.dart` | ثبت خودکار صفحات برای preload (کمک به `RoutePrefetcher`) | — |
| `permission_guard.dart` | صفحهٔ «عدم دسترسی» و کمک‌تابع‌های چک مجوز، در کنار `AuthStore.hasAppPermission` / `hasBusinessPermission` | — |
| `locale_controller.dart` | زبان جاری (fa/en) | — |
| `business_route_paths.dart` / `business_nav.dart` / `business_named_route_locations.dart` | تعریف مسیرهای پنل کسب‌وکار و منوی ناوبری آن به‌صورت متمرکز | — |
| `fiscal_year_controller.dart` | سال مالی انتخابی، bind شده به `ApiClient` برای فیلتر گزارش‌ها | — |

**الگوی احراز هویت و مجوز:** `ApiKey` بعد از لاگین در `AuthStore` (و به‌صورت امن در `flutter_secure_storage`) نگه داشته می‌شود. `ApiClient.bindAuthStore` هدر `Authorization` را به هر درخواست اضافه می‌کند. مجوزها دو سطحی‌اند: `appPermissions` (سراسری/ادمین) و `businessPermissions` (per-business، وابسته به نقش کاربر در آن کسب‌وکار). `redirect` در `GoRouter` قبل از هر ناوبری چک می‌کند که آیا apiKey موجود است؛ اگر نه، به `/login` هدایت می‌شود؛ per-route هم `PermissionGuard.buildAccessDeniedPage()` صدا زده می‌شود.

---

## ۴. مسیریابی (Routing)

همهٔ ۲۵۰+ روت به‌صورت دستی و تخت در یک `GoRouter` واحد داخل `main.dart` تعریف شده‌اند (فایل main.dart حدود ۳۸۵۰ خط است) — بدون تفکیک فایل به‌ازای هر ماژول. ساختار کلی:

- **Public routes** (بدون نیاز به لاگین): لینک‌های اشتراک‌گذاری فاکتور/شخص/فایل، ردیابی گارانتی، لینک‌های کوتاه `/i/:code`
- **`/login`**
- **`ShellRoute` → `ProfileShell`**: پنل کاربر (`/user/profile/*`) شامل داشبورد، تنظیمات حساب، امنیت، اعلان‌ها و زیرشاخهٔ کامل `system-settings/*` (ادمین سیستم: کاربران، پرداخت، ایمیل، هوش مصنوعی، Zohal، …)
- **`ShellRoute` → `BusinessShell`**: پنل کسب‌وکار (`/business/:id/*`) — بزرگ‌ترین بخش اپ: فاکتور، انبار، بانک، چک، حسابداری، گزارش‌ها (~۳۰ نوع گزارش)، CRM، تعمیرگاه، باشگاه مشتریان، توزیع (distribution)، یکپارچه‌سازی با Basalam/WooCommerce، Workflow builder، مارکت‌پلیس افزونه، AI chat/subscription
- **`StatefulShellRoute` → `MobileLauncherShell`**: نمای موبایل جایگزین (لانچر) برای `/mobile-launcher/:businessId/*`

هر صفحه با `registerRoutePage(...)` خودش را برای `RoutePrefetcher` ثبت می‌کند و در `_preloadPages()` (در `_MyAppState`) صدها صفحه به‌صورت eager نمونه‌سازی می‌شوند تا در build وب همه در باندل اصلی باشند و ناوبری بدون تأخیر lazy-load حس شود — هزینه‌اش باندل اولیهٔ سنگین است.

مسیرهای قدیمی پنل کسب‌وکار (بدون سگمنت `tabN`) با `redirectLegacyBusinessPath` نرمال‌سازی می‌شوند تا با `StatefulShellRoute` سازگار بمانند.

---

## ۵. لایهٔ داده: Model / Service / ApiClient

الگوی هر دامنه (نمونه: Person):

```
lib/models/person_model.dart        →  کلاس داده + fromJson/toJson
lib/services/person_service.dart    →  متدهای CRUD که ApiClient را صدا می‌زنند و JSON را به مدل تبدیل می‌کنند
lib/pages/business/persons_page.dart → مصرف‌کنندهٔ UI (لیست/فرم)
```

این الگو بدون انتزاع مشترک (no base `Repository`/`Service` class) برای هر یک از ~۵۵ resource تکرار شده — یعنی ۱۲۸ فایل سرویس مجزا، هرکدام مسئول یک domain (invoice, warehouse, tax, crm, wallet, workflow, zohal, basalam/woocommerce integration، …). خطاها با `services/errors/api_error.dart` و `utils/error_extractor.dart` نرمال‌سازی می‌شوند.

چند نکتهٔ خاص:
- ارتباطات real-time (چت CRM، مانیتورینگ، اعلان‌ها) از طریق WebSocket با پیاده‌سازی مجزا برای وب/غیر وب (`*_ws_client_io.dart` vs `*_ws_client_web.dart` vs `*_ws_client_stub.dart`) — الگوی conditional import برای پلتفرم.
- `AISseClient` برای stream پاسخ‌های هوش مصنوعی از Server-Sent Events استفاده می‌کند (مشابه الگوی io/web/stub).

---

## ۶. لایهٔ UI و سیستم طراحی (Theme)

طبق `CLAUDE.md` پروژه، `lib/theme/` **تنها محل مجاز** برای مقادیر خام UI است (رنگ/شعاع/فونت/آیکون) و برنچ فعلی (`feat/m3-alignment`) دقیقاً هدفش انطباق کامل با Material 3 است:

```
lib/theme/
├── app_theme.dart          ساخت ColorScheme/ThemeData نهایی (روشن/تاریک)
├── components.dart         override استایل ویجت‌های M3 (Button/Card/…)
├── theme_controller.dart   انتخاب حالت روشن/تاریک/سیستم + persist
└── tokens/
    ├── color_schemes.dart  رنگ‌های خام (تنها جایی که Color(0xFF…) مجاز است)
    ├── typography.dart     مقیاس تایپوگرافی
    └── extensions.dart     context.colors / context.texts / context.semantic / context.shape (نقطهٔ ورود مصرف توکن‌ها در بقیهٔ کد)
```

یک ابزار محافظ سفارشی، `tool/m3_audit.dart`، به‌عنوان دروازهٔ کیفیت اجرا می‌شود (`--check`) و از نشت مقادیر خام (رنگ/radius/فونت/پدینگ غیرجهت‌دار) به بیرون از `theme/` جلوگیری می‌کند — این عملاً نقش «lint سفارشی معماری» را بازی می‌کند، جدا از `flutter analyze` استاندارد.

رابط کاملاً RTL است (فارسی پیش‌فرض)؛ قانون پروژه استفاده از `EdgeInsetsDirectional`/`AlignmentDirectional` به‌جای `left/right` مطلق است.

---

## ۷. الگوهای اپ‌عریض (Cross-cutting)

- **Shell pattern**: هر ناحیهٔ اصلی (Profile, Business, MobileLauncher) یک Shell دارد که navbar/sidebar/state مشترک را نگه می‌دارد و `child` را رندر می‌کند؛ Shellها به AuthStore/LocaleController/CalendarController/ThemeController نیاز دارند و همه را به‌صورت prop پایین می‌فرستند (dependency-injection دستی، بدون Provider/InheritedWidget عمومی).
- **Permission Guard**: هر route حساس دستی چک `_authStore!.isSuperAdmin || _authStore!.hasAppPermission(...)` را در `builder` تکرار می‌کند (نه یک middleware مرکزی) — نقطهٔ تکرار کد قابل توجه در `main.dart`.
- **AI Layer**: `lib/widgets/ai/*` + `lib/services/ai_service.dart` + `ai_sse_client*` یک زیرسیستم کامل چت/دستیار هوش مصنوعی با marketplace مهارت، اشتراک، و پیگیری مصرف است؛ به‌صورت جداگانه در پنل کسب‌وکار و بخش‌های ادمین (system-settings/ai-*) نمایان می‌شود.
- **Workflow Engine (UI)**: `lib/pages/business/workflow_visual_editor_page.dart` + `widgets/workflow/*` یک ویرایشگر گراف/بوم (canvas) برای تعریف گردش‌کار کسب‌وکار است — یکی از پیچیده‌ترین زیرسیستم‌های UI پروژه.
- **یکپارچه‌سازی‌های خارجی**: Basalam، WooCommerce، Bale، Telegram، درگاه‌های پرداخت — هرکدام یک `*_integration_service.dart` + صفحات اختصاصی در `pages/business/basalam|woocommerce/`.
- **مارکت‌پلیس افزونه**: `plugin_marketplace_page.dart` + `marketplace_service.dart` مکانیزم خرید/فعال‌سازی افزونه (شبیه App Store داخلی) برای گسترش قابلیت هر کسب‌وکار.

---

## ۸. یافته‌های گراف کد (Graphify)

اجرا شد: `graphify update .` (استخراج AST محلی، بدون نیاز به کلید LLM) → `graphify-out/graph.json` (۳۶٬۸۱۰ گره / ۴۵٬۴۲۰ یال / ۶۱۸ کامیونیتی).

- **بدون Import Cycle** در کل کدبیس — نشانهٔ سالم بودن جهت وابستگی‌ها بین لایه‌ها.
- **God Nodes** (پریال‌ترین انتزاع‌های مرکزی): `CalendarController` (۱۴۳)، `ApiClient` (۱۲۸)، `AuthStore` (۱۲۰) — این سه عملاً «هستهٔ» اپ هستند و هر تغییر ساختاری در آن‌ها روی بیشتر صفحات اثر می‌گذارد.
- کامیونیتی‌های بزرگ گراف تقریباً هم‌راستا با پوشه‌های `pages/business/*` هستند؛ یعنی جداسازی ماژول‌ها در سطح فایل هم در گراف وابستگی واقعی منعکس شده (coupling کنترل‌شده بین ماژول‌های کسب‌وکار).
- دو هشدار جزئی: چند فایل third_party (`desktop_drop`) و پیکربندی پلتفرم (`android/.../generated_plugin_registrant.cc`) خطای parse جزئی داشتند — بی‌ربط به کد اصلی اپ.

برای کاوش بیشتر:
```bash
graphify explain "AuthStore"
graphify path "ApiClient" "InvoicesListPage"
```
گزارش کامل: [`graphify-out/GRAPH_REPORT.md`](../graphify-out/GRAPH_REPORT.md) — نمای گرافیکی تعاملی: `graphify-out/graph.html`

---

## ۹. نقاط ریسک / بدهی فنی قابل توجه (مشاهده‌شده، نه دستورالعمل تغییر)

- `main.dart` تک‌فایلی با ~۳۸۵۰ خط شامل هم تعریف کامل روت‌ها و هم لیست دستی preload صدها صفحه — بزرگ‌ترین نقطهٔ تمرکز کد پروژه.
- تکرار الگوی چک مجوز per-route به‌جای middleware/guard مرکزی روی `GoRoute`.
- نبود انتزاع مشترک بین ۱۲۸ فایل سرویس (هرکدام دستی Dio/ApiClient را صدا می‌زند) — تغییر یک الگوی مشترک (مثلاً pagination) نیازمند ویرایش پراکنده است.
- Eager-preload تمام صفحات در `main.dart` باعث باندل وب سنگین می‌شود؛ trade-off آگاهانه برای ناوبری سریع است، اما قابل بازبینی با lazy route-level code splitting.

---

*این سند صرفاً توصیفی است و مطابق قوانین پروژه (`CLAUDE.md`) هیچ تغییر رفتاری در کد اعمال نشده.*
