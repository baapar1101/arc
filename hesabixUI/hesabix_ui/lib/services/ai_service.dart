import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../models/ai_models.dart';

class AIService {
  final ApiClient _api;
  AIService(this._api);

  // ========== Admin: AI Config ==========
  Future<AIConfig> getAIConfig() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/ai/config');
    final body = res.data as Map<String, dynamic>;
    return AIConfig.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIConfig> updateAIConfig(Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/config',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIConfig.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> testAIConnection() async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/config/test-connection',
    );
    return res.data as Map<String, dynamic>;
  }

  // ========== Admin: AI Plans ==========
  Future<List<AIPlan>> listAIPlans({bool? onlyActive}) async {
    final query = <String, dynamic>{};
    if (onlyActive != null) {
      query['only_active'] = onlyActive;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/plans',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => AIPlan.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AIPlan> getAIPlan(int planId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/ai/plans/$planId');
    final body = res.data as Map<String, dynamic>;
    return AIPlan.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIPlan> createAIPlan(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/plans',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPlan.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIPlan> updateAIPlan(int planId, Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/plans/$planId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPlan.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteAIPlan(int planId) async {
    await _api.delete('/api/v1/admin/ai/plans/$planId');
  }

  // ========== Admin: AI Prompts ==========
  Future<List<AIPrompt>> listDefaultPrompts({String? role}) async {
    final query = <String, dynamic>{};
    if (role != null) {
      query['role'] = role;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/prompts/default',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => AIPrompt.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AIPrompt> createDefaultPrompt(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/prompts/default',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIPrompt> updateDefaultPrompt(int promptId, Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/prompts/default/$promptId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteDefaultPrompt(int promptId) async {
    await _api.delete('/api/v1/admin/ai/prompts/default/$promptId');
  }

  // ========== User: Chat ==========
  Future<List<AIChatSession>> listChatSessions({
    int? businessId,
    int limit = 50,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.toString(),
      'skip': skip.toString(),
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => AIChatSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AIChatSession> createChatSession({
    int? businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions',
      data: {
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return AIChatSession.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<AIChatMessage>> getSessionMessages({
    required int sessionId,
    int limit = 100,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.toString(),
      'skip': skip.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/messages',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => AIChatMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> sendMessage({
    required int sessionId,
    required String content,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/messages',
      data: {'content': content},
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  /// ارسال پیام به صورت streaming
  /// 
  /// Returns a Stream<String> که هر chunk محتوای جدید است
  /// onComplete callback با usage stats فراخوانی می‌شود
  Stream<String> sendMessageStream({
    required int sessionId,
    required String content,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
  }) async* {
    try {
      // Use ApiClient with streaming response type
      debugPrint('[AIService] Starting streaming request for session $sessionId');
      final response = await _api.post<ResponseBody>(
        '/api/v1/ai/chat/sessions/$sessionId/messages?stream=true',
        data: {'content': content},
        responseType: ResponseType.stream,
        options: Options(
          receiveTimeout: const Duration(seconds: 30), // timeout 30 ثانیه
          sendTimeout: const Duration(seconds: 30),
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
        ),
      );

      final responseBody = response.data;
      if (responseBody == null) {
        debugPrint('[AIService] Empty streaming response body');
        onError?.call('Empty response');
        return;
      }

      // Transform stream to UTF-8 decoded lines
      final lineStream = responseBody.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final List<String> eventBuffer = [];

      await for (final rawLine in lineStream) {
        debugPrint('[AIService] SSE raw line: $rawLine');
        final line = rawLine.trimRight();

        // Empty line → event separator
        if (line.isEmpty) {
          if (eventBuffer.isEmpty) {
            continue;
          }

          final payload = eventBuffer.join('\n');
          eventBuffer.clear();

          Map<String, dynamic> data;
          try {
            data = jsonDecode(payload) as Map<String, dynamic>;
            debugPrint('[AIService] SSE event payload: $data');
          } catch (_) {
            debugPrint('[AIService] Failed to decode SSE payload: $payload');
            continue;
          }

              if (data.containsKey('error')) {
            final errorMessage = data['error'] as String? ?? 'خطای نامشخص در استریم';
            debugPrint('[AIService] SSE error event: $errorMessage');
            onError?.call(errorMessage);
                return;
              }
              
              final done = data['done'] as bool? ?? false;
          final contentChunk = data['content'] as String? ?? '';
              
              if (contentChunk.isNotEmpty) {
                yield contentChunk;
              }
              
              if (done) {
                final usage = data['usage'] as Map<String, dynamic>?;
                final messageId = data['message_id'] as int?;
                onComplete?.call(usage, messageId);
                return;
              }
              continue;
            }

        if (line.startsWith('data:')) {
          // Support both "data: " and "data:"
          final value = line.length > 5 && line[5] == ' '
              ? line.substring(6)
              : line.substring(5);
          eventBuffer.add(value);
          }
        }

      // Flush remaining buffer if stream ended without trailing newline
      if (eventBuffer.isNotEmpty) {
        final payload = eventBuffer.join('\n');
        Map<String, dynamic> data;
        try {
          data = jsonDecode(payload) as Map<String, dynamic>;
          debugPrint('[AIService] SSE final payload: $data');
        } catch (_) {
          debugPrint('[AIService] Failed to decode final SSE payload: $payload');
          return;
        }

        if (data.containsKey('error')) {
          final errorMessage = data['error'] as String? ?? 'خطای نامشخص در استریم';
          debugPrint('[AIService] SSE final error event: $errorMessage');
          onError?.call(errorMessage);
          return;
        }

        final contentChunk = data['content'] as String? ?? '';
        if (contentChunk.isNotEmpty) {
          yield contentChunk;
        }

        final usage = data['usage'] as Map<String, dynamic>?;
        final messageId = data['message_id'] as int?;
        onComplete?.call(usage, messageId);
      }
    } catch (e, stack) {
      debugPrint('[AIService] Streaming error: $e');
      debugPrintStack(stackTrace: stack);
      onError?.call(e.toString());
      rethrow;
    }
  }

  Future<void> deleteChatSession(int sessionId) async {
    await _api.delete('/api/v1/ai/chat/sessions/$sessionId');
  }

  // ========== User: Subscription ==========
  Future<UserAISubscription?> getCurrentSubscription({int? businessId}) async {
    try {
      final query = <String, dynamic>{};
      if (businessId != null) {
        query['business_id'] = businessId.toString();
      }
      final res = await _api.get<Map<String, dynamic>>(
        '/api/v1/ai/subscription/current',
        query: query,
      );
      final body = res.data as Map<String, dynamic>;
      final data = body['data'];
      if (data == null) return null;
      return UserAISubscription.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<UserAISubscription> subscribeToPlan({
    required int planId,
    int? businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/subscription/subscribe',
      data: {
        'plan_id': planId,
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    final subscriptionJson = data is Map<String, dynamic>
        ? data['subscription'] ?? data
        : data;
    return UserAISubscription.fromJson(
      Map<String, dynamic>.from(subscriptionJson as Map),
    );
  }

  Future<UserAISubscription> upgradeSubscription({
    required int newPlanId,
    int? businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/subscription/upgrade',
      data: {
        'plan_id': newPlanId,
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    final subscriptionJson = data is Map<String, dynamic>
        ? data['subscription'] ?? data
        : data;
    return UserAISubscription.fromJson(
      Map<String, dynamic>.from(subscriptionJson as Map),
    );
  }

  Future<void> cancelSubscription({int? businessId}) async {
    final query = <String, dynamic>{};
    if (businessId != null) {
      query['business_id'] = businessId.toString();
    }
    await _api.post('/api/v1/ai/subscription/cancel', query: query);
  }

  // ========== User: Personal Prompts ==========
  Future<List<AIPrompt>> getMyPrompts() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/ai/prompts/my');
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => AIPrompt.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AIPrompt> createMyPrompt(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/prompts/my',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIPrompt> updateMyPrompt(int promptId, Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/ai/prompts/my/$promptId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteMyPrompt(int promptId) async {
    await _api.delete('/api/v1/ai/prompts/my/$promptId');
  }

  // ========== User: Usage Stats ==========
  Future<AIUsageStats> getUsageStats({
    int? businessId,
    String? startDate,
    String? endDate,
  }) async {
    final query = <String, dynamic>{};
    if (businessId != null) {
      query['business_id'] = businessId.toString();
    }
    if (startDate != null) {
      query['start_date'] = startDate;
    }
    if (endDate != null) {
      query['end_date'] = endDate;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/usage/stats',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return AIUsageStats.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<List<AIUsageLog>> getUsageLogs({
    int? businessId,
    int limit = 50,
    int skip = 0,
    String? startDate,
    String? endDate,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.toString(),
      'skip': skip.toString(),
      if (businessId != null) 'business_id': businessId.toString(),
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/usage/logs',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => AIUsageLog.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getInvoices({
    int? businessId,
    String? invoiceType,
    int limit = 50,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.toString(),
      'skip': skip.toString(),
      if (businessId != null) 'business_id': businessId.toString(),
      if (invoiceType != null) 'invoice_type': invoiceType,
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/usage/invoices',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ========== Support: AI Ticket Suggestions ==========
  Future<Map<String, dynamic>> suggestTicketReply({
    required int ticketId,
    String? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/support/tickets/$ticketId/ai-suggest-reply',
      data: {
        if (context != null) 'context': context,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> autoReplyTicket({
    required int ticketId,
    String? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/support/tickets/$ticketId/ai-auto-reply',
      data: {
        if (context != null) 'context': context,
      },
    );
    return res.data as Map<String, dynamic>;
  }
}

