class EmailConfig {
  final int id;
  final String name;
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final bool useTls;
  final bool useSsl;
  final String fromEmail;
  final String fromName;
  final bool isActive;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmailConfig({
    required this.id,
    required this.name,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUsername,
    required this.useTls,
    required this.useSsl,
    required this.fromEmail,
    required this.fromName,
    required this.isActive,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmailConfig.fromJson(Map<String, dynamic> json) {
    return EmailConfig(
      id: json['id'] as int,
      name: json['name'] as String,
      smtpHost: json['smtp_host'] as String,
      smtpPort: json['smtp_port'] as int,
      smtpUsername: json['smtp_username'] as String,
      useTls: json['use_tls'] as bool,
      useSsl: json['use_ssl'] as bool,
      fromEmail: json['from_email'] as String,
      fromName: json['from_name'] as String,
      isActive: json['is_active'] as bool,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime _parseDateTime(dynamic dateValue) {
    if (dateValue == null) {
      return DateTime.now();
    }
    
    if (dateValue is String) {
      return DateTime.parse(dateValue);
    }
    
    if (dateValue is Map<String, dynamic>) {
      // Handle formatted date object
      final formatted = dateValue['formatted'] as String?;
      if (formatted != null) {
        return DateTime.parse(formatted);
      }
    }
    
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'smtp_host': smtpHost,
      'smtp_port': smtpPort,
      'smtp_username': smtpUsername,
      'use_tls': useTls,
      'use_ssl': useSsl,
      'from_email': fromEmail,
      'from_name': fromName,
      'is_active': isActive,
      'is_default': isDefault,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  EmailConfig copyWith({
    int? id,
    String? name,
    String? smtpHost,
    int? smtpPort,
    String? smtpUsername,
    bool? useTls,
    bool? useSsl,
    String? fromEmail,
    String? fromName,
    bool? isActive,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmailConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpUsername: smtpUsername ?? this.smtpUsername,
      useTls: useTls ?? this.useTls,
      useSsl: useSsl ?? this.useSsl,
      fromEmail: fromEmail ?? this.fromEmail,
      fromName: fromName ?? this.fromName,
      isActive: isActive ?? this.isActive,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CreateEmailConfigRequest {
  final String name;
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final String smtpPassword;
  final bool useTls;
  final bool useSsl;
  final String fromEmail;
  final String fromName;
  final bool isActive;

  CreateEmailConfigRequest({
    required this.name,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUsername,
    required this.smtpPassword,
    required this.useTls,
    required this.useSsl,
    required this.fromEmail,
    required this.fromName,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'smtp_host': smtpHost,
      'smtp_port': smtpPort,
      'smtp_username': smtpUsername,
      'smtp_password': smtpPassword,
      'use_tls': useTls,
      'use_ssl': useSsl,
      'from_email': fromEmail,
      'from_name': fromName,
      'is_active': isActive,
    };
  }
}

class UpdateEmailConfigRequest {
  final String? name;
  final String? smtpHost;
  final int? smtpPort;
  final String? smtpUsername;
  final String? smtpPassword;
  final bool? useTls;
  final bool? useSsl;
  final String? fromEmail;
  final String? fromName;
  final bool? isActive;

  UpdateEmailConfigRequest({
    this.name,
    this.smtpHost,
    this.smtpPort,
    this.smtpUsername,
    this.smtpPassword,
    this.useTls,
    this.useSsl,
    this.fromEmail,
    this.fromName,
    this.isActive,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    if (name != null) json['name'] = name;
    if (smtpHost != null) json['smtp_host'] = smtpHost;
    if (smtpPort != null) json['smtp_port'] = smtpPort;
    if (smtpUsername != null) json['smtp_username'] = smtpUsername;
    if (smtpPassword != null) json['smtp_password'] = smtpPassword;
    if (useTls != null) json['use_tls'] = useTls;
    if (useSsl != null) json['use_ssl'] = useSsl;
    if (fromEmail != null) json['from_email'] = fromEmail;
    if (fromName != null) json['from_name'] = fromName;
    if (isActive != null) json['is_active'] = isActive;
    return json;
  }
}

class SendEmailRequest {
  final String to;
  final String subject;
  final String body;
  final String? htmlBody;
  final int? configId;

  SendEmailRequest({
    required this.to,
    required this.subject,
    required this.body,
    this.htmlBody,
    this.configId,
  });

  Map<String, dynamic> toJson() {
    return {
      'to': to,
      'subject': subject,
      'body': body,
      if (htmlBody != null) 'html_body': htmlBody,
      if (configId != null) 'config_id': configId,
    };
  }
}

class EmailConfigListResponse {
  final bool success;
  final List<EmailConfig> data;
  final String message;

  EmailConfigListResponse({
    required this.success,
    required this.data,
    required this.message,
  });

  factory EmailConfigListResponse.fromJson(Map<String, dynamic> json) {
    return EmailConfigListResponse(
      success: json['success'] as bool? ?? true,
      data: (json['data'] as List? ?? [])
          .map((item) => EmailConfig.fromJson(item as Map<String, dynamic>))
          .toList(),
      message: json['message'] as String? ?? '',
    );
  }
}

class EmailConfigResponse {
  final bool success;
  final EmailConfig data;
  final String message;

  EmailConfigResponse({
    required this.success,
    required this.data,
    required this.message,
  });

  factory EmailConfigResponse.fromJson(Map<String, dynamic> json) {
    return EmailConfigResponse(
      success: json['success'] as bool? ?? true,
      data: EmailConfig.fromJson(json['data'] as Map<String, dynamic>),
      message: json['message'] as String? ?? '',
    );
  }
}

class SendEmailResponse {
  final bool success;
  final String message;

  SendEmailResponse({
    required this.success,
    required this.message,
  });

  factory SendEmailResponse.fromJson(Map<String, dynamic> json) {
    return SendEmailResponse(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String? ?? '',
    );
  }
}

class TestConnectionResponse {
  final bool success;
  final String message;
  final bool connected;

  TestConnectionResponse({
    required this.success,
    required this.message,
    required this.connected,
  });

  factory TestConnectionResponse.fromJson(Map<String, dynamic> json) {
    return TestConnectionResponse(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String? ?? '',
      connected: json['connected'] as bool? ?? false,
    );
  }
}
