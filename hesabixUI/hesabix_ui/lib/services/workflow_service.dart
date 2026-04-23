import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';

class WorkflowService {
  final ApiClient _apiClient;

  WorkflowService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> listWorkflows({
    required int businessId,
    QueryInfo? queryInfo,
  }) async {
    final body = (queryInfo ?? const QueryInfo(take: 50, skip: 0, sortDesc: true, sortBy: 'created_at')).toJson();
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/list',
      data: body,
    );
    final data = _asMap(res.data?['data']);
    final items = (data['items'] as List?)
            ?.map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList() ??
        const <Map<String, dynamic>>[];
    return {
      'items': items,
      'total': data['total'] ?? items.length,
      'page': data['page'] ?? 1,
      'page_size': data['page_size'] ?? body['take'] ?? 50,
    };
  }

  Future<Map<String, dynamic>> createWorkflow({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/create',
      data: payload,
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> updateWorkflow({
    required int businessId,
    required int workflowId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/$workflowId/edit',
      data: payload,
    );
    return _asMap(res.data?['data']);
  }

  Future<void> deleteWorkflow({
    required int businessId,
    required int workflowId,
  }) async {
    await _apiClient.delete<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/$workflowId',
    );
  }

  Future<Map<String, dynamic>> executeWorkflow({
    required int businessId,
    required int workflowId,
    Map<String, dynamic>? triggerData,
    bool asyncExecution = false,
    /// اجرای آزمایشی: بدون ارسال/ثبت واقعی (تست امن)
    bool dryRun = false,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/$workflowId/execute',
      data: <String, dynamic>{
        'async_execution': asyncExecution,
        'dry_run': dryRun,
        'trigger_data': triggerData ?? const <String, dynamic>{},
      },
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> getWorkflowExecution({
    required int businessId,
    required int workflowId,
    required int executionId,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/$workflowId/executions/$executionId',
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> listExecutions({
    required int businessId,
    required int workflowId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/$workflowId/executions',
      query: {
        'page': page,
        'page_size': pageSize,
      },
    );
    final data = _asMap(res.data?['data']);
    final items = (data['items'] as List?)
            ?.map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList() ??
        const <Map<String, dynamic>>[];
    return {
      'items': items,
      'total': data['total'] ?? items.length,
      'page': data['page'] ?? page,
      'page_size': data['page_size'] ?? pageSize,
    };
  }

  Future<List<Map<String, dynamic>>> getExecutionLogs({
    required int businessId,
    required int workflowId,
    required int executionId,
    int? afterLogId,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/$workflowId/executions/$executionId/logs',
      query: {
        if (afterLogId != null) 'after_log_id': afterLogId,
      },
    );
    final data = res.data?['data'];
    final logs = (data as List?)
            ?.map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList() ??
        const <Map<String, dynamic>>[];
    return logs;
  }

  Future<List<Map<String, dynamic>>> listTriggers() async {
    return _listWorkflowItems('/workflows/triggers');
  }

  Future<List<Map<String, dynamic>>> listActions() async {
    return _listWorkflowItems('/workflows/actions');
  }

  /// Helper method برای list کردن triggers و actions
  Future<List<Map<String, dynamic>>> _listWorkflowItems(String endpoint) async {
    final res = await _apiClient.get<Map<String, dynamic>>(endpoint);
    final data = _asMap(res.data?['data']);
    return data.entries
        .map<Map<String, dynamic>>((entry) {
          final meta = _asMap(entry.value);
          return {
            'key': entry.key,
            'name': meta['name'] ?? entry.key,
            'description': meta['description'] ?? '',
            'config_schema': meta['config_schema'] ?? const <String, dynamic>{},
          };
        })
        .toList()
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getTelegramConnectedUsers({
    required int businessId,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/business/$businessId/users/telegram-connected',
    );
    final data = _asMap(res.data?['data']);
    final users = (data['users'] as List?)
            ?.map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList() ??
        const <Map<String, dynamic>>[];
    return users;
  }

  Future<List<Map<String, dynamic>>> getBaleConnectedUsers({
    required int businessId,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/business/$businessId/users/bale-connected',
    );
    final data = _asMap(res.data?['data']);
    final users = (data['users'] as List?)
            ?.map<Map<String, dynamic>>(
              (item) => Map<String, dynamic>.from(item as Map),
            )
            .toList() ??
        const <Map<String, dynamic>>[];
    return users;
  }

  Future<List<Map<String, dynamic>>> getBusinessCurrencies({
    required int businessId,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/currencies/business/$businessId',
    );
    final data = res.data?['data'];
    if (data is List) {
      return data
          .map<Map<String, dynamic>>((c) => Map<String, dynamic>.from(c as Map))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// Analytics: دریافت آمار خطاهای workflow
  Future<Map<String, dynamic>> getWorkflowErrorsAnalytics({
    required int businessId,
    int? workflowId,
    int days = 7,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/analytics/errors',
      query: {
        'days': days,
        if (workflowId != null) 'workflow_id': workflowId,
      },
    );
    return _asMap(res.data?['data']);
  }

  /// Analytics: دریافت آمار عملکرد workflows
  Future<Map<String, dynamic>> getWorkflowPerformanceAnalytics({
    required int businessId,
    int? workflowId,
    int days = 30,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/analytics/performance',
      query: {
        'days': days,
        if (workflowId != null) 'workflow_id': workflowId,
      },
    );
    return _asMap(res.data?['data']);
  }

  /// دریافت Timeline اجرای workflow
  Future<Map<String, dynamic>> getExecutionTimeline({
    required int businessId,
    required int workflowId,
    required int executionId,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/$workflowId/executions/$executionId/timeline',
    );
    return _asMap(res.data?['data']);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry('$key', val));
    }
    return <String, dynamic>{};
  }
}


