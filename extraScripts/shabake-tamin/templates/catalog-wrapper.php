<?php
/**
 * پوستهٔ HTML کاتالوگ (قابل override در قالب: shabake-tamin/catalog-wrapper.php).
 *
 * @package Shabake_Tamin
 *
 * @var array<string, mixed> $st_config پیکربندی نمونه.
 */

defined( 'ABSPATH' ) || exit;

$cfg = isset( $st_config ) && is_array( $st_config ) ? $st_config : array();
$cfg = wp_parse_args(
	$cfg,
	array(
		'businessId'            => null,
		'categoryId'            => null,
		'province'              => null,
		'city'                  => null,
		'locationFilters'       => false,
		'provinceSuggestions'   => false,
		'showProductDetails'    => true,
		'columns'               => 4,
		'search'                => true,
		'take'                  => 20,
		'pageLayout'            => false,
	)
);

$uid = 'st-' . preg_replace( '/[^a-zA-Z0-9_-]/', '', uniqid( '', true ) );

$json_flags = JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT;
$json       = wp_json_encode( $cfg, $json_flags );
if ( false === $json ) {
	$json = '{}';
}

$cols                    = (int) $cfg['columns'];
$page_layout             = ! empty( $cfg['pageLayout'] );
$show_search             = ! empty( $cfg['search'] );
$show_loc_ui             = ! empty( $cfg['locationFilters'] );
$show_toolbar            = $show_search || $show_loc_ui;
$prov_val                = isset( $cfg['province'] ) && is_string( $cfg['province'] ) ? $cfg['province'] : '';
$city_val                = isset( $cfg['city'] ) && is_string( $cfg['city'] ) ? $cfg['city'] : '';
$provinces_list_id       = $uid . '-provinces';
$show_province_datalist  = $show_loc_ui && ! empty( $cfg['provinceSuggestions'] );
?>
<div class="st-catalog-root<?php echo $page_layout ? ' st-page-layout' : ''; ?>" id="<?php echo esc_attr( $uid ); ?>" data-st-root="1" style="--st-columns: <?php echo esc_attr( (string) $cols ); ?>;">
	<script type="application/json" class="st-json-config"><?php echo $json; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?></script>
	<?php if ( $show_toolbar ) : ?>
		<div class="st-toolbar-stack">
			<?php if ( $show_search ) : ?>
				<div class="st-toolbar">
					<label class="st-sr-only" for="<?php echo esc_attr( $uid ); ?>-q"><?php esc_html_e( 'جستجو', 'shabake-tamin' ); ?></label>
					<input type="search" class="st-search-input" id="<?php echo esc_attr( $uid ); ?>-q" autocomplete="off" placeholder="" />
					<button type="button" class="st-search-btn button"><?php esc_html_e( 'جستجو', 'shabake-tamin' ); ?></button>
				</div>
			<?php endif; ?>
			<?php if ( $show_loc_ui ) : ?>
				<div class="st-toolbar st-toolbar--filters">
					<div class="st-filter-fields">
						<label class="st-filter-label">
							<span class="st-filter-label-text"><?php esc_html_e( 'استان', 'shabake-tamin' ); ?></span>
							<input type="text" class="st-filter-province" maxlength="100" value="<?php echo esc_attr( $prov_val ); ?>" autocomplete="address-level1"<?php echo $show_province_datalist ? ' list="' . esc_attr( $provinces_list_id ) . '"' : ''; ?> />
						</label>
						<label class="st-filter-label">
							<span class="st-filter-label-text"><?php esc_html_e( 'شهر', 'shabake-tamin' ); ?></span>
							<input type="text" class="st-filter-city" maxlength="100" value="<?php echo esc_attr( $city_val ); ?>" autocomplete="address-level2" />
						</label>
					</div>
					<button type="button" class="st-filter-apply button"><?php esc_html_e( 'اعمال فیلتر مکان', 'shabake-tamin' ); ?></button>
					<?php if ( $show_province_datalist ) : ?>
						<?php require_once ST_PLUGIN_DIR . 'includes/iran-provinces-list.php'; ?>
						<datalist id="<?php echo esc_attr( $provinces_list_id ); ?>">
							<?php foreach ( shabake_tamin_get_iran_provinces() as $st_province_name ) : ?>
								<option value="<?php echo esc_attr( $st_province_name ); ?>"></option>
							<?php endforeach; ?>
						</datalist>
					<?php endif; ?>
				</div>
			<?php endif; ?>
		</div>
	<?php endif; ?>
	<?php if ( $page_layout ) : ?>
		<div class="st-pub-meta" aria-live="polite">
			<span class="st-pub-result-stats"></span>
		</div>
	<?php endif; ?>
	<div class="st-catalog-status" hidden></div>
	<div class="st-grid" aria-live="polite"></div>
	<div class="st-loadmore-wrap">
		<button type="button" class="st-loadmore button" hidden><?php esc_html_e( 'بارگذاری بیشتر', 'shabake-tamin' ); ?></button>
	</div>
</div>
