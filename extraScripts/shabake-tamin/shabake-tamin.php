<?php
/**
 * Plugin Name:       شبکه تأمین
 * Plugin URI:        https://hesabix.ir
 * Description:       نمایش کاتالوگ عمومی محصولات Hesabix روی وردپرس؛ تم پیش‌فرض شبیه ترب و قابل override در قالب.
 * Version:            1.3.0
 * Requires at least:  5.8
 * Requires PHP:       7.4
 * Author:             Hesabix
 * License:            GPL v2 or later
 * Text Domain:        shabake-tamin
 * Domain Path:        /languages
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

define( 'ST_VERSION', '1.3.0' );
define( 'ST_PLUGIN_FILE', __FILE__ );
define( 'ST_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );
define( 'ST_PLUGIN_URL', plugin_dir_url( __FILE__ ) );

require_once ST_PLUGIN_DIR . 'includes/class-st-loader.php';

Shabake_Tamin_Loader::instance();
