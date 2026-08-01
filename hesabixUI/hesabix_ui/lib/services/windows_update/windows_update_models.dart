import '../app_update/app_release_version.dart';

class WindowsReleaseAsset {
  final String name;
  final int size;
  final String downloadUrl;

  const WindowsReleaseAsset({
    required this.name,
    required this.size,
    required this.downloadUrl,
  });

  bool get isMsi => name.toLowerCase().endsWith('.msi');
}

class WindowsRemoteRelease {
  final String tagName;
  final AppReleaseVersion version;
  final String name;
  final String body;
  final bool draft;
  final bool prerelease;
  final DateTime? publishedAt;
  final WindowsReleaseAsset installer;

  const WindowsRemoteRelease({
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

enum WindowsUpdateAvailability {
  /// Platform does not support Windows OTA (web / non-Windows).
  unsupported,

  /// Could not reach Forgejo or parse versions.
  unknown,

  /// Installed version is current/newer, or latest release has no Windows asset.
  upToDate,

  /// A newer Windows installer is available.
  updateAvailable,
}

class WindowsUpdateCheckResult {
  final WindowsUpdateAvailability availability;
  final AppReleaseVersion? installedVersion;
  final String? installedVersionLabel;
  final WindowsRemoteRelease? remote;

  const WindowsUpdateCheckResult({
    required this.availability,
    this.installedVersion,
    this.installedVersionLabel,
    this.remote,
  });

  bool get hasUpdate =>
      availability == WindowsUpdateAvailability.updateAvailable && remote != null;
}

class WindowsUpdateDownloadProgress {
  final int received;
  final int total;

  const WindowsUpdateDownloadProgress({
    required this.received,
    required this.total,
  });

  double? get fraction {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }

  int get percent {
    final f = fraction;
    if (f == null) return 0;
    return (f * 100).round();
  }
}

class WindowsUpdateCancelledException implements Exception {
  @override
  String toString() => 'Windows update download cancelled';
}
