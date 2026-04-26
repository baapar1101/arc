<?php
/**
 * Plugin Name:       Hesabix Web Chat
 * Plugin URI:        https://hesabix.ir
 * Description:       اتصال سایت وردپرس به چت وب CRM حسابیکس؛ ارتباط بازدیدکننده با کسب‌وکار از طریق API عمومی.
 * Version:           1.0.11
 * Requires at least: 5.8
 * Requires PHP:      7.4
 * Author:            Hesabix
 * License:           GPL v2 or later
 * Text Domain:       hesabix-chat
 * Domain Path:       /languages
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

define( 'HESABIX_CHAT_VERSION', '1.0.11' );
define( 'HESABIX_CHAT_FILE', __FILE__ );
define( 'HESABIX_CHAT_PATH', plugin_dir_path( __FILE__ ) );
define( 'HESABIX_CHAT_URL', plugin_dir_url( __FILE__ ) );

/**
 * به‌روزرسانی: نسخه از فایل اصلی به‌صورت raw، بسته از archive همان شاخه (آدرس ثابت).
 * اختیاری: HESABIX_CHAT_UPDATE_MANIFEST_URL برای مانیفست JSON (اگر خالی باشد استفاده نمی‌شود).
 */
if ( ! defined( 'HESABIX_CHAT_UPDATE_RAW_PHP_URL' ) ) {
	define(
		'HESABIX_CHAT_UPDATE_RAW_PHP_URL',
		'https://source.hesabix.ir/hesabix/HesabixChatPlugin/-/raw/master/hesabix-chat.php'
	);
}
if ( ! defined( 'HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL' ) ) {
	define(
		'HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL',
		'https://source.hesabix.ir/hesabix/HesabixChatPlugin/-/archive/master.zip'
	);
}

require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat-updater.php';
require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat.php';

new Hesabix_Chat_Updater();

add_action( 'plugins_loaded', 'hesabix_chat_load_textdomain', 0 );

/**
 * بارگذاری فایل‌های ترجمه (.mo) از پوشه languages
 */
function hesabix_chat_load_textdomain() {
	load_plugin_textdomain(
		'hesabix-chat',
		false,
		dirname( plugin_basename( HESABIX_CHAT_FILE ) ) . '/languages'
	);
}

Hesabix_Chat::instance();
