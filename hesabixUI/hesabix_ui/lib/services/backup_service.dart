import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/job_status_utils.dart';

class BackupService {
  final ApiClient _apiClient;

  BackupService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> listBackups(int businessId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/businesses/$businessId/backups');
    final data = (res.data?['data']?['items'] as List?) ?? const [];
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createBackup(int businessId, {bool uploadToFtp = false}) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/backups',
      data: {'upload_to_ftp': uploadToFtp},
      query: {'async_mode': false},
    );
    return (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<String> startBackupAsync(int businessId, {bool uploadToFtp = false}) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/backups',
      data: {'upload_to_ftp': uploadToFtp},
      query: {'async_mode': true},
    );
    final data = (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return (data['job_id'] as String?) ?? '';
  }

  Future<Uint8List> downloadBackup(int businessId, String backupId) async {
    final res = await _apiClient.get<List<int>>(
      '/businesses/$businessId/backups/$backupId/download',
      responseType: ResponseType.bytes,
      options: Options(
        headers: {'Accept': 'application/zip, application/octet-stream'},
      ),
    );
    final data = res.data ?? const <int>[];
    return Uint8List.fromList(data);
  }

  Future<bool> deleteBackup(int businessId, String backupId) async {
    final res = await _apiClient.delete<Map<String, dynamic>>('/businesses/$businessId/backups/$backupId');
    return (res.data?['data']?['deleted'] == true);
  }

  Future<Map<String, dynamic>> restoreFromBackupId(int businessId, String backupId, {String mode = 'new_business'}) async {
    final body = {'backup_id': backupId, 'mode': mode};
    final res = await _apiClient.post<Map<String, dynamic>>('/businesses/$businessId/backups/restore', data: body, query: {'async_mode': false});
    return (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<String> startRestoreAsync(int businessId, String backupId, {String mode = 'replace'}) async {
    final body = {'backup_id': backupId, 'mode': mode};
    final res = await _apiClient.post<Map<String, dynamic>>('/businesses/$businessId/backups/restore', data: body, query: {'async_mode': true});
    final data = (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return (data['job_id'] as String?) ?? '';
  }

  Future<String> startRestoreFromFileAsync(
    int businessId, {
    String? filePath,
    Uint8List? fileBytes,
    String? filename,
    String mode = 'replace',
  }) async {
    MultipartFile file;
    
    // اگر bytes موجود باشد (برای وب)، از آن استفاده می‌کنیم
    if (fileBytes != null) {
      file = MultipartFile.fromBytes(
        fileBytes,
        filename: filename ?? 'backup.hbx',
      );
    } else if (filePath != null) {
      // اگر path موجود باشد (برای موبایل/دسکتاپ)، از آن استفاده می‌کنیم
      file = await MultipartFile.fromFile(filePath, filename: filename);
    } else {
      throw Exception('Either filePath or fileBytes must be provided');
    }
    
    final form = FormData.fromMap({
      'mode': mode,
      'file': file,
    });
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/backups/restore',
      data: form,
      query: {'async_mode': true},
      options: Options(contentType: 'multipart/form-data', headers: {'Content-Type': 'multipart/form-data'}),
    );
    final data = (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return (data['job_id'] as String?) ?? '';
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/jobs/$jobId');
    return (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  /// منتظر اتمام job پشتیبان/بازیابی می‌ماند؛ در خطا [Exception] با پیام قابل نمایش.
  Future<void> waitForJobUntilDone(
    String jobId,
    AppLocalizations l10n, {
    void Function(int progress, String? message)? onProgress,
    Duration pollInterval = const Duration(seconds: 1),
    Duration timeout = const Duration(minutes: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var lastProgress = 0;
    while (DateTime.now().isBefore(deadline)) {
      final st = await getJobStatus(jobId);
      lastProgress = JobStatusUtils.readProgress(st, lastProgress);
      onProgress?.call(lastProgress, JobStatusUtils.readRawMessage(st));
      final state = (st['state'] as String?) ?? '';
      if (JobStatusUtils.isSuccessState(state)) {
        return;
      }
      if (JobStatusUtils.isFailedState(state)) {
        final errorData = st['error_data'];
        if (errorData is Map) {
          final code = errorData['error'] as String?;
          if (code == 'STORAGE_LIMIT_EXCEEDED' || code == 'NO_ACTIVE_STORAGE_PLAN') {
            final msg =
                errorData['message'] as String? ?? l10n.backupJobStorageLimitFallback;
            throw Exception(msg);
          }
        }
        final err = JobStatusUtils.stringifyError(st['error'], l10n.backupFailed);
        throw Exception(err);
      }
      await Future.delayed(pollInterval);
    }
    throw Exception(l10n.backupJobWaitTimeout);
  }
}


