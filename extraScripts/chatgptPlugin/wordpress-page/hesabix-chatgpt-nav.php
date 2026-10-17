<?php
/**
 * Plugin Name: Hesabix ChatGPT navigation
 * Description: Adds the ChatGPT connection guide to the Hesabix product menu.
 * Version: 1.0.0
 * Author: TFS company LTD
 */

defined('ABSPATH') || exit;

add_filter('hesabix2_header_nav_tree', static function ($tree) {
    if (!is_array($tree)) {
        return $tree;
    }

    $url = home_url('/chatgpt/');
    foreach ($tree as &$node) {
        if (($node['id'] ?? '') !== 'product' || empty($node['columns']) || !is_array($node['columns'])) {
            continue;
        }
        foreach ($node['columns'] as &$column) {
            if (($column['title'] ?? '') !== 'هوشمندسازی') {
                continue;
            }
            $items = !empty($column['items']) && is_array($column['items']) ? $column['items'] : array();
            foreach ($items as $item) {
                if (($item['url'] ?? '') === $url) {
                    continue 3;
                }
            }
            $items[] = array(
                'label'       => 'حسابیکس در ChatGPT',
                'description' => 'گزارش و عملیات مجاز با اتصال MCP',
                'url'         => $url,
                'icon'        => 'ai',
                'badge'       => 'جدید',
            );
            $column['items'] = $items;
        }
        unset($column);
    }
    unset($node);

    return $tree;
});
