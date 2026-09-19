<?php
/**
 * داشبورد آمار نصب.
 *
 * @package Hesabix_Install_Stats
 *
 * @var array $summary
 * @var array $by_day
 * @var array $installs_day
 * @var array $os
 * @var array $branch
 * @var array $pip
 * @var array $flutter
 * @var array $arch
 * @var array $ram
 * @var array $cpu
 * @var array $app_ver
 */

defined( 'ABSPATH' ) || exit;

$max_day = 1;
foreach ( $by_day as $row ) {
	$max_day = max( $max_day, (int) $row['c'] );
}

$dist_max = static function ( array $rows ) {
	$m = 1;
	foreach ( $rows as $r ) {
		$m = max( $m, (int) $r['c'] );
	}
	return $m;
};

$render_dist = static function ( $title, array $rows ) use ( $dist_max ) {
	$max = $dist_max( $rows );
	echo '<div class="his-panel">';
	echo '<h2>' . esc_html( $title ) . '</h2>';
	if ( ! $rows ) {
		echo '<p class="his-muted">' . esc_html__( 'داده‌ای نیست.', 'hesabix-install-stats' ) . '</p></div>';
		return;
	}
	echo '<table class="his-table"><thead><tr><th>' . esc_html__( 'مورد', 'hesabix-install-stats' ) . '</th><th>' . esc_html__( 'تعداد', 'hesabix-install-stats' ) . '</th></tr></thead><tbody>';
	foreach ( $rows as $r ) {
		$label = ( $r['label'] === '' || $r['label'] === null ) ? '—' : (string) $r['label'];
		echo '<tr><td>' . esc_html( $label ) . ' ' . HIS_Admin::bar_html( (int) $r['c'], $max ) . '</td><td>' . esc_html( (string) (int) $r['c'] ) . '</td></tr>';
	}
	echo '</tbody></table></div>';
};
?>
<div class="wrap his-wrap">
	<h1><?php echo esc_html__( 'آمار نصب Hesabix', 'hesabix-install-stats' ); ?></h1>
	<p class="his-muted">
		<?php echo esc_html__( 'جمع‌آوری ناشناس/نیمه‌ناشناس از سرورهایی که Hesabix را با deploy.sh یا hesabix -update نصب/به‌روز می‌کنند.', 'hesabix-install-stats' ); ?>
	</p>

	<div class="his-cards">
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'کل نمونه‌ها', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['total_instances'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'فعال ۷ روز', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['active_7d'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'فعال ۳۰ روز', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['active_30d'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'ساکت ۹۰+ روز', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['silent_90d'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'نصب امروز', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['installs_today'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'نصب ۷ روز', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['installs_7d'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'نصب ۳۰ روز', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['installs_30d'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'آپدیت ۳۰ روز', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['updates_30d'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'SSL API', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['ssl_api_count'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'SSL UI', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['ssl_ui_count'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'Voice', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['voice_count'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'pgAdmin', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['pgadmin_count'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'میانگین RAM (MB)', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['avg_ram_mb'] ); ?></span></div>
		<div class="his-card"><span class="his-card__label"><?php esc_html_e( 'میانگین CPU', 'hesabix-install-stats' ); ?></span><span class="his-card__value"><?php echo esc_html( (string) $summary['avg_cpu_cores'] ); ?></span></div>
	</div>

	<div class="his-panel" style="margin-bottom:20px;">
		<h2><?php esc_html_e( 'رویدادها — ۳۰ روز اخیر', 'hesabix-install-stats' ); ?></h2>
		<?php if ( ! $by_day ) : ?>
			<p class="his-muted"><?php esc_html_e( 'هنوز رویدادی ثبت نشده.', 'hesabix-install-stats' ); ?></p>
		<?php else : ?>
			<div class="his-spark" title="<?php esc_attr_e( 'همه رویدادها', 'hesabix-install-stats' ); ?>">
				<?php foreach ( $by_day as $row ) : ?>
					<?php
					$h = max( 4, (int) round( ( (int) $row['c'] / $max_day ) * 80 ) );
					?>
					<span class="his-spark__bar" style="height:<?php echo esc_attr( (string) $h ); ?>px" title="<?php echo esc_attr( $row['d'] . ': ' . $row['c'] ); ?>"></span>
				<?php endforeach; ?>
			</div>
			<p class="his-muted" style="margin-top:8px;">
				<?php
				printf(
					/* translators: %d: number of install events in 30 days */
					esc_html__( 'نصب در ۳۰ روز: %d', 'hesabix-install-stats' ),
					(int) array_sum( array_map( static function ( $r ) {
						return (int) $r['c'];
					}, $installs_day ) )
				);
				?>
			</p>
		<?php endif; ?>
	</div>

	<div class="his-grid-2">
		<?php
		$render_dist( __( 'توزیع سیستم‌عامل', 'hesabix-install-stats' ), $os );
		$render_dist( __( 'توزیع معماری', 'hesabix-install-stats' ), $arch );
		$render_dist( __( 'توزیع RAM', 'hesabix-install-stats' ), $ram );
		$render_dist( __( 'توزیع CPU', 'hesabix-install-stats' ), $cpu );
		$render_dist( __( 'شاخه Git', 'hesabix-install-stats' ), $branch );
		$render_dist( __( 'نسخه اپ', 'hesabix-install-stats' ), $app_ver );
		$render_dist( __( 'آینه pip', 'hesabix-install-stats' ), $pip );
		$render_dist( __( 'آینه Flutter', 'hesabix-install-stats' ), $flutter );
		?>
	</div>

	<p>
		<a class="button button-secondary" href="<?php echo esc_url( admin_url( 'admin.php?page=hesabix-install-stats-instances' ) ); ?>">
			<?php esc_html_e( 'مشاهده لیست نمونه‌ها', 'hesabix-install-stats' ); ?>
		</a>
		<a class="button button-secondary" href="<?php echo esc_url( admin_url( 'admin.php?page=hesabix-install-stats-domains' ) ); ?>">
			<?php esc_html_e( 'مشاهده دامنه‌ها', 'hesabix-install-stats' ); ?>
		</a>
		<a class="button" href="<?php echo esc_url( wp_nonce_url( admin_url( 'admin.php?his_export=csv' ), 'his_export_csv' ) ); ?>">
			<?php esc_html_e( 'خروجی CSV', 'hesabix-install-stats' ); ?>
		</a>
	</p>
</div>
