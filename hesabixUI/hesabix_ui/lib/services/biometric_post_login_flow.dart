import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../core/auth_store.dart';
import '../core/biometric_lock_prefs.dart';
import '../core/biometric_platform.dart';
import '../core/mobile_launcher_prefs.dart';
import '../services/biometric_auth_service.dart';
import '../widgets/biometric/biometric_lock_scope.dart';
import '../utils/snackbar_helper.dart';

/// Post-login opt-in dialog and navigation helper for biometric lock.
class BiometricPostLoginFlow {
  static final BiometricAuthService _biometric = createBiometricAuthService();

  /// Android BiometricPrompt often fails if started while a Flutter dialog
  /// route is still tearing down — wait for frames + a short settle delay.
  static Future<void> _waitForUiSettle() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await SchedulerBinding.instance.endOfFrame;
  }

  static Future<BiometricAuthResult> _authenticateWithRetry(String reason) async {
    final sw = Stopwatch()..start();
    var result = await _biometric.authenticate(reason: reason);
    // Instant failure usually means the system prompt never appeared (UI race).
    if (!result.success && sw.elapsedMilliseconds < 500) {
      await _waitForUiSettle();
      result = await _biometric.authenticate(reason: reason);
    }
    return result;
  }

  static Future<void> maybeShowOptInDialog(
    BuildContext context, {
    required AuthStore authStore,
  }) async {
    if (!supportsBiometricLock) return;

    final userId = authStore.currentUserId;
    if (userId == null || userId <= 0) return;

    final available = await _biometric.isAvailable();
    if (!available) return;

    final alreadyEnabled = await BiometricLockPrefs.isEnabled(userId);
    if (alreadyEnabled) return;

    final prompted = await BiometricLockPrefs.hasBeenPrompted(userId);
    if (prompted) return;

    if (!context.mounted) return;
    final t = AppLocalizations.of(context);

    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          icon: Icon(
            Icons.fingerprint,
            size: 48,
            color: Theme.of(ctx).colorScheme.primary,
          ),
          title: Text(t.biometricOptInTitle),
          content: Text(t.biometricOptInMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.biometricOptInNotNow),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.biometricOptInEnable),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;

    if (enable == true) {
      // Dialog must fully dismiss before BiometricPrompt can attach.
      await _waitForUiSettle();
      if (!context.mounted) return;

      final result = await _authenticateWithRetry(t.biometricOptInAuthReason);
      if (result.success) {
        await BiometricLockPrefs.setEnabled(userId, true);
        await BiometricLockPrefs.markPrompted(userId);
        if (context.mounted) {
          SnackBarHelper.show(context, message: t.biometricSettingsEnabledSuccess);
        }
      } else if (!result.canceled && context.mounted) {
        // Auth failed for a real reason — do NOT mark prompted so user can try again
        // next login / from settings.
        SnackBarHelper.showError(
          context,
          message: result.errorMessage?.isNotEmpty == true
              ? '${t.biometricSettingsEnableFailed} (${result.errorCode ?? ''})'
              : t.biometricSettingsEnableFailed,
        );
      }
      // If canceled: leave prompted=false so we can ask again later.
    } else {
      // Explicit "not now"
      await BiometricLockPrefs.markPrompted(userId);
    }
  }

  static Future<void> completeLoginAndNavigate(
    BuildContext context, {
    required AuthStore authStore,
    String? preferredPath,
  }) async {
    // Keep user on /login until opt-in + navigation finish (see GoRouter redirect).
    authStore.beginPostLoginFlow();
    try {
      await maybeShowOptInDialog(context, authStore: authStore);

      if (!context.mounted) return;
      final lockController = BiometricLockScope.maybeOf(context);
      lockController?.markFreshLogin();

      final destination = preferredPath ??
          await MobileLauncherPrefs.postAuthHomeLocation(authStore.currentUserId);
      if (!context.mounted) return;

      // Clear deferral before go() so future /login visits redirect normally.
      authStore.endPostLoginFlow();
      context.go(destination);
    } finally {
      authStore.endPostLoginFlow();
    }
  }
}
