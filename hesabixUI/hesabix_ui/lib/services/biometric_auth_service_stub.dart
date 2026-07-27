abstract class BiometricAuthService {
  Future<bool> isAvailable();

  Future<bool> authenticate({required String reason});

  Future<List<String>> getAvailableBiometricTypes();
}

BiometricAuthService createBiometricAuthService() => _NoopBiometricAuthService();

class _NoopBiometricAuthService implements BiometricAuthService {
  @override
  Future<bool> authenticate({required String reason}) async => false;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<String>> getAvailableBiometricTypes() async => const [];
}
