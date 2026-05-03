<?php
/**
 * به‌روزرسانی: خواندن نسخه از فایل hesabix-v2.php در مخزن (raw) + بستهٔ zip آرشیو؛ اختیاری: مانیفست JSON.
 *
 * @package Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}

/** Ajax: بررسی نسخه */
const HESABIX_V2_UPDATE_AJAX_CHECK = 'hesabix_v2_update_check';

/** Ajax: نصب از بسته */
const HESABIX_V2_UPDATE_AJAX_INSTALL = 'hesabix_v2_update_install';

const HESABIX_V2_UPDATE_NONCE_ACTION = 'hesabix_v2_update_v1';

/**
 * Class Hesabix_V2_Updater
 */
class Hesabix_V2_Updater {

	const CACHE_TTL = 43200;

	/** @var self|null */
	private static $instance = null;

	/**
	 * @return self
	 */
	public static function init() {
		if (null === self::$instance) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	/**
	 * @return self|null
	 */
	public static function instance() {
		return self::$instance ?: self::init();
	}

	/**
	 * @return string
	 */
	private function get_update_cache_key() {
		return 'hesabix_v2_upd_' . md5($this->get_raw_php_url() . '|' . $this->get_archive_zip_url() . '|' . $this->get_manifest_url());
	}

	/**
	 * @param string $context raw_php|manifest|zip_head .
	 * @return array<string, mixed>
	 */
	private function remote_get_args($context = 'raw_php') {
		$accept = 'text/plain';
		if ('manifest' === $context) {
			$accept = 'application/json';
		}
		$ver = defined('HESABIX_V2_VERSION') ? (string) HESABIX_V2_VERSION : '0';
		$args = array(
			'timeout' => 15,
			'redirection' => 8,
			'sslverify' => true,
			'headers' => array(
				'Accept' => $accept,
				'User-Agent' => 'ArcWOC-HesabixV2-WordPress/' . $ver . '; ' . get_bloginfo('url'),
			),
		);
		return (array) apply_filters('hesabix_v2_update_http_args', $args, $context);
	}

	/**
	 * @param string $body .
	 * @return string
	 */
	private function strip_utf8_bom($body) {
		$body = (string) $body;
		if (strncmp($body, "\xEF\xBB\xBF", 3) === 0) {
			return substr($body, 3);
		}
		return $body;
	}

	private function __construct() {
		add_filter('pre_set_site_transient_update_plugins', array($this, 'filter_update_transient'));
		add_filter('plugins_api', array($this, 'plugin_info'), 10, 3);
		add_filter('upgrader_source_selection', array($this, 'align_extracted_plugin_folder'), 10, 4);
		add_action('wp_ajax_' . HESABIX_V2_UPDATE_AJAX_CHECK, array($this, 'ajax_update_check'));
		add_action('wp_ajax_' . HESABIX_V2_UPDATE_AJAX_INSTALL, array($this, 'ajax_update_install'));
		add_action('delete_site_transient_update_plugins', array($this, 'clear_package_cache'));
	}

	/**
	 * سازگاری با کش قدیمی transient تک‌کلیده.
	 */
	public function clear_package_cache() {
		delete_site_transient($this->get_update_cache_key());
		delete_site_transient('hesabix_v2_remote_version');
	}

	/**
	 * @return string
	 */
	public function get_raw_php_url() {
		$url = defined('HESABIX_V2_UPDATE_RAW_PHP_URL') ? (string) HESABIX_V2_UPDATE_RAW_PHP_URL : '';
		return esc_url_raw((string) apply_filters('hesabix_v2_update_raw_php_url', $url));
	}

	/**
	 * @return string
	 */
	public function get_archive_zip_url() {
		$url = defined('HESABIX_V2_UPDATE_ARCHIVE_ZIP_URL') ? (string) HESABIX_V2_UPDATE_ARCHIVE_ZIP_URL : '';
		if ($url === '' && defined('HESABIX_V2_UPDATE_ARCHIVE_URL')) {
			$url = (string) HESABIX_V2_UPDATE_ARCHIVE_URL;
		}
		return esc_url_raw((string) apply_filters('hesabix_v2_update_archive_zip_url', $url));
	}

	/**
	 * @return string
	 */
	public function get_manifest_url() {
		$url = defined('HESABIX_V2_UPDATE_MANIFEST_URL') ? (string) HESABIX_V2_UPDATE_MANIFEST_URL : '';
		if ($url === '' && defined('HESABIX_V2_UPDATE_INFO_URL')) {
			$url = (string) HESABIX_V2_UPDATE_INFO_URL;
		}
		return esc_url_raw((string) apply_filters('hesabix_v2_update_manifest_url', $url));
	}

	/**
	 * آدرس خام hesabix-v2.php برای خواندن نسخه (بدون نیاز به zip).
	 *
	 * @return bool
	 */
	private function is_raw_php_url_configured() {
		$r = $this->get_raw_php_url();
		if ($r === '') {
			return false;
		}
		return (0 === strpos($r, 'https://') || 0 === strpos($r, 'http://'));
	}

	/**
	 * هر دو آدرس raw + zip برای مسیر کامل نصب از مخزن.
	 *
	 * @return bool
	 */
	private function use_source_urls() {
		if (!$this->is_raw_php_url_configured()) {
			return false;
		}
		$z = $this->get_archive_zip_url();
		if ($z === '') {
			return false;
		}
		$ok_z = (0 === strpos($z, 'https://') || 0 === strpos($z, 'http://'));
		return $ok_z;
	}

	/**
	 * هدرهای readme افزونه معمولاً داخل DocBlock به صورت « * Version:» هستند.
	 *
	 * @param string $php .
	 * @return array<string, string>
	 */
	private function parse_main_file_headers($php) {
		$out = array(
			'version' => '',
			'requires' => '',
			'requires_php' => '',
		);
		// خطوط استاندارد وردپرس: «Version:» یا « * Version:»
		if (preg_match('/^\s*(?:\*\s*)?Version:\s*([0-9][0-9a-z.+-]*)\s*$/mi', $php, $m)) {
			$out['version'] = $m[1];
		} elseif (preg_match("/define\s*\(\s*['\"]HESABIX_V2_VERSION['\"]\s*,\s*['\"]([0-9][0-9a-z.+-]*)['\"]\s*\)/s", $php, $m)) {
			$out['version'] = $m[1];
		}
		if (preg_match('/^\s*(?:\*\s*)?Requires at least:\s*([0-9.]+)\s*$/mi', $php, $m)) {
			$out['requires'] = $m[1];
		}
		if (preg_match('/^\s*(?:\*\s*)?Requires PHP:\s*([0-9.]+)\s*$/mi', $php, $m)) {
			$out['requires_php'] = $m[1];
		}
		return $out;
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_info_from_source() {
		$url = $this->get_raw_php_url();
		$zip = $this->get_archive_zip_url();
		$resp = wp_remote_get($url, $this->remote_get_args('raw_php'));
		if (is_wp_error($resp) || (int) wp_remote_retrieve_response_code($resp) !== 200) {
			return null;
		}
		$body = $this->strip_utf8_bom(wp_remote_retrieve_body($resp));
		if ($body === null || $body === '') {
			return null;
		}
		if (stripos($body, '<html') !== false && stripos($body, '<?php') === false) {
			return null;
		}
		$headers = $this->parse_main_file_headers($body);
		if ($headers['version'] === '') {
			return null;
		}
		$zip = esc_url_raw($zip);
		if ($zip !== '' && 0 !== strpos($zip, 'https://') && 0 !== strpos($zip, 'http://')) {
			$zip = '';
		}
		return array(
			'version' => (string) $headers['version'],
			'download_url' => $zip,
			'requires' => (string) $headers['requires'],
			'tested' => '',
			'requires_php' => (string) $headers['requires_php'],
			'homepage' => 'https://hesabix.ir/',
			'last_updated' => '',
			'name' => 'Hesabix V2: WooCommerce',
			'sections' => array(),
			'package_hash' => '',
			'upgrade_notice' => '',
			'banners' => array(),
			'icons' => array(),
			'icon_svg' => '',
			'source' => 'raw',
		);
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_info_from_json_manifest() {
		$url = $this->get_manifest_url();
		if ($url === '' || (0 !== strpos($url, 'https://') && 0 !== strpos($url, 'http://'))) {
			return null;
		}
		$resp = wp_remote_get($url, $this->remote_get_args('manifest'));
		if (is_wp_error($resp) || (int) wp_remote_retrieve_response_code($resp) !== 200) {
			return null;
		}
		$b = wp_remote_retrieve_body($resp);
		if ($b === '' || $b === null) {
			return null;
		}
		$data = json_decode($b, true);
		if (!is_array($data) || empty($data['version'])) {
			return null;
		}
		$version = (string) $data['version'];
		$dl = isset($data['download_url']) ? trim((string) $data['download_url']) : '';
		if ($dl === '') {
			$dl = $this->get_archive_zip_url();
		} else {
			$dl = str_replace(array('%VERSION%', '{version}'), $version, $dl);
		}
		$dl = esc_url_raw($dl);
		if ($dl === '' || (0 !== strpos($dl, 'https://') && 0 !== strpos($dl, 'http://'))) {
			return null;
		}
		return array(
			'version' => $version,
			'download_url' => $dl,
			'requires' => isset($data['requires']) ? (string) $data['requires'] : '',
			'tested' => isset($data['tested']) ? (string) $data['tested'] : '',
			'requires_php' => isset($data['requires_php']) ? (string) $data['requires_php'] : '',
			'homepage' => isset($data['homepage']) ? (string) $data['homepage'] : 'https://hesabix.ir/',
			'last_updated' => isset($data['last_updated']) ? (string) $data['last_updated'] : '',
			'name' => isset($data['name']) ? (string) $data['name'] : 'Hesabix V2: WooCommerce',
			'sections' => isset($data['sections']) && is_array($data['sections']) ? $data['sections'] : array(),
			'package_hash' => isset($data['package_hash']) ? (string) $data['package_hash'] : '',
			'upgrade_notice' => isset($data['upgrade_notice']) ? (string) $data['upgrade_notice'] : '',
			'banners' => isset($data['banners']) && is_array($data['banners']) ? $data['banners'] : array(),
			'icons' => isset($data['icons']) && is_array($data['icons']) ? $data['icons'] : array(),
			'icon_svg' => isset($data['icon_svg']) ? (string) $data['icon_svg'] : '',
			'source' => 'json',
		);
	}

	/**
	 * @param bool $force_refresh .
	 * @return array<string, mixed>|null
	 */
	private function resolve_remote_package_cached($force_refresh = false) {
		$key = $this->get_update_cache_key();

		if ($force_refresh || (bool) apply_filters('hesabix_v2_update_force_check', false)) {
			delete_site_transient($key);
		}

		$cached = get_site_transient($key);
		if (is_array($cached) && !empty($cached['version'])) {
			return $cached;
		}

		$info = null;
		if ((bool) apply_filters('hesabix_v2_prefer_json_manifest', false) && $this->get_manifest_url() !== '') {
			$info = $this->get_info_from_json_manifest();
		}
		if ($info === null && $this->is_raw_php_url_configured()) {
			$info = $this->get_info_from_source();
		}
		if ($info === null && $this->get_manifest_url() !== '') {
			$info = $this->get_info_from_json_manifest();
		}
		if ($info === null) {
			return null;
		}

		set_site_transient(
			$key,
			$info,
			(int) apply_filters('hesabix_v2_update_cache_ttl', self::CACHE_TTL)
		);
		return $info;
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_remote_info() {
		$info = $this->resolve_remote_package_cached(false);
		if ($info === null) {
			return null;
		}
		if ($info['requires'] !== '' && version_compare(get_bloginfo('version'), $info['requires'], '<')) {
			return null;
		}
		if ($info['requires_php'] !== '' && version_compare((string) PHP_VERSION, $info['requires_php'], '<')) {
			return null;
		}
		return $info;
	}

	/**
	 * @param bool $force_refresh .
	 * @return array<string, scalar|bool|string>
	 */
	public function get_update_dashboard_state($force_refresh = false) {
		$current = defined('HESABIX_V2_VERSION') ? (string) HESABIX_V2_VERSION : '';
		$uses_raw_zip = $this->use_source_urls();
		$uses_manifest_o = $this->get_manifest_url() !== '';
		$configured = $uses_raw_zip || $uses_manifest_o;

		$pkg = $this->resolve_remote_package_cached($force_refresh);
		$remote_str = is_array($pkg) ? (string) ($pkg['version'] ?? '') : '';
		$remote_loaded = ($remote_str !== '');

		$download_url = is_array($pkg) ? (string) ($pkg['download_url'] ?? '') : '';
		$req_wp = is_array($pkg) ? (string) ($pkg['requires'] ?? '') : '';
		$req_php = is_array($pkg) ? (string) ($pkg['requires_php'] ?? '') : '';
		$source = is_array($pkg) ? (string) ($pkg['source'] ?? '') : '';

		$wp_ok = true;
		$php_ok = true;
		if ($remote_loaded) {
			if ($req_wp !== '' && version_compare(get_bloginfo('version'), $req_wp, '<')) {
				$wp_ok = false;
			}
			if ($req_php !== '' && version_compare((string) PHP_VERSION, $req_php, '<')) {
				$php_ok = false;
			}
		}

		$env_ok = $wp_ok && $php_ok;
		$newer = $remote_loaded && version_compare($remote_str, $current, '>');
		$update_available = $newer && $env_ok && $configured && $download_url !== '';

		return array(
			'current_version' => $current,
			'remote_version' => $remote_str,
			'remote_loaded' => $remote_loaded,
			'configured' => $configured,
			'configured_raw_zip' => $uses_raw_zip && $configured,
			'configured_manifest_only' => $uses_manifest_o && !$uses_raw_zip,
			'source_kind' => $source,
			'download_available' => ($download_url !== ''),
			'wp_compatible' => $wp_ok,
			'php_compatible' => $php_ok,
			'env_compatible' => $env_ok,
			'requires_wp' => $req_wp,
			'requires_php' => $req_php,
			'update_available' => $update_available,
			'newer_than_local' => $newer,
			'can_install' => self::current_user_can_update_via_ui(),
		);
	}

	/**
	 * @return bool
	 */
	public static function current_user_can_update_via_ui() {
		return current_user_can('manage_woocommerce') && current_user_can('update_plugins');
	}

	/**
	 * @param false|object $transient .
	 * @return object|false
	 */
	public function filter_update_transient($transient) {
		if (!is_object($transient) || empty($transient->checked) || !is_array($transient->checked)) {
			return $transient;
		}

		$plugin_file = plugin_basename(HESABIX_V2_PLUGIN_FILE);
		if (!isset($transient->checked[$plugin_file])) {
			return $transient;
		}

		$info = $this->get_remote_info();
		if ($info === null) {
			return $transient;
		}

		$current = (string) $transient->checked[$plugin_file];
		$new = (string) $info['version'];
		if (!version_compare($new, $current, '>')) {
			return $transient;
		}

		$home = !empty($info['homepage']) ? $info['homepage'] : 'https://hesabix.ir/';
		$item = array(
			'id' => $plugin_file,
			'slug' => dirname($plugin_file),
			'plugin' => $plugin_file,
			'new_version' => $new,
			'url' => esc_url($home),
			'package' => (string) $info['download_url'],
			'tested' => (string) ($info['tested'] ?? ''),
			'requires' => (string) ($info['requires'] ?? ''),
			'requires_php' => (string) ($info['requires_php'] ?? ''),
		);
		if (!empty($info['upgrade_notice'])) {
			$item['upgrade_notice'] = (string) $info['upgrade_notice'];
		}
		if (!empty($info['banners']) && is_array($info['banners'])) {
			$item['banners'] = $info['banners'];
		}
		if (!empty($info['icons']) && is_array($info['icons'])) {
			$item['icons'] = $info['icons'];
		} elseif (!empty($info['icon_svg'])) {
			$item['icons'] = array('1x' => (string) $info['icon_svg']);
		}

		$transient->response[$plugin_file] = (object) $item;
		return $transient;
	}

	/**
	 * @param false|object|array $res .
	 * @param string             $action .
	 * @param object             $args .
	 * @return false|object|array
	 */
	public function plugin_info($res, $action, $args) {
		if ('plugin_information' !== $action || !isset($args->slug)) {
			return $res;
		}
		$dir = dirname(plugin_basename(HESABIX_V2_PLUGIN_FILE));
		if ((string) $args->slug !== $dir) {
			return $res;
		}

		$info = $this->get_remote_info();
		if ($info === null) {
			$pkg = $this->resolve_remote_package_cached(false);
			if (is_array($pkg) && isset($pkg['version']) && (string) $pkg['version'] !== '') {
				$info = $pkg;
				if (empty($info['name'])) {
					$info['name'] = 'Hesabix V2: WooCommerce';
				}
				if (empty($info['homepage'])) {
					$info['homepage'] = 'https://hesabix.ir/';
				}
			} else {
				$info = array(
					'version' => HESABIX_V2_VERSION,
					'download_url' => '',
					'name' => 'Hesabix V2: WooCommerce',
					'homepage' => 'https://hesabix.ir/',
					'last_updated' => '',
					'sections' => array(),
				);
			}
		}

		$sections = array('description' => '');
		if (!empty($info['sections']) && is_array($info['sections'])) {
			foreach ($info['sections'] as $k => $v) {
				if (is_string($k) && is_string($v) && $v !== '') {
					$sections[$k] = wp_kses_post($v);
				}
			}
		}
		if (!empty($info['source']) && 'raw' === $info['source']) {
			$sections['description'] = esc_html__('منبع به‌روزرسانی: نسخه از فایل اصلی hesabix-v2.php در مخزن و بستهٔ zip همان شاخه.', 'hesabix-v2');
		} elseif (empty($sections['description'])) {
			$sections['description'] = esc_html__('اتصال ووکامرس به نسخهٔ جدید حسابیکس با API پیشرفته.', 'hesabix-v2');
		}

		$out = (object) array(
			'name' => $info['name'],
			'slug' => $dir,
			'version' => $info['version'],
			'author' => '<a href="https://hesabix.ir" target="_blank" rel="noopener">Hesabix</a>',
			'homepage' => !empty($info['homepage']) ? esc_url((string) $info['homepage']) : 'https://hesabix.ir/',
			'last_updated' => !empty($info['last_updated']) ? (string) $info['last_updated'] : null,
			'download_link' => !empty($info['download_url']) ? esc_url((string) $info['download_url']) : '',
			'sections' => $sections,
			'banners' => !empty($info['banners']) && is_array($info['banners']) ? $info['banners'] : array(),
		);
		if (!empty($info['icons']) && is_array($info['icons'])) {
			$out->icons = $info['icons'];
		}
		return $out;
	}

	public function ajax_update_check() {
		if (!current_user_can('manage_woocommerce')) {
			wp_send_json_error(array('message' => __('مجوز کافی نیست.', 'hesabix-v2')), 403);
		}

		check_ajax_referer(HESABIX_V2_UPDATE_NONCE_ACTION, 'nonce');

		$refresh = isset($_POST['refresh'])
			&& ('1' === (string) wp_unslash($_POST['refresh']) || 'true' === (string) wp_unslash($_POST['refresh']));

		wp_send_json_success($this->get_update_dashboard_state($refresh));
	}

	public function ajax_update_install() {
		if (!self::current_user_can_update_via_ui()) {
			wp_send_json_error(array('message' => __('مجوز به‌روزرسانی افزونه را ندارید.', 'hesabix-v2')), 403);
		}

		check_ajax_referer(HESABIX_V2_UPDATE_NONCE_ACTION, 'nonce');

		$this->purge_update_caches_before_install();

		$pkg = $this->resolve_remote_package_cached(true);
		if (!is_array($pkg) || empty($pkg['download_url'])) {
			wp_send_json_error(array('message' => __('دریافت اطلاعات بستهٔ به‌روزرسانی ناموفق بود یا منبعی تنظیم نشده.', 'hesabix-v2')));
		}

		$download = esc_url_raw((string) $pkg['download_url']);
		if (strpos($download, 'http://') !== 0 && strpos($download, 'https://') !== 0) {
			wp_send_json_error(array('message' => __('آدرس بستهٔ نامعتبر است.', 'hesabix-v2')));
		}

		$plugin_file = plugin_basename(HESABIX_V2_PLUGIN_FILE);
		$current = defined('HESABIX_V2_VERSION') ? (string) HESABIX_V2_VERSION : '';
		$new_version = isset($pkg['version']) ? (string) $pkg['version'] : '';

		if ('' === $new_version || '' === $current) {
			wp_send_json_error(array('message' => __('تشخیص نسخه ممکن نیست.', 'hesabix-v2')));
		}

		if (!version_compare($new_version, $current, '>')) {
			wp_send_json_error(array('message' => __('به‌روزرسانی جدیدی نسبت به نسخهٔ فعلی در دسترس نیست.', 'hesabix-v2')));
		}

		$requires = isset($pkg['requires']) ? (string) $pkg['requires'] : '';
		if ($requires !== '' && version_compare(get_bloginfo('version'), $requires, '<')) {
			wp_send_json_error(
				array(
					'message' => sprintf(
						__('وردپرس باید حداقل نسخهٔ %s باشد.', 'hesabix-v2'),
						$requires
					),
				)
			);
		}
		$requires_php = isset($pkg['requires_php']) ? (string) $pkg['requires_php'] : '';
		if ($requires_php !== '' && version_compare((string) PHP_VERSION, $requires_php, '<')) {
			wp_send_json_error(
				array(
					'message' => sprintf(
						__('PHP باید حداقل نسخهٔ %s باشد.', 'hesabix-v2'),
						$requires_php
					),
				)
			);
		}

		if (function_exists('wp_raise_memory_limit')) {
			wp_raise_memory_limit('admin');
		}
		if (function_exists('wc_set_time_limit')) {
			wc_set_time_limit(0);
		} elseif (function_exists('set_time_limit')) {
			@set_time_limit(600);
		}

		require_once ABSPATH . 'wp-admin/includes/file.php';
		require_once ABSPATH . 'wp-admin/includes/plugin.php';
		require_once ABSPATH . 'wp-admin/includes/class-wp-upgrader.php';

		if (!class_exists('Automatic_Upgrader_Skin')) {
			wp_send_json_error(array('message' => __('کلاس‌های به‌روزرسانی وردپرس در دسترس نیستند.', 'hesabix-v2')));
		}

		if (false === WP_Filesystem()) {
			wp_send_json_error(
				array(
					'message' => __('اتصال به فایل سیستم نشد. روش دسترسی به فایل‌ها را از wp-config یا هاست تنظیم کنید.', 'hesabix-v2'),
				)
			);
		}

		$skin = new Automatic_Upgrader_Skin();
		$upgrader = new Plugin_Upgrader($skin);

		$result = $upgrader->run(
			array(
				'package' => $download,
				'destination' => WP_PLUGIN_DIR,
				'clear_destination' => true,
				'clear_working' => true,
				'clear_update_cache' => false,
				'is_multi' => false,
				'hook_extra' => array(
					'plugin' => $plugin_file,
				),
			)
		);

		delete_site_transient($this->get_update_cache_key());

		if (false === $result || is_wp_error($result)) {
			$msg = is_wp_error($result)
				? $result->get_error_message()
				: __('به‌روزرسانی افزونه با خطا متوقف شد.', 'hesabix-v2');
			if (isset($skin, $skin->result) && is_wp_error($skin->result)) {
				$skin_msg = $skin->result->get_error_message();
				if ('' !== $skin_msg && $skin_msg !== $msg) {
					$msg = $skin_msg . ' — ' . $msg;
				}
			}
			wp_send_json_error(array('message' => $msg), 500);
		}

		wp_clean_plugins_cache();

		wp_send_json_success(
			array(
				'message' => __('به‌روزرسانی با موفقیت انجام شد؛ صفحه به‌روز می‌شود…', 'hesabix-v2'),
				'new_version' => $new_version,
			)
		);
	}

	private function purge_update_caches_before_install() {
		delete_site_transient($this->get_update_cache_key());
		delete_site_transient('hesabix_v2_remote_version');
	}

	/**
	 * @param string|WP_Error      $source .
	 * @param string|WP_Error      $remote_source .
	 * @param WP_Upgrader          $upgrader .
	 * @param array<string, mixed> $extra .
	 * @return string|WP_Error
	 */
	public function align_extracted_plugin_folder($source, $remote_source, $upgrader, $extra = array()) {
		if (is_wp_error($source) || !is_string($source) || $source === '') {
			return $source;
		}
		if (empty($extra['plugin']) || (string) $extra['plugin'] !== plugin_basename(HESABIX_V2_PLUGIN_FILE)) {
			return $source;
		}

		$expected_name = dirname((string) $extra['plugin']);
		if (basename($source) === $expected_name) {
			return $source;
		}

		global $wp_filesystem;
		if (!$wp_filesystem || !is_object($wp_filesystem)) {
			return $source;
		}

		$new = trailingslashit(dirname($source)) . $expected_name;
		if ($wp_filesystem->exists($new)) {
			$wp_filesystem->delete($new, true);
		}
		if ($wp_filesystem->move($source, $new)) {
			return $new;
		}
		return $source;
	}
}
