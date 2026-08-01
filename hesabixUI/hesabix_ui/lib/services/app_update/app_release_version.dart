/// Canonical release version shared by Android / Windows OTA: `MAJOR.MINOR.PATCH`
/// (Forgejo tag / Flutter versionName).
class AppReleaseVersion implements Comparable<AppReleaseVersion> {
  final int major;
  final int minor;
  final int patch;

  const AppReleaseVersion(this.major, this.minor, this.patch);

  /// Parses `70.9.911`, optional leading `v`, ignores build suffix after `+` or `-`.
  static AppReleaseVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    s = s.trim();

    final parts = s.split('.');
    if (parts.length != 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) return null;
    if (major < 0 || minor < 0 || patch < 0) return null;
    return AppReleaseVersion(major, minor, patch);
  }

  /// Suggested Android `versionCode`: MAJOR*1_000_000 + MINOR*1_000 + PATCH.
  int get suggestedVersionCode => major * 1000000 + minor * 1000 + patch;

  @override
  int compareTo(AppReleaseVersion other) {
    final a = major.compareTo(other.major);
    if (a != 0) return a;
    final b = minor.compareTo(other.minor);
    if (b != 0) return b;
    return patch.compareTo(other.patch);
  }

  bool operator >(AppReleaseVersion other) => compareTo(other) > 0;
  bool operator <(AppReleaseVersion other) => compareTo(other) < 0;
  bool operator >=(AppReleaseVersion other) => compareTo(other) >= 0;
  bool operator <=(AppReleaseVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppReleaseVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
