import 'package:flutter/foundation.dart';

/// مدل‌های مربوط به سیستم AI

class AIConfig {
  final int? id;
  final String provider; // 'openai', 'anthropic', 'local'
  final String modelName;
  final String? apiBaseUrl;
  final bool isActive;
  /// اگر false: tools به provider نمی‌رود (gateway بدون tool calling)
  final bool functionCallingEnabled;
  final int maxTokens;
  final double temperature;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AIConfig({
    this.id,
    required this.provider,
    required this.modelName,
    this.apiBaseUrl,
    this.isActive = false,
    this.functionCallingEnabled = true,
    this.maxTokens = 2000,
    this.temperature = 0.7,
    this.createdAt,
    this.updatedAt,
  });

  factory AIConfig.fromJson(Map<String, dynamic> json) {
    return AIConfig(
      id: json['id'] as int?,
      provider: json['provider'] as String,
      modelName: json['model_name'] as String,
      apiBaseUrl: json['api_base_url'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      functionCallingEnabled: json['function_calling_enabled'] as bool? ?? true,
      maxTokens: json['max_tokens'] as int? ?? 2000,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'provider': provider,
      'model_name': modelName,
      if (apiBaseUrl != null) 'api_base_url': apiBaseUrl,
      'is_active': isActive,
      'function_calling_enabled': functionCallingEnabled,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };
  }
}

enum AIPlanType {
  free,
  subscription,
  payAsGo,
  hybrid;

  String get value {
    switch (this) {
      case AIPlanType.free:
        return 'free';
      case AIPlanType.subscription:
        return 'subscription';
      case AIPlanType.payAsGo:
        return 'pay_as_go';
      case AIPlanType.hybrid:
        return 'hybrid';
    }
  }

  static AIPlanType fromString(String value) {
    switch (value) {
      case 'free':
        return AIPlanType.free;
      case 'subscription':
        return AIPlanType.subscription;
      case 'pay_as_go':
        return AIPlanType.payAsGo;
      case 'hybrid':
        return AIPlanType.hybrid;
      default:
        return AIPlanType.free;
    }
  }
}

class AIPlan {
  final int? id;
  final String code;
  final String name;
  final String? description;
  final AIPlanType planType;
  final Map<String, dynamic> pricingConfig;
  final int? tokensLimit;
  final int? monthlyTokensLimit;
  final bool isActive;
  final bool autoRenew;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AIPlan({
    this.id,
    required this.code,
    required this.name,
    this.description,
    required this.planType,
    required this.pricingConfig,
    this.tokensLimit,
    this.monthlyTokensLimit,
    this.isActive = true,
    this.autoRenew = false,
    this.createdAt,
    this.updatedAt,
  });

  factory AIPlan.fromJson(Map<String, dynamic> json) {
    return AIPlan(
      id: json['id'] as int?,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      planType: AIPlanType.fromString(json['plan_type'] as String),
      pricingConfig: Map<String, dynamic>.from(
        json['pricing_config'] as Map? ?? {},
      ),
      tokensLimit: json['tokens_limit'] as int?,
      monthlyTokensLimit: json['monthly_tokens_limit'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      autoRenew: json['auto_renew'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      if (description != null) 'description': description,
      'plan_type': planType.value,
      'pricing_config': pricingConfig,
      if (tokensLimit != null) 'tokens_limit': tokensLimit,
      if (monthlyTokensLimit != null) 'monthly_tokens_limit': monthlyTokensLimit,
      'is_active': isActive,
      'auto_renew': autoRenew,
    };
  }
}

class UserAISubscription {
  final int? id;
  final int userId;
  final int? businessId;
  final int planId;
  final AIPlan? plan;
  final String? preferredModelCode;
  final int tokensUsed;
  final int? tokensLimit;
  final bool isActive;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? expiresAt;
  final DateTime? lastResetAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserAISubscription({
    this.id,
    required this.userId,
    this.businessId,
    required     this.planId,
    this.plan,
    this.preferredModelCode,
    this.tokensUsed = 0,
    this.tokensLimit,
    this.isActive = true,
    this.periodStart,
    this.periodEnd,
    this.expiresAt,
    this.lastResetAt,
    this.createdAt,
    this.updatedAt,
  });

  factory UserAISubscription.fromJson(Map<String, dynamic> json) {
    return UserAISubscription(
      id: json['id'] as int?,
      userId: json['user_id'] as int,
      businessId: json['business_id'] as int?,
      planId: json['plan_id'] as int,
      plan: json['plan'] != null
          ? AIPlan.fromJson(json['plan'] as Map<String, dynamic>)
          : null,
      preferredModelCode: json['preferred_model_code'] as String?,
      tokensUsed: json['tokens_used'] as int? ?? 0,
      tokensLimit: json['tokens_limit'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      periodStart: json['period_start'] != null
          ? DateTime.parse(json['period_start'] as String)
          : null,
      periodEnd: json['period_end'] != null
          ? DateTime.parse(json['period_end'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      lastResetAt: json['last_reset_at'] != null
          ? DateTime.parse(json['last_reset_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// true وقتی سقف معین داریم (مثلاً اشتراک ماهانه با monthly_tokens).
  bool get hasTokenCap => tokensLimit != null && tokensLimit! > 0;

  /// null یعنی بدون سقف معین (مثلاً pay-as-go یا مقدار نامحدود).
  int? get remainingTokens {
    if (!hasTokenCap) return null;
    return (tokensLimit! - tokensUsed).clamp(0, tokensLimit!);
  }
}

class AIChatSession {
  final int? id;
  final int userId;
  final int? businessId;
  final String title;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AIChatSession({
    this.id,
    required this.userId,
    this.businessId,
    required this.title,
    this.createdAt,
    this.updatedAt,
  });

  factory AIChatSession.fromJson(Map<String, dynamic> json) {
    return AIChatSession(
      id: json['id'] as int?,
      userId: json['user_id'] as int,
      businessId: json['business_id'] as int?,
      title: json['title'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      if (businessId != null) 'business_id': businessId,
      'title': title,
    };
  }
}

enum MessageRole {
  user,
  assistant,
  system;

  String get value {
    switch (this) {
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
      case MessageRole.system:
        return 'system';
    }
  }

  static MessageRole fromString(String value) {
    switch (value) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      default:
        return MessageRole.user;
    }
  }
}

class AIChatMessage {
  final int? id;
  final int sessionId;
  final MessageRole role;
  final String content;
  final Object? functionCalls;
  final Object? functionResults;
  final int tokensUsed;
  final DateTime? createdAt;

  AIChatMessage({
    this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.functionCalls,
    this.functionResults,
    this.tokensUsed = 0,
    this.createdAt,
  });

  factory AIChatMessage.fromJson(Map<String, dynamic> json) {
    return AIChatMessage(
      id: json['id'] as int?,
      sessionId: json['session_id'] as int,
      role: MessageRole.fromString(json['role'] as String),
      content: json['content'] as String,
      functionCalls: json['function_calls'],
      functionResults: json['function_results'],
      tokensUsed: json['tokens_used'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'role': role.value,
      'content': content,
      if (functionCalls != null) 'function_calls': functionCalls,
      if (functionResults != null) 'function_results': functionResults,
      'tokens_used': tokensUsed,
    };
  }
}

class AIUsageStats {
  final Map<String, dynamic> period;
  final Map<String, dynamic> total;
  final List<Map<String, dynamic>> daily;
  final List<Map<String, dynamic>> byModel;

  AIUsageStats({
    required this.period,
    required this.total,
    required this.daily,
    required this.byModel,
  });

  factory AIUsageStats.fromJson(Map<String, dynamic> json) {
    // ignore: avoid_print
    if (kDebugMode) {
      print('[AIUsageStats] fromJson - Input JSON: $json');
    }
    
    try {
      final period = json['period'] != null 
          ? Map<String, dynamic>.from(json['period'] as Map)
          : <String, dynamic>{};
      
      if (kDebugMode) {
        print('[AIUsageStats] fromJson - period: $period');
      }
      
      final total = json['total'] != null
          ? Map<String, dynamic>.from(json['total'] as Map)
          : <String, dynamic>{
              'total_tokens': 0,
              'input_tokens': 0,
              'output_tokens': 0,
              'total_cost': 0.0,
              'total_requests': 0,
            };
      
      if (kDebugMode) {
        print('[AIUsageStats] fromJson - total: $total');
      }
      
      final dailyRaw = json['daily'];
      final daily = dailyRaw != null && dailyRaw is List
          ? dailyRaw
              .map((e) {
                try {
                  return e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{};
                } catch (err) {
                  if (kDebugMode) {
                    print('[AIUsageStats] fromJson - Error parsing daily entry: $e, error: $err');
                  }
                  return <String, dynamic>{};
                }
              })
              .toList()
          : <Map<String, dynamic>>[];
      
      if (kDebugMode) {
        print('[AIUsageStats] fromJson - daily: $daily (length: ${daily.length})');
      }
      
      final byModelRaw = json['by_model'];
      final byModel = byModelRaw != null && byModelRaw is List
          ? byModelRaw
              .map((e) {
                try {
                  return e is Map<String, dynamic> ? Map<String, dynamic>.from(e) : <String, dynamic>{};
                } catch (err) {
                  if (kDebugMode) {
                    print('[AIUsageStats] fromJson - Error parsing byModel entry: $e, error: $err');
                  }
                  return <String, dynamic>{};
                }
              })
              .toList()
          : <Map<String, dynamic>>[];
      
      if (kDebugMode) {
        print('[AIUsageStats] fromJson - byModel: $byModel (length: ${byModel.length})');
      }
      
      final result = AIUsageStats(
        period: period,
        total: total,
        daily: daily,
        byModel: byModel,
      );
      
      if (kDebugMode) {
        print('[AIUsageStats] fromJson - Successfully created AIUsageStats');
      }
      
      return result;
    } catch (e, stackTrace) {
      // ignore: avoid_print
      if (kDebugMode) {
        print('[AIUsageStats] fromJson - Error: $e');
        print('[AIUsageStats] fromJson - StackTrace: $stackTrace');
      }
      rethrow;
    }
  }
}

class AIUsageLog {
  final int? id;
  final String provider;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final double cost;
  final String paymentMethod;
  final DateTime? createdAt;

  AIUsageLog({
    this.id,
    required this.provider,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.cost,
    required this.paymentMethod,
    this.createdAt,
  });

  factory AIUsageLog.fromJson(Map<String, dynamic> json) {
    return AIUsageLog(
      id: json['id'] as int?,
      provider: json['provider'] as String,
      model: json['model'] as String,
      inputTokens: json['input_tokens'] as int,
      outputTokens: json['output_tokens'] as int,
      cost: (json['cost'] as num).toDouble(),
      paymentMethod: json['payment_method'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  int get totalTokens => inputTokens + outputTokens;
}

/// کاتالوگ مدل AI قابل انتخاب توسط کاربر
class AIModelCatalogItem {
  final int? id;
  final String code;
  final String displayName;
  final String? description;
  final String provider;
  final String modelId;
  final String? tier;
  final bool supportsTools;
  final int maxTokensDefault;
  final bool isActive;
  final bool isDefault;
  final Map<String, dynamic>? pricing;
  final double? estimatedCostPer1kTokens;
  final String? pricingHint;
  final bool isAuto;

  AIModelCatalogItem({
    this.id,
    required this.code,
    required this.displayName,
    this.description,
    required this.provider,
    required this.modelId,
    this.tier,
    this.supportsTools = true,
    this.maxTokensDefault = 4000,
    this.isActive = true,
    this.isDefault = false,
    this.pricing,
    this.estimatedCostPer1kTokens,
    this.pricingHint,
    this.isAuto = false,
  });

  factory AIModelCatalogItem.fromJson(Map<String, dynamic> json) {
    return AIModelCatalogItem(
      id: json['id'] as int?,
      code: json['code'] as String,
      displayName: json['display_name'] as String? ?? json['code'] as String,
      description: json['description'] as String?,
      provider: json['provider'] as String? ?? 'openai',
      modelId: json['model_id'] as String? ?? json['code'] as String,
      tier: json['tier'] as String?,
      supportsTools: json['supports_tools'] as bool? ?? true,
      maxTokensDefault: json['max_tokens_default'] as int? ?? 4000,
      isActive: json['is_active'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
      pricing: json['pricing'] is Map
          ? Map<String, dynamic>.from(json['pricing'] as Map)
          : null,
      estimatedCostPer1kTokens:
          (json['estimated_cost_per_1k_tokens'] as num?)?.toDouble(),
      pricingHint: json['pricing_hint'] as String?,
      isAuto: json['is_auto'] as bool? ?? json['code'] == 'auto',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'display_name': displayName,
      if (description != null) 'description': description,
      'provider': provider,
      'model_id': modelId,
      if (tier != null) 'tier': tier,
      'supports_tools': supportsTools,
      'max_tokens_default': maxTokensDefault,
      'is_active': isActive,
      'sort_order': 0,
    };
  }
}

class AIPrompt {
  final int? id;
  final String? promptKey;
  final String role; // 'admin', 'operator', 'user'
  final String? promptType; // 'system', 'user'
  final String? category;
  final String? title;
  final String content;
  final int? userId;
  final bool isDefault;
  final String? source; // 'database' | 'fallback'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AIPrompt({
    this.id,
    this.promptKey,
    required this.role,
    this.promptType,
    this.category,
    this.title,
    required this.content,
    this.userId,
    this.isDefault = false,
    this.source,
    this.createdAt,
    this.updatedAt,
  });

  factory AIPrompt.fromJson(Map<String, dynamic> json) {
    return AIPrompt(
      id: json['id'] as int?,
      promptKey: json['prompt_key'] as String?,
      role: json['role'] as String,
      promptType: json['prompt_type'] as String?,
      category: json['category'] as String?,
      title: json['title'] as String?,
      content: json['content'] as String,
      userId: json['user_id'] as int?,
      isDefault: json['is_default'] as bool? ?? false,
      source: json['source'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (promptKey != null) 'prompt_key': promptKey,
      'role': role,
      if (promptType != null) 'prompt_type': promptType,
      if (category != null) 'category': category,
      if (title != null) 'title': title,
      'content': content,
      if (userId != null) 'user_id': userId,
      'is_default': isDefault,
      if (source != null) 'source': source,
    };
  }
}

