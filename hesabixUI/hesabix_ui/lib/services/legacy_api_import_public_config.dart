import '../core/api_client.dart';

/// وضعیت انتقال از حسابیکس قبلی برای کاربران؛ از [/api/v1/auth/public-config] خوانده می‌شود.
class LegacyApiImportPublicConfig {
  /// اگر از سرور نامشخص باشد فرض روشن بودن است تا UI قفل نشود.
  final bool enabledForUsers;

  /// وقتی [enabledForUsers] false است؛ ممکن است از سرور خالی برود.
  final String disabledMessage;

  const LegacyApiImportPublicConfig({
    this.enabledForUsers = true,
    this.disabledMessage = '',
  });

  static LegacyApiImportPublicConfig? _memoryCache;
  static DateTime? _memoryCacheAt;
  static const Duration _memoryTtl = Duration(seconds: 60);
  static Future<LegacyApiImportPublicConfig>? _inFlight;

  factory LegacyApiImportPublicConfig.fromDataMap(Map<String, dynamic>? data) {
    if (data == null) {
      return const LegacyApiImportPublicConfig();
    }
    final raw = data['legacy_api_import_enabled'];
    final msg = data['legacy_api_import_disabled_message']?.toString() ?? '';
    final enabled = raw is bool ? raw : true;
    return LegacyApiImportPublicConfig(
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

  static Future<LegacyApiImportPublicConfig> fetch(
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

  static Future<LegacyApiImportPublicConfig> _fetchFromNetwork(
    ApiClient api,
  ) async {
    try {
      final res =
          await api.get<Map<String, dynamic>>('/api/v1/auth/public-config');
      final body = res.data;
      Map<String, dynamic>? data;
      if (body is Map<String, dynamic>) {
        final inner = body['data'];
        if (inner is Map<String, dynamic>) {
          data = inner;
        }
      }
      final cfg = LegacyApiImportPublicConfig.fromDataMap(data);
      _memoryCache = cfg;
      _memoryCacheAt = DateTime.now();
      return cfg;
    } catch (_) {
      if (_memoryCache != null) return _memoryCache!;
      return const LegacyApiImportPublicConfig();
    }
  }
}
