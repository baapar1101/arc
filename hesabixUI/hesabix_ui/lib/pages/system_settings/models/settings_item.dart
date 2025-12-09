import 'package:flutter/material.dart';

/// مدل بهبود یافته برای آیتم‌های تنظیمات
class SettingsItem {
  final String id;
  final String title; // کلید localization
  final String description; // کلید localization
  final IconData icon;
  final Color color;
  final String route;
  final String categoryId;
  final List<String> tags; // ['new', 'important', 'advanced']
  final bool isFavorite;
  final int order;
  final bool requiresSuperAdmin; // نیاز به دسترسی superadmin

  const SettingsItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.route,
    required this.categoryId,
    this.tags = const [],
    this.isFavorite = false,
    this.order = 0,
    this.requiresSuperAdmin = false,
  });

  SettingsItem copyWith({
    String? id,
    String? title,
    String? description,
    IconData? icon,
    Color? color,
    String? route,
    String? categoryId,
    List<String>? tags,
    bool? isFavorite,
    int? order,
    bool? requiresSuperAdmin,
  }) {
    return SettingsItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      route: route ?? this.route,
      categoryId: categoryId ?? this.categoryId,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      order: order ?? this.order,
      requiresSuperAdmin: requiresSuperAdmin ?? this.requiresSuperAdmin,
    );
  }
}

