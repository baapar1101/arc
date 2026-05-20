<?php
/**
 * صفحهٔ تنظیمات و ذخیرهٔ گزینه‌ها.
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

/**
 * پنل ادمین.
 */
final class Shabake_Tamin_Admin {

	/**
	 * @var self|null
	 */
	private static $instance = null;

	/**
	 * @return self
	 */
	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	private function __construct() {
		add_action( 'admin_init', array( $this, 'register_settings' ) );
		add_action( 'admin_menu', array( $this, 'add_menu' ) );
	}

	/**
	 * ثبت تنظیمات.
	 */
	public function register_settings() {
		register_setting(
			'shabake_tamin',
			'st_api_base_url',
			array(
				'type'              => 'string',
				'sanitize_callback' => array( $this, 'sanitize_base_url' ),
				'default'           => '',
			)
		);
		register_setting(
			'shabake_tamin',
			'st_cache_ttl',
			array(
				'type'              => 'integer',
				'sanitize_callback' => array( $this, 'sanitize_ttl' ),
				'default'           => 45,
			)
		);
		register_setting(
			'shabake_tamin',
			'st_default_business_id',
			array(
				'type'              => 'integer',
				'sanitize_callback' => 'absint',
				'default'           => 0,
			)
		);
		register_setting(
			'shabake_tamin',
			'st_public_catalog_enabled',
			array(
				'type'              => 'integer',
				'sanitize_callback' => array( $this, 'sanitize_public_catalog_enabled' ),
				'default'           => 0,
			)
		);
		register_setting(
			'shabake_tamin',
			'st_public_catalog_slug',
			array(
				'type'              => 'string',
				'sanitize_callback' => array( $this, 'sanitize_public_catalog_slug' ),
				'default'           => 'tamin',
			)
		);
		register_setting(
			'shabake_tamin',
			'st_public_catalog_title',
			array(
				'type'              => 'string',
				'sanitize_callback' => array( $this, 'sanitize_public_catalog_title' ),
				'default'           => '',
			)
		);
	}

	/**
	 * @param mixed $v مقدار خام.
	 * @return int ۰ یا ۱
	 */
	public function sanitize_public_catalog_enabled( $v ) {
		if ( is_array( $v ) ) {
			$v = end( $v );
		}
		return filter_var( $v, FILTER_VALIDATE_BOOLEAN ) ? 1 : 0;
	}

	/**
	 * @param mixed $slug اسلاگ URL.
	 * @return string
	 */
	public function sanitize_public_catalog_slug( $slug ) {
		$s = is_string( $slug ) ? sanitize_title( trim( $slug ) ) : '';
		return '' === $s ? 'tamin' : $s;
	}

	/**
	 * @param mixed $title عنوان صفحه.
	 * @return string
	 */
	public function sanitize_public_catalog_title( $title ) {
		$t = is_string( $title ) ? sanitize_text_field( trim( $title ) ) : '';
		return mb_substr( $t, 0, 200 );
	}

	/**
	 * @param string $url URL.
	 * @return string
	 */
	public function sanitize_base_url( $url ) {
		$url = is_string( $url ) ? trim( $url ) : '';
		return rtrim( esc_url_raw( $url ), '/' );
	}

	/**
	 * @param mixed $ttl TTL.
	 * @return int
	 */
	public function sanitize_ttl( $ttl ) {
		$n = absint( $ttl );
		return min( 3600, $n );
	}

	/**
	 * منوی تنظیمات.
	 */
	public function add_menu() {
		add_options_page(
			__( 'شبکه تأمین', 'shabake-tamin' ),
			__( 'شبکه تأمین', 'shabake-tamin' ),
			'manage_options',
			'shabake-tamin',
			array( $this, 'render_page' )
		);
	}

	/**
	 * رندر صفحه.
	 */
	public function render_page() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		?>
		<div class="wrap">
			<h1><?php echo esc_html( get_admin_page_title() ); ?></h1>

			<div class="notice notice-info" style="margin-top:1em;">
				<p>
					<strong><?php esc_html_e( 'نمایش برای بازدیدکنندگان', 'shabake-tamin' ); ?></strong><br />
					<?php esc_html_e( 'اگر «شناسهٔ کسب‌وکار پیش‌فرض» را خالی بگذارید و در شورت‌کد یا بلوک هم کسب‌وکار مشخص نکنید، کاتالوگ بدون فیلتر business_id به Hesabix فرستاده می‌شود؛ در نتیجه بازدیدکننده می‌تواند کالاهای عمومی همهٔ کسب‌وکارهایی که در Hesabix منتشر کرده‌اند را ببیند، نام تأمین‌کننده را روی کارت ببیند و با جستجو (و در صورت تنظیم، فیلتر استان/شهر/دسته) نتایج را محدود کند. محدودیت نرخ و کش روی سرور Hesabix و پراکسی وردپرس اعمال می‌شود.', 'shabake-tamin' ); ?>
				</p>
			</div>

			<form action="options.php" method="post">
				<?php settings_fields( 'shabake_tamin' ); ?>
				<table class="form-table" role="presentation">
					<tr>
						<th scope="row">
							<label for="st_api_base_url"><?php esc_html_e( 'آدرس پایهٔ API حسابیکس', 'shabake-tamin' ); ?></label>
						</th>
						<td>
							<input name="st_api_base_url" id="st_api_base_url" type="url" class="regular-text code"
								value="<?php echo esc_attr( get_option( 'st_api_base_url', '' ) ); ?>"
								placeholder="https://api.example.com" />
							<p class="description">
								<?php esc_html_e( 'مثال: همان دامنهٔ سرور Hesabix بدون اسلش انتهایی. درخواست‌های مرورگر از طریق REST وردپرس به این آدرس پراکسی می‌شوند.', 'shabake-tamin' ); ?>
							</p>
						</td>
					</tr>
					<tr>
						<th scope="row">
							<label for="st_cache_ttl"><?php esc_html_e( 'مدت کش پراکسی (ثانیه)', 'shabake-tamin' ); ?></label>
						</th>
						<td>
							<input name="st_cache_ttl" id="st_cache_ttl" type="number" min="0" max="3600" step="1"
								value="<?php echo esc_attr( (string) (int) get_option( 'st_cache_ttl', 45 ) ); ?>" />
							<p class="description"><?php esc_html_e( '۰ یعنی بدون کش در وردپرس.', 'shabake-tamin' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row">
							<label for="st_default_business_id"><?php esc_html_e( 'شناسهٔ کسب‌وکار پیش‌فرض (اختیاری)', 'shabake-tamin' ); ?></label>
						</th>
						<td>
							<input name="st_default_business_id" id="st_default_business_id" type="number" min="0" step="1"
								value="<?php echo esc_attr( (string) (int) get_option( 'st_default_business_id', 0 ) ); ?>" />
							<p class="description">
								<?php esc_html_e( 'اگر ۰ بماند و در شورت‌کد/بلوک هم کسب‌وکار ندهید، لیست برای مهمان شامل همهٔ کسب‌وکارها می‌شود (فقط کالاهای علامت‌خوردهٔ عمومی در Hesabix).', 'shabake-tamin' ); ?>
							</p>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'صفحهٔ عمومی کاتالوگ (آدرس اختصاصی)', 'shabake-tamin' ); ?></th>
						<td>
							<label>
								<input type="hidden" name="st_public_catalog_enabled" value="0" />
								<input name="st_public_catalog_enabled" type="checkbox" value="1"
									<?php checked( (int) get_option( 'st_public_catalog_enabled', 0 ), 1 ); ?> />
								<?php esc_html_e( 'فعال‌سازی آدرس مستقل برای بازدیدکنندگان (شبیه یک ویترین؛ بدون نیاز به برگهٔ وردپرس)', 'shabake-tamin' ); ?>
							</label>
							<p class="description">
								<?php esc_html_e( 'پس از ذخیره، اگر پیوندهای یکتا روشن است، کاتالوگ در آدرس زیر در دسترس است:', 'shabake-tamin' ); ?>
							</p>
							<?php
							$slug = class_exists( 'Shabake_Tamin_Public_Catalog', false )
								? Shabake_Tamin_Public_Catalog::get_slug()
								: ( sanitize_title( (string) get_option( 'st_public_catalog_slug', 'tamin' ) ) ?: 'tamin' );
							$url  = home_url( '/' . $slug . '/' );
							?>
							<p><code dir="ltr" style="unicode-bidi: embed;"><?php echo esc_html( $url ); ?></code></p>
							<p>
								<label for="st_public_catalog_slug"><?php esc_html_e( 'اسلاگ مسیر (انگلیسی، بدون فاصله)', 'shabake-tamin' ); ?></label><br />
								<input name="st_public_catalog_slug" id="st_public_catalog_slug" type="text" class="regular-text code" dir="ltr"
									value="<?php echo esc_attr( (string) get_option( 'st_public_catalog_slug', 'tamin' ) ); ?>"
									pattern="[a-z0-9\-]+"
									autocomplete="off" />
							</p>
							<p>
								<label for="st_public_catalog_title"><?php esc_html_e( 'عنوان هیرو (اختیاری؛ خالی = نام سایت)', 'shabake-tamin' ); ?></label><br />
								<input name="st_public_catalog_title" id="st_public_catalog_title" type="text" class="regular-text"
									value="<?php echo esc_attr( (string) get_option( 'st_public_catalog_title', '' ) ); ?>"
									maxlength="200" />
							</p>
							<p class="description">
								<?php esc_html_e( 'اگر بعد از تغییر اسلاگ یا فعال‌سازی، صفحه ۴۰۴ دیدید، یک‌بار از تنظیمات → پیوندهای یکتا «ذخیره» بزنید تا rewrite بازسازی شود.', 'shabake-tamin' ); ?>
							</p>
						</td>
					</tr>
				</table>
				<?php submit_button(); ?>
			</form>
			<hr />
			<h2><?php esc_html_e( 'شورت‌کد و بلوک', 'shabake-tamin' ); ?></h2>
			<p><code>[shabake_tamin]</code> <?php esc_html_e( 'یا:', 'shabake-tamin' ); ?></p>
			<pre class="code" style="direction:ltr;text-align:left;">[shabake_tamin business_id="123" category_id="5" province="تهران" city="" location_filters="1" province_suggest="1" show_details="1" columns="4" search="1" take="20" page="1"]</pre>
			<p class="description"><?php esc_html_e( 'با page="1" همان چیدمان تمام‌عرض (هیرو + شمارندهٔ نتایج) داخل برگهٔ عادی هم قابل استفاده است.', 'shabake-tamin' ); ?></p>
			<p class="description"><?php esc_html_e( 'در ظاهر → ابزارک‌ها، «کاتالوگ شبکه تأمین» را می‌توانید به سایدبار اضافه کنید. در ویرایشگر بلوک، بلوک هم‌نام را در دستهٔ ابزارک‌ها بیابید.', 'shabake-tamin' ); ?></p>
			<p class="description">
				<?php esc_html_e( 'برای سفارشی‌سازی ظاهر، فایل‌های PHP را در پوشهٔ shabake-tamin داخل قالب کپی کنید (مثلاً catalog-wrapper.php).', 'shabake-tamin' ); ?>
			</p>
		</div>
		<?php
	}
}
