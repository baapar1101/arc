<?php
/**
 * Table of contents from heading tags.
 *
 * @package Hesabix_Help
 */

defined( 'ABSPATH' ) || exit;

/**
 * Class Hhelp_TOC
 */
class Hhelp_TOC {

	/**
	 * Inject IDs into headings and return TOC items.
	 *
	 * @param string $html Content HTML.
	 * @return array{html:string,items:array<int, array{id:string,text:string,level:int}>}
	 */
	public static function process( $html ) {
		$items = array();
		if ( '' === trim( (string) $html ) ) {
			return array(
				'html'  => $html,
				'items' => $items,
			);
		}

		if ( ! class_exists( 'DOMDocument' ) ) {
			return array(
				'html'  => $html,
				'items' => $items,
			);
		}

		$dom    = new DOMDocument();
		$wrapped = '<?xml encoding="utf-8"?><div id="hhelp-root">' . $html . '</div>';
		libxml_use_internal_errors( true );
		$dom->loadHTML( $wrapped, LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD );
		libxml_clear_errors();

		$xpath = new DOMXPath( $dom );
		$nodes = $xpath->query( '//h2|//h3' );
		if ( ! $nodes ) {
			return array(
				'html'  => $html,
				'items' => $items,
			);
		}

		$used = array();
		foreach ( $nodes as $node ) {
			/** @var DOMElement $node */
			$text = trim( preg_replace( '/\s+/u', ' ', $node->textContent ) );
			if ( '' === $text ) {
				continue;
			}
			$level = (int) substr( $node->tagName, 1 );
			$id    = $node->getAttribute( 'id' );
			if ( ! $id ) {
				$id = sanitize_title( $text );
				if ( '' === $id ) {
					$id = 'sec-' . ( count( $items ) + 1 );
				}
				$base = $id;
				$i    = 2;
				while ( isset( $used[ $id ] ) ) {
					$id = $base . '-' . $i;
					++$i;
				}
				$node->setAttribute( 'id', $id );
			}
			$used[ $id ] = true;
			$items[]     = array(
				'id'    => $id,
				'text'  => $text,
				'level' => $level,
			);
		}

		$root = $dom->getElementById( 'hhelp-root' );
		$out  = '';
		if ( $root ) {
			foreach ( $root->childNodes as $child ) {
				$out .= $dom->saveHTML( $child );
			}
		}

		return array(
			'html'  => $out ?: $html,
			'items' => $items,
		);
	}
}
