import 'dart:typed_data';

import 'package:hesabix_ui/core/api_client.dart';
import 'package:dio/dio.dart';

class BackupService {
  final ApiClient _apiClient;

  BackupService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> listBackups(int businessId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/businesses/$businessId/backups');
    final data = (res.data?['data']?['items'] as List?) ?? const [];
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createBackup(int businessId) async {
    final res = await _apiClient.post<Map<String, dynamic>>('/businesses/$businessId/backups', data: {}, query: {'async_mode': false});
    return (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  }

  Future<String> startBackupAsync(int businessId) async {
    final res = await _apiClient.post<Map<String, dynamic>>('/businesses/$businessId/backups', data: {}, query: {'async_mode': true});
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
}


