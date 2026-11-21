<?php
/**
 * Seed sample help tree + optional Woo product.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_Seed
 */
class Hhelp_Seed {

	const META_FLAG = '_hhelp_seed';

	/**
	 * @param bool $force Delete previous seed posts first.
	 */
	public static function run( $force = false ) {
		if ( $force ) {
			self::delete_seeded();
		}

		$existing = get_posts(
			array(
				'post_type'      => HHELP_CPT,
				'posts_per_page' => 1,
				'post_status'    => 'any',
				'meta_key'       => self::META_FLAG,
				'meta_value'     => '1',
				'fields'         => 'ids',
			)
		);
		if ( ! empty( $existing ) && ! $force ) {
			return;
		}

		$product_id = self::ensure_sample_product();

		$start = self::insert(
			array(
				'title'   => 'شروع کار',
				'content' => self::section_intro( 'اولین قدم‌ها برای ثبت‌نام، راه‌اندازی و آشنایی با محیط حسابیکس آرک.' ),
				'excerpt' => 'ثبت‌نام، مرورگر و راه‌اندازی اولیه',
				'order'   => 1,
				'icon'    => 'start',
				'featured'=> true,
				'access'  => 'free',
			)
		);

		self::insert(
			array(
				'title'   => 'مرورگر و سیستم مورد نیاز',
				'parent'  => $start,
				'order'   => 1,
				'access'  => 'free',
				'featured'=> true,
				'content' => <<<'HTML'
<p>برای بهترین تجربه در حسابیکس آرک، همیشه از آخرین نسخهٔ مرورگر خود استفاده کنید. حسابیکس روی مرورگرهای مدرن به‌خوبی اجرا می‌شود.</p>
<h2>مرورگرهای پیشنهادی</h2>
<ul>
<li>گوگل کروم (Google Chrome)</li>
<li>مایکروسافت اج (Microsoft Edge)</li>
<li>موزیلا فایرفاکس (Mozilla Firefox)</li>
<li>سافاری ۸ و بالاتر</li>
</ul>
<h2>نکته مهم</h2>
<blockquote>سیستم‌عامل‌های قدیمی و بدون به‌روزرسانی ممکن است عملکرد کند یا ناسازگار داشته باشند. برای سرعت و امنیت، از آخرین نسخهٔ ویندوز، macOS یا توزیع لینوکس به‌روز استفاده کنید.</blockquote>
<h2>اتصال اینترنت</h2>
<p>حسابیکس یک نرم‌افزار ابری است؛ اتصال پایدار اینترنت برای همگام‌سازی فاکتور، انبار و گزارش‌ها ضروری است.</p>
HTML
,
			)
		);

		self::insert(
			array(
				'title'   => 'ثبت‌نام و فعال‌سازی',
				'parent'  => $start,
				'order'   => 2,
				'access'  => 'free',
				'content' => <<<'HTML'
<p>در چند دقیقه می‌توانید پنل آرک را بسازید و بدون نیاز به کارت بانکی شروع کنید.</p>
<h2>مراحل ثبت‌نام</h2>
<ol>
<li>به صفحه شروع رایگان آرک بروید.</li>
<li>شماره موبایل یا ایمیل خود را وارد کنید.</li>
<li>کد تأیید را دریافت و وارد کنید.</li>
<li>نام کسب‌وکار و اطلاعات پایه را تکمیل کنید.</li>
</ol>
<h2>ورود به پورتال سایت</h2>
<p>برای دسترسی به انجمن، فروشگاه و مطالب آموزشی ویژه، از <strong>پورتال مشتریان</strong> حسابیکس وارد شوید.</p>
HTML
,
			)
		);

		$invoice = self::insert(
			array(
				'title'   => 'فاکتور و فروش',
				'content' => self::section_intro( 'صدور فاکتور، تخفیف، سطوح قیمت و مدیریت فروش در آرک.' ),
				'excerpt' => 'فاکتور فروش، تخفیف و قیمت‌گذاری',
				'order'   => 2,
				'icon'    => 'invoice',
				'featured'=> true,
				'access'  => 'free',
			)
		);

		self::insert(
			array(
				'title'   => 'صدور فاکتور فروش',
				'parent'  => $invoice,
				'order'   => 1,
				'access'  => 'free',
				'content' => <<<'HTML'
<p>فاکتور فروش قلب عملیات روزانه در حسابیکس است. در این راهنما مسیر ایجاد یک فاکتور ساده را می‌بینید.</p>
<h2>ایجاد فاکتور جدید</h2>
<ol>
<li>از منوی فروش، گزینه فاکتور جدید را انتخاب کنید.</li>
<li>مشتری را از فهرست اشخاص برگزینید یا سریع بسازید.</li>
<li>کالا یا خدمت را اضافه و تعداد را مشخص کنید.</li>
<li>مالیات، تخفیف و روش پرداخت را تنظیم کنید.</li>
<li>ثبت را بزنید تا سند حسابداری خودکار صادر شود.</li>
</ol>
<h2>چاپ و ارسال</h2>
<p>پس از ثبت می‌توانید فاکتور را چاپ کنید، PDF بگیرید یا برای مشتری ارسال کنید.</p>
HTML
,
			)
		);

		$paid_lesson = self::insert(
			array(
				'title'      => 'سطوح قیمت و تخفیف پیشرفته',
				'parent'     => $invoice,
				'order'      => 2,
				'access'     => 'paid',
				'product_id' => $product_id,
				'excerpt'    => 'مدیریت چند سطح قیمت، تخفیف پله‌ای و سیاست‌های فروش — نسخه آموزشی کامل.',
				'content'    => <<<'HTML'
<p>در این آموزش ویدئویی و متنی، سطوح مختلف قیمت فروش، تخصیص به مشتری و تخفیف‌های پیشرفته را قدم‌به‌قدم پیاده می‌کنید.</p>
<h2>تعریف سطح قیمت</h2>
<p>برای هر کالا می‌توانید قیمت عمده، همکار و مصرف‌کننده تعریف کنید و به‌صورت خودکار در فاکتور اعمال شود.</p>
<h2>تخفیف پله‌ای</h2>
<p>با قواعد تعداد، مبلغ فاکتور یا گروه مشتری، تخفیف را بدون دخالت دستی اعمال کنید.</p>
<h2>گزارش اثر تخفیف</h2>
<p>ببینید هر سیاست تخفیف چه تأثیری روی حاشیه سود داشته است.</p>
HTML
,
			)
		);

		if ( $product_id && $paid_lesson ) {
			update_post_meta( $product_id, Hhelp_Access::PRODUCT_GRANTS, (string) $paid_lesson );
		}

		$inv = self::insert(
			array(
				'title'   => 'انبار و موجودی',
				'content' => self::section_intro( 'تعریف انبار، حواله، انتقال و انبارگردانی.' ),
				'excerpt' => 'موجودی، حواله و انبارگردانی',
				'order'   => 3,
				'icon'    => 'inventory',
				'featured'=> true,
				'access'  => 'free',
			)
		);

		self::insert(
			array(
				'title'   => 'تعریف انبار و کالا',
				'parent'  => $inv,
				'order'   => 1,
				'access'  => 'free',
				'content' => <<<'HTML'
<p>قبل از فروش، کالا و انبار را درست تعریف کنید تا موجودی و گزارش‌ها دقیق بمانند.</p>
<h2>ساخت انبار</h2>
<p>نام، شعبه و مسئول انبار را مشخص کنید. می‌توانید چند انبار موازی داشته باشید.</p>
<h2>تعریف کالا</h2>
<ul>
<li>کد و بارکد</li>
<li>واحد شمارش</li>
<li>نقطه سفارش</li>
<li>انبار پیش‌فرض</li>
</ul>
HTML
,
			)
		);

		self::insert(
			array(
				'title'   => 'حواله و انتقال بین انبارها',
				'parent'  => $inv,
				'order'   => 2,
				'access'  => 'members',
				'excerpt' => 'ویژه اعضای پورتال — صدور حواله خروج و انتقال موجودی بین انبارها.',
				'content' => <<<'HTML'
<p>این بخش برای کاربران واردشده به پورتال مشتریان آزاد است.</p>
<h2>حواله خروج</h2>
<p>کالا را از انبار کسر و به مقصد مشخص ثبت کنید.</p>
<h2>انتقال بین انبارها</h2>
<p>با یک سند، موجودی از انبار مبدأ به مقصد منتقل می‌شود و اسناد حسابداری متناظر ساخته می‌شوند.</p>
HTML
,
			)
		);

		$crm = self::insert(
			array(
				'title'   => 'اشخاص و CRM',
				'content' => self::section_intro( 'طرف‌حساب‌ها، مشتریان و پیگیری ارتباط.' ),
				'excerpt' => 'اشخاص، مشتریان و ارتباط',
				'order'   => 4,
				'icon'    => 'crm',
				'access'  => 'free',
			)
		);

		self::insert(
			array(
				'title'   => 'تعریف طرف‌حساب',
				'parent'  => $crm,
				'order'   => 1,
				'access'  => 'free',
				'content' => <<<'HTML'
<p>هر مشتری، تأمین‌کننده یا سهامدار یک شخص در حسابیکس است.</p>
<h2>اطلاعات پایه</h2>
<p>نام، کد اقتصادی، موبایل و نشانی را وارد کنید تا فاکتور و سامانه مودیان کامل باشد.</p>
HTML
,
			)
		);

		Hhelp_Tree::flush_cache();
	}

	/**
	 * @param string $text Intro text.
	 * @return string
	 */
	private static function section_intro( $text ) {
		return '<p>' . esc_html( $text ) . '</p><p>' . esc_html__( 'از فهرست زیر یک موضوع را انتخاب کنید یا از سایدبار درخت راهنما پیش بروید.', 'hesabix-help' ) . '</p>';
	}

	/**
	 * @param array<string, mixed> $args Args.
	 * @return int
	 */
	private static function insert( $args ) {
		$id = wp_insert_post(
			array(
				'post_type'    => HHELP_CPT,
				'post_status'  => 'publish',
				'post_title'   => $args['title'],
				'post_content' => $args['content'] ?? '',
				'post_excerpt' => $args['excerpt'] ?? '',
				'post_parent'  => isset( $args['parent'] ) ? (int) $args['parent'] : 0,
				'menu_order'   => isset( $args['order'] ) ? (int) $args['order'] : 0,
			),
			true
		);

		if ( is_wp_error( $id ) || ! $id ) {
			return 0;
		}

		update_post_meta( $id, self::META_FLAG, '1' );
		update_post_meta( $id, '_hhelp_access', $args['access'] ?? 'free' );
		if ( ! empty( $args['icon'] ) ) {
			update_post_meta( $id, '_hhelp_icon', sanitize_key( $args['icon'] ) );
		}
		if ( ! empty( $args['featured'] ) ) {
			update_post_meta( $id, '_hhelp_featured', 1 );
		}
		if ( ! empty( $args['product_id'] ) ) {
			update_post_meta( $id, '_hhelp_product_id', (int) $args['product_id'] );
		}
		update_post_meta( $id, '_hhelp_video_type', 'none' );

		return (int) $id;
	}

	/**
	 * @return int Product ID or 0.
	 */
	private static function ensure_sample_product() {
		if ( ! class_exists( 'WooCommerce' ) ) {
			return 0;
		}

		$existing = get_posts(
			array(
				'post_type'      => 'product',
				'posts_per_page' => 1,
				'post_status'    => 'any',
				'meta_key'       => '_hhelp_seed_product',
				'meta_value'     => '1',
				'fields'         => 'ids',
			)
		);
		if ( ! empty( $existing ) ) {
			return (int) $existing[0];
		}

		$product = new WC_Product_Simple();
		$product->set_name( 'آموزش سطوح قیمت و تخفیف — حسابیکس' );
		$product->set_status( 'publish' );
		$product->set_catalog_visibility( 'visible' );
		$product->set_description( 'دسترسی کامل به آموزش پولی «سطوح قیمت و تخفیف پیشرفته» در راهنمای جامع حسابیکس.' );
		$product->set_short_description( 'خرید فوری و دسترسی آنی به آموزش.' );
		$product->set_regular_price( '149000' );
		$product->set_virtual( true );
		$product->set_sold_individually( true );
		$product_id = $product->save();

		if ( $product_id ) {
			update_post_meta( $product_id, '_hhelp_seed_product', '1' );
		}

		return (int) $product_id;
	}

	/**
	 * Delete seeded help posts.
	 */
	private static function delete_seeded() {
		$ids = get_posts(
			array(
				'post_type'      => HHELP_CPT,
				'posts_per_page' => -1,
				'post_status'    => 'any',
				'meta_key'       => self::META_FLAG,
				'meta_value'     => '1',
				'fields'         => 'ids',
			)
		);
		foreach ( $ids as $id ) {
			wp_delete_post( (int) $id, true );
		}
		Hhelp_Tree::flush_cache();
	}
}
