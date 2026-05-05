<?php
/**
 * Plugin Name:       Hesabix Web Chat
 * Plugin URI:        https://hesabix.ir
 * Description:       اتصال سایت وردپرس به چت وب CRM حسابیکس؛ ارتباط بازدیدکننده با کسب‌وکار از طریق API عمومی.
 * Version:           1.1.62
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

define( 'HESABIX_CHAT_VERSION', '1.1.62' );
define( 'HESABIX_CHAT_FILE', __FILE__ );
define( 'HESABIX_CHAT_PATH', plugin_dir_path( __FILE__ ) );
define( 'HESABIX_CHAT_URL', plugin_dir_url( __FILE__ ) );

/**
 * به‌روزرسانی: نسخه از فایل اصلی به‌صورت raw، بسته از archive همان شاخه (آدرس ثابت).
 * اختیاری: HESABIX_CHAT_UPDATE_MANIFEST_URL برای مانیفست JSON (اگر خالی باشد استفاده نمی‌شود).
 * برای مخزن اختصاصی: قبل از بارگذاری این فایل در wp-config مقدار HESABIX_CHAT_UPDATE_RAW_PHP_URL و HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL را تعریف کنید.
 */
if ( ! defined( 'HESABIX_CHAT_UPDATE_RAW_PHP_URL' ) ) {
	define(
		'HESABIX_CHAT_UPDATE_RAW_PHP_URL',
		'https://source.hesabix.ir/hesabix/HesabixChatPlugin/raw/branch/master/hesabix-chat.php'
	);
}
if ( ! defined( 'HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL' ) ) {
	define(
		'HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL',
		'https://source.hesabix.ir/hesabix/HesabixChatPlugin/archive/master.zip'
	);
}

require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat-updater.php';
require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat-debug.php';
require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat-hours.php';
require_once HESABIX_CHAT_PATH . 'includes/class-hesabix-chat.php';

Hesabix_Chat_Debug::init();

Hesabix_Chat_Business_Hours::init();

Hesabix_Chat_Updater::init();

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
