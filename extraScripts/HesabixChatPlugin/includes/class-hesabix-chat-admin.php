<?php
/**
 * صفحه تنظیمات ادمین.
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hesabix_Chat_Admin
 */
class Hesabix_Chat_Admin {

	const OPTION_NAME = 'hesabix_chat_options';

	/**
	 * user meta: نسخهٔ راه‌دوری که کاربر برای اعلان «به‌روزرسانی» در پیشخوان دکمهٔ بی‌خیال زده است؛ تا انتشار بعدی تکرار نشود.
	 */
	const USER_META_DISMISSED_REMOTE_NOTICE_VER = 'hesabix_chat_dismissed_dashboard_update_remote_ver';

	const DISMISS_UPDATE_NOTICE_NONCE_ACTION = 'hesabix_chat_dismiss_update_notice';

	/**
	 * پیش‌فرض‌ها.
	 *
	 * @return array<string, mixed>
	 */
	public static function defaults() {
		return array(
			'api_base'             => 'https://hsxn.hesabix.ir',
			'public_key'           => '',
			'load_mode'            => 'global',
			'button_position'      => 'bottom-right',
			'button_color'         => '#4f46e5',
			'button_text_color'    => '#ffffff',
			'button_text'          => __( 'گفتگو با پشتیبانی', 'hesabix-chat' ),
			'theme'                => 'light',
			'panel_width'          => 380,
			'panel_height'         => 520,
			'z_index'              => 99999,
			'offset_bottom'        => 24,
			'offset_side_desktop'  => 24,
			'offset_side_mobile'   => 24,
			'margin_left_desktop'  => 0,
			'margin_right_desktop' => 0,
			'margin_left_mobile'   => 0,
			'margin_right_mobile'  => 0,
			'hide_launcher_front'  => 0,
			'hide_launcher_post_ids' => '',
			'hide_launcher_paths'  => '',
			'border_radius'        => 16,
			'chat_title'           => __( 'پشتیبانی', 'hesabix-chat' ),
			'welcome_message'      => __( 'به بخش فروش خوش آمدید! چه کمکی از دستم برمی‌آید؟', 'hesabix-chat' ),
			'response_time_text'   => __( 'ما معمولاً در کمتر از یک ساعت پاسخ می‌دهیم.', 'hesabix-chat' ),
			'ui_preset'            => 'default',
			'header_logo_url'      => '',
			'rtl'                  => 'auto',
			'show_file_upload'     => 0,
			'show_voice_message'  => 0,
			'email_field'         => 'required',
			'show_page_context'   => 0,
			'quick_replies_text'  => '',
			'agent_reply_sound'   => '',
			'launcher_idle_animation'     => 'none',
			'launcher_attention_delay_sec' => 3,
			'open_panel_on_load'          => 0,
			'open_panel_delay_sec'        => 0,
			'remember_panel_between_pages' => 1,
			'show_agent_join_ws'          => 1,
			'show_agent_attendance_on_read' => 0,
			'slow_reply_timeout_sec'      => 0,
			'slow_reply_message'         => __( 'با عرض پوزش، در این لحظه پاسخ سریع نمی‌توانیم بدهیم. پیام خود را بگذارید؛ همکاران تا لحظاتی دیگر پاسخ می‌دهند.', 'hesabix-chat' ),
			'agent_join_notice_template'  => __( '%s به اتاق این گفتگو در پشتیبان متصل شد', 'hesabix-chat' ),
			'agent_read_notice_template'  => __( '%s به گفتگو پیوست', 'hesabix-chat' ),
			'operator_label_mode'         => 'real',
			'operator_unified_display_name' => __( 'پشتیبان', 'hesabix-chat' ),
			'show_powered_by_hesabix'        => 1,
			'powered_by_hesabix_url'       => 'https://hesabix.ir',
			'powered_by_hesabix_text'      => __( 'قدرت گرفته از حسابیکس', 'hesabix-chat' ),
			'widget_debug_logging'          => 0,
			'widget_custom_css'             => '',
			'widget_tpl_classes_host'       => '',
			'widget_tpl_classes_root'       => '',
			'widget_tpl_classes_launcher_wrap' => '',
			'widget_tpl_classes_launcher' => '',
			'widget_tpl_classes_panel'      => '',
			'widget_tpl_classes_surface'    => '',
			'business_hours_enabled'       => 0,
			'business_hours_message'       => __( 'در حال حاضر خارج از ساعات حضور اپراتور هستیم؛ پیام شما ثبت شد و در اولین فرصت پاسخ داده می‌شود.', 'hesabix-chat' ),
			'business_hours_tz_mode'         => 'wp',
			'business_hours_timezone'        => '',
			'business_hours_holidays_raw'    => '',
			'business_hours_holidays'        => array(),
			'business_hours_schedule'        => self::default_business_hours_schedule(),
		);
	}

	/** حداکثر طول متن CSS سفارشی در اپشن‌ها. */
	const WIDGET_CUSTOM_CSS_MAX_LEN = 65000;

	/**
	 * حذف الگوی خطرناک یا خروج از context در CSS دلخواه.
	 *
	 * @param string $css .
	 * @return string
	 */
	public static function sanitize_widget_custom_css( $css ) {
		$css = is_string( $css ) ? $css : '';
		$css = str_replace( "\0", '', $css );
		if ( strlen( $css ) > self::WIDGET_CUSTOM_CSS_MAX_LEN ) {
			$css = substr( $css, 0, self::WIDGET_CUSTOM_CSS_MAX_LEN );
		}
		// رد @import خارجی؛ جلوگیری از شکستن تگ استایل.
		$css = preg_replace( '/@import\b[^;]*;/i', '', $css );
		$needle = array( 'expression(', 'javascript:', '</style', '<script', '-moz-binding', 'behavior:', 'binding:' );
		$css    = str_ireplace( $needle, '', $css );

		return $css;
	}

	/**
	 * توکن کلاس برای HTML class؛ فقط کاراکترهای ایمن؛ حداکثر ۲۰ توکن؛ هر توکن تا ۶۴ نویسه.
	 *
	 * @param string $raw .
	 * @return string توکن‌ها با فاصله
	 */
	public static function sanitize_widget_class_tokens( $raw ) {
		$s   = preg_split( '/[\s,]+/u', (string) $raw, -1, PREG_SPLIT_NO_EMPTY );
		$out = array();
		foreach ( $s as $t ) {
			if ( count( $out ) >= 20 ) {
				break;
			}
			$t = preg_replace( '/[^a-zA-Z0-9_-]/', '', $t );
			if ( $t !== '' ) {
				if ( function_exists( 'mb_strlen' ) && mb_strlen( $t ) > 64 ) {
					continue;
				}
				if ( ! function_exists( 'mb_strlen' ) && strlen( $t ) > 64 ) {
					continue;
				}
				$out[] = $t;
			}
		}

		return implode( ' ', array_unique( $out ) );
	}

	/**
	 * مقدار صفت class برای ظرف #hesabix-chat-host با کلاس‌های پایه.
	 *
	 * @param array<string, mixed> $o .
	 * @param bool                 $shortcode .
	 * @return string
	 */
	public static function widget_host_class_attribute_value( array $o, $shortcode ) {
		$base = $shortcode ? 'hesabix-chat-host hesabix-chat-host--shortcode' : 'hesabix-chat-host';
		$ex   = self::sanitize_widget_class_tokens( (string) ( $o['widget_tpl_classes_host'] ?? '' ) );

		return trim( $base . ( $ex !== '' ? ' ' . $ex : '' ) );
	}

	/**
	 * کلاس‌های اضافی برای هدف قرارگرفته در ویجیت JS؛ خروجی فیلترپذیر ایمن‌شدهٔ دوباره.
	 *
	 * @param array<string, mixed> $o .
	 * @return array<string, string>
	 */
	public static function template_extra_classes_bundle( array $o ) {
		$bundle = array(
			'root'           => self::sanitize_widget_class_tokens( (string) ( $o['widget_tpl_classes_root'] ?? '' ) ),
			'launcherWrap'   => self::sanitize_widget_class_tokens( (string) ( $o['widget_tpl_classes_launcher_wrap'] ?? '' ) ),
			'launcher'       => self::sanitize_widget_class_tokens( (string) ( $o['widget_tpl_classes_launcher'] ?? '' ) ),
			'panel'          => self::sanitize_widget_class_tokens( (string) ( $o['widget_tpl_classes_panel'] ?? '' ) ),
			'surface'        => self::sanitize_widget_class_tokens( (string) ( $o['widget_tpl_classes_surface'] ?? '' ) ),
		);
		$filtered = apply_filters( 'hesabix_chat_tpl_extra_classes', $bundle, $o );
		if ( ! is_array( $filtered ) ) {
			return $bundle;
		}
		foreach ( array_keys( $bundle ) as $bk ) {
			if ( isset( $filtered[ $bk ] ) ) {
				$bundle[ $bk ] = self::sanitize_widget_class_tokens( (string) $filtered[ $bk ] );
			}
		}

		return $bundle;
	}

	/**
	 * برنامه پیش‌فرض: جمعه تعطیل (۵ در date('w') PHP)؛ بقیهٔ روزها ۹ تا ۱۷ — منطبق با هفتهٔ رایج در ایران.
	 *
	 * @return array<int, array{closed: bool, open: string, close: string}>
	 */
	public static function default_business_hours_schedule() {
		$rows = array();
		for ( $d = 0; $d < 7; $d++ ) {
			// date('w') در PHP: ۰ یکشنبه … ۵ جمعه، ۶ شنبه.
			$closed = ( 5 === $d );
			$rows[] = array(
				'closed' => $closed,
				'open'   => '09:00',
				'close'  => '17:00',
			);
		}

		return $rows;
	}

	/**
	 * @param mixed $raw .
	 * @return array<int, array{closed: bool, open: string, close: string}>
	 */
	public static function normalize_business_hours_schedule( $raw ) {
		if ( ! is_array( $raw ) ) {
			return self::default_business_hours_schedule();
		}
		$list = array_values( $raw );
		if ( count( $list ) < 7 ) {
			return self::default_business_hours_schedule();
		}
		$out = array();
		for ( $i = 0; $i < 7; $i++ ) {
			$r = isset( $list[ $i ] ) && is_array( $list[ $i ] ) ? $list[ $i ] : array();
			$cd = ! empty( $r['closed'] );
			$op = self::sanitize_time_hm( isset( $r['open'] ) ? (string) $r['open'] : '' );
			$cl = self::sanitize_time_hm( isset( $r['close'] ) ? (string) $r['close'] : '' );
			if ( '' === $op ) {
				$op = '09:00';
			}
			if ( '' === $cl ) {
				$cl = '17:00';
			}
			$om = self::minutes_from_hm( $op );
			$cm = self::minutes_from_hm( $cl );
			if ( false === $om ) {
				$op = '09:00';
				$om = self::minutes_from_hm( $op );
			}
			if ( false === $cm ) {
				$cl = '17:00';
				$cm = self::minutes_from_hm( $cl );
			}
			if ( false !== $om && false !== $cm && $om === $cm ) {
				$cd = true;
			}
			if ( false !== $om && false !== $cm && $cm < $om ) {
				$cd = true;
			}

			$out[] = array(
				'closed' => $cd,
				'open'   => $op,
				'close'  => $cl,
			);
		}

		return $out;
	}

	/**
	 * @param string $s .
	 * @return string HH:MM
	 */
	public static function sanitize_time_hm( $s ) {
		$s = trim( (string) $s );
		if ( '' === $s ) {
			return '';
		}
		if ( ! preg_match( '/^\s*(\d{1,2})\s*:\s*(\d{2})\s*$/', $s, $m ) ) {
			return '';
		}
		$h = max( 0, min( 23, (int) $m[1] ) );
		$i = max( 0, min( 59, (int) $m[2] ) );

		return sprintf( '%02d:%02d', $h, $i );
	}

	/**
	 * @param string $hm HH:MM.
	 * @return int|false دقیقه از نیمه‌شب؛ نادرست = false.
	 */
	public static function minutes_from_hm( $hm ) {
		if ( '' === $hm || ! preg_match( '/^(\d{2}):(\d{2})$/', $hm, $m ) ) {
			return false;
		}

		return (int) $m[1] * 60 + (int) $m[2];
	}

	/**
	 * هر خط تاریخ YYYY-MM-DD یا با /.
	 *
	 * @param string $textarea .
	 * @return string[] تاریخ‌های یکتا به صورت Y-m-d.
	 */
	public static function parse_business_hours_holidays( $textarea ) {
		$lines = preg_split( '/\R/u', (string) $textarea );
		if ( false === $lines ) {
			$lines = array();
		}
		$saw = array();
		foreach ( $lines as $line ) {
			$line = trim( $line );
			if ( '' === $line ) {
				continue;
			}
			if ( ! preg_match( '/^\s*(\d{4})[-/](\d{1,2})[-/](\d{1,2})\s*$/', $line, $m ) ) {
				continue;
			}
			$y = (int) $m[1];
			$mo = (int) $m[2];
			$d = (int) $m[3];
			if ( $y < 1970 || $y > 2100 ) {
				continue;
			}
			if ( ! checkdate( $mo, $d, $y ) ) {
				continue;
			}
			$ymd           = sprintf( '%04d-%02d-%02d', $y, $mo, $d );
			$saw[ $ymd ] = true;
		}

		return array_keys( $saw );
	}

	/**
	 * متن پیام خارج از وقت برای بازدیدکننده (خلاصه یک‌خط؛ چندخط در ورودی جمع می‌شود).
	 *
	 * @param array<string, mixed> $o .
	 * @return string
	 */
	public static function business_hours_visitor_message_line( array $o ) {
		$raw = isset( $o['business_hours_message'] ) ? sanitize_textarea_field( (string) $o['business_hours_message'] ) : '';
		$raw = trim( preg_replace( "/[\r\n]+/", ' ', $raw ) );
		if ( function_exists( 'mb_strlen' ) && mb_strlen( $raw ) > 900 ) {
			$raw = mb_substr( $raw, 0, 900 ) . '…';
		} elseif ( strlen( $raw ) > 900 ) {
			$raw = substr( $raw, 0, 900 ) . '…';
		}

		return $raw;
	}

	/**
	 * فایل‌های صوتی مجاز در assets/sounds (برای اعلان پیام پشتیبان).
	 *
	 * @return string[] نام فایل‌ها
	 */
	public static function list_agent_reply_sound_files() {
		$dir = HESABIX_CHAT_PATH . 'assets/sounds/';
		if ( ! is_dir( $dir ) ) {
			return array();
		}
		$ext_ok = array( 'mp3' => true, 'm4a' => true, 'wav' => true, 'ogg' => true );
		$out    = array();
		$dh     = opendir( $dir );
		if ( ! $dh ) {
			return array();
		}
		while ( false !== ( $f = readdir( $dh ) ) ) {
			if ( $f === '.' || $f === '..' || $f === 'index.php' ) {
				continue;
			}
			$ext = strtolower( pathinfo( $f, PATHINFO_EXTENSION ) );
			if ( isset( $ext_ok[ $ext ] ) ) {
				$out[] = $f;
			}
		}
		closedir( $dh );
		sort( $out, SORT_NATURAL | SORT_FLAG_CASE );
		return $out;
	}

	/**
	 * تطبیق نام فایل صدا با لیست واقعی روی دیسک (بدون sanitize_file_name که پرانتز و … را عوض می‌کند).
	 *
	 * @param string   $raw           مقدار ارسال‌شده از فرم.
	 * @param string[] $allowed_files خروجی list_agent_reply_sound_files().
	 * @return string نام دقیق فایل از دیسک یا رشته خالی.
	 */
	public static function resolve_agent_reply_sound_choice( $raw, array $allowed_files ) {
		$name = basename( str_replace( '\\', '/', trim( (string) $raw ) ) );
		if ( $name === '' || $name === '.' || $name === '..' ) {
			return '';
		}
		foreach ( $allowed_files as $f ) {
			if ( is_string( $f ) && strcasecmp( $name, $f ) === 0 ) {
				return $f;
			}
		}
		return '';
	}

	/**
	 * هر خط: پرسش|پاسخ (اولین | جداکننده). حداکثر ۱۲ مورد.
	 *
	 * @param string $raw .
	 * @return array<int, array{q: string, a: string}>
	 */
	public static function parse_quick_replies_text( $raw ) {
		$lines = preg_split( '/\R/u', (string) $raw );
		$out   = array();
		foreach ( $lines as $line ) {
			if ( count( $out ) >= 12 ) {
				break;
			}
			$line = trim( $line );
			if ( $line === '' ) {
				continue;
			}
			$parts = explode( '|', $line, 2 );
			$q     = trim( $parts[0] );
			$a     = isset( $parts[1] ) ? trim( $parts[1] ) : '';
			if ( $q === '' || $a === '' ) {
				continue;
			}
			if ( function_exists( 'mb_substr' ) ) {
				$q = mb_substr( $q, 0, 200 );
				$a = mb_substr( $a, 0, 2000 );
			} else {
				$q = substr( $q, 0, 200 );
				$a = substr( $a, 0, 2000 );
			}
			$out[] = array(
				'q' => $q,
				'a' => $a,
			);
		}
		return $out;
	}

	/**
	 * @return array<string, mixed>
	 */
	public static function get_options() {
		$opts = get_option( self::OPTION_NAME, array() );
		if ( ! is_array( $opts ) ) {
			$opts = array();
		}
		$out = array_replace_recursive( self::defaults(), $opts );
		if ( isset( $opts['offset_side'] ) && ! isset( $opts['offset_side_desktop'] ) && ! isset( $opts['offset_side_mobile'] ) ) {
			$legacy = max( 0, min( 200, (int) $opts['offset_side'] ) );
			$out['offset_side_desktop'] = $legacy;
			$out['offset_side_mobile']  = $legacy;
		}
		$sound_ok = self::list_agent_reply_sound_files();
		$resolved = self::resolve_agent_reply_sound_choice( (string) ( $out['agent_reply_sound'] ?? '' ), $sound_ok );
		$out['agent_reply_sound'] = $resolved;
		$allowed_th               = array( 'light', 'dark', 'cream', 'ocean', 'midnight' );
		if ( ! in_array( (string) ( $out['theme'] ?? 'light' ), $allowed_th, true ) ) {
			$out['theme'] = 'light';
		}
		$olm_chk = (string) ( $out['operator_label_mode'] ?? 'real' );
		if ( ! in_array( $olm_chk, array( 'real', 'unified' ), true ) ) {
			$out['operator_label_mode'] = 'real';
		}

		$out['business_hours_schedule'] = self::normalize_business_hours_schedule( isset( $out['business_hours_schedule'] ) ? $out['business_hours_schedule'] : null );
		$tzm = isset( $out['business_hours_tz_mode'] ) ? (string) $out['business_hours_tz_mode'] : 'wp';
		$out['business_hours_tz_mode'] = ( 'custom' === $tzm ) ? 'custom' : 'wp';
		$raw_h = isset( $out['business_hours_holidays_raw'] ) ? (string) $out['business_hours_holidays_raw'] : '';
		if ( '' !== trim( $raw_h ) ) {
			$out['business_hours_holidays'] = self::parse_business_hours_holidays( $raw_h );
		} else {
			$ho = isset( $out['business_hours_holidays'] ) && is_array( $out['business_hours_holidays'] ) ? $out['business_hours_holidays'] : array();
			$clean = array();
			foreach ( $ho as $hx ) {
				if ( is_string( $hx ) && preg_match( '/^\d{4}-\d{2}-\d{2}$/', $hx ) ) {
					$clean[ $hx ] = true;
				}
			}
			$out['business_hours_holidays'] = array_keys( $clean );
			sort( $out['business_hours_holidays'] );
		}

		return $out;
	}

	/**
	 * @param string $raw .
	 * @return int[]
	 */
	public static function parse_post_id_list( $raw ) {
		$out = array();
		foreach ( preg_split( '/[\s,]+/', (string) $raw, -1, PREG_SPLIT_NO_EMPTY ) as $p ) {
			$n = (int) $p;
			if ( $n > 0 ) {
				$out[] = $n;
			}
		}
		return array_values( array_unique( $out ) );
	}

	/**
	 * @param string $raw .
	 * @return string[]
	 */
	public static function parse_path_prefix_lines( $raw ) {
		$lines = preg_split( '/\R/u', (string) $raw );
		$out   = array();
		foreach ( $lines as $line ) {
			$line = trim( $line );
			if ( $line === '' ) {
				continue;
			}
			if ( isset( $line[0] ) && $line[0] !== '/' ) {
				$line = '/' . $line;
			}
			$line = untrailingslashit( $line );
			if ( $line === '' ) {
				continue;
			}
			$out[] = $line;
		}
		return array_values( array_unique( $out ) );
	}

	public function __construct() {
		add_action( 'admin_init', array( $this, 'register_settings' ) );
		add_action( 'admin_menu', array( $this, 'add_menu' ) );
		add_action( 'admin_enqueue_scripts', array( $this, 'admin_assets' ) );
		add_action( 'admin_action_hesabix_clear_widget_debug_log', array( $this, 'action_clear_widget_debug_log' ) );
		add_action( 'admin_action_hesabix_export_widget_debug_log', array( $this, 'action_export_widget_debug_log' ) );
		add_action( 'admin_notices', array( $this, 'maybe_render_dashboard_update_notice' ) );
		add_action( 'admin_post_hesabix_chat_dismiss_update_notice', array( $this, 'handle_post_dismiss_update_notice' ) );
	}

	public function add_menu() {
		add_options_page(
			__( 'چت حسابیکس', 'hesabix-chat' ),
			__( 'چت حسابیکس', 'hesabix-chat' ),
			'manage_options',
			'hesabix-chat',
			array( $this, 'render_page' )
		);
	}

	/**
	 * @param string $s .
	 * @return bool
	 */
	private static function plausible_plugin_version_slug( $s ) {
		return is_string( $s ) && $s !== '' && preg_match( '/^[0-9][0-9a-z.+-]*$/i', $s ) === 1;
	}

	/**
	 * اعلان پیشخوان در صورت وجود نسخهٔ جدیدتر در منبع (متفاوت از نسخهٔ کنونی نصب‌شده).
	 */
	public function maybe_render_dashboard_update_notice() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		// صفحهٔ تنظیمات خود افزونه: آن‌جا تب «به‌روزرسانی» هست؛ اعلان تکراری نباشد.
		if ( isset( $_GET['page'] ) && 'hesabix-chat' === sanitize_text_field( wp_unslash( (string) $_GET['page'] ) ) ) {
			return;
		}

		if ( ! class_exists( 'Hesabix_Chat_Updater', false ) ) {
			return;
		}

		$upd = Hesabix_Chat_Updater::instance()->get_update_dashboard_state( false );

		if ( empty( $upd['configured'] ) || empty( $upd['remote_loaded'] ) || empty( $upd['newer_than_local'] ) ) {
			return;
		}

		$remote_ver = isset( $upd['remote_version'] ) ? trim( (string) $upd['remote_version'] ) : '';
		$local_ver  = isset( $upd['current_version'] ) ? trim( (string) $upd['current_version'] ) : '';
		if ( ! self::plausible_plugin_version_slug( $remote_ver ) ) {
			return;
		}

		$dismissed = get_user_meta( get_current_user_id(), self::USER_META_DISMISSED_REMOTE_NOTICE_VER, true );
		$dismissed = is_string( $dismissed ) ? trim( $dismissed ) : '';
		if ( '' !== $dismissed && $dismissed === $remote_ver ) {
			return;
		}

		$settings_update_url = admin_url( 'options-general.php?page=hesabix-chat#hesabix-tab-update' );

		$notice_class = ! empty( $upd['update_available'] ) ? 'notice-info' : 'notice-warning';
		if ( ! empty( $upd['update_available'] ) ) {
			/* translators: 1: installed version, 2: newer remote version */
			$body = sprintf( __( 'افزونهٔ «چت حسابیکس» را الان نسخهٔ %1$s دارید؛ نسخهٔ %2$s در منبع به‌روزرسانی موجود است. از تنظیمات افزونه و تب «به‌روزرسانی افزونه» می‌توانید آن را نصب کنید.', 'hesabix-chat' ), $local_ver !== '' ? $local_ver : '—', $remote_ver );
		} elseif ( empty( $upd['env_compatible'] ) ) {
			/* translators: 1: installed version, 2: remote version */
			$body = sprintf( __( 'نسخهٔ %2$s «چت حسابیکس» در منبع منتشر شده؛ نصب‌شدهٔ شما %1$s است، اما نسخهٔ وردپرس یا PHP با الزامات اعلام‌شده جور نیست. از تب «به‌روزرسانی افزونه» جزئیات را ببینید.', 'hesabix-chat' ), $local_ver !== '' ? $local_ver : '—', $remote_ver );
		} else {
			/* translators: 1: installed version, 2: remote version */
			$body = sprintf( __( 'نسخهٔ %2$s «چت حسابیکس» در منبع دیده می‌شود (شما %1$s). اگر ابزار نصب در دسترس نباشد از تب «به‌روزرسانی افزونه» کمک بگیرید.', 'hesabix-chat' ), $local_ver !== '' ? $local_ver : '—', $remote_ver );
		}

		$dismiss_base = wp_nonce_url(
			admin_url( 'admin-post.php?action=hesabix_chat_dismiss_update_notice&remote_ver=' . rawurlencode( $remote_ver ) ),
			self::DISMISS_UPDATE_NOTICE_NONCE_ACTION
		);

		echo '<div class="' . esc_attr( 'notice ' . $notice_class . ' hesabix-chat-dashboard-update-notice' ) . '"><p><strong>'
			. esc_html__( 'به‌روزرسانی افزونه چت حسابیکس', 'hesabix-chat' )
			. '</strong></p><p>' . esc_html( $body ) . '</p><p style="margin-top:12px;display:flex;flex-wrap:wrap;gap:10px;align-items:center;">'
			. '<a href="' . esc_url( $settings_update_url ) . '" class="button button-primary">' . esc_html__( 'رفتن به به‌روزرسانی افزونه', 'hesabix-chat' ) . '</a>'
			. '<a href="' . esc_url( $dismiss_base ) . '" class="button button-secondary">' . esc_html__( 'بی‌خیال تا نسخهٔ بعد', 'hesabix-chat' ) . '</a>'
			. '<span class="description">' . esc_html__( 'تا وقتی نسخهٔ جدیدی در منبع منتشر نشود، با «بی‌خیال» این پیام نشان داده نمی‌شود.', 'hesabix-chat' ) . '</span></p></div>';
	}

	/**
	 * ذخیرهٔ «بی‌خیال» برای نسخهٔ راه‌دور کنونی؛ بعد از انتشار نسخهٔ بعدی دوباره اعلان ظاهر می‌شود.
	 */
	public function handle_post_dismiss_update_notice() {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'مجوز دسترسی ندارید.', 'hesabix-chat' ) );
		}
		check_admin_referer( self::DISMISS_UPDATE_NOTICE_NONCE_ACTION );

		$referer_safe = wp_get_referer();
		if ( ! is_string( $referer_safe ) || $referer_safe === '' ) {
			$referer_safe = admin_url();
		}

		if ( isset( $_GET['remote_ver'] ) ) {
			$rv = sanitize_text_field( wp_unslash( (string) $_GET['remote_ver'] ) );
			if ( self::plausible_plugin_version_slug( $rv ) ) {
				update_user_meta( get_current_user_id(), self::USER_META_DISMISSED_REMOTE_NOTICE_VER, $rv );
			}
		}

		wp_safe_redirect( $referer_safe );
		exit;
	}

	public function register_settings() {
		register_setting(
			'hesabix_chat_group',
			self::OPTION_NAME,
			array(
				'sanitize_callback' => array( $this, 'sanitize' ),
			)
		);
	}

	public function action_clear_widget_debug_log() {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'مجوز دسترسی ندارید.', 'hesabix-chat' ) );
		}
		check_admin_referer( 'hesabix_clear_dbg' );
		Hesabix_Chat_Debug::clear_log();
		wp_safe_redirect(
			add_query_arg(
				array(
					'page'             => 'hesabix-chat',
					'hesabix_dbg_note' => 'cleared',
				),
				admin_url( 'options-general.php' )
			)
		);
		exit;
	}

	public function action_export_widget_debug_log() {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'مجوز دسترسی ندارید.', 'hesabix-chat' ) );
		}
		check_admin_referer( 'hesabix_export_dbg' );
		$entries = Hesabix_Chat_Debug::get_entries();
		nocache_headers();
		header( 'Content-Type: application/json; charset=utf-8' );
		header(
			'Content-Disposition: attachment; filename="hesabix-chat-widget-debug-' . gmdate( 'Ymd-His' ) . '.json"'
		);
		// phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
		echo wp_json_encode( $entries, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE );
		exit;
	}

	/**
	 * @param array<string, mixed> $input .
	 * @return array<string, mixed>
	 */
	public function sanitize( $input ) {
		$defaults = self::defaults();
		$out      = self::get_options();

		if ( ! is_array( $input ) ) {
			return $out;
		}

		if ( isset( $input['api_base'] ) ) {
			$url = esc_url_raw( trim( (string) $input['api_base'] ) );
			$url = rtrim( $url, '/' );
			if ( $url !== '' && ( strpos( $url, 'https://' ) === 0 || strpos( $url, 'http://' ) === 0 ) ) {
				$out['api_base'] = $url;
			} else {
				$out['api_base'] = $defaults['api_base'];
			}
		}

		if ( isset( $input['public_key'] ) ) {
			$out['public_key'] = sanitize_text_field( (string) $input['public_key'] );
		}

		$out['load_mode'] = ( isset( $input['load_mode'] ) && 'shortcode' === $input['load_mode'] )
			? 'shortcode'
			: 'global';

		$pos = isset( $input['button_position'] ) ? (string) $input['button_position'] : $defaults['button_position'];
		$allowed_pos     = array( 'bottom-right', 'bottom-left', 'top-right', 'top-left' );
		$out['button_position'] = in_array( $pos, $allowed_pos, true ) ? $pos : 'bottom-right';

		if ( isset( $input['button_color'] ) ) {
			$out['button_color'] = $this->sanitize_hex( (string) $input['button_color'], (string) $defaults['button_color'] );
		}
		if ( isset( $input['button_text_color'] ) ) {
			$out['button_text_color'] = $this->sanitize_hex( (string) $input['button_text_color'], (string) $defaults['button_text_color'] );
		}
		if ( isset( $input['button_text'] ) ) {
			$out['button_text'] = sanitize_text_field( (string) $input['button_text'] );
		}
		if ( isset( $input['chat_title'] ) ) {
			$out['chat_title'] = sanitize_text_field( (string) $input['chat_title'] );
		}
		if ( isset( $input['welcome_message'] ) ) {
			$wm = sanitize_textarea_field( (string) $input['welcome_message'] );
			if ( function_exists( 'mb_substr' ) ) {
				$wm = mb_substr( $wm, 0, 2000 );
			} else {
				$wm = substr( $wm, 0, 2000 );
			}
			$out['welcome_message'] = $wm;
		}
		if ( isset( $input['response_time_text'] ) ) {
			$rt = sanitize_text_field( (string) $input['response_time_text'] );
			if ( function_exists( 'mb_substr' ) ) {
				$rt = mb_substr( $rt, 0, 300 );
			} else {
				$rt = substr( $rt, 0, 300 );
			}
			$out['response_time_text'] = $rt;
		}
		if ( isset( $input['header_logo_url'] ) ) {
			$u = esc_url_raw( trim( (string) $input['header_logo_url'] ) );
			$out['header_logo_url'] = ( $u !== '' && preg_match( '#^https?://#i', $u ) ) ? $u : '';
		}
		$pr = isset( $input['ui_preset'] ) ? (string) $input['ui_preset'] : 'default';
		$out['ui_preset'] = in_array( $pr, array( 'default', 'minimal', 'colorful' ), true ) ? $pr : 'default';

		$th = isset( $input['theme'] ) ? (string) $input['theme'] : (string) $defaults['theme'];
		$allowed_themes = array( 'light', 'dark', 'cream', 'ocean', 'midnight' );
		$out['theme']   = in_array( $th, $allowed_themes, true ) ? $th : 'light';

		$out['panel_width']  = $this->int_range( $input['panel_width'] ?? null, 280, 560, (int) $defaults['panel_width'] );
		$out['panel_height'] = $this->int_range( $input['panel_height'] ?? null, 320, 800, (int) $defaults['panel_height'] );
		$out['z_index']      = $this->int_range( $input['z_index'] ?? null, 1, 2147483647, (int) $defaults['z_index'] );
		$out['offset_bottom'] = $this->int_range( $input['offset_bottom'] ?? null, 0, 200, (int) $defaults['offset_bottom'] );
		$out['offset_side_desktop']  = $this->int_range( $input['offset_side_desktop'] ?? null, 0, 200, (int) $defaults['offset_side_desktop'] );
		$out['offset_side_mobile']   = $this->int_range( $input['offset_side_mobile'] ?? null, 0, 200, (int) $defaults['offset_side_mobile'] );
		$out['margin_left_desktop']  = $this->int_range( $input['margin_left_desktop'] ?? null, 0, 200, (int) $defaults['margin_left_desktop'] );
		$out['margin_right_desktop'] = $this->int_range( $input['margin_right_desktop'] ?? null, 0, 200, (int) $defaults['margin_right_desktop'] );
		$out['margin_left_mobile']   = $this->int_range( $input['margin_left_mobile'] ?? null, 0, 200, (int) $defaults['margin_left_mobile'] );
		$out['margin_right_mobile']  = $this->int_range( $input['margin_right_mobile'] ?? null, 0, 200, (int) $defaults['margin_right_mobile'] );
		$out['hide_launcher_front'] = ! empty( $input['hide_launcher_front'] ) ? 1 : 0;
		if ( isset( $input['hide_launcher_post_ids'] ) ) {
			$ids = self::parse_post_id_list( (string) $input['hide_launcher_post_ids'] );
			$out['hide_launcher_post_ids'] = $ids ? implode( ',', $ids ) : '';
		}
		if ( isset( $input['hide_launcher_paths'] ) ) {
			$lines = self::parse_path_prefix_lines( sanitize_textarea_field( (string) $input['hide_launcher_paths'] ) );
			$out['hide_launcher_paths'] = $lines ? implode( "\n", $lines ) : '';
		}
		$out['border_radius'] = $this->int_range( $input['border_radius'] ?? null, 0, 40, (int) $defaults['border_radius'] );

		$rtl = isset( $input['rtl'] ) ? (string) $input['rtl'] : 'auto';
		$out['rtl'] = in_array( $rtl, array( 'auto', 'ltr', 'rtl' ), true ) ? $rtl : 'auto';

		$out['show_file_upload'] = ! empty( $input['show_file_upload'] ) ? 1 : 0;
		$out['show_voice_message'] = ! empty( $input['show_voice_message'] ) ? 1 : 0;

		$ef = isset( $input['email_field'] ) ? (string) $input['email_field'] : (string) $defaults['email_field'];
		$out['email_field'] = in_array( $ef, array( 'required', 'optional', 'hidden', 'auto' ), true ) ? $ef : 'required';
		$out['show_page_context'] = ! empty( $input['show_page_context'] ) ? 1 : 0;

		if ( isset( $input['quick_replies_text'] ) ) {
			$qt = sanitize_textarea_field( (string) $input['quick_replies_text'] );
			if ( function_exists( 'mb_substr' ) ) {
				$qt = mb_substr( $qt, 0, 50000 );
			} else {
				$qt = substr( $qt, 0, 50000 );
			}
			$out['quick_replies_text'] = $qt;
		}

		if ( isset( $input['agent_reply_sound'] ) ) {
			$ok                       = self::list_agent_reply_sound_files();
			$out['agent_reply_sound'] = self::resolve_agent_reply_sound_choice( (string) $input['agent_reply_sound'], $ok );
		}

		$allowed_anim = array( 'none', 'bounce', 'pulse', 'shake', 'wiggle', 'glow', 'ring', 'float' );
		$anim         = isset( $input['launcher_idle_animation'] ) ? (string) $input['launcher_idle_animation'] : (string) $defaults['launcher_idle_animation'];
		$out['launcher_idle_animation'] = in_array( $anim, $allowed_anim, true ) ? $anim : 'none';
		$out['launcher_attention_delay_sec'] = $this->int_range( $input['launcher_attention_delay_sec'] ?? null, 0, 600, (int) $defaults['launcher_attention_delay_sec'] );
		$out['open_panel_on_load']   = ! empty( $input['open_panel_on_load'] ) ? 1 : 0;
		$out['open_panel_delay_sec'] = $this->int_range( $input['open_panel_delay_sec'] ?? null, 0, 120, (int) $defaults['open_panel_delay_sec'] );
		$out['remember_panel_between_pages'] = ! empty( $input['remember_panel_between_pages'] ) ? 1 : 0;

		$out['show_agent_join_ws'] = ! empty( $input['show_agent_join_ws'] ) ? 1 : 0;
		$out['show_agent_attendance_on_read'] = ! empty( $input['show_agent_attendance_on_read'] ) ? 1 : 0;
		$out['slow_reply_timeout_sec'] = $this->int_range(
			$input['slow_reply_timeout_sec'] ?? null,
			0,
			3600,
			(int) ( $defaults['slow_reply_timeout_sec'] ?? 0 )
		);
		if ( isset( $input['slow_reply_message'] ) ) {
			$sr = sanitize_textarea_field( (string) $input['slow_reply_message'] );
			if ( function_exists( 'mb_substr' ) ) {
				$sr = mb_substr( $sr, 0, 2000 );
			} else {
				$sr = substr( $sr, 0, 2000 );
			}
			$out['slow_reply_message'] = $sr;
		}

		if ( isset( $input['agent_join_notice_template'] ) ) {
			$tj = sanitize_text_field( (string) $input['agent_join_notice_template'] );
			if ( function_exists( 'mb_substr' ) ) {
				$tj = mb_substr( $tj, 0, 400 );
			} else {
				$tj = substr( $tj, 0, 400 );
			}
			$out['agent_join_notice_template'] = $tj;
		}

		if ( isset( $input['agent_read_notice_template'] ) ) {
			$tr = sanitize_text_field( (string) $input['agent_read_notice_template'] );
			if ( function_exists( 'mb_substr' ) ) {
				$tr = mb_substr( $tr, 0, 400 );
			} else {
				$tr = substr( $tr, 0, 400 );
			}
			$out['agent_read_notice_template'] = $tr;
		}

		$olm = isset( $input['operator_label_mode'] ) ? (string) $input['operator_label_mode'] : (string) ( $defaults['operator_label_mode'] ?? 'real' );
		$out['operator_label_mode'] = in_array( $olm, array( 'real', 'unified' ), true ) ? $olm : 'real';

		if ( isset( $input['operator_unified_display_name'] ) ) {
			$oun = sanitize_text_field( (string) $input['operator_unified_display_name'] );
			if ( function_exists( 'mb_substr' ) ) {
				$oun = mb_substr( $oun, 0, 120 );
			} else {
				$oun = substr( $oun, 0, 120 );
			}
			$out['operator_unified_display_name'] = $oun;
		}

		$out['show_powered_by_hesabix'] = ! empty( $input['show_powered_by_hesabix'] ) ? 1 : 0;

		if ( isset( $input['powered_by_hesabix_url'] ) ) {
			$pbu = esc_url_raw( trim( (string) $input['powered_by_hesabix_url'] ) );
			if ( $pbu !== '' && preg_match( '#^https?://#i', $pbu ) ) {
				$out['powered_by_hesabix_url'] = $pbu;
			} else {
				$out['powered_by_hesabix_url'] = (string) ( $defaults['powered_by_hesabix_url'] ?? 'https://hesabix.ir' );
			}
		}

		if ( isset( $input['powered_by_hesabix_text'] ) ) {
			$pbt = sanitize_text_field( (string) $input['powered_by_hesabix_text'] );
			if ( function_exists( 'mb_substr' ) ) {
				$pbt = mb_substr( $pbt, 0, 120 );
			} else {
				$pbt = substr( $pbt, 0, 120 );
			}
			$out['powered_by_hesabix_text'] = $pbt;
		}

		$out['widget_debug_logging'] = ! empty( $input['widget_debug_logging'] ) ? 1 : 0;

		$out['business_hours_enabled'] = ! empty( $input['business_hours_enabled'] ) ? 1 : 0;

		if ( isset( $input['business_hours_message'] ) ) {
			$bm = sanitize_textarea_field( (string) $input['business_hours_message'] );
			if ( function_exists( 'mb_substr' ) ) {
				$bm = mb_substr( $bm, 0, 1200 );
			} else {
				$bm = substr( $bm, 0, 1200 );
			}
			$out['business_hours_message'] = $bm;
		}

		$bhtm = isset( $input['business_hours_tz_mode'] ) ? (string) $input['business_hours_tz_mode'] : 'wp';
		$out['business_hours_tz_mode'] = ( 'custom' === $bhtm ) ? 'custom' : 'wp';

		if ( isset( $input['business_hours_timezone'] ) ) {
			$tzid = sanitize_text_field( (string) $input['business_hours_timezone'] );
			if ( function_exists( 'mb_strlen' ) && mb_strlen( $tzid ) > 120 ) {
				$tzid = mb_substr( $tzid, 0, 120 );
			} elseif ( strlen( $tzid ) > 120 ) {
				$tzid = substr( $tzid, 0, 120 );
			}
			$ok_tz = '';
			if ( '' !== $tzid ) {
				try {
					new DateTimeZone( $tzid );
					$ok_tz = $tzid;
				} catch ( Exception $e ) {
					$ok_tz = '';
				}
			}
			$out['business_hours_timezone'] = $ok_tz;
		}

		if ( isset( $input['business_hours_holidays_raw'] ) ) {
			$hraw = sanitize_textarea_field( (string) $input['business_hours_holidays_raw'] );
			if ( function_exists( 'mb_substr' ) ) {
				$hraw = mb_substr( $hraw, 0, 20000 );
			} else {
				$hraw = substr( $hraw, 0, 20000 );
			}
			$out['business_hours_holidays_raw'] = $hraw;
			$out['business_hours_holidays']     = self::parse_business_hours_holidays( $hraw );
		}

		if ( isset( $input['business_hours_day'] ) && is_array( $input['business_hours_day'] ) ) {
			$sched_rows = array();
			$day_in     = $input['business_hours_day'];
			for ( $di = 0; $di < 7; $di++ ) {
				$dr = isset( $day_in[ $di ] ) && is_array( $day_in[ $di ] ) ? $day_in[ $di ] : array();
				$sched_rows[] = array(
					'closed' => ! empty( $dr['closed'] ),
					'open'   => isset( $dr['open'] ) ? (string) $dr['open'] : '',
					'close'  => isset( $dr['close'] ) ? (string) $dr['close'] : '',
				);
			}
			$out['business_hours_schedule'] = self::normalize_business_hours_schedule( $sched_rows );
		}

		$tpl_class_keys = array(
			'widget_tpl_classes_host',
			'widget_tpl_classes_root',
			'widget_tpl_classes_launcher_wrap',
			'widget_tpl_classes_launcher',
			'widget_tpl_classes_panel',
			'widget_tpl_classes_surface',
		);
		foreach ( $tpl_class_keys as $tk ) {
			if ( isset( $input[ $tk ] ) ) {
				$out[ $tk ] = self::sanitize_widget_class_tokens( (string) $input[ $tk ] );
			}
		}

		if ( isset( $input['widget_custom_css'] ) ) {
			$out['widget_custom_css'] = self::sanitize_widget_custom_css( (string) wp_unslash( $input['widget_custom_css'] ) );
		}

		return $out;
	}

	/**
	 * @param string $val .
	 * @param string $fallback .
	 * @return string
	 */
	private function sanitize_hex( $val, $fallback ) {
		$val = trim( $val );
		if ( preg_match( '/^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$/', $val ) ) {
			return strtolower( $val );
		}
		return $fallback;
	}

	/**
	 * @param mixed  $v .
	 * @param int    $min .
	 * @param int    $max .
	 * @param int    $def .
	 * @return int
	 */
	private function int_range( $v, $min, $max, $def ) {
		$n = is_numeric( $v ) ? (int) $v : $def;
		if ( $n < $min ) {
			$n = $min;
		}
		if ( $n > $max ) {
			$n = $max;
		}
		return $n;
	}

	public function admin_assets( $hook ) {
		if ( 'settings_page_hesabix-chat' !== $hook ) {
			return;
		}
		wp_enqueue_style( 'wp-color-picker' );
		wp_enqueue_media();
		wp_enqueue_script( 'hesabix-chat-admin', HESABIX_CHAT_URL . 'assets/js/admin-settings.js', array( 'jquery', 'wp-color-picker' ), HESABIX_CHAT_VERSION, true );
		wp_enqueue_script(
			'hesabix-chat-update',
			HESABIX_CHAT_URL . 'assets/js/admin-update.js',
			array( 'jquery' ),
			HESABIX_CHAT_VERSION,
			true
		);
		wp_localize_script(
			'hesabix-chat-update',
			'HESABIX_CHAT_UPD',
			array(
				'ajaxUrl' => admin_url( 'admin-ajax.php' ),
				'nonce'   => wp_create_nonce( HESABIX_CHAT_UPDATE_NONCE_ACTION ),
				'actions' => array(
					'check'   => HESABIX_CHAT_UPDATE_AJAX_CHECK,
					'install' => HESABIX_CHAT_UPDATE_AJAX_INSTALL,
				),
				'strings' => array(
					'checking'              => __( 'در حال بررسی با سرور…', 'hesabix-chat' ),
					'installing'            => __( 'در حال دریافت و نصب به‌روزرسانی، لطفاً صبر کنید…', 'hesabix-chat' ),
					'reloadHint'            => __( 'به‌روزرسانی انجام شد؛ صفحه در حال تازه‌سازی است.', 'hesabix-chat' ),
					'genericError'          => __( 'درخواست ناموفق بود.', 'hesabix-chat' ),
					'remoteShort'           => __( 'نامشخص', 'hesabix-chat' ),
					'remoteUnknown'         => __( 'نامشخص (ارتباط با منبع برقرار نشد یا نسخه‌ای تشخیص داده نشد)', 'hesabix-chat' ),
					'sourceDisabled'        => __( 'منبع به‌روزرسانی تنظیم نشده. در مستند افزونه، آدرس raw فایل اصلی + zip آرشیو یا مانیفست JSON را تعریف کنید.', 'hesabix-chat' ),
					'blockedEnv'            => __( 'نسخهٔ جدید روی مخزن هست؛ ولی نسخهٔ وردپرس یا PHP سایت الزامات را نمی‌گذراند.', 'hesabix-chat' ),
					'noPermissionInstall'  => __( 'برای نصب از اینجا هر دؤ «مدیریت تنظیمات» و «به‌روزرسانی افزونه‌ها» نیاز است.', 'hesabix-chat' ),
					'requirementsUnknown'   => __( 'نامشخص', 'hesabix-chat' ),
					'requirementsFmt'       => __( 'وردپرس ≥ {{w}}؛ PHP ≥ {{p}}', 'hesabix-chat' ),
					'sourceLabelOff'        => __( 'تنظیم نشده', 'hesabix-chat' ),
					'sourceRawZip'          => __( 'نگاشت خام hesabix-chat.php + بستهٔ zip پیش‌فرض', 'hesabix-chat' ),
					'sourceManifest'        => __( 'مانیفست JSON', 'hesabix-chat' ),
					'sourceMixed'           => __( 'خام + آرشیو / مانیفست', 'hesabix-chat' ),
					'sourceDisabledSummary' => __( 'منبع به‌روزرسانی (آدرس فایل اصلی + zip آرشیو، یا مانیفست JSON) تنظیم نشده است؛ طبق راهنمای فایل اصلی افزونه یا wp-config آن را ست کنید.', 'hesabix-chat' ),
					'summaryNoRemote'       => __( 'به منبع وصل نشد یا نسخه‌ای از فایل اصلی/مانیفست خوانده نشد؛ «بررسی مجدد» را بزنید.', 'hesabix-chat' ),
					'summaryUpdateReady'    => __( 'نسخهٔ جدیدتری موجود است؛ می‌توانید همین‌جا با «به‌روزرسانی خودکار» از بستهٔ zip نصب کنید (پایان کار صفحه تازه می‌شود).', 'hesabix-chat' ),
					'summaryUpToDate'       => __( 'نسخهٔ نصب‌شده با آخرین نسخهٔ تشخیص‌داده‌شده از منبع برابر است (یا از راه‌دور جدیدتر دارید).', 'hesabix-chat' ),
				),
			)
		);
	}

	public function render_page() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$o = self::get_options();
		$upd_state = Hesabix_Chat_Updater::instance()->get_update_dashboard_state( false );
		if ( isset( $_GET['hesabix_dbg_note'] ) && 'cleared' === sanitize_text_field( wp_unslash( (string) $_GET['hesabix_dbg_note'] ) ) ) {
			echo '<div class="notice notice-success is-dismissible"><p>' . esc_html__( 'لاگ دیباگ ویجیت پاک شد.', 'hesabix-chat' ) . '</p></div>';
		}
		?>
		<div class="wrap">
			<h1><?php echo esc_html( get_admin_page_title() ); ?></h1>
			<p><?php esc_html_e( 'اتصال به سرور حسابیکس: آدرس پایه API و کلید عمومی ویجت چت را از پنل CRM > چت وب وارد کنید. دامنه سایت وردپرس باید در «دامنه‌های مجاز» همان ویجت ثبت شده باشد.', 'hesabix-chat' ); ?></p>
			<form method="post" action="options.php">
				<?php settings_fields( 'hesabix_chat_group' ); ?>
				<style>
					.hesabix-chat-settings-tabs { margin: 1em 0 0; padding-top: 4px; }
					.hesabix-chat-tab-panel { margin-top: 0.5em; }
					.hesabix-chat-tab-panel[hidden] { display: none !important; }
					.hesabix-chat-settings-submit-wrap {
						margin-top: 1.5em;
						padding: 14px 0 6px;
						border-top: 1px solid #c3c4c7;
						position: sticky;
						bottom: 0;
						background: #fff;
						box-shadow: 0 -6px 16px rgba( 0, 0, 0, 0.06 );
						z-index: 100;
					}
					.hesabix-chat-settings-submit-wrap .submit { margin: 0; padding: 0; }
					.hesabix-chat-doc-box { margin: 12px 0 4px; padding: 14px 16px 12px; max-width: 52rem; border: 1px solid #c3c4c7; border-radius: 8px; background: #fdfdfd; }
					.hesabix-chat-doc-box summary { cursor: pointer; font-weight: 600; outline: none; }
					.hesabix-chat-doc-box .hesabix-chat-doc-body { margin: 10px 0 0 1em; line-height: 1.65; font-size: 13px; }
					.hesabix-chat-doc-box code { font-size: 12px; }
				</style>
				<h2 class="nav-tab-wrapper hesabix-chat-settings-tabs wp-clearfix">
					<a href="#" class="nav-tab nav-tab-active" role="tab" aria-selected="true" data-tab="connection"><?php esc_html_e( 'اتصال', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="display"><?php esc_html_e( 'نمایش', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="content"><?php esc_html_e( 'متن و محتوا', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="appearance"><?php esc_html_e( 'ظاهر', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="behavior"><?php esc_html_e( 'رفتار', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="chat"><?php esc_html_e( 'چت و فرم', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="hours"><?php esc_html_e( 'ساعت کاری', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="customize"><?php esc_html_e( 'قالب و CSS سفارشی', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="update"><?php esc_html_e( 'به‌روزرسانی افزونه', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="debug"><?php esc_html_e( 'دیباگ', 'hesabix-chat' ); ?></a>
				</h2>
				<div class="hesabix-chat-tab-panel" data-tab="connection">
					<h2 class="screen-reader-text"><?php esc_html_e( 'اتصال به سرور', 'hesabix-chat' ); ?></h2>
					<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><label for="hesabix_api_base"><?php esc_html_e( 'آدرس پایه API (سرور)', 'hesabix-chat' ); ?></label></th>
						<td>
							<input name="<?php echo esc_attr( self::OPTION_NAME . '[api_base]' ); ?>" type="url" id="hesabix_api_base" class="regular-text" value="<?php echo esc_attr( $o['api_base'] ); ?>" />
							<p class="description"><?php esc_html_e( 'مثال: https://hsxn.hesabix.ir — بدون / در انتها.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_public_key"><?php esc_html_e( 'Public Key ویجت', 'hesabix-chat' ); ?></label></th>
						<td>
							<input name="<?php echo esc_attr( self::OPTION_NAME . '[public_key]' ); ?>" type="text" id="hesabix_public_key" class="large-text" value="<?php echo esc_attr( $o['public_key'] ); ?>" autocomplete="off" />
						</td>
					</tr>
					</table>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="display" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'محل و نحوهٔ نمایش', 'hesabix-chat' ); ?></h2>
					<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><?php esc_html_e( 'نمایش ویجت', 'hesabix-chat' ); ?></th>
						<td>
							<label><input name="<?php echo esc_attr( self::OPTION_NAME . '[load_mode]' ); ?>" type="radio" value="global" <?php checked( $o['load_mode'], 'global' ); ?> /> <?php esc_html_e( 'در تمام صفحات (دکمه شناور)', 'hesabix-chat' ); ?></label><br />
							<label><input name="<?php echo esc_attr( self::OPTION_NAME . '[load_mode]' ); ?>" type="radio" value="shortcode" <?php checked( $o['load_mode'], 'shortcode' ); ?> /> <?php esc_html_e( 'فقط با شورتکد [hesabix_chat] در برگه/نوشته', 'hesabix-chat' ); ?></label>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'مخفی کردن دکمه شناور', 'hesabix-chat' ); ?></th>
						<td>
							<p class="description" style="margin-top:0;"><?php esc_html_e( 'فقط وقتی «نمایش ویجت» روی «در تمام صفحات» است اعمال می‌شود. صفحه‌ای که فقط با شورتکد چت دارد تحت این قواعد نیست.', 'hesabix-chat' ); ?></p>
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[hide_launcher_front]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['hide_launcher_front'] ?? 0 ) ); ?> />
								<?php esc_html_e( 'مخفی در صفحهٔ اصلی', 'hesabix-chat' ); ?>
							</label>
							<p>
								<label for="hesabix_hide_ids"><?php esc_html_e( 'شناسه برگه/نوشته (با ویرگول یا فاصله)', 'hesabix-chat' ); ?></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[hide_launcher_post_ids]' ); ?>" type="text" id="hesabix_hide_ids" class="large-text" value="<?php echo esc_attr( (string) ( $o['hide_launcher_post_ids'] ?? '' ) ); ?>" placeholder="12, 45" />
							</p>
							<p>
								<label for="hesabix_hide_paths"><?php esc_html_e( 'مسیر URL (هر خط یک پیشوند، از / شروع کنید)', 'hesabix-chat' ); ?></label><br />
								<textarea name="<?php echo esc_attr( self::OPTION_NAME . '[hide_launcher_paths]' ); ?>" id="hesabix_hide_paths" class="large-text" rows="4" placeholder="/cart&#10;/checkout"><?php echo esc_textarea( (string) ( $o['hide_launcher_paths'] ?? '' ) ); ?></textarea>
							</p>
						</td>
					</tr>
					</table>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="content" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'متن و تجربهٔ بازدیدکننده', 'hesabix-chat' ); ?></h2>
					<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><label for="hesabix_button_text"><?php esc_html_e( 'متن دکمه', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[button_text]' ); ?>" type="text" id="hesabix_button_text" class="regular-text" value="<?php echo esc_attr( $o['button_text'] ); ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_chat_title"><?php esc_html_e( 'عنوان پنل چت', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[chat_title]' ); ?>" type="text" id="hesabix_chat_title" class="regular-text" value="<?php echo esc_attr( $o['chat_title'] ); ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_welcome_message"><?php esc_html_e( 'پیام اولیه برای بازدیدکننده', 'hesabix-chat' ); ?></label></th>
						<td>
							<textarea name="<?php echo esc_attr( self::OPTION_NAME . '[welcome_message]' ); ?>" id="hesabix_welcome_message" class="large-text" rows="4" placeholder="<?php echo esc_attr__( 'مثال: به بخش فروش خوش آمدید! چه کمکی از دستم برمی‌آید؟', 'hesabix-chat' ); ?>"><?php echo esc_textarea( (string) ( $o['welcome_message'] ?? '' ) ); ?></textarea>
							<p class="description"><?php esc_html_e( 'این متن پس از شروع چت، در بالای پنل به‌صورت نزدیک به پیام پشتیبانی نمایش داده می‌شود. چند سطر جدا با اینتر مجاز است.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_response_time"><?php esc_html_e( 'زمان پاسخ‌گویی (نمایش برای بازدیدکننده)', 'hesabix-chat' ); ?></label></th>
						<td>
							<input name="<?php echo esc_attr( self::OPTION_NAME . '[response_time_text]' ); ?>" type="text" id="hesabix_response_time" class="large-text" value="<?php echo esc_attr( (string) ( $o['response_time_text'] ?? '' ) ); ?>" />
							<p class="description"><?php esc_html_e( 'مثال: «ما معمولاً در کمتر از یک ساعت پاسخ می‌دهیم.» — زیر پیام خوش‌آمد دیده می‌شود. خالی بگذارید اگر نمی‌خواهید نمایش داده شود.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_quick_replies"><?php esc_html_e( 'پرسش و پاسخ آماده (در چت)', 'hesabix-chat' ); ?></label></th>
						<td>
							<textarea name="<?php echo esc_attr( self::OPTION_NAME . '[quick_replies_text]' ); ?>" id="hesabix_quick_replies" class="large-text code" rows="8" placeholder="<?php echo esc_attr__( "ساعت کاری شما؟|شنبه تا چهارشنبه ۹ تا ۱۷\nارسال چقدر طول می‌کشد؟|معمولاً ۲ تا ۴ روز کاری", 'hesabix-chat' ); ?>"><?php echo esc_textarea( (string) ( $o['quick_replies_text'] ?? '' ) ); ?></textarea>
							<p class="description"><?php esc_html_e( 'هر خط یک جفت: متن دکمه (پرسش) سپس | سپس پاسخ آماده. با کلیک بازدیدکننده، پرسش مثل پیام عادی به مکالمه ارسال می‌شود و پاسخ در همان پنل به‌صورت حباب پشتیبانی نمایش داده می‌شود (فقط در مرورگر؛ در CRM فقط همان پرسش دیده می‌شود). حداکثر ۱۲ خط؛ در هر بخش حدود ۲۰۰ و ۲۰۰۰ نویسه.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					</table>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="appearance" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'ظاهر، ابعاد و جایگاه', 'hesabix-chat' ); ?></h2>
					<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><label for="hesabix_ui_preset"><?php esc_html_e( 'الگوی ظاهر', 'hesabix-chat' ); ?></label></th>
						<td>
							<select name="<?php echo esc_attr( self::OPTION_NAME . '[ui_preset]' ); ?>" id="hesabix_ui_preset">
								<option value="default" <?php selected( (string) ( $o['ui_preset'] ?? 'default' ), 'default' ); ?>><?php esc_html_e( 'پیش‌فرض (گرادیان نرم، کارت خوش‌آمد)', 'hesabix-chat' ); ?></option>
								<option value="minimal" <?php selected( (string) ( $o['ui_preset'] ?? 'default' ), 'minimal' ); ?>><?php esc_html_e( 'مینیمال (تخت، بوردر کم)', 'hesabix-chat' ); ?></option>
								<option value="colorful" <?php selected( (string) ( $o['ui_preset'] ?? 'default' ), 'colorful' ); ?>><?php esc_html_e( 'رنگی (پس‌زمینه و سایهٔ پررنگ‌تر)', 'hesabix-chat' ); ?></option>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_logo_select"><?php esc_html_e( 'لوگو کنار عنوان پنل', 'hesabix-chat' ); ?></label></th>
						<td>
							<input type="hidden" name="<?php echo esc_attr( self::OPTION_NAME . '[header_logo_url]' ); ?>" id="hesabix_header_logo" value="<?php echo esc_attr( (string) ( $o['header_logo_url'] ?? '' ) ); ?>" />
							<p>
								<button type="button" class="button" id="hesabix_logo_select" data-title="<?php echo esc_attr__( 'لوگو برای هدر چت', 'hesabix-chat' ); ?>"><?php esc_html_e( 'انتخاب از رسانه', 'hesabix-chat' ); ?></button>
								<button type="button" class="button" id="hesabix_logo_clear"><?php esc_html_e( 'حذف تصویر', 'hesabix-chat' ); ?></button>
							</p>
							<?php
							$logo_u = trim( (string) ( $o['header_logo_url'] ?? '' ) );
							$show   = ( $logo_u !== '' );
							?>
							<div id="hesabix_logo_preview_wrap" style="<?php echo $show ? '' : 'display:none;'; ?>">
								<img src="<?php echo $show ? esc_url( $logo_u ) : ''; ?>" alt="" id="hesabix_logo_preview" style="max-width: 72px; max-height: 72px; object-fit: contain; border-radius: 8px; border: 1px solid #c3c4c7; padding: 4px; background: #fff; margin-top: 6px;" width="72" height="72" />
							</div>
							<p class="description"><?php esc_html_e( 'تصویر مربع یا افقی کوچک (مثلاً ۶۴px) مناسب است. در سمت راست/چپ کنار عنوان هدر دیده می‌شود.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_button_color"><?php esc_html_e( 'رنگ اصلی (دکمه و هدر)', 'hesabix-chat' ); ?></label></th>
						<td>
							<input name="<?php echo esc_attr( self::OPTION_NAME . '[button_color]' ); ?>" type="text" id="hesabix_button_color" value="<?php echo esc_attr( $o['button_color'] ); ?>" class="hesabix-color-field" data-default-color="#4f46e5" />
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_button_text_color"><?php esc_html_e( 'رنگ متن دکمه', 'hesabix-chat' ); ?></label></th>
						<td>
							<input name="<?php echo esc_attr( self::OPTION_NAME . '[button_text_color]' ); ?>" type="text" id="hesabix_button_text_color" value="<?php echo esc_attr( $o['button_text_color'] ); ?>" class="hesabix-color-field" data-default-color="#ffffff" />
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_button_position"><?php esc_html_e( 'جایگاه دکمه', 'hesabix-chat' ); ?></label></th>
						<td>
							<select name="<?php echo esc_attr( self::OPTION_NAME . '[button_position]' ); ?>" id="hesabix_button_position">
								<option value="bottom-right" <?php selected( $o['button_position'], 'bottom-right' ); ?>><?php esc_html_e( 'پایین · راست', 'hesabix-chat' ); ?></option>
								<option value="bottom-left" <?php selected( $o['button_position'], 'bottom-left' ); ?>><?php esc_html_e( 'پایین · چپ', 'hesabix-chat' ); ?></option>
								<option value="top-right" <?php selected( $o['button_position'], 'top-right' ); ?>><?php esc_html_e( 'بالا · راست', 'hesabix-chat' ); ?></option>
								<option value="top-left" <?php selected( $o['button_position'], 'top-left' ); ?>><?php esc_html_e( 'بالا · چپ', 'hesabix-chat' ); ?></option>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_theme"><?php esc_html_e( 'تم پنل', 'hesabix-chat' ); ?></label></th>
						<td>
							<select name="<?php echo esc_attr( self::OPTION_NAME . '[theme]' ); ?>" id="hesabix_theme">
								<option value="light" <?php selected( $o['theme'], 'light' ); ?>><?php esc_html_e( 'روشن (پیش‌فرض)', 'hesabix-chat' ); ?></option>
								<option value="dark" <?php selected( $o['theme'], 'dark' ); ?>><?php esc_html_e( 'تاریک', 'hesabix-chat' ); ?></option>
								<option value="cream" <?php selected( $o['theme'], 'cream' ); ?>><?php esc_html_e( 'کرمی / گرم', 'hesabix-chat' ); ?></option>
								<option value="ocean" <?php selected( $o['theme'], 'ocean' ); ?>><?php esc_html_e( 'آبی اقیانوسی', 'hesabix-chat' ); ?></option>
								<option value="midnight" <?php selected( $o['theme'], 'midnight' ); ?>><?php esc_html_e( 'نیمه‌شب (تیرهٔ عمیق)', 'hesabix-chat' ); ?></option>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_rtl"><?php esc_html_e( 'جهت نوشتار', 'hesabix-chat' ); ?></label></th>
						<td>
							<select name="<?php echo esc_attr( self::OPTION_NAME . '[rtl]' ); ?>" id="hesabix_rtl">
								<option value="auto" <?php selected( $o['rtl'], 'auto' ); ?>><?php esc_html_e( 'خودکار (از سایت وردپرس)', 'hesabix-chat' ); ?></option>
								<option value="rtl" <?php selected( $o['rtl'], 'rtl' ); ?>><?php echo esc_html( __( 'راست‌به‌چپ (RTL)', 'hesabix-chat' ) ); ?></option>
								<option value="ltr" <?php selected( $o['rtl'], 'ltr' ); ?>><?php echo esc_html( __( 'چپ‌به‌راست (LTR)', 'hesabix-chat' ) ); ?></option>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_panel_w"><?php esc_html_e( 'عرض پنل (px)', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[panel_width]' ); ?>" type="number" id="hesabix_panel_w" min="280" max="560" value="<?php echo (int) $o['panel_width']; ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_panel_h"><?php esc_html_e( 'ارتفاع پنل (px)', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[panel_height]' ); ?>" type="number" id="hesabix_panel_h" min="320" max="800" value="<?php echo (int) $o['panel_height']; ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_z_index"><?php esc_html_e( 'z-index (لایه نسبت به سایر عناصر)', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[z_index]' ); ?>" type="number" id="hesabix_z_index" min="1" value="<?php echo (int) $o['z_index']; ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_offset_b"><?php esc_html_e( 'فاصله از لبه عمودی (px)', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[offset_bottom]' ); ?>" type="number" id="hesabix_offset_b" min="0" max="200" value="<?php echo (int) $o['offset_bottom']; ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'فاصله و مارجین افقی دکمه/پنل', 'hesabix-chat' ); ?></th>
						<td>
							<p class="description" style="margin-top:0;"><?php esc_html_e( 'برای نمایش سراسری (دکمه شناور): فاصله از کنار همان لبه‌ای که دکمه به آن چسبیده است؛ مارجین چپ/راست برای جابه‌جایی اضافی (مثلاً دور از نوار کناری قالب). در موبایل: عرض viewport تا ۷۶۸px.', 'hesabix-chat' ); ?></p>
							<fieldset style="border:1px solid #c3c4c7;padding:10px 12px;margin:0 0 10px 0;">
								<legend><?php esc_html_e( 'دسکتاپ (عرض بیشتر از ۷۶۸px)', 'hesabix-chat' ); ?></legend>
								<p>
									<label for="hesabix_offset_side_d"><?php esc_html_e( 'فاصله از لبه (px)', 'hesabix-chat' ); ?></label><br />
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[offset_side_desktop]' ); ?>" type="number" id="hesabix_offset_side_d" min="0" max="200" value="<?php echo (int) $o['offset_side_desktop']; ?>" />
								</p>
								<p>
									<label for="hesabix_ml_d"><?php esc_html_e( 'مارجین چپ (px)', 'hesabix-chat' ); ?></label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[margin_left_desktop]' ); ?>" type="number" id="hesabix_ml_d" min="0" max="200" style="width:5em;" value="<?php echo (int) $o['margin_left_desktop']; ?>" />
									&nbsp;
									<label for="hesabix_mr_d"><?php esc_html_e( 'مارجین راست (px)', 'hesabix-chat' ); ?></label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[margin_right_desktop]' ); ?>" type="number" id="hesabix_mr_d" min="0" max="200" style="width:5em;" value="<?php echo (int) $o['margin_right_desktop']; ?>" />
								</p>
							</fieldset>
							<fieldset style="border:1px solid #c3c4c7;padding:10px 12px;margin:0;">
								<legend><?php esc_html_e( 'موبایل (حداکثر ۷۶۸px)', 'hesabix-chat' ); ?></legend>
								<p>
									<label for="hesabix_offset_side_m"><?php esc_html_e( 'فاصله از لبه (px)', 'hesabix-chat' ); ?></label><br />
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[offset_side_mobile]' ); ?>" type="number" id="hesabix_offset_side_m" min="0" max="200" value="<?php echo (int) $o['offset_side_mobile']; ?>" />
								</p>
								<p>
									<label for="hesabix_ml_m"><?php esc_html_e( 'مارجین چپ (px)', 'hesabix-chat' ); ?></label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[margin_left_mobile]' ); ?>" type="number" id="hesabix_ml_m" min="0" max="200" style="width:5em;" value="<?php echo (int) $o['margin_left_mobile']; ?>" />
									&nbsp;
									<label for="hesabix_mr_m"><?php esc_html_e( 'مارجین راست (px)', 'hesabix-chat' ); ?></label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[margin_right_mobile]' ); ?>" type="number" id="hesabix_mr_m" min="0" max="200" style="width:5em;" value="<?php echo (int) $o['margin_right_mobile']; ?>" />
								</p>
							</fieldset>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_radius"><?php esc_html_e( 'گردی گوشه پنل (px)', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[border_radius]' ); ?>" type="number" id="hesabix_radius" min="0" max="40" value="<?php echo (int) $o['border_radius']; ?>" /></td>
					</tr>
					</table>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="behavior" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'رفتار دکمه و پنل', 'hesabix-chat' ); ?></h2>
					<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><?php esc_html_e( 'جلب توجه به دکمه (وقتی پنل بسته است)', 'hesabix-chat' ); ?></th>
						<td>
							<p class="description" style="margin-top:0;"><?php esc_html_e( 'انیمیشن روی دکمهٔ گفتگو فقط وقتی پنل بسته باشد اجرا می‌شود؛ با باز کردن پنل متوقف می‌شود و با بستن دوباره (فوری) از سر گرفته می‌شود. در حالت «کاهش حرکت» سیستم‌عامل غیرفعال می‌شود.', 'hesabix-chat' ); ?></p>
							<p>
								<label for="hesabix_launcher_anim"><?php esc_html_e( 'نوع انیمیشن', 'hesabix-chat' ); ?></label><br />
								<select name="<?php echo esc_attr( self::OPTION_NAME . '[launcher_idle_animation]' ); ?>" id="hesabix_launcher_anim">
									<option value="none" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'none' ); ?>><?php esc_html_e( 'بدون انیمیشن', 'hesabix-chat' ); ?></option>
									<option value="bounce" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'bounce' ); ?>><?php esc_html_e( 'جهش عمودی (بالا–پایین)', 'hesabix-chat' ); ?></option>
									<option value="pulse" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'pulse' ); ?>><?php esc_html_e( 'تپش (بزرگ‌وشدن)', 'hesabix-chat' ); ?></option>
									<option value="shake" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'shake' ); ?>><?php esc_html_e( 'لرزش افقی', 'hesabix-chat' ); ?></option>
									<option value="wiggle" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'wiggle' ); ?>><?php esc_html_e( 'تکان چرخشی آیکون', 'hesabix-chat' ); ?></option>
									<option value="glow" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'glow' ); ?>><?php esc_html_e( 'درخشش سایه', 'hesabix-chat' ); ?></option>
									<option value="ring" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'ring' ); ?>><?php esc_html_e( 'حلقهٔ نبض (پالس)', 'hesabix-chat' ); ?></option>
									<option value="float" <?php selected( (string) ( $o['launcher_idle_animation'] ?? 'none' ), 'float' ); ?>><?php esc_html_e( 'شناور ملایم', 'hesabix-chat' ); ?></option>
								</select>
							</p>
							<p>
								<label for="hesabix_launcher_anim_delay"><?php esc_html_e( 'تأخیر شروع انیمیشن پس از لود صفحه (ثانیه)', 'hesabix-chat' ); ?></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[launcher_attention_delay_sec]' ); ?>" type="number" id="hesabix_launcher_anim_delay" min="0" max="600" value="<?php echo (int) ( $o['launcher_attention_delay_sec'] ?? 3 ); ?>" />
							</p>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'باز بودن خودکار پنل', 'hesabix-chat' ); ?></th>
						<td>
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[open_panel_on_load]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['open_panel_on_load'] ?? 0 ) ); ?> />
								<?php esc_html_e( 'با بارگذاری صفحه، پنل گفتگو از همان ابتدا باز باشد (دیالوگ باز).', 'hesabix-chat' ); ?>
							</label>
							<p>
								<label for="hesabix_open_panel_delay"><?php esc_html_e( 'تأخیر باز شدن پنل (ثانیه)', 'hesabix-chat' ); ?></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[open_panel_delay_sec]' ); ?>" type="number" id="hesabix_open_panel_delay" min="0" max="120" value="<?php echo (int) ( $o['open_panel_delay_sec'] ?? 0 ); ?>" />
								<span class="description"><?php esc_html_e( '۰ یعنی بلافاصله پس از آماده‌شدن ویجت.', 'hesabix-chat' ); ?></span>
							</p>
							<p>
								<label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[remember_panel_between_pages]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['remember_panel_between_pages'] ?? 1 ) ); ?> />
									<?php esc_html_e( 'حفظ وضعیت باز یا بسته بودن پنل هنگام رفتن به صفحهٔ دیگر (در همین تب مرورگر).', 'hesabix-chat' ); ?>
								</label>
							</p>
							<p class="description"><?php esc_html_e( 'اگر غیرفعال باشد، در هر بارگذاری صفحه فقط گزینهٔ «باز بودن خودکار پنل» بالا اعمال می‌شود و آخرین وضعیت پنل به خاطر سپرده نمی‌شود.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					</table>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="chat" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'گزینه‌های چت و فرم', 'hesabix-chat' ); ?></h2>
					<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><?php esc_html_e( 'ارسال فایل', 'hesabix-chat' ); ?></th>
						<td>
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[show_file_upload]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) $o['show_file_upload'] ); ?> />
								<?php esc_html_e( 'اجازه اتصال به ارسال فایل (ابتدا در CRM: تنظیمات چت > ارسال فایل باید فعال و فضای ذخیره‌سازی کافی باشد؛ سپس ویجت فقط اگر API تأیید کند input را نشان می‌دهد).', 'hesabix-chat' ); ?>
							</label>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'پیام صوتی', 'hesabix-chat' ); ?></th>
						<td>
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[show_voice_message]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['show_voice_message'] ?? 0 ) ); ?> />
								<?php esc_html_e( 'نمایش دکمهٔ ضبط؛ فقط در صورت تأیید API و فعال بودن در تنظیمات CRM و ویجت.', 'hesabix-chat' ); ?>
							</label>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_agent_reply_sound"><?php esc_html_e( 'صدای اعلان پاسخ پشتیبان', 'hesabix-chat' ); ?></label></th>
						<td>
							<select name="<?php echo esc_attr( self::OPTION_NAME . '[agent_reply_sound]' ); ?>" id="hesabix_agent_reply_sound">
								<option value="" <?php selected( (string) ( $o['agent_reply_sound'] ?? '' ), '' ); ?>><?php esc_html_e( 'بدون صدا', 'hesabix-chat' ); ?></option>
								<?php
								$sound_files = self::list_agent_reply_sound_files();
								$cur_sound   = (string) ( $o['agent_reply_sound'] ?? '' );
								foreach ( $sound_files as $sf ) {
									echo '<option value="' . esc_attr( $sf ) . '" ' . selected( $cur_sound, $sf, false ) . '>' . esc_html( $sf ) . '</option>';
								}
								?>
							</select>
							<p class="description"><?php esc_html_e( 'فایل‌های mp3، ogg، wav یا m4a را در پوشهٔ افزونه: assets/sounds قرار دهید؛ اینجا انتخاب می‌شوند. با رسیدن پیام جدید از پشتیبان (نه بارگذاری اولیهٔ تاریخچه) یک‌بار پخش می‌شود. مرورگر ممکن است تا اولین تعامل کاربر با صفحه اجازهٔ پخش خودکار ندهد.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_email_field"><?php esc_html_e( 'فیلد ایمیل', 'hesabix-chat' ); ?></label></th>
						<td>
							<select name="<?php echo esc_attr( self::OPTION_NAME . '[email_field]' ); ?>" id="hesabix_email_field">
								<option value="required" <?php selected( (string) ( $o['email_field'] ?? 'required' ), 'required' ); ?>><?php esc_html_e( 'الزامی', 'hesabix-chat' ); ?></option>
								<option value="optional" <?php selected( (string) ( $o['email_field'] ?? 'required' ), 'optional' ); ?>><?php esc_html_e( 'اختیاری (می‌توان خالی گذاشت)', 'hesabix-chat' ); ?></option>
								<option value="hidden" <?php selected( (string) ( $o['email_field'] ?? 'required' ), 'hidden' ); ?>><?php esc_html_e( 'نمایش نده (برای مهمانی که ایمیل نمی‌خواهید بپرسد)', 'hesabix-chat' ); ?></option>
								<option value="auto" <?php selected( (string) ( $o['email_field'] ?? 'required' ), 'auto' ); ?>><?php esc_html_e( 'خودکار: اگر کاربر وارد وردپرس است و ایمیل دارد — مخفی + استفاده از پروفایل؛ وگرنه الزامی', 'hesabix-chat' ); ?></option>
							</select>
							<p class="description"><?php esc_html_e( 'در حالت «نمایش نده»، اگر کسی وارد سایت است ایمیل پروفایل به صورت پنهان به مکالمه ارسال می‌شود. سرور باید به نسخه API که ایمیل خالی می‌پذیرد، به‌روز شده باشد.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'نمایش صفحهٔ فعلی در چت', 'hesabix-chat' ); ?></th>
						<td>
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[show_page_context]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['show_page_context'] ?? 0 ) ); ?> />
								<?php esc_html_e( 'اگر تیک بخورد، در فرم شروع گفتگؤ ویجت، عنوان و لینک صفحه به بازدیدکننده نشان داده می‌شود. آدرس همان صفحه همیشه همراه مکالمه به پنل (برای اپراتور) ارسال می‌گردد؛ این گزینه فقط دیدن آن در سمت مشتری را کنترل می‌کند.', 'hesabix-chat' ); ?>
							</label>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'اعلام حضور پشتیبان در ویجت', 'hesabix-chat' ); ?></th>
						<td>
							<p class="description" style="margin-top:0;"><?php esc_html_e( 'متن اعلام در فیلدهای زیر؛ از %s برای جای اسم پشتیبان استفاده کنید. اگر هر دو رویداد فعال باشد، تنها اولین اعلام (در همان نشست بازدیدکننده) نشان داده می‌شود.', 'hesabix-chat' ); ?></p>
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[show_agent_join_ws]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['show_agent_join_ws'] ?? 1 ) ); ?> />
								<?php esc_html_e( 'وقتی عامل CRM در مرورگر به اتاق وب‌سوکت آن مکالمه وارد می‌شود (باز بودن آن گفتگو در پنل).', 'hesabix-chat' ); ?>
							</label><br />
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[show_agent_attendance_on_read]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['show_agent_attendance_on_read'] ?? 0 ) ); ?> />
								<?php esc_html_e( 'وقتی پیام بازدیدکننده در پنل به‌صورت خوانده‌شده ثبت شد (اولین بار پس از ارسال شما). نیازمند حسابیکس هم‌نسخه با فیلد reader_display_name در رویداد messages.read است.', 'hesabix-chat' ); ?>
							</label>
							<p>
								<label for="hesabix_agent_join_tpl"><?php esc_html_e( 'متن اعلام (اتصال وب‌سوکت پشتیبان)', 'hesabix-chat' ); ?></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[agent_join_notice_template]' ); ?>" type="text" id="hesabix_agent_join_tpl" class="large-text" value="<?php echo esc_attr( (string) ( $o['agent_join_notice_template'] ?? '' ) ); ?>" />
							</p>
							<p>
								<label for="hesabix_agent_read_tpl"><?php esc_html_e( 'متن اعلام (خوانده شدن پیام توسط پشتیبان)', 'hesabix-chat' ); ?></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[agent_read_notice_template]' ); ?>" type="text" id="hesabix_agent_read_tpl" class="large-text" value="<?php echo esc_attr( (string) ( $o['agent_read_notice_template'] ?? '' ) ); ?>" />
							</p>
							<p class="description"><?php esc_html_e( 'در هر دو از %s برای جای نام پشتیبان استفاده کنید (طبق تنظیم «نمایش نام» زیر).', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'نام پشتیبان در ویجت (برای بازدیدکننده)', 'hesabix-chat' ); ?></th>
						<td>
							<fieldset style="margin:0;padding:0;border:0;">
								<label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[operator_label_mode]' ); ?>" type="radio" value="real" <?php checked( (string) ( $o['operator_label_mode'] ?? 'real' ), 'real' ); ?> />
									<?php esc_html_e( 'نام واقعی هر اپراتور (آن چه حسابیکس یا CRM می‌فرستد)', 'hesabix-chat' ); ?>
								</label><br />
								<label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[operator_label_mode]' ); ?>" type="radio" value="unified" <?php checked( (string) ( $o['operator_label_mode'] ?? 'real' ), 'unified' ); ?> />
									<?php esc_html_e( 'یک نام واحد برای همهٔ اپراتورها', 'hesabix-chat' ); ?>
								</label>
								<p>
									<label for="hesabix_operator_unified_name"><?php esc_html_e( 'نام واحد در صورت انتخاب حالت بالا', 'hesabix-chat' ); ?></label><br />
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[operator_unified_display_name]' ); ?>" type="text" id="hesabix_operator_unified_name" class="regular-text" value="<?php echo esc_attr( (string) ( $o['operator_unified_display_name'] ?? '' ) ); ?>" placeholder="<?php echo esc_attr__( 'مثلاً: پشتیبانی فروشگاه', 'hesabix-chat' ); ?>" />
								</p>
							</fieldset>
							<p class="description"><?php esc_html_e( 'این تنظیم روی برچسب حباب‌های پیام عامل، وضعیت «در حال تایپ…» و پیام‌های اعلام حضور اعمال می‌شود.', 'hesabix-chat' ); ?></p>
						</td>
					</tr>
					<tr>
						<th scope="row"><?php esc_html_e( 'اعتبار به حسابیکس (صفحهٔ شروع گفتگو)', 'hesabix-chat' ); ?></th>
						<td>
							<label>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[show_powered_by_hesabix]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['show_powered_by_hesabix'] ?? 1 ) ); ?> />
								<?php esc_html_e( 'در پایین فرم پیش از شروع چت، متن با لینک به hesabix.ir نمایش داده شود.', 'hesabix-chat' ); ?>
							</label>
							<p class="description" style="max-width:40em;"><em><?php esc_html_e( 'لطفاً برای حمایت از این برنامهٔ متن‌باز نمایش این خط را فعال بگذارید تا دیگر کاربران آن را بشناسند.', 'hesabix-chat' ); ?></em></p>
							<p>
								<label for="hesabix_powered_by_text"><?php esc_html_e( 'متن پیوند', 'hesabix-chat' ); ?></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[powered_by_hesabix_text]' ); ?>" type="text" id="hesabix_powered_by_text" class="large-text" value="<?php echo esc_attr( (string) ( $o['powered_by_hesabix_text'] ?? '' ) ); ?>" />
							</p>
							<p>
								<label for="hesabix_powered_by_url"><?php esc_html_e( 'آدرس پیوند', 'hesabix-chat' ); ?></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[powered_by_hesabix_url]' ); ?>" type="url" id="hesabix_powered_by_url" class="regular-text code" value="<?php echo esc_attr( (string) ( $o['powered_by_hesabix_url'] ?? '' ) ); ?>" />
							</p>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_slow_reply_sec"><?php esc_html_e( 'پاسخ دیر؛ یادآوری برای بازدیدکننده', 'hesabix-chat' ); ?></label></th>
						<td>
							<input name="<?php echo esc_attr( self::OPTION_NAME . '[slow_reply_timeout_sec]' ); ?>" type="number" id="hesabix_slow_reply_sec" min="0" max="3600" step="15" style="width:6em;" value="<?php echo (int) ( $o['slow_reply_timeout_sec'] ?? 0 ); ?>" />
							<span class="description"><?php esc_html_e( '۰ یعنی غیرفعال. پس از ارسال هر پیام توسط بازدیدکننده، اگر ظرف این مدت پاسخی از پشتیبان نرسد، پیام متن زیر نشان داده می‌شود (تا وقتی پشتیبان پاسخ دهد یا پیام بعدی بازدیدکننده تایمر را از نو بگیرد).', 'hesabix-chat' ); ?></span>
							<p>
								<label for="hesabix_slow_reply_msg"><?php esc_html_e( 'متن پیام', 'hesabix-chat' ); ?></label><br />
								<textarea name="<?php echo esc_attr( self::OPTION_NAME . '[slow_reply_message]' ); ?>" id="hesabix_slow_reply_msg" class="large-text" rows="3"><?php echo esc_textarea( (string) ( $o['slow_reply_message'] ?? '' ) ); ?></textarea>
							</p>
						</td>
					</tr>
				</table>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="hours" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'ساعت کاری و تعطیلات', 'hesabix-chat' ); ?></h2>
					<table class="form-table" role="presentation">
						<tr>
							<th scope="row"><?php esc_html_e( 'فعال‌سازی', 'hesabix-chat' ); ?></th>
							<td>
								<label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[business_hours_enabled]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['business_hours_enabled'] ?? 0 ) ); ?> />
									<?php esc_html_e( 'خارج از ساعات کاری یا روز تعطیل، پس از ارسال هر پیام توسط بازدیدکننده، متن دلخواه زیر نشان داده شود.', 'hesabix-chat' ); ?>
								</label>
								<p class="description"><?php esc_html_e( 'زمان‌ها بر اساس منطقهٔ زمانی وردپرس یا منطقهٔ دلخواه زیر محاسبه می‌شوند. شمارهٔ روز مانند date(\'w\') در PHP است: ۰ یکشنبه، …، ۵ جمعه، ۶ شنبه. پیش‌فرض برنامهٔ هفتگی: فقط جمعه تعطیل (مناسب ایران)؛ در جدول پایین قابل تغییر است.', 'hesabix-chat' ); ?></p>
							</td>
						</tr>
						<tr>
							<th scope="row"><label for="hesabix_bh_message"><?php esc_html_e( 'پیام به بازدیدکننده', 'hesabix-chat' ); ?></label></th>
							<td>
								<textarea name="<?php echo esc_attr( self::OPTION_NAME . '[business_hours_message]' ); ?>" id="hesabix_bh_message" class="large-text" rows="3"><?php echo esc_textarea( (string) ( $o['business_hours_message'] ?? '' ) ); ?></textarea>
								<p class="description"><?php esc_html_e( 'مثلاً: اکنون تعطیل است و اپراتوری فعال نیست؛ در اولین فرصت جواب می‌دهیم.', 'hesabix-chat' ); ?></p>
							</td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'منطقهٔ زمانی', 'hesabix-chat' ); ?></th>
							<td>
								<fieldset style="margin:0;padding:0;border:0;">
									<label>
										<input name="<?php echo esc_attr( self::OPTION_NAME . '[business_hours_tz_mode]' ); ?>" type="radio" value="wp" <?php checked( (string) ( $o['business_hours_tz_mode'] ?? 'wp' ), 'wp' ); ?> />
										<?php esc_html_e( 'همان منطقهٔ زمانی سایت وردپرس', 'hesabix-chat' ); ?>
									</label><br />
									<label>
										<input name="<?php echo esc_attr( self::OPTION_NAME . '[business_hours_tz_mode]' ); ?>" type="radio" value="custom" <?php checked( (string) ( $o['business_hours_tz_mode'] ?? 'wp' ), 'custom' ); ?> />
										<?php esc_html_e( 'IANA دلخواه (مثل Asia/Tehran)', 'hesabix-chat' ); ?>
									</label>
									<p>
										<label for="hesabix_bh_tz" class="screen-reader-text"><?php esc_html_e( 'شناسهٔ منطقهٔ دلخواه', 'hesabix-chat' ); ?></label>
										<input name="<?php echo esc_attr( self::OPTION_NAME . '[business_hours_timezone]' ); ?>" type="text" id="hesabix_bh_tz" class="regular-text code" placeholder="Asia/Tehran" value="<?php echo esc_attr( (string) ( $o['business_hours_timezone'] ?? '' ) ); ?>" autocomplete="off" />
									</p>
								</fieldset>
								<p class="description"><?php esc_html_e( 'شناسه نامعتبر برای حالت دلخواه نادیده گرفته می‌شود و همان وقت وردپرس استفاده می‌شود.', 'hesabix-chat' ); ?></p>
							</td>
						</tr>
						<tr>
							<th scope="row"><label for="hesabix_bh_holidays"><?php esc_html_e( 'تاریخ‌های تعطیل', 'hesabix-chat' ); ?></label></th>
							<td>
								<textarea name="<?php echo esc_attr( self::OPTION_NAME . '[business_hours_holidays_raw]' ); ?>" id="hesabix_bh_holidays" class="large-text code" rows="6" spellcheck="false" placeholder="2026-03-21&#10;2026-03-22"><?php echo esc_textarea( (string) ( $o['business_hours_holidays_raw'] ?? '' ) ); ?></textarea>
								<p class="description"><?php esc_html_e( 'هر خط یک تاریخ میلادی؛ فرمت YYYY-MM-DD یا YYYY/MM/DD. کل آن روز در آن منطقهٔ زمانی خارج از حضور محسوب می‌شود.', 'hesabix-chat' ); ?></p>
							</td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'برنامهٔ هفتگی', 'hesabix-chat' ); ?></th>
							<td>
								<table class="widefat striped hesabix-bh-schedule" style="max-width:36rem;margin-top:0;">
									<thead>
										<tr>
											<th scope="col"><?php esc_html_e( 'روز', 'hesabix-chat' ); ?></th>
											<th scope="col"><?php esc_html_e( 'تعطیل', 'hesabix-chat' ); ?></th>
											<th scope="col"><?php esc_html_e( 'شروع', 'hesabix-chat' ); ?></th>
											<th scope="col"><?php esc_html_e( 'پایان', 'hesabix-chat' ); ?></th>
										</tr>
									</thead>
									<tbody>
										<?php
										$bh_day_labels = array(
											__( 'یکشنبه', 'hesabix-chat' ),
											__( 'دوشنبه', 'hesabix-chat' ),
											__( 'سه‌شنبه', 'hesabix-chat' ),
											__( 'چهارشنبه', 'hesabix-chat' ),
											__( 'پنج‌شنبه', 'hesabix-chat' ),
											__( 'جمعه', 'hesabix-chat' ),
											__( 'شنبه', 'hesabix-chat' ),
										);
										$bh_sched       = Hesabix_Chat_Admin::normalize_business_hours_schedule( isset( $o['business_hours_schedule'] ) ? $o['business_hours_schedule'] : null );
										for ( $ddi = 0; $ddi < 7; $ddi++ ) {
											$rrow           = isset( $bh_sched[ $ddi ] ) && is_array( $bh_sched[ $ddi ] ) ? $bh_sched[ $ddi ] : array(
												'closed' => false,
												'open'   => '09:00',
												'close'  => '17:00',
											);
											$lbl            = isset( $bh_day_labels[ $ddi ] ) ? $bh_day_labels[ $ddi ] : (string) $ddi;
											$closed_checked = ! empty( $rrow['closed'] );
											$op_val         = esc_attr( (string) ( $rrow['open'] ?? '' ) );
											$cl_val         = esc_attr( (string) ( $rrow['close'] ?? '' ) );
											echo '<tr><th scope="row">' . esc_html( $lbl ) . '</th>';
											echo '<td><label><input type="checkbox" name="' . esc_attr( self::OPTION_NAME . '[business_hours_day][' . $ddi . '][closed]' ) . '" value="1"' . checked( $closed_checked, true, false ) . ' /> ';
											echo esc_html__( 'تعطیل', 'hesabix-chat' );
											echo '</label></td>';
											echo '<td><label class="screen-reader-text" for="' . esc_attr( 'hesabix_bh_open_' . $ddi ) . '">' . esc_html( sprintf( /* translators: %s weekday */ __( 'شروع %s', 'hesabix-chat' ), $lbl ) ) . '</label>';
											echo '<input type="text" id="' . esc_attr( 'hesabix_bh_open_' . $ddi ) . '" name="' . esc_attr( self::OPTION_NAME . '[business_hours_day][' . $ddi . '][open]' ) . '" class="regular-text" style="max-width:6em;font-family:monospace;" value="' . $op_val . '" pattern="^[0-2]?\\d:[0-5]\\d$" maxlength="8" autocomplete="off" /></td>';
											echo '<td><label class="screen-reader-text" for="' . esc_attr( 'hesabix_bh_close_' . $ddi ) . '">' . esc_html( sprintf( /* translators: %s weekday */ __( 'پایان %s', 'hesabix-chat' ), $lbl ) ) . '</label>';
											echo '<input type="text" id="' . esc_attr( 'hesabix_bh_close_' . $ddi ) . '" name="' . esc_attr( self::OPTION_NAME . '[business_hours_day][' . $ddi . '][close]' ) . '" class="regular-text" style="max-width:6em;font-family:monospace;" value="' . $cl_val . '" pattern="^[0-2]?\\d:[0-5]\\d$" maxlength="8" autocomplete="off" /></td></tr>';
										}
										?>
									</tbody>
								</table>
								<p class="description"><?php esc_html_e( 'ساعت‌ها به صورت ۲۴ساعته (مثل ۹:۰۰ تا ۱۷:۰۰). شیفت شب (پایان قبل یا برابر شروع) به‌صورت خارج از وقت تلقی می‌شود تا از سوء‌برداشت جلوگیری شود.', 'hesabix-chat' ); ?></p>
							</td>
						</tr>
					</table>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="customize" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'قالب، کلاس‌ها و استایل سفارشی', 'hesabix-chat' ); ?></h2>
					<p class="description" style="max-width:52rem;"><?php esc_html_e( 'پایهٔ رابط ویجیت با JavaScript ساخته می‌شود؛ «قالب سفارشی» اینجا یعنی افزودن کلاس برای هدف‌گیری با CSS خودتان یا تم فرزند. برای HTML جدید باید از قلاب‌ها و فیلترهای وردپرس در قالب یا یک افزونهٔ کوچک استفاده کنید.', 'hesabix-chat' ); ?></p>
					<details class="hesabix-chat-doc-box" open>
						<summary><?php esc_html_e( 'راهنمای کلاس‌ها و متغیرهای CSS', 'hesabix-chat' ); ?></summary>
						<div class="hesabix-chat-doc-body">
							<p><strong><?php esc_html_e( 'شناسه و ظرف ثابت', 'hesabix-chat' ); ?></strong></p>
							<ul>
								<li><code>#hesabix-chat-host</code> — <?php esc_html_e( 'ریشه در DOM (شورتکد یا شناور). برای حاشیهٔ صفر یا محصورکردن کل ویجیت.', 'hesabix-chat' ); ?></li>
								<li><?php esc_html_e( 'کلاس پایهٔ ظرف:', 'hesabix-chat' ); ?> <code>hesabix-chat-host</code>؛ <?php esc_html_e( 'در شورتکد:', 'hesabix-chat' ); ?> <code>hesabix-chat-host--shortcode</code>.</li>
							</ul>
							<p><strong><?php esc_html_e( 'زنجیرهٔ اصلی (پس از بارگذاری اسکریپت)', 'hesabix-chat' ); ?></strong></p>
							<ul>
								<li><code>.hesabix-chat-root</code> — <?php esc_html_e( 'جهت متن، تم رنگ، الگو و متغیرهای CSS؛ زیرمجموعهٔ مستقیم #hesabix-chat-host.', 'hesabix-chat' ); ?></li>
								<li><code>.hesabix-chat-floating</code> — <?php esc_html_e( 'بستهٔ شناور (لانچر + پنل)؛ جهت مانند hesabix-pos-bottom-right همین عنصر را هدف می‌گیرد.', 'hesabix-chat' ); ?></li>
								<li><code>.hesabix-chat-launcher</code>، <code>.hesabix-chat-panel</code> <?php esc_html_e( '(نقش دیالوگ)،', 'hesabix-chat' ); ?> <code>.hesabix-chat-surface</code>، <code>.hesabix-chat-header</code>، <code>.hesabix-chat-messages</code>، <code>.hesabix-chat-composer</code>.</li>
							</ul>
							<p><strong><?php esc_html_e( 'تم و الگو روی گرهٔ ریشهٔ داخلی', 'hesabix-chat' ); ?></strong></p>
							<ul>
								<li><code>.hesabix-chat--theme-light</code> / <code>--theme-dark</code>، <code>.hesabix-chat--preset-default|minimal|colorful</code>؛ <?php esc_html_e( 'تم ویژه: cream، ocean، midnight.', 'hesabix-chat' ); ?></li>
							</ul>
							<p><strong><?php esc_html_e( 'متغیرهای CSS روی پوستهٔ اصلی', 'hesabix-chat' ); ?></strong></p>
							<ul>
								<li><code>--hesabix-btn</code>، <code>--hesabix-btn-txt</code>، <code>--hesabix-panel-w</code>، <code>--hesabix-panel-h</code>، <code>--hesabix-z</code>، <code>--hesabix-bottom</code>، <code>--hesabix-side</code>، <code>--hesabix-side-mobile</code>، <code>--hesabix-radius</code>، <code>--hesabix-accent</code>.</li>
							</ul>
							<p><strong><?php esc_html_e( 'توسعه‌دهندگان PHP', 'hesabix-chat' ); ?></strong></p>
							<ul>
								<li><code>hesabix_chat_widget_custom_css</code> — <?php esc_html_e( 'فیلتر روی متن CSS ذخیره‌شده پیش از افزودن به برگه.', 'hesabix-chat' ); ?></li>
								<li><code>hesabix_chat_tpl_extra_classes</code> — <?php esc_html_e( 'فیلتر روی آرایهٔ کلاس‌های ارسالی به اسکریپت (کلیدها: root, launcherWrap, launcher, panel, surface).', 'hesabix-chat' ); ?></li>
							</ul>
						</div>
					</details>
					<table class="form-table" role="presentation">
						<tr>
							<th scope="row"><?php esc_html_e( 'CSS سفارشی ویجیت', 'hesabix-chat' ); ?></th>
							<td>
								<label for="hesabix_custom_css"><?php esc_html_e( 'کد خام بدون تگ', 'hesabix-chat' ); ?> <code>&lt;style&gt;</code><?php esc_html_e( '؛ بعد از stylesheet اصلی افزونه لود می‌شود.', 'hesabix-chat' ); ?></label>
								<p class="description"><?php esc_html_e( 'برای ایمن‌سازی، @import از متن حذف می‌شود؛ از تزریق script/expression خودداری کنید.', 'hesabix-chat' ); ?></p>
								<textarea name="<?php echo esc_attr( self::OPTION_NAME . '[widget_custom_css]' ); ?>" id="hesabix_custom_css" class="large-text code" rows="14" spellcheck="false"><?php echo esc_textarea( (string) ( $o['widget_custom_css'] ?? '' ) ); ?></textarea>
							</td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'کلاس اضافه روی #hesabix-chat-host', 'hesabix-chat' ); ?></th>
							<td>
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[widget_tpl_classes_host]' ); ?>" type="text" id="hesabix_tpl_host" class="large-text code" value="<?php echo esc_attr( (string) ( $o['widget_tpl_classes_host'] ?? '' ) ); ?>" autocomplete="off" />
								<p class="description"><?php esc_html_e( 'فقط a–z، 0–9، زیرخط و خط‌تیره؛ با فاصله جدا کنید. حداکثر ۲۰ قطعه؛ هر قطعه تا ۶۴ نویسه.', 'hesabix-chat' ); ?></p>
							</td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'کلاس‌های اضافی جزئیات قالب', 'hesabix-chat' ); ?></th>
							<td>
								<p><label for="hesabix_tpl_root"><code>.hesabix-chat-root</code></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[widget_tpl_classes_root]' ); ?>" type="text" id="hesabix_tpl_root" class="large-text code" value="<?php echo esc_attr( (string) ( $o['widget_tpl_classes_root'] ?? '' ) ); ?>" autocomplete="off" /></p>
								<p><label for="hesabix_tpl_wrap"><code>.hesabix-chat-floating</code></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[widget_tpl_classes_launcher_wrap]' ); ?>" type="text" id="hesabix_tpl_wrap" class="large-text code" value="<?php echo esc_attr( (string) ( $o['widget_tpl_classes_launcher_wrap'] ?? '' ) ); ?>" autocomplete="off" /></p>
								<p><label for="hesabix_tpl_launcher"><code>.hesabix-chat-launcher</code></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[widget_tpl_classes_launcher]' ); ?>" type="text" id="hesabix_tpl_launcher" class="large-text code" value="<?php echo esc_attr( (string) ( $o['widget_tpl_classes_launcher'] ?? '' ) ); ?>" autocomplete="off" /></p>
								<p><label for="hesabix_tpl_panel"><code>.hesabix-chat-panel</code></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[widget_tpl_classes_panel]' ); ?>" type="text" id="hesabix_tpl_panel" class="large-text code" value="<?php echo esc_attr( (string) ( $o['widget_tpl_classes_panel'] ?? '' ) ); ?>" autocomplete="off" /></p>
								<p><label for="hesabix_tpl_surface"><code>.hesabix-chat-surface</code></label><br />
								<input name="<?php echo esc_attr( self::OPTION_NAME . '[widget_tpl_classes_surface]' ); ?>" type="text" id="hesabix_tpl_surface" class="large-text code" value="<?php echo esc_attr( (string) ( $o['widget_tpl_classes_surface'] ?? '' ) ); ?>" autocomplete="off" /></p>
							</td>
						</tr>
					</table>
				</div>
				<?php
				$upd_remote_disp = __( 'نامشخص', 'hesabix-chat' );
				if ( ! empty( $upd_state['remote_loaded'] ) && isset( $upd_state['remote_version'] ) && (string) $upd_state['remote_version'] !== '' ) {
					$upd_remote_disp = (string) $upd_state['remote_version'];
				}
				$upd_summary_txt = '';
				if ( empty( $upd_state['configured'] ) ) {
					$upd_summary_txt = __( 'منبع به‌روزرسانی (آدرس فایل اصلی + zip آرشیو، یا مانیفست JSON) تنظیم نشده است؛ طبق راهنمای فایل اصلی افزونه یا wp-config آن را ست کنید.', 'hesabix-chat' );
				} elseif ( empty( $upd_state['remote_loaded'] ) ) {
					$upd_summary_txt = __( 'به منبع وصل نشد یا نسخه‌ای از فایل اصلی/مانیفست خوانده نشد؛ «بررسی مجدد» را بزنید.', 'hesabix-chat' );
				} elseif ( ! empty( $upd_state['update_available'] ) ) {
					$upd_summary_txt = __( 'نسخهٔ جدیدتری موجود است؛ می‌توانید همین‌جا با «به‌روزرسانی خودکار» از بستهٔ zip نصب کنید (پایان کار صفحه تازه می‌شود).', 'hesabix-chat' );
				} elseif ( ! empty( $upd_state['newer_than_local'] ) && empty( $upd_state['env_compatible'] ) ) {
					$upd_summary_txt = __( 'نسخهٔ جدید روی مخزن است؛ اما نسخهٔ وردپرس یا PHP سایت به حد لازم نمی‌رسد.', 'hesabix-chat' );
				} else {
					$upd_summary_txt = __( 'نسخهٔ نصب‌شده با آخرین نسخهٔ تشخیص‌داده‌شده از منبع برابر است (یا از راه‌دور جدیدتر دارید).', 'hesabix-chat' );
				}
				$upd_install_disabled = empty( $upd_state['update_available'] ) || empty( $upd_state['can_install'] );
				$upd_requires_label     = __( 'نامشخص', 'hesabix-chat' );
				if ( ! empty( $upd_state['remote_loaded'] ) ) {
					$upd_rw = isset( $upd_state['requires_wp'] ) ? (string) $upd_state['requires_wp'] : '';
					$upd_rp = isset( $upd_state['requires_php'] ) ? (string) $upd_state['requires_php'] : '';
					if ( '' !== $upd_rw || '' !== $upd_rp ) {
						$upd_requires_label = sprintf(
						/* translators: 1: minimum WordPress version, 2: minimum PHP version */
							__( 'وردپرس ≥ %1$s؛ PHP ≥ %2$s', 'hesabix-chat' ),
							'' !== $upd_rw ? $upd_rw : '—',
							'' !== $upd_rp ? $upd_rp : '—'
						);
					}
				}
				$upd_source_label = __( 'نامشخص', 'hesabix-chat' );
				if ( empty( $upd_state['configured'] ) ) {
					$upd_source_label = __( 'تنظیم نشده', 'hesabix-chat' );
				} elseif ( ! empty( $upd_state['configured_raw_zip'] ) ) {
					$upd_source_label = __( 'نگاشت خام hesabix-chat.php + بستهٔ zip پیش‌فرض', 'hesabix-chat' );
				} elseif ( ! empty( $upd_state['configured_manifest_only'] ) ) {
					$upd_source_label = __( 'مانیفست JSON', 'hesabix-chat' );
				} else {
					$upd_source_label = __( 'خام + آرشیو / مانیفست', 'hesabix-chat' );
				}
				?>
				<div class="hesabix-chat-tab-panel" data-tab="update" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'به‌روزرسانی افزونه از مخزن', 'hesabix-chat' ); ?></h2>
					<p class="description" style="max-width:54rem;margin-top:0;"><?php esc_html_e( 'منبع نسخه و بسته، همان رویکرد به‌روزرسانی از راه دور خود وردپرس است (فایل اصلی raw برای خواندن نسخه + آرشیؤ zip برای جایگزینی فایل‌های افزونه). پس از نصب موفق صفحه دوباره بارگذاری می‌شود.', 'hesabix-chat' ); ?></p>
					<table class="form-table hesabix-upd-versions" role="presentation">
						<tr>
							<th scope="row"><?php esc_html_e( 'نسخهٔ نصب‌شدهٔ فعلی', 'hesabix-chat' ); ?></th>
							<td><strong id="hesabix-upd-current"><?php echo esc_html( (string) ( $upd_state['current_version'] ?? '' ) ); ?></strong></td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'آخرین نسخهٔ منتشرشده (از منبع)', 'hesabix-chat' ); ?></th>
							<td><strong id="hesabix-upd-remote"><?php echo esc_html( $upd_remote_disp ); ?></strong></td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'نوع منبع', 'hesabix-chat' ); ?></th>
							<td id="hesabix-upd-source"><?php echo esc_html( $upd_source_label ); ?></td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'الزاماتِ اعلام‌شده در بستهٔ راه دور', 'hesabix-chat' ); ?></th>
							<td id="hesabix-upd-requires"><?php echo esc_html( $upd_requires_label ); ?></td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'خلاصهٔ وضعیت', 'hesabix-chat' ); ?></th>
							<td id="hesabix-upd-summary"><?php echo esc_html( $upd_summary_txt ); ?></td>
						</tr>
					</table>
					<p class="submit" style="padding-top:8px;display:flex;flex-wrap:wrap;gap:10px;align-items:center;">
						<button type="button" class="button button-secondary" id="hesabix-upd-refresh"><?php esc_html_e( 'بررسی مجدد از سرور', 'hesabix-chat' ); ?></button>
						<button type="button" class="button button-primary" id="hesabix-upd-install"<?php echo $upd_install_disabled ? ' disabled aria-disabled="true"' : ''; ?>><?php esc_html_e( 'به‌روزرسانی خودکار (Ajax)', 'hesabix-chat' ); ?></button>
						<span class="description" id="hesabix-upd-inline-status" aria-live="polite" style="flex-basis:100%;"></span>
					</p>
					<p class="notice notice-alt" style="max-width:52rem;"><strong><?php esc_html_e( 'مجوز:', 'hesabix-chat' ); ?></strong>
						<?php
						if ( ! empty( $upd_state['can_install'] ) ) {
							echo esc_html__( 'شما حق به‌روزرسانی این افزونه از این برگه را دارید.', 'hesabix-chat' );
						} else {
							echo esc_html__( 'برای دکمهٔ نصب باید علاوه بر دسترسی به این تنظیمات، نقش کاربریٔ شما شامل «به‌روزرسانی افزونه‌ها» هم باشد (در چند‌سایت ممکن است محدود شود).', 'hesabix-chat' );
						}
						?>
					</p>
					<script type="application/json" id="hesabix-upd-initial-state"><?php echo wp_json_encode( $upd_state ); ?></script>
				</div>
				<div class="hesabix-chat-tab-panel" data-tab="debug" hidden>
					<h2 class="screen-reader-text"><?php esc_html_e( 'لاگ و عیب‌یابی ویجیت', 'hesabix-chat' ); ?></h2>
					<?php
					$dbg_preview = Hesabix_Chat_Debug::get_entries();
					$n_dbg       = is_array( $dbg_preview ) ? count( $dbg_preview ) : 0;
					$dbg_slice   = $n_dbg > 120 ? array_slice( $dbg_preview, -120 ) : $dbg_preview;
					$dbg_flags   = JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE;
					if ( defined( 'JSON_INVALID_UTF8_SUBSTITUTE' ) ) {
						$dbg_flags |= JSON_INVALID_UTF8_SUBSTITUTE;
					}
					$dbg_json = wp_json_encode( $dbg_slice, $dbg_flags );
					if ( false === $dbg_json ) {
						$dbg_json = wp_json_encode(
							array(
								'error'   => 'wp_json_encode_failed',
								'entries' => $n_dbg,
							),
							JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE
						);
						if ( false === $dbg_json ) {
							$dbg_json = '{}';
						}
					}
					?>
					<table class="form-table" role="presentation">
						<tr>
							<th scope="row"><?php esc_html_e( 'ثبت لاگ از مرورگر بازدیدکننده', 'hesabix-chat' ); ?></th>
							<td>
								<label>
									<input name="<?php echo esc_attr( self::OPTION_NAME . '[widget_debug_logging]' ); ?>" type="checkbox" value="1" <?php checked( 1, (int) ( $o['widget_debug_logging'] ?? 0 ) ); ?> />
									<?php esc_html_e( 'رویدادها و پیام‌های وب‌سوکت (پس از ماسک کردن توکن‌ها) را در این سایت ذخیره کن.', 'hesabix-chat' ); ?>
								</label>
								<p class="description"><?php esc_html_e( 'فقط برای عیب‌یابی کوتاه فعال کنید؛ حجم اپشن وردپرس و بار سرور کم است اما باز هم پس از تست غیرفعال کنید.', 'hesabix-chat' ); ?></p>
								<p class="description"><strong><?php esc_html_e( 'توجه:', 'hesabix-chat' ); ?></strong>
									<?php esc_html_e( 'نشانگر «در حال تایپ» و پیام «به گفتگو پیوست» فقط با اتصال وب‌سوکت زنده به API کار می‌کنند؛ اگر در ویجیت «غیرزنده» می‌بینید آن را بررسی کنید.', 'hesabix-chat' ); ?>
								</p>
							</td>
						</tr>
						<tr>
							<th scope="row"><?php esc_html_e( 'پیش‌نمایش لاگ (آخرین ردیف‌ها)', 'hesabix-chat' ); ?></th>
							<td>
								<textarea readonly rows="18" cols="60" id="hesabix_widget_dbg_preview" class="large-text code"><?php echo esc_textarea( $dbg_json ); ?></textarea>
								<p class="description">
									<?php
									echo esc_html(
										sprintf(
										/* translators: 1: number of entries currently stored */
											__( 'در حافظه حداکثر %1$d ردیف نگه‌داری می‌شود؛ الان %2$d ردیف دارید.', 'hesabix-chat' ),
											Hesabix_Chat_Debug::MAX_ENTRIES,
											$n_dbg
										)
									);
									?>
								</p>
								<p>
									<a class="button" href="<?php echo esc_url( wp_nonce_url( admin_url( 'admin.php?action=hesabix_export_widget_debug_log' ), 'hesabix_export_dbg' ) ); ?>">
										<?php esc_html_e( 'دانلود JSON کامل', 'hesabix-chat' ); ?>
									</a>
									<a class="button button-link-delete" style="margin-inline-start:8px;" href="<?php echo esc_url( wp_nonce_url( admin_url( 'admin.php?action=hesabix_clear_widget_debug_log' ), 'hesabix_clear_dbg' ) ); ?>">
										<?php esc_html_e( 'پاک کردن لاگ', 'hesabix-chat' ); ?>
									</a>
								</p>
							</td>
						</tr>
					</table>
				</div>
				<div class="hesabix-chat-settings-submit-wrap">
					<?php submit_button(); ?>
				</div>
			</form>
		</div>
		<?php
	}
}
