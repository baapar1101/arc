<?php
/**
 * وضعیت لایسنس افزونهٔ ووکامرس حسابیکس در بازار افزونه‌ها.
 *
 * لایسنس marketplace با توکن پل WordPress یکی نیست؛ هر دو جداگانه بررسی می‌شوند.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 * @since      4.9.0
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Marketplace_License
{
	const PLUGIN_CODE = 'woocommerce_hesabix';

	/** @var string option کش وضعیت */
	const OPT_STATUS = 'hesabix_v2_marketplace_woo_status';

	/** @var string transient TTL برای جلوگیری از درخواست مکرر */
	const TRANSIENT_KEY = 'hesabix_v2_mp_woo_license_ok';

	/** @var int ثانیه — ۲۴ ساعت */
	const CACHE_TTL = 86400;

	/** @var string user meta برای پنهان‌سازی موقت بنر */
	const USER_META_DISMISS = 'hesabix_v2_dismiss_mp_banner_until';

	/**
	 * وضعیت لایسنس (با کش).
	 *
	 * @param bool $force_refresh
	 * @return array{
	 *   checked:bool,
	 *   active:bool,
	 *   expired:bool,
	 *   is_trial:bool,
	 *   trial_remaining_days:?int,
	 *   plugin_name:?string,
	 *   ends_at:?string,
	 *   checked_at:?int,
	 *   error:?string,
	 *   bridge_ready:bool
	 * }
	 */
	public static function get_status($force_refresh = false)
	{
		$bridge_ready = self::is_bridge_ready();

		if (!$force_refresh) {
			$cached = get_option(self::OPT_STATUS, null);
			if (is_array($cached) && !empty($cached['checked_at'])) {
				$age = time() - (int) $cached['checked_at'];
				if ($age >= 0 && $age < self::CACHE_TTL) {
					$cached['bridge_ready'] = $bridge_ready;
					return self::normalize_status($cached);
				}
			}
		}

		return self::refresh_status();
	}

	/**
	 * @return bool
	 */
	public static function is_woo_plugin_active()
	{
		$st = self::get_status(false);
		return !empty($st['active']);
	}

	/**
	 * دریافت تازه از API و ذخیره.
	 *
	 * @return array
	 */
	public static function refresh_status()
	{
		$bridge_ready = self::is_bridge_ready();
		$base = array(
			'checked' => true,
			'active' => false,
			'expired' => false,
			'is_trial' => false,
			'trial_remaining_days' => null,
			'plugin_name' => null,
			'ends_at' => null,
			'checked_at' => time(),
			'error' => null,
			'bridge_ready' => $bridge_ready,
		);

		if (!get_option('hesabix_v2_api_key') || !get_option('hesabix_v2_business_id')) {
			$base['error'] = __('اتصال API پیکربندی نشده است.', 'hesabix-v2');
			update_option(self::OPT_STATUS, $base, false);
			return $base;
		}

		try {
			$api = new Hesabix_V2_Api();
			$res = $api->get_business_marketplace_plugins();
			if (empty($res['success'])) {
				$base['error'] = isset($res['message'])
					? (string) $res['message']
					: __('بررسی لایسنس بازار افزونه ناموفق بود.', 'hesabix-v2');
				update_option(self::OPT_STATUS, $base, false);
				return $base;
			}

			$list = isset($res['data']) ? $res['data'] : array();
			if (isset($list['items']) && is_array($list['items'])) {
				$list = $list['items'];
			}
			if (!is_array($list)) {
				$list = array();
			}

			$match = null;
			foreach ($list as $row) {
				if (!is_array($row)) {
					continue;
				}
				$code = isset($row['plugin_code']) ? (string) $row['plugin_code'] : '';
				if ($code === self::PLUGIN_CODE) {
					$match = $row;
					break;
				}
			}

			if ($match) {
				$base['active'] = !empty($match['is_active']);
				$base['expired'] = !empty($match['is_expired']);
				$base['is_trial'] = !empty($match['is_trial']);
				$base['trial_remaining_days'] = isset($match['trial_remaining_days'])
					? (int) $match['trial_remaining_days']
					: null;
				$base['plugin_name'] = isset($match['plugin_name']) ? (string) $match['plugin_name'] : null;
				if (!empty($match['ends_at'])) {
					$base['ends_at'] = is_string($match['ends_at'])
						? $match['ends_at']
						: (string) $match['ends_at'];
				}
			}
		} catch (Exception $e) {
			$base['error'] = $e->getMessage();
		}

		update_option(self::OPT_STATUS, $base, false);
		set_transient(self::TRANSIENT_KEY, $base['active'] ? '1' : '0', self::CACHE_TTL);

		return $base;
	}

	/**
	 * لینک بازار افزونه در پنل حسابیکس.
	 *
	 * @return string
	 */
	public static function marketplace_url()
	{
		$bid = (int) get_option('hesabix_v2_business_id', 0);
		$path = $bid > 0
			? sprintf('https://app.hesabix.ir/business/%d/plugin-marketplace', $bid)
			: 'https://app.hesabix.ir/';

		/**
		 * فیلتر URL بازار افزونه.
		 *
		 * @param string $path
		 * @param int    $bid
		 */
		return (string) apply_filters('hesabix_v2_marketplace_plugin_url', $path, $bid);
	}

	/**
	 * آیا کاربر فعلی بنر را موقتاً پنهان کرده؟
	 *
	 * @return bool
	 */
	public static function is_banner_dismissed()
	{
		$uid = get_current_user_id();
		if ($uid < 1) {
			return false;
		}
		$until = (int) get_user_meta($uid, self::USER_META_DISMISS, true);
		return $until > time();
	}

	/**
	 * پنهان‌سازی بنر برای ۱۴ روز.
	 *
	 * @return void
	 */
	public static function dismiss_banner_for_user()
	{
		$uid = get_current_user_id();
		if ($uid < 1) {
			return;
		}
		update_user_meta($uid, self::USER_META_DISMISS, time() + (14 * DAY_IN_SECONDS));
	}

	/**
	 * رندر بنرهای ادمین (upsell لایسنس + یادآوری پل).
	 *
	 * @param string $context dashboard|settings|orders
	 * @return void
	 */
	public static function render_admin_notices($context = 'dashboard')
	{
		if (!current_user_can('manage_woocommerce')) {
			return;
		}
		if (!get_option('hesabix_v2_api_key')) {
			return;
		}

		$status = self::get_status(false);

		// لایسنس فعال: فقط در صورت نیاز به پل هشدار بده
		if (!empty($status['active'])) {
			if (empty($status['bridge_ready']) && in_array($context, array('dashboard', 'settings'), true)) {
				self::render_bridge_notice();
			}
			return;
		}

		if (self::is_banner_dismissed()) {
			return;
		}

		$url = self::marketplace_url();
		$trial_hint = '';
		if (!empty($status['is_trial']) && !empty($status['expired'])) {
			$trial_hint = __('دوره آزمایشی شما به پایان رسیده است.', 'hesabix-v2');
		} elseif (!empty($status['expired'])) {
			$trial_hint = __('لایسنس افزونه ووکامرس منقضی شده است.', 'hesabix-v2');
		}

		?>
		<div class="hesabix-v2-mp-banner" role="region" aria-label="<?php esc_attr_e('بازار افزونه حسابیکس', 'hesabix-v2'); ?>">
			<div class="hesabix-v2-mp-banner__glow" aria-hidden="true"></div>
			<div class="hesabix-v2-mp-banner__content">
				<div class="hesabix-v2-mp-banner__copy">
					<p class="hesabix-v2-mp-banner__eyebrow"><?php esc_html_e('بازار افزونه‌های حسابیکس', 'hesabix-v2'); ?></p>
					<h2 class="hesabix-v2-mp-banner__title">
						<?php esc_html_e('افزونهٔ رسمی ووکامرس حسابیکس را فعال کنید', 'hesabix-v2'); ?>
					</h2>
					<p class="hesabix-v2-mp-banner__text">
						<?php
						esc_html_e(
							'با فعال‌سازی لایسنس، همگام‌سازی دوطرفه موجودی، کنترل از پنل حسابیکس و امکانات پیشرفتهٔ فروشگاه در دسترس قرار می‌گیرد. این افزونهٔ وردپرس (ArcWOC) لایسنس را جایگزین نمی‌کند.',
							'hesabix-v2'
						);
						?>
					</p>
					<?php if ($trial_hint !== '') : ?>
						<p class="hesabix-v2-mp-banner__alert"><?php echo esc_html($trial_hint); ?></p>
					<?php endif; ?>
					<?php if (!empty($status['error'])) : ?>
						<p class="hesabix-v2-mp-banner__alert hesabix-v2-mp-banner__alert--soft">
							<?php
							echo esc_html(
								sprintf(
									/* translators: %s: API error */
									__('وضعیت لایسنس بررسی نشد: %s', 'hesabix-v2'),
									(string) $status['error']
								)
							);
							?>
						</p>
					<?php endif; ?>
					<div class="hesabix-v2-mp-banner__actions">
						<a class="hesabix-v2-mp-banner__cta" href="<?php echo esc_url($url); ?>" target="_blank" rel="noopener noreferrer">
							<?php esc_html_e('فعال‌سازی در حسابیکس', 'hesabix-v2'); ?>
						</a>
						<button type="button" class="hesabix-v2-mp-banner__refresh" id="hesabix-v2-mp-refresh-license">
							<?php esc_html_e('بررسی مجدد لایسنس', 'hesabix-v2'); ?>
						</button>
						<button type="button" class="hesabix-v2-mp-banner__dismiss" id="hesabix-v2-mp-dismiss-banner">
							<?php esc_html_e('فعلاً نه', 'hesabix-v2'); ?>
						</button>
					</div>
				</div>
				<div class="hesabix-v2-mp-banner__aside" aria-hidden="true">
					<div class="hesabix-v2-mp-banner__mark">
						<span>Woo</span>
						<span>×</span>
						<span>Hx</span>
					</div>
					<ul class="hesabix-v2-mp-banner__perks">
						<li><?php esc_html_e('موجودی دوطرفه', 'hesabix-v2'); ?></li>
						<li><?php esc_html_e('کنترل از پنل', 'hesabix-v2'); ?></li>
						<li><?php esc_html_e('پشتیبانی رسمی', 'hesabix-v2'); ?></li>
					</ul>
				</div>
			</div>
		</div>
		<?php
	}

	/**
	 * @return void
	 */
	private static function render_bridge_notice()
	{
		$settings = admin_url('admin.php?page=hesabix-v2-settings');
		?>
		<div class="hesabix-v2-bridge-hint notice notice-info is-dismissible">
			<p>
				<strong><?php esc_html_e('لایسنس ووکامرس فعال است.', 'hesabix-v2'); ?></strong>
				<?php esc_html_e('برای دریافت دستورات از پنل حسابیکس (مثل پوش موجودی)، پل اتصال وردپرس را در تنظیمات فعال و توکن بسازید.', 'hesabix-v2'); ?>
				<a href="<?php echo esc_url($settings); ?>"><?php esc_html_e('رفتن به تنظیمات پل', 'hesabix-v2'); ?></a>
			</p>
		</div>
		<?php
	}

	/**
	 * @return bool
	 */
	public static function is_bridge_ready()
	{
		if (!class_exists('Hesabix_V2_Bridge_Rest', false)) {
			return false;
		}
		$enabled = (bool) get_option(Hesabix_V2_Bridge_Rest::OPT_ENABLED);
		$token = (string) get_option(Hesabix_V2_Bridge_Rest::OPT_TOKEN_HASH, '');
		return $enabled && $token !== '';
	}

	/**
	 * @param array $raw
	 * @return array
	 */
	private static function normalize_status($raw)
	{
		return array(
			'checked' => !empty($raw['checked']),
			'active' => !empty($raw['active']),
			'expired' => !empty($raw['expired']),
			'is_trial' => !empty($raw['is_trial']),
			'trial_remaining_days' => isset($raw['trial_remaining_days']) ? (int) $raw['trial_remaining_days'] : null,
			'plugin_name' => isset($raw['plugin_name']) ? (string) $raw['plugin_name'] : null,
			'ends_at' => isset($raw['ends_at']) ? (string) $raw['ends_at'] : null,
			'checked_at' => isset($raw['checked_at']) ? (int) $raw['checked_at'] : null,
			'error' => isset($raw['error']) ? (string) $raw['error'] : null,
			'bridge_ready' => !empty($raw['bridge_ready']),
		);
	}
}
