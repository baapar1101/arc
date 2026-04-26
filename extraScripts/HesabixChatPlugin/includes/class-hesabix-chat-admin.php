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
			'offset_side'          => 24,
			'border_radius'        => 16,
			'chat_title'           => __( 'پشتیبانی', 'hesabix-chat' ),
			'welcome_message'      => __( 'به بخش فروش خوش آمدید! چه کمکی از دستم برمی‌آید؟', 'hesabix-chat' ),
			'response_time_text'   => __( 'ما معمولاً در کمتر از یک ساعت پاسخ می‌دهیم.', 'hesabix-chat' ),
			'ui_preset'            => 'default',
			'header_logo_url'      => '',
			'rtl'                  => 'auto',
			'show_file_upload'     => 0,
			'email_field'         => 'required',
			'show_page_context'   => 0,
		);
	}

	/**
	 * @return array<string, mixed>
	 */
	public static function get_options() {
		$opts = get_option( self::OPTION_NAME, array() );
		if ( ! is_array( $opts ) ) {
			$opts = array();
		}
		return array_replace_recursive( self::defaults(), $opts );
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

		$out['theme'] = ( isset( $input['theme'] ) && 'dark' === $input['theme'] ) ? 'dark' : 'light';

		$out['panel_width']  = $this->int_range( $input['panel_width'] ?? null, 280, 560, (int) $defaults['panel_width'] );
		$out['panel_height'] = $this->int_range( $input['panel_height'] ?? null, 320, 800, (int) $defaults['panel_height'] );
		$out['z_index']      = $this->int_range( $input['z_index'] ?? null, 1, 2147483647, (int) $defaults['z_index'] );
		$out['offset_bottom'] = $this->int_range( $input['offset_bottom'] ?? null, 0, 200, (int) $defaults['offset_bottom'] );
		$out['offset_side']  = $this->int_range( $input['offset_side'] ?? null, 0, 200, (int) $defaults['offset_side'] );
		$out['border_radius'] = $this->int_range( $input['border_radius'] ?? null, 0, 40, (int) $defaults['border_radius'] );

		$rtl = isset( $input['rtl'] ) ? (string) $input['rtl'] : 'auto';
		$out['rtl'] = in_array( $rtl, array( 'auto', 'ltr', 'rtl' ), true ) ? $rtl : 'auto';

		$out['show_file_upload'] = ! empty( $input['show_file_upload'] ) ? 1 : 0;

		$ef = isset( $input['email_field'] ) ? (string) $input['email_field'] : (string) $defaults['email_field'];
		$out['email_field'] = in_array( $ef, array( 'required', 'optional', 'hidden', 'auto' ), true ) ? $ef : 'required';
		$out['show_page_context'] = ! empty( $input['show_page_context'] ) ? 1 : 0;

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
					<tr>
						<th scope="row"><?php esc_html_e( 'نمایش ویجت', 'hesabix-chat' ); ?></th>
						<td>
							<label><input name="<?php echo esc_attr( self::OPTION_NAME . '[load_mode]' ); ?>" type="radio" value="global" <?php checked( $o['load_mode'], 'global' ); ?> /> <?php esc_html_e( 'در تمام صفحات (دکمه شناور)', 'hesabix-chat' ); ?></label><br />
							<label><input name="<?php echo esc_attr( self::OPTION_NAME . '[load_mode]' ); ?>" type="radio" value="shortcode" <?php checked( $o['load_mode'], 'shortcode' ); ?> /> <?php esc_html_e( 'فقط با شورتکد [hesabix_chat] در برگه/نوشته', 'hesabix-chat' ); ?></label>
						</td>
					</tr>
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
								<option value="light" <?php selected( $o['theme'], 'light' ); ?>><?php esc_html_e( 'روشن', 'hesabix-chat' ); ?></option>
								<option value="dark" <?php selected( $o['theme'], 'dark' ); ?>><?php esc_html_e( 'تاریک', 'hesabix-chat' ); ?></option>
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
						<th scope="row"><label for="hesabix_offset_s"><?php esc_html_e( 'فاصله از لبه افقی (px)', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[offset_side]' ); ?>" type="number" id="hesabix_offset_s" min="0" max="200" value="<?php echo (int) $o['offset_side']; ?>" /></td>
					</tr>
					<tr>
						<th scope="row"><label for="hesabix_radius"><?php esc_html_e( 'گردی گوشه پنل (px)', 'hesabix-chat' ); ?></label></th>
						<td><input name="<?php echo esc_attr( self::OPTION_NAME . '[border_radius]' ); ?>" type="number" id="hesabix_radius" min="0" max="40" value="<?php echo (int) $o['border_radius']; ?>" /></td>
					</tr>
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
				<?php submit_button(); ?>
			</form>
		</div>
		<?php
	}
}
