import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

import '../../core/android_update_prefs.dart';
import 'android_update_models.dart';
import 'android_update_version.dart';

/// System-managed APK download session (Android DownloadWorker / UIDT).
class AndroidApkDownloadCoordinator {
  AndroidApkDownloadCoordinator._();

  static final AndroidApkDownloadCoordinator instance =
      AndroidApkDownloadCoordinator._();

  static const apkUpdateGroup = 'hesabix_apk_update';
  static const apkUpdatesDirectory = 'apk_updates';

  final _states = StreamController<AndroidApkDownloadSession>.broadcast();
  Stream<AndroidApkDownloadSession> get sessions => _states.stream;

  final _installPromptRequests = StreamController<void>.broadcast();
  /// Fired when the user taps the completed-download notification (or UI
  /// explicitly asks to re-show the install prompt).
  Stream<void> get installPromptRequests => _installPromptRequests.stream;

  AndroidApkDownloadSession _current = const AndroidApkDownloadSession.idle();
  AndroidApkDownloadSession get current => _current;

  StreamSubscription<TaskUpdate>? _updatesSub;
  Completer<String>? _activeCompleter;
  DownloadTask? _activeTask;
  AndroidRemoteRelease? _activeRelease;
  bool _initialized = false;

  /// While > 0, auto install prompts are suppressed so a foreground sheet can
  /// own the completed path without racing the gate.
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

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await FileDownloader().start();
    FileDownloader().registerCallbacks(
      group: apkUpdateGroup,
      taskNotificationTapCallback: _onNotificationTap,
    );
    _updatesSub ??= FileDownloader().updates.listen(
      _onTaskUpdate,
      onError: (Object e, StackTrace st) {
        debugPrint('AndroidApkDownloadCoordinator updates error: $e\n$st');
      },
    );

    await _recoverActiveSession();
  }

  void requestInstallPrompt() {
    if (!_installPromptRequests.isClosed) {
      _installPromptRequests.add(null);
    }
  }

  void _onNotificationTap(Task task, NotificationType notificationType) {
    if (task.group != apkUpdateGroup) return;
    if (notificationType != NotificationType.complete) return;
    debugPrint(
      'AndroidApkDownloadCoordinator: complete notification tapped '
      '(task=${task.taskId})',
    );
    requestInstallPrompt();
  }

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
  }) {
    FileDownloader().configureNotificationForGroup(
      apkUpdateGroup,
      running: TaskNotification(runningTitle, runningBody),
      complete: TaskNotification(completeTitle, completeBody),
      error: TaskNotification(errorTitle, errorBody),
      paused: TaskNotification(pausedTitle, pausedBody),
      canceled: TaskNotification(canceledTitle, canceledBody),
      progressBar: true,
      // applicationDocuments cannot be opened via tapOpensFile; we handle taps
      // ourselves and launch the package installer through MethodChannel.
      tapOpensFile: false,
    );
  }

  Future<String> startDownload(
    AndroidRemoteRelease release, {
    void Function(AndroidUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    await initialize();
    await cancelDownload();
    await AndroidUpdatePrefs.clearReadyInstall();

    final safeName = _safeFilename(release.apk.name);
    final taskId =
        'hesabix_apk_${release.tagName.replaceAll(RegExp(r'[^\w.\-]+'), '_')}';

    final task = DownloadTask(
      taskId: taskId,
      url: release.apk.downloadUrl,
      filename: safeName,
      directory: apkUpdatesDirectory,
      baseDirectory: BaseDirectory.applicationDocuments,
      group: apkUpdateGroup,
      updates: Updates.statusAndProgress,
      allowPause: true,
      priority: 0,
      retries: 3,
      displayName: release.version.toString(),
      metaData: release.tagName,
      headers: const {
        'User-Agent': 'HesabixAndroidUpdate/1.0',
        'Accept': '*/*',
      },
    );

    _activeTask = task;
    _activeRelease = release;
    _activeCompleter = Completer<String>();

    _emit(
      AndroidApkDownloadSession(
        phase: AndroidApkDownloadPhase.downloading,
        release: release,
        progress: AndroidUpdateDownloadProgress(
          received: 0,
          total: release.apk.size,
        ),
      ),
    );

    await AndroidUpdatePrefs.setPendingDownload(
      taskId: taskId,
      releaseTag: release.tagName,
    );

    final enqueued = await FileDownloader().enqueue(task);
    if (!enqueued) {
      await AndroidUpdatePrefs.clearPendingDownload();
      _activeTask = null;
      _activeRelease = null;
      _activeCompleter = null;
      _emit(const AndroidApkDownloadSession.idle());
      throw StateError('Could not enqueue APK download');
    }

    // Progress callbacks for foreground UI.
    late final StreamSubscription<AndroidApkDownloadSession> progressSub;
    progressSub = sessions.listen((session) {
      if (isCancelled?.call() == true) {
        unawaited(cancelDownload());
        return;
      }
      final progress = session.progress;
      if (progress != null) {
        onProgress?.call(progress);
      }
      if (session.phase == AndroidApkDownloadPhase.complete &&
          session.filePath != null) {
        progressSub.cancel();
      }
    });

    try {
      return await _activeCompleter!.future;
    } on AndroidUpdateCancelledException {
      rethrow;
    } finally {
      await progressSub.cancel();
    }
  }

  Future<void> cancelDownload() async {
    final task = _activeTask;
    if (task != null) {
      await FileDownloader().cancel(task);
    } else {
      final pendingId = await AndroidUpdatePrefs.getPendingTaskId();
      if (pendingId != null) {
        final records = await FileDownloader().database.allRecords(
          group: apkUpdateGroup,
        );
        for (final record in records) {
          if (record.taskId == pendingId) {
            await FileDownloader().cancelTasksWithIds([pendingId]);
            break;
          }
        }
      }
    }

    await AndroidUpdatePrefs.clearPendingDownload();
    await AndroidUpdatePrefs.clearReadyInstall();
    _completeActive(
      AndroidApkDownloadSession(
        phase: AndroidApkDownloadPhase.cancelled,
        release: _activeRelease,
      ),
    );
  }

  /// Returns the completed session without clearing it.
  AndroidApkDownloadSession? peekCompletedInstall() {
    final session = _current;
    if (session.phase == AndroidApkDownloadPhase.complete &&
        session.filePath != null) {
      return session;
    }
    return null;
  }

  /// Clears a completed install session after install was launched or discarded.
  Future<void> clearCompletedInstall() async {
    await AndroidUpdatePrefs.clearReadyInstall();
    if (_current.phase == AndroidApkDownloadPhase.complete) {
      _activeTask = null;
      _activeRelease = null;
      _emit(const AndroidApkDownloadSession.idle());
    }
  }

  /// Prefer in-memory complete session; otherwise restore from prefs / DB.
  Future<AndroidApkDownloadSession?> resolveCompletedInstall() async {
    final current = peekCompletedInstall();
    if (current != null) {
      final path = current.filePath;
      if (path != null && await File(path).exists()) {
        return current;
      }
    }

    final readyPath = await AndroidUpdatePrefs.getReadyInstallPath();
    final readyTag = await AndroidUpdatePrefs.getReadyInstallTag();
    if (readyPath != null && await File(readyPath).exists()) {
      final session = AndroidApkDownloadSession(
        phase: AndroidApkDownloadPhase.complete,
        release: _activeRelease ??
            (readyTag != null
                ? AndroidRemoteRelease(
                    tagName: readyTag,
                    version: AndroidAppVersion.tryParse(readyTag) ??
                        AndroidAppVersion(0, 0, 0),
                    name: readyTag,
                    body: '',
                    draft: false,
                    prerelease: false,
                    publishedAt: null,
                    apk: AndroidReleaseAsset(
                      name: readyPath.split(Platform.pathSeparator).last,
                      size: await File(readyPath).length(),
                      downloadUrl: '',
                    ),
                  )
                : null),
        filePath: readyPath,
      );
      _emit(session);
      return session;
    }

    await _recoverActiveSession();
    return peekCompletedInstall();
  }

  Future<void> _recoverActiveSession() async {
    final records = await FileDownloader().database.allRecords(
      group: apkUpdateGroup,
    );

    if (records.isNotEmpty) {
      records.sort(
        (a, b) => b.task.creationTime.compareTo(a.task.creationTime),
      );
      final record = records.first;
      final task = record.task;

      switch (record.status) {
        case TaskStatus.complete:
          final path = await task.filePath();
          if (await File(path).exists()) {
            _activeTask = task as DownloadTask?;
            final release = _releaseFromTask(task);
            await AndroidUpdatePrefs.setReadyInstall(
              filePath: path,
              releaseTag: release?.tagName ?? task.metaData,
            );
            _emit(
              AndroidApkDownloadSession(
                phase: AndroidApkDownloadPhase.complete,
                release: release,
                filePath: path,
                progress: AndroidUpdateDownloadProgress(
                  received: record.expectedFileSize,
                  total: record.expectedFileSize,
                ),
              ),
            );
            return;
          }
        case TaskStatus.running:
        case TaskStatus.enqueued:
        case TaskStatus.paused:
          _activeTask = task as DownloadTask?;
          _emit(
            AndroidApkDownloadSession(
              phase: record.status == TaskStatus.paused
                  ? AndroidApkDownloadPhase.paused
                  : AndroidApkDownloadPhase.downloading,
              release: _releaseFromTask(task),
              progress: AndroidUpdateDownloadProgress(
                received: (record.progress * record.expectedFileSize).round(),
                total: record.expectedFileSize,
              ),
            ),
          );
          return;
        default:
          break;
      }
    }

    final readyPath = await AndroidUpdatePrefs.getReadyInstallPath();
    if (readyPath != null && await File(readyPath).exists()) {
      final readyTag = await AndroidUpdatePrefs.getReadyInstallTag();
      _emit(
        AndroidApkDownloadSession(
          phase: AndroidApkDownloadPhase.complete,
          release: readyTag == null
              ? null
              : AndroidRemoteRelease(
                  tagName: readyTag,
                  version: AndroidAppVersion.tryParse(readyTag) ??
                      AndroidAppVersion(0, 0, 0),
                  name: readyTag,
                  body: '',
                  draft: false,
                  prerelease: false,
                  publishedAt: null,
                  apk: AndroidReleaseAsset(
                    name: readyPath.split(Platform.pathSeparator).last,
                    size: await File(readyPath).length(),
                    downloadUrl: '',
                  ),
                ),
          filePath: readyPath,
        ),
      );
      return;
    }

    await AndroidUpdatePrefs.clearPendingDownload();
    if (_current.phase != AndroidApkDownloadPhase.complete) {
      _emit(const AndroidApkDownloadSession.idle());
    }
  }

  AndroidRemoteRelease? _releaseFromTask(Task task) {
    final tag = task.metaData;
    if (tag.isEmpty) return _activeRelease;
    return _activeRelease ??
        AndroidRemoteRelease(
          tagName: tag,
          version: AndroidAppVersion.tryParse(tag) ?? AndroidAppVersion(0, 0, 0),
          name: task.displayName,
          body: '',
          draft: false,
          prerelease: false,
          publishedAt: null,
          apk: AndroidReleaseAsset(
            name: task.filename,
            size: 0,
            downloadUrl: task.url,
          ),
        );
  }

  Future<void> _onTaskUpdate(TaskUpdate update) async {
    if (update.task.group != apkUpdateGroup) return;

    final task = update.task;
    if (task is! DownloadTask) return;

    _activeTask ??= task;

    switch (update) {
      case TaskProgressUpdate():
        final total = update.expectedFileSize;
        final received = (update.progress * total).round();
        _emit(
          AndroidApkDownloadSession(
            phase: _current.phase == AndroidApkDownloadPhase.paused
                ? AndroidApkDownloadPhase.paused
                : AndroidApkDownloadPhase.downloading,
            release: _activeRelease ?? _releaseFromTask(task),
            progress: AndroidUpdateDownloadProgress(
              received: received,
              total: total,
            ),
          ),
        );
      case TaskStatusUpdate():
        await _handleStatus(task, update.status, update.exception);
    }
  }

  Future<void> _handleStatus(
    DownloadTask task,
    TaskStatus status,
    Object? exception,
  ) async {
    switch (status) {
      case TaskStatus.running:
      case TaskStatus.enqueued:
      case TaskStatus.waitingToRetry:
        _emit(
          AndroidApkDownloadSession(
            phase: AndroidApkDownloadPhase.downloading,
            release: _activeRelease ?? _releaseFromTask(task),
            progress: _current.progress,
          ),
        );
        return;
      case TaskStatus.paused:
        _emit(
          AndroidApkDownloadSession(
            phase: AndroidApkDownloadPhase.paused,
            release: _activeRelease ?? _releaseFromTask(task),
            progress: _current.progress,
          ),
        );
        return;
      case TaskStatus.complete:
        final path = await task.filePath();
        await AndroidUpdatePrefs.clearPendingDownload();
        final release = _activeRelease ?? _releaseFromTask(task);
        if (release != null) {
          await AndroidUpdatePrefs.setReadyInstall(
            filePath: path,
            releaseTag: release.tagName,
          );
        } else {
          await AndroidUpdatePrefs.setReadyInstall(
            filePath: path,
            releaseTag: task.metaData,
          );
        }
        final session = AndroidApkDownloadSession(
          phase: AndroidApkDownloadPhase.complete,
          release: release,
          filePath: path,
          progress: AndroidUpdateDownloadProgress(
            received: _current.progress?.total ?? 0,
            total: _current.progress?.total ?? 0,
          ),
        );
        _completeActive(session, path: path);
        return;
      case TaskStatus.canceled:
        await AndroidUpdatePrefs.clearPendingDownload();
        await AndroidUpdatePrefs.clearReadyInstall();
        _completeActive(
          AndroidApkDownloadSession(
            phase: AndroidApkDownloadPhase.cancelled,
            release: _activeRelease ?? _releaseFromTask(task),
          ),
          error: AndroidUpdateCancelledException(),
        );
        return;
      case TaskStatus.failed:
      case TaskStatus.notFound:
        await AndroidUpdatePrefs.clearPendingDownload();
        await AndroidUpdatePrefs.clearReadyInstall();
        _completeActive(
          AndroidApkDownloadSession(
            phase: AndroidApkDownloadPhase.failed,
            release: _activeRelease ?? _releaseFromTask(task),
            errorMessage: exception?.toString() ?? status.name,
          ),
          error: StateError(exception?.toString() ?? 'Download failed'),
        );
        return;
    }
  }

  void _completeActive(
    AndroidApkDownloadSession session, {
    String? path,
    Object? error,
  }) {
    _emit(session);
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      if (error is AndroidUpdateCancelledException) {
        completer.completeError(error);
      } else if (error != null) {
        completer.completeError(error);
      } else if (path != null) {
        completer.complete(path);
      }
    }
    if (session.phase.isTerminal) {
      _activeCompleter = null;
      if (session.phase != AndroidApkDownloadPhase.complete) {
        _activeTask = null;
        _activeRelease = null;
      }
    }
  }

  void _emit(AndroidApkDownloadSession session) {
    _current = session;
    if (!_states.isClosed) {
      _states.add(session);
    }
  }

  String _safeFilename(String name) =>
      name.replaceAll(RegExp(r'[^\w.\-]+'), '_');

  Future<void> dispose() async {
    await _updatesSub?.cancel();
    await _states.close();
    await _installPromptRequests.close();
  }
}
