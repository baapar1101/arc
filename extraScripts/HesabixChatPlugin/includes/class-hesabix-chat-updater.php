<?php
/**
 * به‌روزرسانی: خواندن نسخه از فایل raw در مخزن + بسته zip از archive (آدرس ثابت)
 * — یا اختیاری: مانیفست JSON
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

/** اکشن Ajax بررسی نسخه */
const HESABIX_CHAT_UPDATE_AJAX_CHECK = 'hesabix_chat_update_check';

/** اکشن Ajax نصب/به‌روزرسانی از بسته */
const HESABIX_CHAT_UPDATE_AJAX_INSTALL = 'hesabix_chat_update_install';

/** برای check_ajax_referer و هر دو درخواست */
const HESABIX_CHAT_UPDATE_NONCE_ACTION = 'hesabix_chat_update_v1';

class Hesabix_Chat_Updater {

	/** ۱۲ ساعت */
	const CACHE_TTL = 43200;

	/** @var self|null */
	private static $instance = null;

	public static function init() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	public static function instance() {
		return self::$instance ?: self::init();
	}

	/**
	 * کلید کش وابسته به آدرس‌های به‌روزرسانی تا بعد از تغییر wp-config یا فیلتر، نتیجهٔ تازه گرفته شود.
	 *
	 * @return string
	 */
	private function get_update_cache_key() {
		return 'hesabix_chat_upd_' . md5( $this->get_raw_php_url() . '|' . $this->get_archive_zip_url() . '|' . $this->get_manifest_url() );
	}

	/**
	 * آرگومان‌های مشترک wp_remote_get (قابل تغییر با فیلتر برای میزبان‌های خاص).
	 *
	 * @param string $context raw_php|manifest|zip_head .
	 * @return array<string, mixed>
	 */
	private function remote_get_args( $context = 'raw_php' ) {
		$accept = 'text/plain';
		if ( 'manifest' === $context ) {
			$accept = 'application/json';
		}
		$args = array(
			'timeout'     => 15,
			'redirection' => 8,
			'sslverify'   => true,
			'headers'     => array(
				'Accept'     => $accept,
				'User-Agent' => 'HesabixChat-WordPress/' . HESABIX_CHAT_VERSION . '; ' . get_bloginfo( 'url' ),
			),
		);
		return (array) apply_filters( 'hesabix_chat_update_http_args', $args, $context );
	}

	/**
	 * @param string $body .
	 * @return string
	 */
	private function strip_utf8_bom( $body ) {
		$body = (string) $body;
		if ( strncmp( $body, "\xEF\xBB\xBF", 3 ) === 0 ) {
			return substr( $body, 3 );
		}
		return $body;
	}

	/**
	 * @return void
	 */
	private function __construct() {
		add_filter( 'pre_set_site_transient_update_plugins', array( $this, 'filter_update_transient' ) );
		add_filter( 'plugins_api', array( $this, 'plugin_info' ), 10, 3 );
		add_filter( 'upgrader_source_selection', array( $this, 'align_extracted_plugin_folder' ), 10, 4 );
		add_action( 'wp_ajax_' . HESABIX_CHAT_UPDATE_AJAX_CHECK, array( $this, 'ajax_update_check' ) );
		add_action( 'wp_ajax_' . HESABIX_CHAT_UPDATE_AJAX_INSTALL, array( $this, 'ajax_update_install' ) );
	}

	/**
	 * @return string
	 */
	public function get_raw_php_url() {
		$url = defined( 'HESABIX_CHAT_UPDATE_RAW_PHP_URL' ) ? (string) HESABIX_CHAT_UPDATE_RAW_PHP_URL : '';
		return esc_url_raw( (string) apply_filters( 'hesabix_chat_update_raw_php_url', $url ) );
	}

	/**
	 * @return string
	 */
	public function get_archive_zip_url() {
		$url = defined( 'HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL' ) ? (string) HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL : '';
		return esc_url_raw( (string) apply_filters( 'hesabix_chat_update_archive_zip_url', $url ) );
	}

	/**
	 * @return string
	 */
	public function get_manifest_url() {
		$url = defined( 'HESABIX_CHAT_UPDATE_MANIFEST_URL' ) ? (string) HESABIX_CHAT_UPDATE_MANIFEST_URL : '';
		return esc_url_raw( (string) apply_filters( 'hesabix_chat_update_manifest_url', $url ) );
	}

	/**
	 * آیا از raw + zip استفاده کنیم؟
	 *
	 * @return bool
	 */
	private function use_source_urls() {
		$r = $this->get_raw_php_url();
		$z = $this->get_archive_zip_url();
		if ( $r === '' || $z === '' ) {
			return false;
		}
		$ok_r = ( 0 === strpos( $r, 'https://' ) || 0 === strpos( $r, 'http://' ) );
		$ok_z = ( 0 === strpos( $z, 'https://' ) || 0 === strpos( $z, 'http://' ) );
		if ( ! $ok_r || ! $ok_z ) {
			return false;
		}
		return true;
	}

	/**
	 * استخراج نسخه و نیازمندی‌ها از محتوای hesabix-chat.php
	 *
	 * @param string $php
	 * @return array<string, string>
	 */
	private function parse_main_file_headers( $php ) {
		$out = array(
			'version'      => '',
			'requires'     => '',
			'requires_php' => '',
		);
		if ( preg_match( '/^\s*Version:\s*([0-9][0-9a-z.+-]*)\s*$/mi', $php, $m ) ) {
			$out['version'] = $m[1];
		} elseif ( preg_match( "/define\s*\(\s*['\"]HESABIX_CHAT_VERSION['\"]\s*,\s*['\"]([0-9][0-9a-z.+-]*)['\"]\s*\)/s", $php, $m ) ) {
			$out['version'] = $m[1];
		}
		if ( preg_match( '/^\s*Requires at least:\s*([0-9.]+)\s*$/mi', $php, $m ) ) {
			$out['requires'] = $m[1];
		}
		if ( preg_match( '/^\s*Requires PHP:\s*([0-9.]+)\s*$/mi', $php, $m ) ) {
			$out['requires_php'] = $m[1];
		}
		return $out;
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_info_from_source() {
		$url = $this->get_raw_php_url();
		$zip = $this->get_archive_zip_url();
		$resp = wp_remote_get( $url, $this->remote_get_args( 'raw_php' ) );
		if ( is_wp_error( $resp ) || (int) wp_remote_retrieve_response_code( $resp ) !== 200 ) {
			return null;
		}
		$body = $this->strip_utf8_bom( wp_remote_retrieve_body( $resp ) );
		if ( $body === null || $body === '' ) {
			return null;
		}
		if ( stripos( $body, '<html' ) !== false && stripos( $body, '<?php' ) === false ) {
			return null;
		}
		$headers = $this->parse_main_file_headers( $body );
		if ( $headers['version'] === '' ) {
			return null;
		}
		return array(
			'version'         => (string) $headers['version'],
			'download_url'    => $zip,
			'requires'        => (string) $headers['requires'],
			'tested'          => '',
			'requires_php'    => (string) $headers['requires_php'],
			'homepage'        => 'https://hesabix.ir',
			'last_updated'    => '',
			'name'            => 'Hesabix Web Chat',
			'sections'        => array(),
			'package_hash'    => '',
			'upgrade_notice'  => '',
			'banners'         => array(),
			'icons'           => array(),
			'icon_svg'        => '',
			'source'          => 'raw',
		);
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_info_from_json_manifest() {
		$url = $this->get_manifest_url();
		if ( $url === '' || ( 0 !== strpos( $url, 'https://' ) && 0 !== strpos( $url, 'http://' ) ) ) {
			return null;
		}
		$resp = wp_remote_get( $url, $this->remote_get_args( 'manifest' ) );
		if ( is_wp_error( $resp ) || (int) wp_remote_retrieve_response_code( $resp ) !== 200 ) {
			return null;
		}
		$body = wp_remote_retrieve_body( $resp );
		if ( $body === '' || $body === null ) {
			return null;
		}
		$data = json_decode( $body, true );
		if ( ! is_array( $data ) || empty( $data['version'] ) || empty( $data['download_url'] ) ) {
			return null;
		}
		$dl = esc_url_raw( (string) $data['download_url'] );
		if ( $dl === '' || ( 0 !== strpos( $dl, 'https://' ) && 0 !== strpos( $dl, 'http://' ) ) ) {
			return null;
		}
		return array(
			'version'         => (string) $data['version'],
			'download_url'    => $dl,
			'requires'        => isset( $data['requires'] ) ? (string) $data['requires'] : '',
			'tested'          => isset( $data['tested'] ) ? (string) $data['tested'] : '',
			'requires_php'    => isset( $data['requires_php'] ) ? (string) $data['requires_php'] : '',
			'homepage'        => isset( $data['homepage'] ) ? (string) $data['homepage'] : 'https://hesabix.ir',
			'last_updated'    => isset( $data['last_updated'] ) ? (string) $data['last_updated'] : '',
			'name'            => isset( $data['name'] ) ? (string) $data['name'] : 'Hesabix Web Chat',
			'sections'        => isset( $data['sections'] ) && is_array( $data['sections'] ) ? $data['sections'] : array(),
			'package_hash'    => isset( $data['package_hash'] ) ? (string) $data['package_hash'] : '',
			'upgrade_notice'  => isset( $data['upgrade_notice'] ) ? (string) $data['upgrade_notice'] : '',
			'banners'         => isset( $data['banners'] ) && is_array( $data['banners'] ) ? $data['banners'] : array(),
			'icons'           => isset( $data['icons'] ) && is_array( $data['icons'] ) ? $data['icons'] : array(),
			'icon_svg'        => isset( $data['icon_svg'] ) ? (string) $data['icon_svg'] : '',
			'source'          => 'json',
		);
	}

	/**
	 * خواندن متادادهٔ آخرین بستهٔ راه دور (نسخه + آدرس zip)؛ کش می‌شود حتی اگر محیط وردپرس/PHP نامناسب باشد تا تب تنظیمات بتواند نسخه را نشان دهد.
	 *
	 * @param bool $force_refresh .
	 * @return array<string, mixed>|null
	 */
	private function resolve_remote_package_cached( $force_refresh = false ) {
		$key = $this->get_update_cache_key();

		if ( $force_refresh || (bool) apply_filters( 'hesabix_chat_update_force_check', false ) ) {
			delete_site_transient( $key );
			delete_site_transient( 'hesabix_chat_update_manifest' );
		}

		$cached = get_site_transient( $key );
		if ( is_array( $cached ) && ! empty( $cached['version'] ) && ! empty( $cached['download_url'] ) ) {
			return $cached;
		}

		$info = null;
		if ( (bool) apply_filters( 'hesabix_chat_prefer_json_manifest', false ) && $this->get_manifest_url() !== '' ) {
			$info = $this->get_info_from_json_manifest();
		}
		if ( $info === null && $this->use_source_urls() ) {
			$info = $this->get_info_from_source();
		}
		if ( $info === null && $this->get_manifest_url() !== '' ) {
			$info = $this->get_info_from_json_manifest();
		}
		if ( $info === null ) {
			return null;
		}

		set_site_transient(
			$key,
			$info,
			(int) apply_filters( 'hesabix_chat_update_cache_ttl', self::CACHE_TTL )
		);
		return $info;
	}

	/**
	 * منطق پیشین: فقط اگر الزامات وردپرس و PHP برآورده شود برای هستهٔ به‌روزرسانی افزونه‌ها برمی‌گردد.
	 *
	 * @return array<string, mixed>|null
	 */
	private function get_remote_info() {
		$info = $this->resolve_remote_package_cached( false );
		if ( $info === null ) {
			return null;
		}
		if ( $info['requires'] !== '' && version_compare( get_bloginfo( 'version' ), $info['requires'], '<' ) ) {
			return null;
		}
		if ( $info['requires_php'] !== '' && version_compare( (string) PHP_VERSION, $info['requires_php'], '<' ) ) {
			return null;
		}
		return $info;
	}

	/**
	 * وضعیت برای تب «به‌روزرسانی» و Ajax.
	 *
	 * @param bool $force_refresh .
	 * @return array<string, scalar|bool|string>
	 */
	public function get_update_dashboard_state( $force_refresh = false ) {
		$current         = defined( 'HESABIX_CHAT_VERSION' ) ? (string) HESABIX_CHAT_VERSION : '';
		$uses_raw_zip    = $this->use_source_urls();
		$uses_manifest_o = $this->get_manifest_url() !== '';
		$configured      = $uses_raw_zip || $uses_manifest_o;

		$pkg             = $this->resolve_remote_package_cached( $force_refresh );
		$remote_str      = is_array( $pkg ) ? (string) ( $pkg['version'] ?? '' ) : '';
		$remote_loaded   = ( $remote_str !== '' );

		$download_url = is_array( $pkg ) ? (string) ( $pkg['download_url'] ?? '' ) : '';
		$req_wp       = is_array( $pkg ) ? (string) ( $pkg['requires'] ?? '' ) : '';
		$req_php      = is_array( $pkg ) ? (string) ( $pkg['requires_php'] ?? '' ) : '';
		$source       = is_array( $pkg ) ? (string) ( $pkg['source'] ?? '' ) : '';

		$wp_ok  = true;
		$php_ok = true;
		if ( $remote_loaded ) {
			if ( $req_wp !== '' && version_compare( get_bloginfo( 'version' ), $req_wp, '<' ) ) {
				$wp_ok = false;
			}
			if ( $req_php !== '' && version_compare( (string) PHP_VERSION, $req_php, '<' ) ) {
				$php_ok = false;
			}
		}

		$env_ok           = $wp_ok && $php_ok;
		$newer            = $remote_loaded && version_compare( $remote_str, $current, '>' );
		$update_available = $newer && $env_ok && $configured && $download_url !== '';

		return array(
			'current_version'            => $current,
			'remote_version'             => $remote_str,
			'remote_loaded'              => $remote_loaded,
			'configured'                 => $configured,
			'configured_raw_zip'         => $uses_raw_zip && $configured,
			'configured_manifest_only'   => $uses_manifest_o && ! $uses_raw_zip,
			'source_kind'                => $source,
			'download_available'         => ( $download_url !== '' ),
			'wp_compatible'              => $wp_ok,
			'php_compatible'             => $php_ok,
			'env_compatible'             => $env_ok,
			'requires_wp'                => $req_wp,
			'requires_php'               => $req_php,
			'update_available'           => $update_available,
			'newer_than_local'           => $newer,
			'can_install'                => self::current_user_can_update_via_ui(),
		);
	}

	/**
	 * حق انجام به‌روزرسانی از این صفحه.
	 *
	 * @return bool
	 */
	public static function current_user_can_update_via_ui() {
		return current_user_can( 'manage_options' ) && current_user_can( 'update_plugins' );
	}

	/**
	 * @param false|object $transient .
	 * @return object|false
	 */
	public function filter_update_transient( $transient ) {
		if ( ! is_object( $transient ) || empty( $transient->checked ) || ! is_array( $transient->checked ) ) {
			return $transient;
		}

		$plugin_file = plugin_basename( HESABIX_CHAT_FILE );
		if ( ! isset( $transient->checked[ $plugin_file ] ) ) {
			return $transient;
		}

		$info = $this->get_remote_info();
		if ( $info === null ) {
			return $transient;
		}

		$current = (string) $transient->checked[ $plugin_file ];
		$new     = (string) $info['version'];
		if ( ! version_compare( $new, $current, '>' ) ) {
			return $transient;
		}

		$home = ! empty( $info['homepage'] ) ? $info['homepage'] : 'https://hesabix.ir';
		$item = array(
			'id'           => $plugin_file,
			'slug'         => dirname( $plugin_file ),
			'plugin'       => $plugin_file,
			'new_version'  => $new,
			'url'          => esc_url( $home ),
			'package'      => (string) $info['download_url'],
			'tested'       => (string) ( $info['tested'] ?? '' ),
			'requires'     => (string) ( $info['requires'] ?? '' ),
			'requires_php' => (string) ( $info['requires_php'] ?? '' ),
		);
		if ( ! empty( $info['upgrade_notice'] ) ) {
			$item['upgrade_notice'] = (string) $info['upgrade_notice'];
		}
		if ( ! empty( $info['banners'] ) && is_array( $info['banners'] ) ) {
			$item['banners'] = $info['banners'];
		}
		if ( ! empty( $info['icons'] ) && is_array( $info['icons'] ) ) {
			$item['icons'] = $info['icons'];
		} elseif ( ! empty( $info['icon_svg'] ) ) {
			$item['icons'] = array( '1x' => (string) $info['icon_svg'] );
		}

		$transient->response[ $plugin_file ] = (object) $item;
		return $transient;
	}

	/**
	 * @param false|object|array $res .
	 * @param string             $action .
	 * @param object             $args .
	 * @return false|object|array
	 */
	public function plugin_info( $res, $action, $args ) {
		if ( 'plugin_information' !== $action || ! isset( $args->slug ) ) {
			return $res;
		}
		$dir = dirname( plugin_basename( HESABIX_CHAT_FILE ) );
		if ( (string) $args->slug !== $dir ) {
			return $res;
		}

		$info = $this->get_remote_info();
		if ( $info === null ) {
			$pkg = $this->resolve_remote_package_cached( false );
			if ( is_array( $pkg ) && isset( $pkg['version'] ) && (string) $pkg['version'] !== '' ) {
				$info = $pkg;
				if ( empty( $info['name'] ) ) {
					$info['name'] = 'Hesabix Web Chat';
				}
				if ( empty( $info['homepage'] ) ) {
					$info['homepage'] = 'https://hesabix.ir';
				}
			} else {
				$info = array(
					'version'      => HESABIX_CHAT_VERSION,
					'download_url' => '',
					'name'         => 'Hesabix Web Chat',
					'homepage'     => 'https://hesabix.ir',
					'last_updated' => '',
					'sections'     => array(),
				);
			}
		}

		$sections = array( 'description' => '' );
		if ( ! empty( $info['sections'] ) && is_array( $info['sections'] ) ) {
			foreach ( $info['sections'] as $k => $v ) {
				if ( is_string( $k ) && is_string( $v ) && $v !== '' ) {
					$sections[ $k ] = wp_kses_post( $v );
				}
			}
		}
		if ( ! empty( $info['source'] ) && 'raw' === $info['source'] ) {
			$sections['description'] = esc_html__( 'منبع به‌روزرسانی: نسخه از فایل اصلی در مخزن و بسته zip همان شاخه.', 'hesabix-chat' );
		} elseif ( empty( $sections['description'] ) ) {
			$sections['description'] = esc_html__( 'اتصال سایت وردپرس به چت وب CRM حسابیکس.', 'hesabix-chat' );
		}

		$out = (object) array(
			'name'          => $info['name'],
			'slug'          => $dir,
			'version'       => $info['version'],
			'author'        => '<a href="https://hesabix.ir" target="_blank" rel="noopener">Hesabix</a>',
			'homepage'      => ! empty( $info['homepage'] ) ? esc_url( (string) $info['homepage'] ) : 'https://hesabix.ir',
			'last_updated'  => ! empty( $info['last_updated'] ) ? (string) $info['last_updated'] : null,
			'download_link' => ! empty( $info['download_url'] ) ? esc_url( (string) $info['download_url'] ) : '',
			'sections'      => $sections,
			'banners'       => ! empty( $info['banners'] ) && is_array( $info['banners'] ) ? $info['banners'] : array(),
		);
		if ( ! empty( $info['icons'] ) && is_array( $info['icons'] ) ) {
			$out->icons = $info['icons'];
		}
		return $out;
	}

	/**
	 * Ajax: مقایسهٔ نسخهٔ نصب‌شده با نسخهٔ منتشرشده (بدون نشان‌دادن URL بسته به مرورگر).
	 */
	public function ajax_update_check() {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_send_json_error( array( 'message' => __( 'مجوز کافی نیست.', 'hesabix-chat' ) ), 403 );
		}

		check_ajax_referer( HESABIX_CHAT_UPDATE_NONCE_ACTION, 'nonce' );

		$refresh = isset( $_POST['refresh'] )
			&& ( '1' === (string) wp_unslash( $_POST['refresh'] ) || 'true' === (string) wp_unslash( $_POST['refresh'] ) );

		wp_send_json_success( $this->get_update_dashboard_state( $refresh ) );
	}

	/**
	 * Ajax: نصب/به‌روزرسانی از بستهٔ راه دور؛ پس از موفقیت کاربر با ریفرش صفحه نسخهٔ جدید را می‌بیند.
	 */
	public function ajax_update_install() {
		if ( ! self::current_user_can_update_via_ui() ) {
			wp_send_json_error( array( 'message' => __( 'مجوز به‌روزرسانی افزونه را ندارید.', 'hesabix-chat' ) ), 403 );
		}

		check_ajax_referer( HESABIX_CHAT_UPDATE_NONCE_ACTION, 'nonce' );

		$this->purge_update_caches_before_install();

		$pkg = $this->resolve_remote_package_cached( true );
		if ( ! is_array( $pkg ) || empty( $pkg['download_url'] ) ) {
			wp_send_json_error( array( 'message' => __( 'دریافت اطلاعات بستهٔ به‌روزرسانی ناموفق بود یا منبعی تنظیم نشده.', 'hesabix-chat' ) ) );
		}

		$download = esc_url_raw( (string) $pkg['download_url'] );
		if ( strpos( $download, 'http://' ) !== 0 && strpos( $download, 'https://' ) !== 0 ) {
			wp_send_json_error( array( 'message' => __( 'آدرس بستهٔ نامعتبر است.', 'hesabix-chat' ) ) );
		}

		$plugin_file = plugin_basename( HESABIX_CHAT_FILE );
		$current     = defined( 'HESABIX_CHAT_VERSION' ) ? (string) HESABIX_CHAT_VERSION : '';
		$new_version = isset( $pkg['version'] ) ? (string) $pkg['version'] : '';

		if ( '' === $new_version || '' === $current ) {
			wp_send_json_error( array( 'message' => __( 'تشخیص نسخه ممکن نیست.', 'hesabix-chat' ) ) );
		}

		if ( ! version_compare( $new_version, $current, '>' ) ) {
			wp_send_json_error( array( 'message' => __( 'به‌روزرسانی جدیدی نسبت به نسخهٔ فعلی در دسترس نیست.', 'hesabix-chat' ) ) );
		}

		$requires = isset( $pkg['requires'] ) ? (string) $pkg['requires'] : '';
		if ( $requires !== '' && version_compare( get_bloginfo( 'version' ), $requires, '<' ) ) {
			wp_send_json_error(
				array(
					'message' => sprintf(
					/* translators: %s: minimum WP version required */
						__( 'وردپرس باید حداقل نسخهٔ %s باشد.', 'hesabix-chat' ),
						$requires
					),
				)
			);
		}
		$requires_php = isset( $pkg['requires_php'] ) ? (string) $pkg['requires_php'] : '';
		if ( $requires_php !== '' && version_compare( (string) PHP_VERSION, $requires_php, '<' ) ) {
			wp_send_json_error(
				array(
					'message' => sprintf(
					/* translators: %s: minimum PHP version required */
						__( 'PHP باید حداقل نسخهٔ %s باشد.', 'hesabix-chat' ),
						$requires_php
					),
				)
			);
		}

		if ( function_exists( 'wp_raise_memory_limit' ) ) {
			wp_raise_memory_limit( 'admin' );
		}
		if ( function_exists( 'wc_set_time_limit' ) ) {
			wc_set_time_limit( 0 );
		} elseif ( function_exists( 'set_time_limit' ) ) {
			// phpcs:ignore Squiz.PHP.DiscouragedFunctions.Discouraged -- طول کشیدن دریافت بستهٔ zip
			@set_time_limit( 600 );
		}

		require_once ABSPATH . 'wp-admin/includes/file.php';
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
		require_once ABSPATH . 'wp-admin/includes/class-wp-upgrader.php';

		if ( ! class_exists( 'Automatic_Upgrader_Skin' ) ) {
			wp_send_json_error( array( 'message' => __( 'کلاس‌های به‌روزرسانی وردپرس در دسترس نیستند.', 'hesabix-chat' ) ) );
		}

		if ( false === WP_Filesystem() ) {
			wp_send_json_error(
				array(
					'message' => __( 'اتصال به فایل سیستم نشد. روش دسترسی به فایل‌ها (مانند FTP) را از طریق wp-config یا پشتیبان هاست تنظیم کنید.', 'hesabix-chat' ),
				)
			);
		}

		$skin     = new Automatic_Upgrader_Skin();
		$upgrader = new Plugin_Upgrader( $skin );

		$result = $upgrader->run(
			array(
				'package'             => $download,
				'destination'         => WP_PLUGIN_DIR,
				'clear_destination'   => true,
				'clear_working'       => true,
				'clear_update_cache'  => false,
				'is_multi'            => false,
				'hook_extra'          => array(
					'plugin' => $plugin_file,
				),
			)
		);

		delete_site_transient( $this->get_update_cache_key() );
		delete_site_transient( 'hesabix_chat_update_manifest' );

		if ( false === $result || is_wp_error( $result ) ) {
			$msg = is_wp_error( $result )
				? $result->get_error_message()
				: __( 'به‌روزرسانی افزونه با خطا متوقف شد.', 'hesabix-chat' );
			if ( isset( $skin ) && isset( $skin->result ) && is_wp_error( $skin->result ) ) {
				$skin_msg = $skin->result->get_error_message();
				if ( '' !== $skin_msg && $skin_msg !== $msg ) {
					$msg = $skin_msg . ' — ' . $msg;
				}
			}
			wp_send_json_error( array( 'message' => $msg ), 500 );
		}

		wp_clean_plugins_cache();

		wp_send_json_success(
			array(
				'message'     => __( 'به‌روزرسانی با موفقیت انجام شد؛ صفحه به‌روز می‌شود…', 'hesabix-chat' ),
				'new_version' => $new_version,
			)
		);
	}

	/**
	 * پیش از یک نصب کامل کش‌های وابسته را خالی کن تا خطای کش قدیمی نباشیم.
	 */
	private function purge_update_caches_before_install() {
		delete_site_transient( $this->get_update_cache_key() );
		delete_site_transient( 'hesabix_chat_update_manifest' );
	}

	/**
	 * پوشهٔ داخل zip آرشیو گیت‌معمولاً `نامپروژه-شاخه` است؛ به نام پوشهٔ نصب‌شده روی وردپرس یکی می‌کنیم.
	 *
	 * @param string|WP_Error      $source       .
	 * @param string|WP_Error      $remote_source .
	 * @param \WP_Upgrader         $upgrader     .
	 * @param array<string, mixed> $extra        .
	 * @return string|WP_Error
	 */
	public function align_extracted_plugin_folder( $source, $remote_source, $upgrader, $extra = array() ) { // phpcs:ignore VariableAnalysis.CodeAnalysis.VariableAnalysis
		if ( is_wp_error( $source ) || ! is_string( $source ) || $source === '' ) {
			return $source;
		}
		if ( empty( $extra['plugin'] ) || (string) $extra['plugin'] !== plugin_basename( HESABIX_CHAT_FILE ) ) {
			return $source;
		}

		$expected_name = dirname( (string) $extra['plugin'] );
		if ( basename( $source ) === $expected_name ) {
			return $source;
		}

		global $wp_filesystem;
		if ( ! $wp_filesystem || ! is_object( $wp_filesystem ) ) {
			return $source;
		}

		$new = trailingslashit( dirname( $source ) ) . $expected_name;
		if ( $wp_filesystem->exists( $new ) ) {
			$wp_filesystem->delete( $new, true );
		}
		if ( $wp_filesystem->move( $source, $new ) ) {
			return $new;
		}
		return $source;
	}
}
