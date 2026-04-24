/// کمک‌کننده برای خواندن پاسخ GET /api/v1/jobs/:id
/// (پیشرفت در `meta`، خطا گاهی Map و گاهی String)
class JobStatusUtils {
  JobStatusUtils._();

  static int readProgress(Map<String, dynamic> st, int fallback) {
    final meta = st['meta'];
    if (meta is Map) {
      final p = meta['progress'];
      if (p is int) return p;
      if (p is num) return p.round();
    }
    final tp = st['progress'];
    if (tp is int) return tp;
    if (tp is num) return tp.round();
    return fallback;
  }

  static String? readRawMessage(Map<String, dynamic> st) {
    final meta = st['meta'];
    if (meta is Map && meta['message'] is String) {
      return meta['message'] as String;
    }
    final m = st['message'];
    if (m is String) return m;
    return null;
  }

  /// خطای job می‌تواند String یا Map باشد (بک‌اند structured error می‌فرستد)
  static String stringifyError(dynamic error, [String fallback = '']) {
    if (error == null) return fallback;
    if (error is String) return error;
    if (error is Map) {
      final msg = error['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      final code = error['code'];
      if (code is String && code.isNotEmpty) return code;
      return error.toString();
    }
    return '$error';
  }

  static bool isSuccessState(String state) {
    final s = state.toLowerCase();
    return s == 'succeeded' || s == 'finished' || s == 'complete' || s == 'completed';
  }

  static bool isFailedState(String state) {
    final s = state.toLowerCase();
    return s == 'failed' || s == 'error' || s == 'cancelled';
  }
}
