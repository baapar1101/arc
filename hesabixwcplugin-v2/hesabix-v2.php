<?php
/**
 * @link              https://hesabix.ir/
 * @since             2.0.0
 * @package           Hesabix_V2
 *
 * @wordpress-plugin
 * Plugin Name:       Hesabix V2: WooCommerce
 * Plugin URI:        https://hesabix.ir/
 * Description:       اتصال ووکامرس به نسخه جدید حسابیکس با API پیشرفته - نسخه دوم با پشتیبانی از API Key و امکانات جدید
 * Version:           2.0.0
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
define('HESABIX_V2_VERSION', '2.0.0');
define('HESABIX_V2_PLUGIN_URL', plugin_dir_url(__FILE__));
define('HESABIX_V2_PLUGIN_DIR', plugin_dir_path(__FILE__));
define('HESABIX_V2_API_BASE_URL', 'https://api.hesabix.ir/v1');

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
 * Check if WooCommerce is active
 */
if (!in_array('woocommerce/woocommerce.php', apply_filters('active_plugins', get_option('active_plugins')))) {
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

/**
 * Check if old version is active
 */
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

/**
 * The core plugin class that is used to define internationalization,
 * admin-specific hooks, and public-facing site hooks.
 */
require HESABIX_V2_PLUGIN_DIR . 'includes/class-hesabix-v2.php';

/**
 * Begins execution of the plugin.
 */
function run_hesabix_v2()
{
	$plugin = new Hesabix_V2();
	$plugin->run();
}

run_hesabix_v2();

