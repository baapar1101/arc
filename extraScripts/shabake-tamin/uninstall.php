<?php
/**
 * حذف تنظیمات هنگام حذف افزونه از پنل وردپرس.
 *
 * @package Shabake_Tamin
 */

defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

delete_option( 'st_api_base_url' );
delete_option( 'st_cache_ttl' );
delete_option( 'st_default_business_id' );
