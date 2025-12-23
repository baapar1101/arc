import '../core/api_client.dart';

class JobService {
  final ApiClient _apiClient;
  JobService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// دریافت وضعیت job
  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/api/v1/jobs/$jobId');
    return (res.data?['data'] as Map<String, dynamic>?) ?? const {};
  }

  /// لغو job
  Future<void> cancelJob(String jobId) async {
    await _apiClient.delete('/api/v1/jobs/$jobId');
  }
}

