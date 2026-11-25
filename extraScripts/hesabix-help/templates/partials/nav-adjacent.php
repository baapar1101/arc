<?php
/**
 * Prev / next navigation.
 *
 * @package Hesabix_Help
 * @var WP_Post|null $prev
 * @var WP_Post|null $next
 */

defined( 'ABSPATH' ) || exit;

if ( empty( $prev ) && empty( $next ) ) {
	return;
}
?>
<nav class="hx-help-adjacent" aria-label="<?php esc_attr_e( 'مطلب قبلی و بعدی', 'hesabix-help' ); ?>">
	<?php if ( ! empty( $prev ) ) : ?>
		<a class="hx-help-adjacent__link hx-help-adjacent__link--prev" href="<?php echo esc_url( get_permalink( $prev ) ); ?>">
			<span class="hx-help-adjacent__dir"><?php esc_html_e( 'قبلی', 'hesabix-help' ); ?></span>
			<span class="hx-help-adjacent__title"><?php echo esc_html( get_the_title( $prev ) ); ?></span>
		</a>
	<?php else : ?>
		<span class="hx-help-adjacent__link is-empty"></span>
	<?php endif; ?>

	<?php if ( ! empty( $next ) ) : ?>
		<a class="hx-help-adjacent__link hx-help-adjacent__link--next" href="<?php echo esc_url( get_permalink( $next ) ); ?>">
			<span class="hx-help-adjacent__dir"><?php esc_html_e( 'بعدی', 'hesabix-help' ); ?></span>
			<span class="hx-help-adjacent__title"><?php echo esc_html( get_the_title( $next ) ); ?></span>
		</a>
	<?php else : ?>
		<span class="hx-help-adjacent__link is-empty"></span>
	<?php endif; ?>
</nav>
