import 'dart:convert';

/// Encodes/decodes OS notification tap payloads for [AnnouncementNavigation].
class NotificationPayloadCodec {
  NotificationPayloadCodec._();

  static String encode(Map<String, dynamic> item) {
    return jsonEncode(<String, dynamic>{
      if (item['id'] != null) 'id': item['id'],
      if (item['announcement_id'] != null) 'id': item['announcement_id'],
      if (item['title'] != null) 'title': item['title'],
      if (item['body'] != null) 'body': item['body'],
      if (item['level'] != null) 'level': item['level'],
      if (item['deep_link'] != null && '${item['deep_link']}'.isNotEmpty)
        'deep_link': '${item['deep_link']}',
      if (item['ticket_id'] != null) 'ticket_id': item['ticket_id'],
      if (item['event_key'] != null && '${item['event_key']}'.isNotEmpty)
        'event_key': '${item['event_key']}',
      'is_read': item['is_read'] == true,
    });
  }

  static Map<String, dynamic>? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Normalize string-map payloads (e.g. OS notification tap extras) to WS item shape.
  static Map<String, dynamic> fromStringMap(Map<String, dynamic> data) {
    final id = data['announcement_id'] ?? data['id'];
    return <String, dynamic>{
      if (id != null) 'id': id,
      if (data['title'] != null) 'title': data['title'],
      if (data['body'] != null) 'body': data['body'],
      if (data['level'] != null) 'level': data['level'],
      if (data['deep_link'] != null && '${data['deep_link']}'.isNotEmpty)
        'deep_link': '${data['deep_link']}',
      if (data['ticket_id'] != null) 'ticket_id': data['ticket_id'],
      if (data['event_key'] != null && '${data['event_key']}'.isNotEmpty)
        'event_key': '${data['event_key']}',
      'is_read': false,
    };
  }
}
