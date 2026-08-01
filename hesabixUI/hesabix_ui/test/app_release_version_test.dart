import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/app_update/app_release_version.dart';
import 'package:hesabix_ui/services/android_update/android_update_version.dart';

void main() {
  group('AppReleaseVersion', () {
    test('parses Forgejo-style tags', () {
      expect(AppReleaseVersion.tryParse('70.9.911'), const AppReleaseVersion(70, 9, 911));
      expect(AppReleaseVersion.tryParse('v70.9.911'), const AppReleaseVersion(70, 9, 911));
      expect(
        AppReleaseVersion.tryParse('70.9.911+70009911'),
        const AppReleaseVersion(70, 9, 911),
      );
    });

    test('rejects invalid strings', () {
      expect(AppReleaseVersion.tryParse(null), isNull);
      expect(AppReleaseVersion.tryParse(''), isNull);
      expect(AppReleaseVersion.tryParse('1.0'), isNull);
      expect(AppReleaseVersion.tryParse('abc'), isNull);
    });

    test('compares versions correctly', () {
      const a = AppReleaseVersion(70, 9, 311);
      const b = AppReleaseVersion(70, 9, 911);
      const c = AppReleaseVersion(70, 10, 0);
      expect(b > a, isTrue);
      expect(c > b, isTrue);
      expect(a < b, isTrue);
      expect(a.compareTo(a), 0);
    });

    test('suggestedVersionCode encoding', () {
      expect(const AppReleaseVersion(70, 9, 911).suggestedVersionCode, 70009911);
    });
  });

  group('AndroidAppVersion alias', () {
    test('typedef remains compatible', () {
      expect(AndroidAppVersion.tryParse('70.1.2'), const AndroidAppVersion(70, 1, 2));
      expect(const AndroidAppVersion(1, 2, 3), const AppReleaseVersion(1, 2, 3));
    });
  });
}
