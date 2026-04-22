import '../core/api_client.dart';

class MobileVerificationService {
  final ApiClient _api;
  MobileVerificationService(this._api);

  /// ارسال کد تایید به شماره موبایل (همراه کپچا)
  Future<Map<String, dynamic>> sendMobileVerification({
    required String mobile,
    required String captchaId,
    required String captchaCode,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/send-mobile-verification',
      data: {
        'mobile': mobile,
        'captcha_id': captchaId,
        'captcha_code': captchaCode,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// تایید شماره موبایل با کد OTP
  Future<Map<String, dynamic>> verifyMobile(String otpCode) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/verify-mobile',
      query: {'otp_code': otpCode},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// ارسال مجدد کد تایید موبایل
  Future<Map<String, dynamic>> resendMobileVerification() async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/resend-mobile-verification',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}

