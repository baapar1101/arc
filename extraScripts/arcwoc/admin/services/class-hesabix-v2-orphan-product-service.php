<?php
/**
 * تشخیص و پاک‌سازی امن کالاهای یتیم «والد متغیر به‌عنوان ساده» در حسابیکس.
 *
 * @since      4.7.2
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/admin/services
 */

if (!defined('WPINC')) {
	die;
}

class Hesabix_V2_Orphan_Product_Service
{
	const OPTION_REGISTRY = 'hesabix_v2_orphan_parent_products';
	const TIER_HIGH = 'high';
	const TIER_MEDIUM = 'medium';

	/** @var Hesabix_V2_Api */
	private $api;

	/** @var Hesabix_V2_DB_Service */
	private $db;

	public function __construct()
	{
		$this->api = new Hesabix_V2_Api();
		$this->db = new Hesabix_V2_DB_Service();
	}

	/**
	 * شناسه‌های کالا که هرگز نباید حذف/غیرفعال شوند (حمل‌ونقل، کارمزد، …).
	 *
	 * @return int[]
	 */
	public static function protected_hesabix_ids()
	{
		$ids = array(
			(int) get_option('hesabix_v2_shipping_product_id', 0),
			(int) get_option('hesabix_v2_fee_product_id', 0),
		);

		/**
		 * شناسه‌های حسابیکس که از پاک‌سازی یتیم‌ها مستثنی هستند.
		 *
		 * @param int[] $ids
		 */
		$filtered = apply_filters('hesabix_v2_orphan_protected_hesabix_ids', $ids);
		if (!is_array($filtered)) {
			$filtered = $ids;
		}

		$out = array();
		foreach ($filtered as $id) {
			$id = absint($id);
			if ($id > 0) {
				$out[ $id ] = $id;
			}
		}

		return array_values($out);
	}

	/**
	 * ثبت یک کالای یتیم در رجیستری محلی (مثلاً هنگام پاک شدن نگاشت والد).
	 *
	 * @param array<string, mixed> $row
	 * @return void
	 */
	public static function register(array $row)
	{
		$hesabix_id = isset($row['hesabix_id']) ? absint($row['hesabix_id']) : 0;
		if ($hesabix_id < 1) {
			return;
		}

		if (in_array($hesabix_id, self::protected_hesabix_ids(), true)) {
			return;
		}

		$registry = self::get_registry();
		$existing = isset($registry[ $hesabix_id ]) && is_array($registry[ $hesabix_id ])
			? $registry[ $hesabix_id ]
			: array();

		$registry[ $hesabix_id ] = array_merge(
			array(
				'hesabix_id' => $hesabix_id,
				'wc_parent_id' => 0,
				'parent_name' => '',
				'source' => 'manual',
				'tier' => self::TIER_HIGH,
				'status' => 'pending',
				'last_message' => '',
				'detected_at' => current_time('mysql'),
				'document_types' => array(),
			),
			$existing,
			$row,
			array(
				'hesabix_id' => $hesabix_id,
				'updated_at' => current_time('mysql'),
			)
		);

		// اگر قبلاً حذف شده، دوباره pending نشود مگر صریحاً خواسته شود
		if (!empty($existing['status']) && $existing['status'] === 'deleted' && empty($row['force_reopen'])) {
			$registry[ $hesabix_id ]['status'] = 'deleted';
		} elseif (empty($row['status'])) {
			$registry[ $hesabix_id ]['status'] = 'pending';
		}

		self::save_registry($registry);
	}

	/**
	 * @return array<int, array<string, mixed>>
	 */
	public static function get_registry()
	{
		$raw = get_option(self::OPTION_REGISTRY, array());
		if (!is_array($raw)) {
			return array();
		}

		$out = array();
		foreach ($raw as $key => $row) {
			if (!is_array($row)) {
				continue;
			}
			$id = isset($row['hesabix_id']) ? absint($row['hesabix_id']) : absint($key);
			if ($id < 1) {
				continue;
			}
			$row['hesabix_id'] = $id;
			$out[ $id ] = $row;
		}

		return $out;
	}

	/**
	 * @param array<int, array<string, mixed>> $registry
	 * @return void
	 */
	public static function save_registry(array $registry)
	{
		update_option(self::OPTION_REGISTRY, $registry, false);
	}

	/**
	 * اسکن کاندیداهای یتیم و به‌روزرسانی رجیستری.
	 *
	 * @param array{include_name_heuristics?:bool} $args
	 * @return array{success:bool,candidates:array,counts:array,message:string}
	 */
	public function scan_candidates(array $args = array())
	{
		$include_heuristics = !empty($args['include_name_heuristics']);
		$protected = array_fill_keys(self::protected_hesabix_ids(), true);
		$mappings = $this->db->get_all_product_mappings();

		$mapped_hesabix = array();
		$parent_null_by_wc = array();
		$variation_parents = array();

		foreach ($mappings as $m) {
			if (!is_array($m)) {
				continue;
			}
			$hid = isset($m['hesabix_id']) ? absint($m['hesabix_id']) : 0;
			$wc_id = isset($m['wc_id']) ? absint($m['wc_id']) : 0;
			$wc_parent = array_key_exists('wc_parent_id', $m) && $m['wc_parent_id'] !== null && $m['wc_parent_id'] !== ''
				? absint($m['wc_parent_id'])
				: null;

			if ($hid > 0) {
				$mapped_hesabix[ $hid ] = true;
			}

			if ($wc_parent === null || $wc_parent === 0) {
				if ($wc_id > 0 && $hid > 0) {
					$parent_null_by_wc[ $wc_id ] = $hid;
				}
			} else {
				$variation_parents[ $wc_parent ] = true;
			}
		}

		$candidates = array();
		$registry = self::get_registry();

		// سطح بالا: نگاشت والد با wc_parent_id خالی روی محصول متغیر WC
		foreach ($parent_null_by_wc as $wc_parent_id => $hesabix_id) {
			if (isset($protected[ $hesabix_id ])) {
				continue;
			}

			$product = wc_get_product($wc_parent_id);
			if (!$product || !$product->is_type('variable')) {
				continue;
			}

			$row = $this->build_candidate_row(
				$hesabix_id,
				$wc_parent_id,
				$product->get_title(),
				self::TIER_HIGH,
				'mapping',
				__('نگاشت والد متغیر به‌عنوان محصول ساده', 'hesabix-v2')
			);
			$candidates[ $hesabix_id ] = $row;
			self::register(array_merge($row, array('status' => 'pending')));
		}

		// رجیستری قبلی (پس از پاک شدن نگاشت)
		foreach ($registry as $hid => $row) {
			$hid = absint($hid);
			if ($hid < 1 || isset($protected[ $hid ]) || isset($candidates[ $hid ])) {
				continue;
			}

			$status = isset($row['status']) ? (string) $row['status'] : 'pending';
			if (in_array($status, array('deleted'), true)) {
				continue;
			}

			// اگر این hesabix_id هنوز نگاشت معتبری دارد (غیر از همان والد یتیم)، رد کن
			if (isset($mapped_hesabix[ $hid ])) {
				$still_parent_orphan = false;
				$wc_pid = isset($row['wc_parent_id']) ? absint($row['wc_parent_id']) : 0;
				if ($wc_pid > 0 && isset($parent_null_by_wc[ $wc_pid ]) && (int) $parent_null_by_wc[ $wc_pid ] === $hid) {
					$still_parent_orphan = true;
				}
				if (!$still_parent_orphan) {
					continue;
				}
			}

			$wc_parent_id = isset($row['wc_parent_id']) ? absint($row['wc_parent_id']) : 0;
			$parent_name = isset($row['parent_name']) ? (string) $row['parent_name'] : '';
			if ($wc_parent_id > 0) {
				$p = wc_get_product($wc_parent_id);
				if ($p && $p->is_type('variable')) {
					$parent_name = $p->get_title();
				} elseif ($p && !$p->is_type('variable')) {
					// دیگر متغیر نیست — از لیست فعال خارج کن
					continue;
				}
			}

			$cand = $this->build_candidate_row(
				$hid,
				$wc_parent_id,
				$parent_name,
				isset($row['tier']) ? (string) $row['tier'] : self::TIER_HIGH,
				isset($row['source']) ? (string) $row['source'] : 'registry',
				__('ثبت‌شده در رجیستری یتیم‌ها (نگاشت محلی قبلاً پاک شده)', 'hesabix-v2')
			);
			$cand['status'] = $status;
			$candidates[ $hid ] = $cand;
		}

		// سطح متوسط (اختیاری): نام دقیق والد متغیر در حسابیکس بدون نگاشت محلی
		if ($include_heuristics) {
			$heuristic = $this->detect_name_heuristics($mapped_hesabix, $variation_parents, $protected, $candidates);
			foreach ($heuristic as $hid => $row) {
				$candidates[ $hid ] = $row;
				self::register(array_merge($row, array('status' => 'pending', 'force_reopen' => true)));
			}
		}

		$counts = array(
			'total' => count($candidates),
			'high' => 0,
			'medium' => 0,
			'pending' => 0,
			'deactivated' => 0,
		);
		foreach ($candidates as $c) {
			if (($c['tier'] ?? '') === self::TIER_MEDIUM) {
				$counts['medium']++;
			} else {
				$counts['high']++;
			}
			$st = isset($c['status']) ? (string) $c['status'] : 'pending';
			if ($st === 'deactivated') {
				$counts['deactivated']++;
			} elseif ($st !== 'deleted') {
				$counts['pending']++;
			}
		}

		$list = array_values($candidates);
		usort(
			$list,
			static function ($a, $b) {
				$ta = ($a['tier'] ?? '') === self::TIER_HIGH ? 0 : 1;
				$tb = ($b['tier'] ?? '') === self::TIER_HIGH ? 0 : 1;
				if ($ta !== $tb) {
					return $ta - $tb;
				}
				return ((int) ($a['hesabix_id'] ?? 0)) - ((int) ($b['hesabix_id'] ?? 0));
			}
		);

		Hesabix_V2_Log_Service::info(
			'Orphan parent products scan completed',
			array(
				'entity_type' => 'product',
				'counts' => $counts,
				'include_name_heuristics' => $include_heuristics,
			)
		);

		return array(
			'success' => true,
			'candidates' => $list,
			'counts' => $counts,
			'message' => sprintf(
				/* translators: %d candidate count */
				__('اسکن انجام شد: %d کاندیدا یافت شد.', 'hesabix-v2'),
				count($list)
			),
		);
	}

	/**
	 * پاک‌سازی دسته‌ای کاندیداها.
	 *
	 * @param int[] $hesabix_ids
	 * @param array{dry_run?:bool,deactivate_if_used?:bool,allow_medium?:bool} $args
	 * @return array{success:bool,results:array,summary:array,message:string}
	 */
	public function cleanup_batch(array $hesabix_ids, array $args = array())
	{
		$dry_run = !empty($args['dry_run']);
		$deactivate_if_used = !isset($args['deactivate_if_used']) || !empty($args['deactivate_if_used']);
		$allow_medium = !empty($args['allow_medium']);

		$results = array();
		$summary = array(
			'deleted' => 0,
			'deactivated' => 0,
			'skipped' => 0,
			'errors' => 0,
			'dry_run_deletable' => 0,
			'dry_run_in_use' => 0,
		);

		$ids = array_values(array_unique(array_filter(array_map('absint', $hesabix_ids))));
		foreach ($ids as $hid) {
			$one = $this->cleanup_one(
				$hid,
				array(
					'dry_run' => $dry_run,
					'deactivate_if_used' => $deactivate_if_used,
					'allow_medium' => $allow_medium,
				)
			);
			$results[] = $one;

			$action = isset($one['action']) ? (string) $one['action'] : '';
			if (!empty($one['success'])) {
				if ($action === 'deleted') {
					$summary['deleted']++;
				} elseif ($action === 'deactivated') {
					$summary['deactivated']++;
				} elseif ($action === 'would_delete') {
					$summary['dry_run_deletable']++;
				} elseif ($action === 'would_deactivate' || $action === 'in_use') {
					$summary['dry_run_in_use']++;
				} else {
					$summary['skipped']++;
				}
			} else {
				if ($action === 'skipped') {
					$summary['skipped']++;
				} else {
					$summary['errors']++;
				}
			}
		}

		if ($dry_run) {
			$message = sprintf(
				/* translators: 1: deletable 2: in use 3: skipped/errors */
				__('پیش‌نمایش: %1$d قابل حذف، %2$d در استفاده، %3$d رد/خطا.', 'hesabix-v2'),
				$summary['dry_run_deletable'],
				$summary['dry_run_in_use'],
				$summary['skipped'] + $summary['errors']
			);
		} else {
			$message = sprintf(
				/* translators: 1: deleted 2: deactivated 3: skipped 4: errors */
				__('پاک‌سازی: %1$d حذف، %2$d غیرفعال، %3$d رد، %4$d خطا.', 'hesabix-v2'),
				$summary['deleted'],
				$summary['deactivated'],
				$summary['skipped'],
				$summary['errors']
			);
		}

		return array(
			'success' => true,
			'results' => $results,
			'summary' => $summary,
			'message' => $message,
			'dry_run' => $dry_run,
		);
	}

	/**
	 * پاک‌سازی یک کالا.
	 *
	 * @param int   $hesabix_id
	 * @param array $args
	 * @return array<string, mixed>
	 */
	public function cleanup_one($hesabix_id, array $args = array())
	{
		$hesabix_id = absint($hesabix_id);
		$dry_run = !empty($args['dry_run']);
		$deactivate_if_used = !isset($args['deactivate_if_used']) || !empty($args['deactivate_if_used']);
		$allow_medium = !empty($args['allow_medium']);

		$base = array(
			'hesabix_id' => $hesabix_id,
			'success' => false,
			'action' => 'error',
			'message' => '',
			'document_types' => array(),
			'can_delete' => null,
			'tier' => self::TIER_HIGH,
			'wc_parent_id' => 0,
			'parent_name' => '',
		);

		if ($hesabix_id < 1) {
			$base['message'] = __('شناسهٔ کالا نامعتبر است.', 'hesabix-v2');
			return $base;
		}

		if (in_array($hesabix_id, self::protected_hesabix_ids(), true)) {
			$base['action'] = 'skipped';
			$base['success'] = true;
			$base['message'] = __('این کالا محافظت‌شده است (حمل‌ونقل/کارمزد) و پاک‌سازی نمی‌شود.', 'hesabix-v2');
			return $base;
		}

		$validation = $this->validate_candidate($hesabix_id, $allow_medium);
		if (empty($validation['ok'])) {
			$base['action'] = 'skipped';
			$base['success'] = true;
			$base['message'] = isset($validation['message']) ? (string) $validation['message'] : __('کاندیدای معتبر نیست.', 'hesabix-v2');
			$base['tier'] = isset($validation['tier']) ? (string) $validation['tier'] : self::TIER_HIGH;
			return $base;
		}

		$base['tier'] = (string) $validation['tier'];
		$base['wc_parent_id'] = (int) $validation['wc_parent_id'];
		$base['parent_name'] = (string) $validation['parent_name'];

		$usage = $this->check_usage($hesabix_id);
		$base['document_types'] = isset($usage['document_types']) && is_array($usage['document_types'])
			? $usage['document_types']
			: array();
		$base['can_delete'] = !empty($usage['can_delete']);
		$base['usage_source'] = isset($usage['source']) ? (string) $usage['source'] : '';

		if (!empty($usage['not_found'])) {
			$this->update_registry_status($hesabix_id, 'deleted', __('کالا در حسابیکس یافت نشد؛ از رجیستری حذف شد.', 'hesabix-v2'));
			$this->db->delete_parent_only_product_mapping_by_hesabix_id($hesabix_id);
			$base['success'] = true;
			$base['action'] = 'deleted';
			$base['message'] = __('کالا در حسابیکس وجود ندارد؛ نگاشت/رجیستری پاک شد.', 'hesabix-v2');
			return $base;
		}

		if (!empty($usage['error']) && $usage['can_delete'] === null) {
			$base['message'] = isset($usage['message']) ? (string) $usage['message'] : __('خطا در بررسی استفاده کالا.', 'hesabix-v2');
			$this->update_registry_status($hesabix_id, 'error', $base['message'], $base['document_types']);
			return $base;
		}

		if ($dry_run) {
			if (!empty($usage['uncertain'])) {
				$base['success'] = true;
				$base['action'] = 'uncertain';
				$base['message'] = isset($usage['message'])
					? (string) $usage['message']
					: __('وضعیت استفاده نامشخص است (API قدیمی). در پاک‌سازی واقعی گارد حذف اعمال می‌شود.', 'hesabix-v2');
				return $base;
			}
			if (!empty($usage['can_delete'])) {
				$base['success'] = true;
				$base['action'] = 'would_delete';
				$base['message'] = __('قابل حذف: در فاکتور/سند/انبار استفاده نشده است.', 'hesabix-v2');
			} else {
				$types = !empty($base['document_types']) ? implode('، ', $base['document_types']) : __('نامشخص', 'hesabix-v2');
				$base['success'] = true;
				$base['action'] = $deactivate_if_used ? 'would_deactivate' : 'in_use';
				$base['message'] = sprintf(
					/* translators: %s document types */
					__('در استفاده است (%s) — حذف نمی‌شود؛ در پاک‌سازی واقعی غیرفعال می‌شود.', 'hesabix-v2'),
					$types
				);
			}
			return $base;
		}

		if (!empty($usage['can_delete'])) {
			$del = $this->api->delete_product($hesabix_id);
			if (!empty($del['success'])) {
				$this->db->delete_parent_only_product_mapping_by_hesabix_id($hesabix_id);
				// اگر هنوز نگاشت روی wc_parent با این id باشد
				if (!empty($validation['wc_parent_id'])) {
					$m = $this->db->get_mapping('product', (int) $validation['wc_parent_id'], null);
					if ($m && (int) $m['hesabix_id'] === $hesabix_id) {
						$this->db->delete_parent_only_product_mapping((int) $validation['wc_parent_id']);
					}
				}
				$this->update_registry_status($hesabix_id, 'deleted', __('حذف شد.', 'hesabix-v2'));
				$base['success'] = true;
				$base['action'] = 'deleted';
				$base['message'] = __('کالای یتیم با موفقیت از حسابیکس حذف شد.', 'hesabix-v2');

				Hesabix_V2_Log_Service::info(
					'Orphan parent product deleted',
					array(
						'entity_type' => 'product',
						'hesabix_id' => $hesabix_id,
						'wc_parent_id' => (int) $validation['wc_parent_id'],
					)
				);

				return $base;
			}

			// حذف شکست خورد — شاید همزمان استفاده شده
			$msg = isset($del['message']) ? (string) $del['message'] : __('حذف ناموفق بود.', 'hesabix-v2');
			$looks_in_use = (false !== strpos($msg, 'اسناد مرتبط') || false !== strpos($msg, 'استفاده'));

			if ($looks_in_use && $deactivate_if_used) {
				return $this->deactivate_orphan($hesabix_id, $validation, $base, $msg);
			}

			$base['message'] = $msg;
			$this->update_registry_status($hesabix_id, 'error', $msg);
			return $base;
		}

		// در استفاده
		if ($deactivate_if_used) {
			$types = !empty($base['document_types']) ? implode('، ', $base['document_types']) : '';
			return $this->deactivate_orphan(
				$hesabix_id,
				$validation,
				$base,
				$types !== ''
					? sprintf(__('در استفاده: %s', 'hesabix-v2'), $types)
					: __('در اسناد مرتبط استفاده شده است.', 'hesabix-v2')
			);
		}

		$base['success'] = true;
		$base['action'] = 'skipped';
		$base['message'] = __('کالا در استفاده است و حذف/غیرفعال‌سازی انجام نشد.', 'hesabix-v2');
		$this->update_registry_status($hesabix_id, 'skipped', $base['message'], $base['document_types']);
		return $base;
	}

	/**
	 * بررسی استفاده کالا در حسابیکس.
	 *
	 * @param int $hesabix_id
	 * @return array{can_delete:?bool,is_used:?bool,document_types:array,source:string,error?:bool,not_found?:bool,message?:string}
	 */
	public function check_usage($hesabix_id)
	{
		$hesabix_id = absint($hesabix_id);
		$res = $this->api->check_product_usage($hesabix_id);

		if (!empty($res['success']) && is_array($res['data'])) {
			$data = $res['data'];
			$can = array_key_exists('can_delete', $data) ? (bool) $data['can_delete'] : null;
			$used = array_key_exists('is_used', $data) ? (bool) $data['is_used'] : ($can === null ? null : !$can);
			$types = isset($data['document_types']) && is_array($data['document_types']) ? $data['document_types'] : array();

			return array(
				'can_delete' => $can,
				'is_used' => $used,
				'document_types' => $types,
				'source' => 'usage_check',
			);
		}

		$status = isset($res['status_code']) ? (int) $res['status_code'] : 0;
		$msg = isset($res['message']) ? (string) $res['message'] : '';

		if ($status === 404 || false !== strpos($msg, 'یافت نشد')) {
			return array(
				'can_delete' => true,
				'is_used' => false,
				'document_types' => array(),
				'source' => 'not_found',
				'not_found' => true,
				'message' => $msg,
			);
		}

		// سرور قدیمی بدون usage-check: وجود کالا را چک کن
		$get = $this->api->get_product($hesabix_id);
		if (empty($get['success'])) {
			$gmsg = isset($get['message']) ? (string) $get['message'] : '';
			$gstatus = isset($get['status_code']) ? (int) $get['status_code'] : 0;
			if ($gstatus === 404 || false !== strpos($gmsg, 'یافت نشد')) {
				return array(
					'can_delete' => true,
					'is_used' => false,
					'document_types' => array(),
					'source' => 'not_found',
					'not_found' => true,
					'message' => $gmsg,
				);
			}

			return array(
				'can_delete' => null,
				'is_used' => null,
				'document_types' => array(),
				'source' => 'error',
				'error' => true,
				'message' => $msg !== '' ? $msg : ($gmsg !== '' ? $gmsg : __('خطا در بررسی کالا.', 'hesabix-v2')),
			);
		}

		// usage-check نیست؛ برای حذف واقعی به گارد DELETE تکیه می‌کنیم؛ برای dry-run نامشخص است
		return array(
			'can_delete' => true,
			'is_used' => false,
			'document_types' => array(),
			'source' => 'fallback_probe_delete',
			'uncertain' => true,
			'message' => __('endpoint بررسی استفاده در دسترس نیست؛ حذف توسط گارد سرور کنترل می‌شود.', 'hesabix-v2'),
		);
	}

	/**
	 * @param int    $hesabix_id
	 * @param int    $wc_parent_id
	 * @param string $parent_name
	 * @param string $tier
	 * @param string $source
	 * @param string $reason
	 * @return array<string, mixed>
	 */
	private function build_candidate_row($hesabix_id, $wc_parent_id, $parent_name, $tier, $source, $reason)
	{
		return array(
			'hesabix_id' => (int) $hesabix_id,
			'wc_parent_id' => (int) $wc_parent_id,
			'parent_name' => (string) $parent_name,
			'tier' => $tier === self::TIER_MEDIUM ? self::TIER_MEDIUM : self::TIER_HIGH,
			'source' => (string) $source,
			'reason' => (string) $reason,
			'status' => 'pending',
			'detected_at' => current_time('mysql'),
		);
	}

	/**
	 * @param array<int,bool> $mapped_hesabix
	 * @param array<int,bool> $variation_parents
	 * @param array<int,bool> $protected
	 * @param array<int,array> $already
	 * @return array<int, array<string, mixed>>
	 */
	private function detect_name_heuristics(array $mapped_hesabix, array $variation_parents, array $protected, array $already)
	{
		$found = array();

		foreach (array_keys($variation_parents) as $wc_parent_id) {
			$wc_parent_id = absint($wc_parent_id);
			if ($wc_parent_id < 1) {
				continue;
			}

			$product = wc_get_product($wc_parent_id);
			if (!$product || !$product->is_type('variable')) {
				continue;
			}

			$title = trim((string) $product->get_title());
			if ($title === '') {
				continue;
			}

			$search = $this->api->search_products(
				array(
					'search' => $title,
					'take' => 20,
					'skip' => 0,
				)
			);

			if (empty($search['success']) || empty($search['data'])) {
				continue;
			}

			$items = array();
			if (isset($search['data']['items']) && is_array($search['data']['items'])) {
				$items = $search['data']['items'];
			} elseif (isset($search['data']['results']) && is_array($search['data']['results'])) {
				$items = $search['data']['results'];
			} elseif (is_array($search['data']) && isset($search['data'][0])) {
				$items = $search['data'];
			}

			foreach ($items as $item) {
				if (!is_array($item)) {
					continue;
				}
				$hid = isset($item['id']) ? absint($item['id']) : 0;
				$name = isset($item['name']) ? trim((string) $item['name']) : '';
				if ($hid < 1 || $name === '') {
					continue;
				}
				if (isset($protected[ $hid ]) || isset($mapped_hesabix[ $hid ]) || isset($already[ $hid ]) || isset($found[ $hid ])) {
					continue;
				}
				if ($this->normalize_name($name) !== $this->normalize_name($title)) {
					continue;
				}

				$found[ $hid ] = $this->build_candidate_row(
					$hid,
					$wc_parent_id,
					$title,
					self::TIER_MEDIUM,
					'name_heuristic',
					__('نام دقیق برابر عنوان والد متغیر و بدون نگاشت محلی (نیاز به تأیید)', 'hesabix-v2')
				);
			}
		}

		return $found;
	}

	/**
	 * @param string $name
	 * @return string
	 */
	private function normalize_name($name)
	{
		$name = wp_strip_all_tags((string) $name);
		$name = preg_replace('/\s+/u', ' ', $name);
		return mb_strtolower(trim((string) $name));
	}

	/**
	 * @param int  $hesabix_id
	 * @param bool $allow_medium
	 * @return array{ok:bool,message?:string,tier?:string,wc_parent_id?:int,parent_name?:string}
	 */
	private function validate_candidate($hesabix_id, $allow_medium)
	{
		$registry = self::get_registry();
		$row = isset($registry[ $hesabix_id ]) ? $registry[ $hesabix_id ] : null;

		$mappings = $this->db->get_all_product_mappings();
		$parent_null_match = null;
		$used_elsewhere = false;

		foreach ($mappings as $m) {
			if (!is_array($m) || (int) ($m['hesabix_id'] ?? 0) !== $hesabix_id) {
				continue;
			}
			$wc_id = absint($m['wc_id'] ?? 0);
			$wc_parent = array_key_exists('wc_parent_id', $m) && $m['wc_parent_id'] !== null && $m['wc_parent_id'] !== ''
				? absint($m['wc_parent_id'])
				: null;

			if ($wc_parent === null || $wc_parent === 0) {
				$p = wc_get_product($wc_id);
				if ($p && $p->is_type('variable')) {
					$parent_null_match = array(
						'wc_parent_id' => $wc_id,
						'parent_name' => $p->get_title(),
						'tier' => self::TIER_HIGH,
					);
				} else {
					$used_elsewhere = true;
				}
			} else {
				$used_elsewhere = true;
			}
		}

		if ($used_elsewhere && !$parent_null_match) {
			return array(
				'ok' => false,
				'message' => __('این شناسه هنوز نگاشت معتبر دارد و یتیم محسوب نمی‌شود.', 'hesabix-v2'),
			);
		}

		if ($parent_null_match) {
			return array(
				'ok' => true,
				'tier' => self::TIER_HIGH,
				'wc_parent_id' => (int) $parent_null_match['wc_parent_id'],
				'parent_name' => (string) $parent_null_match['parent_name'],
			);
		}

		if (is_array($row)) {
			$tier = isset($row['tier']) ? (string) $row['tier'] : self::TIER_HIGH;
			if ($tier === self::TIER_MEDIUM && !$allow_medium) {
				return array(
					'ok' => false,
					'message' => __('کاندیدای سطح متوسط فقط با تأیید صریح پاک‌سازی می‌شود.', 'hesabix-v2'),
					'tier' => self::TIER_MEDIUM,
				);
			}

			$status = isset($row['status']) ? (string) $row['status'] : 'pending';
			if ($status === 'deleted') {
				return array(
					'ok' => false,
					'message' => __('این مورد قبلاً حذف شده است.', 'hesabix-v2'),
				);
			}

			return array(
				'ok' => true,
				'tier' => $tier === self::TIER_MEDIUM ? self::TIER_MEDIUM : self::TIER_HIGH,
				'wc_parent_id' => isset($row['wc_parent_id']) ? absint($row['wc_parent_id']) : 0,
				'parent_name' => isset($row['parent_name']) ? (string) $row['parent_name'] : '',
			);
		}

		return array(
			'ok' => false,
			'message' => __('کاندیدا در اسکن/رجیستری یافت نشد. ابتدا اسکن کنید.', 'hesabix-v2'),
		);
	}

	/**
	 * @param int                  $hesabix_id
	 * @param array<string,mixed>  $validation
	 * @param array<string,mixed>  $base
	 * @param string               $reason
	 * @return array<string, mixed>
	 */
	private function deactivate_orphan($hesabix_id, array $validation, array $base, $reason)
	{
		$upd = $this->api->update_product(
			$hesabix_id,
			array(
				'is_active' => false,
			)
		);

		if (!empty($upd['success'])) {
			// نگاشت محلی والد را قطع کن تا دوباره لینک نشود
			if (!empty($validation['wc_parent_id'])) {
				$m = $this->db->get_mapping('product', (int) $validation['wc_parent_id'], null);
				if ($m && (int) $m['hesabix_id'] === $hesabix_id) {
					$this->db->delete_parent_only_product_mapping((int) $validation['wc_parent_id']);
				}
			}
			$this->db->delete_parent_only_product_mapping_by_hesabix_id($hesabix_id);

			$msg = sprintf(
				/* translators: %s reason */
				__('غیرفعال شد (حذف نشد): %s', 'hesabix-v2'),
				$reason
			);
			$this->update_registry_status($hesabix_id, 'deactivated', $msg, isset($base['document_types']) ? $base['document_types'] : array());

			$base['success'] = true;
			$base['action'] = 'deactivated';
			$base['message'] = $msg;

			Hesabix_V2_Log_Service::info(
				'Orphan parent product deactivated',
				array(
					'entity_type' => 'product',
					'hesabix_id' => $hesabix_id,
					'wc_parent_id' => (int) ($validation['wc_parent_id'] ?? 0),
					'reason' => $reason,
				)
			);

			return $base;
		}

		$base['message'] = isset($upd['message'])
			? (string) $upd['message']
			: __('غیرفعال‌سازی ناموفق بود.', 'hesabix-v2');
		$this->update_registry_status($hesabix_id, 'error', $base['message']);
		return $base;
	}

	/**
	 * @param int         $hesabix_id
	 * @param string      $status
	 * @param string      $message
	 * @param array       $document_types
	 * @return void
	 */
	private function update_registry_status($hesabix_id, $status, $message = '', array $document_types = array())
	{
		$registry = self::get_registry();
		if (!isset($registry[ $hesabix_id ]) || !is_array($registry[ $hesabix_id ])) {
			$registry[ $hesabix_id ] = array(
				'hesabix_id' => $hesabix_id,
				'tier' => self::TIER_HIGH,
				'source' => 'cleanup',
			);
		}

		$registry[ $hesabix_id ]['status'] = $status;
		$registry[ $hesabix_id ]['last_message'] = $message;
		$registry[ $hesabix_id ]['updated_at'] = current_time('mysql');
		if (!empty($document_types)) {
			$registry[ $hesabix_id ]['document_types'] = $document_types;
		}

		self::save_registry($registry);
	}
}
