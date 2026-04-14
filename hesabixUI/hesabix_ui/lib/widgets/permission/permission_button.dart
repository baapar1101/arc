import 'package:flutter/material.dart';
import '../../core/auth_store.dart';

/// کامپوننت برای نمایش دکمه‌ها بر اساس دسترسی‌ها
class PermissionButton extends StatelessWidget {
  final String section;
  final String action;
  final Widget child;
  final VoidCallback? onPressed;
  final bool showIfNoPermission;
  final Widget? fallbackWidget;
  final AuthStore authStore;

  const PermissionButton({
    super.key,
    required this.section,
    required this.action,
    required this.child,
    required this.authStore,
    this.onPressed,
    this.showIfNoPermission = false,
    this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (!authStore.hasBusinessPermission(section, action)) {
      if (showIfNoPermission) {
        return child;
      }
      return fallbackWidget ?? const SizedBox.shrink();
    }
    
    return child;
  }
}

/// کامپوننت برای نمایش ویجت‌ها بر اساس دسترسی‌ها
class PermissionWidget extends StatelessWidget {
  final String section;
  final String action;
  final Widget child;
  final Widget? fallbackWidget;
  final AuthStore authStore;

  const PermissionWidget({
    super.key,
    required this.section,
    required this.action,
    required this.child,
    required this.authStore,
    this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (!authStore.hasBusinessPermission(section, action)) {
      return fallbackWidget ?? const SizedBox.shrink();
    }
    
    return child;
  }
}

/// کامپوننت برای نمایش لیست بر اساس دسترسی‌ها
class PermissionListTile extends StatelessWidget {
  final String section;
  final String action;
  final Widget child;
  final VoidCallback? onTap;
  final AuthStore authStore;

  const PermissionListTile({
    super.key,
    required this.section,
    required this.action,
    required this.child,
    required this.authStore,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!authStore.hasBusinessPermission(section, action)) {
      return const SizedBox.shrink();
    }
    
    return child;
  }
}

/// کامپوننت برای نمایش منو بر اساس دسترسی‌ها
class PermissionMenuItem extends StatelessWidget {
  final String section;
  final String action;
  final Widget child;
  final AuthStore authStore;

  const PermissionMenuItem({
    super.key,
    required this.section,
    required this.action,
    required this.child,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    if (!authStore.hasBusinessPermission(section, action)) {
      return const SizedBox.shrink();
    }
    
    return child;
  }
}
