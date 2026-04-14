import 'package:shamsi_date/shamsi_date.dart';

class WarrantySetting {
  final int? id;
  final int businessId;
  final String codeFormat; // random, sequential, custom
  final String? codePrefix;
  final String serialFormat; // random, custom
  final int? serialLength;
  final bool requireSerialVerification;
  final bool requireProductInstanceMatch;
  final int? maxActivationAttempts;
  final int? activationLockoutDurationMinutes;
  final bool requireCustomerRegistration;
  final bool autoLinkToPerson;
  final bool enableTrackingLink;
  final int? trackingLinkExpiresDays;
  final bool enableSmsNotification;
  final bool enableEmailNotification;
  final Map<String, dynamic>? securityFeatures;
  final DateTime createdAt;
  final DateTime updatedAt;

  WarrantySetting({
    this.id,
    required this.businessId,
    required this.codeFormat,
    this.codePrefix,
    required this.serialFormat,
    this.serialLength,
    required this.requireSerialVerification,
    required this.requireProductInstanceMatch,
    this.maxActivationAttempts,
    this.activationLockoutDurationMinutes,
    required this.requireCustomerRegistration,
    required this.autoLinkToPerson,
    required this.enableTrackingLink,
    this.trackingLinkExpiresDays,
    required this.enableSmsNotification,
    required this.enableEmailNotification,
    this.securityFeatures,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WarrantySetting.fromJson(Map<String, dynamic> json) {
    return WarrantySetting(
      id: json['id'],
      businessId: json['business_id'],
      codeFormat: json['code_format'] ?? 'random',
      codePrefix: json['code_prefix'],
      serialFormat: json['serial_format'] ?? 'random',
      serialLength: json['serial_length'],
      requireSerialVerification: json['require_serial_verification'] ?? false,
      requireProductInstanceMatch: json['require_product_instance_match'] ?? false,
      maxActivationAttempts: json['max_activation_attempts'],
      activationLockoutDurationMinutes: json['activation_lockout_duration_minutes'],
      requireCustomerRegistration: json['require_customer_registration'] ?? false,
      autoLinkToPerson: json['auto_link_to_person'] ?? true,
      enableTrackingLink: json['enable_tracking_link'] ?? true,
      trackingLinkExpiresDays: json['tracking_link_expires_days'],
      enableSmsNotification: json['enable_sms_notification'] ?? false,
      enableEmailNotification: json['enable_email_notification'] ?? false,
      securityFeatures: json['security_features'] != null
          ? Map<String, dynamic>.from(json['security_features'])
          : null,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) {
      // epoch ms
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      // Jalali format: YYYY/MM/DD [HH:MM:SS]
      if (value.contains('/') && !value.contains('-')) {
        try {
          final parts = value.split(' ');
          final dateParts = parts[0].split('/');
          if (dateParts.length == 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            int hour = 0, minute = 0, second = 0;
            if (parts.length > 1) {
              final timeParts = parts[1].split(':');
              if (timeParts.length >= 2) {
                hour = int.parse(timeParts[0]);
                minute = int.parse(timeParts[1]);
                if (timeParts.length >= 3) {
                  second = int.parse(timeParts[2]);
                }
              }
            }
            // اگر سال بزرگتر از 1500 است، Jalali است
            if (year > 1500) {
              final j = Jalali(year, month, day);
              final dt = j.toDateTime();
              return DateTime(dt.year, dt.month, dt.day, hour, minute, second);
            } else {
              // سال میلادی است
              return DateTime(year, month, day, hour, minute, second);
            }
          }
        } catch (_) {
          // fallthrough
        }
      }
      // ISO or other parseable formats
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'code_format': codeFormat,
      'code_prefix': codePrefix,
      'serial_format': serialFormat,
      'serial_length': serialLength,
      'require_serial_verification': requireSerialVerification,
      'require_product_instance_match': requireProductInstanceMatch,
      'max_activation_attempts': maxActivationAttempts,
      'activation_lockout_duration_minutes': activationLockoutDurationMinutes,
      'require_customer_registration': requireCustomerRegistration,
      'auto_link_to_person': autoLinkToPerson,
      'enable_tracking_link': enableTrackingLink,
      'tracking_link_expires_days': trackingLinkExpiresDays,
      'enable_sms_notification': enableSmsNotification,
      'enable_email_notification': enableEmailNotification,
      'security_features': securityFeatures,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

enum WarrantyStatus {
  generated,
  activated,
  expired,
  used,
  revoked;

  static WarrantyStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'generated':
        return WarrantyStatus.generated;
      case 'activated':
        return WarrantyStatus.activated;
      case 'expired':
        return WarrantyStatus.expired;
      case 'used':
        return WarrantyStatus.used;
      case 'revoked':
        return WarrantyStatus.revoked;
      default:
        return WarrantyStatus.generated;
    }
  }

  String get value {
    switch (this) {
      case WarrantyStatus.generated:
        return 'generated';
      case WarrantyStatus.activated:
        return 'activated';
      case WarrantyStatus.expired:
        return 'expired';
      case WarrantyStatus.used:
        return 'used';
      case WarrantyStatus.revoked:
        return 'revoked';
    }
  }
}

class WarrantyCode {
  final int? id;
  final int businessId;
  final String code;
  final String warrantySerial;
  final int productId;
  final int? productInstanceId;
  final WarrantyStatus status;
  final int? generatedByUserId;
  final DateTime generatedAt;
  final DateTime? activatedAt;
  final int? activatedByPersonId;
  final Map<String, dynamic>? activatedByCustomerInfo;
  final DateTime? expiresAt;
  final int warrantyDurationDays;
  final String? trackingLinkCode;
  final Map<String, dynamic>? extraMetadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  WarrantyCode({
    this.id,
    required this.businessId,
    required this.code,
    required this.warrantySerial,
    required this.productId,
    this.productInstanceId,
    required this.status,
    this.generatedByUserId,
    required this.generatedAt,
    this.activatedAt,
    this.activatedByPersonId,
    this.activatedByCustomerInfo,
    this.expiresAt,
    required this.warrantyDurationDays,
    this.trackingLinkCode,
    this.extraMetadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WarrantyCode.fromJson(Map<String, dynamic> json) {
    return WarrantyCode(
      id: json['id'],
      businessId: json['business_id'],
      code: json['code'],
      warrantySerial: json['warranty_serial'],
      productId: json['product_id'],
      productInstanceId: json['product_instance_id'],
      status: WarrantyStatus.fromString(json['status'] ?? 'generated'),
      generatedByUserId: json['generated_by_user_id'],
      generatedAt: _parseDateTime(json['generated_at']),
      activatedAt: json['activated_at'] != null
          ? _parseDateTime(json['activated_at'])
          : null,
      activatedByPersonId: json['activated_by_person_id'],
      activatedByCustomerInfo: json['activated_by_customer_info'] != null
          ? Map<String, dynamic>.from(json['activated_by_customer_info'])
          : null,
      expiresAt: json['expires_at'] != null
          ? _parseDateTime(json['expires_at'])
          : null,
      warrantyDurationDays: json['warranty_duration_days'],
      trackingLinkCode: json['tracking_link_code'],
      extraMetadata: json['extra_metadata'] != null
          ? Map<String, dynamic>.from(json['extra_metadata'])
          : null,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      if (value.contains('/') && !value.contains('-')) {
        try {
          final parts = value.split(' ');
          final dateParts = parts[0].split('/');
          if (dateParts.length == 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            int hour = 0, minute = 0, second = 0;
            if (parts.length > 1) {
              final timeParts = parts[1].split(':');
              if (timeParts.length >= 2) {
                hour = int.parse(timeParts[0]);
                minute = int.parse(timeParts[1]);
                if (timeParts.length >= 3) {
                  second = int.parse(timeParts[2]);
                }
              }
            }
            if (year > 1500) {
              final j = Jalali(year, month, day);
              final dt = j.toDateTime();
              return DateTime(dt.year, dt.month, dt.day, hour, minute, second);
            } else {
              return DateTime(year, month, day, hour, minute, second);
            }
          }
        } catch (_) {
          // fallthrough
        }
      }
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'code': code,
      'warranty_serial': warrantySerial,
      'product_id': productId,
      'product_instance_id': productInstanceId,
      'status': status.value,
      'generated_by_user_id': generatedByUserId,
      'generated_at': generatedAt.toIso8601String(),
      'activated_at': activatedAt?.toIso8601String(),
      'activated_by_person_id': activatedByPersonId,
      'activated_by_customer_info': activatedByCustomerInfo,
      'expires_at': expiresAt?.toIso8601String(),
      'warranty_duration_days': warrantyDurationDays,
      'tracking_link_code': trackingLinkCode,
      'extra_metadata': extraMetadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class WarrantyActivation {
  final int? id;
  final int warrantyCodeId;
  final int? personId;
  final int? productInstanceId;
  final String warrantySerial;
  final String? productSerial;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final DateTime activationDate;
  final String? ipAddress;
  final String? userAgent;
  final String? verificationMethod;
  final DateTime createdAt;

  WarrantyActivation({
    this.id,
    required this.warrantyCodeId,
    this.personId,
    this.productInstanceId,
    required this.warrantySerial,
    this.productSerial,
    required this.customerName,
    required this.customerPhone,
    this.customerEmail,
    required this.activationDate,
    this.ipAddress,
    this.userAgent,
    this.verificationMethod,
    required this.createdAt,
  });

  factory WarrantyActivation.fromJson(Map<String, dynamic> json) {
    return WarrantyActivation(
      id: json['id'],
      warrantyCodeId: json['warranty_code_id'],
      personId: json['person_id'],
      productInstanceId: json['product_instance_id'],
      warrantySerial: json['warranty_serial'],
      productSerial: json['product_serial'],
      customerName: json['customer_name'],
      customerPhone: json['customer_phone'],
      customerEmail: json['customer_email'],
      activationDate: _parseDateTime(json['activation_date']),
      ipAddress: json['ip_address'],
      userAgent: json['user_agent'],
      verificationMethod: json['verification_method'],
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      if (value.contains('/') && !value.contains('-')) {
        try {
          final parts = value.split(' ');
          final dateParts = parts[0].split('/');
          if (dateParts.length == 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            int hour = 0, minute = 0, second = 0;
            if (parts.length > 1) {
              final timeParts = parts[1].split(':');
              if (timeParts.length >= 2) {
                hour = int.parse(timeParts[0]);
                minute = int.parse(timeParts[1]);
                if (timeParts.length >= 3) {
                  second = int.parse(timeParts[2]);
                }
              }
            }
            if (year > 1500) {
              final j = Jalali(year, month, day);
              final dt = j.toDateTime();
              return DateTime(dt.year, dt.month, dt.day, hour, minute, second);
            } else {
              return DateTime(year, month, day, hour, minute, second);
            }
          }
        } catch (_) {
          // fallthrough
        }
      }
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'warranty_code_id': warrantyCodeId,
      'person_id': personId,
      'product_instance_id': productInstanceId,
      'warranty_serial': warrantySerial,
      'product_serial': productSerial,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_email': customerEmail,
      'activation_date': activationDate.toIso8601String(),
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'verification_method': verificationMethod,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

enum WarrantyEventType {
  activation,
  repairRequest,
  repairCompleted,
  replacement,
  expired,
  revoked;

  static WarrantyEventType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'activation':
        return WarrantyEventType.activation;
      case 'repair_request':
        return WarrantyEventType.repairRequest;
      case 'repair_completed':
        return WarrantyEventType.repairCompleted;
      case 'replacement':
        return WarrantyEventType.replacement;
      case 'expired':
        return WarrantyEventType.expired;
      case 'revoked':
        return WarrantyEventType.revoked;
      default:
        return WarrantyEventType.activation;
    }
  }

  String get value {
    switch (this) {
      case WarrantyEventType.activation:
        return 'activation';
      case WarrantyEventType.repairRequest:
        return 'repair_request';
      case WarrantyEventType.repairCompleted:
        return 'repair_completed';
      case WarrantyEventType.replacement:
        return 'replacement';
      case WarrantyEventType.expired:
        return 'expired';
      case WarrantyEventType.revoked:
        return 'revoked';
    }
  }
}

class WarrantyTracking {
  final int? id;
  final int warrantyCodeId;
  final int? productInstanceId;
  final int? personId;
  final WarrantyEventType eventType;
  final String? description;
  final int? performedByUserId;
  final DateTime createdAt;

  WarrantyTracking({
    this.id,
    required this.warrantyCodeId,
    this.productInstanceId,
    this.personId,
    required this.eventType,
    this.description,
    this.performedByUserId,
    required this.createdAt,
  });

  factory WarrantyTracking.fromJson(Map<String, dynamic> json) {
    return WarrantyTracking(
      id: json['id'],
      warrantyCodeId: json['warranty_code_id'],
      productInstanceId: json['product_instance_id'],
      personId: json['person_id'],
      eventType: WarrantyEventType.fromString(json['event_type'] ?? 'activation'),
      description: json['description'],
      performedByUserId: json['performed_by_user_id'],
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      if (value.contains('/') && !value.contains('-')) {
        try {
          final parts = value.split(' ');
          final dateParts = parts[0].split('/');
          if (dateParts.length == 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            int hour = 0, minute = 0, second = 0;
            if (parts.length > 1) {
              final timeParts = parts[1].split(':');
              if (timeParts.length >= 2) {
                hour = int.parse(timeParts[0]);
                minute = int.parse(timeParts[1]);
                if (timeParts.length >= 3) {
                  second = int.parse(timeParts[2]);
                }
              }
            }
            if (year > 1500) {
              final j = Jalali(year, month, day);
              final dt = j.toDateTime();
              return DateTime(dt.year, dt.month, dt.day, hour, minute, second);
            } else {
              return DateTime(year, month, day, hour, minute, second);
            }
          }
        } catch (_) {
          // fallthrough
        }
      }
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'warranty_code_id': warrantyCodeId,
      'product_instance_id': productInstanceId,
      'person_id': personId,
      'event_type': eventType.value,
      'description': description,
      'performed_by_user_id': performedByUserId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WarrantyTrackingLink {
  final int? id;
  final int warrantyCodeId;
  final int personId;
  final String linkCode;
  final DateTime? expiresAt;
  final bool isActive;
  final int accessCount;
  final DateTime? lastAccessedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  WarrantyTrackingLink({
    this.id,
    required this.warrantyCodeId,
    required this.personId,
    required this.linkCode,
    this.expiresAt,
    required this.isActive,
    required this.accessCount,
    this.lastAccessedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WarrantyTrackingLink.fromJson(Map<String, dynamic> json) {
    return WarrantyTrackingLink(
      id: json['id'],
      warrantyCodeId: json['warranty_code_id'],
      personId: json['person_id'],
      linkCode: json['link_code'],
      expiresAt: json['expires_at'] != null
          ? _parseDateTime(json['expires_at'])
          : null,
      isActive: json['is_active'] ?? true,
      accessCount: json['access_count'] ?? 0,
      lastAccessedAt: json['last_accessed_at'] != null
          ? _parseDateTime(json['last_accessed_at'])
          : null,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      if (value.contains('/') && !value.contains('-')) {
        try {
          final parts = value.split(' ');
          final dateParts = parts[0].split('/');
          if (dateParts.length == 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            int hour = 0, minute = 0, second = 0;
            if (parts.length > 1) {
              final timeParts = parts[1].split(':');
              if (timeParts.length >= 2) {
                hour = int.parse(timeParts[0]);
                minute = int.parse(timeParts[1]);
                if (timeParts.length >= 3) {
                  second = int.parse(timeParts[2]);
                }
              }
            }
            if (year > 1500) {
              final j = Jalali(year, month, day);
              final dt = j.toDateTime();
              return DateTime(dt.year, dt.month, dt.day, hour, minute, second);
            } else {
              return DateTime(year, month, day, hour, minute, second);
            }
          }
        } catch (_) {
          // fallthrough
        }
      }
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'warranty_code_id': warrantyCodeId,
      'person_id': personId,
      'link_code': linkCode,
      'expires_at': expiresAt?.toIso8601String(),
      'is_active': isActive,
      'access_count': accessCount,
      'last_accessed_at': lastAccessedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class WarrantyTrackingInfo {
  final int id;
  final String code;
  final String warrantySerial;
  final WarrantyStatus status;
  final DateTime generatedAt;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final int warrantyDurationDays;
  final WarrantyProductInfo? product;
  final WarrantyBusinessInfo? business;
  final List<WarrantyTracking> trackingEvents;

  WarrantyTrackingInfo({
    required this.id,
    required this.code,
    required this.warrantySerial,
    required this.status,
    required this.generatedAt,
    this.activatedAt,
    this.expiresAt,
    required this.warrantyDurationDays,
    this.product,
    this.business,
    required this.trackingEvents,
  });

  factory WarrantyTrackingInfo.fromJson(Map<String, dynamic> json) {
    return WarrantyTrackingInfo(
      id: json['id'],
      code: json['code'],
      warrantySerial: json['warranty_serial'],
      status: WarrantyStatus.fromString(json['status'] ?? 'generated'),
      generatedAt: _parseDateTime(json['generated_at']),
      activatedAt: json['activated_at'] != null
          ? _parseDateTime(json['activated_at'])
          : null,
      expiresAt: json['expires_at'] != null
          ? _parseDateTime(json['expires_at'])
          : null,
      warrantyDurationDays: json['warranty_duration_days'],
      product: json['product'] != null
          ? WarrantyProductInfo.fromJson(json['product'])
          : null,
      business: json['business'] != null
          ? WarrantyBusinessInfo.fromJson(json['business'])
          : null,
      trackingEvents: (json['tracking_events'] as List<dynamic>?)
              ?.map((e) => WarrantyTracking.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      if (value.contains('/') && !value.contains('-')) {
        try {
          final parts = value.split(' ');
          final dateParts = parts[0].split('/');
          if (dateParts.length == 3) {
            final year = int.parse(dateParts[0]);
            final month = int.parse(dateParts[1]);
            final day = int.parse(dateParts[2]);
            int hour = 0, minute = 0, second = 0;
            if (parts.length > 1) {
              final timeParts = parts[1].split(':');
              if (timeParts.length >= 2) {
                hour = int.parse(timeParts[0]);
                minute = int.parse(timeParts[1]);
                if (timeParts.length >= 3) {
                  second = int.parse(timeParts[2]);
                }
              }
            }
            if (year > 1500) {
              final j = Jalali(year, month, day);
              final dt = j.toDateTime();
              return DateTime(dt.year, dt.month, dt.day, hour, minute, second);
            } else {
              return DateTime(year, month, day, hour, minute, second);
            }
          }
        } catch (_) {
          // fallthrough
        }
      }
      try {
        return DateTime.parse(value);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }
}

class WarrantyProductInfo {
  final int? id;
  final String? name;
  final String? code;

  WarrantyProductInfo({
    this.id,
    this.name,
    this.code,
  });

  factory WarrantyProductInfo.fromJson(Map<String, dynamic> json) {
    return WarrantyProductInfo(
      id: json['id'],
      name: json['name'],
      code: json['code'],
    );
  }
}

class WarrantyBusinessInfo {
  final int? id;
  final String? name;
  final String? code;

  WarrantyBusinessInfo({
    this.id,
    this.name,
    this.code,
  });

  factory WarrantyBusinessInfo.fromJson(Map<String, dynamic> json) {
    return WarrantyBusinessInfo(
      id: json['id'],
      name: json['name'],
      code: json['code'],
    );
  }
}

