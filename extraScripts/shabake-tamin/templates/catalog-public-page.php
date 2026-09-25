<?php
/**
 * قالب صفحهٔ عمومی کاتالوگ (rewrite) — قابل override: shabake-tamin/catalog-public-page.php
 *
 * @package Shabake_Tamin
 */

defined( 'ABSPATH' ) || exit;

$config = apply_filters( 'shabake_tamin_public_catalog_config', Shabake_Tamin_Public_Catalog::default_page_config() );

$title = (string) get_option( 'st_public_catalog_title', '' );
$title = trim( $title );
if ( '' === $title ) {
	$title = get_bloginfo( 'name', 'display' );
}

get_header();
?>
<main class="site-main st-public-page st-public-catalog-main" id="st-public-catalog-main">
	<header class="st-public-hero" role="banner">
		<div class="st-public-hero__inner">
			<h1 class="st-public-hero__title"><?php echo esc_html( $title ); ?></h1>
			<p class="st-public-hero__tagline">
				<?php esc_html_e( 'جستجو در کالاهای عمومی، مقایسهٔ قیمت و اطلاعات تأمین‌کنندگان؛ داده از Hesabix.', 'shabake-tamin' ); ?>
			</p>
			<p class="st-public-hero__contact-hint">
				<?php esc_html_e( 'برای تماس مستقیم با تأمین‌کننده، اطلاعات تماس هر کالا را در کارت محصول یا بخش جزئیات ببینید.', 'shabake-tamin' ); ?>
			</p>
		</div>
	</header>
	<div class="st-public-page__body">
		<?php
		// phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped
		echo Shabake_Tamin_Catalog::render_html( $config, 'public_page', null );
		?>
	</div>
</main>
<?php
get_footer();
