import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../utils/error_extractor.dart';
import '../models/ai_models.dart';
import '../models/ai_stream_event.dart';
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

  // ========== User: AI Models ==========
  Future<List<AIModelCatalogItem>> listAvailableAIModels({int? businessId}) async {
    final query = <String, dynamic>{};
    if (businessId != null) query['business_id'] = businessId;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/models',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final models = data['models'] as List? ?? [];
    return models
        .map((e) => AIModelCatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String?> getPreferredModelCode({int? businessId}) async {
    final query = <String, dynamic>{};
    if (businessId != null) query['business_id'] = businessId;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/models',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    return data['preferred_model_code'] as String? ??
        data['plan_default_model'] as String?;
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
    return data
        .map((e) => AIPrompt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AIPrompt> createDefaultPrompt(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/ai/prompts/default',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return AIPrompt.fromJson(body['data'] as Map<String, dynamic>);
  }

  Future<AIPrompt> updateDefaultPrompt(
    int promptId,
    Map<String, dynamic> data,
  ) async {
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
    Map<String, dynamic>? structured,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory',
      data: {
        'content': content,
        if (businessId != null) 'business_id': businessId,
        if (structured != null && structured.isNotEmpty)
          'structured': structured,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getAIMemoryDigest({int? businessId}) async {
    final query = <String, dynamic>{
      if (businessId != null) 'business_id': businessId.toString(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/chat/memory/digest',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>;
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

  Future<AIChatSession> createChatSession({int? businessId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/chat/sessions',
      data: {if (businessId != null) 'business_id': businessId},
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
    String? explorationMode,
    String? model,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
  }) async* {
    try {
      final query = <String, dynamic>{'stream': true};
      if (explorationMode != null && explorationMode.isNotEmpty) {
        query['mode'] = explorationMode;
      }
      final payload = <String, dynamic>{
        'content': content,
        'approve_writes': approveWrites,
        if (explorationMode != null && explorationMode.isNotEmpty)
          'mode': explorationMode,
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
        )) {
          final chunk = _parseSsePayload(eventPayload, onError, onComplete);
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
          );
          eventBuffer.clear();
          if (chunk != null) yield chunk;
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
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
  ) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final eventType = data['type'] as String?;

    if (data.containsKey('error') &&
        ((data['done'] as bool? ?? false) || eventType == 'error')) {
      final errorMessage = data['error'] as String? ?? 'خطای نامشخص';
      onError?.call(errorMessage);
      return AIStreamChunk(
        error: errorMessage,
        done: data['done'] as bool? ?? true,
        recoverable: data['recoverable'] as bool? ?? false,
        suggestedAction: data['suggested_action'] as String?,
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
    if (eventType == 'trace_step' || eventType == 'trace_step_update') {
      final step = AIAgentTraceStep.fromJson(data);
      return AIStreamChunk(traceStep: step);
    }
    if (eventType == 'context_usage') {
      return AIStreamChunk(contextUsage: AIStreamContextUsage.fromJson(data));
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
      return AIStreamChunk(
        done: true,
        messageId: data['message_id'] as int?,
        functionCalls: data['function_calls'],
        functionResults: data['function_results'],
        agentTrace: agentTrace,
        requestedModel: data['requested_model'] as String?,
        resolvedModel: data['resolved_model'] as String?,
      );
    }

    if (content.isNotEmpty) {
      return AIStreamChunk(contentDelta: content);
    }
    return null;
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

  Stream<AIStreamChunk> _postSseStream(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    void Function(Map<String, dynamic>? usage, int? messageId)? onComplete,
    void Function(String error)? onError,
    CancelToken? cancelToken,
    String logLabel = 'SSE',
  }) async* {
    try {
      if (kIsWeb) {
        final uri = _api.resolveUri(path, query: query);
        final headers = _api.streamingHeadersFor(uri);
        await for (final eventPayload in postSsePayloads(
          uri: uri,
          headers: headers,
          body: jsonEncode(data ?? const <String, dynamic>{}),
          cancelToken: cancelToken,
        )) {
          final chunk = _parseSsePayload(eventPayload, onError, onComplete);
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
          );
          eventBuffer.clear();
          if (chunk != null) yield chunk;
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
