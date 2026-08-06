import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/android_sms_bank_platform.dart';
import '../../core/auth_store.dart';
import '../../core/biometric_lock_controller.dart';
import '../../core/biometric_platform.dart';
import '../../core/calendar_controller.dart';
import '../../services/notification_tap_navigation.dart';
import '../../services/sms_bank/sms_bank_assistant_service.dart';
import '../../services/sms_bank/sms_bank_capture_navigation.dart';
import '../../services/sms_bank/sms_bank_launch_navigation.dart';
import '../../services/sms_bank/sms_bank_models.dart';
import 'sms_quick_capture_sheet.dart';

/// Android-only bootstrap: drains pending SMS bank events and shows quick capture.
class SmsBankBootstrap extends StatefulWidget {
  final AuthStore authStore;
  final CalendarController? calendarController;
  final BiometricLockController? biometricLockController;
  final Widget child;

  const SmsBankBootstrap({
    super.key,
    required this.authStore,
    required this.child,
    this.calendarController,
    this.biometricLockController,
  });

  @override
  State<SmsBankBootstrap> createState() => _SmsBankBootstrapState();
}

class _SmsBankBootstrapState extends State<SmsBankBootstrap> with WidgetsBindingObserver {
  final SmsBankAssistantService _service = createSmsBankAssistantService();
  bool _ready = false;
  bool _showing = false;
  String? _lastShownId;
  /// Held while biometric lock is active; presented after unlock.
  SmsBankEvent? _waitingForUnlock;

  bool get _isBiometricLocked =>
      supportsBiometricLock && (widget.biometricLockController?.isLocked ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SmsBankCaptureNavigation.instance.addListener(_onQueued);
    widget.authStore.addListener(_onAuth);
    widget.biometricLockController?.addListener(_onLockChanged);
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(covariant SmsBankBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.biometricLockController != widget.biometricLockController) {
      oldWidget.biometricLockController?.removeListener(_onLockChanged);
      widget.biometricLockController?.addListener(_onLockChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SmsBankCaptureNavigation.instance.removeListener(_onQueued);
    widget.authStore.removeListener(_onAuth);
    widget.biometricLockController?.removeListener(_onLockChanged);
    _service.setOnEvent(null);
    super.dispose();
  }

  void _onAuth() => unawaited(_syncBusinessAndDrain());

  void _onLockChanged() {
    if (_isBiometricLocked) return;
    final waiting = _waitingForUnlock ?? SmsBankCaptureNavigation.instance.peek();
    if (waiting != null) {
      _waitingForUnlock = null;
      unawaited(_present(waiting));
      return;
    }
    unawaited(_syncBusinessAndDrain());
  }

  void _onQueued(SmsBankEvent event) {
    if (_isBiometricLocked) {
      _waitingForUnlock = event;
      return;
    }
    unawaited(_present(event));
  }

  Future<void> _boot() async {
    if (!supportsAndroidSmsBankAssistant) {
      _ready = true;
      return;
    }
    await _service.initialize(onEvent: (event) {
      SmsBankCaptureNavigation.instance.enqueue(event);
    });
    _ready = true;
    await _syncBusinessAndDrain();
  }

  Future<void> _syncBusinessAndDrain() async {
    if (!supportsAndroidSmsBankAssistant || !_ready) return;
    final biz = widget.authStore.currentBusiness;
    if (biz != null) {
      final settings = await _service.getSettings();
      // Soft hint only — do not reassign other businesses' patterns.
      if (settings.activeBusinessId != biz.id) {
        await _service.saveSettings(settings.copyWith(activeBusinessId: biz.id));
      } else {
        await _service.syncNativeConfig();
      }
    }

    // Intercept tray notification taps for SMS bank before GoRouter tries hesabix://
    final pendingTap = NotificationTapNavigation.instance.peek();
    if (pendingTap != null &&
        SmsBankLaunchNavigation.isSmsBankCaptureNotification(pendingTap)) {
      NotificationTapNavigation.instance.clear();
      final id = SmsBankLaunchNavigation.extractEventIdFromNotification(pendingTap);
      if (id != null && id.isNotEmpty) {
        final event = await _resolveEvent(id);
        if (event != null) {
          await _present(event);
          return;
        }
      }
    }

    final launchId = await _service.peekLaunchEventId();
    if (launchId != null && launchId.isNotEmpty) {
      final event = await _resolveEvent(launchId);
      if (event != null) {
        await _present(event);
        return;
      }
    }

    if (_isBiometricLocked) {
      return;
    }

    final settings = await _service.getSettings();
    final pending = await _service.drainPendingEvents();
    if (pending.isEmpty) return;

    final newest = pending.first;
    if (settings.interruptMode == SmsBankInterruptMode.autoOpen ||
        SmsBankCaptureNavigation.instance.peek() == null) {
      await _present(newest);
    } else {
      SmsBankCaptureNavigation.instance.enqueue(newest);
    }
  }

  Future<SmsBankEvent?> _resolveEvent(String id) async {
    final cached = await _service.getEvent(id);
    if (cached != null) return cached;
    final taken = await _service.takePendingEvent(id);
    if (taken != null) return taken;
    // Fallback: legacy path if native take is unavailable.
    final pending = await _service.drainPendingEvents();
    for (final e in pending) {
      if (e.id == id) return e;
    }
    return _service.getEvent(id);
  }

  void _ensureSafeRouteForCapture() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (SmsBankLaunchNavigation.shouldRedirectAwayFromCapture(router.state.uri)) {
      router.go('/');
    }
  }

  Future<void> _present(SmsBankEvent event) async {
    if (!supportsAndroidSmsBankAssistant) return;
    if (!mounted) return;
    if (_showing) {
      SmsBankCaptureNavigation.instance.enqueue(event);
      return;
    }
    if (_lastShownId == event.id && event.status != SmsBankEventStatus.pending) return;
    if (widget.authStore.apiKey == null || widget.authStore.apiKey!.isEmpty) {
      SmsBankCaptureNavigation.instance.enqueue(event);
      return;
    }
    if (_isBiometricLocked) {
      _waitingForUnlock = event;
      return;
    }
    if (event.status != SmsBankEventStatus.pending &&
        event.status != SmsBankEventStatus.captured) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (_isBiometricLocked) {
      _waitingForUnlock = event;
      return;
    }

    _ensureSafeRouteForCapture();

    _showing = true;
    _lastShownId = event.id;
    SmsBankCaptureNavigation.instance.consume();
    if (!mounted) {
      _showing = false;
      _waitingForUnlock = event;
      return;
    }
    // Clear launch id only once we are about to show the sheet successfully.
    await _service.clearLaunchEventId();
    if (!mounted) {
      _showing = false;
      _waitingForUnlock = event;
      return;
    }
    try {
      await showSmsQuickCaptureSheet(
        context: context,
        event: event,
        authStore: widget.authStore,
        calendarController: widget.calendarController,
      );
    } finally {
      _showing = false;
      final next = SmsBankCaptureNavigation.instance.peek();
      if (next != null && next.id != event.id) {
        unawaited(_present(next));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncBusinessAndDrain());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
