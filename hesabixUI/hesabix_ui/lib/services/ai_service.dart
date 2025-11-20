import 'package:dio/dio.dart';
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
    required String title,
    int? businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions',
      data: {
        'title': title,
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

