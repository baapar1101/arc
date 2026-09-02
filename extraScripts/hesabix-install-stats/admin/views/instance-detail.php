<?php
/**
 * جزئیات یک نمونه.
 *
 * @package Hesabix_Install_Stats
 *
 * @var array|null $instance
 * @var array      $events
 * @var string     $install_id
 */

defined( 'ABSPATH' ) || exit;

$back = admin_url( 'admin.php?page=hesabix-install-stats-instances' );
?>
<div class="wrap his-wrap">
	<p><a href="<?php echo esc_url( $back ); ?>">&larr; <?php esc_html_e( 'بازگشت به لیست', 'hesabix-install-stats' ); ?></a></p>

	<?php if ( ! $instance ) : ?>
		<h1><?php esc_html_e( 'نمونه یافت نشد', 'hesabix-install-stats' ); ?></h1>
	<?php else : ?>
		<h1><?php echo esc_html( $instance['api_domain'] ?: $instance['ui_domain'] ?: $install_id ); ?></h1>
		<p class="his-mono his-muted"><?php echo esc_html( $instance['install_id'] ); ?></p>

		<div class="his-grid-2">
			<div class="his-panel">
				<h2><?php esc_html_e( 'وضعیت فعلی', 'hesabix-install-stats' ); ?></h2>
				<table class="his-table">
					<?php
					$fields = array(
						'api_domain'      => 'API domain',
						'ui_domain'       => 'UI domain',
						'remote_ip'       => 'Remote IP',
						'reported_ip'     => 'Reported IP',
						'ram_mb'          => 'RAM (MB)',
						'cpu_cores'       => 'CPU cores',
						'disk_free_gb'    => 'Disk free (GB)',
						'arch'            => 'Arch',
						'os_id'           => 'OS',
						'os_version'      => 'OS version',
						'branch'          => 'Branch',
						'git_commit'      => 'Commit',
						'app_version'     => 'App version',
						'uvicorn_workers' => 'Workers',
						'ssl_api'         => 'SSL API',
						'ssl_ui'          => 'SSL UI',
						'install_pgadmin' => 'pgAdmin',
						'install_voice'   => 'Voice',
						'pip_mirror'      => 'pip mirror',
						'flutter_mirror'  => 'Flutter mirror',
						'first_seen'      => 'First seen (UTC)',
						'last_seen'       => 'Last seen (UTC)',
						'last_event'      => 'Last event',
						'event_count'     => 'Event count',
					);
					foreach ( $fields as $key => $label ) :
						$val = isset( $instance[ $key ] ) ? $instance[ $key ] : '';
						?>
						<tr>
							<th><?php echo esc_html( $label ); ?></th>
							<td class="his-mono"><?php echo esc_html( (string) $val ); ?></td>
						</tr>
					<?php endforeach; ?>
				</table>
			</div>

			<div class="his-panel">
				<h2><?php esc_html_e( 'تاریخچه رویدادها', 'hesabix-install-stats' ); ?></h2>
				<?php if ( ! $events ) : ?>
					<p class="his-muted"><?php esc_html_e( 'رویدادی نیست.', 'hesabix-install-stats' ); ?></p>
				<?php else : ?>
					<table class="his-table">
						<thead>
							<tr>
								<th><?php esc_html_e( 'زمان (UTC)', 'hesabix-install-stats' ); ?></th>
								<th><?php esc_html_e( 'رویداد', 'hesabix-install-stats' ); ?></th>
								<th><?php esc_html_e( 'IP', 'hesabix-install-stats' ); ?></th>
							</tr>
						</thead>
						<tbody>
							<?php foreach ( $events as $ev ) : ?>
								<tr>
									<td><?php echo esc_html( $ev['created_at'] ); ?></td>
									<td><?php echo esc_html( $ev['event'] ); ?></td>
									<td class="his-mono"><?php echo esc_html( $ev['remote_ip'] ); ?></td>
								</tr>
							<?php endforeach; ?>
						</tbody>
					</table>
				<?php endif; ?>
			</div>
		</div>
	<?php endif; ?>
</div>
