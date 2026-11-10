import 'package:hesabix_ui/core/api_client.dart';

class AdminOperationsService {
  AdminOperationsService(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> _dataOf(String path, {Map<String, dynamic>? query}) async {
    final res = await _api.get<Map<String, dynamic>>(path, query: query);
    final body = res.data;
    final data = body?['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> home() => _dataOf('/api/v1/admin/operations/home');

  Future<Map<String, dynamic>> schedules() => _dataOf('/api/v1/admin/operations/schedules');

  Future<Map<String, dynamic>> storageReport() => _dataOf('/api/v1/admin/operations/reports/storage');

  Future<Map<String, dynamic>> inactiveBusinesses() =>
      _dataOf('/api/v1/admin/operations/reports/inactive-businesses');

  Future<Map<String, dynamic>> failedLogins() =>
      _dataOf('/api/v1/admin/operations/reports/failed-logins');

  Future<Map<String, dynamic>> expiringLicenses() =>
      _dataOf('/api/v1/admin/operations/licenses/expiring');

  Future<Map<String, dynamic>> auditLogs({String? action}) => _dataOf(
        '/api/v1/admin/audit-logs',
        query: {
          'take': 80,
          if (action != null && action.isNotEmpty) 'action': action,
        },
      );

  Future<List<Map<String, dynamic>>> wallets() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/wallets', query: {'limit': 100});
    final data = res.data?['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<void> refund({
    required int businessId,
    required int transactionId,
    required String confirmation,
    String? reason,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/wallets/$businessId/refunds',
      data: {
        'transaction_id': transactionId,
        'confirmation': confirmation,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> hscriptRuns() =>
      _dataOf('/api/v1/admin/hscript/runs', query: {'take': 80});

  Future<Map<String, dynamic>> aiOpsMetrics() => _dataOf('/api/v1/admin/ai/ops-metrics');

  Future<Map<String, dynamic>> supportStats() => _dataOf('/api/v1/admin/support-billing/stats');

  Future<Map<String, dynamic>> outboxSummary() =>
      _dataOf('/api/v1/admin/monitoring/notifications/outbox/summary');

  Future<Map<String, dynamic>> abandonOutbox({
    required String confirmPhrase,
    String? channel,
    String? eventKey,
    int? userId,
    int maxRows = 50000,
    String? adminNote,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/monitoring/notifications/outbox/abandon',
      data: {
        'confirm_phrase': confirmPhrase,
        'statuses': ['failed', 'pending'],
        if (channel != null && channel.isNotEmpty) 'channel': channel,
        if (eventKey != null && eventKey.isNotEmpty) 'event_key': eventKey,
        if (userId != null) 'user_id': userId,
        'only_retry_scheduled': true,
        'max_rows': maxRows,
        if (adminNote != null && adminNote.isNotEmpty) 'admin_note': adminNote,
      },
    );
    final data = res.data?['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
