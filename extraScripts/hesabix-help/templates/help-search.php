<?php
/**
 * Help search results.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

$q = isset( $_GET['q'] ) ? sanitize_text_field( wp_unslash( $_GET['q'] ) ) : ''; // phpcs:ignore WordPress.Security.NonceVerification.Recommended

$results = array();
if ( '' !== $q ) {
	$results = get_posts(
		array(
			'post_type'      => HHELP_CPT,
			'post_status'    => 'publish',
			's'              => $q,
			'posts_per_page' => 30,
			'orderby'        => 'relevance',
		)
	);
}

get_header();
?>

<main id="main-content" class="hx-help hx-help--search">
	<section class="hx-help-hero hx-help-hero--compact">
		<div class="hx-help-hero__wrap">
			<?php if ( function_exists( 'hesabix2_seo_render_breadcrumb' ) ) : ?>
				<div class="hx-help-breadcrumb-wrap"><?php hesabix2_seo_render_breadcrumb( 'hesabix2-breadcrumb hesabix2-breadcrumb--on-dark' ); ?></div>
			<?php endif; ?>
			<h1 class="hx-help-hero__title"><?php esc_html_e( 'جستجو در راهنما', 'hesabix-help' ); ?></h1>
			<form class="hx-help-hero-search" action="<?php echo esc_url( hhelp_search_url() ); ?>" method="get" role="search">
				<label class="screen-reader-text" for="hx-help-search-q"><?php esc_html_e( 'جستجو', 'hesabix-help' ); ?></label>
				<input type="search" id="hx-help-search-q" name="q" class="hx-help-hero-search__input" value="<?php echo esc_attr( $q ); ?>" placeholder="<?php esc_attr_e( 'عبارت جستجو…', 'hesabix-help' ); ?>" />
				<button type="submit" class="hx-help-hero-search__btn"><?php esc_html_e( 'جستجو', 'hesabix-help' ); ?></button>
			</form>
		</div>
	</section>

	<div class="hx-help-body">
		<div class="hx-help-layout">
			<?php Hhelp_Templates::partial( 'sidebar', array( 'current_id' => 0 ) ); ?>
			<div class="hx-help-main">
				<?php if ( '' === $q ) : ?>
					<p class="hx-help-muted"><?php esc_html_e( 'عبارتی برای جستجو وارد کنید.', 'hesabix-help' ); ?></p>
				<?php elseif ( empty( $results ) ) : ?>
					<p class="hx-help-muted"><?php esc_html_e( 'نتیجه‌ای یافت نشد.', 'hesabix-help' ); ?></p>
				<?php else : ?>
					<p class="hx-help-results-count">
						<?php
						echo esc_html(
							sprintf(
								/* translators: %d: count */
								_n( '%d نتیجه', '%d نتیجه', count( $results ), 'hesabix-help' ),
								count( $results )
							)
						);
						?>
					</p>
					<ul class="hx-help-search-results">
						<?php foreach ( $results as $hit ) : ?>
						<li class="hx-help-search-hit">
							<a href="<?php echo esc_url( get_permalink( $hit ) ); ?>">
								<span class="hx-help-search-hit__title"><?php echo esc_html( get_the_title( $hit ) ); ?></span>
								<span class="hx-help-search-hit__excerpt"><?php echo esc_html( wp_trim_words( $hit->post_excerpt ?: wp_strip_all_tags( $hit->post_content ), 28 ) ); ?></span>
								<?php Hhelp_Templates::partial( 'badge', array( 'access' => hhelp_get_access( $hit->ID ) ) ); ?>
							</a>
						</li>
						<?php endforeach; ?>
					</ul>
				<?php endif; ?>
			</div>
		</div>
	</div>
</main>

<?php
get_footer();
