import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/sms_bank/sms_bank_launch_navigation.dart';

void main() {
  group('normalizeInitialLocation', () {
    test('maps Windows file:// install path to /', () {
      final base = Uri.parse('file:///C:/Program%20Files/Hesabix/');
      expect(SmsBankLaunchNavigation.normalizeInitialLocation(base), '/');
      expect(SmsBankLaunchNavigation.shouldOverridePlatformDefault(base), isTrue);
    });

    test('maps Windows file:// exe path to /', () {
      final base = Uri.parse('file:///D:/hesabixArc/build/windows/x64/runner/Debug/hesabix_ui.exe');
      expect(SmsBankLaunchNavigation.normalizeInitialLocation(base), '/');
      expect(SmsBankLaunchNavigation.isFilesystemRoutePath(base.path), isTrue);
    });

    test('keeps Android-style file:/// root as /', () {
      final base = Uri.parse('file:///');
      expect(SmsBankLaunchNavigation.normalizeInitialLocation(base), '/');
      expect(SmsBankLaunchNavigation.shouldOverridePlatformDefault(base), isFalse);
    });

    test('keeps web http path', () {
      final base = Uri.parse('https://app.hesabix.ir/user/profile/dashboard');
      expect(
        SmsBankLaunchNavigation.normalizeInitialLocation(base),
        '/user/profile/dashboard',
      );
      expect(SmsBankLaunchNavigation.shouldOverridePlatformDefault(base), isFalse);
    });

    test('maps sms-bank capture to /', () {
      final base = Uri.parse('hesabix://sms-bank/capture?id=42');
      expect(SmsBankLaunchNavigation.normalizeInitialLocation(base), '/');
    });
  });

  group('isFilesystemRoutePath', () {
    test('detects Windows drive paths', () {
      expect(SmsBankLaunchNavigation.isFilesystemRoutePath('/C:/Program Files/Hesabix'), isTrue);
      expect(SmsBankLaunchNavigation.isFilesystemRoutePath('/D/hesabixArc/build'), isTrue);
      expect(SmsBankLaunchNavigation.isFilesystemRoutePath('/user/profile/dashboard'), isFalse);
      expect(SmsBankLaunchNavigation.isFilesystemRoutePath('/'), isFalse);
    });
  });

  group('isRecognizedAppRoutePath', () {
    test('accepts app routes', () {
      expect(SmsBankLaunchNavigation.isRecognizedAppRoutePath('/'), isTrue);
      expect(SmsBankLaunchNavigation.isRecognizedAppRoutePath('/login'), isTrue);
      expect(SmsBankLaunchNavigation.isRecognizedAppRoutePath('/user/profile/dashboard'), isTrue);
      expect(SmsBankLaunchNavigation.isRecognizedAppRoutePath('/business/5/tab0/invoices'), isTrue);
    });

    test('rejects filesystem-like paths', () {
      expect(SmsBankLaunchNavigation.isRecognizedAppRoutePath('/C:/Program Files/Hesabix'), isFalse);
      expect(SmsBankLaunchNavigation.isRecognizedAppRoutePath('/Program Files/Hesabix'), isFalse);
    });
  });

  group('shouldRedirectUnknownPathToRoot', () {
    test('redirects unknown desktop paths', () {
      expect(
        SmsBankLaunchNavigation.shouldRedirectUnknownPathToRoot('/C:/Program Files/Hesabix'),
        isTrue,
      );
      expect(
        SmsBankLaunchNavigation.shouldRedirectUnknownPathToRoot('/Program Files/Hesabix'),
        isTrue,
      );
      expect(
        SmsBankLaunchNavigation.shouldRedirectUnknownPathToRoot('/user/profile/dashboard'),
        isFalse,
      );
    });
  });
}
