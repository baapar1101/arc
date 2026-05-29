import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';

/// سرویس ایمپورت دیتابیس قدیمی MySQL (.sql) — مدیر سیستم
class AdminLegacyImportService {
  AdminLegacyImportService(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> analyzeLegacySql({
    required List<int> fileBytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/legacy-import/analyze',
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<String> startLegacyImport({
    required List<int> fileBytes,
    required String filename,
    required LegacyImportRunParams params,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/legacy-import/run',
      data: formData,
      query: params.toQuery(),
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final data = res.data?['data'] as Map?;
    final jobId = data?['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw Exception('job_id دریافت نشد');
    }
    return jobId;
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/jobs/$jobId');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}

class LegacyImportRunParams {
  const LegacyImportRunParams({
    this.importMode = 'new_business',
    this.targetBusinessId,
    this.ownerUserId,
    this.dryRun = false,
    this.importUsers = true,
    this.importMasterData = true,
    this.importInvoices = true,
    this.importReceiptsPayments = true,
    this.importExpenseIncome = true,
    this.importWarehouses = true,
    this.importTransfers = true,
    this.importOpeningBalance = true,
    this.importChecks = true,
    this.rewriteConfirmation,
  });

  final String importMode;
  final int? targetBusinessId;
  final int? ownerUserId;
  final bool dryRun;
  final bool importUsers;
  final bool importMasterData;
  final bool importInvoices;
  final bool importReceiptsPayments;
  final bool importExpenseIncome;
  final bool importWarehouses;
  final bool importTransfers;
  final bool importOpeningBalance;
  final bool importChecks;
  final String? rewriteConfirmation;

  Map<String, String> toQuery() {
    final q = <String, String>{
      'import_mode': importMode,
      'dry_run': dryRun.toString(),
      'import_users': importUsers.toString(),
      'import_master_data': importMasterData.toString(),
      'import_invoices': importInvoices.toString(),
      'import_receipts_payments': importReceiptsPayments.toString(),
      'import_expense_income': importExpenseIncome.toString(),
      'import_warehouses': importWarehouses.toString(),
      'import_transfers': importTransfers.toString(),
      'import_opening_balance': importOpeningBalance.toString(),
      'import_checks': importChecks.toString(),
    };
    if (targetBusinessId != null) {
      q['target_business_id'] = targetBusinessId.toString();
    }
    if (ownerUserId != null) {
      q['owner_user_id'] = ownerUserId.toString();
    }
    if (rewriteConfirmation != null && rewriteConfirmation!.isNotEmpty) {
      q['rewrite_confirmation'] = rewriteConfirmation!;
    }
    return q;
  }
}
