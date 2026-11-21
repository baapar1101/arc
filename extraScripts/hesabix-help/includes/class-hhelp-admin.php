<?php
/**
 * Admin helpers.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_Admin
 */
class Hhelp_Admin {

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

	/**
	 * Constructor.
	 */
	private function __construct() {
		add_filter( 'manage_' . HHELP_CPT . '_posts_columns', array( $this, 'columns' ) );
		add_action( 'manage_' . HHELP_CPT . '_posts_custom_column', array( $this, 'column_content' ), 10, 2 );
		add_action( 'admin_menu', array( $this, 'settings_page' ) );
	}

	/**
	 * @param array<string, string> $cols Columns.
	 * @return array<string, string>
	 */
	public function columns( $cols ) {
		$new = array();
		foreach ( $cols as $key => $label ) {
			$new[ $key ] = $label;
			if ( 'title' === $key ) {
				$new['hhelp_access'] = __( 'دسترسی', 'hesabix-help' );
				$new['hhelp_video']  = __( 'ویدئو', 'hesabix-help' );
			}
		}
		return $new;
	}

	/**
	 * @param string $col     Column.
	 * @param int    $post_id Post ID.
	 */
	public function column_content( $col, $post_id ) {
		if ( 'hhelp_access' === $col ) {
			echo esc_html( hhelp_access_label( hhelp_get_access( $post_id ) ) );
		}
		if ( 'hhelp_video' === $col ) {
			$v = Hhelp_Meta::get_video( $post_id );
			echo 'none' !== $v['type'] ? '✓' : '—';
		}
	}

	/**
	 * Settings submenu.
	 */
	public function settings_page() {
		add_submenu_page(
			'edit.php?post_type=' . HHELP_CPT,
			__( 'تنظیمات راهنما', 'hesabix-help' ),
			__( 'تنظیمات', 'hesabix-help' ),
			'manage_options',
			'hesabix-help-settings',
			array( $this, 'render_settings' )
		);
	}

	/**
	 * Settings screen.
	 */
	public function render_settings() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}

		if ( isset( $_POST['hhelp_reseed'] ) && check_admin_referer( 'hhelp_reseed' ) ) {
			Hhelp_Seed::run( true );
			echo '<div class="notice notice-success"><p>' . esc_html__( 'محتوای نمونه بازسازی شد.', 'hesabix-help' ) . '</p></div>';
		}

		$hub = hhelp_hub_url();
		$api = rest_url( 'wp/v2/help' );
		$app_passwords_ok = function_exists( 'wp_is_application_passwords_available' ) && wp_is_application_passwords_available();
		?>
		<div class="wrap">
			<h1><?php esc_html_e( 'تنظیمات راهنمای جامع', 'hesabix-help' ); ?></h1>
			<p>
				<?php esc_html_e( 'آدرس هاب:', 'hesabix-help' ); ?>
				<a href="<?php echo esc_url( $hub ); ?>" target="_blank" rel="noopener noreferrer"><code><?php echo esc_html( $hub ); ?></code></a>
			</p>
			<p><?php esc_html_e( 'مطالب سلسله‌مراتبی را از منوی «راهنمای جامع» مدیریت کنید. سطح دسترسی، ویدئو و محصول پولی در باکس کناری هر مطلب است.', 'hesabix-help' ); ?></p>

			<hr />
			<h2><?php esc_html_e( 'REST API برای هوش مصنوعی (مسیر A)', 'hesabix-help' ); ?></h2>
			<p>
				<?php esc_html_e( 'Endpoint:', 'hesabix-help' ); ?>
				<code><?php echo esc_html( $api ); ?></code>
			</p>
			<p>
				<?php
				echo $app_passwords_ok
					? esc_html__( 'Application Passwords فعال است. از پروفایل کاربر (ترجیحاً supportAI) یک رمز برنامه بسازید.', 'hesabix-help' )
					: esc_html__( 'Application Passwords در دسترس نیست؛ اتصال HTTPS سایت را بررسی کنید.', 'hesabix-help' );
				?>
			</p>
			<p class="description">
				<?php esc_html_e( 'کاربر باید نقش Administrator یا قابلیت edit_pages / publish_pages داشته باشد. احراز هویت: Basic Auth با نام‌کاربری و Application Password.', 'hesabix-help' ); ?>
			</p>
			<pre style="background:#f6f7f7;padding:12px;overflow:auto;direction:ltr;text-align:left;max-width:52rem"><?php
				echo esc_html(
					"curl -u 'USERNAME:APPLICATION_PASSWORD' \\\n" .
					"  -X POST " . $api . " \\\n" .
					"  -H 'Content-Type: application/json' \\\n" .
					"  -d '{\n" .
					"    \"title\": \"عنوان مطلب\",\n" .
					"    \"content\": \"<p>متن HTML</p>\",\n" .
					"    \"status\": \"draft\",\n" .
					"    \"parent\": 0,\n" .
					"    \"meta\": {\n" .
					"      \"_hhelp_access\": \"free\",\n" .
					"      \"_hhelp_video_type\": \"none\",\n" .
					"      \"_hhelp_featured\": false\n" .
					"    }\n" .
					"  }'"
				);
			?></pre>
			<p>
				<a class="button" href="<?php echo esc_url( admin_url( 'profile.php#application-passwords-section' ) ); ?>">
					<?php esc_html_e( 'ساخت Application Password', 'hesabix-help' ); ?>
				</a>
			</p>

			<hr />
			<form method="post">
				<?php wp_nonce_field( 'hhelp_reseed' ); ?>
				<p class="description"><?php esc_html_e( 'بازسازی نمونه فقط مطالب نمونهٔ قبلی با meta مخصوص را حذف و دوباره می‌سازد.', 'hesabix-help' ); ?></p>
				<?php submit_button( __( 'بازسازی محتوای نمونه', 'hesabix-help' ), 'secondary', 'hhelp_reseed' ); ?>
			</form>
		</div>
		<?php
	}
}
