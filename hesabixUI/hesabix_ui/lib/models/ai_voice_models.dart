class AIVoiceModelItem {
  final int? id;
  final String code;
  final String kind;
  final String displayName;
  final String? description;
  final String provider;
  final String modelId;
  final String language;
  final String? voiceId;
  final String? tier;
  final bool isDefault;
  final bool isActive;
  final bool isCloud;
  final bool dummy;
  final int sortOrder;

  const AIVoiceModelItem({
    this.id,
    required this.code,
    required this.kind,
    required this.displayName,
    this.description,
    required this.provider,
    required this.modelId,
    this.language = 'fa',
    this.voiceId,
    this.tier,
    this.isDefault = false,
    this.isActive = true,
    this.isCloud = false,
    this.dummy = false,
    this.sortOrder = 0,
  });

  factory AIVoiceModelItem.fromJson(Map<String, dynamic> json) {
    return AIVoiceModelItem(
      id: json['id'] as int?,
      code: json['code'] as String? ?? '',
      kind: json['kind'] as String? ?? 'stt',
      displayName: json['display_name'] as String? ?? json['code'] as String? ?? '',
      description: json['description'] as String?,
      provider: json['provider'] as String? ?? 'local',
      modelId: json['model_id'] as String? ?? '',
      language: json['language'] as String? ?? 'fa',
      voiceId: json['voice_id'] as String?,
      tier: json['tier'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isCloud: json['is_cloud'] as bool? ?? false,
      dummy: json['dummy'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class AIVoiceCatalog {
  final List<AIVoiceModelItem> stt;
  final List<AIVoiceModelItem> tts;
  final String? defaultSttCode;
  final String? defaultTtsCode;
  final bool allowCloudAudio;
  final bool policyAllowCloudAudio;

  const AIVoiceCatalog({
    this.stt = const [],
    this.tts = const [],
    this.defaultSttCode,
    this.defaultTtsCode,
    this.allowCloudAudio = false,
    this.policyAllowCloudAudio = false,
  });

  factory AIVoiceCatalog.fromJson(Map<String, dynamic> json) {
    List<AIVoiceModelItem> parse(String key) {
      final raw = json[key] as List? ?? const [];
      return raw
          .whereType<Map>()
          .map((e) => AIVoiceModelItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return AIVoiceCatalog(
      stt: parse('stt'),
      tts: parse('tts'),
      defaultSttCode: json['default_stt_code'] as String?,
      defaultTtsCode: json['default_tts_code'] as String?,
      allowCloudAudio: json['allow_cloud_audio'] as bool? ?? false,
      policyAllowCloudAudio: json['policy_allow_cloud_audio'] as bool? ?? false,
    );
  }

  bool get isEmpty => stt.isEmpty && tts.isEmpty;
}
