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

    group('isNewerReleaseThanInstalled', () {
      const installed = AppReleaseVersion(70, 14, 911);
      test('false when APK is the same as installed', () {
        expect(
          isNewerReleaseThanInstalled(release: installed, installed: installed),
          isFalse,
        );
      });
      test('false when APK is older than installed', () {
        expect(
          isNewerReleaseThanInstalled(
            release: const AppReleaseVersion(70, 13, 0),
            installed: installed,
          ),
          isFalse,
        );
      });
      test('true when APK is newer than installed', () {
        expect(
          isNewerReleaseThanInstalled(
            release: const AppReleaseVersion(70, 15, 0),
            installed: installed,
          ),
          isTrue,
        );
      });
      test('true when a side cannot be parsed (do not drop a real update)', () {
        expect(
          isNewerReleaseThanInstalled(release: null, installed: installed),
          isTrue,
        );
        expect(
          isNewerReleaseThanInstalled(release: installed, installed: null),
          isTrue,
        );
      });
    });
  });

  group('AndroidAppVersion alias', () {
    test('typedef remains compatible', () {
      expect(AndroidAppVersion.tryParse('70.1.2'), const AndroidAppVersion(70, 1, 2));
      expect(const AndroidAppVersion(1, 2, 3), const AppReleaseVersion(1, 2, 3));
    });
  });
}
