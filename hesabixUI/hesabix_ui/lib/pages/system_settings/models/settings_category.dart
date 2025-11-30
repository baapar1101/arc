import 'package:flutter/material.dart';
import 'settings_item.dart';

/// مدل دسته‌بندی تنظیمات
class SettingsCategory {
  final String id;
  final String title; // کلید localization
  final String? description; // کلید localization
  final IconData icon;
  final Color color;
  final List<SettingsItem> items;
  final int order;
  final bool requiresSuperAdmin; // آیا فقط SuperAdmin می‌تواند ببیند

  const SettingsCategory({
    required this.id,
    required this.title,
    this.description,
    required this.icon,
    required this.color,
    required this.items,
    this.order = 0,
    this.requiresSuperAdmin = false,
  });

  SettingsCategory copyWith({
    String? id,
    String? title,
    String? description,
    IconData? icon,
    Color? color,
    List<SettingsItem>? items,
    int? order,
    bool? requiresSuperAdmin,
  }) {
    return SettingsCategory(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      items: items ?? this.items,
      order: order ?? this.order,
      requiresSuperAdmin: requiresSuperAdmin ?? this.requiresSuperAdmin,
    );
  }

  /// تعداد آیتم‌های فعال در این دسته
  int get itemCount => items.length;

  /// تعداد آیتم‌های مورد علاقه در این دسته
  int get favoriteCount => items.where((item) => item.isFavorite).length;
}

