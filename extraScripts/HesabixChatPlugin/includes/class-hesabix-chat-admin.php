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
		);
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

	public function register_settings() {
		register_setting(
			'hesabix_chat_group',
			self::OPTION_NAME,
			array(
				'sanitize_callback' => array( $this, 'sanitize' ),
			)
		);
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
	}

	public function render_page() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$o = self::get_options();
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
				</style>
				<h2 class="nav-tab-wrapper hesabix-chat-settings-tabs wp-clearfix">
					<a href="#" class="nav-tab nav-tab-active" role="tab" aria-selected="true" data-tab="connection"><?php esc_html_e( 'اتصال', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="display"><?php esc_html_e( 'نمایش', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="content"><?php esc_html_e( 'متن و محتوا', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="appearance"><?php esc_html_e( 'ظاهر', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="behavior"><?php esc_html_e( 'رفتار', 'hesabix-chat' ); ?></a>
					<a href="#" class="nav-tab" role="tab" aria-selected="false" data-tab="chat"><?php esc_html_e( 'چت و فرم', 'hesabix-chat' ); ?></a>
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
