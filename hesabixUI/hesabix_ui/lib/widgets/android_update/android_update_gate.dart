import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/android_update_platform.dart';
import '../../core/android_update_prefs.dart';
import '../../services/android_update/android_update_models.dart';
import '../../services/android_update/android_update_service.dart';
import '../../services/android_update/android_update_version.dart';
import '../../utils/snackbar_helper.dart';

/// Runs a single automatic update check after the app shell is ready (Android only).
class AndroidUpdateGate extends StatefulWidget {
  final Widget child;

  const AndroidUpdateGate({super.key, required this.child});

  @override
  State<AndroidUpdateGate> createState() => _AndroidUpdateGateState();
}

class _AndroidUpdateGateState extends State<AndroidUpdateGate> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    if (supportsAndroidApkUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
    }
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await AndroidUpdateFlow.runStartupCheck(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shared UI flows for check / download / install.
class AndroidUpdateFlow {
  AndroidUpdateFlow._();

  static final AndroidUpdateService _service = createAndroidUpdateService();

  static AndroidUpdateService get service => _service;

  static Future<void> runStartupCheck(BuildContext context) async {
    if (!supportsAndroidApkUpdate) return;
    if (!await AndroidUpdatePrefs.isAutoCheckEnabled()) return;

    final result = await _service.checkForUpdate();
    if (!context.mounted || !result.hasUpdate || result.remote == null) return;

    final remote = result.remote!;
    if (await _isSkipped(remote.version)) return;

    final autoDownload = await AndroidUpdatePrefs.isAutoDownloadEnabled();
    if (!context.mounted) return;

    if (autoDownload) {
      // In-app notification + immediate download (cancellable).
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).androidUpdateAvailableTitle,
      );
      final proceed = await _confirmUpdate(context, result, emphasizeAuto: true);
      if (!context.mounted) return;
      if (!proceed) {
        await AndroidUpdatePrefs.setSkippedVersion(remote.tagName);
        return;
      }
      await downloadAndInstall(context, remote);
    } else {
      final proceed = await _confirmUpdate(context, result, emphasizeAuto: false);
      if (!context.mounted) return;
      if (!proceed) {
        await AndroidUpdatePrefs.setSkippedVersion(remote.tagName);
        return;
      }
      await downloadAndInstall(context, remote);
    }
  }

  static Future<bool> _isSkipped(AndroidAppVersion remote) async {
    final skipped = await AndroidUpdatePrefs.getSkippedVersion();
    final skippedVer = AndroidAppVersion.tryParse(skipped);
    if (skippedVer == null) return false;
    return remote <= skippedVer;
  }

  /// Returns true if user wants to download & install.
  static Future<bool> _confirmUpdate(
    BuildContext context,
    AndroidUpdateCheckResult result, {
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
          title: Text(t.androidUpdateAvailableTitle),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.androidUpdateAvailableMessage(
                    remote.version.toString(),
                    result.installedVersionLabel ?? '—',
                  ),
                ),
                if (remote.body.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    t.androidUpdateChangelogTitle,
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(remote.body),
                ],
                if (emphasizeAuto) ...[
                  const SizedBox(height: 12),
                  Text(
                    t.androidUpdateAutoDownloadStarting,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  t.androidUpdateApkSizeHint(_formatBytes(remote.apk.size)),
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
              child: Text(t.androidUpdateLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.androidUpdateDownloadAndInstall),
            ),
          ],
        );
      },
    );

    return action == true;
  }

  /// Manual prompt from settings (same confirm → download → install).
  static Future<void> showUpdateAvailableDialog(
    BuildContext context, {
    required AndroidUpdateCheckResult result,
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
      await AndroidUpdatePrefs.setSkippedVersion(remote.tagName);
      return;
    }
    await downloadAndInstall(context, remote);
  }

  static Future<void> downloadAndInstall(
    BuildContext context,
    AndroidRemoteRelease remote,
  ) async {
    final t = AppLocalizations.of(context);
    var cancelled = false;
    final progressNotifier =
        ValueNotifier<AndroidUpdateDownloadProgress?>(null);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(t.androidUpdateDownloadingTitle),
            content: ValueListenableBuilder<AndroidUpdateDownloadProgress?>(
              valueListenable: progressNotifier,
              builder: (context, progress, _) {
                final fraction = progress?.fraction;
                final percent = progress?.percent ?? 0;
                final label = progress == null
                    ? t.androidUpdateDownloadingPreparing
                    : t.androidUpdateDownloadProgress(
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
      final path = await _service.downloadApk(
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
            message: t.androidUpdateDownloadCancelled,
          );
        }
        return;
      }

      await AndroidUpdatePrefs.clearSkippedVersion();
      if (!context.mounted) return;
      await _installWithPermission(context, path);
    } on AndroidUpdateCancelledException {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        SnackBarHelper.show(
          context,
          message: t.androidUpdateDownloadCancelled,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        SnackBarHelper.showError(
          context,
          message: t.androidUpdateDownloadFailed(e.toString()),
        );
      }
    } finally {
      progressNotifier.dispose();
    }
  }

  static Future<void> _installWithPermission(
    BuildContext context,
    String path,
  ) async {
    final t = AppLocalizations.of(context);
    try {
      final allowed = await _service.canRequestPackageInstalls();
      if (!allowed) {
        if (!context.mounted) return;
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.androidUpdatePermissionTitle),
            content: Text(t.androidUpdatePermissionMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(t.androidUpdateOpenPermissionSettings),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          await _service.openInstallPermissionSettings();
          if (!context.mounted) return;
          SnackBarHelper.show(
            context,
            message: t.androidUpdatePermissionReturnHint,
          );
          return;
        }
        return;
      }

      await _service.installApk(path);
      if (context.mounted) {
        SnackBarHelper.show(context, message: t.androidUpdateInstallStarted);
      }
    } on AndroidUpdateInstallPermissionException {
      if (context.mounted) {
        SnackBarHelper.showError(
          context,
          message: t.androidUpdatePermissionMessage,
        );
      }
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showError(
          context,
          message: t.androidUpdateInstallFailed(e.toString()),
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
