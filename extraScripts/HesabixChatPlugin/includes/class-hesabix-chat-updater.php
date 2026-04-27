<?php
/**
 * به‌روزرسانی: خواندن نسخه از فایل raw در مخزن + بسته zip از archive (آدرس ثابت)
 * — یا اختیاری: مانیفست JSON
 *
 * @package HesabixChat
 */

defined( 'ABSPATH' ) || exit;

class Hesabix_Chat_Updater {

	/** ۱۲ ساعت */
	const CACHE_TTL = 43200;

	/**
	 * کلید کش وابسته به آدرس‌های به‌روزرسانی تا بعد از تغییر wp-config یا فیلتر، نتیجهٔ تازه گرفته شود.
	 *
	 * @return string
	 */
	private function get_update_cache_key() {
		return 'hesabix_chat_upd_' . md5( $this->get_raw_php_url() . '|' . $this->get_archive_zip_url() . '|' . $this->get_manifest_url() );
	}

	/**
	 * @return void
	 */
	public function __construct() {
		add_filter( 'pre_set_site_transient_update_plugins', array( $this, 'filter_update_transient' ) );
		add_filter( 'plugins_api', array( $this, 'plugin_info' ), 10, 3 );
		add_filter( 'upgrader_source_selection', array( $this, 'align_extracted_plugin_folder' ), 10, 4 );
	}

	/**
	 * @return string
	 */
	public function get_raw_php_url() {
		$url = defined( 'HESABIX_CHAT_UPDATE_RAW_PHP_URL' ) ? (string) HESABIX_CHAT_UPDATE_RAW_PHP_URL : '';
		return esc_url_raw( (string) apply_filters( 'hesabix_chat_update_raw_php_url', $url ) );
	}

	/**
	 * @return string
	 */
	public function get_archive_zip_url() {
		$url = defined( 'HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL' ) ? (string) HESABIX_CHAT_UPDATE_ARCHIVE_ZIP_URL : '';
		return esc_url_raw( (string) apply_filters( 'hesabix_chat_update_archive_zip_url', $url ) );
	}

	/**
	 * @return string
	 */
	public function get_manifest_url() {
		$url = defined( 'HESABIX_CHAT_UPDATE_MANIFEST_URL' ) ? (string) HESABIX_CHAT_UPDATE_MANIFEST_URL : '';
		return esc_url_raw( (string) apply_filters( 'hesabix_chat_update_manifest_url', $url ) );
	}

	/**
	 * آیا از raw + zip استفاده کنیم؟
	 *
	 * @return bool
	 */
	private function use_source_urls() {
		$r = $this->get_raw_php_url();
		$z = $this->get_archive_zip_url();
		if ( $r === '' || $z === '' ) {
			return false;
		}
		if ( 0 !== strpos( $r, 'https://' ) || 0 !== strpos( $z, 'https://' ) ) {
			return false;
		}
		return true;
	}

	/**
	 * استخراج نسخه و نیازمندی‌ها از محتوای hesabix-chat.php
	 *
	 * @param string $php
	 * @return array<string, string>
	 */
	private function parse_main_file_headers( $php ) {
		$out = array(
			'version'      => '',
			'requires'     => '',
			'requires_php' => '',
		);
		if ( preg_match( '/^\s*Version:\s*([0-9][0-9a-z.+-]*)\s*$/mi', $php, $m ) ) {
			$out['version'] = $m[1];
		} elseif ( preg_match( "/define\s*\(\s*['\"]HESABIX_CHAT_VERSION['\"]\s*,\s*['\"]([0-9][0-9a-z.+-]*)['\"]\s*\)/s", $php, $m ) ) {
			$out['version'] = $m[1];
		}
		if ( preg_match( '/^\s*Requires at least:\s*([0-9.]+)\s*$/mi', $php, $m ) ) {
			$out['requires'] = $m[1];
		}
		if ( preg_match( '/^\s*Requires PHP:\s*([0-9.]+)\s*$/mi', $php, $m ) ) {
			$out['requires_php'] = $m[1];
		}
		return $out;
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_info_from_source() {
		$url = $this->get_raw_php_url();
		$zip = $this->get_archive_zip_url();
		$resp = wp_remote_get(
			$url,
			array(
				'timeout'    => 15,
				'redirection'=> 2,
				'sslverify'  => true,
				'headers'    => array( 'Accept' => 'text/plain' ),
				'user-agent' => 'HesabixChat-WordPress/' . HESABIX_CHAT_VERSION . '; ' . get_bloginfo( 'url' ),
			)
		);
		if ( is_wp_error( $resp ) || (int) wp_remote_retrieve_response_code( $resp ) !== 200 ) {
			return null;
		}
		$body = wp_remote_retrieve_body( $resp );
		if ( $body === null || $body === '' ) {
			return null;
		}
		$headers = $this->parse_main_file_headers( $body );
		if ( $headers['version'] === '' ) {
			return null;
		}
		return array(
			'version'         => (string) $headers['version'],
			'download_url'    => $zip,
			'requires'        => (string) $headers['requires'],
			'tested'          => '',
			'requires_php'    => (string) $headers['requires_php'],
			'homepage'        => 'https://hesabix.ir',
			'last_updated'    => '',
			'name'            => 'Hesabix Web Chat',
			'sections'        => array(),
			'package_hash'    => '',
			'upgrade_notice'  => '',
			'banners'         => array(),
			'icons'           => array(),
			'icon_svg'        => '',
			'source'          => 'raw',
		);
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_info_from_json_manifest() {
		$url = $this->get_manifest_url();
		if ( $url === '' || 0 !== strpos( $url, 'https://' ) ) {
			return null;
		}
		$resp = wp_remote_get(
			$url,
			array(
				'timeout'     => 12,
				'redirection' => 2,
				'sslverify'   => true,
				'headers'     => array( 'Accept' => 'application/json' ),
				'user-agent'  => 'HesabixChat-WordPress/' . HESABIX_CHAT_VERSION . '; ' . get_bloginfo( 'url' ),
			)
		);
		if ( is_wp_error( $resp ) || (int) wp_remote_retrieve_response_code( $resp ) !== 200 ) {
			return null;
		}
		$body = wp_remote_retrieve_body( $resp );
		if ( $body === '' || $body === null ) {
			return null;
		}
		$data = json_decode( $body, true );
		if ( ! is_array( $data ) || empty( $data['version'] ) || empty( $data['download_url'] ) ) {
			return null;
		}
		$dl = esc_url_raw( (string) $data['download_url'] );
		if ( $dl === '' || 0 !== strpos( $dl, 'https://' ) ) {
			return null;
		}
		return array(
			'version'         => (string) $data['version'],
			'download_url'    => $dl,
			'requires'        => isset( $data['requires'] ) ? (string) $data['requires'] : '',
			'tested'          => isset( $data['tested'] ) ? (string) $data['tested'] : '',
			'requires_php'    => isset( $data['requires_php'] ) ? (string) $data['requires_php'] : '',
			'homepage'        => isset( $data['homepage'] ) ? (string) $data['homepage'] : 'https://hesabix.ir',
			'last_updated'    => isset( $data['last_updated'] ) ? (string) $data['last_updated'] : '',
			'name'            => isset( $data['name'] ) ? (string) $data['name'] : 'Hesabix Web Chat',
			'sections'        => isset( $data['sections'] ) && is_array( $data['sections'] ) ? $data['sections'] : array(),
			'package_hash'    => isset( $data['package_hash'] ) ? (string) $data['package_hash'] : '',
			'upgrade_notice'  => isset( $data['upgrade_notice'] ) ? (string) $data['upgrade_notice'] : '',
			'banners'         => isset( $data['banners'] ) && is_array( $data['banners'] ) ? $data['banners'] : array(),
			'icons'           => isset( $data['icons'] ) && is_array( $data['icons'] ) ? $data['icons'] : array(),
			'icon_svg'        => isset( $data['icon_svg'] ) ? (string) $data['icon_svg'] : '',
			'source'          => 'json',
		);
	}

	/**
	 * @return array<string, mixed>|null
	 */
	private function get_remote_info() {
		if ( (bool) apply_filters( 'hesabix_chat_update_force_check', false ) ) {
			delete_site_transient( $this->get_update_cache_key() );
			delete_site_transient( 'hesabix_chat_update_manifest' );
		}

		$cached = get_site_transient( $this->get_update_cache_key() );
		if ( is_array( $cached ) && ! empty( $cached['version'] ) && ! empty( $cached['download_url'] ) ) {
			return $cached;
		}

		$info = null;
		if ( (bool) apply_filters( 'hesabix_chat_prefer_json_manifest', false ) && $this->get_manifest_url() !== '' ) {
			$info = $this->get_info_from_json_manifest();
		}
		if ( $info === null && $this->use_source_urls() ) {
			$info = $this->get_info_from_source();
		}
		if ( $info === null && $this->get_manifest_url() !== '' ) {
			$info = $this->get_info_from_json_manifest();
		}
		if ( $info === null ) {
			return null;
		}

		if ( $info['requires'] !== '' && version_compare( get_bloginfo( 'version' ), $info['requires'], '<' ) ) {
			return null;
		}
		if ( $info['requires_php'] !== '' && version_compare( (string) PHP_VERSION, $info['requires_php'], '<' ) ) {
			return null;
		}

		set_site_transient( $this->get_update_cache_key(), $info, (int) apply_filters( 'hesabix_chat_update_cache_ttl', self::CACHE_TTL ) );
		return $info;
	}

	/**
	 * @param false|object $transient .
	 * @return object|false
	 */
	public function filter_update_transient( $transient ) {
		if ( ! is_object( $transient ) || empty( $transient->checked ) || ! is_array( $transient->checked ) ) {
			return $transient;
		}

		$plugin_file = plugin_basename( HESABIX_CHAT_FILE );
		if ( ! isset( $transient->checked[ $plugin_file ] ) ) {
			return $transient;
		}

		$info = $this->get_remote_info();
		if ( $info === null ) {
			return $transient;
		}

		$current = (string) $transient->checked[ $plugin_file ];
		$new     = (string) $info['version'];
		if ( ! version_compare( $new, $current, '>' ) ) {
			return $transient;
		}

		$home = ! empty( $info['homepage'] ) ? $info['homepage'] : 'https://hesabix.ir';
		$item = array(
			'id'           => $plugin_file,
			'slug'         => dirname( $plugin_file ),
			'plugin'       => $plugin_file,
			'new_version'  => $new,
			'url'          => esc_url( $home ),
			'package'      => (string) $info['download_url'],
			'tested'       => (string) ( $info['tested'] ?? '' ),
			'requires'     => (string) ( $info['requires'] ?? '' ),
			'requires_php' => (string) ( $info['requires_php'] ?? '' ),
		);
		if ( ! empty( $info['upgrade_notice'] ) ) {
			$item['upgrade_notice'] = (string) $info['upgrade_notice'];
		}
		if ( ! empty( $info['banners'] ) && is_array( $info['banners'] ) ) {
			$item['banners'] = $info['banners'];
		}
		if ( ! empty( $info['icons'] ) && is_array( $info['icons'] ) ) {
			$item['icons'] = $info['icons'];
		} elseif ( ! empty( $info['icon_svg'] ) ) {
			$item['icons'] = array( '1x' => (string) $info['icon_svg'] );
		}

		$transient->response[ $plugin_file ] = (object) $item;
		return $transient;
	}

	/**
	 * @param false|object|array $res .
	 * @param string             $action .
	 * @param object             $args .
	 * @return false|object|array
	 */
	public function plugin_info( $res, $action, $args ) {
		if ( 'plugin_information' !== $action || ! isset( $args->slug ) ) {
			return $res;
		}
		$dir = dirname( plugin_basename( HESABIX_CHAT_FILE ) );
		if ( (string) $args->slug !== $dir ) {
			return $res;
		}

		$info = $this->get_remote_info();
		if ( $info === null ) {
			$info = array(
				'version'         => HESABIX_CHAT_VERSION,
				'download_url'    => '',
				'name'            => 'Hesabix Web Chat',
				'homepage'        => 'https://hesabix.ir',
				'last_updated'    => '',
				'sections'        => array(),
			);
		}

		$sections = array( 'description' => '' );
		if ( ! empty( $info['sections'] ) && is_array( $info['sections'] ) ) {
			foreach ( $info['sections'] as $k => $v ) {
				if ( is_string( $k ) && is_string( $v ) && $v !== '' ) {
					$sections[ $k ] = wp_kses_post( $v );
				}
			}
		}
		if ( ! empty( $info['source'] ) && 'raw' === $info['source'] ) {
			$sections['description'] = esc_html__( 'منبع به‌روزرسانی: نسخه از فایل اصلی در مخزن و بسته zip همان شاخه.', 'hesabix-chat' );
		} elseif ( empty( $sections['description'] ) ) {
			$sections['description'] = esc_html__( 'اتصال سایت وردپرس به چت وب CRM حسابیکس.', 'hesabix-chat' );
		}

		$out = (object) array(
			'name'          => $info['name'],
			'slug'          => $dir,
			'version'       => $info['version'],
			'author'        => '<a href="https://hesabix.ir" target="_blank" rel="noopener">Hesabix</a>',
			'homepage'      => ! empty( $info['homepage'] ) ? esc_url( (string) $info['homepage'] ) : 'https://hesabix.ir',
			'last_updated'  => ! empty( $info['last_updated'] ) ? (string) $info['last_updated'] : null,
			'download_link' => ! empty( $info['download_url'] ) ? esc_url( (string) $info['download_url'] ) : '',
			'sections'      => $sections,
			'banners'       => ! empty( $info['banners'] ) && is_array( $info['banners'] ) ? $info['banners'] : array(),
		);
		if ( ! empty( $info['icons'] ) && is_array( $info['icons'] ) ) {
			$out->icons = $info['icons'];
		}
		return $out;
	}

	/**
	 * پوشهٔ داخل zip آرشیو گیت‌معمولاً `نامپروژه-شاخه` است؛ به نام پوشهٔ نصب‌شده روی وردپرس یکی می‌کنیم.
	 *
	 * @param string|WP_Error      $source       .
	 * @param string|WP_Error      $remote_source .
	 * @param \WP_Upgrader         $upgrader     .
	 * @param array<string, mixed> $extra        .
	 * @return string|WP_Error
	 */
	public function align_extracted_plugin_folder( $source, $remote_source, $upgrader, $extra = array() ) { // phpcs:ignore VariableAnalysis.CodeAnalysis.VariableAnalysis
		if ( is_wp_error( $source ) || ! is_string( $source ) || $source === '' ) {
			return $source;
		}
		if ( empty( $extra['plugin'] ) || (string) $extra['plugin'] !== plugin_basename( HESABIX_CHAT_FILE ) ) {
			return $source;
		}

		$expected_name = dirname( (string) $extra['plugin'] );
		if ( basename( $source ) === $expected_name ) {
			return $source;
		}

		global $wp_filesystem;
		if ( ! $wp_filesystem || ! is_object( $wp_filesystem ) ) {
			return $source;
		}

		$new = trailingslashit( dirname( $source ) ) . $expected_name;
		if ( $wp_filesystem->exists( $new ) ) {
			$wp_filesystem->delete( $new, true );
		}
		if ( $wp_filesystem->move( $source, $new ) ) {
			return $new;
		}
		return $source;
	}
}
