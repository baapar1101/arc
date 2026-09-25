import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../core/biometric_lock_prefs.dart';
import '../../core/biometric_platform.dart';
import '../../services/biometric_auth_service.dart';
import '../../utils/snackbar_helper.dart';

class BiometricLockSettingsPage extends StatefulWidget {
  final AuthStore authStore;

  const BiometricLockSettingsPage({super.key, required this.authStore});

  @override
  State<BiometricLockSettingsPage> createState() => _BiometricLockSettingsPageState();
}

class _BiometricLockSettingsPageState extends State<BiometricLockSettingsPage> {
  final BiometricAuthService _biometric = createBiometricAuthService();
  bool _loading = true;
  bool _enabled = false;
  bool _available = false;
  bool _saving = false;
  List<String> _biometricTypes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.authStore.currentUserId;
    final available = await _biometric.isAvailable();
    final enabled = await BiometricLockPrefs.isEnabled(userId);
    final types = available ? await _biometric.getAvailableBiometricTypes() : <String>[];

    if (!mounted) return;
    setState(() {
      _available = available;
      _enabled = enabled;
      _biometricTypes = types;
      _loading = false;
    });
  }

  Future<void> _onToggle(bool value) async {
    if (_saving) return;
    final t = AppLocalizations.of(context);
    final userId = widget.authStore.currentUserId;

    setState(() => _saving = true);
    try {
      if (value) {
        if (!_available) {
          SnackBarHelper.showError(context, message: t.biometricSettingsUnavailable);
          return;
        }
        final verified = await _biometric.authenticate(reason: t.biometricSettingsEnableReason);
        if (!verified.success) {
          if (mounted) {
            final msg = verified.canceled
                ? t.biometricSettingsEnableFailed
                : (verified.errorMessage?.isNotEmpty == true
                    ? '${t.biometricSettingsEnableFailed} (${verified.errorCode ?? ''})'
                    : t.biometricSettingsEnableFailed);
            SnackBarHelper.showError(context, message: msg);
          }
          return;
        }
        await BiometricLockPrefs.setEnabled(userId, true);
        await BiometricLockPrefs.markPrompted(userId);
      } else {
        await BiometricLockPrefs.setEnabled(userId, false);
      }

      if (!mounted) return;
      setState(() => _enabled = value);
      SnackBarHelper.show(
        context,
        message: value ? t.biometricSettingsEnabledSuccess : t.biometricSettingsDisabledSuccess,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _biometricTypeLabel(AppLocalizations t, String type) {
    switch (type) {
      case 'fingerprint':
        return t.biometricTypeFingerprint;
      case 'face':
        return t.biometricTypeFace;
      case 'iris':
        return t.biometricTypeIris;
      case 'weak':
        return t.biometricTypeWeak;
      case 'strong':
        return t.biometricTypeStrong;
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    if (!supportsBiometricLock) {
      return Scaffold(
        appBar: AppBar(title: Text(t.biometricSettingsTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t.biometricSettingsUnavailable,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.biometricSettingsTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.fingerprint, color: theme.colorScheme.primary, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t.biometricSettingsTitle,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.biometricSettingsDescription,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    title: Text(t.biometricSettingsToggleTitle),
                    subtitle: Text(
                      _available
                          ? t.biometricSettingsToggleSubtitle
                          : t.biometricSettingsUnavailable,
                    ),
                    value: _enabled,
                    onChanged: (!_available || _saving) ? null : _onToggle,
                    secondary: const Icon(Icons.fingerprint),
                  ),
                ),
                if (_biometricTypes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.biometricSettingsAvailableMethods,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _biometricTypes
                                .map(
                                  (type) => Chip(
                                    avatar: const Icon(Icons.check_circle_outline, size: 18),
                                    label: Text(_biometricTypeLabel(t, type)),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.biometricSettingsInfoTitle,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.biometricSettingsInfoBody,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Returns true when biometric settings should be visible in account settings.
bool showBiometricLockSettingsEntry() => supportsBiometricLock;
