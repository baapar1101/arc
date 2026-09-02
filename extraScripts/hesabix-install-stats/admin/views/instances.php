<?php
/**
 * لیست نمونه‌ها.
 *
 * @package Hesabix_Install_Stats
 *
 * @var array  $result
 * @var int    $page
 * @var string $search
 * @var string $active
 */

defined( 'ABSPATH' ) || exit;

$items = $result['items'];
$total = (int) $result['total'];
$pages = max( 1, (int) ceil( $total / 25 ) );
$base  = admin_url( 'admin.php?page=hesabix-install-stats-instances' );
?>
<div class="wrap his-wrap">
	<h1><?php esc_html_e( 'نمونه‌های نصب‌شده', 'hesabix-install-stats' ); ?></h1>

	<form method="get" class="his-filters">
		<input type="hidden" name="page" value="hesabix-install-stats-instances" />
		<input type="search" name="s" value="<?php echo esc_attr( $search ); ?>" placeholder="<?php esc_attr_e( 'جستجو: دامنه، IP، install_id…', 'hesabix-install-stats' ); ?>" class="regular-text" />
		<select name="active">
			<option value=""><?php esc_html_e( 'همه', 'hesabix-install-stats' ); ?></option>
			<option value="7" <?php selected( $active, '7' ); ?>><?php esc_html_e( 'فعال ۷ روز', 'hesabix-install-stats' ); ?></option>
			<option value="30" <?php selected( $active, '30' ); ?>><?php esc_html_e( 'فعال ۳۰ روز', 'hesabix-install-stats' ); ?></option>
			<option value="silent90" <?php selected( $active, 'silent90' ); ?>><?php esc_html_e( 'ساکت ۹۰+ روز', 'hesabix-install-stats' ); ?></option>
		</select>
		<?php submit_button( __( 'فیلتر', 'hesabix-install-stats' ), 'secondary', '', false ); ?>
		<a class="button" href="<?php echo esc_url( wp_nonce_url( admin_url( 'admin.php?his_export=csv' ), 'his_export_csv' ) ); ?>"><?php esc_html_e( 'CSV', 'hesabix-install-stats' ); ?></a>
	</form>

	<p class="his-muted"><?php echo esc_html( sprintf( /* translators: %d count */ __( 'تعداد: %d', 'hesabix-install-stats' ), $total ) ); ?></p>

	<table class="wp-list-table widefat striped">
		<thead>
			<tr>
				<th><?php esc_html_e( 'دامنه API', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'دامنه UI', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'IP', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'سخت‌افزار', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'OS', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'آخرین رویداد', 'hesabix-install-stats' ); ?></th>
				<th><?php esc_html_e( 'آخرین بازدید', 'hesabix-install-stats' ); ?></th>
			</tr>
		</thead>
		<tbody>
			<?php if ( ! $items ) : ?>
				<tr><td colspan="7"><?php esc_html_e( 'موردی یافت نشد.', 'hesabix-install-stats' ); ?></td></tr>
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
					$hw = trim( ( (int) $row['ram_mb'] ? round( (int) $row['ram_mb'] / 1024, 1 ) . ' GB' : '—' ) . ' / ' . ( (int) $row['cpu_cores'] ? ( (int) $row['cpu_cores'] . ' CPU' ) : '—' ) );
					?>
					<tr>
						<td>
							<a href="<?php echo esc_url( $detail ); ?>"><strong><?php echo esc_html( $row['api_domain'] ?: '—' ); ?></strong></a>
							<div class="his-mono his-muted"><?php echo esc_html( substr( (string) $row['install_id'], 0, 8 ) ); ?>…</div>
						</td>
						<td><?php echo esc_html( $row['ui_domain'] ?: '—' ); ?></td>
						<td class="his-mono"><?php echo esc_html( $row['remote_ip'] ?: '—' ); ?></td>
						<td><?php echo esc_html( $hw ); ?></td>
						<td><?php echo esc_html( trim( $row['os_id'] . ' ' . $row['os_version'] ) ?: '—' ); ?></td>
						<td><?php echo esc_html( $row['last_event'] ); ?> <span class="his-muted">(<?php echo esc_html( (string) (int) $row['event_count'] ); ?>)</span></td>
						<td><?php echo esc_html( $row['last_seen'] ); ?> UTC</td>
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
