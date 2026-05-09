import '../core/api_client.dart';

/// وضعیت تیکت پشتیبانی برای کاربران عادی؛ از [/api/v1/auth/public-config] خوانده می‌شود.
class SupportTicketsPublicConfig {
  /// اگر از سرور نامشخص باشد فرض روشن بودن است تا UI قفل نشود.
  final bool enabledForUsers;

  /// وقتی [enabledForUsers] false است؛ ممکن است از سرور خالی برود.
  final String disabledMessage;

  const SupportTicketsPublicConfig({
    this.enabledForUsers = true,
    this.disabledMessage = '',
  });

  factory SupportTicketsPublicConfig.fromDataMap(Map<String, dynamic>? data) {
    if (data == null) {
      return const SupportTicketsPublicConfig();
    }
    final raw = data['support_tickets_enabled'];
    final msg = data['support_tickets_disabled_message']?.toString() ?? '';
    final enabled = raw is bool ? raw : true;
    return SupportTicketsPublicConfig(
      enabledForUsers: enabled,
      disabledMessage: msg,
    );
  }

  static Future<SupportTicketsPublicConfig> fetch(ApiClient api) async {
    try {
      final res = await api.get<Map<String, dynamic>>('/api/v1/auth/public-config');
      final body = res.data;
      Map<String, dynamic>? data;
      if (body is Map<String, dynamic>) {
        final inner = body['data'];
        if (inner is Map<String, dynamic>) {
          data = inner;
        }
      }
      return SupportTicketsPublicConfig.fromDataMap(data);
    } catch (_) {
      return const SupportTicketsPublicConfig();
    }
  }
}
