<?php
/**
 * Hierarchical tree for sidebar and hub cards.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_Tree
 */
class Hhelp_Tree {

	/**
	 * Full published tree (cached per request).
	 *
	 * @var array<int, array<string, mixed>>|null
	 */
	private static $cache = null;

	/**
	 * @return array<int, array<string, mixed>>
	 */
	public static function get_tree() {
		if ( null !== self::$cache ) {
			return self::$cache;
		}

		$posts = get_posts(
			array(
				'post_type'      => HHELP_CPT,
				'post_status'    => 'publish',
				'posts_per_page' => -1,
				'orderby'        => hhelp_query_order(),
			)
		);

		$by_parent = array();
		foreach ( $posts as $p ) {
			$parent = (int) $p->post_parent;
			if ( ! isset( $by_parent[ $parent ] ) ) {
				$by_parent[ $parent ] = array();
			}
			$by_parent[ $parent ][] = $p;
		}

		self::$cache = self::build_nodes( $by_parent, 0 );
		return self::$cache;
	}

	/**
	 * @param array<int, array<int, WP_Post>> $by_parent Grouped posts.
	 * @param int                             $parent_id Parent ID.
	 * @return array<int, array<string, mixed>>
	 */
	private static function build_nodes( $by_parent, $parent_id ) {
		if ( empty( $by_parent[ $parent_id ] ) ) {
			return array();
		}
		$nodes = array();
		foreach ( $by_parent[ $parent_id ] as $post ) {
			$children = self::build_nodes( $by_parent, (int) $post->ID );
			$nodes[]  = array(
				'id'       => (int) $post->ID,
				'title'    => get_the_title( $post ),
				'url'      => get_permalink( $post ),
				'access'   => hhelp_get_access( $post->ID ),
				'icon'     => (string) get_post_meta( $post->ID, '_hhelp_icon', true ),
				'excerpt'  => $post->post_excerpt ? $post->post_excerpt : wp_trim_words( wp_strip_all_tags( $post->post_content ), 18 ),
				'featured' => (bool) get_post_meta( $post->ID, '_hhelp_featured', true ),
				'has_video'=> 'none' !== (string) get_post_meta( $post->ID, '_hhelp_video_type', true )
					&& (string) get_post_meta( $post->ID, '_hhelp_video_id', true ),
				'children' => $children,
				'is_section' => ! empty( $children ),
			);
		}
		return $nodes;
	}

	/**
	 * Top-level sections for hub.
	 *
	 * @return array<int, array<string, mixed>>
	 */
	public static function top_sections() {
		return self::get_tree();
	}

	/**
	 * Featured cards.
	 *
	 * @return array<int, array<string, mixed>>
	 */
	public static function featured() {
		$out = array();
		self::walk(
			self::get_tree(),
			static function ( $node ) use ( &$out ) {
				if ( ! empty( $node['featured'] ) ) {
					$out[] = $node;
				}
			}
		);
		return $out;
	}

	/**
	 * @param array<int, array<string, mixed>> $nodes Nodes.
	 * @param callable                        $cb    Callback.
	 */
	public static function walk( $nodes, $cb ) {
		foreach ( $nodes as $node ) {
			$cb( $node );
			if ( ! empty( $node['children'] ) ) {
				self::walk( $node['children'], $cb );
			}
		}
	}

	/**
	 * Ancestor IDs including self for expand state.
	 *
	 * @param int $post_id Current post.
	 * @return array<int, int>
	 */
	public static function active_path_ids( $post_id ) {
		$ids   = array( (int) $post_id );
		$anc   = get_post_ancestors( $post_id );
		foreach ( $anc as $a ) {
			$ids[] = (int) $a;
		}
		return $ids;
	}

	/**
	 * Children of a section.
	 *
	 * @param int $parent_id Parent.
	 * @return array<int, WP_Post>
	 */
	public static function children( $parent_id ) {
		return get_posts(
			array(
				'post_type'      => HHELP_CPT,
				'post_parent'    => (int) $parent_id,
				'post_status'    => 'publish',
				'posts_per_page' => -1,
				'orderby'        => hhelp_query_order(),
			)
		);
	}

	/**
	 * Depth-first curriculum list (chapters then lessons).
	 *
	 * @param array<int, array<string, mixed>>|null $nodes Nodes.
	 * @return array<int, array<string, mixed>>
	 */
	public static function flatten( $nodes = null ) {
		if ( null === $nodes ) {
			$nodes = self::get_tree();
		}
		$out = array();
		foreach ( $nodes as $node ) {
			$out[] = $node;
			if ( ! empty( $node['children'] ) ) {
				foreach ( self::flatten( $node['children'] ) as $child ) {
					$out[] = $child;
				}
			}
		}
		return $out;
	}

	/**
	 * Prev / next along the full syllabus, not just siblings.
	 *
	 * @param WP_Post $post Current.
	 * @return array{prev:?WP_Post,next:?WP_Post}
	 */
	public static function adjacent( $post ) {
		$prev  = null;
		$next  = null;
		$found = false;
		foreach ( self::flatten() as $node ) {
			$id = (int) $node['id'];
			if ( $found ) {
				$next = get_post( $id );
				break;
			}
			if ( $id === (int) $post->ID ) {
				$found = true;
				continue;
			}
			$prev = get_post( $id );
		}
		return array(
			'prev' => $prev,
			'next' => $next,
		);
	}

	/**
	 * Clear request cache (after seed etc.).
	 */
	public static function flush_cache() {
		self::$cache = null;
	}
}
