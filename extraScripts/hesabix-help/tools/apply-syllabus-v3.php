<?php
/**
 * Sync help CPT tree to syllabus v3. Does not overwrite existing post_content.
 *
 * wp eval-file tools/apply-syllabus-v3.php --allow-root
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

if ( ! defined( 'HHELP_CPT' ) ) {
	echo "HHELP_CPT missing\n";
	return;
}

function hhelp_syllabus_stub( $menu, $blurb ) {
	$menu  = esc_html( $menu );
	$blurb = esc_html( $blurb );
	return '<p>این درس در حال تکمیل است و به‌زودی با متن و ویدئوی منطبق با پنل آرک منتشر می‌شود.</p>'
		. '<p><strong>مسیر منو در آرک:</strong> ' . $menu . '</p>'
		. '<p>' . $blurb . '</p>';
}

function hhelp_syllabus_intro( $text ) {
	return '<p>' . esc_html( $text ) . '</p><p>از فهرست زیر درس‌ها را به‌ترتیب یادگیری بخوانید. مطالب علامت‌خورده به‌مرور تکمیل می‌شوند.</p>';
}

function hhelp_syllabus_upsert( $spec, $parent_id, $order ) {
	$id = isset( $spec['id'] ) ? (int) $spec['id'] : 0;
	if ( $id ) {
		$post = get_post( $id );
		if ( ! $post || HHELP_CPT !== $post->post_type ) {
			echo "MISSING_ID {$id} {$spec['title']}\n";
			return 0;
		}
		$update = array(
			'ID'          => $id,
			'post_parent' => $parent_id,
			'menu_order'  => $order,
		);
		if ( ! empty( $spec['rename'] ) ) {
			$update['post_title'] = $spec['title'];
		}
		if ( ! empty( $spec['excerpt'] ) && '' === trim( (string) $post->post_excerpt ) ) {
			$update['post_excerpt'] = $spec['excerpt'];
		}
		wp_update_post( $update );
	} else {
		$slug = $spec['slug'];
		$found = get_posts(
			array(
				'post_type'      => HHELP_CPT,
				'name'           => $slug,
				'post_status'    => 'any',
				'posts_per_page' => 1,
				'fields'         => 'ids',
			)
		);
		if ( $found ) {
			$id = (int) $found[0];
			wp_update_post(
				array(
					'ID'          => $id,
					'post_title'  => $spec['title'],
					'post_parent' => $parent_id,
					'menu_order'  => $order,
					'post_status' => 'publish',
				)
			);
		} else {
			$id = (int) wp_insert_post(
				array(
					'post_type'    => HHELP_CPT,
					'post_status'  => 'publish',
					'post_title'   => $spec['title'],
					'post_name'    => $slug,
					'post_content' => $spec['content'],
					'post_excerpt' => $spec['excerpt'] ?? '',
					'post_parent'  => $parent_id,
					'menu_order'   => $order,
				),
				true
			);
			if ( ! $id || is_wp_error( $id ) ) {
				echo "INSERT_FAIL {$slug}\n";
				return 0;
			}
			update_post_meta( $id, '_hhelp_stub', '1' );
			update_post_meta( $id, '_hhelp_video_type', 'none' );
		}
	}

	if ( ! empty( $spec['access'] ) ) {
		update_post_meta( $id, '_hhelp_access', $spec['access'] );
	}
	if ( ! empty( $spec['icon'] ) ) {
		update_post_meta( $id, '_hhelp_icon', sanitize_key( $spec['icon'] ) );
	}
	if ( ! empty( $spec['menu'] ) ) {
		update_post_meta( $id, '_hhelp_menu_key', sanitize_text_field( $spec['menu'] ) );
	}
	return $id;
}

$tree = array(
	array(
		'id'      => 759,
		'title'   => 'شروع و راه‌اندازی',
		'icon'    => 'start',
		'access'  => 'free',
		'menu'    => 'dashboard',
		'excerpt' => 'ثبت‌نام، ساخت کسب‌وکار و آشنایی با داشبورد آرک.',
		'children'=> array(
			array( 'id' => 761, 'title' => 'ثبت‌نام و ورود به حسابیکس', 'access' => 'free', 'menu' => 'auth' ),
			array( 'id' => 763, 'title' => 'ساخت اولین کسب‌وکار', 'access' => 'free', 'menu' => 'onboarding' ),
			array( 'id' => 765, 'title' => 'آشنایی با داشبورد و منوی کناری', 'access' => 'free', 'menu' => 'dashboard' ),
			array(
				'slug'    => 'help-switch-business',
				'title'   => 'کسب‌وکارهای من و سوییچ پنل',
				'access'  => 'free',
				'menu'    => 'profile',
				'excerpt' => 'جابه‌جایی بین کسب‌وکارها و ورود به پنل آرک.',
				'content' => hhelp_syllabus_stub( 'پروفایل ← کسب‌وکارهای من', 'بعد از ساخت کسب‌وکار، ورود به پنل و سوییچ بین چند کسب‌وکار از این مسیر است.' ),
			),
		),
	),
	array(
		'slug'    => 'help-chapter-settings',
		'title'   => 'تنظیمات کسب‌وکار',
		'icon'    => 'start',
		'access'  => 'free',
		'menu'    => 'settings',
		'excerpt' => 'اطلاعات کسب‌وکار، سال مالی، ارز، چاپ، کاربران و بازار افزونه‌ها.',
		'content' => hhelp_syllabus_intro( 'قبل از صدور فاکتور، تنظیمات کسب‌وکار و دسترسی کاربران را یک‌بار درست کنید. بسیاری از منوها فقط بعد از نصب افزونه دیده می‌شوند.' ),
		'children'=> array(
			array( 'id' => 767, 'title' => 'تنظیمات اولیه کسب‌وکار', 'access' => 'free', 'menu' => 'settings' ),
			array(
				'slug'    => 'help-currencies',
				'title'   => 'ارز و چندارزی',
				'access'  => 'members',
				'menu'    => 'settings/currencies',
				'excerpt' => 'تعریف ارز، نرخ و کسب‌وکار چندارزی در تنظیمات آرک.',
				'content' => hhelp_syllabus_stub( 'تنظیمات ← ارزها', 'برای فروش ارزی و تسعیر، ارز پایه و ارزهای فرعی از این صفحه تعریف می‌شوند.' ),
			),
			array(
				'slug'    => 'help-document-numbering',
				'title'   => 'شماره‌گذاری اسناد',
				'access'  => 'members',
				'menu'    => 'settings/document-numbering',
				'excerpt' => 'الگوی شماره فاکتور، سند و سایر مدارک.',
				'content' => hhelp_syllabus_stub( 'تنظیمات ← شماره‌گذاری اسناد', 'شماره فاکتور و سند حسابداری از این تنظیم کنترل می‌شود.' ),
			),
			array(
				'slug'    => 'help-print-templates',
				'title'   => 'چاپ اسناد و قالب‌ها',
				'access'  => 'members',
				'menu'    => 'report-templates',
				'excerpt' => 'چاپ فاکتور و استودیو قالب اسناد.',
				'content' => hhelp_syllabus_stub( 'تنظیمات ← چاپ اسناد · منو ← قالب‌ها', 'چاپ پیش‌فرض و قالب سفارشی فاکتور از این دو مسیر تنظیم می‌شود.' ),
			),
			array( 'id' => 769, 'title' => 'کاربران و سطوح دسترسی', 'access' => 'members', 'menu' => 'settings/users' ),
			array( 'id' => 855, 'title' => 'بازار افزونه‌ها و لایسنس', 'access' => 'free', 'menu' => 'plugin-marketplace', 'rename' => true ),
		),
	),
	array(
		'id'      => 771,
		'title'   => 'اشخاص',
		'icon'    => 'crm',
		'access'  => 'free',
		'menu'    => 'persons',
		'children'=> array(
			array( 'id' => 773, 'title' => 'تعریف طرف‌حساب (مشتری/تأمین‌کننده)', 'access' => 'free', 'menu' => 'persons' ),
			array( 'id' => 775, 'title' => 'گروه‌بندی اشخاص', 'access' => 'members', 'menu' => 'persons' ),
			array( 'id' => 777, 'title' => 'مانده و گردش حساب شخص', 'access' => 'members', 'menu' => 'persons' ),
		),
	),
	array(
		'id'      => 779,
		'title'   => 'کالا و خدمات',
		'icon'    => 'inventory',
		'access'  => 'free',
		'menu'    => 'group:products',
		'children'=> array(
			array( 'id' => 781, 'title' => 'تعریف کالا یا خدمت', 'access' => 'free', 'menu' => 'products' ),
			array( 'id' => 783, 'title' => 'دسته‌بندی کالاها', 'access' => 'free', 'menu' => 'categories' ),
			array(
				'slug'    => 'help-product-bundles',
				'title'   => 'بسته‌های کالا',
				'access'  => 'members',
				'menu'    => 'product-bundles',
				'excerpt' => 'تعریف بسته کالا از چند قلم در آرک.',
				'content' => hhelp_syllabus_stub( 'کالا و خدمات ← بسته‌های کالا', 'بسته، چند کالا را به‌صورت یک قلم قابل فروش کنار هم می‌گذارد.' ),
			),
			array(
				'slug'    => 'help-product-attributes',
				'title'   => 'ویژگی‌ها و مشخصات کاتالوگ',
				'access'  => 'members',
				'menu'    => 'product-attributes',
				'excerpt' => 'ویژگی کالا و فیلدهای مشخصات کاتالوگ.',
				'content' => hhelp_syllabus_stub( 'کالا و خدمات ← ویژگی‌ها / مشخصات کاتالوگ', 'رنگ، سایز و مشخصات فنی کالا از این دو صفحه تعریف می‌شود.' ),
			),
			array( 'id' => 785, 'title' => 'لیست قیمت', 'access' => 'members', 'menu' => 'price-lists' ),
			array( 'id' => 787, 'title' => 'سطوح قیمت و تخفیف پیشرفته', 'access' => 'paid', 'menu' => 'pricing' ),
			array(
				'slug'    => 'help-barcode-labels',
				'title'   => 'طراحی و چاپ برچسب بارکد',
				'access'  => 'members',
				'menu'    => 'barcode-labels',
				'excerpt' => 'استودیو برچسب بارکد (افزونه).',
				'content' => hhelp_syllabus_stub( 'کالا و خدمات ← برچسب بارکد', 'نیاز به افزونه «طراحی و چاپ برچسب بارکد» دارد.' ),
			),
		),
	),
	array(
		'id'      => 789,
		'title'   => 'فروش',
		'icon'    => 'invoice',
		'access'  => 'free',
		'menu'    => 'invoice',
		'rename'  => true,
		'excerpt' => 'فاکتور فروش، فروش سریع، اقساط و صفحه پرداخت.',
		'children'=> array(
			array( 'id' => 791, 'title' => 'صدور فاکتور فروش', 'access' => 'free', 'menu' => 'invoice' ),
			array( 'id' => 793, 'title' => 'فروش سریع', 'access' => 'free', 'menu' => 'quick-sales' ),
			array( 'id' => 797, 'title' => 'فروش اقساطی', 'access' => 'members', 'menu' => 'invoice' ),
			array(
				'slug'    => 'help-invoice-pay-page',
				'title'   => 'اشتراک فاکتور و صفحه پرداخت',
				'access'  => 'members',
				'menu'    => 'settings/pay-page',
				'excerpt' => 'ارسال لینک فاکتور و دریافت آنلاین.',
				'content' => hhelp_syllabus_stub( 'تنظیمات ← اشتراک فاکتور / صفحه پرداخت', 'لینک پرداخت مشتری و درگاه از این تنظیمات فعال می‌شود.' ),
			),
			array( 'id' => 799, 'title' => 'سناریوی پیشرفته فروش چندمرحله‌ای', 'access' => 'paid', 'menu' => 'invoice' ),
		),
	),
	array(
		'slug'    => 'help-chapter-purchase',
		'title'   => 'خرید',
		'icon'    => 'invoice',
		'access'  => 'free',
		'menu'    => 'invoice',
		'excerpt' => 'فاکتور خرید و برگشت از خرید در همان فرم فاکتور آرک.',
		'content' => hhelp_syllabus_intro( 'خرید از همان منوی فاکتور است؛ نوع فاکتور را روی خرید می‌گذارید. تأمین‌کننده و ورود انبار در این فصل است.' ),
		'children'=> array(
			array( 'id' => 795, 'title' => 'فاکتور خرید', 'access' => 'free', 'menu' => 'invoice' ),
			array(
				'slug'    => 'help-purchase-return',
				'title'   => 'برگشت از خرید و اصلاح فاکتور',
				'access'  => 'members',
				'menu'    => 'invoice',
				'excerpt' => 'نوع برگشت از خرید و اصلاح فاکتور ثبت‌شده.',
				'content' => hhelp_syllabus_stub( 'فاکتور ← نوع: برگشت از خرید', 'برای مرجوعی به تأمین‌کننده از نوع برگشت از خرید استفاده می‌شود.' ),
			),
		),
	),
	array(
		'id'      => 801,
		'title'   => 'خزانه، بانک و نقدینگی',
		'icon'    => 'accounting',
		'access'  => 'free',
		'menu'    => 'group:accounts',
		'rename'  => true,
		'excerpt' => 'بانک، صندوق، تنخواه، دریافت و پرداخت، انتقال، چک و کیف پول.',
		'children'=> array(
			array( 'id' => 803, 'title' => 'تعریف حساب بانکی', 'access' => 'free', 'menu' => 'accounts' ),
			array(
				'slug'    => 'help-cash-box',
				'title'   => 'صندوق',
				'access'  => 'free',
				'menu'    => 'cash-box',
				'excerpt' => 'تعریف صندوق نقدی در آرک.',
				'content' => hhelp_syllabus_stub( 'بانکداری ← صندوق', 'صندوق محل نگهداری وجه نقد شعبه است و در دریافت و پرداخت انتخاب می‌شود.' ),
			),
			array(
				'slug'    => 'help-petty-cash',
				'title'   => 'تنخواه',
				'access'  => 'members',
				'menu'    => 'petty-cash',
				'excerpt' => 'تنخواه و تسویه تنخواه‌گردان.',
				'content' => hhelp_syllabus_stub( 'بانکداری ← تنخواه', 'تنخواه برای هزینه‌های خرد جدا از حساب بانکی تعریف می‌شود.' ),
			),
			array( 'id' => 805, 'title' => 'دریافت و پرداخت', 'access' => 'free', 'menu' => 'receipts-payments' ),
			array(
				'slug'    => 'help-transfers',
				'title'   => 'انتقال بین حساب‌ها',
				'access'  => 'members',
				'menu'    => 'transfers',
				'excerpt' => 'انتقال وجه بین بانک، صندوق و تنخواه.',
				'content' => hhelp_syllabus_stub( 'حسابداری ← انتقالات', 'جابه‌جایی بین حساب بانکی، صندوق و تنخواه بدون طرف‌حساب شخص.' ),
			),
			array( 'id' => 807, 'title' => 'مدیریت چک‌ها', 'access' => 'members', 'menu' => 'checks' ),
			array(
				'slug'    => 'help-wallet',
				'title'   => 'کیف پول حسابیکس',
				'access'  => 'members',
				'menu'    => 'wallet',
				'excerpt' => 'کیف پول و شارژ خدمات حسابیکس.',
				'content' => hhelp_syllabus_stub( 'بانکداری ← کیف پول', 'برای پیامک، افزونه و خدمات ابری حسابیکس استفاده می‌شود.' ),
			),
		),
	),
	array(
		'slug'    => 'help-chapter-expense-income',
		'title'   => 'هزینه و درآمد',
		'icon'    => 'accounting',
		'access'  => 'free',
		'menu'    => 'expense-income',
		'excerpt' => 'ثبت هزینه و درآمد مستقل از فاکتور کالا.',
		'content' => hhelp_syllabus_intro( 'هزینه اجاره، حقوق پیمانکار یا درآمد متفرقه از منوی هزینه و درآمد ثبت می‌شود؛ نه از فاکتور کالا.' ),
		'children'=> array(
			array(
				'slug'    => 'help-expense-income',
				'title'   => 'ثبت هزینه و درآمد',
				'access'  => 'free',
				'menu'    => 'expense-income',
				'excerpt' => 'فرم هزینه و درآمد، سرفصل و طرف‌حساب نقدی.',
				'content' => hhelp_syllabus_stub( 'حسابداری ← هزینه و درآمد', 'چند سرفصل هزینه/درآمد و چند طرف‌حساب نقدی در یک سند.' ),
			),
		),
	),
	array(
		'id'      => 809,
		'title'   => 'انبار و موجودی',
		'icon'    => 'inventory',
		'access'  => 'free',
		'menu'    => 'group:warehouses',
		'children'=> array(
			array( 'id' => 811, 'title' => 'تعریف انبار', 'access' => 'free', 'menu' => 'warehouses' ),
			array( 'id' => 813, 'title' => 'اسناد انبار (حواله و انتقال)', 'access' => 'members', 'menu' => 'warehouse-docs', 'rename' => true ),
			array( 'id' => 815, 'title' => 'انبارگردانی', 'access' => 'members', 'menu' => 'stock-count' ),
			array(
				'slug'    => 'help-qs-stock-discrepancies',
				'title'   => 'مغایرت موجودی فروش سریع',
				'access'  => 'members',
				'menu'    => 'quick-sales-stock-discrepancies',
				'excerpt' => 'اختلاف فروش صندوق با موجودی انبار.',
				'content' => hhelp_syllabus_stub( 'انبار ← مغایرت موجودی فروش سریع', 'وقتی فروش سریع بدون موجودی کافی ثبت شود، مغایرت اینجا دیده می‌شود.' ),
			),
			array(
				'slug'    => 'help-production-orders',
				'title'   => 'سفارش تولید',
				'access'  => 'members',
				'menu'    => 'production-orders',
				'excerpt' => 'سفارش تولید پایه در انبار.',
				'content' => hhelp_syllabus_stub( 'انبار ← سفارش تولید', 'تبدیل مواد به کالای ساخته‌شده با اسناد انبار.' ),
			),
		),
	),
	array(
		'id'      => 817,
		'title'   => 'حسابداری و دوره مالی',
		'icon'    => 'accounting',
		'access'  => 'free',
		'menu'    => 'group:chart-of-accounts',
		'rename'  => true,
		'excerpt' => 'جدول حساب، سند دستی، تراز افتتاحیه، بستن سال و تسعیر.',
		'children'=> array(
			array( 'id' => 819, 'title' => 'جدول حساب‌ها', 'access' => 'free', 'menu' => 'chart-of-accounts', 'rename' => true ),
			array( 'id' => 821, 'title' => 'ثبت سند حسابداری', 'access' => 'members', 'menu' => 'documents', 'rename' => true ),
			array( 'id' => 823, 'title' => 'تراز افتتاحیه', 'access' => 'members', 'menu' => 'opening-balance' ),
			array( 'id' => 825, 'title' => 'بستن سال مالی', 'access' => 'paid', 'menu' => 'year-end-closing' ),
			array(
				'slug'    => 'help-currency-revaluation',
				'title'   => 'تسعیر ارز',
				'access'  => 'members',
				'menu'    => 'currency-revaluation',
				'excerpt' => 'تسعیر پایان دوره در کسب‌وکار چندارزی.',
				'content' => hhelp_syllabus_stub( 'حسابداری ← تسعیر ارز', 'برای کسب‌وکار چندارزی و افزونه حسابداری پیشرفته.' ),
			),
		),
	),
	array(
		'id'      => 827,
		'title'   => 'گزارش‌ها',
		'icon'    => 'accounting',
		'access'  => 'free',
		'menu'    => 'reports',
		'children'=> array(
			array(
				'slug'    => 'help-reports-hub',
				'title'   => 'مرکز گزارش‌ها',
				'access'  => 'free',
				'menu'    => 'reports',
				'excerpt' => 'نقشه کاتالوگ گزارش‌های آرک.',
				'content' => hhelp_syllabus_stub( 'گزارش‌ها', 'گزارش‌ها بر اساس بخش (فروش، انبار، مالی، سیستم) دسته‌بندی شده‌اند؛ علاقه و فیلتر ذخیره می‌شود.' ),
			),
			array( 'id' => 831, 'title' => 'گزارش‌های فروش و اشخاص', 'access' => 'members', 'menu' => 'reports', 'rename' => true ),
			array(
				'slug'    => 'help-reports-inventory',
				'title'   => 'گزارش‌های موجودی و انبار',
				'access'  => 'members',
				'menu'    => 'reports',
				'excerpt' => 'موجودی، انبارگردانی، کالای کم‌گردش و بحرانی.',
				'content' => hhelp_syllabus_stub( 'گزارش‌ها ← بخش انبار و موجودی', 'موجودی لحظه‌ای، حواله، کالای کم‌گردش، بحرانی و تاریخ انقضا.' ),
			),
			array( 'id' => 829, 'title' => 'صورت‌های مالی و دفاتر', 'access' => 'members', 'menu' => 'reports', 'rename' => true ),
			array(
				'slug'    => 'help-hscript',
				'title'   => 'گزارش‌ساز HScript',
				'access'  => 'members',
				'menu'    => 'hscript',
				'excerpt' => 'ساخت گزارش سفارشی با HScript.',
				'content' => hhelp_syllabus_stub( 'خدمات ← گزارش‌ساز HScript', 'گزارش و داشبورد سفارشی؛ سقف رایگان دارد و با افزونه بازتر می‌شود.' ),
			),
		),
	),
	array(
		'id'      => 833,
		'title'   => 'مالیات و سامانه مودیان',
		'icon'    => 'tax',
		'access'  => 'free',
		'menu'    => 'tax-workspace',
		'children'=> array(
			array( 'id' => 835, 'title' => 'فعال‌سازی افزونه مودیان', 'access' => 'free', 'menu' => 'plugin-marketplace' ),
			array( 'id' => 837, 'title' => 'کارپوشه مودیان', 'access' => 'members', 'menu' => 'tax-workspace' ),
			array(
				'slug'    => 'help-moadian-submit',
				'title'   => 'ارسال، اصلاح و ابطال صورت‌حساب',
				'access'  => 'members',
				'menu'    => 'tax-workspace',
				'excerpt' => 'ارسال به سامانه مودیان، اصلاحی و ابطال.',
				'content' => hhelp_syllabus_stub( 'مودیان ← کارپوشه', 'بعد از صدور فاکتور، ارسال الکترونیکی، استعلام وضعیت، اصلاحی و ابطال از کارپوشه است.' ),
			),
		),
	),
	array(
		'id'      => 839,
		'title'   => 'CRM',
		'icon'    => 'crm',
		'access'  => 'free',
		'menu'    => 'group:crm',
		'children'=> array(
			array(
				'slug'    => 'help-crm-dashboard',
				'title'   => 'داشبورد CRM',
				'access'  => 'free',
				'menu'    => 'crm/dashboard',
				'excerpt' => 'نمای کلی قیف فروش و کارهای CRM.',
				'content' => hhelp_syllabus_stub( 'CRM ← داشبورد', 'نقطه ورود قیف فروش، وظایف باز و شاخص‌های CRM.' ),
			),
			array( 'id' => 841, 'title' => 'مدیریت سرنخ‌ها', 'access' => 'free', 'menu' => 'crm/leads' ),
			array(
				'slug'    => 'help-crm-deals',
				'title'   => 'فرصت‌های فروش',
				'access'  => 'members',
				'menu'    => 'crm/deals',
				'excerpt' => 'مدیریت فرصت و مرحله قیف.',
				'content' => hhelp_syllabus_stub( 'CRM ← فرصت‌ها', 'تبدیل سرنخ به فرصت و حرکت در مراحل قیف.' ),
			),
			array(
				'slug'    => 'help-crm-tasks',
				'title'   => 'وظایف، فعالیت‌ها و تقویم',
				'access'  => 'members',
				'menu'    => 'crm/tasks',
				'excerpt' => 'کار روزانه CRM: وظیفه، فعالیت و تقویم.',
				'content' => hhelp_syllabus_stub( 'CRM ← وظایف / فعالیت‌ها / یادداشت و تقویم', 'کار روزانه تیم فروش جدا از فاکتور حسابداری است.' ),
			),
			array( 'id' => 843, 'title' => 'چت وب با مشتری', 'access' => 'members', 'menu' => 'crm/web-chat' ),
			array(
				'slug'    => 'help-crm-360',
				'title'   => 'مشتری ۳۶۰',
				'access'  => 'members',
				'menu'    => 'crm/customer-360',
				'excerpt' => 'نمای ۳۶۰ درجه مشتری در CRM.',
				'content' => hhelp_syllabus_stub( 'CRM ← مشتری ۳۶۰', 'سرنخ، فرصت، فاکتور و فعالیت یک شخص در یک صفحه.' ),
			),
		),
	),
	array(
		'id'      => 845,
		'title'   => 'هوش مصنوعی',
		'icon'    => 'ai',
		'access'  => 'free',
		'menu'    => 'group:ai',
		'children'=> array(
			array( 'id' => 847, 'title' => 'دستیار هوشمند', 'access' => 'free', 'menu' => 'ai/chat' ),
			array(
				'slug'    => 'help-ai-subscription',
				'title'   => 'اشتراک و مصرف هوش مصنوعی',
				'access'  => 'members',
				'menu'    => 'ai/subscription',
				'excerpt' => 'پلن، مصرف و سقف استفاده از دستیار.',
				'content' => hhelp_syllabus_stub( 'هوش مصنوعی ← اشتراک / مصرف', 'بدون اشتراک فعال، دستیار به داده کسب‌وکار وصل نمی‌شود.' ),
			),
			array(
				'slug'    => 'help-ai-mcp',
				'title'   => 'مهارت‌ها و سرور MCP',
				'access'  => 'members',
				'menu'    => 'ai/skills/marketplace',
				'excerpt' => 'بازار مهارت و اتصال ChatGPT/Claude از طریق MCP.',
				'content' => hhelp_syllabus_stub( 'هوش مصنوعی ← بازار مهارت + افزونه سرور MCP', 'مهارت داخل آرک؛ MCP برای دستیار خارجی روی همان کسب‌وکار.' ),
			),
		),
	),
	array(
		'id'      => 849,
		'title'   => 'اتوماسیون و ورک‌فلو',
		'icon'    => 'workflow',
		'access'  => 'free',
		'menu'    => 'workflows',
		'children'=> array(
			array( 'id' => 851, 'title' => 'ساخت ورک‌فلو ساده', 'access' => 'members', 'menu' => 'workflows' ),
			array(
				'slug'    => 'help-workflow-marketplace',
				'title'   => 'نصب قالب از بازار ورک‌فلو',
				'access'  => 'members',
				'menu'    => 'workflows',
				'excerpt' => 'نصب بسته آماده ورک‌فلو.',
				'content' => hhelp_syllabus_stub( 'ورک‌فلو ← بازار قالب', 'به‌جای ساخت از صفر می‌توان قالب آماده نصب کرد.' ),
			),
		),
	),
	array(
		'id'      => 853,
		'title'   => 'فروشگاه آنلاین و اتصال‌ها',
		'icon'    => 'start',
		'access'  => 'free',
		'menu'    => 'woocommerce',
		'rename'  => true,
		'excerpt' => 'ووکامرس، باسلام و دیجی‌پی.',
		'content' => hhelp_syllabus_intro( 'اتصال فروشگاه و درگاه اعتباری از منوی خدمات و افزونه‌هاست. بازار افزونه‌ها در فصل تنظیمات است.' ),
		'children'=> array(
			array( 'id' => 857, 'title' => 'اتصال ووکامرس', 'access' => 'members', 'menu' => 'woocommerce' ),
			array(
				'slug'    => 'help-basalam',
				'title'   => 'اتصال باسلام',
				'access'  => 'members',
				'menu'    => 'basalam',
				'excerpt' => 'همگام‌سازی سفارش و محصول باسلام.',
				'content' => hhelp_syllabus_stub( 'خدمات ← باسلام', 'وب‌هوک، سفارش، محصول و چت باسلام بعد از نصب افزونه.' ),
			),
			array(
				'slug'    => 'help-digipay',
				'title'   => 'پرداخت اعتباری دیجی‌پی',
				'access'  => 'members',
				'menu'    => 'digipay',
				'excerpt' => 'فروش اعتباری دیجی‌پی در فاکتور.',
				'content' => hhelp_syllabus_stub( 'خدمات ← دیجی‌پی', 'خرید اعتباری در فروش حضوری و آنلاین؛ سند تسویه جدا از دریافت نقدی.' ),
			),
		),
	),
	array(
		'id'      => 865,
		'title'   => 'افزونه‌های تخصصی',
		'icon'    => 'start',
		'access'  => 'free',
		'menu'    => 'plugin-marketplace',
		'rename'  => true,
		'excerpt' => 'گارانتی، تعمیرگاه، باشگاه، حقوق، اتوماسیون اداری، اموال، تماس، پخش و تولید.',
		'children'=> array(
			array( 'id' => 867, 'title' => 'گارانتی کالا', 'access' => 'members', 'menu' => 'warranty' ),
			array( 'id' => 869, 'title' => 'تعمیرگاه', 'access' => 'members', 'menu' => 'repair-shop' ),
			array( 'id' => 871, 'title' => 'باشگاه مشتریان', 'access' => 'members', 'menu' => 'customer-club' ),
			array( 'id' => 873, 'title' => 'حقوق و دستمزد', 'access' => 'members', 'menu' => 'payroll' ),
			array(
				'slug'    => 'help-office-automation',
				'title'   => 'اتوماسیون اداری',
				'access'  => 'members',
				'menu'    => 'office-automation',
				'excerpt' => 'کارتابل نامه، ارجاع و دبیرخانه.',
				'content' => hhelp_syllabus_stub( 'اتوماسیون اداری ← کارتابل', 'نامه داخلی، وارده و صادره، ارجاع و پاراف.' ),
			),
			array(
				'slug'    => 'help-fixed-assets',
				'title'   => 'دارایی ثابت',
				'access'  => 'members',
				'menu'    => 'fixed-assets',
				'excerpt' => 'اموال، تحصیل و استهلاک.',
				'content' => hhelp_syllabus_stub( 'اموال و دارایی ثابت', 'جدا از انبار کالای فروش؛ استهلاک و سند دفتر کل.' ),
			),
			array( 'id' => 875, 'title' => 'مرکز تماس', 'access' => 'members', 'menu' => 'telephony' ),
			array( 'id' => 877, 'title' => 'پخش مویرگی', 'access' => 'members', 'menu' => 'distribution' ),
			array(
				'slug'    => 'help-advanced-production',
				'title'   => 'تولید پیشرفته',
				'access'  => 'members',
				'menu'    => 'advanced-production',
				'excerpt' => 'گزارش بهای تمام‌شده و کسری مواد تولید.',
				'content' => hhelp_syllabus_stub( 'تولید پیشرفته', 'روی سفارش تولید هسته؛ پیشرفت، بها و انحراف مصرف.' ),
			),
		),
	),
	array(
		'id'      => 859,
		'title'   => 'پرسش‌های متداول و عیب‌یابی',
		'icon'    => 'start',
		'access'  => 'free',
		'menu'    => 'help',
		'children'=> array(
			array( 'id' => 861, 'title' => 'چرا آیتم منو را نمی‌بینم؟', 'access' => 'free', 'menu' => 'settings' ),
			array( 'id' => 863, 'title' => 'فاکتور ذخیره نمی‌شود', 'access' => 'free', 'menu' => 'invoice' ),
		),
	),
);

$featured_on = array( 761, 763, 765, 773, 781, 791 );
$kept_ids    = array();
$created     = 0;
$updated     = 0;

foreach ( $tree as $chapter_i => $chapter ) {
	$chapter_order = ( $chapter_i + 1 ) * 10;
	$chapter_id    = hhelp_syllabus_upsert( $chapter, 0, $chapter_order );
	if ( ! $chapter_id ) {
		continue;
	}
	if ( empty( $chapter['id'] ) ) {
		++$created;
	} else {
		++$updated;
	}
	$kept_ids[] = $chapter_id;
	foreach ( $chapter['children'] as $lesson_i => $lesson ) {
		$lesson_id = hhelp_syllabus_upsert( $lesson, $chapter_id, ( $lesson_i + 1 ) * 10 );
		if ( ! $lesson_id ) {
			continue;
		}
		if ( empty( $lesson['id'] ) ) {
			++$created;
		} else {
			++$updated;
		}
		$kept_ids[] = $lesson_id;
	}
}

$all = get_posts(
	array(
		'post_type'      => HHELP_CPT,
		'post_status'    => 'any',
		'posts_per_page' => -1,
		'fields'         => 'ids',
	)
);
foreach ( $all as $hid ) {
	$hid = (int) $hid;
	if ( in_array( $hid, $featured_on, true ) ) {
		update_post_meta( $hid, '_hhelp_featured', 1 );
	} else {
		delete_post_meta( $hid, '_hhelp_featured' );
	}
}

if ( class_exists( 'Hhelp_Tree' ) ) {
	Hhelp_Tree::flush_cache();
}
wp_cache_flush();
update_option( 'hhelp_syllabus_version', '3', false );

echo "updated={$updated} created_or_reused_new={$created} kept=" . count( $kept_ids ) . "\n";
echo 'chapters=' . count( $tree ) . "\n";
