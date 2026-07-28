import 'android_update_version.dart';

class AndroidReleaseAsset {
  final String name;
  final int size;
  final String downloadUrl;

  const AndroidReleaseAsset({
    required this.name,
    required this.size,
    required this.downloadUrl,
  });
}

class AndroidRemoteRelease {
  final String tagName;
  final AndroidAppVersion version;
  final String name;
  final String body;
  final bool draft;
  final bool prerelease;
  final DateTime? publishedAt;
  final AndroidReleaseAsset apk;

  const AndroidRemoteRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.draft,
    required this.prerelease,
    required this.publishedAt,
    required this.apk,
  });
}

enum AndroidUpdateAvailability {
  /// Platform does not support APK OTA (web / non-Android).
  unsupported,

  /// Could not parse installed or remote version.
  unknown,

  /// Installed version is current or newer.
  upToDate,

  /// A newer release is available.
  updateAvailable,
}

class AndroidUpdateCheckResult {
  final AndroidUpdateAvailability availability;
  final AndroidAppVersion? installedVersion;
  final String? installedVersionLabel;
  final AndroidRemoteRelease? remote;

  const AndroidUpdateCheckResult({
    required this.availability,
    this.installedVersion,
    this.installedVersionLabel,
    this.remote,
  });

  bool get hasUpdate =>
      availability == AndroidUpdateAvailability.updateAvailable && remote != null;
}

class AndroidUpdateDownloadProgress {
  final int received;
  final int total;

  const AndroidUpdateDownloadProgress({
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

class AndroidUpdateCancelledException implements Exception {
  @override
  String toString() => 'Android update download cancelled';
}

class AndroidUpdateInstallPermissionException implements Exception {
  @override
  String toString() => 'Install unknown apps permission required';
}
