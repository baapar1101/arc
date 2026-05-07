<?php
/**
 * هسته افزونه.
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat-admin.php';
require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat-frontend.php';

/**
 * Singleton اصلی.
 */
final class Hesabix_Chat {

	/**
	 * @var Hesabix_Chat|null
	 */
	private static $instance = null;

	/**
	 * @return Hesabix_Chat
	 */
	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	private function __construct() {
		if ( is_admin() ) {
			new Hesabix_Chat_Admin();
		}
		new Hesabix_Chat_Frontend();
	}
}
