<?php
/**
 * Single help lesson / section.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

the_post();
$post_id   = get_the_ID();
$access    = hhelp_get_access( $post_id );
$can_view  = hhelp_user_can_view( $post_id );
$children  = Hhelp_Tree::children( $post_id );
$is_section = ! empty( $children );
$video     = Hhelp_Meta::get_video( $post_id );
$adjacent  = Hhelp_Tree::adjacent( get_post() );
$product_id = (int) get_post_meta( $post_id, '_hhelp_product_id', true );

$content_html = '';
$toc_items    = array();
if ( $can_view && ! $is_section ) {
	$raw = apply_filters( 'the_content', get_post()->post_content );
	$toc = Hhelp_TOC::process( $raw );
	$content_html = $toc['html'];
	$toc_items    = $toc['items'];
} elseif ( $is_section ) {
	$content_html = apply_filters( 'the_content', get_post()->post_content );
}

get_header();
?>

<main id="main-content" class="hx-help hx-help--single">
	<section class="hx-help-article-hero">
		<div class="hx-help-article-hero__wrap">
			<?php if ( function_exists( 'hesabix2_seo_render_breadcrumb' ) ) : ?>
				<div class="hx-help-breadcrumb-wrap"><?php hesabix2_seo_render_breadcrumb( 'hesabix2-breadcrumb' ); ?></div>
			<?php endif; ?>
			<div class="hx-help-article-hero__meta">
				<?php Hhelp_Templates::partial( 'badge', array( 'access' => $access ) ); ?>
				<?php if ( ! empty( $video['duration'] ) ) : ?>
					<span class="hx-help-meta-chip"><?php echo esc_html( $video['duration'] ); ?></span>
				<?php endif; ?>
				<?php if ( ! empty( $video['type'] ) && 'none' !== $video['type'] ) : ?>
					<span class="hx-help-meta-chip hx-help-meta-chip--video"><?php esc_html_e( 'ویدئو', 'hesabix-help' ); ?></span>
				<?php endif; ?>
			</div>
			<h1 class="hx-help-article-hero__title"><?php the_title(); ?></h1>
			<?php if ( has_excerpt() ) : ?>
				<p class="hx-help-article-hero__lead"><?php echo esc_html( get_the_excerpt() ); ?></p>
			<?php endif; ?>
		</div>
	</section>

	<div class="hx-help-body">
		<div class="hx-help-layout">
			<?php Hhelp_Templates::partial( 'sidebar', array( 'current_id' => $post_id ) ); ?>

			<article class="hx-help-main hx-help-article" itemscope itemtype="https://schema.org/TechArticle">
				<button type="button" class="hx-help-mobile-toc-btn" data-hhelp-open-nav>
					<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" aria-hidden="true"><path stroke-linecap="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h10"/></svg>
					<?php esc_html_e( 'فهرست راهنما', 'hesabix-help' ); ?>
				</button>

				<?php if ( $is_section ) : ?>
					<div class="hx-help-content entry-content">
						<?php echo $content_html; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
					</div>
					<ol class="hx-help-child-list">
						<?php foreach ( $children as $i => $child ) : ?>
							<li>
								<a href="<?php echo esc_url( get_permalink( $child ) ); ?>" class="hx-help-child-link">
									<span class="hx-help-child-link__num"><?php echo esc_html( hhelp_fa_num( (int) $i + 1 ) ); ?></span>
									<span class="hx-help-child-link__title"><?php echo esc_html( get_the_title( $child ) ); ?></span>
									<?php Hhelp_Templates::partial( 'badge', array( 'access' => hhelp_get_access( $child->ID ) ) ); ?>
									<span class="hx-help-child-link__arrow" aria-hidden="true">←</span>
								</a>
							</li>
						<?php endforeach; ?>
					</ol>
				<?php else : ?>
					<?php
					Hhelp_Templates::partial(
						'video',
						array(
							'video'    => $video,
							'can_view' => $can_view,
							'post_id'  => $post_id,
						)
					);
					?>

					<?php if ( ! $can_view ) : ?>
						<div class="hx-help-preview">
							<?php echo Hhelp_Access::preview_html( get_post() ); // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
						</div>
						<?php
						Hhelp_Templates::partial(
							'lock',
							array(
								'access'     => $access,
								'product_id' => $product_id,
								'post_id'    => $post_id,
							)
						);
						?>
					<?php else : ?>
						<?php if ( ! empty( $toc_items ) ) : ?>
						<nav class="hx-help-toc" aria-label="<?php esc_attr_e( 'فهرست مطالب', 'hesabix-help' ); ?>">
							<h2 class="hx-help-toc__title"><?php esc_html_e( 'در این صفحه', 'hesabix-help' ); ?></h2>
							<ol class="hx-help-toc__list">
								<?php foreach ( $toc_items as $item ) : ?>
								<li class="hx-help-toc__item hx-help-toc__item--l<?php echo (int) $item['level']; ?>">
									<a href="#<?php echo esc_attr( $item['id'] ); ?>"><?php echo esc_html( $item['text'] ); ?></a>
								</li>
								<?php endforeach; ?>
							</ol>
						</nav>
						<?php endif; ?>

						<div class="hx-help-content entry-content" itemprop="articleBody">
							<?php echo $content_html; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
						</div>
					<?php endif; ?>
				<?php endif; ?>

				<?php
				Hhelp_Templates::partial(
					'nav-adjacent',
					array(
						'prev' => $adjacent['prev'],
						'next' => $adjacent['next'],
					)
				);
				?>
			</article>
		</div>
	</div>
</main>

<?php
get_footer();
