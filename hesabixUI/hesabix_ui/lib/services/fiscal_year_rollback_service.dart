import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// استخراج پیام خطای خوانا برای API های برگشت از سال مالی.
class FiscalYearRollbackService {
  final ApiClient _apiClient;

  FiscalYearRollbackService(this._apiClient);

  /// حذف پیشوند تکنیکی `Exception:` برای نمایش در SnackBar
  static String formatError(Object error) {
    final s = error.toString().trim();
    if (s.startsWith('Exception: ')) {
      return s.substring('Exception: '.length).trim();
    }
    return s;
  }

  Future<Map<String, dynamic>> preview(int businessId, AppLocalizations l10n) async {
    try {
      final res = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/business/$businessId/fiscal-years/current/rollback/preview',
      );
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) {
        final msg = data['message']?.toString();
        throw Exception(msg ?? l10n.fiscalYearRollbackPreviewFailed);
      }
      return Map<String, dynamic>.from(data['data'] as Map);
    } on DioException catch (e) {
      final msg = extractApiErrorMessage(e, l10n);
      throw Exception(msg ?? l10n.fiscalYearRollbackNetworkUnreachable);
    }
  }

  Future<Map<String, dynamic>> execute(
    int businessId,
    String confirmationToken,
    AppLocalizations l10n,
  ) async {
    try {
      final res = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/fiscal-years/current/rollback/execute',
        data: {'confirmation_token': confirmationToken},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['success'] != true) {
        final msg = data['message']?.toString();
        throw Exception(msg ?? l10n.fiscalYearRollbackExecuteFailed);
      }
      return Map<String, dynamic>.from(data['data'] as Map);
    } on DioException catch (e) {
      final msg = extractApiErrorMessage(e, l10n);
      throw Exception(
        msg ?? e.message ?? l10n.fiscalYearRollbackExecuteFailedSupport,
      );
    }
  }

  /// پیام `error.message` از پاسخ استاندارد ApiError هسابیکس
  static String? extractApiErrorMessage(DioException e, AppLocalizations l10n) {
    final raw = e.response?.data;
    if (raw is! Map) {
      if (e.type == DioExceptionType.connectionTimeout) {
        return l10n.errorConnectionTimeout;
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return l10n.errorReceiveTimeout;
      }
      if (e.type == DioExceptionType.connectionError) {
        return l10n.errorConnectionError;
      }
      return null;
    }
    final d = Map<String, dynamic>.from(raw);
    final detail = d['detail'];
    if (detail is Map) {
      final err = detail['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
      }
      if (err is Map && err['code'] != null && err['message'] != null) {
        return '${err['message']}';
      }
    }
    final errTop = d['error'];
    if (errTop is Map && errTop['message'] != null) {
      return errTop['message'].toString();
    }
    return d['message']?.toString();
  }
}
