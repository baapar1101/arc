import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/android_update_platform.dart';
import '../../core/android_update_prefs.dart';
import 'android_update_models.dart';
import 'android_update_version.dart';

/// Forgejo-backed Android APK update (check / download / install).
class AndroidUpdateService {
  static const forgejoApiBase = 'https://source.hesabix.ir/api/v1';
  static const owner = 'hesabix';
  static const repo = 'arc';
  static const _channelName = 'ir.hsxn.hesabix_ui/apk_installer';

  final Dio _dio;
  final MethodChannel _channel;
  CancelToken? _downloadCancel;

  AndroidUpdateService({
    Dio? dio,
    MethodChannel? channel,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(minutes: 30),
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'HesabixAndroidUpdate/1.0',
                },
              ),
            ),
        _channel = channel ?? const MethodChannel(_channelName);

  Future<AndroidUpdateCheckResult> checkForUpdate() async {
    if (!supportsAndroidApkUpdate) {
      return const AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.unsupported,
      );
    }

    final info = await PackageInfo.fromPlatform();
    final installedLabel = info.version;
    final installed = AndroidAppVersion.tryParse(installedLabel);

    try {
      final remote = await _fetchLatestRelease();
      await AndroidUpdatePrefs.setLastCheckNow();

      if (remote == null) {
        return AndroidUpdateCheckResult(
          availability: AndroidUpdateAvailability.unknown,
          installedVersion: installed,
          installedVersionLabel: installedLabel,
        );
      }

      if (installed == null) {
        // Cannot compare; treat as update available so user can still upgrade
        // after aligning versionName with Forgejo tags.
        return AndroidUpdateCheckResult(
          availability: AndroidUpdateAvailability.updateAvailable,
          installedVersion: null,
          installedVersionLabel: installedLabel,
          remote: remote,
        );
      }

      if (remote.version > installed) {
        return AndroidUpdateCheckResult(
          availability: AndroidUpdateAvailability.updateAvailable,
          installedVersion: installed,
          installedVersionLabel: installedLabel,
          remote: remote,
        );
      }

      return AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.upToDate,
        installedVersion: installed,
        installedVersionLabel: installedLabel,
        remote: remote,
      );
    } catch (e, st) {
      debugPrint('AndroidUpdateService.checkForUpdate failed: $e\n$st');
      return AndroidUpdateCheckResult(
        availability: AndroidUpdateAvailability.unknown,
        installedVersion: installed,
        installedVersionLabel: installedLabel,
      );
    }
  }

  Future<AndroidRemoteRelease?> _fetchLatestRelease() async {
    final url = '$forgejoApiBase/repos/$owner/$repo/releases/latest';
    final res = await _dio.get<Map<String, dynamic>>(url);
    final data = res.data;
    if (data == null) return null;
    return _parseRelease(data);
  }

  AndroidRemoteRelease? _parseRelease(Map<String, dynamic> data) {
    final draft = data['draft'] == true;
    final prerelease = data['prerelease'] == true;
    if (draft || prerelease) return null;

    final tagName = (data['tag_name'] ?? '').toString().trim();
    final version = AndroidAppVersion.tryParse(tagName);
    if (version == null) return null;

    final assetsRaw = data['assets'];
    if (assetsRaw is! List) return null;

    final assets = <AndroidReleaseAsset>[];
    for (final item in assetsRaw) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString();
      final downloadUrl = (item['browser_download_url'] ?? '').toString();
      if (!name.toLowerCase().endsWith('.apk') || downloadUrl.isEmpty) {
        continue;
      }
      final size = item['size'] is int
          ? item['size'] as int
          : int.tryParse('${item['size']}') ?? 0;
      assets.add(
        AndroidReleaseAsset(name: name, size: size, downloadUrl: downloadUrl),
      );
    }
    if (assets.isEmpty) return null;

    assets.sort((a, b) {
      final ap = a.name.toLowerCase().contains('app-release') ? 0 : 1;
      final bp = b.name.toLowerCase().contains('app-release') ? 0 : 1;
      return ap.compareTo(bp);
    });
    final apk = assets.first;

    DateTime? publishedAt;
    final publishedRaw = data['published_at']?.toString();
    if (publishedRaw != null && publishedRaw.isNotEmpty) {
      publishedAt = DateTime.tryParse(publishedRaw);
    }

    return AndroidRemoteRelease(
      tagName: tagName,
      version: version,
      name: (data['name'] ?? tagName).toString(),
      body: (data['body'] ?? '').toString().trim(),
      draft: draft,
      prerelease: prerelease,
      publishedAt: publishedAt,
      apk: apk,
    );
  }

  Future<String> downloadApk(
    AndroidRemoteRelease release, {
    void Function(AndroidUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!supportsAndroidApkUpdate) {
      throw UnsupportedError('Android APK update is not supported on this platform');
    }

    await cancelDownload();
    _downloadCancel = CancelToken();

    final dir = await getTemporaryDirectory();
    final updatesDir = Directory('${dir.path}/apk_updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }

    final safeName = release.apk.name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final savePath = '${updatesDir.path}/$safeName';

    // Remove stale file with same name.
    final existing = File(savePath);
    if (await existing.exists()) {
      await existing.delete();
    }

    try {
      await _dio.download(
        release.apk.downloadUrl,
        savePath,
        cancelToken: _downloadCancel,
        onReceiveProgress: (received, total) {
          if (isCancelled?.call() == true) {
            _downloadCancel?.cancel('cancelled');
            return;
          }
          onProgress?.call(
            AndroidUpdateDownloadProgress(received: received, total: total),
          );
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || isCancelled?.call() == true) {
        try {
          await File(savePath).delete();
        } catch (_) {}
        throw AndroidUpdateCancelledException();
      }
      rethrow;
    } finally {
      _downloadCancel = null;
    }

    final file = File(savePath);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('Downloaded APK is missing or empty');
    }
    return savePath;
  }

  Future<void> cancelDownload() async {
    final token = _downloadCancel;
    if (token != null && !token.isCancelled) {
      token.cancel('cancelled');
    }
    _downloadCancel = null;
  }

  Future<bool> canRequestPackageInstalls() async {
    if (!supportsAndroidApkUpdate) return false;
    try {
      final result = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return result ?? false;
    } catch (e) {
      debugPrint('canRequestPackageInstalls failed: $e');
      return false;
    }
  }

  Future<void> openInstallPermissionSettings() async {
    if (!supportsAndroidApkUpdate) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  Future<void> installApk(String filePath) async {
    if (!supportsAndroidApkUpdate) {
      throw UnsupportedError('Android APK update is not supported on this platform');
    }
    final allowed = await canRequestPackageInstalls();
    if (!allowed) {
      throw AndroidUpdateInstallPermissionException();
    }
    await _channel.invokeMethod<void>('installApk', {'filePath': filePath});
  }
}

AndroidUpdateService createAndroidUpdateService() => AndroidUpdateService();
