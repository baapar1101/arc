import 'android_update_models.dart';

/// Stub for non-IO platforms (web). Never performs network or install.
class AndroidUpdateService {
  Future<AndroidUpdateCheckResult> checkForUpdate() async {
    return const AndroidUpdateCheckResult(
      availability: AndroidUpdateAvailability.unsupported,
    );
  }

  Future<String> downloadApk(
    AndroidRemoteRelease release, {
    void Function(AndroidUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) {
    throw UnsupportedError('Android APK update is not supported on this platform');
  }

  Future<bool> canRequestPackageInstalls() async => false;

  Future<void> openInstallPermissionSettings() async {}

  Future<void> installApk(String filePath) {
    throw UnsupportedError('Android APK update is not supported on this platform');
  }

  Future<void> cancelDownload() async {}
}

AndroidUpdateService createAndroidUpdateService() => AndroidUpdateService();
