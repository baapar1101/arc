import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/windows_update_platform.dart';
import '../../core/windows_update_prefs.dart';
import '../app_update/app_release_version.dart';
import 'windows_update_models.dart';

/// Forgejo-backed Windows installer update (check / download / launch MSI or setup EXE).
///
/// Shares the same release tags as Android; picks only Windows assets so Android-only
/// releases never trigger a Windows update prompt.
class WindowsUpdateService {
  static const forgejoApiBase = 'https://source.hesabix.ir/api/v1';
  static const owner = 'hesabix';
  static const repo = 'arc';

  final Dio _dio;
  CancelToken? _downloadCancel;

  WindowsUpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(minutes: 45),
                headers: const {
                  'Accept': 'application/json',
                  'User-Agent': 'HesabixWindowsUpdate/1.0',
                },
              ),
            );

  Future<WindowsUpdateCheckResult> checkForUpdate() async {
    if (!supportsWindowsDesktopUpdate) {
      return const WindowsUpdateCheckResult(
        availability: WindowsUpdateAvailability.unsupported,
      );
    }

    final info = await PackageInfo.fromPlatform();
    final installedLabel = info.version;
    final installed = AppReleaseVersion.tryParse(installedLabel);

    try {
      final parsed = await _fetchLatestRelease();
      await WindowsUpdatePrefs.setLastCheckNow();

      if (parsed == null) {
        return WindowsUpdateCheckResult(
          availability: WindowsUpdateAvailability.unknown,
          installedVersion: installed,
          installedVersionLabel: installedLabel,
        );
      }

      final tagVersion = parsed.version;
      final installer = parsed.installer;

      // Newer Forgejo tag without a Windows package → not actionable on Windows.
      if (installer == null) {
        if (installed != null && tagVersion <= installed) {
          return WindowsUpdateCheckResult(
            availability: WindowsUpdateAvailability.upToDate,
            installedVersion: installed,
            installedVersionLabel: installedLabel,
          );
        }
        return WindowsUpdateCheckResult(
          availability: WindowsUpdateAvailability.upToDate,
          installedVersion: installed,
          installedVersionLabel: installedLabel,
        );
      }

      final remote = WindowsRemoteRelease(
        tagName: parsed.tagName,
        version: tagVersion,
        name: parsed.name,
        body: parsed.body,
        draft: parsed.draft,
        prerelease: parsed.prerelease,
        publishedAt: parsed.publishedAt,
        installer: installer,
      );

      if (installed == null) {
        return WindowsUpdateCheckResult(
          availability: WindowsUpdateAvailability.updateAvailable,
          installedVersion: null,
          installedVersionLabel: installedLabel,
          remote: remote,
        );
      }

      if (tagVersion > installed) {
        return WindowsUpdateCheckResult(
          availability: WindowsUpdateAvailability.updateAvailable,
          installedVersion: installed,
          installedVersionLabel: installedLabel,
          remote: remote,
        );
      }

      return WindowsUpdateCheckResult(
        availability: WindowsUpdateAvailability.upToDate,
        installedVersion: installed,
        installedVersionLabel: installedLabel,
        remote: remote,
      );
    } catch (e, st) {
      debugPrint('WindowsUpdateService.checkForUpdate failed: $e\n$st');
      return WindowsUpdateCheckResult(
        availability: WindowsUpdateAvailability.unknown,
        installedVersion: installed,
        installedVersionLabel: installedLabel,
      );
    }
  }

  Future<_ParsedForgejoRelease?> _fetchLatestRelease() async {
    final url = '$forgejoApiBase/repos/$owner/$repo/releases/latest';
    final res = await _dio.get<Map<String, dynamic>>(url);
    final data = res.data;
    if (data == null) return null;
    return _parseRelease(data);
  }

  _ParsedForgejoRelease? _parseRelease(Map<String, dynamic> data) {
    final draft = data['draft'] == true;
    final prerelease = data['prerelease'] == true;
    if (draft || prerelease) return null;

    final tagName = (data['tag_name'] ?? '').toString().trim();
    final version = AppReleaseVersion.tryParse(tagName);
    if (version == null) return null;

    final assetsRaw = data['assets'];
    final assets = <WindowsReleaseAsset>[];
    if (assetsRaw is List) {
      for (final item in assetsRaw) {
        if (item is! Map) continue;
        final name = (item['name'] ?? '').toString();
        final downloadUrl = (item['browser_download_url'] ?? '').toString();
        if (downloadUrl.isEmpty) continue;
        if (!_looksLikeWindowsInstaller(name)) continue;
        final size = item['size'] is int
            ? item['size'] as int
            : int.tryParse('${item['size']}') ?? 0;
        assets.add(
          WindowsReleaseAsset(name: name, size: size, downloadUrl: downloadUrl),
        );
      }
    }

    assets.sort((a, b) => _assetRank(a).compareTo(_assetRank(b)));

    DateTime? publishedAt;
    final publishedRaw = data['published_at']?.toString();
    if (publishedRaw != null && publishedRaw.isNotEmpty) {
      publishedAt = DateTime.tryParse(publishedRaw);
    }

    return _ParsedForgejoRelease(
      tagName: tagName,
      version: version,
      name: (data['name'] ?? tagName).toString(),
      body: (data['body'] ?? '').toString().trim(),
      draft: draft,
      prerelease: prerelease,
      publishedAt: publishedAt,
      installer: assets.isEmpty ? null : assets.first,
    );
  }

  /// Prefer `hesabix-windows*.msi`, then any `.msi`, then setup-like `.exe`.
  static bool _looksLikeWindowsInstaller(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.apk')) return false;
    if (lower.endsWith('.msi')) return true;
    if (!lower.endsWith('.exe')) return false;
    return lower.contains('hesabix-windows') ||
        lower.contains('setup') ||
        lower.contains('installer') ||
        lower.contains('install');
  }

  static int _assetRank(WindowsReleaseAsset a) {
    final lower = a.name.toLowerCase();
    if (lower.contains('hesabix-windows') && lower.endsWith('.msi')) return 0;
    if (lower.endsWith('.msi')) return 1;
    if (lower.contains('hesabix-windows') && lower.endsWith('.exe')) return 2;
    if (lower.endsWith('.exe')) return 3;
    return 9;
  }

  Future<String> downloadInstaller(
    WindowsRemoteRelease release, {
    void Function(WindowsUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!supportsWindowsDesktopUpdate) {
      throw UnsupportedError(
        'Windows installer update is not supported on this platform',
      );
    }

    await cancelDownload();
    _downloadCancel = CancelToken();

    final dir = await getTemporaryDirectory();
    final updatesDir = Directory('${dir.path}/windows_updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }

    final safeName =
        release.installer.name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final savePath = '${updatesDir.path}/$safeName';

    final existing = File(savePath);
    if (await existing.exists()) {
      await existing.delete();
    }

    try {
      await _dio.download(
        release.installer.downloadUrl,
        savePath,
        cancelToken: _downloadCancel,
        onReceiveProgress: (received, total) {
          if (isCancelled?.call() == true) {
            _downloadCancel?.cancel('cancelled');
            return;
          }
          onProgress?.call(
            WindowsUpdateDownloadProgress(received: received, total: total),
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
        throw WindowsUpdateCancelledException();
      }
      rethrow;
    } finally {
      _downloadCancel = null;
    }

    final file = File(savePath);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('Downloaded Windows installer is missing or empty');
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

  /// Launches MSI via msiexec or setup EXE, detached so the app can exit.
  Future<void> launchInstaller(String filePath, {required bool isMsi}) async {
    if (!supportsWindowsDesktopUpdate) {
      throw UnsupportedError(
        'Windows installer update is not supported on this platform',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('Installer file not found: $filePath');
    }

    if (isMsi) {
      await Process.start(
        'msiexec.exe',
        ['/i', filePath],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    } else {
      await Process.start(
        filePath,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    }
  }

  /// Exit so the installer can replace running binaries.
  void quitAppForInstaller() {
    if (!supportsWindowsDesktopUpdate) return;
    exit(0);
  }
}

class _ParsedForgejoRelease {
  final String tagName;
  final AppReleaseVersion version;
  final String name;
  final String body;
  final bool draft;
  final bool prerelease;
  final DateTime? publishedAt;
  final WindowsReleaseAsset? installer;

  const _ParsedForgejoRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.draft,
    required this.prerelease,
    required this.publishedAt,
    required this.installer,
  });
}

WindowsUpdateService createWindowsUpdateService() => WindowsUpdateService();
