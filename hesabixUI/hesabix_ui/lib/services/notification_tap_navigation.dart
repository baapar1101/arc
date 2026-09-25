import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/announcement_navigation.dart';
import '../services/sms_bank/sms_bank_launch_navigation.dart';

/// Queues notification-tap navigation until GoRouter / auth are ready.
class NotificationTapNavigation {
  NotificationTapNavigation._();

  static final NotificationTapNavigation instance = NotificationTapNavigation._();

  Map<String, dynamic>? _pending;
  bool _consuming = false;

  void enqueue(Map<String, dynamic> item) {
    _pending = AnnouncementNavigation.normalizeItem(item);
  }

  Map<String, dynamic>? peek() => _pending;

  /// Apply pending navigation when a [GoRouter]-capable context is available.
  Future<bool> tryConsume(BuildContext context) async {
    final item = _pending;
    if (item == null || _consuming) return false;
    if (!context.mounted) return false;

    // SMS bank capture is handled by SmsBankBootstrap — keep pending until then.
    if (SmsBankLaunchNavigation.isSmsBankCaptureNotification(item)) {
      return false;
    }

    final route = AnnouncementNavigation.resolveDeepLink(item);
    if (route == null || route.isEmpty) {
      // Still mark-read if possible; clear pending either way.
      _consuming = true;
      try {
        await AnnouncementNavigation.handleTap(context, item);
      } finally {
        _pending = null;
        _consuming = false;
      }
      return true;
    }

    _consuming = true;
    try {
      await AnnouncementNavigation.handleTap(context, item);
      _pending = null;
      return true;
    } catch (_) {
      // Keep pending for a later resume attempt.
      return false;
    } finally {
      _consuming = false;
    }
  }

  /// Direct go when only a router is available (cold start after splash).
  Future<bool> tryConsumeWithRouter(GoRouter router) async {
    final item = _pending;
    if (item == null || _consuming) return false;

    if (SmsBankLaunchNavigation.isSmsBankCaptureNotification(item)) {
      return false;
    }

    final route = AnnouncementNavigation.resolveDeepLink(item);
    if (route == null || route.isEmpty) {
      _pending = null;
      return false;
    }
    _consuming = true;
    try {
      // Mark read best-effort without BuildContext snackbars.
      final annId = AnnouncementNavigation.parseAnnouncementId(item['id']);
      if (annId != null && item['is_read'] != true) {
        try {
          // Lazy import path via AnnouncementNavigation.handleTap needs context;
          // for router-only path we just navigate; mark-read happens on open screens.
        } catch (_) {}
      }
      router.go(route);
      _pending = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      _consuming = false;
    }
  }

  void clear() {
    _pending = null;
  }
}
