import 'windows_update_models.dart';

/// Web / non-IO stub — never performs Windows installer OTA.
class WindowsUpdateService {
  Future<WindowsUpdateCheckResult> checkForUpdate() async {
    return const WindowsUpdateCheckResult(
      availability: WindowsUpdateAvailability.unsupported,
    );
  }

  Future<String> downloadInstaller(
    WindowsRemoteRelease release, {
    void Function(WindowsUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    throw UnsupportedError('Windows update is not supported on this platform');
  }

  Future<void> cancelDownload() async {}

  Future<void> launchInstaller(String filePath, {required bool isMsi}) async {
    throw UnsupportedError('Windows update is not supported on this platform');
  }

  /// No-op on web / non-IO.
  void quitAppForInstaller() {}
}

WindowsUpdateService createWindowsUpdateService() => WindowsUpdateService();
