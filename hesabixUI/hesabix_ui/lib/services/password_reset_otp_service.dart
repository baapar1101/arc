import '../core/api_client.dart';

class PasswordResetOtpService {
  final ApiClient _api;
  PasswordResetOtpService(this._api);

  /// ارسال OTP برای بازیابی رمز عبور
  Future<Map<String, dynamic>> sendPasswordResetOtp({
    required String identifier,
    required String captchaId,
    required String captchaCode,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/password-reset/send-otp',
      data: {
        'identifier': identifier,
        'captcha_id': captchaId,
        'captcha_code': captchaCode,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// تایید OTP و دریافت reset token
  Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String identifier,
    required String otpCode,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/password-reset/verify-otp',
      query: {
        'identifier': identifier,
        'otp_code': otpCode,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}

