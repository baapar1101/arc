import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/android_update_platform.dart';
import '../../core/android_update_prefs.dart';
import '../../services/android_update/android_apk_download_coordinator.dart';
import '../../services/android_update/android_update_models.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/android_update/android_update_download_sheet.dart';
import '../../widgets/android_update/android_update_gate.dart';

class AndroidUpdateSettingsPage extends StatefulWidget {
  const AndroidUpdateSettingsPage({super.key});

  @override
  State<AndroidUpdateSettingsPage> createState() =>
      _AndroidUpdateSettingsPageState();
}

class _AndroidUpdateSettingsPageState extends State<AndroidUpdateSettingsPage> {
  bool _loading = true;
  bool _checking = false;
  bool _busy = false;
  bool _autoCheck = true;
  bool _autoDownload = true;
  AndroidUpdateCheckResult? _result;
  DateTime? _lastCheckAt;
  String? _error;
  StreamSubscription<AndroidApkDownloadSession>? _downloadSub;
  AndroidApkDownloadSession _downloadSession =
      const AndroidApkDownloadSession.idle();

  @override
  void initState() {
    super.initState();
    _downloadSession = AndroidApkDownloadCoordinator.instance.current;
    _downloadSub =
        AndroidApkDownloadCoordinator.instance.sessions.listen((session) {
      if (!mounted) return;
      setState(() => _downloadSession = session);
    });
    _load();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final autoCheck = await AndroidUpdatePrefs.isAutoCheckEnabled();
    final autoDownload = await AndroidUpdatePrefs.isAutoDownloadEnabled();
    final lastCheck = await AndroidUpdatePrefs.getLastCheckAt();
    if (!mounted) return;
    setState(() {
      _autoCheck = autoCheck;
      _autoDownload = autoDownload;
      _lastCheckAt = lastCheck;
      _loading = false;
    });
    await _check(silent: true);
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      if (!silent) _error = null;
    });
    try {
      final result = await AndroidUpdateFlow.service.checkForUpdate();
      final lastCheck = await AndroidUpdatePrefs.getLastCheckAt();
      if (!mounted) return;
      setState(() {
        _result = result;
        _lastCheckAt = lastCheck;
      });
      if (!silent && mounted) {
        final t = AppLocalizations.of(context);
        if (result.availability == AndroidUpdateAvailability.upToDate) {
          SnackBarHelper.show(context, message: t.androidUpdateUpToDate);
        } else if (result.hasUpdate) {
          SnackBarHelper.show(
            context,
            message: t.androidUpdateAvailableTitle,
          );
        } else if (result.availability == AndroidUpdateAvailability.unknown) {
          SnackBarHelper.showError(context, message: t.androidUpdateCheckFailed);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      if (!silent) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: t.androidUpdateCheckFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _onAutoCheck(bool value) async {
    await AndroidUpdatePrefs.setAutoCheckEnabled(value);
    if (mounted) setState(() => _autoCheck = value);
  }

  Future<void> _onAutoDownload(bool value) async {
    await AndroidUpdatePrefs.setAutoDownloadEnabled(value);
    if (mounted) setState(() => _autoDownload = value);
  }

  Future<void> _downloadAndInstall() async {
    final remote = _result?.remote;
    if (remote == null || _busy) return;
    setState(() => _busy = true);
    try {
      await AndroidUpdateFlow.downloadAndInstall(context, remote);
      if (mounted) await _check(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPermissionSettings() async {
    await AndroidUpdateFlow.service.openInstallPermissionSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    if (!supportsAndroidApkUpdate) {
      return Scaffold(
        appBar: AppBar(title: Text(t.androidUpdateSettingsTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t.androidUpdateUnsupported,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    final result = _result;
    final remote = result?.remote;
    final hasUpdate = result?.hasUpdate == true;

    return Scaffold(
      appBar: AppBar(title: Text(t.androidUpdateSettingsTitle)),
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
                            Icon(
                              Icons.system_update_alt,
                              color: theme.colorScheme.primary,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t.androidUpdateSettingsTitle,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.androidUpdateSettingsDescription,
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
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.phone_android),
                        title: Text(t.androidUpdateInstalledVersion),
                        subtitle: Text(
                          result?.installedVersionLabel ??
                              result?.installedVersion?.toString() ??
                              '—',
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          hasUpdate
                              ? Icons.new_releases
                              : Icons.verified_outlined,
                          color: hasUpdate
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(t.androidUpdateLatestVersion),
                        subtitle: Text(
                          remote?.version.toString() ??
                              (result?.availability ==
                                      AndroidUpdateAvailability.upToDate
                                  ? (result?.installedVersionLabel ?? '—')
                                  : '—'),
                        ),
                        trailing: hasUpdate
                            ? Chip(
                                label: Text(t.androidUpdateAvailableBadge),
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
                      ),
                      if (_lastCheckAt != null) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule),
                          title: Text(t.androidUpdateLastChecked),
                          subtitle: Text(
                            DateFormat.yMMMd()
                                .add_Hm()
                                .format(_lastCheckAt!.toLocal()),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (remote != null && remote.body.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.androidUpdateChangelogTitle,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(remote.body),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ),
                ],
                if (_downloadSession.isActive) ...[
                  const SizedBox(height: 12),
                  _buildActiveDownloadCard(theme, t),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_active_outlined),
                        title: Text(t.androidUpdateAutoCheckTitle),
                        subtitle: Text(t.androidUpdateAutoCheckSubtitle),
                        value: _autoCheck,
                        onChanged: _busy ? null : _onAutoCheck,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.download_outlined),
                        title: Text(t.androidUpdateAutoDownloadTitle),
                        subtitle: Text(t.androidUpdateAutoDownloadSubtitle),
                        value: _autoDownload,
                        onChanged: _busy ? null : _onAutoDownload,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (_checking || _busy) ? null : () => _check(),
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(t.androidUpdateCheckNow),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed:
                      (hasUpdate && !_busy && !_checking) ? _downloadAndInstall : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.install_mobile),
                  label: Text(t.androidUpdateDownloadAndInstall),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openPermissionSettings,
                  icon: const Icon(Icons.settings_applications),
                  label: Text(t.androidUpdateOpenPermissionSettings),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.androidUpdateInfoTitle,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.androidUpdateInfoBody,
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

  Widget _buildActiveDownloadCard(ThemeData theme, AppLocalizations t) {
    final progress = _downloadSession.progress;
    final fraction = progress?.fraction;
    final version = _downloadSession.release?.version.toString() ?? '—';

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.androidUpdateDownloadingSheetTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  version,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: fraction, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Text(
              progress == null
                  ? t.androidUpdateDownloadingPreparing
                  : t.androidUpdateDownloadProgress(
                      progress.percent,
                      formatAndroidUpdateBytes(progress.received),
                      progress.total > 0
                          ? formatAndroidUpdateBytes(progress.total)
                          : '—',
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.androidUpdateDownloadingBackgroundHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether to show the update entry in account settings.
bool showAndroidUpdateSettingsEntry() => supportsAndroidApkUpdate;
