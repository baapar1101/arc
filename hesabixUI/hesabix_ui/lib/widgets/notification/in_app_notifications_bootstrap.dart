import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../services/in_app_notifications_hub.dart';
import '../../services/notification_tap_navigation.dart';

/// Binds auth + lifecycle to [InAppNotificationsHub] and consumes notification taps.
class InAppNotificationsBootstrap extends StatefulWidget {
  final AuthStore authStore;
  final CalendarController? calendarController;
  final Widget child;

  const InAppNotificationsBootstrap({
    super.key,
    required this.authStore,
    required this.child,
    this.calendarController,
  });

  @override
  State<InAppNotificationsBootstrap> createState() => _InAppNotificationsBootstrapState();
}

class _InAppNotificationsBootstrapState extends State<InAppNotificationsBootstrap>
    with WidgetsBindingObserver {
  String? _lastApiKey;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.authStore.addListener(_onAuthChanged);
    widget.calendarController?.addListener(_onCalendarChanged);
    _applyCalendar();
    unawaited(_sync());
  }

  @override
  void didUpdateWidget(covariant InAppNotificationsBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authStore != widget.authStore) {
      oldWidget.authStore.removeListener(_onAuthChanged);
      widget.authStore.addListener(_onAuthChanged);
      unawaited(_sync());
    }
    if (oldWidget.calendarController != widget.calendarController) {
      oldWidget.calendarController?.removeListener(_onCalendarChanged);
      widget.calendarController?.addListener(_onCalendarChanged);
      _applyCalendar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authStore.removeListener(_onAuthChanged);
    widget.calendarController?.removeListener(_onCalendarChanged);
    super.dispose();
  }

  void _onCalendarChanged() => _applyCalendar();

  void _applyCalendar() {
    final jalali = widget.calendarController?.isJalali ?? true;
    InAppNotificationsHub.instance.setAppIsJalali(jalali);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    InAppNotificationsHub.instance.setLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _consumePendingTap();
    }
  }

  void _onAuthChanged() {
    unawaited(_sync());
  }

  Future<void> _sync() async {
    _applyCalendar();
    final apiKey = widget.authStore.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      if (_started || _lastApiKey != null) {
        await InAppNotificationsHub.instance.onLogout();
        _started = false;
        _lastApiKey = null;
      }
      return;
    }
    if (_lastApiKey == apiKey && _started) {
      _consumePendingTap();
      return;
    }
    _lastApiKey = apiKey;
    await InAppNotificationsHub.instance.startForApiKey(apiKey);
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingTap());
  }

  void _consumePendingTap() {
    if (!mounted) return;
    final pending = NotificationTapNavigation.instance.peek();
    if (pending == null) return;
    final apiKey = widget.authStore.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    try {
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        unawaited(NotificationTapNavigation.instance.tryConsume(context));
        return;
      }
    } catch (_) {}
    unawaited(NotificationTapNavigation.instance.tryConsume(context));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
