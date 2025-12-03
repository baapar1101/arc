class NotificationHistoryItem {
  final int id;
  final String channel;
  final String eventKey;
  final String eventTitle;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> payload;
  final String? errorMessage;
  final int retryCount;

  NotificationHistoryItem({
    required this.id,
    required this.channel,
    required this.eventKey,
    required this.eventTitle,
    required this.status,
    this.createdAt,
    this.updatedAt,
    required this.payload,
    this.errorMessage,
    required this.retryCount,
  });

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) {
    return NotificationHistoryItem(
      id: json['id'] as int,
      channel: json['channel'] as String,
      eventKey: json['event_key'] as String,
      eventTitle: json['event_title'] as String? ?? json['event_key'] as String,
      status: json['status'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      errorMessage: json['error_message'] as String?,
      retryCount: json['retry_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'channel': channel,
      'event_key': eventKey,
      'event_title': eventTitle,
      'status': status,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'payload': payload,
      'error_message': errorMessage,
      'retry_count': retryCount,
    };
  }
}

