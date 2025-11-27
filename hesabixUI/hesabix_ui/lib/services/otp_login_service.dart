import '../core/api_client.dart';

class OtpLoginService {
  final ApiClient _api;
  OtpLoginService(this._api);

  /// دریافت کانال‌های در دسترس برای یک identifier
  Future<Map<String, dynamic>> getAvailableChannels(String identifier) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/auth/login/available-channels',
      query: {'identifier': identifier},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// ارسال OTP برای ورود
  Future<Map<String, dynamic>> sendLoginOtp({
    required String identifier,
    required String channel,
    required String captchaId,
    required String captchaCode,
    String? sessionId,
  }) async {
    final data = <String, dynamic>{
      'identifier': identifier,
      'channel': channel,
      'captcha_id': captchaId,
      'captcha_code': captchaCode,
    };
    if (sessionId != null) {
      data['session_id'] = sessionId;
    }
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/login/send-otp',
      data: data,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// تایید OTP و ورود
  Future<Map<String, dynamic>> verifyLoginOtp({
    required String sessionId,
    required String otpCode,
    String? deviceId,
  }) async {
    final queryParams = <String, String>{
      'session_id': sessionId,
      'otp_code': otpCode,
    };
    if (deviceId != null) {
      queryParams['device_id'] = deviceId;
    }
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/auth/login/verify-otp',
      query: queryParams,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}

