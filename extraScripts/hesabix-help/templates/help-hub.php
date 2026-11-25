<?php
/**
 * Hub — راهنمای جامع.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

$sections = Hhelp_Tree::top_sections();
$featured = Hhelp_Tree::featured();

get_header();
?>

<main id="main-content" class="hx-help hx-help--hub">
	<section class="hx-help-hero">
		<div class="hx-help-hero__wrap">
			<?php if ( function_exists( 'hesabix2_seo_render_breadcrumb' ) ) : ?>
				<div class="hx-help-breadcrumb-wrap"><?php hesabix2_seo_render_breadcrumb( 'hesabix2-breadcrumb hesabix2-breadcrumb--on-dark' ); ?></div>
			<?php endif; ?>
			<p class="hx-help-hero__eyebrow"><?php esc_html_e( 'منابع', 'hesabix-help' ); ?></p>
			<h1 class="hx-help-hero__title"><?php esc_html_e( 'راهنمای جامع حسابیکس', 'hesabix-help' ); ?></h1>
			<p class="hx-help-hero__lead">
				<?php esc_html_e( 'قدم‌به‌قدم با بخش‌های آرک آشنا شوید؛ از شروع کار تا فاکتور، انبار و CRM — متن، ویدئو، رایگان و اختصاصی.', 'hesabix-help' ); ?>
			</p>
			<form class="hx-help-hero-search" action="<?php echo esc_url( hhelp_search_url() ); ?>" method="get" role="search">
				<label class="screen-reader-text" for="hx-help-hero-q"><?php esc_html_e( 'جستجو در راهنما', 'hesabix-help' ); ?></label>
				<input type="search" id="hx-help-hero-q" name="q" class="hx-help-hero-search__input" placeholder="<?php esc_attr_e( 'چه چیزی را می‌خواهید یاد بگیرید؟', 'hesabix-help' ); ?>" autocomplete="off" data-hhelp-live-search />
				<button type="submit" class="hx-help-hero-search__btn"><?php esc_html_e( 'جستجو', 'hesabix-help' ); ?></button>
			</form>
		</div>
	</section>

	<div class="hx-help-body">
		<div class="hx-help-layout">
			<?php Hhelp_Templates::partial( 'sidebar', array( 'current_id' => 0 ) ); ?>

			<div class="hx-help-main">
				<?php if ( ! empty( $featured ) ) : ?>
				<section class="hx-help-featured" aria-labelledby="hx-help-featured-title">
					<h2 id="hx-help-featured-title" class="hx-help-section-title"><?php esc_html_e( 'مسیر شروع کار', 'hesabix-help' ); ?></h2>
					<p class="hx-help-section-lead"><?php esc_html_e( 'همین شش درس را به‌ترتیب بخوانید تا از ثبت‌نام تا صدور اولین فاکتور جلو بروید.', 'hesabix-help' ); ?></p>
					<ul class="hx-help-featured__grid">
						<?php foreach ( array_slice( $featured, 0, 6 ) as $step => $card ) : ?>
						<li>
							<a href="<?php echo esc_url( $card['url'] ); ?>" class="hx-help-card">
								<span class="hx-help-card__top">
									<span class="hx-help-card__step"><?php echo esc_html( hhelp_fa_num( (int) $step + 1 ) ); ?></span>
									<?php Hhelp_Templates::partial( 'badge', array( 'access' => $card['access'] ) ); ?>
								</span>
								<span class="hx-help-card__label"><?php echo esc_html( $card['title'] ); ?></span>
								<span class="hx-help-card__desc"><?php echo esc_html( $card['excerpt'] ); ?></span>
								<span class="hx-help-card__arrow" aria-hidden="true">←</span>
							</a>
						</li>
						<?php endforeach; ?>
					</ul>
				</section>
				<?php endif; ?>

				<section class="hx-help-catalog" aria-labelledby="hx-help-catalog-title">
					<h2 id="hx-help-catalog-title" class="hx-help-section-title"><?php esc_html_e( 'سرفصل‌های آموزشی', 'hesabix-help' ); ?></h2>
					<p class="hx-help-section-lead"><?php esc_html_e( 'مرتب‌شده به ترتیب یادگیری در حسابیکس آرک؛ از راه‌اندازی تا حسابداری، مالیات و افزونه‌ها.', 'hesabix-help' ); ?></p>
					<?php if ( empty( $sections ) ) : ?>
						<p class="hx-help-muted"><?php esc_html_e( 'هنوز مطلبی منتشر نشده است.', 'hesabix-help' ); ?></p>
					<?php else : ?>
						<ol class="hx-help-catalog__grid">
							<?php foreach ( $sections as $i => $sec ) : ?>
							<li>
								<a href="<?php echo esc_url( $sec['url'] ); ?>" class="hx-help-cat">
									<span class="hx-help-cat__num" aria-hidden="true"><?php echo esc_html( hhelp_fa_num( (int) $i + 1 ) ); ?></span>
									<span class="hx-help-cat__body">
										<span class="hx-help-cat__title"><?php echo esc_html( $sec['title'] ); ?></span>
										<span class="hx-help-cat__meta">
											<?php
											$count = count( $sec['children'] );
											echo esc_html(
												sprintf(
													/* translators: %d: lesson count */
													_n( '%d مطلب', '%d مطلب', $count, 'hesabix-help' ),
													$count
												)
											);
											?>
										</span>
										<span class="hx-help-cat__desc"><?php echo esc_html( $sec['excerpt'] ); ?></span>
									</span>
								</a>
							</li>
							<?php endforeach; ?>
						</ol>
					<?php endif; ?>
				</section>
			</div>
		</div>
	</div>
</main>

<?php
get_footer();
