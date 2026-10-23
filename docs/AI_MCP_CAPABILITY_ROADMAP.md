# ممیزی پوشش قابلیت‌های حسابیکس در MCP و برنامهٔ اجرایی

تاریخ ممیزی: ۱۴۰۵/۰۸/۰۱ (۲۰۲۶-۱۰-۲۳)

## هدف و تعریف تکمیل

هدف، فراهم‌کردن قابلیت‌های کاربردی نرم‌افزار برای دستیارهای هوش مصنوعی از راه MCP است؛ با همان tenant، عضویت، نقش و مجوزهای دامنه‌ای کاربر. «همهٔ قابلیت‌ها» به معنی تبدیل بی‌قیدوشرط هر endpoint داخلی به ابزار نیست. عملیات کسب‌وکاری باید از مسیر سرویس دامنه، با اعتبارسنجی و مجوزهای موجود در دسترس قرار بگیرد. endpointهای ورود، OTP، پنل پشتیبانی/اپراتور، مدیریت سراسری سامانه، callback/webhook، فایل عمومی و عملیات زیرساخت به‌خودی‌خود ابزار کسب‌وکاری MCP نمی‌شوند. هر مورد مستثنا باید در ماتریس پوشش دلیل و مسیر جایگزین داشته باشد.

تکمیل زمانی پذیرفته می‌شود که: (۱) هر قابلیت کاربرمحور در ماتریس به ابزار خواندن/نوشتن، منبع، یا استثنای مستند نگاشت شده باشد؛ (۲) مجوز عضو در زمان فهرست و اجرا اعمال شود؛ (۳) هیچ آرگومان مدل نتواند tenant یا مجوز را تغییر دهد؛ (۴) ابزارهای نوشتنی قرارداد پارامتر روشن، اثر جانبی و تأیید متناسب داشته باشند؛ (۵) promptها فقط به ابزار واقعی همین اتصال ارجاع دهند؛ (۶) راهنمای MCP و کاتالوگ ابزار با کد همگام باشند.

## روش و محدودهٔ ممیزی

- در `hesabixAPI/adapters/api/v1` با AST تعداد ۱۶۰۲ ثبت route صریح در ۱۴۱ ماژول شمرده شد؛ این شمارش routeهای تولیدشده در زمان اجرا را شامل نمی‌شود و مساوی تعداد قابلیت‌های مستقل نیست.
- baseline پیش از پیاده‌سازی این سند: در `function_registry.py` و `ai_function_extensions*.py` تعداد ۱۸۰ نام literal از `AIFunction` و در `ai_tool_manifest.py` تعداد ۱۸۰ مدخل metadata استخراج شد؛ در baseline مدخل ثبت‌نشده در manifest یافت نشد. پس از ابزارهای انبار و کالا، گردش‌کار مالیاتی، CRUD چرخهٔ CRM، خطوط فرصت و تبدیل فرصت به فاکتور، شمار literal ابزارها پیش از این مرحله ۲۲۱ بود؛ پس از افزودن ۴۸ ابزار CRM، ۱۳ ابزار فاکتور و ۱۲ ابزار چک و ۳ ابزار انبارگردانی، تعداد ابزارهای استخراج‌شده از AST و manifest هر دو ۲۹۷ است؛ همه یکتا هستند و اختلافی ندارند.
- MCP از registry مشترک AI تغذیه می‌شود؛ سپس ابزارهای وابسته به کسب‌وکار، نقش کاربر، permissionهای جاری، allowlist رضایت OAuth و scope خواندن/نوشتن را فیلتر می‌کند. بررسی فقط وجود نام ابزار نبود؛ APIهای نمونهٔ فاکتور، انبار و CRM با ابزارها مقایسه شدند.
- شمار routeها ابزار پوشش نیست. بعضی routeها CRUD داخلی، چند endpoint برای یک گردش‌کار، webhook یا API عمومی هستند. ماتریس زیر قابلیت را در سطح گردش‌کار دسته‌بندی می‌کند.

## وضعیت پایه و شکاف‌های تأییدشده

### آنچه از قبل در اختیار MCP است

- اتصال OAuth با PKCE، انتخاب کسب‌وکار و ابزار، مجوزهای per-tool، حفظ مجوزها در refresh و اعتبارسنجی دوبارهٔ عضویت و permission عضو.
- جستجو/جزئیات و ثبت فاکتور، ویرایش و حذف فاکتور، ثبت و ویرایش کالا، ایجاد سرنخ CRM، ایجاد حوالهٔ دستی انبار و خواندن حواله/موجودی.
- در baseline ثبت‌شده ۲۲۱ تعریف literal وجود داشت؛ مرحله‌های بعد ۴۸ ابزار CRM، ۱۳ ابزار فاکتور، ۱۲ ابزار چک، ۳ ابزار انبارگردانی، ۳ ابزار ثبت/حذف گروهی اسناد مالی، ۳۷ ابزار حقوق‌ودستمزد، ۶ ابزار گروهی کالا/قیمت/انبار پیش‌فرض، ۱۰ گزارش ساخت‌یافته انبار، ۱۸ ابزار تعمیرگاه، ۶ ابزار مدیریت گارانتی، ۱۹ ابزار تولید/BOM و ۸۷ ابزار تازهٔ توزیع اضافه کرده‌اند. manifest فعلی ۴۸۳ نام یکتا دارد؛ شمار ابزار برابر دسترسی هر کاربر نیست و MCP زیرمجموعهٔ مجاز همان کاربر را ارائه می‌کند.

### شکاف‌هایی که در کد مسیر API و registry با هم اختلاف دارند

| حوزه | قابلیت‌های موجود در API یا دامنه | وضعیت AI/MCP در ممیزی | کار لازم |
|---|---|---|---|
| فاکتور و سامانهٔ مالیاتی | فضای کاری مالیاتی، افزودن/حذف، پیوند مرجع، ارسال، ارسال اصلاحی، ابطال، ارسال/حذف گروهی، سلامت سرویس، استعلام، timeline، اعتبارسنجی و عملیات سریع | CRUD فاکتور، upsert گروهی حداکثر ۲۵تایی، قسط‌بندی/جستجوی اقساط، محاسبه مانده، tagها، پیش‌نمایش اثر حذف، حذف گروهی حداکثر ۱۰۰تایی و لینک عمومی امن؛ ابزارهای افزودن/حذف در کارپوشه، ارسال عادی/اصلاحی، ابطال، وضعیت، اعتبارسنجی و استعلام اضافه شده‌اند. پیوند مرجع برای ثبت برگشت، batch validation، صف خطا، timeline و فهرست مرجع پوشش دارند؛ ارسال گروهی محدود، retry، health، صف خطا و حذف گروهی ابزار دارند؛ quick action تجمیعی و import/export باینری MCP نشده‌اند؛ quick action می‌تواند روی مجموعهٔ نامحدود فاکتورها اثر خارجی بگذارد و خروجی فایل در پروتکل tool مناسب نیست | تکمیل عملیات باقیمانده و تطبیق اثر بیرونی، مجوز و خروجی هر عملیات؛ idempotency و گزارش نتیجه را بررسی کنید |
| انبار | ایجاد، ویرایش سند و خطوط، قطعی‌سازی، حذف draft، حذف گروهی، لغو سند posted با سند معکوس، شمارش موجودی و تعدیل | جستجو/جزئیات/موجودی، lifecycle حواله و انبارگردانی اضافه شده؛ ۱۰ گزارش حواله، کم‌گردش، بحرانی، انتقال، تعدیل، عملکرد، حرکت کالا، ارزش‌گذاری، draft و turnover اکنون JSON صفحه‌بندی‌شده دارند | بررسی تعدیل با کنترل موجودی منفی، exportهای XLSX و تطبیق نهایی permission و workflow |
| CRM | ساخت/ویرایش/حذف سرنخ، تبدیل به مشتری؛ CRUD فرصت و فعالیت؛ تاریخچه، یادداشت/تقویم، برچسب، دلایل بستن، فیلد سفارشی، تعریف فرایند و مرحله، گزارش‌ها، customer 360 و صف کاری | ابزارهای چرخهٔ اصلی، تنظیمات، تاریخچه/یادداشت/metadata/فرایند/مرحله، گزارش‌ها و صف کاری اضافه شده‌اند. endpointهای عمومی CRM و routeهای تلفیقی خارج از این فایل هنوز باید در ممیزی جداگانه بررسی شوند؛ routeهای هسته syntax/metadata دارند و نیازمند integration verification هستند | بررسی CRM AI/chat/public routes و تطبیق نهایی permission |
| محصولات و کاتالوگ | CRUD کالا، import/export، ویرایش گروهی قیمت/انبار، bundle، attribute، instance و گزارش‌ها | CRUD و پیش‌بررسی وابستگی موجود؛ upsert محدود ۲۵ کالا، حذف محدود ۱۰۰ کالا، preview/apply قیمت روی شناسه‌های صریح حداکثر ۱۰۰ کالا و preview/apply انبار پیش‌فرض همین سقف اضافه شد؛ opening balance همچنان به مجوز مستقل نیاز دارد | Import/Export Excel و PDF و برخی امکانات تامین‌کننده/کاتالوگ، bundle/instance کامل، گزارش‌ها و بقیه routeها را تکمیل و تطبیق دهید |
| مالی و اسناد | حساب، بانک/صندوق، دریافت/پرداخت، چک و گردش/راس‌گیری، انتقال، هزینه/درآمد، سال مالی، ارز | ابزارهای upsert گروهی دریافت/پرداخت و هزینه/درآمد حداکثر ۲۵ آیتم با مجوز per-item افزودن/ویرایش؛ حذف گروهی هزینه/درآمد حداکثر ۱۰۰ سند با tenant/type check کامل و permission `expenses_income.delete`؛ همه با تأیید اجباری | چرخه‌های چک/تطبیق بانکی، گزارش‌ها و تطبیق همه ماژول‌های مالی با route ادامه دارد |
| حقوق‌ودستمزد | تنظیمات، کارکنان، دسته/اجزای حقوق، بخش‌ها، دوره‌ها، اجرای حقوق، تأیید، ثبت حسابداری/پرداخت، گزارش و فایل Excel/PDF | ۳۷ ابزار MCP برای تنظیمات، پرسنل، اقلام، دوره، اجرای حقوق، گزارش، تأیید/رد، نهایی‌سازی و ثبت حسابداری/پرداخت افزوده شد؛ `payroll.view/manage/operate/approve/post` با permission واقعی بخش payroll نگاشت شده‌اند | Import/Export Excel و PDF فیش در MCP نیستند؛ باید قرارداد دادهٔ ساخت‌یافته/Resource برای جایگزینی باینری، کنترل افشای فیش و import گروهی بررسی شود. route به route باقی‌مانده نیز تطبیق داده شود |
| تعمیرگاه | تنظیمات، تعمیرکار، سفارش تعمیر، تخصیص/وضعیت، قطعات و موجودی، هزینه، تکمیل/تحویل، فاکتور و گزارش تعمیرات گارانتی | ابزارهای tenant-bound برای CRUD سفارش/تعمیرکار، تخصیص، تغییر وضعیت، افزودن قطعه، محاسبه هزینه، تکمیل/تحویل، صدور فاکتور و گزارش حسابداری/گارانتی اضافه شد؛ اعلان مشتری و ثبت مالی با تأیید جداگانه هستند. ابزارهای قدیمی خواندن از permission اشتباه `invoices.read` به `repair_shop.read` اصلاح شدند | ویرایش کامل تنظیمات پیام/فرم، history و routeهای جانبی permissionها را با lifecycleهای سرویس تطبیق دهید؛ اعلان SMS/email از ابزارهای وضعیت مجزا ارزیابی شود |
| گارانتی | تنظیمات، تولید کد، فهرست کدها، انتساب به شخص، حذف و جریان عمومی فعال‌سازی/رهگیری | ابزارهای تنظیمات، تولید دسته‌ای ۵۰تایی، جستجوی صفحه‌بندی‌شده، فهرست به تفکیک شخص و حذف تکی/گروهی اضافه شد؛ خروجی AI اطلاعات تماس و token رهگیری را حذف می‌کند؛ permissionها با `read/manage/write/delete` واقعی API همسان شدند. endpointهای عمومی مشتریان عمداً از MCP کسب‌وکاری کنار گذاشته شدند | بررسی workflow فعال‌سازی مدیریت‌شده با قرارداد رضایت و ثبت تماس جداگانه |
| تولید و BOM | تعریف/ویرایش/حذف BOM، انفجار مواد، پیش‌نویس سند تولید، سفارش تولید، lifecycle، lot، برنامه مواد و بهای تمام‌شده | ۱۹ ابزار ساخت‌یافته با schemaهای API، کنترل نسخه سفارش، تأیید برای تغییر lifecycle/موجودی، و مجوزهای inventory.read/write/delete اضافه شد؛ فهرست BOM و جستجوی اسناد تولید قبلاً موجود بودند | تطبیق خط به خط قوانین permission و ثبت سند با API؛ بررسی report/export و مشخص‌کردن وضعیت‌های مختلف approval/consumption |
| توزیع | قلمرو/مسیر/توقف/تخصیص، بازدید، مرجوعی، خودرو و موجودی، هدف/تسویه، پیش‌فروش و پروموشن، تحویل، کمیسیون، پروفایل مشتری، ترکیب کالا و گزارش‌ها | ابزارهای گردش‌کار اصلی و prompt اختصاصی افزوده شد. عملیات نوشتنی tenant-bound هستند، از schemaهای Pydantic route بهره می‌برند و مجوز view/manage/operate/settle/approve_returns را رعایت می‌کنند؛ عملیات مالی/موجودی/مکان حساس نیازمند تأیید است | تطبیق runtime ابزارها با routeها و permissionها؛ بررسی routeهای PDF/خروجی، offline sync و endpointهای دارای فایل/تصویر قبل از تصمیم دربارهٔ قالب MCP جایگزین |
| اشخاص | شخص/مشتری/تأمین‌کننده، گروه، مانده، گردش حساب و برچسب | جستجو و بخش مهم CRUD موجود است | تفکیک APIهای عمومی و خصوصی، مانده و اطلاعات حساس؛ بررسی پوشش فیلدهای هر فرم |
| عملیات تخصصی کسب‌وکار | حقوق و دستمزد، پروژه، تعمیرگاه، گارانتی، توزیع، تولید/BOM، club، telephony، integrations | registry ترکیبی از پوشش‌ها دارد؛ صرف شمار ابزارها کفایت این حوزه‌ها را ثابت نمی‌کند | ممیزی جداگانه با فهرست endpoint و permission، سپس افزودن ابزارهای کاربرمحور بر اساس قابلیت و نه تعداد route |
| منابع و promptها | راهنمای اتصال و فهرست ابزار | پیش‌تر یک overview و سه prompt عمومی و ثابت | این تغییر یک منبع capabilities پویا و promptهای دامنه‌ای مبتنی بر ابزار واقعی اتصال اضافه کرده؛ باقی زبان‌های رابط/راهنمای اتصال باید همگام شود |

ماتریس بالا عمداً وضعیت «نیازمند بررسی» را از «قطعاً موجود» جدا می‌کند؛ برای نمونه، حضور ابزار عمومی query به معنی معادل‌بودن عملیات نوشتنی، workflow یا اثر جانبی API نیست.

## موجودی routeها در زمان ممیزی

۱۶۰۲ route صریح در ۱۴۱ ماژول پیدا شد. ماژول‌های عمدهٔ کاربرمحور عبارت‌اند از: CRM (۷۷)، توزیع (۹۲)، اسناد (۴۷)، فاکتور (۴۵)، حقوق (۴۳)، کالا (۳۹)، اشخاص (۲۸)، گردش‌کار (۱۸)، پروژه (۸)، دریافت/پرداخت (۹)، انبار (۷)، فضای کاری انبار (۱۹)، گزارش انبار (۲۰)، تولید (۱۳)، تعمیرگاه (۲۲)، باشگاه مشتری (۱۱)، گارانتی (۱۲)، قیمت‌گذاری (۸)، چک (۱۹)، حساب‌ها (۷)، بانک (۱۱)، و کیف پول (۱۴). این‌ها اولویت ممیزی کاربردی‌اند، نه تعهد تبدیل تک‌تک routeها به ابزار.

طبقه‌های خارج از دسترس مستقیم MCP کسب‌وکاری شامل احراز هویت/OTP، اپراتور و ادمین سراسری، health/monitoring، callback و webhook، APIهای public share/catalog، مدیریت زیرساخت و فایل‌های عمومی است. برخی قابلیت‌های کسب‌وکاری مانند مدیریت کاربر کسب‌وکار یا تنظیمات حساس نیازمند تصمیم permission و سطح افشای جداگانه‌اند و تا تعیین سیاست نباید از ابزار عمومی عبور داده شوند.

## برنامهٔ اجرا و معیار پذیرش

### فاز ۰ — تثبیت قرارداد و پوشش

- نگهداری inventory ماشینی API و registry، کلید یکتای capability و permission map.
- לכל ابزار ثبت‌شده: schema version، description، category/domain، read/write، side effect، approval، permissions، aliasها و companion tools.
- طبقه‌بندی endpointها: ابزار مستقیم، تجمیع در capability workflow، منبع read-only، internal/excluded با دلیل.
- معیار پذیرش: هیچ route کاربرمحور بدون وضعیت/دلیل و owner در inventory نماند.

### فاز ۱ — MCP discovery و راهنمای اتصال (در این تغییر آغاز شده)

- resource فهرست capabilityهای واقعاً مجاز به اتصال؛ بدون افشای ابزار انتخاب‌نشده یا permission کاربر دیگر.
- promptهای دامنه‌ای فقط در حضور دستهٔ متناظر؛ دستورهای محدودکننده برای tenant، استفاده از شناسهٔ واقعی، پرهیز از حدس و تأیید اثر جانبی.
- README معماری/اتصال و قراردادهای schema/version را با رفتار واقعی به‌روز نگه‌دار.
- پذیرش: `tools/list`، capabilities resource و prompts هم‌پوشان و مختص همان اتصال باشند.

### فاز ۲ — کامل‌کردن گردش‌کارهای پرتکرار

ترتیب: فاکتور و مالیات؛ انبار؛ CRM؛ کالا/اشخاص؛ دریافت‌وپرداخت/چک/هزینه؛ سپس گزارش و گردش‌کار. هر capability از service layer موجود استفاده می‌کند، tenant را از context می‌گیرد، permission متناظر را اعلام می‌کند، ورودی را با schema محدود می‌کند، خروجی را استاندارد می‌سازد و اثر/حالت رکورد را برمی‌گرداند. ابزار مالیاتی، ارسال بیرونی، حذف، لغو، ثبت قطعی و batch پرخطر نیازمند confirmation سطح tool/client و محدودیت batch هستند.

### فاز ۳ — پوشش حوزه‌های تخصصی

برای payroll، production/BOM، projects، repair shop، distribution، warranty، customer club، telephony، integrations و marketplace قرارداد جداگانه تهیه شود. قابلیت‌های admin/operator/public یا از ابزارهای کسب‌وکاری خارج بمانند یا با credential/consent و namespace مستقل عرضه شوند.

### فاز ۴ — استانداردسازی، مستندات و نگهداری

- schemaهای ورودی/خروجی versioned؛ enum و required واقعی؛ توضیح قالب تاریخ، ارز، واحد و pagination؛ خطاهای قابل‌اقدام و محدودیت تعداد.
- metadata سازگار با MCP برای read-only/destructive/idempotent/open-world؛ cache فقط برای داده‌های read-only و کلیددار براساس tenant و مجوز.
- کاتالوگ و promptهای فارسی/انگلیسی؛ مثال‌های اتصال؛ راهنمای انتخاب permission؛ نسخهٔ MCP؛ خطایابی و راهنمای revoke.
- فرآیند release: هر capability API در PR با تصمیم MCP ثبت شود و inventory/manifest همان تغییر اصلاح گردد.

## حاکمیت امنیتی ابزارها

- هر ابزار کسب‌وکاری باید tenant-bound، business-context-required و role/permission gated باشد. ورودی `business_id`، `user_id`، approval و scope از مدل قابل اعتماد نیست.
- permission نوشتن را با دسترسی API هم‌تراز کنید؛ owner بودن جایگزین permission عضو نیست. allowlist OAuth صرفاً فیلتر مضاعف است و permission جاری را توسعه نمی‌دهد.
- برای عملیات برگشت‌ناپذیر/بیرونی، اثر دقیق و مقصد را قبل از اجرا نمایش دهید. صرف ظاهرشدن ابزار یا scope عمومی، جایگزین consent روشن برای عملیات حساس نشود.
- خروجی نباید token، secret، اطلاعات tenant دیگر یا دادهٔ خارج از permission را برگرداند. pagination و batch باید محدود باشند.
- ابزار پیچیدهٔ generic که امکان اجرای arbitrary endpoint، SQL، query بدون allowlist یا عبور از workflow را می‌دهد قابل قبول نیست.

## تغییر اجراشده در این مرحله

- `hesabix://mcp/capabilities` به منابع MCP افزوده شد. محتوای آن در زمان read از ابزارهای قابل مشاهدهٔ همین context ساخته می‌شود و نام، شرح، دسته، capability، نوع اثر و permission لازم را می‌دهد.
- promptهای CRM، فروش، موجودی، مطالبات/بدهی، آماده‌سازی فاکتور و حواله به catalog وابسته شدند. prompt دامنه‌ای وقتی ابزار دستهٔ آن برای اتصال موجود نیست ارائه نمی‌شود.
- متن prompt به tenant متصل، مجوز جاری، استفاده از ابزارهای واقعی، عدم جعل شناسه و پرهیز از write بدون درخواست صریح اشاره می‌کند.
- پیش از اجرای handlerهای MCP، required/type/enum/ساختار object و array و محدودیت‌های پایهٔ JSON Schema بررسی می‌شود.
- در لایهٔ MCP، `user_id` ورودی حذف و فقط از هویت احراز‌شده تزریق می‌شود؛ `business_id` نیز پیش از بررسی schema به tenant اتصال pin می‌شود.
- به چرخهٔ حوالهٔ انبار، ویرایش، قطعی‌سازی، حذف draft و لغو posted اضافه شد. هر چهار عملیات از `warehouse_service` استفاده می‌کنند، tenant سند را پیش‌بررسی می‌کنند و write permission دارند؛ ثبت قطعی و حذف/لغو high risk هستند.
- ابزار پیش‌بررسی وابستگی کالا و حذف کالا اضافه شد؛ هر دو از product service استفاده می‌کنند، حذف permission جداگانهٔ `products.delete` دارد و سرویس آن را به tenant و وابستگی‌های کالا محدود می‌کند.
- شانزده ابزار مالیاتی برای کارپوشه، ارسال، ارسال اصلاحی، ابطال، وضعیت، اعتبارسنجی، استعلام، تایم‌لاین، صف خطا، اعتبارسنجی گروهی و مرجع‌ها افزوده شد؛ عملیات بیرونی high risk و نیازمند تأیید هستند و استعلام فقط شناسهٔ فاکتورهای متعلق به tenant را می‌پذیرد.
- ابزارهای چرخهٔ CRM شامل به‌روزرسانی/حذف/تبدیل سرنخ، ایجاد/ویرایش/حذف فرصت و فعالیت، جایگزینی خطوط فرصت و تبدیل آن به فاکتور افزوده شد. ابزارهای خط و فاکتور از سرویس‌های دامنه استفاده می‌کنند؛ تبدیل فرصت را قفل و از صدور تکراری جلوگیری می‌کند. تبدیل سرنخ و ساخت شخص/فرصت در یک تراکنش انجام می‌شود.
- اعتبارسنج JSON Schema در MCP برای `exclusiveMinimum` و `exclusiveMaximum` نیز اعمال می‌شود؛ شش ابزار CRUD و ثبت‌نام توالی‌های CRM، به‌علاوهٔ خواندن/ویرایش تنظیمات automation افزوده شد؛ پیکربندی گام‌ها allowlist شده، تعداد گام محدود است و تغییراتی مانند SMS نیازمند تأیید هستند. شناسه‌های auto-assign به عضویت فعال کسب‌وکار محدودند. این مرحله ۴۸ ابزار CRM، ۱۳ ابزار فاکتور و ۱۲ ابزار چک و ۳ ابزار انبارگردانی برای یادداشت و metadata، فرایند و مرحله، تاریخچه و نمای شخص، گزارش‌های پایپلاین/سرنخ/منبع/پیش‌بینی/روند/کارمند/دلایل برد و باخت اضافه کرد. شمارش static AST برابر ۲۹۷ نام یکتا و ۲۹۷ مدخل manifest است؛ این بررسی جایگزین اجرای integration در محیط برنامه نیست. برای چک ۱۲ ابزار گردش lifecycle، تاریخچه و راس‌گیری اضافه شد؛ actionها high risk و نیازمند مجوز accounting.write و تأیید هستند. برای فاکتور ابزارهای اقساط، محاسبه مانده حداکثر ۱۰۰ شناسه، tag، پیش‌نمایش اثر حذف، upsert گروهی حداکثر ۲۵ مورد، حذف گروهی حداکثر ۱۰۰ مورد و share link اضافه شدند؛ ایجاد/لغو لینک و تغییر پرداخت آنلاین high risk و نیازمند تأیید است.
- گام بعد، بررسی endpointهای جانبی CRM و سپس به‌صورت route-to-tool تطبیقی انبار، مالی و ماژول‌های تخصصی است. پیش از عرضهٔ هر capability باید مسیر service، permission و side effect آن تطبیق داده شود.

## پیوست — شمار route به تفکیک ماژول

فهرست فشردهٔ routeهای صریح API (تعداد route، نه تعداد قابلیت):

```text
accounts 7; activity_logs 4; activity_logs_admin 5; ai_eval 12; ai_models 6; ai_plans 5; ai_prompts 5; ai_provider_credentials 4; ai_settings 4; ai_skills 4; ai_tickets 2; ai_voice_models 9; announcements 9; attachments_operator 7; attachments_user 3; auth 34; bale 4; bank_accounts 11; barcode_labels 15; basalam_integration 23; billing 8; boms 7; business_backups 5; business_currency_rates 7; business_dashboard 15; business_data_table_settings 3; business_frequent_descriptions 4; business_ftp_backup 5; business_fx_auto_sync 5; business_fx_global_rates 2; business_notifications 10; business_provider 4; business_users 8; businesses 23; businesses_admin 3; cash_registers 11; catalog_spec_fields 6; categories 7; chat 46; checks 19; credit 9; crm 77; crm_ai 4; crm_chat 14; crm_chat_public 8; currencies 7; customer_club 11; customers 4; distribution 92; document_code_reservations 2; document_monetization 22; document_numbering 4; documents 47; email_config 9; expense_income 10; file_storage 13; firewall 13; fiscal_years 11; fx_providers 7; goods_expense_income 11; health 3; hscript_admin 1; hscript_reports 29; invoices 45; jobs 5; kardex 3; legacy_import 2; marketplace 16; mcp 4; models 1; monitoring 13; notification_event_types 4; notification_moderation 8; notification_templates 6; notifications 4; opening_balance 7; operator 17; payment_callbacks 9; payment_gateways 6; payroll 43; period_end_fx_revaluation 2; person_group_routes 5; persons 28; petty_cash 8; ping_pong 4; price_lists 8; priorities 1; product_attributes 5; product_bundles 6; product_instances 9; production_orders 13; products 39; profile_dashboard 6; projects 8; prompts 4; public_product_catalog 6; public_share_links 9; public_storage_file_shares 4; query_schema 2; quick_sales 19; receipts_payments 9; received_loan_facilities 8; repair_shop 22; report_list_exports 2; report_templates 26; scripts 5; statuses 1; storage 25; storage_plans 5; subscription 8; support_billing 8; system_services 6; system_settings 22; tax_product_codes 2; tax_providers 3; tax_reports 1; tax_settings 14; tax_types 1; tax_units 1; telegram 4; telephony 47; tickets 10; transfers 8; usage 7; users 15; users_permissions 5; voice_feedback 1; voice_http 5; wallet 14; wallet_admin 7; wallet_webhook 1; warehouse_docs 19; warehouse_locations 9; warehouse_reports 20; warehouses 7; warranty 12; workflow_marketplace 8; workflows 18; zohal 12
```
