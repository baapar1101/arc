
DateTime _safeParse(dynamic value) {
  if (value == null) return DateTime.now();
  try {
    final text = value.toString().trim();
    // Try ISO first
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
      return DateTime.parse(text);
    }
    // Try Persian/Gregorian slash pattern: YYYY/MM/DD
    final match = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})').firstMatch(text);
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      if (year >= 1700 && year <= 2200 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }
  } catch (_) {}
  return DateTime.now();
}

class ResponseTemplate {
  final String name;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ResponseTemplate({
    required this.name,
    required this.content,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ResponseTemplate.fromJson(Map<String, dynamic> json) {
    return ResponseTemplate(
      name: json['name'] as String,
      content: json['content'] as String,
      createdAt: json['created_at'] != null
          ? _safeParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? _safeParse(json['updated_at'] as String)
          : null,
    );
  }

  ResponseTemplate copyWith({
    String? name,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ResponseTemplate(
      name: name ?? this.name,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Replace variables in template with actual values
  String format(Map<String, String> variables) {
    String result = content;
    variables.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
}




