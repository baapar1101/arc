/// مدل‌های مربوط به سیستم AI

class AIConfig {
  final int? id;
  final String provider; // 'openai', 'anthropic', 'local'
  final String modelName;
  final String? apiBaseUrl;
  final bool isActive;
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
    required this.planId,
    this.plan,
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

  int get remainingTokens {
    if (tokensLimit == null) return 0;
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
  final Map<String, dynamic>? functionCalls;
  final Map<String, dynamic>? functionResults;
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
      functionCalls: json['function_calls'] != null
          ? Map<String, dynamic>.from(json['function_calls'] as Map)
          : null,
      functionResults: json['function_results'] != null
          ? Map<String, dynamic>.from(json['function_results'] as Map)
          : null,
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
    return AIUsageStats(
      period: Map<String, dynamic>.from(json['period'] as Map),
      total: Map<String, dynamic>.from(json['total'] as Map),
      daily: (json['daily'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      byModel: (json['by_model'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
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

class AIPrompt {
  final int? id;
  final String role; // 'admin', 'operator', 'user'
  final String? promptType; // 'system', 'user'
  final String content;
  final int? userId;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AIPrompt({
    this.id,
    required this.role,
    this.promptType,
    required this.content,
    this.userId,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  factory AIPrompt.fromJson(Map<String, dynamic> json) {
    return AIPrompt(
      id: json['id'] as int?,
      role: json['role'] as String,
      promptType: json['prompt_type'] as String?,
      content: json['content'] as String,
      userId: json['user_id'] as int?,
      isDefault: json['is_default'] as bool? ?? false,
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
      'role': role,
      if (promptType != null) 'prompt_type': promptType,
      'content': content,
      if (userId != null) 'user_id': userId,
      'is_default': isDefault,
    };
  }
}

