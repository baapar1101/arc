import 'package:flutter/material.dart';
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
      final result = await _biometric.authenticate(reason: t.biometricOptInAuthReason);
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
          message: t.biometricSettingsEnableFailed,
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
    await maybeShowOptInDialog(context, authStore: authStore);

    final lockController = BiometricLockScope.maybeOf(context);
    lockController?.markFreshLogin();

    if (!context.mounted) return;

    final destination = preferredPath ??
        await MobileLauncherPrefs.postAuthHomeLocation(authStore.currentUserId);
    if (!context.mounted) return;
    context.go(destination);
  }
}
