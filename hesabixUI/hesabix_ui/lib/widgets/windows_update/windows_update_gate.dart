import 'package:flutter/material.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/windows_update_platform.dart';
import '../../core/windows_update_prefs.dart';
import '../../services/app_update/app_release_version.dart';
import '../../services/windows_update/windows_update_models.dart';
import '../../services/windows_update/windows_update_service.dart';
import '../../utils/snackbar_helper.dart';

/// Runs a single automatic update check after the app shell is ready (Windows only).
class WindowsUpdateGate extends StatefulWidget {
  final Widget child;

  const WindowsUpdateGate({super.key, required this.child});

  @override
  State<WindowsUpdateGate> createState() => _WindowsUpdateGateState();
}

class _WindowsUpdateGateState extends State<WindowsUpdateGate> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    if (supportsWindowsDesktopUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
    }
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await WindowsUpdateFlow.runStartupCheck(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shared UI flows for check / download / install on Windows.
class WindowsUpdateFlow {
  WindowsUpdateFlow._();

  static final WindowsUpdateService _service = createWindowsUpdateService();

  static WindowsUpdateService get service => _service;

  static Future<void> runStartupCheck(BuildContext context) async {
    if (!supportsWindowsDesktopUpdate) return;
    if (!await WindowsUpdatePrefs.isAutoCheckEnabled()) return;

    final result = await _service.checkForUpdate();
    if (!context.mounted || !result.hasUpdate || result.remote == null) return;

    final remote = result.remote!;
    if (await _isSkipped(remote.version)) return;

    final autoDownload = await WindowsUpdatePrefs.isAutoDownloadEnabled();
    if (!context.mounted) return;

    if (autoDownload) {
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).windowsUpdateAvailableTitle,
      );
      final proceed = await _confirmUpdate(context, result, emphasizeAuto: true);
      if (!context.mounted) return;
      if (!proceed) {
        await WindowsUpdatePrefs.setSkippedVersion(remote.tagName);
        return;
      }
      await downloadAndInstall(context, remote);
    } else {
      final proceed =
          await _confirmUpdate(context, result, emphasizeAuto: false);
      if (!context.mounted) return;
      if (!proceed) {
        await WindowsUpdatePrefs.setSkippedVersion(remote.tagName);
        return;
      }
      await downloadAndInstall(context, remote);
    }
  }

  static Future<bool> _isSkipped(AppReleaseVersion remote) async {
    final skipped = await WindowsUpdatePrefs.getSkippedVersion();
    final skippedVer = AppReleaseVersion.tryParse(skipped);
    if (skippedVer == null) return false;
    return remote <= skippedVer;
  }

  static Future<bool> _confirmUpdate(
    BuildContext context,
    WindowsUpdateCheckResult result, {
    required bool emphasizeAuto,
  }) async {
    final remote = result.remote!;
    final t = AppLocalizations.of(context);

    final action = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          icon: Icon(
            Icons.system_update_alt,
            color: Theme.of(ctx).colorScheme.primary,
            size: 36,
          ),
          title: Text(t.windowsUpdateAvailableTitle),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.windowsUpdateAvailableMessage(
                    remote.version.toString(),
                    result.installedVersionLabel ?? '—',
                  ),
                ),
                if (remote.body.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    t.windowsUpdateChangelogTitle,
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(remote.body),
                ],
                if (emphasizeAuto) ...[
                  const SizedBox(height: 12),
                  Text(
                    t.windowsUpdateAutoDownloadStarting,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  t.windowsUpdateInstallerSizeHint(
                    _formatBytes(remote.installer.size),
                  ),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.windowsUpdateInstallWillCloseApp,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.windowsUpdateLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.windowsUpdateDownloadAndInstall),
            ),
          ],
        );
      },
    );

    return action == true;
  }

  static Future<void> showUpdateAvailableDialog(
    BuildContext context, {
    required WindowsUpdateCheckResult result,
    bool autoStartDownload = false,
  }) async {
    final remote = result.remote;
    if (remote == null) return;

    final proceed = await _confirmUpdate(
      context,
      result,
      emphasizeAuto: autoStartDownload,
    );
    if (!context.mounted) return;
    if (!proceed) {
      await WindowsUpdatePrefs.setSkippedVersion(remote.tagName);
      return;
    }
    await downloadAndInstall(context, remote);
  }

  static Future<void> downloadAndInstall(
    BuildContext context,
    WindowsRemoteRelease remote,
  ) async {
    final t = AppLocalizations.of(context);
    var cancelled = false;
    final progressNotifier =
        ValueNotifier<WindowsUpdateDownloadProgress?>(null);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(t.windowsUpdateDownloadingTitle),
            content: ValueListenableBuilder<WindowsUpdateDownloadProgress?>(
              valueListenable: progressNotifier,
              builder: (context, progress, _) {
                final fraction = progress?.fraction;
                final percent = progress?.percent ?? 0;
                final label = progress == null
                    ? t.windowsUpdateDownloadingPreparing
                    : t.windowsUpdateDownloadProgress(
                        percent,
                        _formatBytes(progress.received),
                        progress.total > 0
                            ? _formatBytes(progress.total)
                            : '—',
                      );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fraction != null)
                      LinearProgressIndicator(value: fraction)
                    else
                      const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(label, textAlign: TextAlign.center),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  _service.cancelDownload();
                },
                child: Text(t.cancel),
              ),
            ],
          ),
        );
      },
    );

    try {
      final path = await _service.downloadInstaller(
        remote,
        onProgress: (p) {
          progressNotifier.value = p;
        },
        isCancelled: () => cancelled,
      );

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (cancelled) {
        if (context.mounted) {
          SnackBarHelper.show(
            context,
            message: t.windowsUpdateDownloadCancelled,
          );
        }
        return;
      }

      await WindowsUpdatePrefs.clearSkippedVersion();
      if (!context.mounted) return;
      await _launchAndExit(context, path, isMsi: remote.installer.isMsi);
    } on WindowsUpdateCancelledException {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        SnackBarHelper.show(
          context,
          message: t.windowsUpdateDownloadCancelled,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        SnackBarHelper.showError(
          context,
          message: t.windowsUpdateDownloadFailed(e.toString()),
        );
      }
    } finally {
      progressNotifier.dispose();
    }
  }

  static Future<void> _launchAndExit(
    BuildContext context,
    String path, {
    required bool isMsi,
  }) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t.windowsUpdateReadyToInstallTitle),
        content: Text(t.branded(t.windowsUpdateReadyToInstallMessage)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.windowsUpdateLaunchInstaller),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await _service.launchInstaller(path, isMsi: isMsi);
      if (context.mounted) {
        SnackBarHelper.show(context, message: t.windowsUpdateInstallStarted);
      }
      // Give the installer a moment to start, then quit so files can be replaced.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      _service.quitAppForInstaller();
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(
          context,
          message: t.windowsUpdateInstallFailed(e.toString()),
        );
      }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}
