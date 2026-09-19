<?php
/**
 * Plugin Name:       Hesabix Install Stats
 * Plugin URI:        https://hesabix.ir
 * Description:       دریافت و گزارش آمار نصب/به‌روزرسانی سرورهای Hesabix (دامنه، سخت‌افزار، نسخه). مخصوص سایت مرکزی hesabix.ir.
 * Version:           1.1.0
 * Requires at least: 5.8
 * Requires PHP:      7.4
 * Author:            Hesabix Team
 * Author URI:        https://hesabix.ir
 * License:           GPL-3.0+
 * License URI:       http://www.gnu.org/licenses/gpl-3.0.txt
 * Text Domain:       hesabix-install-stats
 * Domain Path:       /languages
 *
 * @package Hesabix_Install_Stats
 */

defined( 'ABSPATH' ) || exit;

define( 'HIS_VERSION', '1.1.0' );
define( 'HIS_PLUGIN_FILE', __FILE__ );
define( 'HIS_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );
define( 'HIS_PLUGIN_URL', plugin_dir_url( __FILE__ ) );
define( 'HIS_DB_VERSION', '1.0.0' );

/**
 * توکن پیش‌فرض ingest (قابل تغییر در تنظیمات افزونه).
 * اسکریپت‌های deploy/update همین مقدار را به‌صورت پیش‌فرض می‌فرستند.
 */
define( 'HIS_DEFAULT_INGEST_TOKEN', 'hesabix-stats-ingest-v1' );

require_once HIS_PLUGIN_DIR . 'includes/class-his-storage.php';
require_once HIS_PLUGIN_DIR . 'includes/class-his-activator.php';
require_once HIS_PLUGIN_DIR . 'includes/class-his-rest.php';
require_once HIS_PLUGIN_DIR . 'includes/class-his-reports.php';
require_once HIS_PLUGIN_DIR . 'includes/class-his-admin.php';

/**
 * فعال‌سازی: جداول و گزینه‌ها.
 */
function his_activate() {
	HIS_Activator::activate();
}
register_activation_hook( __FILE__, 'his_activate' );

/**
 * بارگذاری textdomain.
 */
function his_load_textdomain() {
	load_plugin_textdomain(
		'hesabix-install-stats',
		false,
		dirname( plugin_basename( HIS_PLUGIN_FILE ) ) . '/languages'
	);
}
add_action( 'plugins_loaded', 'his_load_textdomain', 0 );

/**
 * اطمینان از به‌روز بودن schema در صورت به‌روزرسانی فایل افزونه بدون deactivate.
 */
function his_maybe_upgrade_db() {
	$installed = (string) get_option( 'his_db_version', '' );
	if ( $installed !== HIS_DB_VERSION ) {
		HIS_Activator::activate();
	}
}
add_action( 'plugins_loaded', 'his_maybe_upgrade_db', 5 );

HIS_REST::instance();
HIS_Admin::instance();
