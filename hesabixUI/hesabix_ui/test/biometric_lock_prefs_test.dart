import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/biometric_lock_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('per-user biometric prefs are isolated', () async {
    await BiometricLockPrefs.setEnabled(10, true);
    await BiometricLockPrefs.markPrompted(10);

    expect(await BiometricLockPrefs.isEnabled(10), isTrue);
    expect(await BiometricLockPrefs.hasBeenPrompted(10), isTrue);
    expect(await BiometricLockPrefs.isEnabled(20), isFalse);
    expect(await BiometricLockPrefs.hasBeenPrompted(20), isFalse);
  });

  test('clearForUser removes flags', () async {
    await BiometricLockPrefs.setEnabled(5, true);
    await BiometricLockPrefs.markPrompted(5);

    await BiometricLockPrefs.clearForUser(5);

    expect(await BiometricLockPrefs.isEnabled(5), isFalse);
    expect(await BiometricLockPrefs.hasBeenPrompted(5), isFalse);
  });
}
