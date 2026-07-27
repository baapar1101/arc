import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import '../core/biometric_platform.dart';
export 'biometric_auth_service_stub.dart';
import 'biometric_auth_service_stub.dart';

BiometricAuthService createBiometricAuthService() => _BiometricAuthServiceIo();

class _BiometricAuthServiceIo implements BiometricAuthService {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (!supportsBiometricLock) return false;
    try {
      final isDeviceSupported = await _auth.isDeviceSupported();
      if (!isDeviceSupported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate({required String reason}) async {
    if (!supportsBiometricLock) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'احراز هویت بیومتریک',
            cancelButton: 'لغو',
            biometricHint: 'اثر انگشت خود را روی سنسور قرار دهید',
            biometricNotRecognized: 'شناسایی نشد. دوباره تلاش کنید.',
            biometricSuccess: 'موفق',
            biometricRequiredTitle: 'اثر انگشت',
            deviceCredentialsRequiredTitle: 'رمز دستگاه',
            deviceCredentialsSetupDescription: 'رمز دستگاه را تنظیم کنید',
            goToSettingsButton: 'تنظیمات',
            goToSettingsDescription: 'احراز هویت بیومتریک در تنظیمات فعال نیست.',
          ),
        ],
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> getAvailableBiometricTypes() async {
    if (!supportsBiometricLock) return const [];
    try {
      final types = await _auth.getAvailableBiometrics();
      return types.map((t) => t.name).toList();
    } catch (_) {
      return const [];
    }
  }
}
