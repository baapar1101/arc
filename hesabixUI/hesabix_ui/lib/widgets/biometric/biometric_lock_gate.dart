import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth_store.dart';
import '../../core/biometric_lock_controller.dart';
import '../../core/biometric_lock_prefs.dart';
import '../../core/biometric_platform.dart';
import 'biometric_lock_overlay.dart';
import 'biometric_lock_scope.dart';

/// Observes app lifecycle and auth changes to show biometric lock overlay.
class BiometricLockGate extends StatefulWidget {
  final AuthStore authStore;
  final BiometricLockController lockController;
  final Widget child;

  const BiometricLockGate({
    super.key,
    required this.authStore,
    required this.lockController,
    required this.child,
  });

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate>
    with WidgetsBindingObserver {
  bool _wentToBackground = false;
  bool _initialLockScheduled = false;

  @override
  void initState() {
    super.initState();
    if (supportsBiometricLock) {
      WidgetsBinding.instance.addObserver(this);
      widget.authStore.addListener(_onAuthChanged);
      _scheduleInitialLock();
    }
  }

  @override
  void dispose() {
    if (supportsBiometricLock) {
      widget.authStore.removeListener(_onAuthChanged);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  void _scheduleInitialLock() {
    if (_initialLockScheduled) return;
    _initialLockScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await BiometricLockPrefs.runMigrationIfNeeded();
      if (!mounted) return;
      await widget.lockController.lockIfNeeded(
        hasApiKey: _hasApiKey,
        userId: widget.authStore.currentUserId,
      );
    });
  }

  bool get _hasApiKey =>
      widget.authStore.apiKey != null && widget.authStore.apiKey!.isNotEmpty;

  void _onAuthChanged() {
    if (!_hasApiKey) {
      widget.lockController.unlock();
      return;
    }
    _scheduleInitialLock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!supportsBiometricLock) return;

    // فقط paused/hidden = واقعاً به پس‌زمینه رفته.
    // inactive معمولاً هنگام نمایش BiometricPrompt سیستم رخ می‌دهد و نباید قفل را تریگر کند.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wentToBackground = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _wentToBackground) {
      _wentToBackground = false;
      if (!_hasApiKey) return;
      // اگر همین الان در حال احراز هویت هستیم، دوباره قفل نکن
      if (widget.lockController.isLocked) return;
      unawaited(
        widget.lockController.forceLock(
          hasApiKey: true,
          userId: widget.authStore.currentUserId,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsBiometricLock) {
      return widget.child;
    }

    return BiometricLockScope(
      controller: widget.lockController,
      child: ListenableBuilder(
        listenable: widget.lockController,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (widget.lockController.isLocked)
                BiometricLockOverlay(
                  authStore: widget.authStore,
                  lockController: widget.lockController,
                ),
            ],
          );
        },
      ),
    );
  }
}
