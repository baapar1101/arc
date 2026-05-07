<?php
/**
 * حذف تنظیمات هنگام حذف افزونه.
 *
 * @package HesabixChat
 */

defined( 'WP_UNINSTALL_PLUGIN' ) || exit;

delete_option( 'hesabix_chat_options' );
delete_site_transient( 'hesabix_chat_update_manifest' );
delete_site_transient( 'hesabix_chat_update_info' );
