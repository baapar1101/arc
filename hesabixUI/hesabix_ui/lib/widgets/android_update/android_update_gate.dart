import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/android_update_platform.dart';
import '../../core/android_update_prefs.dart';
import '../../services/android_update/android_apk_download_coordinator.dart';
import '../../services/android_update/android_update_bootstrap.dart';
import '../../services/android_update/android_update_models.dart';
import '../../services/android_update/android_update_service.dart';
import '../../services/android_update/android_update_version.dart';
import '../../utils/snackbar_helper.dart';
import 'android_update_download_sheet.dart';

/// Runs a single automatic update check after the app shell is ready (Android only).
class AndroidUpdateGate extends StatefulWidget {
  final Widget child;

  const AndroidUpdateGate({super.key, required this.child});

  @override
  State<AndroidUpdateGate> createState() => _AndroidUpdateGateState();
}

class _AndroidUpdateGateState extends State<AndroidUpdateGate>
    with WidgetsBindingObserver {
  bool _scheduled = false;
  StreamSubscription<AndroidApkDownloadSession>? _downloadSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (supportsAndroidApkUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _downloadSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_promptInstallIfReady());
    }
  }

  Future<void> _bootstrap() async {
    await initAndroidApkUpdateInfrastructure();
    _downloadSub ??=
        AndroidApkDownloadCoordinator.instance.sessions.listen((session) {
      if (session.phase == AndroidApkDownloadPhase.complete) {
        unawaited(_promptInstallIfReady());
      }
    });
    _schedule();
    await _promptInstallIfReady();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await AndroidUpdateFlow.runStartupCheck(context);
    });
  }

  Future<void> _promptInstallIfReady() async {
    if (!mounted) return;
    final session =
        await AndroidApkDownloadCoordinator.instance.consumeCompletedInstall();
    if (session == null || !mounted) return;
    final path = session.filePath;
    final release = session.release;
    if (path == null || release == null) return;

    final t = AppLocalizations.of(context);
    final install = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.download_done_rounded,
          color: Theme.of(ctx).colorScheme.primary,
          size: 36,
        ),
        title: Text(t.androidUpdateDownloadCompleteTitle),
        content: Text(
          t.androidUpdateDownloadCompleteMessage(release.version.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.androidUpdateLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.androidUpdateInstallNow),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (install == true) {
      await AndroidUpdateFlow.installDownloadedApk(context, path);
    }
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
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).androidUpdateAvailableTitle,
      );
    }

    final proceed = await _confirmUpdate(
      context,
      result,
      emphasizeAuto: autoDownload,
    );
    if (!context.mounted) return;
    if (!proceed) {
      await AndroidUpdatePrefs.setSkippedVersion(remote.tagName);
      return;
    }
    await downloadAndInstall(context, remote);
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
                  t.androidUpdateApkSizeHintBackground(
                    formatAndroidUpdateBytes(remote.apk.size),
                  ),
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
    await ensureAndroidApkDownloadPermissions();
    if (!context.mounted) return;
    configureAndroidApkDownloadNotifications(t);

    final sheetResult = await showAndroidUpdateDownloadSheet(
      context: context,
      release: remote,
      startDownload: ({
        void Function(AndroidUpdateDownloadProgress progress)? onProgress,
        bool Function()? isCancelled,
      }) {
        return _service.downloadApk(
          remote,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      },
    );

    switch (sheetResult) {
      case AndroidUpdateDownloadSheetResult.background:
        if (context.mounted) {
          SnackBarHelper.show(
            context,
            message: t.androidUpdateDownloadingBackgroundHint,
          );
        }
        return;
      case AndroidUpdateDownloadSheetResult.cancelled:
        if (context.mounted) {
          SnackBarHelper.show(
            context,
            message: t.androidUpdateDownloadCancelled,
          );
        }
        return;
      case AndroidUpdateDownloadSheetResult.failed:
        if (context.mounted) {
          SnackBarHelper.showError(
            context,
            message: t.androidUpdateDownloadFailed(
              AndroidApkDownloadCoordinator.instance.current.errorMessage ??
                  'unknown',
            ),
          );
        }
        return;
      case AndroidUpdateDownloadSheetResult.completed:
        final session = AndroidApkDownloadCoordinator.instance.current;
        final path = session.filePath;
        if (path == null) return;
        await AndroidUpdatePrefs.clearSkippedVersion();
        if (!context.mounted) return;
        await installDownloadedApk(context, path);
    }
  }

  static Future<void> installDownloadedApk(
    BuildContext context,
    String path,
  ) async {
    await _installWithPermission(context, path);
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
}
