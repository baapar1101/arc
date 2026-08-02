import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../core/android_update_platform.dart';
import 'android_apk_download_coordinator.dart';

/// Initializes Android APK background download infrastructure.
Future<void> initAndroidApkUpdateInfrastructure() async {
  if (!supportsAndroidApkUpdate) return;
  await AndroidApkDownloadCoordinator.instance.initialize();
}

Future<void> ensureAndroidApkDownloadPermissions() async {
  if (!supportsAndroidApkUpdate) return;
  await Permission.notification.request();
}

void configureAndroidApkDownloadNotifications(AppLocalizations t) {
  if (!supportsAndroidApkUpdate) return;
  AndroidApkDownloadCoordinator.instance.configureNotifications(
    runningTitle: t.androidUpdateBackgroundNotificationRunning,
    runningBody: '{displayName} — {progress}%',
    completeTitle: t.androidUpdateBackgroundNotificationComplete,
    completeBody: '{displayName}',
    errorTitle: t.androidUpdateBackgroundNotificationError,
    errorBody: '{filename}',
    pausedTitle: t.androidUpdateBackgroundNotificationPaused,
    pausedBody: '{filename}',
    canceledTitle: t.androidUpdateBackgroundNotificationCanceled,
    canceledBody: '{filename}',
  );
}
