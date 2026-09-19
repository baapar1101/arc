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

  /// کش کوتاه‌عمر تا شل پروفایل و داشبورد دوباره همان درخواست را نزنند.
  static SupportTicketsPublicConfig? _memoryCache;
  static DateTime? _memoryCacheAt;
  static const Duration _memoryTtl = Duration(seconds: 60);
  static Future<SupportTicketsPublicConfig>? _inFlight;

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

  static bool get _memoryFresh {
    final at = _memoryCacheAt;
    final cached = _memoryCache;
    if (at == null || cached == null) return false;
    return DateTime.now().difference(at) < _memoryTtl;
  }

  static Future<SupportTicketsPublicConfig> fetch(
    ApiClient api, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _memoryFresh) {
      return _memoryCache!;
    }
    if (!forceRefresh && _inFlight != null) {
      return _inFlight!;
    }
    final future = _fetchFromNetwork(api);
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }

  static Future<SupportTicketsPublicConfig> _fetchFromNetwork(ApiClient api) async {
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
      final cfg = SupportTicketsPublicConfig.fromDataMap(data);
      _memoryCache = cfg;
      _memoryCacheAt = DateTime.now();
      return cfg;
    } catch (_) {
      if (_memoryCache != null) return _memoryCache!;
      return const SupportTicketsPublicConfig();
    }
  }
}
