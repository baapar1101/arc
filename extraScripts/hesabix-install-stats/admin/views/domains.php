<?php
/**
 * لیست دامنه‌های ثبت‌شده (API / UI).
 *
 * @package Hesabix_Install_Stats
 *
 * @var array  $result
 * @var int    $page
 * @var string $search
 * @var string $role
 * @var string $active
 */

defined( 'ABSPATH' ) || exit;

$items  = $result['items'];
$total  = (int) $result['total'];
$pages  = max( 1, (int) ceil( $total / 50 ) );
$base   = admin_url( 'admin.php?page=hesabix-install-stats-domains' );
$unique = (int) $result['unique_domains'];
$api_n  = (int) $result['api_count'];
$ui_n   = (int) $result['ui_count'];
?>
<div class="wrap his-wrap">
	<h1><?php esc_html_e( 'دامنه‌های نصب‌شده', 'hesabix-install-stats' ); ?></h1>
	<p class="his-muted">
		<?php esc_html_e( 'فهرست دامنهٔ API و UI گزارش‌شده از سرورهای Hesabix برای ادمین.', 'hesabix-install-stats' ); ?>
	</p>

	<div class="his-cards">
		<div class="his-card">
			<span class="his-card__label"><?php esc_html_e( 'ردیف دامنه (API+UI)', 'hesabix-install-stats' ); ?></span>
			<span class="his-card__value"><?php echo esc_html( (string) $total ); ?></span>
		</div>
		<div class="his-card">
			<span class="his-card__label"><?php esc_html_e( 'دامنه یکتا', 'hesabix-install-stats' ); ?></span>
			<span class="his-card__value"><?php echo esc_html( (string) $unique ); ?></span>
		</div>
		<div class="his-card">
			<span class="his-card__label"><?php esc_html_e( 'دامنه API', 'hesabix-install-stats' ); ?></span>
			<span class="his-card__value"><?php echo esc_html( (string) $api_n ); ?></span>
		</div>
		<div class="his-card">
			<span class="his-card__label"><?php esc_html_e( 'دامنه UI', 'hesabix-install-stats' ); ?></span>
			<span class="his-card__value"><?php echo esc_html( (string) $ui_n ); ?></span>
		</div>
	</div>

	<form method="get" class="his-filters">
		<input type="hidden" name="page" value="hesabix-install-stats-domains" />
		<input type="search" name="s" value="<?php echo esc_attr( $search ); ?>" placeholder="<?php esc_attr_e( 'جستجوی دامنه یا IP…', 'hesabix-install-stats' ); ?>" class="regular-text" />
		<select name="role">
			<option value=""><?php esc_html_e( 'همه نقش‌ها', 'hesabix-install-stats' ); ?></option>
			<option value="api" <?php selected( $role, 'api' ); ?>><?php esc_html_e( 'فقط API', 'hesabix-install-stats' ); ?></option>
			<option value="ui" <?php selected( $role, 'ui' ); ?>><?php esc_html_e( 'فقط UI', 'hesabix-install-stats' ); ?></option>
		</select>
		<select name="active">
			<option value=""><?php esc_html_e( 'همه وضعیت‌ها', 'hesabix-install-stats' ); ?></option>
			<option value="7" <?php selected( $active, '7' ); ?>><?php esc_html_e( 'فعال ۷ روز', 'hesabix-install-stats' ); ?></option>
			<option value="30" <?php selected( $active, '30' ); ?>><?php esc_html_e( 'فعال ۳۰ روز', 'hesabix-install-stats' ); ?></option>
			<option value="silent90" <?php selected( $active, 'silent90' ); ?>><?php esc_html_e( 'ساکت ۹۰+ روز', 'hesabix-install-stats' ); ?></option>
		</select>
		<?php submit_button( __( 'فیلتر', 'hesabix-install-stats' ), 'secondary', '', false ); ?>
		<a class="button" href="<?php echo esc_url( wp_nonce_url( admin_url( 'admin.php?his_export=domains_csv' ), 'his_export_domains_csv' ) ); ?>">
			<?php esc_html_e( 'خروجی CSV دامنه‌ها', 'hesabix-install-stats' ); ?>
		</a>
	</form>

	<table class="wp-list-table widefat striped his-domains-table">
		<thead>
			<tr>
				<th><?php esc_html_e( 'دامنه', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'نقش', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'SSL', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'دامنه جفت', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'IP', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'آخرین بازدید', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'نمونه', 'hesabix-install-stats' ); ?></th>
			</tr>
		</thead>
		<tbody>
			<?php if ( ! $items ) : ?>
				<tr><td colspan="7"><?php esc_html_e( 'دامنه‌ای ثبت نشده است.', 'hesabix-install-stats' ); ?></td></tr>
			<?php else : ?>
				<?php foreach ( $items as $row ) : ?>
					<?php
					$detail = add_query_arg(
						array(
							'page'       => 'hesabix-install-stats-instances',
							'install_id' => $row['install_id'],
						),
						admin_url( 'admin.php' )
					);
					$scheme = ! empty( $row['ssl'] ) ? 'https' : 'http';
					$url    = $scheme . '://' . $row['domain'] . '/';
					$role_label = ( $row['role'] === 'api' )
						? __( 'API', 'hesabix-install-stats' )
						: __( 'UI', 'hesabix-install-stats' );
					$ip = $row['remote_ip'] ?: ( $row['reported_ip'] ?: '—' );
					?>
					<tr>
						<td>
							<strong class="his-mono"><?php echo esc_html( $row['domain'] ); ?></strong>
							<div class="his-domain-actions">
								<a href="<?php echo esc_url( $url ); ?>" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'باز کردن', 'hesabix-install-stats' ); ?></a>
							</div>
						</td>
						<td>
							<span class="his-role his-role--<?php echo esc_attr( $row['role'] ); ?>"><?php echo esc_html( $role_label ); ?></span>
						</td>
						<td><?php echo ! empty( $row['ssl'] ) ? esc_html__( 'بله', 'hesabix-install-stats' ) : esc_html__( 'خیر', 'hesabix-install-stats' ); ?></td>
						<td class="his-mono"><?php echo esc_html( $row['pair_domain'] ?: '—' ); ?></td>
						<td class="his-mono"><?php echo esc_html( $ip ); ?></td>
						<td><?php echo esc_html( $row['last_seen'] ); ?> UTC</td>
						<td>
							<a href="<?php echo esc_url( $detail ); ?>" class="his-mono"><?php echo esc_html( substr( (string) $row['install_id'], 0, 8 ) ); ?>…</a>
						</td>
					</tr>
				<?php endforeach; ?>
			<?php endif; ?>
		</tbody>
	</table>

	<?php if ( $pages > 1 ) : ?>
		<div class="tablenav">
			<div class="tablenav-pages">
				<?php
				echo wp_kses_post(
					paginate_links(
						array(
							'base'      => add_query_arg(
								array(
									'paged'  => '%#%',
									's'      => $search,
									'role'   => $role,
									'active' => $active,
								),
								$base
							),
							'format'    => '',
							'current'   => $page,
							'total'     => $pages,
							'prev_text' => '&laquo;',
							'next_text' => '&raquo;',
						)
					)
				);
				?>
			</div>
		</div>
	<?php endif; ?>
</div>
