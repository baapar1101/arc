import 'package:flutter/foundation.dart';
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

      // Device may support biometrics even when none are enrolled yet.
      final canCheck = await _auth.canCheckBiometrics;
      if (canCheck) {
        final types = await _auth.getAvailableBiometrics();
        if (types.isNotEmpty) return true;
      }

      // Fallback: some OEMs report empty types but still allow BiometricPrompt.
      return isDeviceSupported;
    } on PlatformException catch (e) {
      debugPrint('Biometric isAvailable PlatformException: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Biometric isAvailable error: $e');
      return false;
    }
  }

  @override
  Future<BiometricAuthResult> authenticate({required String reason}) async {
    if (!supportsBiometricLock) {
      return BiometricAuthResult.fail(
        errorCode: 'unsupported',
        errorMessage: 'Biometric lock is only supported on Android',
      );
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          // Allow PIN/pattern as fallback when fingerprint UI is unavailable
          // (still primarily biometric on enrolled devices).
          biometricOnly: false,
          useErrorDialogs: true,
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
            deviceCredentialsSetupDescription: 'رمز یا اثر انگشت دستگاه را در تنظیمات فعال کنید',
            goToSettingsButton: 'تنظیمات',
            goToSettingsDescription: 'احراز هویت بیومتریک در تنظیمات دستگاه فعال نیست.',
          ),
        ],
      );
      if (ok) return BiometricAuthResult.ok();
      return BiometricAuthResult.fail(
        errorCode: 'failed',
        errorMessage: 'Authentication failed',
        canceled: true,
      );
    } on PlatformException catch (e) {
      debugPrint('Biometric authenticate PlatformException: ${e.code} ${e.message}');
      final canceled = e.code == 'UserCanceled' ||
          e.code == 'Canceled' ||
          e.code == 'userCanceled';
      return BiometricAuthResult.fail(
        errorCode: e.code,
        errorMessage: e.message,
        canceled: canceled,
      );
    } catch (e) {
      debugPrint('Biometric authenticate error: $e');
      return BiometricAuthResult.fail(
        errorCode: 'unknown',
        errorMessage: e.toString(),
      );
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
