<?php
/**
 * Tree sidebar.
 *
 * @package Hesabix_Help
 * @var int $current_id
 */

defined( 'ABSPATH' ) || exit;

$current_id = isset( $current_id ) ? (int) $current_id : 0;
$tree       = Hhelp_Tree::get_tree();
$path_ids   = $current_id ? Hhelp_Tree::active_path_ids( $current_id ) : array();

/**
 * Render tree recursively.
 *
 * @param array<int, array<string, mixed>> $nodes   Nodes.
 * @param array<int, int>                  $path    Active path.
 * @param int                              $current Current ID.
 * @param int                              $depth   Depth.
 */
function hhelp_render_tree_nodes( $nodes, $path, $current, $depth = 0 ) {
	if ( empty( $nodes ) ) {
		return;
	}
	echo '<ul class="hx-help-tree__list hx-help-tree__list--d' . (int) $depth . '">';
	foreach ( $nodes as $i => $node ) {
		$id         = (int) $node['id'];
		$is_current = $id === $current;
		$in_path    = in_array( $id, $path, true );
		$has_kids   = ! empty( $node['children'] );
		$open       = $has_kids && ( $in_path || ( 0 === $current && 0 === $depth && 0 === (int) $i ) );
		$classes    = array( 'hx-help-tree__item' );
		if ( $is_current ) {
			$classes[] = 'is-current';
		}
		if ( $in_path ) {
			$classes[] = 'is-path';
		}
		if ( $has_kids ) {
			$classes[] = 'has-children';
		}
		if ( $open ) {
			$classes[] = 'is-open';
		}
		echo '<li class="' . esc_attr( implode( ' ', $classes ) ) . '" data-id="' . esc_attr( (string) $id ) . '">';
		echo '<div class="hx-help-tree__row">';
		if ( $has_kids ) {
			echo '<button type="button" class="hx-help-tree__toggle" aria-expanded="' . ( $open ? 'true' : 'false' ) . '" aria-label="' . esc_attr__( 'باز و بسته کردن', 'hesabix-help' ) . '"><span aria-hidden="true"></span></button>';
		} else {
			echo '<span class="hx-help-tree__spacer" aria-hidden="true"></span>';
		}
		echo '<a class="hx-help-tree__link" href="' . esc_url( $node['url'] ) . '"' . ( $is_current ? ' aria-current="page"' : '' ) . '>';
		$num_class = 0 === $depth ? 'hx-help-tree__num' : 'hx-help-tree__lesson-num';
		echo '<span class="' . esc_attr( $num_class ) . '">' . esc_html( hhelp_fa_num( (int) $i + 1 ) ) . '</span>';
		echo '<span class="hx-help-tree__label">' . esc_html( $node['title'] ) . '</span>';
		if ( 'free' !== $node['access'] ) {
			echo '<span class="hx-help-tree__access hx-help-tree__access--' . esc_attr( $node['access'] ) . '" title="' . esc_attr( hhelp_access_label( $node['access'] ) ) . '"></span>';
		}
		echo '</a></div>';
		if ( $has_kids ) {
			echo '<div class="hx-help-tree__children"' . ( $open ? '' : ' hidden' ) . '>';
			hhelp_render_tree_nodes( $node['children'], $path, $current, $depth + 1 );
			echo '</div>';
		}
		echo '</li>';
	}
	echo '</ul>';
}
?>
<aside class="hx-help-sidebar" aria-label="<?php esc_attr_e( 'فهرست راهنما', 'hesabix-help' ); ?>" data-hhelp-sidebar>
	<div class="hx-help-sidebar__backdrop" data-hhelp-close-nav hidden></div>
	<div class="hx-help-sidebar__inner">
		<div class="hx-help-sidebar__head">
			<span class="hx-help-sidebar__title"><?php esc_html_e( 'فهرست راهنما', 'hesabix-help' ); ?></span>
			<button type="button" class="hx-help-sidebar__close" data-hhelp-close-nav aria-label="<?php esc_attr_e( 'بستن', 'hesabix-help' ); ?>">×</button>
		</div>

		<div class="hx-help-sidebar__search">
			<form class="hx-help-search-form" action="<?php echo esc_url( hhelp_search_url() ); ?>" method="get" role="search">
				<label class="screen-reader-text" for="hx-help-sidebar-q"><?php esc_html_e( 'جستجو', 'hesabix-help' ); ?></label>
				<input type="search" id="hx-help-sidebar-q" name="q" class="hx-help-search-form__input" placeholder="<?php esc_attr_e( 'جستجو…', 'hesabix-help' ); ?>" autocomplete="off" data-hhelp-live-search />
				<button type="submit" class="hx-help-search-form__btn" aria-label="<?php esc_attr_e( 'جستجو', 'hesabix-help' ); ?>">
					<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
				</button>
			</form>
			<div class="hx-help-live-results" data-hhelp-live-results hidden></div>
		</div>

		<nav class="hx-help-tree" data-hhelp-tree>
			<?php hhelp_render_tree_nodes( $tree, $path_ids, $current_id ); ?>
		</nav>

		<p class="hx-help-sidebar__wiki">
			<a href="<?php echo esc_url( function_exists( 'hwiki_hub_url' ) ? hwiki_hub_url() : home_url( '/docs/' ) ); ?>">
				<?php esc_html_e( 'دانشنامه فنی', 'hesabix-help' ); ?>
				<span aria-hidden="true">↗</span>
			</a>
		</p>
	</div>
</aside>
