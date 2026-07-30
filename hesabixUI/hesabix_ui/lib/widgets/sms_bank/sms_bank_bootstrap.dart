import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/android_sms_bank_platform.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../services/notification_tap_navigation.dart';
import '../../services/sms_bank/sms_bank_assistant_service.dart';
import '../../services/sms_bank/sms_bank_capture_navigation.dart';
import '../../services/sms_bank/sms_bank_models.dart';
import 'sms_quick_capture_sheet.dart';

/// Android-only bootstrap: drains pending SMS bank events and shows quick capture.
class SmsBankBootstrap extends StatefulWidget {
  final AuthStore authStore;
  final CalendarController? calendarController;
  final Widget child;

  const SmsBankBootstrap({
    super.key,
    required this.authStore,
    required this.child,
    this.calendarController,
  });

  @override
  State<SmsBankBootstrap> createState() => _SmsBankBootstrapState();
}

class _SmsBankBootstrapState extends State<SmsBankBootstrap> with WidgetsBindingObserver {
  final SmsBankAssistantService _service = createSmsBankAssistantService();
  bool _ready = false;
  bool _showing = false;
  String? _lastShownId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SmsBankCaptureNavigation.instance.addListener(_onQueued);
    widget.authStore.addListener(_onAuth);
    unawaited(_boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SmsBankCaptureNavigation.instance.removeListener(_onQueued);
    widget.authStore.removeListener(_onAuth);
    _service.setOnEvent(null);
    super.dispose();
  }

  void _onAuth() => unawaited(_syncBusinessAndDrain());

  void _onQueued(SmsBankEvent event) {
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
    if (pendingTap != null) {
      final deep = '${pendingTap['deep_link'] ?? ''}';
      final eventKey = '${pendingTap['event_key'] ?? ''}';
      final smsId = '${pendingTap['sms_bank_event_id'] ?? ''}';
      if (eventKey == 'sms_bank_capture' || deep.contains('sms-bank') || smsId.isNotEmpty) {
        NotificationTapNavigation.instance.clear();
        final id = smsId.isNotEmpty
            ? smsId
            : Uri.tryParse(deep)?.queryParameters['id'];
        if (id != null && id.isNotEmpty) {
          final event = await _service.getEvent(id);
          if (event != null) {
            await _present(event);
            return;
          }
        }
      }
    }

    final launchId = await _service.consumeLaunchEventId();
    if (launchId != null && launchId.isNotEmpty) {
      final event = await _service.getEvent(launchId);
      if (event != null) {
        await _present(event);
        return;
      }
      final pending = await _service.drainPendingEvents();
      SmsBankEvent? found;
      for (final e in pending) {
        if (e.id == launchId) {
          found = e;
          break;
        }
      }
      if (found != null) {
        await _present(found);
        return;
      }
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
    if (event.status != SmsBankEventStatus.pending &&
        event.status != SmsBankEventStatus.captured) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    _showing = true;
    _lastShownId = event.id;
    SmsBankCaptureNavigation.instance.consume();
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
