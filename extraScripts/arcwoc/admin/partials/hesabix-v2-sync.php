<?php
/**
 * Sync view — همگام‌سازی دسته‌ای با مرحله‌بندی AJAX
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 */

if (!defined('WPINC')) {
	die;
}

$bulk_defs = Hesabix_V2_Sync_Service::get_bulk_sync_defaults();
$bulk_opts = Hesabix_V2_Sync_Service::get_bulk_sync_options();
?>

<div class="wrap hesabix-v2-wrap hesabix-v2-sync-page">
	<h1><?php echo esc_html(get_admin_page_title()); ?></h1>

	<?php if (!empty($_GET['hesabix_bulk_saved'])): ?>
		<div class="notice notice-success is-dismissible"><p><?php esc_html_e('تنظیمات اندازهٔ دسته ذخیره شد.', 'hesabix-v2'); ?></p></div>
	<?php endif; ?>

	<form method="post" action="" class="hesabix-v2-card hesabix-v2-bulk-settings-form">
		<?php wp_nonce_field('hesabix_v2_bulk_sync_save'); ?>
		<input type="hidden" name="hesabix_v2_save_bulk_sync" value="1">
		<h2><?php esc_html_e('همگام‌سازی دسته‌ای (کاهش تایم‌اوت)', 'hesabix-v2'); ?></h2>
		<p class="description"><?php esc_html_e('در فروشگاه‌های بزرگ، عملیات در چند درخواست کوتاه‌تر تقسیم می‌شود. اگر یک مرحله خطا بدهد، بقیه مراحل ادامه می‌یابند. در انتها خلاصه و نمونهٔ خطاها نمایش داده می‌شود.', 'hesabix-v2'); ?></p>

		<table class="form-table hesabix-v2-bulk-form-table">
			<tr>
				<th scope="row"><label for="wc_product_parents_per_ajax"><?php esc_html_e('تعداد محصول والد به‌ازای هر درخواست (وکامرس → حسابیکس)', 'hesabix-v2'); ?></label></th>
				<td>
					<input type="number" min="5" max="500" step="1" name="wc_product_parents_per_ajax" id="wc_product_parents_per_ajax" value="<?php echo esc_attr((string) $bulk_opts['wc_product_parents_per_ajax']); ?>" class="small-text">
					<p class="description"><?php esc_html_e('محصول متغیر به ازای هر واریانت یک عملیات API جدا دارد؛ مقدار کمتر بار شبکهٔ پایدارتر و زمان هر مرحله کوتاه‌تر.', 'hesabix-v2'); ?></p>
				</td>
			</tr>
			<tr>
				<th scope="row"><label for="wc_customers_per_ajax"><?php esc_html_e('تعداد مشتری به‌ازای هر درخواست (وکامرس → حسابیکس)', 'hesabix-v2'); ?></label></th>
				<td>
					<input type="number" min="5" max="500" step="1" name="wc_customers_per_ajax" id="wc_customers_per_ajax" value="<?php echo esc_attr((string) $bulk_opts['wc_customers_per_ajax']); ?>" class="small-text">
				</td>
			</tr>
			<tr>
				<th scope="row"><label for="hesabix_person_take"><?php esc_html_e('اندازهٔ صفحهٔ API اشخاص (حسابیکس → ووکامرس)', 'hesabix-v2'); ?></label></th>
				<td>
					<input type="number" min="10" max="200" step="1" name="hesabix_person_take" id="hesabix_person_take" value="<?php echo esc_attr((string) $bulk_opts['hesabix_person_take']); ?>" class="small-text">
				</td>
			</tr>
			<tr>
				<th scope="row"><label for="hesabix_import_pages_per_ajax"><?php esc_html_e('تعداد صفحهٔ اشخاص در هر درخواست واردات', 'hesabix-v2'); ?></label></th>
				<td>
					<input type="number" min="1" max="50" step="1" name="hesabix_import_pages_per_ajax" id="hesabix_import_pages_per_ajax" value="<?php echo esc_attr((string) $bulk_opts['hesabix_import_pages_per_ajax']); ?>" class="small-text">
				</td>
			</tr>
			<tr>
				<th scope="row"><label for="errors_preview_cap"><?php esc_html_e('حداکثر نمونهٔ خطا برای هر مرحله در پاسخ JSON', 'hesabix-v2'); ?></label></th>
				<td>
					<input type="number" min="10" max="300" step="1" name="errors_preview_cap" id="errors_preview_cap" value="<?php echo esc_attr((string) $bulk_opts['errors_preview_cap']); ?>" class="small-text">
				</td>
			</tr>
		</table>
		<p>
			<?php submit_button(__('ذخیرهٔ اندازهٔ دسته‌ها', 'hesabix-v2'), 'secondary', 'submit', false); ?>
		</p>
	</form>

	<div class="hesabix-v2-card">
		<h2><?php esc_html_e('همگام‌سازی محصولات', 'hesabix-v2'); ?></h2>
		<p><?php esc_html_e('تمام محصولات منتشرشدهٔ ووکامرس به حسابیکس؛ به‌صورت چند مرحله.', 'hesabix-v2'); ?></p>
		<button id="sync-products" type="button" class="button button-primary"><?php esc_html_e('همگام‌سازی همهٔ محصولات', 'hesabix-v2'); ?></button>
		<button id="abort-sync-products" type="button" class="button" style="display:none;" aria-live="polite"><?php esc_html_e('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2'); ?></button>
		<div id="products-progress" class="hesabix-v2-sync-progress" aria-live="polite"></div>
		<div id="products-result"></div>
	</div>

	<div class="hesabix-v2-card">
		<h2><?php esc_html_e('همگام‌سازی مشتریان', 'hesabix-v2'); ?></h2>
		<p><?php esc_html_e('کاربران با نقش مشتری یا مشترک به حسابیکس؛ مرحله‌ای.', 'hesabix-v2'); ?></p>
		<button id="sync-customers" type="button" class="button button-primary"><?php esc_html_e('همگام‌سازی همهٔ مشتریان', 'hesabix-v2'); ?></button>
		<button id="abort-sync-customers" type="button" class="button" style="display:none;"><?php esc_html_e('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2'); ?></button>
		<div id="customers-progress" class="hesabix-v2-sync-progress" aria-live="polite"></div>
		<div id="customers-result"></div>
	</div>

	<div class="hesabix-v2-card">
		<h2><?php esc_html_e('واردات مشتریان از حسابیکس', 'hesabix-v2'); ?></h2>
		<p><?php esc_html_e('اشخاص حسابیکس با ایمیل یا موبایل معتبر با کاربر ووکامرس تطبیق داده می‌شوند.', 'hesabix-v2'); ?></p>
		<p>
			<label>
				<input type="checkbox" id="hesabix-import-create-missing" value="1">
				<?php esc_html_e('ایجاد حساب مشتری برای اشخاصی که ایمیل معتبر دارند و کاربر نیستند', 'hesabix-v2'); ?>
			</label>
		</p>
		<p class="description"><?php esc_html_e('رمز تصادفی ساخته می‌شود؛ ممکن است ووکامرس ایمیل ارسال کند.', 'hesabix-v2'); ?></p>
		<p>
			<button type="button" id="import-customers-from-hesabix" class="button button-primary"><?php esc_html_e('واردات از حسابیکس', 'hesabix-v2'); ?></button>
			<button id="abort-import-customers" type="button" class="button" style="display:none;"><?php esc_html_e('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2'); ?></button>
		</p>
		<div id="import-customers-progress" class="hesabix-v2-sync-progress" aria-live="polite"></div>
		<div id="import-customers-result"></div>
	</div>

	<div class="hesabix-v2-card">
		<h2><?php esc_html_e('وضعیت همگام‌سازی', 'hesabix-v2'); ?></h2>
		<?php
		$db = new Hesabix_V2_DB_Service();
		$pending = $db->get_pending_items(null, 100);
		$errors = $db->get_error_items(null, 100);
		?>
		<p>
			<?php esc_html_e('موارد در انتظار:', 'hesabix-v2'); ?> <strong><?php echo count($pending); ?></strong><br>
			<?php esc_html_e('موارد با خطا:', 'hesabix-v2'); ?> <strong><?php echo count($errors); ?></strong>
		</p>

		<?php if (!empty($errors)): ?>
			<h3><?php esc_html_e('خطاهای اخیر', 'hesabix-v2'); ?></h3>
			<table class="wp-list-table widefat fixed striped">
				<thead>
					<tr>
						<th><?php esc_html_e('نوع', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('شناسه', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('پیام خطا', 'hesabix-v2'); ?></th>
						<th><?php esc_html_e('تلاش مجدد', 'hesabix-v2'); ?></th>
					</tr>
				</thead>
				<tbody>
					<?php foreach ($errors as $error): ?>
						<tr>
							<td><?php echo esc_html($error['entity_type']); ?></td>
							<td><?php echo esc_html($error['wc_id']); ?></td>
							<td><?php echo esc_html($error['error_message']); ?></td>
							<td><?php echo esc_html($error['retry_count']); ?></td>
						</tr>
					<?php endforeach; ?>
				</tbody>
			</table>
		<?php endif; ?>
	</div>
</div>

<style>
.hesabix-v2-bulk-settings-form { margin-bottom: 20px; }
.hesabix-v2-bulk-form-table th { width: 280px; vertical-align: top; }
.hesabix-v2-sync-progress {
	margin: 12px 0 6px;
	padding: 10px 12px;
	background: #f6f7f7;
	border: 1px solid #c3c4c7;
	border-radius: 4px;
	font-size: 13px;
	line-height: 1.55;
	max-width: 720px;
}
.hesabix-v2-sync-progress .hesabix-v2-sync-bar {
	height: 8px;
	background: #dcdcde;
	border-radius: 4px;
	overflow: hidden;
	margin-top: 8px;
}
.hesabix-v2-sync-progress .hesabix-v2-sync-bar > span {
	display: block;
	height: 100%;
	background: #2271b1;
	width: 0%;
	transition: width 0.25s ease;
}
</style>

<script>
jQuery(function($) {
	var ajaxUrl = (typeof hesabix_v2_ajax !== 'undefined' && hesabix_v2_ajax.ajax_url) ? hesabix_v2_ajax.ajax_url : (typeof ajaxurl !== 'undefined' ? ajaxurl : '');
	var nonce = (typeof hesabix_v2_ajax !== 'undefined' && hesabix_v2_ajax.nonce) ? hesabix_v2_ajax.nonce : '';
	var bulk = (typeof hesabix_v2_ajax !== 'undefined' && hesabix_v2_ajax.bulk_sync) ? hesabix_v2_ajax.bulk_sync : {};

	function esc(s) {
		return $('<div/>').text(String(s == null ? '' : s)).html();
	}

	function mergeImportStats(tot, ch) {
		if (!ch) return;
		tot.matched_updated += (ch.matched_updated || 0);
		tot.created += (ch.created || 0);
		tot.skipped += (ch.skipped || 0);
		tot.failed += (ch.failed || 0);
		tot.total_processed += (ch.total_processed || 0);
	}

	function attachErrors(agg, chunk) {
		if (!chunk || !chunk.errors_preview || !chunk.errors_preview.length) return;
		for (var i = 0; i < chunk.errors_preview.length && agg.errors.length < 200; i++) {
			agg.errors.push(chunk.errors_preview[i]);
		}
	}

	function ajaxChunk(action, data, retries) {
		retries = retries === undefined ? 3 : retries;
		return $.Deferred(function(def) {
			function attempt(left) {
				$.ajax({
					url: ajaxUrl,
					type: 'POST',
					timeout: 300000,
					data: $.extend({ action: action, nonce: nonce }, data)
				}).done(function(res) {
					def.resolve(res || {});
				}).fail(function(xhr, status) {
					if (left > 0 && (status === 'timeout' || xhr.status === 0 || xhr.status >= 500)) {
						window.setTimeout(function() {
							attempt(left - 1);
						}, 800 + (400 * (4 - left)));
						return;
					}
					def.resolve({
						success: false,
						message: status || xhr.statusText || '<?php echo esc_js(__('خطای شبکه یا سرور', 'hesabix-v2')); ?>'
					});
				});
			}
			attempt(retries);
		}).promise();
	}

	function fmtProductErr(e) {
		if (!e) {
			return '';
		}
		var label = e.variation_id ? ('#' + e.product_id + ' (واریانت ' + e.variation_id + ')') : ('#' + (e.product_id || ''));
		return esc(label) + ': ' + esc(e.message || '');
	}

	function renderFinalNoticeCls(aggFailed) {
		return aggFailed > 0 ? 'notice-warning' : 'notice-success';
	}

	// --- محصولات ---
	var abortProducts = false;
	$('#abort-sync-products').on('click', function() {
		abortProducts = true;
		$(this).prop('disabled', true).text('<?php echo esc_js(__('در انتظار پایان مرحلهٔ جاری…', 'hesabix-v2')); ?>');
	});

	$('#sync-products').on('click', async function() {
		if (!ajaxUrl || !nonce) return;
		if (!confirm('<?php echo esc_js(__('این عمل در چند مرحله انجام می‌شود و ممکن است طولانی باشد. ادامه می‌دهید؟', 'hesabix-v2')); ?>')) return;

		var $btn = $('#sync-products');
		var $abort = $('#abort-sync-products');
		var $prog = $('#products-progress');
		var $result = $('#products-result');
		abortProducts = false;
		$btn.prop('disabled', true);
		$abort.prop('disabled', false).show().text('<?php echo esc_js(__('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2')); ?>');

		var agg = { success: 0, failed: 0, total: 0, errors: [], batches: 0, haltedMsg: '', networkStalls: 0 };
		var offset = 0;
		var batch = parseInt(String(bulk.wc_product_parents_per_ajax || <?php echo (int) $bulk_defs['wc_product_parents_per_ajax']; ?>), 10) || 35;
		var estTotal = null;

		for (;;) {
			if (abortProducts) {
				agg.haltedMsg = '<?php echo esc_js(__('توسط کاربر متوقف شد (پس از آخرین مرحلهٔ کامل).', 'hesabix-v2')); ?>';
				break;
			}
			$prog.html(
				'<strong><?php echo esc_js(__('در حال اجرا…', 'hesabix-v2')); ?></strong>'
				+ '<div class="hesabix-v2-sync-bar"><span></span></div>'
				+ '<p class="hesabix-sync-progress-text"></p>'
			);
			var pct = estTotal ? Math.min(99, Math.round((offset / estTotal) * 100)) : 0;
			$prog.find('.hesabix-v2-sync-bar > span').css('width', pct + '%');
			$prog.find('.hesabix-sync-progress-text').text(
				'<?php echo esc_js(__('مرحلهٔ', 'hesabix-v2')); ?> ' + (agg.batches + 1)
				+ ' — <?php echo esc_js(__('offset', 'hesabix-v2')); ?> ' + offset
				+ (estTotal !== null ? ' / ~' + estTotal : '')
			);

			var res = await ajaxChunk('hesabix_v2_sync_products', { offset: offset, batch_size: batch });

			if (!res || res.success !== true || !res.chunk_results) {
				agg.haltedMsg = (res && res.message) ? res.message : '<?php echo esc_js(__('پاسخ نامعتبر یا خطای سرور', 'hesabix-v2')); ?>';
				break;
			}

			var ch = res.chunk_results;
			agg.success += (ch.success || 0);
			agg.failed += (ch.failed || 0);
			agg.total += (ch.total || 0);
			attachErrors(agg, ch);
			agg.batches++;

			if (agg.batches > 5000) {
				agg.haltedMsg += (agg.haltedMsg ? ' ' : '') +
					'<?php echo esc_js(__('حداکثر تعداد مراحل ایمن رسید؛ در صورت نیاز دوباره اجرا کنید.', 'hesabix-v2')); ?>';
				break;
			}

			if (res.estimated_catalog_total_parents !== undefined && res.estimated_catalog_total_parents !== null) {
				estTotal = parseInt(res.estimated_catalog_total_parents, 10) || estTotal;
			}
			offset = parseInt(res.next_offset, 10) || 0;

			if (res.done) {
				break;
			}

			var advance = parseInt(res.processed_parent_posts_in_chunk, 10);
			if (!advance || advance < 1) {
				break;
			}
		}

		var cls = renderFinalNoticeCls(agg.failed);
		var note = '';
		note += '<strong><?php echo esc_js(__('گزارش نهایی همگام‌سازی محصولات', 'hesabix-v2')); ?></strong><br>';
		note += '<?php echo esc_js(__('موفق:', 'hesabix-v2')); ?> ' + agg.success + '<br>';
		note += '<?php echo esc_js(__('ناموفق:', 'hesabix-v2')); ?> ' + agg.failed + '<br>';
		note += '<?php echo esc_js(__('جمع عملیات (شامل واریانت‌ها):', 'hesabix-v2')); ?> ' + agg.total + '<br>';
		note += '<?php echo esc_js(__('تعداد دستهٔ اجراشده:', 'hesabix-v2')); ?> ' + agg.batches + '<br>';
		if (agg.haltedMsg) {
			note += '<strong><?php echo esc_js(__('وضعیت:', 'hesabix-v2')); ?></strong> ' + esc(agg.haltedMsg) + '<br>';
		}

		if (agg.errors.length) {
			note += '<br><strong><?php echo esc_js(__('نمونهٔ خطاها (حداکثر ۲۰ خط نخست ذخیره‌شده در گزارش):', 'hesabix-v2')); ?></strong><ul>';
			var show = agg.errors.slice(0, 20);
			for (var ei = 0; ei < show.length; ei++) {
				note += '<li>' + fmtProductErr(show[ei]) + '</li>';
			}
			note += '</ul>';
			if (agg.errors.length > 20) {
				note += '<p class="description">' + esc('<?php echo esc_js(__('… و خطاهای دیگر؛ جمع خطاهای دارای جزئیات در هر مرحله در پاسخ سرور بوده است.', 'hesabix-v2')); ?>') + '</p>';
			}
		}

		$prog.empty();
		$result.html('<div class="notice ' + cls + '"><p>' + note + '</p></div>');
		$btn.prop('disabled', false);
		$abort.hide().prop('disabled', false).text('<?php echo esc_js(__('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2')); ?>');
	});

	// --- مشتریان (به حسابیکس) ---
	var abortCustomers = false;
	$('#abort-sync-customers').on('click', function() {
		abortCustomers = true;
		$(this).prop('disabled', true).text('<?php echo esc_js(__('در انتظار پایان مرحلهٔ جاری…', 'hesabix-v2')); ?>');
	});

	$('#sync-customers').on('click', async function() {
		if (!ajaxUrl || !nonce) return;
		if (!confirm('<?php echo esc_js(__('این عمل در چند مرحله انجام می‌شود. ادامه می‌دهید؟', 'hesabix-v2')); ?>')) return;

		var $btn = $('#sync-customers');
		var $abort = $('#abort-sync-customers');
		var $prog = $('#customers-progress');
		var $result = $('#customers-result');
		abortCustomers = false;
		$btn.prop('disabled', true);
		$abort.prop('disabled', false).show().text('<?php echo esc_js(__('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2')); ?>');

		var agg = { success: 0, failed: 0, total: 0, errors: [], batches: 0, haltedMsg: '' };
		var offset = 0;
		var batch = parseInt(String(bulk.wc_customers_per_ajax || <?php echo (int) $bulk_defs['wc_customers_per_ajax']; ?>), 10) || 45;
		var estTotal = null;

		for (;;) {
			if (abortCustomers) {
				agg.haltedMsg = '<?php echo esc_js(__('توسط کاربر متوقف شد.', 'hesabix-v2')); ?>';
				break;
			}
			$prog.html(
				'<strong><?php echo esc_js(__('در حال اجرا…', 'hesabix-v2')); ?></strong>'
				+ '<div class="hesabix-v2-sync-bar"><span></span></div>'
				+ '<p class="hesabix-sync-progress-text"></p>'
			);
			var pct = estTotal ? Math.min(99, Math.round((offset / estTotal) * 100)) : 0;
			$prog.find('.hesabix-v2-sync-bar > span').css('width', pct + '%');
			$prog.find('.hesabix-sync-progress-text').text(
				'<?php echo esc_js(__('مرحلهٔ', 'hesabix-v2')); ?> ' + (agg.batches + 1) + ' — offset ' + offset + (estTotal !== null ? ' / ~' + estTotal : '')
			);

			var res = await ajaxChunk('hesabix_v2_sync_customers', { offset: offset, batch_size: batch });
			if (!res || res.success !== true || !res.chunk_results) {
				agg.haltedMsg = (res && res.message) ? res.message : '<?php echo esc_js(__('پاسخ نامعتبر یا خطای سرور', 'hesabix-v2')); ?>';
				break;
			}
			var ch = res.chunk_results;
			agg.success += (ch.success || 0);
			agg.failed += (ch.failed || 0);
			agg.total += (ch.total || 0);
			attachErrors(agg, ch);
			agg.batches++;

			if (agg.batches > 5000) {
				agg.haltedMsg += (agg.haltedMsg ? ' ' : '') +
					'<?php echo esc_js(__('حداکثر تعداد مراحل ایمن رسید؛ در صورت نیاز دوباره اجرا کنید.', 'hesabix-v2')); ?>';
				break;
			}

			if (res.estimated_catalog_total_customers !== undefined) {
				estTotal = parseInt(res.estimated_catalog_total_customers, 10) || estTotal;
			}
			offset = parseInt(res.next_offset, 10) || 0;
			if (res.done) break;
			var adv = parseInt(res.processed_in_chunk, 10);
			if (!adv || adv < 1) break;
		}

		var cls = renderFinalNoticeCls(agg.failed);
		var note = '';
		note += '<strong><?php echo esc_js(__('گزارش نهایی همگام‌سازی مشتریان', 'hesabix-v2')); ?></strong><br>';
		note += '<?php echo esc_js(__('موفق:', 'hesabix-v2')); ?> ' + agg.success + '<br>';
		note += '<?php echo esc_js(__('ناموفق:', 'hesabix-v2')); ?> ' + agg.failed + '<br>';
		note += '<?php echo esc_js(__('کل در این عملیات:', 'hesabix-v2')); ?> ' + agg.total + '<br>';
		note += '<?php echo esc_js(__('تعداد دسته:', 'hesabix-v2')); ?> ' + agg.batches + '<br>';
		if (agg.haltedMsg) note += '<strong><?php echo esc_js(__('وضعیت:', 'hesabix-v2')); ?></strong> ' + esc(agg.haltedMsg) + '<br>';
		if (agg.errors.length) {
			note += '<br><strong><?php echo esc_js(__('نمونهٔ خطاها:', 'hesabix-v2')); ?></strong><ul>';
			var sh = agg.errors.slice(0, 20);
			for (var cj = 0; cj < sh.length; cj++) {
				var ee = sh[cj];
				note += '<li>' + esc('#' + (ee.customer_id || '') + ': ' + (ee.message || '')) + '</li>';
			}
			note += '</ul>';
		}
		$prog.empty();
		$result.html('<div class="notice ' + cls + '"><p>' + note + '</p></div>');
		$btn.prop('disabled', false);
		$abort.hide().prop('disabled', false).text('<?php echo esc_js(__('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2')); ?>');
	});

	// --- واردات از حسابیکس ---
	var abortImport = false;
	$('#abort-import-customers').on('click', function() {
		abortImport = true;
		$(this).prop('disabled', true).text('<?php echo esc_js(__('در انتظار پایان مرحلهٔ جاری…', 'hesabix-v2')); ?>');
	});

	$('#import-customers-from-hesabix').on('click', async function() {
		if (!ajaxUrl || !nonce) return;
		if (!confirm('<?php echo esc_js(__('واردات در چند مرحله انجام می‌شود. ادامه می‌دهید؟', 'hesabix-v2')); ?>')) return;

		var $btn = $('#import-customers-from-hesabix');
		var $abort = $('#abort-import-customers');
		var $prog = $('#import-customers-progress');
		var $result = $('#import-customers-result');
		var createMissing = $('#hesabix-import-create-missing').is(':checked') ? '1' : '';

		var tot = { matched_updated: 0, created: 0, skipped: 0, failed: 0, total_processed: 0 };
		var batches = 0;
		var skip = 0;
		var halt = '';
		var lastImportRes = { success: true };
		abortImport = false;
		$btn.prop('disabled', true);
		$abort.prop('disabled', false).show().text('<?php echo esc_js(__('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2')); ?>');

		for (;;) {
			if (abortImport) {
				halt = '<?php echo esc_js(__('توسط کاربر متوقف شد.', 'hesabix-v2')); ?>';
				break;
			}
			batches++;
			$prog.html(
				'<strong><?php echo esc_js(__('در حال واردات…', 'hesabix-v2')); ?></strong>'
				+ '<p class="hesabix-import-skip-msg"></p>'
			);
			$prog.find('.hesabix-import-skip-msg').text('<?php echo esc_js(__('موقعیت:', 'hesabix-v2')); ?> skip = ' + skip);

			var res = await ajaxChunk('hesabix_v2_import_customers_from_hesabix', {
				skip: skip,
				create_missing: createMissing
			});
			lastImportRes = res || lastImportRes;

			if (!res.success) {
				halt = (res.message || '') + '';
				if (res.chunk_stats) mergeImportStats(tot, res.chunk_stats);
				break;
			}

			if (res.chunk_stats) mergeImportStats(tot, res.chunk_stats);
			skip = parseInt(res.next_skip, 10) || skip;

			if (res.done) {
				break;
			}
			if (batches > 8000) {
				halt = '<?php echo esc_js(__('توقف ایمن؛ برای ادامه دوباره واردات را اجرا کنید (از همان ابتدا لیست اشخاص).', 'hesabix-v2')); ?>';
				break;
			}
			if (!(parseInt(res.pages_fetched, 10) > 0)) {
				halt = '<?php echo esc_js(__('هیچ صفحه‌ای از API دریافت نشد؛ واردات متوقف شد.', 'hesabix-v2')); ?>';
				break;
			}
		}

		var touched = !!(tot.total_processed || tot.created || tot.matched_updated);
		var cls = 'notice-success';
		if (lastImportRes && lastImportRes.success !== true && !touched && !halt) {
			cls = 'notice-error';
		} else if (
			halt ||
			tot.failed > 0 ||
			(lastImportRes && lastImportRes.success !== true && touched)
		) {
			cls = 'notice-warning';
		}

		var html = '';
		html += '<strong><?php echo esc_js(__('گزارش واردات', 'hesabix-v2')); ?></strong><br>';
		html += '<?php echo esc_js(__('کل پردازش‌شده:', 'hesabix-v2')); ?> ' + tot.total_processed + '<br>';
		html += '<?php echo esc_js(__('به‌روزشده:', 'hesabix-v2')); ?> ' + tot.matched_updated + '<br>';
		html += '<?php echo esc_js(__('ایجاد شده:', 'hesabix-v2')); ?> ' + tot.created + '<br>';
		html += '<?php echo esc_js(__('رد شده:', 'hesabix-v2')); ?> ' + tot.skipped + '<br>';
		html += '<?php echo esc_js(__('ناموفق:', 'hesabix-v2')); ?> ' + tot.failed + '<br>';
		html += '<?php echo esc_js(__('تعداد دستهٔ AJAX:', 'hesabix-v2')); ?> ' + batches + '<br>';
		if (halt) {
			html += '<strong><?php echo esc_js(__('وضعیت:', 'hesabix-v2')); ?></strong> ' + esc(halt) + '<br>';
		}

		$prog.empty();
		$result.html('<div class="notice ' + cls + '"><p>' + html + '</p></div>');
		$btn.prop('disabled', false);
		$abort.hide().prop('disabled', false).text('<?php echo esc_js(__('توقف پس از پایان مرحلهٔ جاری', 'hesabix-v2')); ?>');
	});
});
</script>
