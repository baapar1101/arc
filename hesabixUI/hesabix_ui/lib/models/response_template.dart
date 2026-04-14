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
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
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




