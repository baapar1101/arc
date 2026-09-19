<?php
/**
 * سود فاکتور حسابیکس روی سفارش ووکامرس.
 *
 * پس از همگام‌سازی موفق، جزئیات فاکتور از API خوانده و در متای سفارش ذخیره می‌شود.
 *
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 * @since      4.9.0
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Invoice_Profit_Service
{
	/** @var string سود نهایی (معادل total_profit در لیست فاکتور حسابیکس) */
	const META_PROFIT = '_hesabix_v2_invoice_profit';

	/** @var string درصد سود نهایی */
	const META_PROFIT_PERCENT = '_hesabix_v2_invoice_profit_percent';

	/** @var string سود ناخالص */
	const META_GROSS = '_hesabix_v2_invoice_gross_profit';

	/** @var string سود خالص */
	const META_NET = '_hesabix_v2_invoice_net_profit';

	/** @var string زمان به‌روزرسانی (unix) */
	const META_AT = '_hesabix_v2_invoice_profit_at';

	/** @var string شناسه فاکتوری که سود برایش کش شده */
	const META_INVOICE_ID = '_hesabix_v2_invoice_profit_invoice_id';

	/** @var string بهای تمام‌شده محاسبه‌شده (برای تشخیص سود ۱۰۰٪ بدون قیمت خرید) */
	const META_TOTAL_COST = '_hesabix_v2_invoice_total_cost';

	/** @var string جمع فروش مبنای سود */
	const META_TOTAL_SALES = '_hesabix_v2_invoice_total_sales';

	/** @var string کد ارز فاکتور حسابیکس (مثلاً IRR) */
	const META_CURRENCY_CODE = '_hesabix_v2_invoice_profit_currency';

	/** @var string عنوان ارز فاکتور */
	const META_CURRENCY_TITLE = '_hesabix_v2_invoice_profit_currency_title';

	/**
	 * خواندن سود ذخیره‌شده برای سفارش.
	 *
	 * @param int|WC_Order $order_or_id
	 * @return array{
	 *   has_value:bool,
	 *   profit:?float,
	 *   profit_percent:?float,
	 *   gross_profit:?float,
	 *   net_profit:?float,
	 *   refreshed_at:?int,
	 *   invoice_id:?int
	 * }
	 */
	public static function get_for_order($order_or_id)
	{
		$order = self::resolve_order($order_or_id);
		$empty = array(
			'has_value' => false,
			'profit' => null,
			'profit_percent' => null,
			'gross_profit' => null,
			'net_profit' => null,
			'total_cost' => null,
			'total_sales' => null,
			'currency_code' => null,
			'currency_title' => null,
			'refreshed_at' => null,
			'invoice_id' => null,
			'cost_missing' => false,
		);
		if (!$order) {
			return $empty;
		}

		$raw = $order->get_meta(self::META_PROFIT, true);
		if ($raw === '' || $raw === null) {
			return $empty;
		}

		$at = $order->get_meta(self::META_AT, true);
		$hid = $order->get_meta(self::META_INVOICE_ID, true);
		$total_cost = self::meta_float_or_null($order, self::META_TOTAL_COST);
		$total_sales = self::meta_float_or_null($order, self::META_TOTAL_SALES);
		$ccode = $order->get_meta(self::META_CURRENCY_CODE, true);
		$ctitle = $order->get_meta(self::META_CURRENCY_TITLE, true);

		return array(
			'has_value' => true,
			'profit' => (float) $raw,
			'profit_percent' => self::meta_float_or_null($order, self::META_PROFIT_PERCENT),
			'gross_profit' => self::meta_float_or_null($order, self::META_GROSS),
			'net_profit' => self::meta_float_or_null($order, self::META_NET),
			'total_cost' => $total_cost,
			'total_sales' => $total_sales,
			'currency_code' => ($ccode !== '' && $ccode !== null) ? strtoupper((string) $ccode) : null,
			'currency_title' => ($ctitle !== '' && $ctitle !== null) ? (string) $ctitle : null,
			'refreshed_at' => ($at !== '' && $at !== null) ? (int) $at : null,
			'invoice_id' => ($hid !== '' && $hid !== null) ? (int) $hid : null,
			'cost_missing' => (
				($total_cost !== null && (float) $total_cost <= 0.0 && (float) $raw > 0.0)
				|| (
					$total_cost === null
					&& self::meta_float_or_null($order, self::META_PROFIT_PERCENT) !== null
					&& (float) self::meta_float_or_null($order, self::META_PROFIT_PERCENT) >= 99.5
					&& (float) $raw > 0.0
				)
			),
		);
	}

	/**
	 * پاک‌سازی متای سود (مثلاً پس از لغو ارسال).
	 *
	 * @param int|WC_Order $order_or_id
	 * @return void
	 */
	public static function clear_for_order($order_or_id)
	{
		$order = self::resolve_order($order_or_id);
		if (!$order) {
			return;
		}
		foreach (array(
			self::META_PROFIT,
			self::META_PROFIT_PERCENT,
			self::META_GROSS,
			self::META_NET,
			self::META_AT,
			self::META_INVOICE_ID,
			self::META_TOTAL_COST,
			self::META_TOTAL_SALES,
			self::META_CURRENCY_CODE,
			self::META_CURRENCY_TITLE,
		) as $key) {
			$order->delete_meta_data($key);
		}
		if (doing_action('woocommerce_update_order')) {
			$order->save_meta_data();
		} else {
			$order->save();
		}
	}

	/**
	 * دریافت سود از API و ذخیره روی سفارش.
	 *
	 * @param int               $order_id
	 * @param int|null          $invoice_id اگر null باشد از نگاشت خوانده می‌شود
	 * @param Hesabix_V2_Api|null $api
	 * @return array{success:bool,message:string,data?:array}
	 */
	public static function refresh_for_order($order_id, $invoice_id = null, $api = null)
	{
		$order_id = (int) $order_id;
		$order = wc_get_order($order_id);
		if (!$order) {
			return array(
				'success' => false,
				'message' => __('سفارش یافت نشد.', 'hesabix-v2'),
			);
		}

		$hid = $invoice_id !== null ? absint($invoice_id) : 0;
		if ($hid < 1) {
			$db = new Hesabix_V2_DB_Service();
			$map = $db->get_mapping('order', $order_id);
			if ($map && !empty($map['hesabix_id'])) {
				$hid = absint((string) $map['hesabix_id']);
			}
		}
		if ($hid < 1) {
			self::clear_for_order($order);
			return array(
				'success' => false,
				'message' => __('این سفارش هنوز به فاکتور حسابیکس متصل نیست.', 'hesabix-v2'),
			);
		}

		if (!$api) {
			$api = new Hesabix_V2_Api();
		}

		$res = $api->get_invoice($hid);
		if (empty($res['success']) || !is_array($res['data'] ?? null)) {
			$msg = isset($res['message']) ? (string) $res['message'] : __('دریافت جزئیات فاکتور ناموفق بود.', 'hesabix-v2');
			return array(
				'success' => false,
				'message' => $msg,
			);
		}

		$parsed = self::extract_profit_fields($res['data']);
		self::persist($order, $hid, $parsed);

		return array(
			'success' => true,
			'message' => __('سود فاکتور به‌روز شد.', 'hesabix-v2'),
			'data' => self::get_for_order($order),
		);
	}

	/**
	 * پس از همگام‌سازی موفق فاکتور — خطا را می‌بلعد تا sync خراب نشود.
	 *
	 * @param int               $order_id
	 * @param int               $invoice_id
	 * @param Hesabix_V2_Api|null $api
	 * @return void
	 */
	public static function maybe_refresh_after_sync($order_id, $invoice_id, $api = null)
	{
		try {
			$result = self::refresh_for_order((int) $order_id, (int) $invoice_id, $api);
			if (empty($result['success']) && class_exists('Hesabix_V2_Log_Service')) {
				Hesabix_V2_Log_Service::debug('Invoice profit refresh skipped/failed', array(
					'entity_type' => 'order',
					'entity_id' => (int) $order_id,
					'hesabix_id' => (int) $invoice_id,
					'message' => isset($result['message']) ? (string) $result['message'] : '',
				));
			}
		} catch (Exception $e) {
			if (class_exists('Hesabix_V2_Log_Service')) {
				Hesabix_V2_Log_Service::debug('Invoice profit refresh exception', array(
					'entity_type' => 'order',
					'entity_id' => (int) $order_id,
					'error' => $e->getMessage(),
				));
			}
		}
	}

	/**
	 * استخراج فیلدهای سود از پاسخ GET فاکتور.
	 *
	 * پاسخ API معمولاً به شکل { success, data: { item: {...} } } است.
	 *
	 * @param array<string,mixed> $invoice
	 * @return array{profit:float,profit_percent:?float,gross_profit:?float,net_profit:?float}
	 */
	public static function extract_profit_fields(array $invoice)
	{
		// unwrap: data.item یا خود سند
		if (isset($invoice['item']) && is_array($invoice['item'])) {
			$invoice = $invoice['item'];
		} elseif (isset($invoice['data']) && is_array($invoice['data'])) {
			$inner = $invoice['data'];
			if (isset($inner['item']) && is_array($inner['item'])) {
				$invoice = $inner['item'];
			} elseif (isset($inner['total_profit']) || isset($inner['gross_profit']) || isset($inner['id'])) {
				$invoice = $inner;
			}
		}

		$profit = null;
		if (isset($invoice['total_profit']) && is_numeric($invoice['total_profit'])) {
			$profit = (float) $invoice['total_profit'];
		} elseif (isset($invoice['net_profit']) && is_numeric($invoice['net_profit'])) {
			$profit = (float) $invoice['net_profit'];
		} elseif (isset($invoice['gross_profit']) && is_numeric($invoice['gross_profit'])) {
			$profit = (float) $invoice['gross_profit'];
		} else {
			$profit = 0.0;
		}

		$percent = null;
		if (isset($invoice['total_profit_percent']) && is_numeric($invoice['total_profit_percent'])) {
			$percent = (float) $invoice['total_profit_percent'];
		} elseif (isset($invoice['net_profit_percent']) && is_numeric($invoice['net_profit_percent'])) {
			$percent = (float) $invoice['net_profit_percent'];
		} elseif (isset($invoice['gross_profit_percent']) && is_numeric($invoice['gross_profit_percent'])) {
			$percent = (float) $invoice['gross_profit_percent'];
		}

		$gross = null;
		if (isset($invoice['gross_profit']) && is_numeric($invoice['gross_profit'])) {
			$gross = (float) $invoice['gross_profit'];
		}
		$net = null;
		if (isset($invoice['net_profit']) && is_numeric($invoice['net_profit'])) {
			$net = (float) $invoice['net_profit'];
		}

		// اگر فقط سود دفتر شناسایی‌شده موجود باشد
		if ($profit == 0.0 && $gross === null && isset($invoice['recognized_profit_ledger']) && is_array($invoice['recognized_profit_ledger'])) {
			$rp = $invoice['recognized_profit_ledger'];
			if (isset($rp['gross_profit_recognized']) && is_numeric($rp['gross_profit_recognized'])) {
				$profit = (float) $rp['gross_profit_recognized'];
				$gross = $profit;
			}
			if (isset($rp['gross_profit_percent_recognized']) && is_numeric($rp['gross_profit_percent_recognized'])) {
				$percent = (float) $rp['gross_profit_percent_recognized'];
			}
		}

		return array(
			'profit' => $profit,
			'profit_percent' => $percent,
			'gross_profit' => $gross,
			'net_profit' => $net,
			'total_cost' => isset($invoice['total_cost']) && is_numeric($invoice['total_cost'])
				? (float) $invoice['total_cost']
				: null,
			'total_sales' => isset($invoice['total_sales']) && is_numeric($invoice['total_sales'])
				? (float) $invoice['total_sales']
				: null,
			'currency_code' => isset($invoice['currency_code']) && is_string($invoice['currency_code'])
				? strtoupper(trim($invoice['currency_code']))
				: null,
			'currency_title' => isset($invoice['currency_title']) && is_string($invoice['currency_title'])
				? trim($invoice['currency_title'])
				: (isset($invoice['currency_name']) && is_string($invoice['currency_name'])
					? trim($invoice['currency_name'])
					: null),
		);
	}

	/**
	 * HTML فشرده برای ستون فهرست سفارش‌ها.
	 *
	 * @param int|WC_Order $order_or_id
	 * @return string
	 */
	public static function render_list_cell($order_or_id)
	{
		$order = self::resolve_order($order_or_id);
		if (!$order) {
			return '<span class="hesabix-v2-muted">—</span>';
		}

		$data = self::get_for_order($order);
		$oid = (int) $order->get_id();

		if (!$data['has_value']) {
			$row = class_exists('Hesabix_V2_Invoice_Service')
				? Hesabix_V2_Invoice_Service::get_sync_status($oid)
				: null;
			$synced = $row && !empty($row['hesabix_id']);
			$hint = $synced
				? __('هنوز دریافت نشده', 'hesabix-v2')
				: __('—', 'hesabix-v2');
			$html = '<span class="hesabix-v2-profit-empty">' . esc_html($hint) . '</span>';
			if ($synced) {
				$html .= sprintf(
					'<br /><button type="button" class="button-link hesabix-v2-refresh-profit" data-order-id="%d">%s</button>',
					$oid,
					esc_html__('دریافت سود', 'hesabix-v2')
				);
			}
			return $html;
		}

		$amount = self::format_money((float) $data['profit'], $order, $data);
		$tone = ((float) $data['profit'] >= 0) ? 'positive' : 'negative';
		$html = '<span class="hesabix-v2-profit-amount hesabix-v2-profit-' . esc_attr($tone) . '">'
			. esc_html($amount)
			. '</span>';

		if ($data['profit_percent'] !== null) {
			$html .= '<br /><span class="hesabix-v2-profit-pct">'
				. esc_html(self::format_percent((float) $data['profit_percent']))
				. '</span>';
		}

		$cc = isset($data['currency_code']) ? (string) $data['currency_code'] : '';
		$wc = method_exists($order, 'get_currency') ? strtoupper((string) $order->get_currency()) : '';
		if ($cc !== '' && $wc !== '' && $cc !== $wc) {
			$html .= '<br /><span class="hesabix-v2-profit-curr-hint">'
				. esc_html(
					sprintf(
						/* translators: %s: Hesabix currency code */
						__('واحد حسابیکس: %s', 'hesabix-v2'),
						$cc
					)
				)
				. '</span>';
		}

		$html .= sprintf(
			'<br /><button type="button" class="button-link hesabix-v2-refresh-profit" data-order-id="%d" title="%s">%s</button>',
			$oid,
			esc_attr__('به‌روزرسانی سود از حسابیکس', 'hesabix-v2'),
			esc_html__('تازه‌سازی', 'hesabix-v2')
		);

		return $html;
	}

	/**
	 * بلوک جزئیات برای متاباکس سفارش.
	 *
	 * @param WC_Order $order
	 * @return string
	 */
	public static function render_meta_box_block(WC_Order $order)
	{
		$data = self::get_for_order($order);
		$oid = (int) $order->get_id();
		ob_start();
		?>
		<div class="hesabix-v2-profit-panel" data-order-id="<?php echo esc_attr((string) $oid); ?>">
			<div class="hesabix-v2-profit-panel__head">
				<strong><?php esc_html_e('سود فاکتور', 'hesabix-v2'); ?></strong>
				<button type="button" class="button button-small hesabix-v2-refresh-profit" data-order-id="<?php echo esc_attr((string) $oid); ?>">
					<?php esc_html_e('به‌روزرسانی', 'hesabix-v2'); ?>
				</button>
			</div>
			<div class="hesabix-v2-profit-panel__body">
				<?php if (!$data['has_value']) : ?>
					<p class="hesabix-v2-profit-empty description">
						<?php esc_html_e('پس از همگام‌سازی سفارش، سود از حسابیکس خوانده می‌شود. می‌توانید همین‌جا دستی به‌روز کنید.', 'hesabix-v2'); ?>
					</p>
				<?php else : ?>
					<?php
					$tone = ((float) $data['profit'] >= 0) ? 'positive' : 'negative';
					?>
					<p class="hesabix-v2-profit-hero hesabix-v2-profit-<?php echo esc_attr($tone); ?>">
						<span class="hesabix-v2-profit-hero__label"><?php esc_html_e('سود نهایی', 'hesabix-v2'); ?></span>
						<span class="hesabix-v2-profit-hero__value"><?php echo esc_html(self::format_money((float) $data['profit'], $order, $data)); ?></span>
						<?php if ($data['profit_percent'] !== null) : ?>
							<span class="hesabix-v2-profit-hero__pct"><?php echo esc_html(self::format_percent((float) $data['profit_percent'])); ?></span>
						<?php endif; ?>
					</p>
					<?php
					$cc = isset($data['currency_code']) ? (string) $data['currency_code'] : '';
					$wc = strtoupper((string) $order->get_currency());
					if ($cc !== '' && $wc !== '' && $cc !== $wc) :
						?>
						<p class="description hesabix-v2-profit-curr-hint" style="margin:4px 0 8px;">
							<?php
							echo esc_html(
								sprintf(
									/* translators: 1: Hesabix currency, 2: WooCommerce currency */
									__('مبالغ سود به واحد حسابیکس (%1$s) است؛ مبلغ سفارش ووکامرس (%2$s) است.', 'hesabix-v2'),
									$cc,
									$wc
								)
							);
							?>
						</p>
					<?php endif; ?>
					<ul class="hesabix-v2-profit-details">
						<?php if ($data['gross_profit'] !== null) : ?>
							<li>
								<span><?php esc_html_e('ناخالص', 'hesabix-v2'); ?></span>
								<strong><?php echo esc_html(self::format_money((float) $data['gross_profit'], $order, $data)); ?></strong>
							</li>
						<?php endif; ?>
						<?php if ($data['net_profit'] !== null) : ?>
							<li>
								<span><?php esc_html_e('خالص', 'hesabix-v2'); ?></span>
								<strong><?php echo esc_html(self::format_money((float) $data['net_profit'], $order, $data)); ?></strong>
							</li>
						<?php endif; ?>
						<?php if ($data['total_cost'] !== null) : ?>
							<li>
								<span><?php esc_html_e('بهای تمام‌شده', 'hesabix-v2'); ?></span>
								<strong><?php echo esc_html(self::format_money((float) $data['total_cost'], $order, $data)); ?></strong>
							</li>
						<?php endif; ?>
						<?php if (!empty($data['cost_missing'])) : ?>
							<li class="hesabix-v2-profit-details__warn">
								<span colspan="2"><?php esc_html_e('بهای تمام‌شده صفر است (قیمت خرید / لایه FIFO یافت نشد)؛ سود نمایشی برابر فروش است و واقعی نیست.', 'hesabix-v2'); ?></span>
							</li>
						<?php endif; ?>
						<?php if (!empty($data['refreshed_at'])) : ?>
							<li class="hesabix-v2-profit-details__meta">
								<span><?php esc_html_e('آخرین به‌روزرسانی', 'hesabix-v2'); ?></span>
								<strong><?php echo esc_html(self::format_datetime((int) $data['refreshed_at'])); ?></strong>
							</li>
						<?php endif; ?>
					</ul>
				<?php endif; ?>
			</div>
		</div>
		<?php
		return (string) ob_get_clean();
	}

	/**
	 * @param array{profit:float,profit_percent:?float,gross_profit:?float,net_profit:?float} $parsed
	 * @return void
	 */
	private static function persist(WC_Order $order, $invoice_id, array $parsed)
	{
		$order->update_meta_data(self::META_PROFIT, (string) $parsed['profit']);
		if ($parsed['profit_percent'] !== null) {
			$order->update_meta_data(self::META_PROFIT_PERCENT, (string) $parsed['profit_percent']);
		} else {
			$order->delete_meta_data(self::META_PROFIT_PERCENT);
		}
		if ($parsed['gross_profit'] !== null) {
			$order->update_meta_data(self::META_GROSS, (string) $parsed['gross_profit']);
		} else {
			$order->delete_meta_data(self::META_GROSS);
		}
		if ($parsed['net_profit'] !== null) {
			$order->update_meta_data(self::META_NET, (string) $parsed['net_profit']);
		} else {
			$order->delete_meta_data(self::META_NET);
		}
		$order->update_meta_data(self::META_AT, (string) time());
		$order->update_meta_data(self::META_INVOICE_ID, (string) absint($invoice_id));
		if (isset($parsed['total_cost']) && $parsed['total_cost'] !== null) {
			$order->update_meta_data(self::META_TOTAL_COST, (string) $parsed['total_cost']);
		} else {
			$order->delete_meta_data(self::META_TOTAL_COST);
		}
		if (isset($parsed['total_sales']) && $parsed['total_sales'] !== null) {
			$order->update_meta_data(self::META_TOTAL_SALES, (string) $parsed['total_sales']);
		} else {
			$order->delete_meta_data(self::META_TOTAL_SALES);
		}
		if (!empty($parsed['currency_code'])) {
			$order->update_meta_data(self::META_CURRENCY_CODE, strtoupper((string) $parsed['currency_code']));
		} else {
			// fallback از تنظیمات ارز فاکتور افزونه
			if (class_exists('Hesabix_V2_Currency_Service')) {
				$row = Hesabix_V2_Currency_Service::resolve_invoice_currency_row();
				if ($row && !empty($row['code'])) {
					$order->update_meta_data(self::META_CURRENCY_CODE, strtoupper((string) $row['code']));
					if (!empty($row['title'])) {
						$order->update_meta_data(self::META_CURRENCY_TITLE, (string) $row['title']);
					}
				} else {
					$order->delete_meta_data(self::META_CURRENCY_CODE);
				}
			} else {
				$order->delete_meta_data(self::META_CURRENCY_CODE);
			}
		}
		if (!empty($parsed['currency_title'])) {
			$order->update_meta_data(self::META_CURRENCY_TITLE, (string) $parsed['currency_title']);
		} elseif (empty($parsed['currency_code'])) {
			// title ممکن است همراه fallback کد تنظیم شده باشد
		} else {
			$order->delete_meta_data(self::META_CURRENCY_TITLE);
		}

		if (doing_action('woocommerce_update_order')) {
			$order->save_meta_data();
		} else {
			$order->save();
		}
	}

	/**
	 * قالب‌بندی مبلغ سود به واحد ارز فاکتور حسابیکس (نه ارز ووکامرس).
	 *
	 * @param float         $amount
	 * @param WC_Order      $order
	 * @param array|null    $profit_data خروجی get_for_order / extract
	 * @return string
	 */
	public static function format_money($amount, WC_Order $order, $profit_data = null)
	{
		$code = null;
		$title = null;
		if (is_array($profit_data)) {
			$code = isset($profit_data['currency_code']) ? $profit_data['currency_code'] : null;
			$title = isset($profit_data['currency_title']) ? $profit_data['currency_title'] : null;
		}
		if (!$code) {
			$meta_code = $order->get_meta(self::META_CURRENCY_CODE, true);
			if ($meta_code !== '' && $meta_code !== null) {
				$code = (string) $meta_code;
			}
			$meta_title = $order->get_meta(self::META_CURRENCY_TITLE, true);
			if ($meta_title !== '' && $meta_title !== null) {
				$title = (string) $meta_title;
			}
		}

		if (class_exists('Hesabix_V2_Currency_Service')) {
			return Hesabix_V2_Currency_Service::format_hesabix_money((float) $amount, $code, $title);
		}

		// fallback نادر
		$formatted = number_format_i18n((float) $amount, 0);
		if ($code && strtoupper((string) $code) === 'IRR') {
			return sprintf(__('%s ریال', 'hesabix-v2'), $formatted);
		}
		return $formatted;
	}

	/**
	 * @param float $pct
	 * @return string
	 */
	public static function format_percent($pct)
	{
		$formatted = number_format_i18n($pct, 1);
		/* translators: %s: profit percent number */
		return sprintf(__('%s٪', 'hesabix-v2'), $formatted);
	}

	/**
	 * @param int $ts
	 * @return string
	 */
	public static function format_datetime($ts)
	{
		$ts = (int) $ts;
		if ($ts < 1) {
			return '—';
		}
		return wp_date(
			get_option('date_format') . ' ' . get_option('time_format'),
			$ts
		);
	}

	/**
	 * @param int|WC_Order $order_or_id
	 * @return WC_Order|null
	 */
	private static function resolve_order($order_or_id)
	{
		if ($order_or_id instanceof WC_Order) {
			return $order_or_id;
		}
		$oid = (int) $order_or_id;
		if ($oid < 1) {
			return null;
		}
		$order = wc_get_order($oid);
		return ($order instanceof WC_Order) ? $order : null;
	}

	/**
	 * @param WC_Order $order
	 * @param string   $key
	 * @return float|null
	 */
	private static function meta_float_or_null(WC_Order $order, $key)
	{
		$v = $order->get_meta($key, true);
		if ($v === '' || $v === null) {
			return null;
		}
		return (float) $v;
	}
}
