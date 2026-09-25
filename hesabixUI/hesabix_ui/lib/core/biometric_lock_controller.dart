import 'package:flutter/foundation.dart';

import 'biometric_lock_prefs.dart';
import 'biometric_platform.dart';

/// Client-side lock state layered on top of persisted API key sessions.
class BiometricLockController extends ChangeNotifier {
  bool _locked = false;
  bool _suppressNextLock = false;
  bool _evaluating = false;

  bool get isLocked => _locked;

  void markFreshLogin() {
    _suppressNextLock = true;
    _locked = false;
    notifyListeners();
  }

  /// Skip the next resume lock (e.g. after handing off to the system package installer).
  void suppressNextLock() {
    _suppressNextLock = true;
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  Future<void> lockIfNeeded({
    required bool hasApiKey,
    required int? userId,
  }) async {
    if (!supportsBiometricLock || _evaluating) return;
    if (!hasApiKey) {
      if (_locked) {
        _locked = false;
        notifyListeners();
      }
      return;
    }

    if (_suppressNextLock) {
      _suppressNextLock = false;
      return;
    }

    _evaluating = true;
    try {
      final enabled = await BiometricLockPrefs.isEnabled(userId);
      if (!enabled) {
        if (_locked) {
          _locked = false;
          notifyListeners();
        }
        return;
      }
      if (!_locked) {
        _locked = true;
        notifyListeners();
      }
    } finally {
      _evaluating = false;
    }
  }

  Future<void> forceLock({
    required bool hasApiKey,
    required int? userId,
  }) async {
    _suppressNextLock = false;
    await lockIfNeeded(hasApiKey: hasApiKey, userId: userId);
  }
}
