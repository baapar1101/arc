import '../core/api_client.dart';
import 'mobile_verification_service.dart';

class VerificationService {
  final ApiClient _api;
  final MobileVerificationService _mobileService;

  VerificationService(this._api) : _mobileService = MobileVerificationService(_api);

  /// دریافت اطلاعات کاربر
  Future<Map<String, dynamic>> getUserInfo() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/auth/me');
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      final user = data['user'];
      if (user is Map<String, dynamic>) {
        return user;
      }
    }
    return {};
  }

  /// دریافت کپچا
  Future<Map<String, dynamic>> getCaptcha() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/auth/captcha');
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) {
      return {
        'captcha_id': data['captcha_id']?.toString(),
        'image_base64': data['image_base64']?.toString(),
        'ttl_seconds': (data['ttl_seconds'] as num?)?.toInt(),
      };
    }
    return {};
  }

  /// تغییر شماره موبایل
  Future<Map<String, dynamic>> updateMobile({
    required String mobile,
    required String captchaId,
    required String captchaCode,
    bool forceUnverified = false,
    bool sendVerificationSms = true,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/update-mobile',
      data: {
        'mobile': mobile,
        'captcha_id': captchaId,
        'captcha_code': captchaCode,
        'force_unverified': forceUnverified,
        'send_verification_sms': sendVerificationSms,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// تغییر ایمیل
  Future<Map<String, dynamic>> updateEmail({
    required String email,
    required String captchaId,
    required String captchaCode,
    bool forceUnverified = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/update-email',
      data: {
        'email': email,
        'captcha_id': captchaId,
        'captcha_code': captchaCode,
        'force_unverified': forceUnverified,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// ارسال کد تایید به شماره موبایل (نیازمند کپچا؛ اگر موبایل را با [updateMobile] و sendVerificationSms عوض کرده‌اید، معمولاً لازم نیست)
  Future<Map<String, dynamic>> sendMobileVerification({
    required String mobile,
    required String captchaId,
    required String captchaCode,
  }) async {
    return _mobileService.sendMobileVerification(
      mobile: mobile,
      captchaId: captchaId,
      captchaCode: captchaCode,
    );
  }

  /// تایید شماره موبایل با کد OTP
  Future<Map<String, dynamic>> verifyMobile(String otpCode) async {
    return await _mobileService.verifyMobile(otpCode);
  }

  /// ارسال مجدد کد تایید موبایل
  Future<Map<String, dynamic>> resendMobileVerification() async {
    return await _mobileService.resendMobileVerification();
  }

  /// ارسال ایمیل تایید
  Future<void> sendEmailVerification() async {
    await _api.post<Map<String, dynamic>>('/api/v1/auth/resend-verification');
  }
}

