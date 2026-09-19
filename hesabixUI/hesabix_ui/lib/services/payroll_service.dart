import 'package:dio/dio.dart';

import '../core/api_client.dart';

/// سرویس API حقوق و دستمزد (`/api/v1/payroll/...`).
class PayrollService {
  final ApiClient _api;

  PayrollService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/settings',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/settings',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getDashboard({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/dashboard',
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listItemCategories({
    required int businessId,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/item-categories',
      query: {'include_inactive': '$includeInactive'},
    );
    final data = _extractData(res.data);
    return _asMapList(data['items']);
  }

  Future<List<Map<String, dynamic>>> listItems({
    required int businessId,
    String? itemKind,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/items',
      query: {
        if (itemKind != null) 'item_kind': itemKind,
        'include_inactive': '$includeInactive',
      },
    );
    final data = _extractData(res.data);
    return _asMapList(data['items']);
  }

  Future<Map<String, dynamic>> createItem({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/items',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateItem({
    required int businessId,
    required int itemId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/items/$itemId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<void> deleteItem({
    required int businessId,
    required int itemId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/items/$itemId',
    );
  }

  Future<List<Map<String, dynamic>>> listDepartments({
    required int businessId,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/departments',
      query: {'include_inactive': '$includeInactive'},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createDepartment({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/departments',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listEmployees({
    required int businessId,
    bool includeInactive = false,
    int limit = 500,
    int skip = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/employees',
      query: {
        'include_inactive': '$includeInactive',
        'limit': '$limit',
        'skip': '$skip',
      },
    );
    final data = _extractData(res.data);
    return _asMapList(data['items']);
  }

  Future<Map<String, dynamic>> createEmployee({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/employees',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateEmployee({
    required int businessId,
    required int employeeId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/employees/$employeeId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listPeriods({
    required int businessId,
    int limit = 24,
    int skip = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/periods',
      query: {'limit': '$limit', 'skip': '$skip'},
    );
    final data = _extractData(res.data);
    return _asMapList(data['items']);
  }

  Future<Map<String, dynamic>> createPeriod({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/periods',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listRuns({
    required int businessId,
    String? status,
    int? periodId,
    int limit = 50,
    int skip = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs',
      query: {
        if (status != null) 'status': status,
        if (periodId != null) 'period_id': '$periodId',
        'limit': '$limit',
        'skip': '$skip',
      },
    );
    final data = _extractData(res.data);
    return _asMapList(data['items']);
  }

  Future<Map<String, dynamic>> getRun({
    required int businessId,
    required int runId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> createRun({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateRun({
    required int businessId,
    required int runId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<void> deleteRun({
    required int businessId,
    required int runId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId',
    );
  }

  Future<Map<String, dynamic>> finalizeRun({
    required int businessId,
    required int runId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/finalize',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> cancelRun({
    required int businessId,
    required int runId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/cancel',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> approveRun({
    required int businessId,
    required int runId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/approve',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> rejectRun({
    required int businessId,
    required int runId,
    String? reason,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/reject',
      data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getItemSummaryReport({
    required int businessId,
    int? periodId,
    int? runId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/reports/item-summary',
      query: {
        if (periodId != null) 'period_id': '$periodId',
        if (runId != null) 'run_id': '$runId',
      },
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getEmployeeSummaryReport({
    required int businessId,
    int? periodId,
    int? runId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/reports/employee-summary',
      query: {
        if (periodId != null) 'period_id': '$periodId',
        if (runId != null) 'run_id': '$runId',
      },
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getStatutorySummaryReport({
    required int businessId,
    int? periodId,
    int? runId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/reports/statutory-summary',
      query: {
        if (periodId != null) 'period_id': '$periodId',
        if (runId != null) 'run_id': '$runId',
      },
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getPeriodOverviewReport({
    required int businessId,
    int? year,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/reports/period-overview',
      query: {if (year != null) 'year': '$year'},
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> postRun({
    required int businessId,
    required int runId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/post',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> postRunPayment({
    required int businessId,
    required int runId,
    required int paymentAccountId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/post-payment',
      data: {'payment_account_id': paymentAccountId},
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> copyRun({
    required int businessId,
    required int runId,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/copy',
      data: payload ?? const {},
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> closePeriod({
    required int businessId,
    required int periodId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/periods/$periodId/close',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateDepartment({
    required int businessId,
    required int departmentId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/departments/$departmentId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getDepartmentSummary({
    required int businessId,
    int? periodId,
    int? runId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/reports/department-summary',
      query: {
        if (periodId != null) 'period_id': '$periodId',
        if (runId != null) 'run_id': '$runId',
      },
    );
    return _extractData(res.data);
  }

  Future<List<int>> downloadPayslipPdf({
    required int businessId,
    required int runId,
    int? lineId,
  }) async {
    return _api.downloadPdf(
      '/api/v1/payroll/business/$businessId/runs/$runId/payslip/pdf',
      query: {if (lineId != null) 'line_id': '$lineId'},
    );
  }

  Future<List<int>> downloadEmployeesTemplate({required int businessId}) async {
    final res = await _api.get<List<int>>(
      '/api/v1/payroll/business/$businessId/employees/import/template',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }

  Future<List<int>> exportEmployeesExcel({required int businessId}) async {
    final res = await _api.get<List<int>>(
      '/api/v1/payroll/business/$businessId/employees/export/excel',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }

  Future<Map<String, dynamic>> importEmployeesExcel({
    required int businessId,
    required List<int> fileBytes,
    required String filename,
    bool dryRun = true,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/employees/import/excel?dry_run=$dryRun',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return _extractData(res.data);
  }

  Future<List<int>> downloadRunLinesTemplate({
    required int businessId,
    required int runId,
  }) async {
    final res = await _api.get<List<int>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/import/template',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }

  Future<Map<String, dynamic>> importRunLinesExcel({
    required int businessId,
    required int runId,
    required List<int> fileBytes,
    required String filename,
    bool dryRun = true,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/payroll/business/$businessId/runs/$runId/import/excel?dry_run=$dryRun',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return _extractData(res.data);
  }

  Map<String, dynamic> _extractData(Map<String, dynamic>? body) {
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
