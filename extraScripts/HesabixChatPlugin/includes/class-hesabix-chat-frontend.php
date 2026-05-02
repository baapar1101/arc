<?php
/**
 * بارگذاری اسکریپت و ریشه ویجت در سمت بازدیدکننده.
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hesabix_Chat_Frontend
 */
class Hesabix_Chat_Frontend {

	/**
	 * @var bool
	 */
	private static $shortcode_used = false;

	public function __construct() {
		add_action( 'wp_enqueue_scripts', array( $this, 'register_assets' ) );
		add_action( 'wp_footer', array( $this, 'maybe_print_root' ), 5 );
		add_shortcode( 'hesabix_chat', array( $this, 'shortcode' ) );
	}

	public function register_assets() {
		$o = Hesabix_Chat_Admin::get_options();
		if ( '' === (string) $o['public_key'] ) {
			return;
		}
		if ( 'global' === $o['load_mode'] ) {
			if ( ! $this->should_show_floating_launcher( $o ) ) {
				return;
			}
			$this->enqueue( $o );
			return;
		}
		if ( 'shortcode' === $o['load_mode'] && $this->content_has_shortcode() ) {
			$this->enqueue( $o );
		}
	}

	/**
	 * مسیر درخواست فعلی (بدون کوئری) برای تطبیق پیشوند مسیر.
	 *
	 * @return string
	 */
	private function current_request_path() {
		$uri = isset( $_SERVER['REQUEST_URI'] ) ? wp_unslash( $_SERVER['REQUEST_URI'] ) : '/';
		$path = wp_parse_url( esc_url_raw( $uri ), PHP_URL_PATH );
		if ( ! is_string( $path ) || $path === '' ) {
			$path = '/';
		}
		$path = untrailingslashit( $path );
		return ( $path !== '' ) ? $path : '/';
	}

	/**
	 * نمایش دکمه/ریشهٔ شناور در حالت load_mode=global
	 *
	 * @param array<string, mixed> $o .
	 * @return bool
	 */
	private function should_show_floating_launcher( $o ) {
		if ( ! apply_filters( 'hesabix_chat_show_floating_launcher', true, $o ) ) {
			return false;
		}
		if ( ! empty( $o['hide_launcher_front'] ) && is_front_page() ) {
			return false;
		}
		if ( is_singular() ) {
			$ids = Hesabix_Chat_Admin::parse_post_id_list( (string) ( $o['hide_launcher_post_ids'] ?? '' ) );
			if ( $ids && in_array( (int) get_queried_object_id(), $ids, true ) ) {
				return false;
			}
		}
		$prefixes = Hesabix_Chat_Admin::parse_path_prefix_lines( (string) ( $o['hide_launcher_paths'] ?? '' ) );
		if ( $prefixes ) {
			$req = $this->current_request_path();
			foreach ( $prefixes as $pref ) {
				if ( $pref !== '' && strpos( $req, $pref ) === 0 ) {
					return false;
				}
			}
		}
		return true;
	}

	/**
	 * بررسی شورتکد در محتوای حلقه اصلی (تقریبی) برای تازه‌سازی.
	 */
	private function content_has_shortcode() {
		if ( is_singular() ) {
			$p = get_post();
			if ( $p && isset( $p->post_content ) && has_shortcode( $p->post_content, 'hesabix_chat' ) ) {
				return true;
			}
		}
		return false;
	}

	/**
	 * حالت «auto»: اگر کاربر وارد است و ایمیل معتبر دارد → مثل hidden (ارسال از پروفایل).
	 *
	 * @param string        $stored یکی از required|optional|hidden|auto .
	 * @param \WP_User|null $user .
	 * @return string required|optional|hidden
	 */
	private function resolve_effective_email_field( $stored, $user ) {
		$stored = (string) $stored;
		if ( ! in_array( $stored, array( 'required', 'optional', 'hidden', 'auto' ), true ) ) {
			$stored = 'required';
		}
		if ( 'auto' === $stored ) {
			if ( $user && (int) $user->ID > 0 && is_email( (string) $user->user_email ) ) {
				return 'hidden';
			}
			return 'required';
		}
		return $stored;
	}

	/**
	 * @param array<string, mixed> $o .
	 * @return array<string, scalar|bool|string>
	 */
	public static function business_hours_client_config( array $o ) {
		$bh = array(
			'enabled'             => false,
			'ajaxUrl'               => '',
			'action'                => '',
			'nonce'                 => '',
			'snapshotOutside'       => false,
			'snapshotMessage'       => '',
		);
		if ( empty( $o['business_hours_enabled'] ) || ! class_exists( 'Hesabix_Chat_Business_Hours' ) ) {
			return $bh;
		}
		$snap                    = Hesabix_Chat_Business_Hours::localize_snapshot( $o );
		$bh['enabled']           = true;
		$bh['ajaxUrl']           = esc_url_raw( admin_url( 'admin-ajax.php' ) );
		$bh['action']            = Hesabix_Chat_Business_Hours::AJAX_ACTION;
		$bh['nonce']             = wp_create_nonce( Hesabix_Chat_Business_Hours::NONCE_ACTION );
		$bh['snapshotOutside']   = ! empty( $snap['outside'] );
		$bh['snapshotMessage']   = isset( $snap['message'] ) ? (string) $snap['message'] : '';

		return $bh;
	}

	/**
	 * @param array<string, mixed> $o .
	 */
	private function enqueue( $o ) {
		if ( '' === (string) $o['public_key'] ) {
			return;
		}

		wp_register_style(
			'hesabix-chat',
			HESABIX_CHAT_URL . 'assets/css/chat-widget.css',
			array(),
			HESABIX_CHAT_VERSION
		);
		wp_register_script(
			'hesabix-chat',
			HESABIX_CHAT_URL . 'assets/js/chat-widget.js',
			array(),
			HESABIX_CHAT_VERSION,
			true
		);

		wp_enqueue_style( 'hesabix-chat' );
		wp_enqueue_script( 'hesabix-chat' );

		$custom_css_saved = isset( $o['widget_custom_css'] ) ? (string) $o['widget_custom_css'] : '';
		$custom_css_live  = (string) apply_filters( 'hesabix_chat_widget_custom_css', $custom_css_saved, $o );
		$custom_css_live  = Hesabix_Chat_Admin::sanitize_widget_custom_css( $custom_css_live );
		if ( $custom_css_live !== '' ) {
			wp_add_inline_style( 'hesabix-chat', $custom_css_live );
		}

		$rtl = is_rtl() ? 'rtl' : 'ltr';
		$opt = (string) $o['rtl'];
		if ( 'rtl' === $opt ) {
			$dir = 'rtl';
		} elseif ( 'ltr' === $opt ) {
			$dir = 'ltr';
		} else {
			$dir = $rtl;
		}

		$current_user = wp_get_current_user();
		$prefill      = array(
			'first_name' => '',
			'last_name'  => '',
			'email'      => '',
			'phone'      => '',
		);
		if ( $current_user && $current_user->ID ) {
			$fn = (string) get_user_meta( $current_user->ID, 'first_name', true );
			$ln = (string) get_user_meta( $current_user->ID, 'last_name', true );
			if ( $fn . $ln === '' && $current_user->display_name ) {
				$parts = preg_split( '/\s+/u', trim( $current_user->display_name ), 2 );
				$fn    = $parts[0] ?? '';
				$ln    = $parts[1] ?? '';
			}
			$prefill['first_name'] = $fn;
			$prefill['last_name']  = $ln;
			$prefill['email']      = (string) $current_user->user_email;
		}

		$email_eff = $this->resolve_effective_email_field( (string) ( $o['email_field'] ?? 'required' ), $current_user );
		$email_eff = (string) apply_filters( 'hesabix_chat_email_field', $email_eff, $o, $current_user );

		$agent_reply_sound_url = '';
		$sn                    = (string) ( $o['agent_reply_sound'] ?? '' );
		if ( $sn !== '' ) {
			$allowed_sounds = Hesabix_Chat_Admin::list_agent_reply_sound_files();
			$resolved       = Hesabix_Chat_Admin::resolve_agent_reply_sound_choice( $sn, $allowed_sounds );
			if ( $resolved !== '' ) {
				$agent_reply_sound_url = apply_filters(
					'hesabix_chat_agent_reply_sound_url',
					HESABIX_CHAT_URL . 'assets/sounds/' . rawurlencode( $resolved ),
					$resolved,
					$o
				);
			}
		}

		wp_localize_script(
			'hesabix-chat',
			'HESABIX_CHAT',
			array(
				'apiBase'         => (string) $o['api_base'],
				'publicKey'       => (string) $o['public_key'],
				'buttonText'      => (string) $o['button_text'],
				'buttonPosition'  => (string) $o['button_position'],
				'buttonColor'     => (string) $o['button_color'],
				'buttonTextColor' => (string) $o['button_text_color'],
				'chatTitle'       => (string) $o['chat_title'],
				'welcomeMessage'  => (string) ( $o['welcome_message'] ?? '' ),
				'responseTimeText' => (string) ( $o['response_time_text'] ?? '' ),
				'uiPreset'        => (string) ( $o['ui_preset'] ?? 'default' ),
				'headerLogoUrl'  => (string) ( $o['header_logo_url'] ?? '' ),
				'theme'           => (string) $o['theme'],
				'panelWidth'      => (int) $o['panel_width'],
				'panelHeight'     => (int) $o['panel_height'],
				'zIndex'          => (int) $o['z_index'],
				'offsetBottom'    => (int) $o['offset_bottom'],
				'offsetSideDesktop'  => (int) ( $o['offset_side_desktop'] ?? 24 ),
				'offsetSideMobile'   => (int) ( $o['offset_side_mobile'] ?? 24 ),
				'marginLeftDesktop'  => (int) ( $o['margin_left_desktop'] ?? 0 ),
				'marginRightDesktop' => (int) ( $o['margin_right_desktop'] ?? 0 ),
				'marginLeftMobile'   => (int) ( $o['margin_left_mobile'] ?? 0 ),
				'marginRightMobile'  => (int) ( $o['margin_right_mobile'] ?? 0 ),
				'borderRadius'    => (int) $o['border_radius'],
				'dir'             => $dir,
				'showFileUpload'  => (int) $o['show_file_upload'] === 1,
				'showVoiceMessage' => (int) ( $o['show_voice_message'] ?? 0 ) === 1,
				'loadMode'        => (string) $o['load_mode'],
				'debug'           => (bool) apply_filters( 'hesabix_chat_debug', false ),
				'widgetDebugLogging'  => ! empty( $o['widget_debug_logging'] ),
				'widgetDebugAjaxUrl'   => esc_url_raw( admin_url( 'admin-ajax.php' ) ),
				'widgetDebugNonce'    => wp_create_nonce( Hesabix_Chat_Debug::NONCE_ACTION ),
				'emailField'      => $email_eff,
				'showPageContext' => (int) ( $o['show_page_context'] ?? 0 ) === 1,
				'prefill'         => $prefill,
				'quickReplies'    => (array) apply_filters(
					'hesabix_chat_quick_replies',
					Hesabix_Chat_Admin::parse_quick_replies_text( (string) ( $o['quick_replies_text'] ?? '' ) ),
					$o
				),
				'agentReplySoundUrl' => (string) $agent_reply_sound_url,
				'launcherIdleAnimation'      => (string) ( $o['launcher_idle_animation'] ?? 'none' ),
				'launcherAttentionDelaySec'  => (int) ( $o['launcher_attention_delay_sec'] ?? 0 ),
				'openPanelOnLoad'            => (int) ( $o['open_panel_on_load'] ?? 0 ) === 1,
				'openPanelDelaySec'          => (int) ( $o['open_panel_delay_sec'] ?? 0 ),
				'rememberPanelBetweenPages'  => (int) ( $o['remember_panel_between_pages'] ?? 1 ) === 1,
				'showAgentJoinWs'            => (int) ( $o['show_agent_join_ws'] ?? 1 ) === 1,
				'showAgentAttendanceOnRead' => (int) ( $o['show_agent_attendance_on_read'] ?? 0 ) === 1,
				'slowReplyTimeoutSec'        => (int) ( $o['slow_reply_timeout_sec'] ?? 0 ),
				'slowReplyMessage'           => (string) ( $o['slow_reply_message'] ?? '' ),
				'agentJoinNoticeTemplate'   => (string) ( $o['agent_join_notice_template'] ?? '' ),
				'agentReadNoticeTemplate'   => (string) ( $o['agent_read_notice_template'] ?? '' ),
				'operatorLabelMode'          => (string) ( $o['operator_label_mode'] ?? 'real' ),
				'operatorUnifiedDisplayName' => (string) ( $o['operator_unified_display_name'] ?? '' ),
				'showPoweredByHesabix'      => (int) ( $o['show_powered_by_hesabix'] ?? 1 ) === 1,
				'poweredByHesabixUrl'       => esc_url_raw(
					(string) apply_filters(
						'hesabix_chat_powered_by_url',
						(string) ( $o['powered_by_hesabix_url'] ?? 'https://hesabix.ir' ),
						$o
					)
				),
				'poweredByHesabixText'      => (string) apply_filters(
					'hesabix_chat_powered_by_text',
					(string) ( $o['powered_by_hesabix_text'] ?? '' ),
					$o
				),
				'tplExtraClasses'           => Hesabix_Chat_Admin::template_extra_classes_bundle( $o ),
				'businessHours'             => Hesabix_Chat_Frontend::business_hours_client_config( $o ),
				'strings'         => array(
					'formTitle'    => __( 'شروع گفتگو', 'hesabix-chat' ),
					'formSubtitle' => __( 'برای شروع، مشخصات خود را وارد کنید.', 'hesabix-chat' ),
					'firstName'    => __( 'نام', 'hesabix-chat' ),
					'lastName'     => __( 'نام خانوادگی', 'hesabix-chat' ),
					'email'        => __( 'ایمیل', 'hesabix-chat' ),
					'emailOptionalHint' => __( 'در صورت تمایل می‌توانید خالی بگذارید.', 'hesabix-chat' ),
					'pageContextLabel'  => __( 'صفحهٔ فعلی', 'hesabix-chat' ),
					'phone'        => __( 'موبایل', 'hesabix-chat' ),
					'start'        => __( 'شروع', 'hesabix-chat' ),
					'placeholder'  => __( 'پیام خود را بنویسید…', 'hesabix-chat' ),
					'send'         => __( 'ارسال', 'hesabix-chat' ),
					'sending'      => __( 'در حال ارسال…', 'hesabix-chat' ),
					'sendBusyHint' => __( 'پیام قبلی در حال ارسال است؛ لطفاً صبر کنید.', 'hesabix-chat' ),
					'sendTooltip'  => sprintf(
						/* translators: 1: Send action, 2: keyboard shortcut hint */
						__( '%1$s — %2$s', 'hesabix-chat' ),
						__( 'ارسال', 'hesabix-chat' ),
						__( 'میانبر: Ctrl یا ⌘ + Enter', 'hesabix-chat' )
					),
					'close'        => __( 'بستن', 'hesabix-chat' ),
					'closeTooltip' => __( 'بستن پنل گفتگو', 'hesabix-chat' ),
					'back'         => __( 'مکالمه جدید', 'hesabix-chat' ),
					'attach'       => __( 'پیوست', 'hesabix-chat' ),
					'errorGeneric' => __( 'خطا در ارتباط با سرور.', 'hesabix-chat' ),
					'you'          => __( 'شما', 'hesabix-chat' ),
					'support'      => __( 'پشتیبانی', 'hesabix-chat' ),
					'voicePick'    => __( 'پیام صوتی (انتخاب فایل ضبط‌شده یا ضبط موبایل)', 'hesabix-chat' ),
					'newChatHint'  => __( 'مکالمه فعلی پاک می‌شود و می‌توانید دوباره شروع کنید.', 'hesabix-chat' ),
					'wsConnecting'     => __( 'در حال اتصال…', 'hesabix-chat' ),
					'wsLive'           => __( 'زنده', 'hesabix-chat' ),
					'wsLiveHint'       => __( 'اتصال لحظه‌ای برقرار است.', 'hesabix-chat' ),
					'wsOffline'        => __( 'غیرزنده', 'hesabix-chat' ),
					'wsOfflineHint'    => __( 'به‌روزرسانی ممکن است با تأخیر باشد.', 'hesabix-chat' ),
					'agentTyping'      => __( 'پشتیبان در حال تایپ…', 'hesabix-chat' ),
					'agentTypingNamed' => __( '%s در حال تایپ است…', 'hesabix-chat' ),
					'agentJoinedNotice' => __( '%s به گفتگو پیوست', 'hesabix-chat' ),
					'msgDelivered'     => __( 'ارسال شد', 'hesabix-chat' ),
					'msgReadBySupport' => __( 'پشتیبان خواند', 'hesabix-chat' ),
					'quickRepliesTitle' => __( 'پرسش‌های پرتکرار', 'hesabix-chat' ),
					'cannedAnswerLabel' => __( 'پاسخ خودکار', 'hesabix-chat' ),
				),
			)
		);
	}

	/**
	 * @param array<string, string> $atts .
	 * @return string
	 */
	public function shortcode( $atts ) {
		self::$shortcode_used = true;
		$o = Hesabix_Chat_Admin::get_options();
		if ( '' === (string) $o['public_key'] ) {
			return '<!-- hesabix_chat: ' . esc_html__( 'public key تنظیم نشده', 'hesabix-chat' ) . ' -->';
		}
		$this->enqueue( $o );
		$class = Hesabix_Chat_Admin::widget_host_class_attribute_value( $o, true );

		return '<div id="hesabix-chat-host" class="' . esc_attr( $class ) . '"></div>';
	}

	public function maybe_print_root() {
		$o = Hesabix_Chat_Admin::get_options();
		if ( '' === (string) $o['public_key'] ) {
			return;
		}
		if ( 'global' !== $o['load_mode'] ) {
			return;
		}
		if ( ! $this->should_show_floating_launcher( $o ) ) {
			return;
		}
		$class = Hesabix_Chat_Admin::widget_host_class_attribute_value( $o, false );

		echo '<div id="hesabix-chat-host" class="' . esc_attr( $class ) . '" aria-hidden="true"></div>';
	}
}
