class NotificationTemplate {
  final int id;
  final String eventKey;
  final String channel;
  final String? locale;
  final String? subject;
  final String body;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotificationTemplate({
    required this.id,
    required this.eventKey,
    required this.channel,
    this.locale,
    this.subject,
    required this.body,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NotificationTemplate.fromJson(Map<String, dynamic> json) {
    return NotificationTemplate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      eventKey: json['event_key']?.toString() ?? '',
      channel: json['channel']?.toString() ?? '',
      locale: json['locale']?.toString(),
      subject: json['subject']?.toString(),
      body: json['body']?.toString() ?? '',
      isActive: json['is_active'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_key': eventKey,
      'channel': channel,
      'locale': locale,
      'subject': subject,
      'body': body,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}



