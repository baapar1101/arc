import 'package:shamsi_date/shamsi_date.dart';

/// پارس امن تاریخ از فیلدهای API (ترجیح با *_raw، پشتیبانی از جلالی و ISO)
DateTime _parseProjectDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  final raw = value.toString().trim();
  if (raw.isEmpty) return DateTime.now();

  try {
    return DateTime.parse(raw);
  } catch (_) {}

  // فرمت جلالی یا میلادی اسلش‌دار مثل 1403/06/22 18:30:00
  if (raw.contains('/') && !raw.contains('-')) {
    final parts = raw.split(' ');
    final datePart = parts[0];
    final timePart = parts.length > 1 ? parts[1] : '';
    final dateSegments = datePart.split('/');
    if (dateSegments.length == 3) {
      final year = int.tryParse(dateSegments[0]);
      final month = int.tryParse(dateSegments[1]);
      final day = int.tryParse(dateSegments[2]);
      if (year != null && month != null && day != null) {
        int hour = 0;
        int minute = 0;
        int second = 0;
        if (timePart.isNotEmpty) {
          final timeSegments = timePart.split(':');
          if (timeSegments.length >= 2) {
            hour = int.tryParse(timeSegments[0]) ?? 0;
            minute = int.tryParse(timeSegments[1]) ?? 0;
            if (timeSegments.length >= 3) {
              second = int.tryParse(timeSegments[2]) ?? 0;
            }
          }
        }
        try {
          if (year >= 1200 && year <= 1600) {
            final dt = Jalali(year, month, day).toDateTime();
            return DateTime(dt.year, dt.month, dt.day, hour, minute, second);
          }
          return DateTime(year, month, day, hour, minute, second);
        } catch (_) {}
      }
    }
  }

  return DateTime.now();
}

DateTime? _parseProjectDateTimeNullable(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return _parseProjectDateTime(value);
}

/// مدل پروژه
class ProjectModel {
  final int id;
  final int businessId;
  final String code;
  final String name;
  final String? description;
  final String status; // active, completed, on_hold, cancelled
  final String statusName;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? budget;
  final int? currencyId;
  final String? currencyCode;
  final String? currencySymbol;
  final int? managerUserId;
  final String? managerName;
  final int? personId;
  final String? personName;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int createdById;
  final String? createdByName;
  final Map<String, dynamic>? extraInfo;

  ProjectModel({
    required this.id,
    required this.businessId,
    required this.code,
    required this.name,
    this.description,
    required this.status,
    required this.statusName,
    this.startDate,
    this.endDate,
    this.budget,
    this.currencyId,
    this.currencyCode,
    this.currencySymbol,
    this.managerUserId,
    this.managerName,
    this.personId,
    this.personName,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.createdById,
    this.createdByName,
    this.extraInfo,
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      status: json['status'] as String,
      statusName: json['status_name'] as String,
      // اولویت با *_raw (ISO) تا تاریخ‌های جلالی نمایشی پارس نشکنند
      startDate: _parseProjectDateTimeNullable(
        json['start_date_raw'] ?? json['start_date'],
      ),
      endDate: _parseProjectDateTimeNullable(
        json['end_date_raw'] ?? json['end_date'],
      ),
      budget: json['budget'] != null ? (json['budget'] as num).toDouble() : null,
      currencyId: json['currency_id'] as int?,
      currencyCode: json['currency_code'] as String?,
      currencySymbol: json['currency_symbol'] as String?,
      managerUserId: json['manager_user_id'] as int?,
      managerName: json['manager_name'] as String?,
      personId: json['person_id'] as int?,
      personName: json['person_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseProjectDateTime(
        json['created_at_raw'] ?? json['created_at'],
      ),
      updatedAt: _parseProjectDateTime(
        json['updated_at_raw'] ?? json['updated_at'],
      ),
      createdById: json['created_by_id'] as int,
      createdByName: json['created_by_name'] as String?,
      extraInfo: json['extra_info'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'code': code,
      'name': name,
      'description': description,
      'status': status,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'budget': budget,
      'currency_id': currencyId,
      'manager_user_id': managerUserId,
      'person_id': personId,
      'is_active': isActive,
      'extra_info': extraInfo,
    };
  }

  /// نسخه کپی با تغییرات
  ProjectModel copyWith({
    int? id,
    int? businessId,
    String? code,
    String? name,
    String? description,
    String? status,
    String? statusName,
    DateTime? startDate,
    DateTime? endDate,
    double? budget,
    int? currencyId,
    String? currencyCode,
    String? currencySymbol,
    int? managerUserId,
    String? managerName,
    int? personId,
    String? personName,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? createdById,
    String? createdByName,
    Map<String, dynamic>? extraInfo,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      statusName: statusName ?? this.statusName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      budget: budget ?? this.budget,
      currencyId: currencyId ?? this.currencyId,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      managerUserId: managerUserId ?? this.managerUserId,
      managerName: managerName ?? this.managerName,
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      extraInfo: extraInfo ?? this.extraInfo,
    );
  }
}
