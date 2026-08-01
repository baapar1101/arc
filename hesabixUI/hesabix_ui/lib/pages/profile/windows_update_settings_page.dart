import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/windows_update_platform.dart';
import '../../core/windows_update_prefs.dart';
import '../../services/windows_update/windows_update_models.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/windows_update/windows_update_gate.dart';

class WindowsUpdateSettingsPage extends StatefulWidget {
  const WindowsUpdateSettingsPage({super.key});

  @override
  State<WindowsUpdateSettingsPage> createState() =>
      _WindowsUpdateSettingsPageState();
}

class _WindowsUpdateSettingsPageState extends State<WindowsUpdateSettingsPage> {
  bool _loading = true;
  bool _checking = false;
  bool _busy = false;
  bool _autoCheck = true;
  bool _autoDownload = true;
  WindowsUpdateCheckResult? _result;
  DateTime? _lastCheckAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final autoCheck = await WindowsUpdatePrefs.isAutoCheckEnabled();
    final autoDownload = await WindowsUpdatePrefs.isAutoDownloadEnabled();
    final lastCheck = await WindowsUpdatePrefs.getLastCheckAt();
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
      final result = await WindowsUpdateFlow.service.checkForUpdate();
      final lastCheck = await WindowsUpdatePrefs.getLastCheckAt();
      if (!mounted) return;
      setState(() {
        _result = result;
        _lastCheckAt = lastCheck;
      });
      if (!silent && mounted) {
        final t = AppLocalizations.of(context);
        if (result.availability == WindowsUpdateAvailability.upToDate) {
          SnackBarHelper.show(context, message: t.windowsUpdateUpToDate);
        } else if (result.hasUpdate) {
          SnackBarHelper.show(
            context,
            message: t.windowsUpdateAvailableTitle,
          );
        } else if (result.availability == WindowsUpdateAvailability.unknown) {
          SnackBarHelper.showError(context, message: t.windowsUpdateCheckFailed);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      if (!silent) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: t.windowsUpdateCheckFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _onAutoCheck(bool value) async {
    await WindowsUpdatePrefs.setAutoCheckEnabled(value);
    if (mounted) setState(() => _autoCheck = value);
  }

  Future<void> _onAutoDownload(bool value) async {
    await WindowsUpdatePrefs.setAutoDownloadEnabled(value);
    if (mounted) setState(() => _autoDownload = value);
  }

  Future<void> _downloadAndInstall() async {
    final remote = _result?.remote;
    if (remote == null || _busy) return;
    setState(() => _busy = true);
    try {
      await WindowsUpdateFlow.downloadAndInstall(context, remote);
      if (mounted) await _check(silent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    if (!supportsWindowsDesktopUpdate) {
      return Scaffold(
        appBar: AppBar(title: Text(t.windowsUpdateSettingsTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t.windowsUpdateUnsupported,
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
      appBar: AppBar(title: Text(t.windowsUpdateSettingsTitle)),
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
                                t.windowsUpdateSettingsTitle,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t.windowsUpdateSettingsDescription,
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
                        leading: const Icon(Icons.desktop_windows_outlined),
                        title: Text(t.windowsUpdateInstalledVersion),
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
                        title: Text(t.windowsUpdateLatestVersion),
                        subtitle: Text(
                          remote?.version.toString() ??
                              (result?.availability ==
                                      WindowsUpdateAvailability.upToDate
                                  ? (result?.installedVersionLabel ?? '—')
                                  : '—'),
                        ),
                        trailing: hasUpdate
                            ? Chip(
                                label: Text(t.windowsUpdateAvailableBadge),
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
                      ),
                      if (_lastCheckAt != null) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule),
                          title: Text(t.windowsUpdateLastChecked),
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
                            t.windowsUpdateChangelogTitle,
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
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary:
                            const Icon(Icons.notifications_active_outlined),
                        title: Text(t.windowsUpdateAutoCheckTitle),
                        subtitle: Text(t.windowsUpdateAutoCheckSubtitle),
                        value: _autoCheck,
                        onChanged: _busy ? null : _onAutoCheck,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.download_outlined),
                        title: Text(t.windowsUpdateAutoDownloadTitle),
                        subtitle: Text(t.windowsUpdateAutoDownloadSubtitle),
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
                  label: Text(t.windowsUpdateCheckNow),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: (hasUpdate && !_busy && !_checking)
                      ? _downloadAndInstall
                      : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.install_desktop),
                  label: Text(t.windowsUpdateDownloadAndInstall),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.windowsUpdateInfoTitle,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.windowsUpdateInfoBody,
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

/// Whether to show the Windows update entry in account settings.
bool showWindowsUpdateSettingsEntry() => supportsWindowsDesktopUpdate;
