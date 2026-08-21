import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../utils/error_extractor.dart';
import '../models/ai_models.dart';
import '../models/ai_voice_models.dart';
import '../models/ai_stream_event.dart';
import '../widgets/ai/ai_subagent_restore.dart';
import 'ai_sse_client.dart';

// Enable debug prints
bool get debugPrintEnabled => kDebugMode;

/// مدل‌های کند (مثلاً روی gateway) ممکن است بیش از ۳۰s پاسخ دهند؛ ApiClient پیش‌فرض ۳۰s است.
const Duration _kLongAiHttpTimeout = Duration(minutes: 5);

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
      options: Options(
        receiveTimeout: _kLongAiHttpTimeout,
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    return res.data as Map<String, dynamic>;
  }

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
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/plans/$planId',
    );
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

  // ========== Admin: AI Models ==========
  Future<List<AIModelCatalogItem>> listAIModels({bool? onlyActive}) async {
    final query = <String, dynamic>{};
    if (onlyActive != null) query['only_active'] = onlyActive;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/models',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data
        .map((e) => AIModelCatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AIModelCatalogItem> createAIModel(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/models',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIModelCatalogItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIModelCatalogItem> updateAIModel(
    int modelId,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/models/$modelId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIModelCatalogItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteAIModel(int modelId) async {
    await _api.delete('/api/v1/admin/ai/models/$modelId');
  }

  Future<Map<String, dynamic>> seedAIModelsFromConfig({
    bool includePresets = true,
    bool force = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/models/seed-from-config',
      data: {
        'include_presets': includePresets,
        'force': force,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<List<AIVoiceModelItem>> listAdminVoiceModels({String? kind}) async {
    final query = <String, dynamic>{};
    if (kind != null) query['kind'] = kind;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/voice-models',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List? ?? const [];
    return data
        .whereType<Map>()
        .map((e) => AIVoiceModelItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<AIVoiceModelItem> createAdminVoiceModel(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/voice-models',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIVoiceModelItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIVoiceModelItem> updateAdminVoiceModel(
    int modelId,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/voice-models/$modelId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIVoiceModelItem.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteAdminVoiceModel(int modelId) async {
    await _api.delete('/api/v1/admin/ai/voice-models/$modelId');
  }

  Future<Map<String, dynamic>> seedAdminVoiceModels({bool force = false}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/voice-models/seed-from-env',
      data: {'force': force},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> getAdminVoicePolicy() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/voice-models/policy',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> updateAdminVoicePolicy(
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/voice-models/policy',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> testAdminVoiceModel(
    int modelId, {
    String? text,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/voice-models/$modelId/test',
      data: {if (text != null) 'text': text},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> listAIProviderCredentials() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/provider-credentials',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> upsertAIProviderCredential(
    String provider,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/provider-credentials/$provider',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> syncAIProviderCredentialsFromConfig() async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/provider-credentials/sync-from-config',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> testAIProviderConnection(
    String provider, {
    String? model,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/provider-credentials/$provider/test-connection',
      data: {if (model != null) 'model': model},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  // ========== Business: BYOK provider ==========
  Future<Map<String, dynamic>> getBusinessAIProvider(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai-provider',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> saveBusinessAIProvider(
    int businessId,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai-provider',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> testBusinessAIProvider(
    int businessId, {
    String? model,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai-provider/test',
      data: {if (model != null) 'model': model},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> deleteBusinessAIProvider(int businessId) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai-provider',
    );
  }

  // ========== User: AI Models ==========
  Future<List<AIModelCatalogItem>> listAvailableAIModels({int? businessId}) async {
    final result = await listAvailableAIModelsResult(businessId: businessId);
    return result.models;
  }

  /// کاتالوگ مدل‌ها به‌همراه preferred/plan default (یک درخواست).
  Future<({List<AIModelCatalogItem> models, String? preferredModelCode})>
      listAvailableAIModelsResult({int? businessId}) async {
    final query = <String, dynamic>{};
    if (businessId != null) query['business_id'] = businessId;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/models',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final models = (data['models'] as List? ?? [])
        .map((e) => AIModelCatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final preferred = data['preferred_model_code'] as String? ??
        data['plan_default_model'] as String?;
    return (models: models, preferredModelCode: preferred);
  }

  Future<String?> getPreferredModelCode({int? businessId}) async {
    final result = await listAvailableAIModelsResult(businessId: businessId);
    return result.preferredModelCode;
  }

  Future<void> setPreferredModel({
    required String modelCode,
    int? businessId,
  }) async {
    await _api.put<Map<String, dynamic>>(
      '/api/v1/ai/subscription/preferred-model',
      data: {
        'model_code': modelCode,
        if (businessId != null) 'business_id': businessId,
      },
    );
  }

  Future<AIVoiceCatalog> getVoiceCatalog({int? businessId}) async {
    final query = <String, dynamic>{};
    if (businessId != null) query['business_id'] = businessId;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/voice/catalog',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return AIVoiceCatalog.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getBusinessVoiceSettings(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/voice/settings',
      query: {'business_id': businessId},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> saveBusinessVoiceSettings(
    int businessId,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/ai/voice/settings',
      query: {'business_id': businessId},
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<String> transcribeVoice({
    required List<int> wavBytes,
    int? businessId,
    String? sttCode,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        wavBytes,
        filename: 'dictate.wav',
        contentType: DioMediaType('audio', 'wav'),
      ),
      if (sttCode != null && sttCode.isNotEmpty) 'stt_code': sttCode,
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/voice/stt',
      data: form,
      query: {if (businessId != null) 'business_id': businessId},
      options: Options(
        sendTimeout: _kLongAiHttpTimeout,
        receiveTimeout: _kLongAiHttpTimeout,
      ),
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    return (data['text'] as String? ?? '').trim();
  }

  Future<List<int>> synthesizeVoice({
    required String text,
    int? businessId,
    String? ttsCode,
  }) async {
    final res = await _api.post<List<int>>(
      '/api/v1/ai/voice/tts',
      data: {
        'text': text,
        if (ttsCode != null && ttsCode.isNotEmpty) 'tts_code': ttsCode,
      },
      query: {if (businessId != null) 'business_id': businessId},
      options: Options(
        responseType: ResponseType.bytes,
        sendTimeout: _kLongAiHttpTimeout,
        receiveTimeout: _kLongAiHttpTimeout,
      ),
    );
    final data = res.data;
    if (data == null) return const [];
    return data;
  }

  Future<List<AIPlan>> listPublicAIPlans({int? businessId}) async {
    final query = <String, dynamic>{};
    if (businessId != null) query['business_id'] = businessId;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/subscription/plans',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final plans = data['plans'] as List? ?? [];
    return plans
        .map((e) => AIPlan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ========== Admin: AI Prompts ==========
  Future<List<AIPrompt>> listDefaultPrompts({String? role, String? category}) async {
    final query = <String, dynamic>{};
    if (role != null) {
      query['role'] = role;
    }
    if (category != null) {
      query['category'] = category;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/prompts/default',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data
        .map((e) => AIPrompt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AIPrompt> updateDefaultPromptByKey(
    String promptKey,
    String content,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/prompts/default/$promptKey',
      data: {'content': content},
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIPrompt> resetDefaultPrompt(String promptKey) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/prompts/default/$promptKey/reset',
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<void> deleteDefaultPrompt(String promptKey) async {
    await _api.delete('/api/v1/admin/ai/prompts/default/$promptKey');
  }

  // ========== User: Chat ==========

  /// بررسی امکان استفاده از AI (چک پیشگیرانه)
  Future<Map<String, dynamic>> checkAvailability({
    int? businessId,
    int estimatedTokens = 1000,
    String? model,
    String? userQuery,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/check-availability',
      data: {
        if (businessId != null) 'business_id': businessId,
        'estimated_tokens': estimatedTokens,
        if (model != null && model.isNotEmpty) 'model': model,
        if (userQuery != null && userQuery.isNotEmpty) 'user_query': userQuery,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getChatSuggestions({
    int? businessId,
  }) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/suggestions',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getAIMemory({int? businessId}) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateAIMemory({
    required String content,
    int? businessId,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory',
      data: {
        'content': content,
        'instructions': content,
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateAIMemoryItem({
    required int itemId,
    required String content,
    int? businessId,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory/items/$itemId',
      data: {
        'content': content,
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pinAIMemoryEntry({
    required String content,
    String kind = 'context',
    int? businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory/entries',
      data: {
        'content': content,
        'kind': kind,
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<void> deleteAIMemoryItem({
    required int itemId,
    int? businessId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory/items/$itemId',
      query: {if (businessId != null) 'business_id': businessId.toString()},
    );
  }

  Future<void> deleteAIMemory({int? businessId}) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory',
      query: {if (businessId != null) 'business_id': businessId.toString()},
    );
  }

  Future<List<Map<String, dynamic>>> listSessionAttachments(
    int sessionId,
  ) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/attachments',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> uploadSessionAttachment({
    required int sessionId,
    required String filename,
    required List<int> bytes,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/attachments',
      data: formData,
      options: Options(
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<void> deleteSessionAttachment({
    required int sessionId,
    required int attachmentId,
  }) async {
    await _api.delete(
      '/api/v1/ai/chat/sessions/$sessionId/attachments/$attachmentId',
    );
  }

  Future<List<Map<String, dynamic>>> searchSessionMessages({
    required int sessionId,
    required String query,
    int limit = 30,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/messages/search',
      query: {'q': query, 'limit': limit.toString()},
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getBusinessInsights({int? businessId}) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/insights',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<AIChatSession>> listChatSessions({
    int? businessId,
    int limit = 50,
    int skip = 0,
    String? search,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.toString(),
      'skip': skip.toString(),
      if (businessId != null) 'business_id': businessId.toString(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data
        .map((e) => AIChatSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AIChatSession?> getChatSession({required int sessionId}) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '/api/v1/ai/chat/sessions/$sessionId',
      );
      final data = res.data?['data'];
      if (data is Map<String, dynamic>) {
        return AIChatSession.fromJson(data);
      }
    } catch (e) {
      debugPrint('[AIService] getChatSession failed: $e');
    }
    return null;
  }

  Future<AIChatActiveRun?> getActiveAgentRun({required int sessionId}) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '/api/v1/ai/chat/sessions/$sessionId/active-run',
      );
      final data = res.data?['data'];
      if (data is Map<String, dynamic>) {
        return AIChatActiveRun.fromJson(data);
      }
    } catch (e) {
      debugPrint('[AIService] getActiveAgentRun failed: $e');
    }
    return null;
  }

  Future<void> cancelAgentRun({
    required int sessionId,
    required String runId,
  }) async {
    try {
      await _api.post(
        '/api/v1/ai/chat/sessions/$sessionId/runs/$runId/cancel',
        data: const <String, dynamic>{},
      );
    } catch (e) {
      debugPrint('[AIService] cancelAgentRun failed: $e');
    }
  }

  Future<AIChatSession> createChatSession({
    int? businessId,
    String? executionMode,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions',
      data: {
        if (businessId != null) 'business_id': businessId,
        if (executionMode != null) 'execution_mode': executionMode,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return AIChatSession.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIChatSession> updateChatSession({
    required int sessionId,
    String? executionMode,
    String? title,
  }) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId',
      data: {
        if (executionMode != null) 'execution_mode': executionMode,
        if (title != null) 'title': title,
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
    return data
        .map((e) => AIChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AIChatSubagentSummary>> listSessionSubagents(int sessionId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/subagents',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    final rawItems = data is Map ? data['items'] : null;
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((e) => AIChatSubagentSummary.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.subagentId.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> sendMessage({
    required int sessionId,
    required String content,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/messages',
      data: {'content': content},
      options: Options(
        receiveTimeout: _kLongAiHttpTimeout,
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  /// ارسال پیام به صورت streaming (متن، رویداد ابزار، پایان)
  Stream<AIStreamChunk> sendMessageStream({
    required int sessionId,
    required String content,
    bool approveWrites = false,
    bool silent = false,
    String? explorationMode,
    String? executionMode,
    String? model,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
    AISseCursor? sseCursor,
  }) async* {
    try {
      final query = <String, dynamic>{'stream': true};
      if (explorationMode != null && explorationMode.isNotEmpty) {
        query['mode'] = explorationMode;
      }
      final payload = <String, dynamic>{
        'content': content,
        'approve_writes': approveWrites,
        if (silent) 'silent': true,
        if (explorationMode != null && explorationMode.isNotEmpty)
          'mode': explorationMode,
        if (executionMode != null && executionMode.isNotEmpty)
          'execution_mode': executionMode,
        if (model != null && model.isNotEmpty) 'model': model,
      };
      final endpoint = '/api/v1/ai/chat/sessions/$sessionId/messages';
      if (kIsWeb) {
        final uri = _api.resolveUri(endpoint, query: query);
        final headers = _api.streamingHeadersFor(uri);
        await for (final eventPayload in postSsePayloads(
          uri: uri,
          headers: headers,
          body: jsonEncode(payload),
          cancelToken: cancelToken,
          onEventId: (id) => sseCursor?.lastEventId = id,
        )) {
          final chunk = _parseSsePayload(
            eventPayload,
            onError,
            onComplete,
            cursor: sseCursor,
          );
          if (chunk != null) yield chunk;
        }
        return;
      }
      final response = await _api.post<ResponseBody>(
        endpoint,
        query: query,
        data: payload,
        responseType: ResponseType.stream,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(seconds: 60),
          headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
        ),
        cancelToken: cancelToken,
      );

      final responseBody = response.data;
      if (responseBody == null) {
        onError?.call('Empty response');
        return;
      }

      final lineStream = responseBody.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final eventBuffer = <String>[];

      await for (final rawLine in lineStream) {
        final line = rawLine.trimRight();
        if (line.isEmpty) {
          if (eventBuffer.isEmpty) continue;
          final chunk = _parseSsePayload(
            eventBuffer.join('\n'),
            onError,
            onComplete,
            cursor: sseCursor,
          );
          eventBuffer.clear();
          if (chunk != null) yield chunk;
          continue;
        }
        if (line.startsWith('id:')) {
          final id = int.tryParse(line.substring(3).trim());
          if (id != null) sseCursor?.lastEventId = id;
          continue;
        }
        if (line.startsWith('data:')) {
          final value = line.length > 5 && line[5] == ' '
              ? line.substring(6)
              : line.substring(5);
          eventBuffer.add(value);
        }
      }

      if (eventBuffer.isNotEmpty) {
        final chunk = _parseSsePayload(
          eventBuffer.join('\n'),
          onError,
          onComplete,
          cursor: sseCursor,
        );
        if (chunk != null) yield chunk;
      }
    } catch (e, stack) {
      debugPrint('[AIService] Streaming error: $e');
      debugPrintStack(stackTrace: stack);
      onError?.call(ErrorExtractor.userMessage(e));
      rethrow;
    }
  }

  AIStreamChunk? _parseSsePayload(
    String payload,
    void Function(String error)? onError,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete, {
    AISseCursor? cursor,
  }) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final eventType = data['type'] as String?;
    final runId = data['run_id'] as String?;
    final sseId = (data['sse_id'] as num?)?.toInt();
    final canContinue = data['can_continue'] as bool?;
    if (cursor != null) {
      if (sseId != null) cursor.lastEventId = sseId;
      if (runId != null && runId.isNotEmpty) cursor.runId = runId;
    }

    if (data.containsKey('error') &&
        ((data['done'] as bool? ?? false) || eventType == 'error')) {
      final errorMessage = data['error'] as String? ?? 'خطای نامشخص';
      // خطا به‌صورت chunk به UI می‌رسد تا یک مسیر بازیابی واحد باشد؛
      // onError فقط برای شکست شبکه/پارس در لایهٔ استریم است.
      return AIStreamChunk(
        error: errorMessage,
        done: data['done'] as bool? ?? true,
        recoverable: data['recoverable'] as bool? ?? false,
        suggestedAction: data['suggested_action'] as String?,
        errorCode: data['error_code'] as String?,
        runId: runId,
        sseId: sseId,
        canContinue: canContinue,
      );
    }
    if (eventType == 'agent_run' || eventType == 'run_resumed') {
      return AIStreamChunk(
        runId: runId,
        sseId: sseId,
        canContinue: canContinue,
      );
    }
    if (eventType == 'status') {
      return AIStreamChunk(
        statusEvent: AIStreamStatusEvent(
          phase: data['phase'] as String? ?? 'thinking',
          step: data['step'] as String?,
          toolKey: data['tool_key'] as String?,
          iteration: data['iteration'] as int?,
          maxIterations: data['max_iterations'] as int?,
        ),
      );
    }
    if (eventType == 'heartbeat') {
      return AIStreamChunk(heartbeatElapsedMs: data['elapsed_ms'] as int? ?? 0);
    }
    if (eventType == 'tool_start' || eventType == 'tool_end') {
      return AIStreamChunk(
        toolEvent: AIStreamToolEvent(
          type: eventType!,
          tool: data['tool'] as String? ?? '',
          toolKey: data['tool_key'] as String?,
          label: data['label'] as String?,
          success: data['success'] as bool?,
          approvalRequired: data['approval_required'] as bool? ?? false,
          approvalDetail: data['approval_detail'] is Map
              ? Map<String, dynamic>.from(data['approval_detail'] as Map)
              : null,
        ),
      );
    }
    if (eventType == 'session_todo_snapshot') {
      final rawItems = data['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => AISessionTodoItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <AISessionTodoItem>[];
      final rawSummary = data['summary'];
      return AIStreamChunk(
        todoSnapshot: AISessionTodoSnapshot(
          items: items,
          summary: rawSummary is Map
              ? AISessionTodoSummary.fromJson(
                  Map<String, dynamic>.from(rawSummary),
                )
              : AISessionTodoSummary.fromItems(items),
          planTitle: data['plan_title'] as String?,
        ),
      );
    }
    if (eventType == 'trace_step' || eventType == 'trace_step_update') {
      final step = AIAgentTraceStep.fromJson(data);
      return AIStreamChunk(traceStep: step);
    }
    if (eventType == 'context_usage') {
      return AIStreamChunk(contextUsage: AIStreamContextUsage.fromJson(data));
    }
    if (eventType == 'agent_budget') {
      return AIStreamChunk(
        agentBudget: AIStreamAgentBudget.fromJson(data),
      );
    }

    final done = data['done'] as bool? ?? false;
    final content = data['content'] as String? ?? '';

    if (done) {
      onComplete?.call(
        data['usage'] as Map<String, dynamic>?,
        data['message_id'] as int?,
      );
      List<AIAgentTraceStep>? agentTrace;
      final rawTrace = data['agent_trace'];
      if (rawTrace is List) {
        agentTrace = rawTrace
            .whereType<Map>()
            .map((e) => AIAgentTraceStep.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      AIStreamAgentBudget? agentBudget;
      if (data['agent_budget'] is Map) {
        agentBudget = AIStreamAgentBudget.fromJson(
          Map<String, dynamic>.from(data['agent_budget'] as Map),
        );
      }
      return AIStreamChunk(
        done: true,
        messageId: data['message_id'] as int?,
        functionCalls: data['function_calls'],
        functionResults: () {
          final fr = data['function_results'];
          final cites = data['citations'];
          final skills = data['activated_skills'];
          if ((cites is List && cites.isNotEmpty) ||
              (skills is List && skills.isNotEmpty)) {
            final map = fr is Map
                ? Map<String, dynamic>.from(fr)
                : <String, dynamic>{};
            if (cites is List && cites.isNotEmpty) {
              map.putIfAbsent(kAgentCitationsStorageKey, () => cites);
            }
            if (skills is List && skills.isNotEmpty) {
              map.putIfAbsent(kActivatedSkillsStorageKey, () => skills);
            }
            return map;
          }
          return fr;
        }(),
        agentTrace: agentTrace,
        agentBudget: agentBudget,
        requestedModel: data['requested_model'] as String?,
        resolvedModel: data['resolved_model'] as String?,
        awaitingApproval: data['awaiting_approval'] as bool?,
        citationsContext: data['citations_context'] as String?,
        executionMode: data['execution_mode'] as String?,
        runId: runId,
        sseId: sseId,
        canContinue: canContinue,
        finalContent: _assistFinalText(data),
      );
    }

    if (content.isNotEmpty) {
      return AIStreamChunk(contentDelta: content);
    }
    return null;
  }

  static String? _assistFinalText(Map<String, dynamic> data) {
    for (final key in [
      'final_content',
      'summary',
      'suggested_reply',
      'suggested_text',
    ]) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  /// ادامهٔ همان run پس از قطع استریم یا سقف بودجه
  Stream<AIStreamChunk> continueAgentRunStream({
    required int sessionId,
    required String runId,
    bool approveWrites = false,
    String? executionMode,
    String? model,
    AISseCursor? sseCursor,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
  }) {
    final headers = <String, dynamic>{};
    if (sseCursor?.lastEventId != null) {
      headers['Last-Event-ID'] = '${sseCursor!.lastEventId}';
    }
    return _postSseStream(
      '/api/v1/ai/chat/sessions/$sessionId/runs/$runId/continue?stream=true',
      data: {
        'approve_writes': approveWrites,
        if (executionMode != null && executionMode.isNotEmpty)
          'execution_mode': executionMode,
        if (model != null && model.isNotEmpty) 'model': model,
        if (sseCursor?.lastEventId != null) 'last_event_id': sseCursor!.lastEventId,
      },
      onComplete: onComplete,
      onError: onError,
      cancelToken: cancelToken,
      logLabel: 'ContinueRun',
      sseCursor: sseCursor,
    );
  }

  /// اشتراک مجدد به run زنده بدون اجرای دوبارهٔ ایجنت.
  Stream<AIStreamChunk> subscribeAgentRunStream({
    required int sessionId,
    required String runId,
    AISseCursor? sseCursor,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
  }) {
    return _postSseStream(
      '/api/v1/ai/chat/sessions/$sessionId/runs/$runId/events',
      data: {
        if (sseCursor?.lastEventId != null) 'last_event_id': sseCursor!.lastEventId,
      },
      onComplete: onComplete,
      onError: onError,
      cancelToken: cancelToken,
      logLabel: 'SubscribeRun',
      sseCursor: sseCursor,
    );
  }

  /// تولید مجدد آخرین پاسخ (همان قرارداد استریم sendMessageStream)
  Stream<AIStreamChunk> regenerateLastResponseStream({
    required int sessionId,
    bool approveWrites = false,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
  }) {
    return _postSseStream(
      '/api/v1/ai/chat/sessions/$sessionId/regenerate?stream=true',
      data: {},
      query: {'approve_writes': approveWrites},
      onComplete: onComplete,
      onError: onError,
      cancelToken: cancelToken,
      logLabel: 'Regenerate',
    );
  }

  /// ویرایش پیام کاربر و تولید پاسخ جدید (استریم)
  Future<Map<String, dynamic>> editChatMessage({
    required int sessionId,
    required int messageId,
    required String content,
    bool regenerateAfter = true,
    bool approveWrites = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/messages/$messageId/edit?stream=false',
      data: {
        'content': content,
        'approve_writes': approveWrites,
        'regenerate_after': regenerateAfter,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getProactiveAlerts({
    int? businessId,
  }) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/alerts',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final alerts = data['alerts'] as List? ?? [];
    return alerts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> submitMessageFeedback({
    required int sessionId,
    required int messageId,
    required int rating,
    String? comment,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/messages/$messageId/feedback',
      data: {
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listConnectors({int? businessId}) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/connectors',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createConnector({
    required String title,
    required String url,
    String? name,
    String? description,
    String httpMethod = 'GET',
    Map<String, String>? headers,
    String? bodyTemplate,
    int? businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/connectors',
      data: {
        'title': title,
        'url': url,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        'http_method': httpMethod,
        if (headers != null) 'headers': headers,
        if (bodyTemplate != null) 'body_template': bodyTemplate,
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<void> deleteConnector({
    required int connectorId,
    int? businessId,
  }) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    await _api.delete('/api/v1/ai/chat/connectors/$connectorId', query: query);
  }

  // ========== Admin: AI Eval ==========
  Future<List<Map<String, dynamic>>> listEvalCases() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/eval/cases',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> seedDefaultEvalCases() async {
    await _api.post('/api/v1/admin/ai/eval/cases/seed-defaults');
  }

  Future<Map<String, dynamic>> runEvalSuite({
    int? businessId,
    List<int>? caseIds,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/eval/runs',
      data: {
        if (businessId != null) 'business_id': businessId,
        if (caseIds != null) 'case_ids': caseIds,
      },
      options: Options(
        receiveTimeout: const Duration(minutes: 15),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getFeedbackAnalytics({
    int? businessId,
    int days = 30,
  }) async {
    final query = <String, dynamic>{
      'days': days.toString(),
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/feedback/analytics',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getEvalSchedule() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/eval/schedule',
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateEvalSchedule(
    Map<String, dynamic> data,
  ) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/ai/eval/schedule',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runEvalScheduleNow() async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/eval/schedule/run-now',
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listEvalRuns() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/ai/eval/runs',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> reindexKnowledge({int? businessId}) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/knowledge/reindex',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Stream<AIStreamChunk> editUserMessageStream({
    required int sessionId,
    required int messageId,
    required String content,
    bool regenerateAfter = true,
    bool approveWrites = false,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
  }) {
    return _postSseStream(
      '/api/v1/ai/chat/sessions/$sessionId/messages/$messageId/edit?stream=true',
      data: {
        'content': content,
        'approve_writes': approveWrites,
        'regenerate_after': regenerateAfter,
      },
      query: null,
      onComplete: onComplete,
      onError: onError,
      cancelToken: cancelToken,
      logLabel: 'Edit message',
    );
  }

  Future<Map<String, dynamic>> forkChatSession({
    required int sessionId,
    int? upToMessageId,
  }) async {
    final query = <String, dynamic>{
      if (upToMessageId != null) 'up_to_message_id': upToMessageId.toString(),
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/fork',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelSubagent({
    required int sessionId,
    required String subagentId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/subagents/$subagentId/cancel',
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exportChatSession(int sessionId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/export',
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listKnowledgeDocuments({
    int? businessId,
  }) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/knowledge',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createKnowledgeDocument({
    required String title,
    required String content,
    int? businessId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/knowledge',
      data: {
        'title': title,
        'content': content,
        if (businessId != null) 'business_id': businessId,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<void> deleteKnowledgeDocument({
    required int documentId,
    int? businessId,
  }) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    await _api.delete('/api/v1/ai/chat/knowledge/$documentId', query: query);
  }

  Future<Map<String, dynamic>> uploadKnowledgeDocument({
    required String filename,
    required List<int> bytes,
    String? title,
    int? businessId,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      if (title != null && title.isNotEmpty) 'title': title,
    });
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/knowledge/upload',
      data: formData,
      query: query,
      options: Options(
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  // ---- AI Skills (Agent Skills / marketplace) ----

  Future<List<Map<String, dynamic>>> listInstalledSkills({
    required int businessId,
    bool enabledOnly = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/installed',
      query: {if (enabledOnly) 'enabled_only': 'true'},
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List? ?? [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> listSkillMarketplace({
    int skip = 0,
    int take = 20,
    String? search,
    String? sourceType,
    bool? isOfficial,
    int? businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/skills/marketplace/packages',
      query: {
        'skip': skip,
        'take': take,
        if (search != null && search.isNotEmpty) 'search': search,
        if (sourceType != null && sourceType.isNotEmpty) 'source_type': sourceType,
        if (isOfficial != null) 'is_official': isOfficial.toString(),
        if (businessId != null) 'business_id': businessId,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<List<Map<String, dynamic>>> listAnthropicSkillCatalog() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/ai/skills/catalog/anthropic');
    final data = res.data?['data'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List? ?? [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> installSkill({
    required int businessId,
    required int packageId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/install',
      data: {'package_id': packageId},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> installAnthropicSkill({
    required int businessId,
    required String anthropicSkillId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/install-anthropic',
      data: {'anthropic_skill_id': anthropicSkillId},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<void> setSkillsEnabled({
    required int businessId,
    List<int>? enableIds,
    List<int>? disableIds,
  }) async {
    await _api.put(
      '/api/v1/businesses/$businessId/ai/skills/enabled',
      data: {
        if (enableIds != null) 'enable_ids': enableIds,
        if (disableIds != null) 'disable_ids': disableIds,
      },
    );
  }

  Future<Map<String, dynamic>> importSkillZip({
    required int businessId,
    required String filename,
    required List<int> bytes,
    String? title,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      if (title != null && title.isNotEmpty) 'title': title,
    });
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/import',
      data: formData,
      options: Options(
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> createNativeSkill({
    required int businessId,
    required String skillSlug,
    required String title,
    required String description,
    required String skillBody,
    List<String>? allowedToolNames,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills',
      data: {
        'skill_slug': skillSlug,
        'title': title,
        'description': description,
        'skill_body': skillBody,
        if (allowedToolNames != null) 'allowed_tool_names': allowedToolNames,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> importSkillFromGit({
    required int businessId,
    required String gitUrl,
    String? title,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/import-git',
      data: {
        'git_url': gitUrl,
        if (title != null && title.isNotEmpty) 'title': title,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<List<Map<String, dynamic>>> listOwnedSkills({
    required int businessId,
    int skip = 0,
    int take = 50,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/owned',
      query: {'skip': skip, 'take': take},
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List? ?? [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> publishSkill({
    required int businessId,
    required int packageId,
    String? shortDescription,
    String? longDescription,
    List<String>? tags,
    String versionLabel = '1.0.0',
    String? changelog,
    double? priceAmount,
    int? currencyId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/$packageId/publish',
      data: {
        if (shortDescription != null) 'short_description': shortDescription,
        if (longDescription != null) 'long_description': longDescription,
        if (tags != null) 'tags': tags,
        'version_label': versionLabel,
        if (changelog != null) 'changelog': changelog,
        if (priceAmount != null) 'price_amount': priceAmount,
        if (currencyId != null) 'currency_id': currencyId,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> getPublisherRevenue({
    required int businessId,
    int skip = 0,
    int take = 20,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/ai/skills/publisher/revenue',
      query: {'skip': skip, 'take': take},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? {});
  }

  Future<List<Map<String, dynamic>>> listPendingSkillsAdmin() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/ai/skills/pending');
    final data = res.data?['data'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List? ?? [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> approveSkillAdmin(int packageId) async {
    await _api.post('/api/v1/admin/ai/skills/packages/$packageId/approve');
  }

  Future<void> rejectSkillAdmin(int packageId, {String? reason}) async {
    await _api.post(
      '/api/v1/admin/ai/skills/packages/$packageId/reject',
      data: {if (reason != null) 'reason': reason},
    );
  }

  Future<int> seedOfficialSkillsAdmin() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/ai/skills/seed-official');
    final data = res.data?['data'] as Map<String, dynamic>? ?? {};
    return data['created'] as int? ?? 0;
  }

  Stream<AIStreamChunk> _postSseStream(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
    String logLabel = 'SSE',
    AISseCursor? sseCursor,
  }) async* {
    try {
      if (kIsWeb) {
        final uri = _api.resolveUri(path, query: query);
        final headers = _api.streamingHeadersFor(uri);
        if (sseCursor?.lastEventId != null) {
          headers['Last-Event-ID'] = '${sseCursor!.lastEventId}';
        }
        await for (final eventPayload in postSsePayloads(
          uri: uri,
          headers: headers,
          body: jsonEncode(data ?? const <String, dynamic>{}),
          cancelToken: cancelToken,
          onEventId: (id) => sseCursor?.lastEventId = id,
        )) {
          final chunk = _parseSsePayload(
            eventPayload,
            onError,
            onComplete,
            cursor: sseCursor,
          );
          if (chunk != null) yield chunk;
        }
        return;
      }
      final response = await _api.post<ResponseBody>(
        path,
        data: data ?? {},
        query: query,
        responseType: ResponseType.stream,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(seconds: 60),
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            if (sseCursor?.lastEventId != null)
              'Last-Event-ID': '${sseCursor!.lastEventId}',
          },
        ),
        cancelToken: cancelToken,
      );

      final responseBody = response.data;
      if (responseBody == null) {
        onError?.call('Empty response');
        return;
      }

      final lineStream = responseBody.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final eventBuffer = <String>[];
      await for (final rawLine in lineStream) {
        final line = rawLine.trimRight();
        if (line.isEmpty) {
          if (eventBuffer.isEmpty) continue;
          final chunk = _parseSsePayload(
            eventBuffer.join('\n'),
            onError,
            onComplete,
            cursor: sseCursor,
          );
          eventBuffer.clear();
          if (chunk != null) yield chunk;
          continue;
        }
        if (line.startsWith('id:')) {
          final id = int.tryParse(line.substring(3).trim());
          if (id != null) sseCursor?.lastEventId = id;
          continue;
        }
        if (line.startsWith('data:')) {
          final value = line.length > 5 && line[5] == ' '
              ? line.substring(6)
              : line.substring(5);
          eventBuffer.add(value);
        }
      }
      if (eventBuffer.isNotEmpty) {
        final chunk = _parseSsePayload(
          eventBuffer.join('\n'),
          onError,
          onComplete,
          cursor: sseCursor,
        );
        if (chunk != null) yield chunk;
      }
    } catch (e, stack) {
      debugPrint('[AIService] $logLabel stream error: $e');
      debugPrintStack(stackTrace: stack);
      onError?.call(ErrorExtractor.userMessage(e));
      rethrow;
    }
  }

  Future<void> deleteChatSession(int sessionId) async {
    await _api.delete('/api/v1/ai/chat/sessions/$sessionId');
  }

  Future<AISessionTodoSnapshot> updateSessionTodo({
    required int sessionId,
    required String todoId,
    required String status,
  }) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions/$sessionId/todos/$todoId',
      data: {'status': status},
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is! Map) {
      return const AISessionTodoSnapshot(
        items: [],
        summary: AISessionTodoSummary(total: 0, completed: 0),
      );
    }
    return AISessionTodoSnapshot.fromJson(Map<String, dynamic>.from(data));
  }

  // ========== Voice: Feedback ==========
  Future<void> submitVoiceFeedback({
    required int interactionId,
    required int rating,
    String? feedbackText,
  }) async {
    await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/voice/interactions/$interactionId/feedback',
      data: {
        'rating': rating,
        if (feedbackText != null && feedbackText.trim().isNotEmpty)
          'feedback_text': feedbackText.trim(),
      },
    );
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
    String period = 'monthly',
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/subscription/subscribe',
      data: {
        'plan_id': planId,
        'period': period,
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
    String period = 'monthly',
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/subscription/upgrade',
      data: {
        'plan_id': newPlanId,
        'period': period,
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

  /// آمار استفاده (از لاگ). بدون from/to کل دوره را می‌دهد.
  Future<Map<String, dynamic>> getSubscriptionUsageStats({
    int? businessId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final query = <String, dynamic>{};
    if (businessId != null) {
      query['business_id'] = businessId.toString();
    }
    if (fromDate != null) {
      query['from_date'] = fromDate.toIso8601String();
    }
    if (toDate != null) {
      query['to_date'] = toDate.toIso8601String();
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/subscription/usage',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  // ========== User: Personal Prompts ==========
  Future<List<AIPrompt>> getMyPrompts() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/ai/prompts/my');
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data
        .map((e) => AIPrompt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AIPrompt> createMyPrompt(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/prompts/my',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIPrompt> updateMyPrompt(
    int promptId,
    Map<String, dynamic> data,
  ) async {
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
    debugPrint('[AIService] getUsageStats - Response body: $body');

    final data = body['data'];
    debugPrint(
      '[AIService] getUsageStats - data field: $data (type: ${data.runtimeType})',
    );

    if (data == null || data is! Map<String, dynamic>) {
      debugPrint('[AIService] getUsageStats - Invalid data format!');
      throw Exception(
        'Invalid response format: data field is missing or invalid. Got: ${data.runtimeType}',
      );
    }

    debugPrint('[AIService] getUsageStats - Parsing AIUsageStats from: $data');
    try {
      final stats = AIUsageStats.fromJson(data);
      debugPrint(
        '[AIService] getUsageStats - Successfully parsed AIUsageStats',
      );
      return stats;
    } catch (e, stackTrace) {
      debugPrint('[AIService] getUsageStats - Error parsing AIUsageStats: $e');
      debugPrint('[AIService] getUsageStats - StackTrace: $stackTrace');
      rethrow;
    }
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
    final data = body['data'];
    if (data == null || data is! List) {
      return [];
    }
    return data.map((e) {
      if (e is Map<String, dynamic>) {
        return AIUsageLog.fromJson(e);
      }
      throw Exception('Invalid log entry format: $e');
    }).toList();
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
  Stream<AIStreamChunk> streamCrmSummarizeLead({
    required int businessId,
    required int leadId,
    CancelToken? cancelToken,
  }) {
    return _postSseStream(
      '/api/v1/ai/crm/businesses/$businessId/summarize-lead',
      query: {'stream': 'true'},
      data: {'lead_id': leadId},
      cancelToken: cancelToken,
      logLabel: 'CRM-lead',
    );
  }

  Stream<AIStreamChunk> streamCrmSummarizeDeal({
    required int businessId,
    required int dealId,
    CancelToken? cancelToken,
  }) {
    return _postSseStream(
      '/api/v1/ai/crm/businesses/$businessId/summarize-deal',
      query: {'stream': 'true'},
      data: {'deal_id': dealId},
      cancelToken: cancelToken,
      logLabel: 'CRM-deal',
    );
  }

  Stream<AIStreamChunk> streamTicketSuggestReply({
    required int ticketId,
    String? context,
    CancelToken? cancelToken,
  }) {
    return _postSseStream(
      '/api/v1/support/tickets/$ticketId/ai-suggest-reply',
      query: {'stream': 'true'},
      data: {if (context != null) 'context': context},
      cancelToken: cancelToken,
      logLabel: 'ticket-suggest',
    );
  }

  Future<Map<String, dynamic>> suggestTicketReply({
    required int ticketId,
    String? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/support/tickets/$ticketId/ai-suggest-reply',
      data: {if (context != null) 'context': context},
      options: Options(
        receiveTimeout: _kLongAiHttpTimeout,
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> autoReplyTicket({
    required int ticketId,
    String? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/support/tickets/$ticketId/ai-auto-reply',
      data: {if (context != null) 'context': context},
      options: Options(
        receiveTimeout: _kLongAiHttpTimeout,
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    return res.data as Map<String, dynamic>;
  }
}
