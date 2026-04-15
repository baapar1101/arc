import 'package:hesabix_ui/core/api_client.dart';

class BusinessFtpBackupService {
  final ApiClient _apiClient;

  BusinessFtpBackupService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> getSettings(int businessId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/businesses/$businessId/ftp-backup/settings');
    return Map<String, dynamic>.from((res.data?['data'] as Map?) ?? const {});
  }

  Future<Map<String, dynamic>> saveSettings(int businessId, Map<String, dynamic> body) async {
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/businesses/$businessId/ftp-backup/settings',
      data: body,
    );
    return Map<String, dynamic>.from((res.data?['data'] as Map?) ?? const {});
  }

  Future<void> deleteSettings(int businessId) async {
    await _apiClient.delete<Map<String, dynamic>>('/businesses/$businessId/ftp-backup/settings');
  }

  Future<String> startTestJob(int businessId, Map<String, dynamic> body) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/ftp-backup/test',
      data: body,
    );
    final data = (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (data['job_id'] as String?) ?? '';
  }

  Future<String> startUsageScanJob(int businessId) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/ftp-backup/usage-scan',
      data: const <String, dynamic>{},
    );
    final data = (res.data?['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (data['job_id'] as String?) ?? '';
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/jobs/$jobId');
    return Map<String, dynamic>.from((res.data?['data'] as Map?) ?? const {});
  }
}
