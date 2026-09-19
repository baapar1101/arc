import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/android_update/android_update_version.dart';

void main() {
  group('AndroidAppVersion', () {
    test('parses Forgejo-style tags', () {
      expect(AndroidAppVersion.tryParse('70.9.911'), const AndroidAppVersion(70, 9, 911));
      expect(AndroidAppVersion.tryParse('v70.9.911'), const AndroidAppVersion(70, 9, 911));
      expect(AndroidAppVersion.tryParse('70.9.911+70009911'), const AndroidAppVersion(70, 9, 911));
    });

    test('rejects invalid strings', () {
      expect(AndroidAppVersion.tryParse(null), isNull);
      expect(AndroidAppVersion.tryParse(''), isNull);
      expect(AndroidAppVersion.tryParse('1.0'), isNull);
      expect(AndroidAppVersion.tryParse('abc'), isNull);
    });

    test('compares versions correctly', () {
      const a = AndroidAppVersion(70, 9, 311);
      const b = AndroidAppVersion(70, 9, 911);
      const c = AndroidAppVersion(70, 10, 0);
      expect(b > a, isTrue);
      expect(c > b, isTrue);
      expect(a < b, isTrue);
      expect(a.compareTo(a), 0);
    });

    test('suggestedVersionCode encoding', () {
      expect(const AndroidAppVersion(70, 9, 911).suggestedVersionCode, 70009911);
    });
  });
}
