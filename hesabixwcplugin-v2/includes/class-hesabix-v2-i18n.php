<?php
/**
 * Define the internationalization functionality
 *
 * @since      2.0.0
 * @package    Hesabix_V2
 * @subpackage Hesabix_V2/includes
 */

class Hesabix_V2_i18n
{
	/**
	 * Load the plugin text domain for translation.
	 *
	 * @since    2.0.0
	 */
	public function load_plugin_textdomain()
	{
		load_plugin_textdomain(
			'hesabix-v2',
			false,
			dirname(dirname(plugin_basename(__FILE__))) . '/languages/'
		);
	}
}

