import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../core/biometric_lock_controller.dart';
import '../../core/biometric_platform.dart';
import '../../services/biometric_auth_service.dart';
import 'biometric_lock_scope.dart';

/// Full-screen overlay that blocks the app until biometric unlock succeeds.
class BiometricLockOverlay extends StatefulWidget {
  final AuthStore authStore;
  final BiometricLockController lockController;

  const BiometricLockOverlay({
    super.key,
    required this.authStore,
    required this.lockController,
  });

  @override
  State<BiometricLockOverlay> createState() => _BiometricLockOverlayState();
}

class _BiometricLockOverlayState extends State<BiometricLockOverlay> {
  final BiometricAuthService _biometric = createBiometricAuthService();
  bool _authenticating = false;
  int _failedAttempts = 0;
  static const _maxAttempts = 3;

  @override
  void initState() {
    super.initState();
    widget.lockController.addListener(_onLockChanged);
    if (widget.lockController.isLocked) {
      unawaited(_authenticate());
    }
  }

  @override
  void dispose() {
    widget.lockController.removeListener(_onLockChanged);
    super.dispose();
  }

  void _onLockChanged() {
    if (!mounted) return;
    if (widget.lockController.isLocked) {
      _failedAttempts = 0;
      unawaited(_authenticate());
    }
    setState(() {});
  }

  Future<void> _authenticate() async {
    if (!widget.lockController.isLocked || _authenticating) return;
    if (!mounted) return;

    setState(() => _authenticating = true);
    final t = AppLocalizations.of(context);
    final ok = await _biometric.authenticate(reason: t.biometricLockAuthReason);
    if (!mounted) return;
    setState(() => _authenticating = false);

    if (ok) {
      _failedAttempts = 0;
      widget.lockController.unlock();
      return;
    }

    _failedAttempts++;
    if (_failedAttempts >= _maxAttempts) {
      await _signInWithPassword();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _signInWithPassword() async {
    widget.lockController.unlock();
    await widget.authStore.saveApiKey(null);
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsBiometricLock || !widget.lockController.isLocked) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final remaining = _maxAttempts - _failedAttempts;

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.fingerprint,
                    size: 88,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t.biometricLockTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.biometricLockSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_failedAttempts > 0 && remaining > 0) ...[
                    const SizedBox(height: 16),
                    Text(
                      t.biometricLockAttemptsRemaining(remaining),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _authenticating ? null : _authenticate,
                    icon: _authenticating
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.fingerprint),
                    label: Text(
                      _authenticating ? t.biometricLockAuthenticating : t.biometricLockRetry,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _authenticating ? null : _signInWithPassword,
                    child: Text(t.biometricLockSignInWithPassword),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
