abstract class BiometricAuthService {
  Future<bool> isAvailable();

  /// Returns true when biometric (or allowed device credential) succeeds.
  Future<BiometricAuthResult> authenticate({required String reason});

  Future<List<String>> getAvailableBiometricTypes();
}

class BiometricAuthResult {
  final bool success;
  final String? errorCode;
  final String? errorMessage;
  final bool canceled;

  const BiometricAuthResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
    this.canceled = false,
  });

  factory BiometricAuthResult.ok() => const BiometricAuthResult(success: true);

  factory BiometricAuthResult.fail({
    String? errorCode,
    String? errorMessage,
    bool canceled = false,
  }) =>
      BiometricAuthResult(
        success: false,
        errorCode: errorCode,
        errorMessage: errorMessage,
        canceled: canceled,
      );
}

BiometricAuthService createBiometricAuthService() => _NoopBiometricAuthService();

class _NoopBiometricAuthService implements BiometricAuthService {
  @override
  Future<BiometricAuthResult> authenticate({required String reason}) async =>
      BiometricAuthResult.fail(errorCode: 'unsupported', errorMessage: 'Biometrics unsupported');

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<String>> getAvailableBiometricTypes() async => const [];
}
