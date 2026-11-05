<?php
/**
 * ریبرند نمایشی افزونه پس از اتصال به نمونهٔ حسابیکس.
 *
 * منبع حقیقت: ‎.deploy_env همان سرور (از طریق GET /system/branding).
 * داده بیرون از پوشهٔ افزونه ذخیره می‌شود تا با آپدیت از بین نرود.
 * بدون اتصال / حالت پیش‌فرض: هیچ جایگزینی انجام نمی‌شود.
 *
 * @package Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Brand
{
	const OPTION_KEY = 'hesabix_v2_brand';
	const REFRESH_TRANSIENT = 'hesabix_v2_brand_refresh';
	const REFRESH_TTL = 43200;
	const UPLOAD_SUBDIR = 'hesabix-v2-branding';
	const TEXT_DOMAIN = 'hesabix-v2';

	/** @var array<string,mixed>|null */
	private static $config_cache = null;

	/** @var bool|null */
	private static $active_cache = null;

	/** @var bool */
	private static $booted = false;

	/** @var bool */
	private static $replacing = false;

	/** @var string|null */
	private static $locale_cache = null;

	/**
	 * @return void
	 */
	public static function init()
	{
		if (self::$booted) {
			return;
		}
		self::$booted = true;

		add_filter('gettext', array(__CLASS__, 'filter_gettext'), 20, 3);
		add_filter('gettext_with_context', array(__CLASS__, 'filter_gettext_with_context'), 20, 4);
		add_filter('ngettext', array(__CLASS__, 'filter_ngettext'), 20, 5);
		add_filter('ngettext_with_context', array(__CLASS__, 'filter_ngettext_with_context'), 20, 6);
		add_filter('all_plugins', array(__CLASS__, 'filter_all_plugins'));
	}

	/**
	 * @return bool
	 */
	public static function is_connected()
	{
		if (!function_exists('get_option')) {
			return false;
		}
		$key = (string) get_option('hesabix_v2_api_key', '');
		$enabled = (bool) get_option('hesabix_v2_enabled', false);
		return ($key !== '' && $enabled);
	}

	/**
	 * @return array{
	 *   enabled:bool,
	 *   name_fa:string,
	 *   name_en:string,
	 *   has_logo:bool,
	 *   logo_etag:string,
	 *   logo_rel:string,
	 *   fetched_at:int,
	 *   source_api:string
	 * }
	 */
	public static function config()
	{
		if (self::$config_cache !== null) {
			return self::$config_cache;
		}

		$defaults = array(
			'enabled' => false,
			'name_fa' => '',
			'name_en' => '',
			'has_logo' => false,
			'logo_etag' => '',
			'logo_rel' => '',
			'fetched_at' => 0,
			'source_api' => '',
		);

		$raw = get_option(self::OPTION_KEY, array());
		if (!is_array($raw)) {
			$raw = array();
		}

		self::$config_cache = array_merge($defaults, $raw);
		self::$config_cache['enabled'] = !empty(self::$config_cache['enabled']);
		self::$config_cache['name_fa'] = trim((string) self::$config_cache['name_fa']);
		self::$config_cache['name_en'] = trim((string) self::$config_cache['name_en']);
		self::$config_cache['has_logo'] = !empty(self::$config_cache['has_logo']);
		self::$config_cache['logo_etag'] = (string) self::$config_cache['logo_etag'];
		self::$config_cache['logo_rel'] = (string) self::$config_cache['logo_rel'];
		self::$config_cache['fetched_at'] = (int) self::$config_cache['fetched_at'];
		self::$config_cache['source_api'] = (string) self::$config_cache['source_api'];

		return self::$config_cache;
	}

	/**
	 * آیا ریبرند متنی باید اعمال شود؟
	 *
	 * @return bool
	 */
	public static function is_active()
	{
		if (self::$active_cache !== null) {
			return self::$active_cache;
		}
		if (!self::is_connected()) {
			self::$active_cache = false;
			return false;
		}
		$cfg = self::config();
		self::$active_cache = (!empty($cfg['enabled']) && ($cfg['name_fa'] !== '' || $cfg['name_en'] !== ''));
		return self::$active_cache;
	}

	/**
	 * @param string $language_code
	 * @return string
	 */
	public static function display_name($language_code = '')
	{
		$cfg = self::config();
		$code = strtolower((string) $language_code);
		if ($code === '') {
			$code = self::current_locale_code();
		}
		$fa = $cfg['name_fa'];
		$en = $cfg['name_en'];
		$prefer_fa = (strpos($code, 'fa') === 0);
		if ($prefer_fa) {
			if ($fa !== '') {
				return $fa;
			}
			return $en;
		}
		if ($en !== '') {
			return $en;
		}
		return $fa;
	}

	/**
	 * جایگزینی حسابیکس / Hesabix وقتی ریبرند فعال است.
	 *
	 * @param string $input
	 * @param string $language_code
	 * @return string
	 */
	public static function rebrand($input, $language_code = '')
	{
		if (!is_string($input) || $input === '' || !self::is_active()) {
			return $input;
		}
		if (
			strpos($input, 'حسابیکس') === false
			&& strpos($input, 'حساب‌یکس') === false
			&& strpos($input, 'Hesabix') === false
		) {
			return $input;
		}
		$name = self::display_name($language_code);
		if ($name === '') {
			return $input;
		}
		return str_replace(
			array('حسابیکس', 'حساب‌یکس', 'Hesabix'),
			$name,
			$input
		);
	}

	/**
	 * @param string $translated
	 * @param string $text
	 * @param string $domain
	 * @return string
	 */
	public static function filter_gettext($translated, $text, $domain)
	{
		if ($domain !== self::TEXT_DOMAIN || self::$replacing) {
			return $translated;
		}
		self::$replacing = true;
		try {
			return self::rebrand((string) $translated);
		} finally {
			self::$replacing = false;
		}
	}

	/**
	 * @param string $translated
	 * @param string $text
	 * @param string $context
	 * @param string $domain
	 * @return string
	 */
	public static function filter_gettext_with_context($translated, $text, $context, $domain)
	{
		unset($text, $context);
		if ($domain !== self::TEXT_DOMAIN || self::$replacing) {
			return $translated;
		}
		self::$replacing = true;
		try {
			return self::rebrand((string) $translated);
		} finally {
			self::$replacing = false;
		}
	}

	/**
	 * @param string $translated
	 * @param string $single
	 * @param string $plural
	 * @param int    $number
	 * @param string $domain
	 * @return string
	 */
	public static function filter_ngettext($translated, $single, $plural, $number, $domain)
	{
		unset($single, $plural, $number);
		if ($domain !== self::TEXT_DOMAIN || self::$replacing) {
			return $translated;
		}
		self::$replacing = true;
		try {
			return self::rebrand((string) $translated);
		} finally {
			self::$replacing = false;
		}
	}

	/**
	 * @param string $translated
	 * @param string $single
	 * @param string $plural
	 * @param int    $number
	 * @param string $context
	 * @param string $domain
	 * @return string
	 */
	public static function filter_ngettext_with_context($translated, $single, $plural, $number, $context, $domain)
	{
		unset($single, $plural, $number, $context);
		if ($domain !== self::TEXT_DOMAIN || self::$replacing) {
			return $translated;
		}
		self::$replacing = true;
		try {
			return self::rebrand((string) $translated);
		} finally {
			self::$replacing = false;
		}
	}

	/**
	 * نام نمایشی در فهرست افزونه‌های وردپرس.
	 *
	 * @param array<string,array<string,mixed>> $plugins
	 * @return array<string,array<string,mixed>>
	 */
	public static function filter_all_plugins($plugins)
	{
		if (!is_array($plugins) || !self::is_active()) {
			return $plugins;
		}
		$file = defined('HESABIX_V2_PLUGIN_FILE') ? plugin_basename(HESABIX_V2_PLUGIN_FILE) : '';
		if ($file === '' || !isset($plugins[$file]) || !is_array($plugins[$file])) {
			return $plugins;
		}
		foreach (array('Name', 'Title', 'Description', 'Author', 'AuthorName') as $field) {
			if (!empty($plugins[$file][$field]) && is_string($plugins[$file][$field])) {
				$plugins[$file][$field] = self::rebrand($plugins[$file][$field]);
			}
		}
		return $plugins;
	}

	/**
	 * آیکون منوی ادمین: لوگوی سفارشی در uploads، وگرنه فایل پیش‌فرض افزونه.
	 *
	 * @return string
	 */
	public static function menu_icon_url()
	{
		$default = defined('HESABIX_V2_PLUGIN_URL')
			? HESABIX_V2_PLUGIN_URL . 'assets/img/menu-icon.png'
			: '';
		if (!self::is_connected()) {
			return $default;
		}
		$cfg = self::config();
		if (empty($cfg['has_logo'])) {
			return $default;
		}
		$path = self::logo_absolute_path($cfg);
		if ($path === '' || !is_readable($path)) {
			return $default;
		}
		$url = self::logo_public_url($cfg);
		return $url !== '' ? $url : $default;
	}

	/**
	 * تازه‌سازی دوره‌ای وقتی ادمین وردپرس باز است.
	 *
	 * @return void
	 */
	public static function maybe_refresh_from_api()
	{
		if (defined('DOING_AJAX') && DOING_AJAX) {
			return;
		}
		if (!self::is_connected()) {
			return;
		}
		if (get_transient(self::REFRESH_TRANSIENT)) {
			return;
		}
		if (!class_exists('Hesabix_V2_Api', false)) {
			return;
		}
		self::sync_from_api(new Hesabix_V2_Api(), false);
	}

	/**
	 * دریافت برند از API متصل و ذخیره در option / uploads.
	 *
	 * @param Hesabix_V2_Api|null $api
	 * @param bool                $force
	 * @return bool
	 */
	public static function sync_from_api($api = null, $force = false)
	{
		if (!self::is_connected() && !$force) {
			return false;
		}
		if (!$force && get_transient(self::REFRESH_TRANSIENT)) {
			return true;
		}
		if ($api === null) {
			if (!class_exists('Hesabix_V2_Api', false)) {
				return false;
			}
			$api = new Hesabix_V2_Api();
		}

		$result = $api->get_system_branding();
		if (!is_array($result)) {
			return false;
		}

		$status = isset($result['status_code']) ? (int) $result['status_code'] : 0;
		if (!empty($result['success'])) {
			$data = isset($result['data']) && is_array($result['data']) ? $result['data'] : array();
			self::apply_remote_payload($api, $data);
			set_transient(self::REFRESH_TRANSIENT, 1, self::REFRESH_TTL);
			return true;
		}

		if ($status === 404) {
			self::store_default_brand((string) get_option('hesabix_v2_api_base_url', ''));
			set_transient(self::REFRESH_TRANSIENT, 1, self::REFRESH_TTL);
			return true;
		}

		return false;
	}

	/**
	 * پاک‌سازی برند محلی (قطع اتصال → برگشت به ظاهر حسابیکس).
	 *
	 * @return void
	 */
	public static function clear_local()
	{
		self::delete_logo_files();
		delete_option(self::OPTION_KEY);
		delete_transient(self::REFRESH_TRANSIENT);
		self::flush_cache();
	}

	/**
	 * @return void
	 */
	public static function flush_cache()
	{
		self::$config_cache = null;
		self::$active_cache = null;
		self::$locale_cache = null;
	}

	/**
	 * @return string
	 */
	private static function current_locale_code()
	{
		if (self::$locale_cache !== null) {
			return self::$locale_cache;
		}
		$code = 'fa';
		if (function_exists('determine_locale')) {
			$code = (string) determine_locale();
		} elseif (function_exists('get_locale')) {
			$code = (string) get_locale();
		}
		self::$locale_cache = strtolower($code);
		return self::$locale_cache;
	}

	/**
	 * @param Hesabix_V2_Api     $api
	 * @param array<string,mixed> $data
	 * @return void
	 */
	private static function apply_remote_payload($api, array $data)
	{
		$enabled = !empty($data['enabled']);
		$name_fa = self::sanitize_brand_name(isset($data['name_fa']) ? $data['name_fa'] : '');
		$name_en = self::sanitize_brand_name(isset($data['name_en']) ? $data['name_en'] : '');
		$has_logo = $enabled && !empty($data['has_logo']);
		$etag = isset($data['logo_etag']) ? (string) $data['logo_etag'] : '';
		$source = (string) get_option('hesabix_v2_api_base_url', '');

		if (!$enabled) {
			self::store_default_brand($source);
			return;
		}

		$cfg = self::config();
		$logo_rel = '';
		$stored_has_logo = false;

		if ($has_logo) {
			$need_download = empty($cfg['has_logo'])
				|| (string) $cfg['logo_etag'] !== $etag
				|| self::logo_absolute_path($cfg) === ''
				|| !is_readable(self::logo_absolute_path($cfg));
			if ($need_download) {
				$saved = self::download_logo($api);
				if (is_string($saved) && $saved !== '') {
					$logo_rel = $saved;
					$stored_has_logo = true;
				}
			} else {
				$logo_rel = (string) $cfg['logo_rel'];
				$stored_has_logo = true;
			}
		} else {
			self::delete_logo_files();
		}

		$stored = array(
			'enabled' => true,
			'name_fa' => $name_fa,
			'name_en' => $name_en,
			'has_logo' => $stored_has_logo,
			'logo_etag' => $stored_has_logo ? $etag : '',
			'logo_rel' => $stored_has_logo ? $logo_rel : '',
			'fetched_at' => time(),
			'source_api' => $source,
		);
		update_option(self::OPTION_KEY, $stored);
		self::flush_cache();
	}

	/**
	 * @param string $source_api
	 * @return void
	 */
	private static function store_default_brand($source_api)
	{
		self::delete_logo_files();
		update_option(
			self::OPTION_KEY,
			array(
				'enabled' => false,
				'name_fa' => '',
				'name_en' => '',
				'has_logo' => false,
				'logo_etag' => '',
				'logo_rel' => '',
				'fetched_at' => time(),
				'source_api' => (string) $source_api,
			)
		);
		self::flush_cache();
	}

	/**
	 * @param Hesabix_V2_Api $api
	 * @return string|false relative path inside uploads
	 */
	private static function download_logo($api)
	{
		$bin = $api->get_system_branding_logo('');
		if (!is_array($bin) || empty($bin['success'])) {
			return false;
		}
		if (!empty($bin['not_modified'])) {
			return false;
		}
		$body = isset($bin['body']) ? (string) $bin['body'] : '';
		if ($body === '' || !self::is_safe_raster_image($body)) {
			return false;
		}
		if (strlen($body) > (2 * 1024 * 1024)) {
			return false;
		}

		$dir = self::upload_dir_path();
		if ($dir === '') {
			return false;
		}
		if (!wp_mkdir_p($dir)) {
			return false;
		}
		self::write_dir_guards($dir);

		$ext = self::extension_from_bytes($body);
		$filename = 'menu-icon.' . $ext;
		$abs = $dir . '/' . $filename;
		$written = file_put_contents($abs, $body);
		if ($written === false) {
			return false;
		}

		foreach (array('menu-icon.png', 'menu-icon.jpg', 'menu-icon.jpeg', 'menu-icon.gif', 'menu-icon.webp', 'menu-icon.ico') as $old) {
			$old_abs = $dir . '/' . $old;
			if ($old !== $filename && is_file($old_abs)) {
				wp_delete_file($old_abs);
			}
		}

		return self::UPLOAD_SUBDIR . '/' . $filename;
	}

	/**
	 * @param mixed $value
	 * @return string
	 */
	private static function sanitize_brand_name($value)
	{
		$name = sanitize_text_field((string) $value);
		if (function_exists('mb_substr')) {
			return mb_substr($name, 0, 80);
		}
		return substr($name, 0, 80);
	}

	/**
	 * @param string $bytes
	 * @return bool
	 */
	private static function is_safe_raster_image($bytes)
	{
		if (strlen($bytes) < 12) {
			return false;
		}
		$head = substr($bytes, 0, 12);
		if (strncmp($head, "\x89PNG\r\n\x1a\n", 8) === 0) {
			return true;
		}
		if (strncmp($head, "\xff\xd8\xff", 3) === 0) {
			return true;
		}
		if (strncmp($head, "GIF87a", 6) === 0 || strncmp($head, "GIF89a", 6) === 0) {
			return true;
		}
		if (strncmp($head, "RIFF", 4) === 0 && substr($bytes, 8, 4) === 'WEBP') {
			return true;
		}
		if (strncmp($head, "\x00\x00\x01\x00", 4) === 0 || strncmp($head, "\x00\x00\x02\x00", 4) === 0) {
			return true;
		}
		return false;
	}

	/**
	 * @param string $bytes
	 * @return string
	 */
	private static function extension_from_bytes($bytes)
	{
		$head = substr($bytes, 0, 12);
		if (strncmp($head, "\x89PNG\r\n\x1a\n", 8) === 0) {
			return 'png';
		}
		if (strncmp($head, "\xff\xd8\xff", 3) === 0) {
			return 'jpg';
		}
		if (strncmp($head, "GIF87a", 6) === 0 || strncmp($head, "GIF89a", 6) === 0) {
			return 'gif';
		}
		if (strncmp($head, "RIFF", 4) === 0 && substr($bytes, 8, 4) === 'WEBP') {
			return 'webp';
		}
		if (strncmp($head, "\x00\x00\x01\x00", 4) === 0 || strncmp($head, "\x00\x00\x02\x00", 4) === 0) {
			return 'ico';
		}
		return 'png';
	}

	/**
	 * @return string
	 */
	private static function upload_dir_path()
	{
		$uploads = wp_upload_dir();
		if (!empty($uploads['error']) || empty($uploads['basedir'])) {
			return '';
		}
		return trailingslashit((string) $uploads['basedir']) . self::UPLOAD_SUBDIR;
	}

	/**
	 * @param array<string,mixed> $cfg
	 * @return string
	 */
	private static function logo_absolute_path(array $cfg)
	{
		$rel = isset($cfg['logo_rel']) ? (string) $cfg['logo_rel'] : '';
		if ($rel === '' || strpos($rel, '..') !== false) {
			return '';
		}
		$uploads = wp_upload_dir();
		if (!empty($uploads['error']) || empty($uploads['basedir'])) {
			return '';
		}
		$base = wp_normalize_path(trailingslashit((string) $uploads['basedir']));
		$abs = wp_normalize_path($base . ltrim($rel, '/\\'));
		if (strpos($abs, $base) !== 0) {
			return '';
		}
		return is_file($abs) ? $abs : '';
	}

	/**
	 * @param array<string,mixed> $cfg
	 * @return string
	 */
	private static function logo_public_url(array $cfg)
	{
		$rel = isset($cfg['logo_rel']) ? (string) $cfg['logo_rel'] : '';
		if ($rel === '') {
			return '';
		}
		$uploads = wp_upload_dir();
		if (!empty($uploads['error']) || empty($uploads['baseurl'])) {
			return '';
		}
		$url = trailingslashit((string) $uploads['baseurl']) . str_replace('\\', '/', ltrim($rel, '/\\'));
		$ver = isset($cfg['fetched_at']) ? (int) $cfg['fetched_at'] : 0;
		if ($ver > 0) {
			$url = add_query_arg('v', (string) $ver, $url);
		}
		return $url;
	}

	/**
	 * @param string $dir
	 * @return void
	 */
	private static function write_dir_guards($dir)
	{
		$index = $dir . '/index.php';
		if (!is_file($index)) {
			file_put_contents($index, "<?php\n// Silence is golden.\n");
		}
		$ht = $dir . '/.htaccess';
		if (!is_file($ht)) {
			file_put_contents($ht, "Options -Indexes\n<FilesMatch \"\\.php$\">\nDeny from all\n</FilesMatch>\n");
		}
	}

	/**
	 * @return void
	 */
	private static function delete_logo_files()
	{
		$dir = self::upload_dir_path();
		if ($dir === '' || !is_dir($dir)) {
			return;
		}
		$files = glob($dir . '/{,.}*', GLOB_BRACE);
		if (!is_array($files)) {
			$files = glob($dir . '/*');
		}
		if (is_array($files)) {
			foreach ($files as $file) {
				$base = basename($file);
				if ($base === '.' || $base === '..') {
					continue;
				}
				if (is_file($file)) {
					wp_delete_file($file);
				}
			}
		}
		if (is_file($dir . '/.htaccess')) {
			wp_delete_file($dir . '/.htaccess');
		}
		if (is_dir($dir)) {
			@rmdir($dir);
		}
	}
}
