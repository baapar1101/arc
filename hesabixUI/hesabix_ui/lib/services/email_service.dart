import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/email_models.dart';

class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  late final ApiClient _apiClient;

  void _initializeApiClient() {
    _apiClient = ApiClient();
  }

  void _ensureApiClientInitialized() {
    try {
      _apiClient;
    } catch (e) {
      _initializeApiClient();
    }
  }

  /// Send email using configured SMTP
  Future<SendEmailResponse> sendEmail(SendEmailRequest request) async {
    _ensureApiClientInitialized();
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/admin/email/send',
        data: request.toJson(),
      );

      return SendEmailResponse.fromJson(response.data!);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Send welcome email to new user
  Future<SendEmailResponse> sendWelcomeEmail(String userEmail, String userName) async {
    _ensureApiClientInitialized();
    return sendEmail(SendEmailRequest(
      to: userEmail,
      subject: 'خوش آمدید به حسابیکس',
      body: 'سلام $userName،\n\nبه حسابیکس خوش آمدید! امیدواریم تجربه خوبی داشته باشید.\n\nبا احترام\nتیم حسابیکس',
      htmlBody: '''
        <h2>خوش آمدید به حسابیکس</h2>
        <p>سلام $userName،</p>
        <p>به حسابیکس خوش آمدید! امیدواریم تجربه خوبی داشته باشید.</p>
        <p>با احترام<br>تیم حسابیکس</p>
      ''',
    ));
  }

  /// Send password reset email
  Future<SendEmailResponse> sendPasswordResetEmail(String userEmail, String resetLink) async {
    _ensureApiClientInitialized();
    return sendEmail(SendEmailRequest(
      to: userEmail,
      subject: 'بازیابی رمز عبور',
      body: 'برای بازیابی رمز عبور روی لینک زیر کلیک کنید:\n\n$resetLink\n\nاین لینک تا 1 ساعت معتبر است.',
      htmlBody: '''
        <h2>بازیابی رمز عبور</h2>
        <p>برای بازیابی رمز عبور روی لینک زیر کلیک کنید:</p>
        <p><a href="$resetLink" style="background-color: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">بازیابی رمز عبور</a></p>
        <p>این لینک تا 1 ساعت معتبر است.</p>
      ''',
    ));
  }

  /// Send notification email
  Future<SendEmailResponse> sendNotificationEmail(String userEmail, String title, String message) async {
    _ensureApiClientInitialized();
    return sendEmail(SendEmailRequest(
      to: userEmail,
      subject: title,
      body: message,
      htmlBody: '''
        <h2>$title</h2>
        <p>$message</p>
      ''',
    ));
  }

  /// Send custom email
  Future<SendEmailResponse> sendCustomEmail({
    required String to,
    required String subject,
    required String body,
    String? htmlBody,
    int? configId,
  }) async {
    _ensureApiClientInitialized();
    return sendEmail(SendEmailRequest(
      to: to,
      subject: subject,
      body: body,
      htmlBody: htmlBody,
      configId: configId,
    ));
  }

  /// Get all email configurations
  Future<EmailConfigListResponse> getEmailConfigs() async {
    _ensureApiClientInitialized();
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/admin/email/configs',
      );

      final data = response.data!;
      return EmailConfigListResponse(
        success: data['success'] as bool? ?? true,
        data: (data['data'] as List? ?? [])
            .map((item) => EmailConfig.fromJson(item as Map<String, dynamic>))
            .toList(),
        message: data['message'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get specific email configuration
  Future<EmailConfigResponse> getEmailConfig(int configId) async {
    _ensureApiClientInitialized();
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/admin/email/configs/$configId',
      );

      final data = response.data!;
      return EmailConfigResponse(
        success: data['success'] as bool? ?? true,
        data: EmailConfig.fromJson(data['data'] as Map<String, dynamic>),
        message: data['message'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Create new email configuration
  Future<EmailConfigResponse> createEmailConfig(CreateEmailConfigRequest request) async {
    _ensureApiClientInitialized();
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/admin/email/configs',
        data: request.toJson(),
      );

      final data = response.data!;
      return EmailConfigResponse(
        success: data['success'] as bool? ?? true,
        data: EmailConfig.fromJson(data['data'] as Map<String, dynamic>),
        message: data['message'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update email configuration
  Future<EmailConfigResponse> updateEmailConfig(int configId, UpdateEmailConfigRequest request) async {
    _ensureApiClientInitialized();
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/v1/admin/email/configs/$configId',
        data: request.toJson(),
      );

      final data = response.data!;
      return EmailConfigResponse(
        success: data['success'] as bool? ?? true,
        data: EmailConfig.fromJson(data['data'] as Map<String, dynamic>),
        message: data['message'] as String? ?? '',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete email configuration
  Future<void> deleteEmailConfig(int configId) async {
    _ensureApiClientInitialized();
    try {
      await _apiClient.delete('/api/v1/admin/email/configs/$configId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Test email configuration connection
  Future<TestConnectionResponse> testEmailConfig(int configId) async {
    _ensureApiClientInitialized();
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/admin/email/configs/$configId/test',
      );

      final data = response.data!;
      return TestConnectionResponse(
        success: data['success'] as bool? ?? true,
        message: data['message'] as String? ?? '',
        connected: data['data']?['connected'] as bool? ?? false,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Activate email configuration
  Future<void> activateEmailConfig(int configId) async {
    _ensureApiClientInitialized();
    try {
      await _apiClient.post('/api/v1/admin/email/configs/$configId/activate');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Set email configuration as default
  Future<void> setDefaultEmailConfig(int configId) async {
    _ensureApiClientInitialized();
    try {
      await _apiClient.post('/api/v1/admin/email/configs/$configId/set-default');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Handle API errors
  String _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic>) {
        // پاسخ‌های ساختارمند شامل success/error/details
        final structuredError = data['error'];
        if (structuredError is Map<String, dynamic>) {
          final detailsMsg = _formatErrorDetails(structuredError['details']);
          final message = structuredError['message']?.toString();
          if (detailsMsg != null && detailsMsg.isNotEmpty) {
            return message != null && message.isNotEmpty ? '$message\n$detailsMsg' : detailsMsg;
          }
          if (message != null && message.isNotEmpty) {
            return message;
          }
        }
        if (data.containsKey('detail')) {
          return data['detail'].toString();
        }
        if (data.containsKey('message')) {
          return data['message'].toString();
        }
      }
      return 'خطا در ارتباط با سرور: ${e.response!.statusCode}';
    } else if (e.type == DioExceptionType.connectionTimeout) {
      return 'خطا در اتصال به سرور - لطفاً اتصال اینترنت خود را بررسی کنید';
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return 'زمان دریافت پاسخ از سرور به پایان رسید';
    } else {
      return 'خطای نامشخص: ${e.message}';
    }
  }

  String? _formatErrorDetails(dynamic rawDetails) {
    if (rawDetails is! List) {
      return null;
    }
    final messages = <String>[];
    for (final item in rawDetails) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final loc = _localizeFieldPath(item['loc']);
      final msg = item['msg']?.toString();
      if ((loc?.isNotEmpty ?? false) && (msg?.isNotEmpty ?? false)) {
        messages.add('$loc: $msg');
      } else if (msg?.isNotEmpty ?? false) {
        messages.add(msg!);
      }
    }
    if (messages.isEmpty) {
      return null;
    }
    return messages.join('\n');
  }

  String? _localizeFieldPath(dynamic loc) {
    if (loc is! List) {
      return loc?.toString();
    }
    final labels = <String>[];
    for (final part in loc) {
      if (part is! String) {
        continue;
      }
      labels.add(_mapFieldLabel(part));
    }
    if (labels.isEmpty) {
      return null;
    }
    return labels.join(' › ');
  }

  String _mapFieldLabel(String key) {
    switch (key) {
      case 'body':
        return 'بدنه درخواست';
      case 'name':
        return 'نام کانفیگ';
      case 'smtp_host':
        return 'میزبان SMTP';
      case 'smtp_port':
        return 'پورت SMTP';
      case 'smtp_username':
        return 'نام کاربری SMTP';
      case 'smtp_password':
        return 'رمز عبور SMTP';
      case 'use_tls':
        return 'TLS';
      case 'use_ssl':
        return 'SSL';
      case 'from_email':
        return 'ایمیل فرستنده';
      case 'from_name':
        return 'نام فرستنده';
      case 'is_active':
        return 'وضعیت فعال';
      default:
        return key;
    }
  }
}
