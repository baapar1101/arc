<?php
/**
 * Template Name: اتصال ChatGPT به حسابیکس
 * Description: صفحهٔ راهنمای اتصال حسابیکس به ChatGPT از طریق MCP.
 * @package Hesabix2
 */

defined('ABSPATH') || exit;

$hx_chatgpt_theme_dir = get_template_directory();
$hx_chatgpt_theme_uri = get_template_directory_uri();
$hx_chatgpt_css       = $hx_chatgpt_theme_dir . '/assets/css/chatgpt-connector.css';
$hx_chatgpt_js        = $hx_chatgpt_theme_dir . '/assets/js/chatgpt-connector.js';

if (is_readable($hx_chatgpt_css)) {
    wp_enqueue_style('hesabix2-chatgpt-connector', $hx_chatgpt_theme_uri . '/assets/css/chatgpt-connector.css', array(), (string) filemtime($hx_chatgpt_css));
}
if (is_readable($hx_chatgpt_js)) {
    wp_enqueue_script('hesabix2-chatgpt-connector', $hx_chatgpt_theme_uri . '/assets/js/chatgpt-connector.js', array(), (string) filemtime($hx_chatgpt_js), true);
}

add_action('wp_head', static function () {
    if (is_page_template('page-chatgpt-hesabix.php')) {
        echo '<meta name="description" content="' . esc_attr('حسابیکس را به ChatGPT وصل کنید؛ گزارش بگیرید، داده‌های مالی و کسب‌وکار را بررسی کنید و عملیات پشتیبانی‌شده را با مجوزهای حساب خود انجام دهید.') . '">' . "\n";
    }
}, 2);

$hx_chatgpt_mcp_url = 'https://arc.hesabix.ir/api/v1/ai/mcp';
$hx_chatgpt_zip_url = 'https://source.hesabix.ir/hesabix/arc/raw/branch/master/extraScripts/chatgptPlugin/plugin-1.0.0.zip';
$hx_chatgpt_source  = 'https://source.hesabix.ir/hesabix/arc/src/branch/master/extraScripts/chatgptPlugin';
$hx_chatgpt_openai  = 'https://developers.openai.com/plugins/deploy/connect-chatgpt';

get_header();
?>
<main id="main-content" class="hx-chatgpt">
    <section class="hx-chatgpt-hero">
        <div class="hx-chatgpt-wrap hx-chatgpt-hero__grid">
            <div class="hx-chatgpt-hero__copy">
                <p class="hx-chatgpt-eyebrow"><span class="hx-chatgpt-status-dot" aria-hidden="true"></span> اتصال حسابیکس به ChatGPT</p>
                <h1>از گفت‌وگو تا <span>کارهای حسابداری</span></h1>
                <p class="hx-chatgpt-hero__lead">حسابیکس را به ChatGPT وصل کنید؛ گزارش‌های کسب‌وکارتان را بپرسید، داده‌ها را بررسی کنید و کارهای پشتیبانی‌شده را در محدودهٔ دسترسی حساب خود انجام دهید.</p>
                <div class="hx-chatgpt-actions">
                    <a class="hx-chatgpt-button hx-chatgpt-button--light" href="#hx-chatgpt-connect">راهنمای اتصال <span aria-hidden="true">←</span></a>
                    <a class="hx-chatgpt-button hx-chatgpt-button--ghost" href="<?php echo esc_url($hx_chatgpt_source); ?>" target="_blank" rel="noopener noreferrer">مشاهدهٔ سورس افزونه</a>
                </div>
                <ul class="hx-chatgpt-proof" aria-label="ویژگی‌های اتصال">
                    <li>گزارش از داده‌های حسابیکس</li>
                    <li>دسترسی بر اساس نقش کاربر</li>
                    <li>تأیید جداگانه برای عملیات نوشتنی</li>
                </ul>
            </div>
            <div class="hx-chatgpt-hero__visual" aria-label="نمونهٔ پاسخ حسابیکس در گفت‌وگو" role="img">
                <div class="hx-chatgpt-orbit" aria-hidden="true"></div>
                <div class="hx-chatgpt-float hx-chatgpt-float--top">گزارش‌های زندهٔ کسب‌وکار</div>
                <div class="hx-chatgpt-chat-card">
                    <div class="hx-chatgpt-chat-card__head">
                        <span class="hx-chatgpt-chat-card__brand"><img src="<?php echo esc_url($hx_chatgpt_theme_uri . '/assets/brand/hesabix-mark.svg'); ?>" alt="" width="30" height="30"> حسابیکس در ChatGPT</span>
                        <span class="hx-chatgpt-connected"><i aria-hidden="true"></i> متصل</span>
                    </div>
                    <p class="hx-chatgpt-chat-card__caption">درخواست شما</p>
                    <div class="hx-chatgpt-bubble">فروش این ماه را با ماه قبل مقایسه کن و ماندهٔ مشتریان را خلاصه کن.</div>
                    <div class="hx-chatgpt-result">
                        <span class="hx-chatgpt-result__spark" aria-hidden="true">✦</span>
                        <div><strong>خلاصهٔ حسابیکس آماده است</strong><p>فروش دوره، تغییر نسبت به ماه قبل و فهرست مانده‌ها بر اساس دادهٔ حساب شما.</p></div>
                    </div>
                    <div class="hx-chatgpt-mini-grid"><div><small>فروش</small><b>گزارش دوره</b></div><div><small>مقایسه</small><b>تحلیل روند</b></div><div><small>اشخاص</small><b>مانده‌ها</b></div></div>
                    <div class="hx-chatgpt-input" aria-hidden="true">سؤال بعدی‌تان را بنویسید… <span>➤</span></div>
                </div>
                <div class="hx-chatgpt-float hx-chatgpt-float--bottom"><span aria-hidden="true">✓</span> مطابق مجوزهای شما</div>
            </div>
        </div>
    </section>

    <section class="hx-chatgpt-ribbon" aria-label="دسترسی‌های حسابیکس">
        <div class="hx-chatgpt-wrap hx-chatgpt-ribbon__inner"><strong>حسابیکس، در دسترس دستیار شما</strong><span>مالی و اسناد</span><span>فروش و مخاطبین</span><span>کالا و انبار</span><span>عملیات مجاز</span></div>
    </section>

    <section class="hx-chatgpt-section" id="hx-chatgpt-capabilities">
        <div class="hx-chatgpt-wrap">
            <header class="hx-chatgpt-section-head"><span>یک دستیار برای جریان واقعی کار</span><h2>از گزارش‌گیری تا انجام کارهای روزانه</h2><p>دستیار از ابزارهای MCP حسابیکس استفاده می‌کند تا درخواست‌های شما را به داده‌ها و کارهای واقعی کسب‌وکار وصل کند.</p></header>
            <div class="hx-chatgpt-feature-grid">
                <article class="hx-chatgpt-feature"><span class="hx-chatgpt-feature__icon" aria-hidden="true">▤</span><h3>گزارش و تحلیل مالی</h3><p>وضعیت فروش، هزینه‌ها، ماندهٔ اشخاص، اسناد و موجودی را بپرسید و خلاصهٔ روشن بگیرید.</p></article>
                <article class="hx-chatgpt-feature"><span class="hx-chatgpt-feature__icon" aria-hidden="true">↗</span><h3>پیگیری فروش و مطالبات</h3><p>فاکتورها و حساب مشتریان را مرور کنید و موارد نیازمند پیگیری را مشخص کنید.</p></article>
                <article class="hx-chatgpt-feature"><span class="hx-chatgpt-feature__icon" aria-hidden="true">◫</span><h3>مخاطبین، کالا و انبار</h3><p>اطلاعات مخاطبین، کالاها و گردش موجودی را در یک گفت‌وگوی ساده جست‌وجو کنید.</p></article>
                <article class="hx-chatgpt-feature"><span class="hx-chatgpt-feature__icon" aria-hidden="true">✎</span><h3>ثبت و ویرایش اطلاعات</h3><p>کارهای پشتیبانی‌شده را درخواست کنید؛ اجرا به فعال‌بودن ابزار و مجوز نوشتن نیاز دارد.</p></article>
                <article class="hx-chatgpt-feature"><span class="hx-chatgpt-feature__icon" aria-hidden="true">⌕</span><h3>پرسش به زبان خودتان</h3><p>درخواست را مثل همکار حسابدار مطرح کنید؛ لازم نیست نام دقیق منوها و گزارش‌ها را بدانید.</p></article>
                <article class="hx-chatgpt-feature"><span class="hx-chatgpt-feature__icon" aria-hidden="true">✓</span><h3>بازبینی پیش از اقدام</h3><p>خلاصه و جزئیات را بررسی کنید و سپس اقدام‌های حساس را در ChatGPT تأیید کنید.</p></article>
            </div>
        </div>
    </section>

    <section class="hx-chatgpt-section hx-chatgpt-section--tint" id="hx-chatgpt-connect">
        <div class="hx-chatgpt-wrap">
            <header class="hx-chatgpt-section-head"><span>شروع در چند دقیقه</span><h2>حسابیکس را به ChatGPT اضافه کنید</h2><p>برای اتصال به سرور عمومی MCP حسابیکس، در ChatGPT وب یک اتصال سفارشی بسازید.</p></header>
            <div class="hx-chatgpt-steps">
                <article class="hx-chatgpt-step"><span class="hx-chatgpt-step__number">۱</span><h3>ChatGPT را باز کنید</h3><p>در بخش Plugins، دکمهٔ افزودن را بزنید و <b>Add custom MCP server</b> را انتخاب کنید.</p></article>
                <article class="hx-chatgpt-step"><span class="hx-chatgpt-step__number">۲</span><h3>نشانی سرور را وارد کنید</h3><p>این نشانی HTTPS را در فیلد Server URL قرار دهید:</p><div class="hx-chatgpt-url"><code dir="ltr"><?php echo esc_html($hx_chatgpt_mcp_url); ?></code><button type="button" class="hx-chatgpt-copy" data-copy="<?php echo esc_attr($hx_chatgpt_mcp_url); ?>">کپی</button></div><span class="hx-chatgpt-copy-status" aria-live="polite"></span></article>
                <article class="hx-chatgpt-step"><span class="hx-chatgpt-step__number">۳</span><h3>ورود و مجوزها را بررسی کنید</h3><p>روش احراز هویت را دنبال کنید، کسب‌وکار موردنظر و دامنهٔ دسترسی را انتخاب کنید و مجوزها را بخوانید.</p></article>
                <article class="hx-chatgpt-step"><span class="hx-chatgpt-step__number">۴</span><h3>اتصال را بسازید و امتحان کنید</h3><p>پس از ساخت اتصال، ابزارهای شناسایی‌شده را مرور کنید و با یک درخواست گزارش ساده شروع کنید.</p></article>
            </div>
            <div class="hx-chatgpt-setup-note"><strong>برای آزمایش سریع:</strong> <a href="https://chatgpt.com/" target="_blank" rel="noopener noreferrer">ورود به ChatGPT وب</a> · <a href="<?php echo esc_url($hx_chatgpt_openai); ?>" target="_blank" rel="noopener noreferrer">راهنمای رسمی اتصال OpenAI</a><br><small>نمای منو و امکان افزودن سرور سفارشی به نوع اشتراک و سیاست‌های فضای کاری شما بستگی دارد.</small></div>
        </div>
    </section>

    <section class="hx-chatgpt-section" id="hx-chatgpt-security">
        <div class="hx-chatgpt-wrap hx-chatgpt-security-grid">
            <div class="hx-chatgpt-security-copy"><span class="hx-chatgpt-section-kicker">دسترسی روشن، کنترل دست شما</span><h2>هر کاربر در محدودهٔ مجوز خودش</h2><p>حسابیکس ابزارهای در دسترس را به کاربر و کسب‌وکار متصل‌شده محدود می‌کند. برای داده‌های مالی حساس، مجوزهای اتصال را با دقت انتخاب کنید.</p>
                <ul class="hx-chatgpt-checks"><li>اتصال خواندنی به‌صورت پیش‌فرض ارائه می‌شود.</li><li>ایجاد یا تغییر سوابق به مجوز نوشتن جداگانه نیاز دارد.</li><li>ابزارهای موجود با نقش شما در حسابیکس و کسب‌وکار انتخاب‌شده محدود می‌شوند.</li><li>قبل از تأیید تغییرات مالی، جزئیات و نتیجه را بررسی کنید.</li></ul>
                <div class="hx-chatgpt-policy-links"><a href="https://hesabix.ir/privacy/">سیاست حریم خصوصی حسابیکس</a><a href="https://hesabix.ir/terms/">قوانین استفاده</a></div>
            </div>
            <aside class="hx-chatgpt-security-card"><span class="hx-chatgpt-security-card__icon" aria-hidden="true">⌑</span><h3>پیش از اتصال این موارد را بدانید</h3><p>ChatGPT درخواست‌های شما را به سرویس حسابیکس می‌فرستد. داده‌هایی که در هر درخواست استفاده می‌شوند به ابزار فراخوانی‌شده و مجوز اتصال بستگی دارند.</p><ul><li>رمز حسابیکس یا اطلاعات ورود را در متن گفت‌وگو وارد نکنید.</li><li>از حساب کاربری با نقش متناسب استفاده کنید.</li><li>سیاست‌های حریم خصوصی ChatGPT را نیز مرور کنید.</li></ul></aside>
        </div>
    </section>

    <section class="hx-chatgpt-section hx-chatgpt-section--tint" id="hx-chatgpt-download">
        <div class="hx-chatgpt-wrap hx-chatgpt-download-panel">
            <div><span class="hx-chatgpt-section-kicker">برای توسعه‌دهندگان</span><h2>سورس و بستهٔ افزونهٔ Hesabix</h2><p>ساختار و فایل‌های نسخهٔ فعلی را در مخزن حسابیکس ببینید. برای استفادهٔ روزمره، اتصال MCP بالا مسیر پیشنهادی است و ZIP فعلی بستهٔ توسعه/آزمایش محسوب می‌شود.</p><small>توسعه‌دهنده: TFS company LTD · پشتیبانی: <a href="mailto:support@hesabix.ir">support@hesabix.ir</a></small></div>
            <div class="hx-chatgpt-download-actions"><a class="hx-chatgpt-button hx-chatgpt-button--primary" href="<?php echo esc_url($hx_chatgpt_zip_url); ?>">دریافت فایل ZIP نسخهٔ آزمایشی <span aria-hidden="true">↓</span></a><a class="hx-chatgpt-button hx-chatgpt-button--outline" href="<?php echo esc_url($hx_chatgpt_source); ?>" target="_blank" rel="noopener noreferrer">باز کردن مخزن سورس</a></div>
        </div>
    </section>

    <section class="hx-chatgpt-section" id="hx-chatgpt-faq">
        <div class="hx-chatgpt-wrap"><header class="hx-chatgpt-section-head"><span>پرسش‌های پرتکرار</span><h2>پیش از شروع</h2></header>
            <div class="hx-chatgpt-faq">
                <details><summary>آیا دستیار فقط گزارش می‌گیرد؟</summary><p>خیر. در کنار خواندن و گزارش‌گیری، ابزارهای پشتیبانی‌شده ممکن است ثبت یا ویرایش را هم انجام دهند؛ این کارها به دسترسی نوشتن جداگانه و مجوز شما نیاز دارند.</p></details>
                <details><summary>آیا همهٔ ابزارها در هر حساب در دسترس هستند؟</summary><p>ابزارها به کسب‌وکار متصل‌شده، نقش کاربر، مجوزها و تنظیمات حساب محدود هستند. اگر عملیاتی در دسترس نبود، نقش کاربر و اتصال را در حسابیکس بررسی کنید.</p></details>
                <details><summary>برای اتصال حتماً باید ZIP را نصب کنم؟</summary><p>برای اتصال MCP سفارشی، نشانی سرور را در ChatGPT وارد کنید؛ فایل ZIP برای توسعه و آزمایش است و جایگزین ساخت اتصال و احراز هویت حساب شما نیست.</p></details>
                <details><summary>از کجا پشتیبانی بگیرم؟</summary><p>سؤال خود را به <a href="mailto:support@hesabix.ir">support@hesabix.ir</a> بفرستید.</p></details>
            </div>
        </div>
    </section>

    <section class="hx-chatgpt-final"><div class="hx-chatgpt-wrap hx-chatgpt-final__inner"><div><h2>گفت‌وگو را به کار حسابداری وصل کنید</h2><p>با گزارش‌های خواندنی شروع کنید و دسترسی‌های لازم را با دقت انتخاب کنید.</p></div><a class="hx-chatgpt-button hx-chatgpt-button--light" href="#hx-chatgpt-connect">مشاهدهٔ مراحل اتصال <span aria-hidden="true">←</span></a></div></section>

    <div class="hx-chatgpt-attribution"><div class="hx-chatgpt-wrap">Hesabix · محصول TFS company LTD · <a href="mailto:support@hesabix.ir">پشتیبانی</a> · <a href="https://hesabix.ir/brand/">دستورالعمل برند</a></div></div>
</main>
<?php get_footer(); ?>
