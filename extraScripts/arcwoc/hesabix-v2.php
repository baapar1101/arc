<?php
/**
 * @link              https://hesabix.ir/
 * @since             3.1.2
 * @package           Hesabix_V2
 *
 * @wordpress-plugin
 * Plugin Name:       Hesabix V2: WooCommerce
 * Plugin URI:        https://hesabix.ir/
 * Description:       اتصال ووکامرس به نسخه جدید حسابیکس با API پیشرفته - نسخه دوم با پشتیبانی از API Key و امکانات جدید
 * Version:           3.5.0
 * Author:            Hesabix Team
 * Author URI:        https://hesabix.ir
 * License:           GPL-3.0+
 * License URI:       http://www.gnu.org/licenses/gpl-3.0.txt
 * Text Domain:       hesabix-v2
 * Domain Path:       /languages
 * WC requires at least: 6.0.0
 * WC tested up to: 8.5.0
 * Requires PHP:      7.4
 */

// If this file is called directly, abort.
if (!defined('WPINC')) {
	die;
}

/**
 * Currently plugin version.
 */
define('HESABIX_V2_VERSION', '3.5.0');
define('HESABIX_V2_PLUGIN_FILE', __FILE__);
define('HESABIX_V2_PLUGIN_URL', plugin_dir_url(__FILE__));
define('HESABIX_V2_PLUGIN_DIR', plugin_dir_path(__FILE__));
define('HESABIX_V2_API_BASE_URL', 'https://hsxn.hesabix.ir/api/v1');

/**
 * به‌روزرسانی: نسخه از hesabix-v2.php به‌صورت raw؛ بسته از archive همان شاخه.
 * مسیر «raw» همان محتوای فایلی است که در مرورگر با /src/branch/… دیده می‌شود.
 *
 * @see https://source.hesabix.ir/hesabix/ArcWOC
 */
if (!defined('HESABIX_V2_UPDATE_RAW_PHP_URL')) {
	define(
		'HESABIX_V2_UPDATE_RAW_PHP_URL',
		'https://source.hesabix.ir/hesabix/ArcWOC/raw/branch/master/hesabix-v2.php'
	);
}
if (!defined('HESABIX_V2_UPDATE_ARCHIVE_ZIP_URL')) {
	define(
		'HESABIX_V2_UPDATE_ARCHIVE_ZIP_URL',
		'https://source.hesabix.ir/hesabix/ArcWOC/archive/refs/heads/master.zip'
	);
}
/**
 * اختیاری: مانیفست JSON در صورت نیاز به fallback (خالی = غیرفعال).
 */
if (!defined('HESABIX_V2_UPDATE_MANIFEST_URL')) {
	define(
		'HESABIX_V2_UPDATE_MANIFEST_URL',
		'https://source.hesabix.ir/hesabix/ArcWOC/raw/branch/master/version.json'
	);
}

/**
 * @deprecated سازگاری با wp-config قدیمی؛ در صورت تعریف، به‌عنوان نشانی مانیفست JSON هم استفاده می‌شود.
 */
if (!defined('HESABIX_V2_UPDATE_INFO_URL')) {
	define('HESABIX_V2_UPDATE_INFO_URL', '');
}
/**
 * @deprecated سازگاری با wp-config قدیمی؛ اگر HESABIX_V2_UPDATE_ARCHIVE_ZIP_URL خالی باشد خوانده می‌شود.
 */
if (!defined('HESABIX_V2_UPDATE_ARCHIVE_URL')) {
	define('HESABIX_V2_UPDATE_ARCHIVE_URL', HESABIX_V2_UPDATE_ARCHIVE_ZIP_URL);
}

/**
 * Plugin updater: مخزن + یکپارچگی با صفحهٔ به‌روزرسانی افزونه‌ها و تب تنظیمات.
 */
require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-updater.php';
Hesabix_V2_Updater::init();

/**
 * Declare compatibility with WooCommerce HPOS (Custom Order Tables).
 * Must run before woocommerce_init.
 */
add_action('before_woocommerce_init', function() {
	if (class_exists(\Automattic\WooCommerce\Utilities\FeaturesUtil::class)) {
		\Automattic\WooCommerce\Utilities\FeaturesUtil::declare_compatibility('custom_order_tables', __FILE__, true);
	}
});

/**
 * بازهٔ کرون هر ۵ دقیقه باید همیشه در فیلتر cron_schedules ثبت شود.
 * قبلاً فقط در هنگام پارسِ فایلٔ فعال‌سازی ثبت می‌شد؛ بعد از آن روی اکثر بارگذاری‌ها هرگز اعمال نمی‌شد و رویداد {@see hesabix_v2_process_queue} خطای invalid_schedule می‌گرفت.
 */
add_filter('cron_schedules', static function ($schedules) {
	if (!is_array($schedules)) {
		$schedules = array();
	}
	$schedules['every_5_minutes'] = array(
		'interval' => 300,
		'display'  => 'Every 5 minutes (Hesabix)',
	);

	return $schedules;
});

/**
 * The code that runs during plugin activation.
 */
function activate_hesabix_v2()
{
	require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-activator.php';
	Hesabix_V2_Activator::activate();
}

/**
 * The code that runs during plugin deactivation.
 */
function deactivate_hesabix_v2()
{
	require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2-deactivator.php';
	Hesabix_V2_Deactivator::deactivate();
}

register_activation_hook(__FILE__, 'activate_hesabix_v2');
register_deactivation_hook(__FILE__, 'deactivate_hesabix_v2');

/**
 * Check if WooCommerce is active (works with normal, network-activated, and load order).
 * Run plugin bootstrap after all plugins are loaded.
 */
function hesabix_v2_bootstrap()
{
	if (!class_exists('WooCommerce')) {
		add_action('admin_notices', function() {
			echo '<div class="error"><p>';
			echo sprintf(
				__('افزونه Hesabix V2 نیاز به %s دارد!', 'hesabix-v2'),
				'<a href="https://wordpress.org/plugins/woocommerce/" target="_blank">WooCommerce</a>'
			);
			echo '</p></div>';
		});
		return;
	}

	if (!function_exists('is_plugin_active')) {
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
	}

	// Check if old version is active (is_plugin_active only exists in admin)
	if (is_plugin_active('hesabixwcplugin/hesabix.php')) {
		add_action('admin_notices', function() {
			echo '<div class="notice notice-info is-dismissible">';
			echo '<p><strong>' . __('توجه:', 'hesabix-v2') . '</strong> ';
			echo sprintf(
				__('نسخه قدیمی افزونه حسابیکس نیز فعال است. برای مایگریشن به <a href="%s">صفحه مایگریشن</a> بروید.', 'hesabix-v2'),
				admin_url('admin.php?page=hesabix-v2-migration')
			);
			echo '</p></div>';
		});
	}

	require_once HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2.php';
	$plugin = new Hesabix_V2();
	$plugin->run();
}

add_action('plugins_loaded', 'hesabix_v2_bootstrap', 20);

