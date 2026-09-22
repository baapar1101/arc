
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

class DocumentNumberingSetting {
  final int? id;
  final int businessId;
  final String documentType;
  final String? prefix;
  final bool includeDate;
  final String calendarType; // gregorian یا jalali
  final String? dateFormat;
  final String separator;
  final int startNumber;
  final int numberPadding;
  final String? resetPeriod; // daily, monthly, yearly, never
  final String? customFormat;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  DocumentNumberingSetting({
    this.id,
    required this.businessId,
    required this.documentType,
    this.prefix,
    this.includeDate = true,
    this.calendarType = 'gregorian',
    this.dateFormat,
    this.separator = '-',
    this.startNumber = 1,
    this.numberPadding = 4,
    this.resetPeriod,
    this.customFormat,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DocumentNumberingSetting.fromJson(Map<String, dynamic> json) {
    return DocumentNumberingSetting(
      id: json['id'],
      businessId: json['business_id'],
      documentType: json['document_type'],
      prefix: json['prefix'],
      includeDate: json['include_date'] ?? true,
      calendarType: json['calendar_type'] ?? 'gregorian',
      dateFormat: json['date_format'],
      separator: json['separator'] ?? '-',
      startNumber: json['start_number'] ?? 1,
      numberPadding: json['number_padding'] ?? 4,
      resetPeriod: json['reset_period'],
      customFormat: json['custom_format'],
      isActive: json['is_active'] ?? true,
      createdAt: _safeParse(json['created_at']),
      updatedAt: _safeParse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'business_id': businessId,
      'document_type': documentType,
      'prefix': prefix,
      'include_date': includeDate,
      'calendar_type': calendarType,
      'date_format': dateFormat,
      'separator': separator,
      'start_number': startNumber,
      'number_padding': numberPadding,
      'reset_period': resetPeriod,
      'custom_format': customFormat,
      'is_active': isActive,
    };
  }

  DocumentNumberingSetting copyWith({
    int? id,
    int? businessId,
    String? documentType,
    String? prefix,
    bool? includeDate,
    String? calendarType,
    String? dateFormat,
    String? separator,
    int? startNumber,
    int? numberPadding,
    String? resetPeriod,
    String? customFormat,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DocumentNumberingSetting(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      documentType: documentType ?? this.documentType,
      prefix: prefix ?? this.prefix,
      includeDate: includeDate ?? this.includeDate,
      calendarType: calendarType ?? this.calendarType,
      dateFormat: dateFormat ?? this.dateFormat,
      separator: separator ?? this.separator,
      startNumber: startNumber ?? this.startNumber,
      numberPadding: numberPadding ?? this.numberPadding,
      resetPeriod: resetPeriod ?? this.resetPeriod,
      customFormat: customFormat ?? this.customFormat,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

