import 'dart:async';

import 'android_update_models.dart';

/// No-op APK download coordinator for web (no `dart:io` / isolates).
class AndroidApkDownloadCoordinator {
  AndroidApkDownloadCoordinator._();

  static final AndroidApkDownloadCoordinator instance =
      AndroidApkDownloadCoordinator._();

  static const apkUpdateGroup = 'hesabix_apk_update';
  static const apkUpdatesDirectory = 'apk_updates';

  final _states = StreamController<AndroidApkDownloadSession>.broadcast();
  Stream<AndroidApkDownloadSession> get sessions => _states.stream;

  final _installPromptRequests = StreamController<void>.broadcast();
  Stream<void> get installPromptRequests => _installPromptRequests.stream;

  AndroidApkDownloadSession _current = const AndroidApkDownloadSession.idle();
  AndroidApkDownloadSession get current => _current;

  int _foregroundInstallFlowDepth = 0;

  bool get isForegroundInstallFlowActive => _foregroundInstallFlowDepth > 0;

  void beginForegroundInstallFlow() {
    _foregroundInstallFlowDepth++;
  }

  void endForegroundInstallFlow() {
    if (_foregroundInstallFlowDepth > 0) {
      _foregroundInstallFlowDepth--;
    }
  }

  Future<void> initialize() async {}

  void requestInstallPrompt() {}

  void configureNotifications({
    required String runningTitle,
    required String runningBody,
    required String completeTitle,
    required String completeBody,
    required String errorTitle,
    required String errorBody,
    required String pausedTitle,
    required String pausedBody,
    required String canceledTitle,
    required String canceledBody,
  }) {}

  Future<String> startDownload(
    AndroidRemoteRelease release, {
    void Function(AndroidUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) {
    throw UnsupportedError(
      'Android APK update is not supported on this platform',
    );
  }

  Future<void> cancelDownload() async {}

  AndroidApkDownloadSession? peekCompletedInstall() {
    final session = _current;
    if (session.phase == AndroidApkDownloadPhase.complete &&
        session.filePath != null) {
      return session;
    }
    return null;
  }

  Future<void> clearCompletedInstall() async {
    if (_current.phase == AndroidApkDownloadPhase.complete) {
      _current = const AndroidApkDownloadSession.idle();
    }
  }

  Future<AndroidApkDownloadSession?> resolveCompletedInstall() async =>
      peekCompletedInstall();

  Future<void> dispose() async {
    await _states.close();
    await _installPromptRequests.close();
  }
}
