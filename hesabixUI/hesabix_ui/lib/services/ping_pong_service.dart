import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/ping_pong_score_model.dart';

class PingPongService {
  static final ApiClient _apiClient = ApiClient();

  /// ذخیره امتیاز جدید
  static Future<PingPongScore> saveScore({
    required int score,
    required int survivalTime,
    required int heroModeUses,
    required double difficultyLevel,
  }) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/ping-pong/scores',
        data: {
          'score': score,
          'survival_time': survivalTime,
          'hero_mode_uses': heroModeUses,
          'difficulty_level': difficultyLevel,
        },
      );

      if (response.data?['success'] == true) {
        return PingPongScore.fromJson(response.data!['data']);
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در ذخیره امتیاز');
      }
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// دریافت بهترین امتیاز کاربر
  static Future<PingPongScore?> getBestScore() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/ping-pong/scores/best',
      );

      if (response.data?['success'] == true) {
        final data = response.data!['data'];
        if (data != null) {
          return PingPongScore.fromJson(data);
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw _handleError(e);
    }
  }

  /// دریافت جدول رده‌بندی
  static Future<List<LeaderboardEntry>> getLeaderboard({
    int limit = 10,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/ping-pong/scores/leaderboard',
        query: {'limit': limit},
      );

      if (response.data?['success'] == true) {
        final List<dynamic> data = response.data!['data'] ?? [];
        return data.map((json) => LeaderboardEntry.fromJson(json)).toList();
      }
      return [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// دریافت آمار کاربر
  static Future<PingPongStats> getStats() async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/ping-pong/scores/stats',
      );

      if (response.data?['success'] == true) {
        return PingPongStats.fromJson(response.data!);
      } else {
        throw Exception(response.data?['message'] ?? 'خطا در دریافت آمار');
      }
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  static Exception _handleError(DioException e) {
    if (e.response != null) {
      final message = e.response?.data?['message'] as String?;
      return Exception(message ?? 'خطا در ارتباط با سرور');
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return Exception('زمان اتصال به سرور به پایان رسید');
    } else {
      return Exception('خطای شبکه');
    }
  }
}

