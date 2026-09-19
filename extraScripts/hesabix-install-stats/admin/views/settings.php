<?php
/**
 * تنظیمات افزونه.
 *
 * @package Hesabix_Install_Stats
 *
 * @var string $token
 * @var int    $days
 * @var string $endpoint
 */

defined( 'ABSPATH' ) || exit;
?>
<div class="wrap his-wrap">
	<h1><?php esc_html_e( 'تنظیمات آمار نصب', 'hesabix-install-stats' ); ?></h1>

	<?php if ( isset( $_GET['updated'] ) ) : // phpcs:ignore WordPress.Security.NonceVerification.Recommended ?>
		<div class="notice notice-success is-dismissible"><p><?php esc_html_e( 'ذخیره شد.', 'hesabix-install-stats' ); ?></p></div>
	<?php endif; ?>

	<div class="his-panel" style="margin-bottom:20px;">
		<h2><?php esc_html_e( 'Endpoint', 'hesabix-install-stats' ); ?></h2>
		<p><code class="his-mono"><?php echo esc_html( $endpoint ); ?></code></p>
		<p class="his-muted">
			<?php esc_html_e( 'هدر لازم: X-Hesabix-Stats-Token', 'hesabix-install-stats' ); ?>
			·
			<?php esc_html_e( 'Health:', 'hesabix-install-stats' ); ?>
			<code class="his-mono"><?php echo esc_html( str_replace( '/event', '/health', $endpoint ) ); ?></code>
		</p>
	</div>

	<form method="post">
		<?php wp_nonce_field( 'his_save_settings' ); ?>
		<table class="form-table" role="presentation">
			<tr>
				<th scope="row"><label for="his_ingest_token"><?php esc_html_e( 'توکن ingest', 'hesabix-install-stats' ); ?></label></th>
				<td>
					<input type="text" class="regular-text his-mono" id="his_ingest_token" name="his_ingest_token" value="<?php echo esc_attr( $token ); ?>" autocomplete="off" />
					<p class="description">
						<?php esc_html_e( 'باید با HESABIX_STATS_TOKEN در سرورهای نصب‌شده یکی باشد. خالی = بدون توکن (توصیه نمی‌شود).', 'hesabix-install-stats' ); ?>
					</p>
				</td>
			</tr>
			<tr>
				<th scope="row"><label for="his_retention_days"><?php esc_html_e( 'نگهداری تاریخچه رویداد (روز)', 'hesabix-install-stats' ); ?></label></th>
				<td>
					<input type="number" min="30" max="3650" id="his_retention_days" name="his_retention_days" value="<?php echo esc_attr( (string) $days ); ?>" />
					<p class="description"><?php esc_html_e( 'ردیف نمونه‌ها حذف نمی‌شوند؛ فقط رویدادهای قدیمی‌تر پاک می‌شوند.', 'hesabix-install-stats' ); ?></p>
				</td>
			</tr>
		</table>
		<?php submit_button( __( 'ذخیره', 'hesabix-install-stats' ), 'primary', 'his_save_settings' ); ?>
	</form>
</div>
