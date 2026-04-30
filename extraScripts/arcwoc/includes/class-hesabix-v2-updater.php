<?php
/**
 * Plugin update checker - reads version from repo and integrates with WordPress update system.
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

// If this file is called directly, abort.
if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Updater
{
	/**
	 * Transient key for caching remote version info.
	 */
	const CACHE_TRANSIENT = 'hesabix_v2_remote_version';

	/**
	 * Cache duration in seconds (12 hours).
	 */
	const CACHE_DURATION = 43200;

	/**
	 * Plugin basename (e.g. arcwoc/hesabix-v2.php).
	 *
	 * @var string
	 */
	private $plugin_basename;

	/**
	 * Constructor. Registers WordPress update filters.
	 */
	public function __construct()
	{
		$this->plugin_basename = plugin_basename(HESABIX_V2_PLUGIN_DIR . 'hesabix-v2.php');

		add_filter('pre_set_site_transient_update_plugins', array($this, 'inject_update_into_transient'), 10, 1);
		add_filter('plugins_api', array($this, 'plugins_api_info'), 20, 3);
		// وقتی وردپرس لیست به‌روزرسانی را پاک می‌کند (مثلاً با «بررسی مجدد»)، کش ما هم پاک شود
		add_action('delete_site_transient_update_plugins', array($this, 'clear_version_cache'));
	}

	/**
	 * پاک کردن کش نسخهٔ ریموت تا در چک بعدی از مخزن خوانده شود.
	 */
	public function clear_version_cache()
	{
		delete_site_transient(self::CACHE_TRANSIENT);
	}

	/**
	 * Build package (ZIP) URL from version.json.
	 * - If download_url is set: supports %VERSION% and {version} placeholder for Release URLs.
	 * - If download_url is empty: uses HESABIX_V2_UPDATE_ARCHIVE_URL (e.g. archive/master.zip).
	 *
	 * @param object $info Decoded version.json.
	 * @return string Package URL or empty string.
	 */
	private function build_download_url($info)
	{
		$url = isset($info->download_url) ? trim($info->download_url) : '';
		if (empty($url)) {
			$url = defined('HESABIX_V2_UPDATE_ARCHIVE_URL') ? HESABIX_V2_UPDATE_ARCHIVE_URL : 'https://source.hesabix.ir/hesabix/ArcWOC/archive/refs/heads/main.zip';
		}
		if (empty($url) || empty($info->version)) {
			return '';
		}
		$version = $info->version;
		$url = str_replace(array('%VERSION%', '{version}'), $version, $url);
		return $url;
	}

	/**
	 * Fetch version info from remote (repo or fallback to local version.json).
	 *
	 * @return object|null Decoded JSON object or null on failure.
	 */
	private function get_remote_info()
	{
		$cached = get_site_transient(self::CACHE_TRANSIENT);
		if ($cached !== false && is_object($cached)) {
			return $cached;
		}

		$base = defined('HESABIX_V2_UPDATE_INFO_URL') ? HESABIX_V2_UPDATE_INFO_URL : 'https://source.hesabix.ir/hesabix/ArcWOC/raw/branch/main/version.json';
		$urls = array($base);
		if (strpos($base, '/main/') !== false) {
			$urls[] = str_replace('/main/', '/master/', $base);
		} elseif (strpos($base, '/master/') !== false) {
			$urls[] = str_replace('/master/', '/main/', $base);
		}

		$response = null;
		foreach ($urls as $url) {
			$response = wp_remote_get($url, array('timeout' => 10, 'sslverify' => true));
			if (!is_wp_error($response) && wp_remote_retrieve_response_code($response) === 200) {
				break;
			}
		}

		if (!$response || is_wp_error($response) || wp_remote_retrieve_response_code($response) !== 200) {
			$local = HESABIX_V2_PLUGIN_DIR . 'version.json';
			if (is_readable($local)) {
				$body = file_get_contents($local);
				$data = json_decode($body);
				if (is_object($data)) {
					set_site_transient(self::CACHE_TRANSIENT, $data, self::CACHE_DURATION);
					return $data;
				}
			}
			return null;
		}

		$body = wp_remote_retrieve_body($response);
		$data = json_decode($body);
		if (!is_object($data) || empty($data->version)) {
			return null;
		}

		set_site_transient(self::CACHE_TRANSIENT, $data, self::CACHE_DURATION);
		return $data;
	}

	/**
	 * Inject our plugin update into the update_plugins transient.
	 *
	 * @param object $transient Site transient update_plugins.
	 * @return object
	 */
	public function inject_update_into_transient($transient)
	{
		if (!is_object($transient)) {
			$transient = new stdClass();
		}

		if (empty($transient->checked)) {
			return $transient;
		}

		$current = defined('HESABIX_V2_VERSION') ? HESABIX_V2_VERSION : '2.0.0';
		$info = $this->get_remote_info();
		if (!$info || empty($info->version) || version_compare($current, $info->version, '>=')) {
			return $transient;
		}

		$package = $this->build_download_url($info);
		if (empty($package)) {
			return $transient;
		}

		$update = (object) array(
			'id' => 'https://hesabix.ir/',
			'slug' => 'arcwoc',
			'plugin' => $this->plugin_basename,
			'new_version' => $info->version,
			'url' => isset($info->homepage) ? $info->homepage : 'https://hesabix.ir/',
			'package' => $package,
			'icons' => array(),
			'banners' => array(),
			'banners_rtl' => array(),
			'tested' => isset($info->tested) ? $info->tested : '',
			'requires_php' => isset($info->requires_php) ? $info->requires_php : '7.4',
			'compatibility' => new stdClass(),
		);

		if (isset($info->requires)) {
			$update->requires = $info->requires;
		}
		if (isset($info->upgrade_notice)) {
			$update->upgrade_notice = $info->upgrade_notice;
		}

		$transient->response[$this->plugin_basename] = $update;
		return $transient;
	}

	/**
	 * Return plugin info for the "View details" / plugins_api request.
	 *
	 * @param false|object|array $result Result of plugins_api().
	 * @param string             $action Action (e.g. plugin_information).
	 * @param object             $args   Arguments.
	 * @return false|object
	 */
	public function plugins_api_info($result, $action, $args)
	{
		if ($action !== 'plugin_information') {
			return $result;
		}

		$slug = isset($args->slug) ? $args->slug : '';
		if ($slug !== 'arcwoc') {
			return $result;
		}

		$info = $this->get_remote_info();
		if (!$info || empty($info->version)) {
			return $result;
		}

		$res = new stdClass();
		$res->name = isset($info->name) ? $info->name : 'Hesabix V2: WooCommerce';
		$res->slug = 'arcwoc';
		$res->version = $info->version;
		$res->author = isset($info->author) ? $info->author : 'Hesabix Team';
		$res->homepage = isset($info->homepage) ? $info->homepage : 'https://hesabix.ir/';
		$res->download_link = $this->build_download_url($info);
		$res->requires = isset($info->requires) ? $info->requires : '5.0';
		$res->tested = isset($info->tested) ? $info->tested : '';
		$res->requires_php = isset($info->requires_php) ? $info->requires_php : '7.4';
		$res->last_updated = isset($info->last_updated) ? $info->last_updated : '';
		$res->sections = isset($info->sections) && is_object($info->sections) ? (array) $info->sections : array(
			'description' => 'اتصال ووکامرس به نسخه جدید حسابیکس با API پیشرفته.',
			'changelog' => '<p>نسخه ' . esc_html($info->version) . '</p>',
		);

		return $res;
	}
}
