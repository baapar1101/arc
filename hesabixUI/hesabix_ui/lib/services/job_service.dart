import '../core/api_client.dart';
import '../utils/job_status_utils.dart';

class JobPollResult {
  const JobPollResult({
    required this.state,
    required this.progress,
    this.message,
    this.result,
    this.errorMessage,
  });

  final String state;
  final int progress;
  final String? message;
  final Map<String, dynamic>? result;
  final String? errorMessage;

  bool get isSuccess => JobStatusUtils.isSuccessState(state);
  bool get isFailed => JobStatusUtils.isFailedState(state);
  bool get isRunning =>
      !isSuccess && !isFailed && state.isNotEmpty;
}

class JobService {
  final ApiClient _apiClient;
  JobService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// دریافت وضعیت job
  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/api/v1/jobs/$jobId');
    return (res.data?['data'] as Map<String, dynamic>?) ?? const {};
  }

  /// polling تا موفقیت/شکست یا timeout
  Future<JobPollResult> pollUntilComplete(
    String jobId, {
    void Function(int progress, String? message)? onProgress,
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(minutes: 25),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var lastProgress = 0;
    String? lastMessage;

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(interval);
      final status = await getJobStatus(jobId);
      final state = (status['state'] as String?) ?? '';
      final progress = JobStatusUtils.readProgress(status, lastProgress);
      final message = JobStatusUtils.readRawMessage(status);
      lastProgress = progress;
      lastMessage = message ?? lastMessage;
      onProgress?.call(progress, message);

      if (JobStatusUtils.isSuccessState(state)) {
        final result = status['result'];
        return JobPollResult(
          state: state,
          progress: progress,
          message: message,
          result: result is Map<String, dynamic>
              ? result
              : (result is Map ? result.cast<String, dynamic>() : null),
        );
      }
      if (JobStatusUtils.isFailedState(state)) {
        return JobPollResult(
          state: state,
          progress: progress,
          message: message,
          errorMessage: JobStatusUtils.stringifyError(
            status['error'],
            'خطا در اجرای کار پس‌زمینه',
          ),
        );
      }
    }

    return JobPollResult(
      state: 'timeout',
      progress: lastProgress,
      message: lastMessage,
      errorMessage: 'زمان انتظار به پایان رسید. شناسه کار: $jobId',
    );
  }

  /// لغو job
  Future<void> cancelJob(String jobId) async {
    await _apiClient.delete('/api/v1/jobs/$jobId');
  }
}




