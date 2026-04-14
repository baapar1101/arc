import 'package:shamsi_date/shamsi_date.dart';
import '../core/api_client.dart';
import '../models/warranty_models.dart';

class WarrantyService {
  final ApiClient _api;

  WarrantyService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  /// دریافت تنظیمات گارانتی
  Future<WarrantySetting> getSettings(int businessId) async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/api/v1/warranty/business/$businessId/settings');
      return WarrantySetting.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to fetch warranty settings: $e');
    }
  }

  /// به‌روزرسانی تنظیمات گارانتی
  Future<WarrantySetting> updateSettings(int businessId, Map<String, dynamic> settings) async {
    try {
      final response = await _api.put<Map<String, dynamic>>(
        '/api/v1/warranty/business/$businessId/settings',
        data: settings,
      );
      return WarrantySetting.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to update warranty settings: $e');
    }
  }

  /// تولید کدهای گارانتی
  Future<List<WarrantyCode>> generateCodes(
    int businessId,
    int productId,
    int quantity,
    int warrantyDurationDays, {
    String? serialFormat,
    List<String>? customSerials,
    String? codeFormat,
    List<String>? customCodes,
  }) async {
    try {
      final payload = {
        'product_id': productId,
        'quantity': quantity,
        'warranty_duration_days': warrantyDurationDays,
        if (serialFormat != null) 'serial_format': serialFormat,
        if (customSerials != null) 'custom_serials': customSerials,
        if (codeFormat != null) 'code_format': codeFormat,
        if (customCodes != null) 'custom_codes': customCodes,
      };
      final response = await _api.post<Map<String, dynamic>>(
        '/api/v1/warranty/business/$businessId/generate',
        data: payload,
      );
      final List<dynamic> codesJson = response.data?['data'] ?? [];
      return codesJson.map((json) => WarrantyCode.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      throw Exception('Failed to generate warranty codes: $e');
    }
  }

  /// لیست کدهای گارانتی
  Future<WarrantyCodesListResponse> listCodes(
    int businessId, {
    String? status,
    int? productId,
    int limit = 100,
    int skip = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'skip': skip,
        if (status != null) 'status': status,
        if (productId != null) 'product_id': productId,
      };
      final response = await _api.get<Map<String, dynamic>>(
        '/api/v1/warranty/business/$businessId/codes',
        query: queryParams,
      );
      return WarrantyCodesListResponse.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to list warranty codes: $e');
    }
  }

  /// فعال‌سازی گارانتی (عمومی)
  Future<WarrantyActivationResponse> activateWarranty(
    int businessId,
    String warrantyCode,
    String warrantySerial,
    String customerName,
    String customerPhone, {
    String? customerEmail,
    String? productSerial,
  }) async {
    try {
      final payload = {
        'warranty_code': warrantyCode,
        'warranty_serial': warrantySerial,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        if (customerEmail != null) 'customer_email': customerEmail,
        if (productSerial != null) 'product_serial': productSerial,
      };
      final response = await _api.post<Map<String, dynamic>>(
        '/api/v1/warranty/public/activate/$businessId',
        data: payload,
      );
      return WarrantyActivationResponse.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to activate warranty: $e');
    }
  }

  /// رهگیری گارانتی (عمومی)
  Future<WarrantyTrackingInfo> trackWarranty(
    String codeOrSerial, {
    int? businessId,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        if (businessId != null) 'business_id': businessId,
      };
      final response = await _api.get<Map<String, dynamic>>(
        '/api/v1/warranty/public/track/$codeOrSerial',
        query: queryParams,
      );
      return WarrantyTrackingInfo.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to track warranty: $e');
    }
  }

  /// رهگیری گارانتی از طریق لینک یکتا
  Future<WarrantyTrackingInfo> trackWarrantyByLink(String linkCode) async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/api/v1/warranty/public/track/link/$linkCode');
      return WarrantyTrackingInfo.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to track warranty by link: $e');
    }
  }

  /// لیست کدهای گارانتی یک Person
  Future<WarrantyCodesListResponse> listCodesByPerson(
    int businessId,
    int personId, {
    String? status,
    int limit = 100,
    int skip = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'skip': skip,
        if (status != null) 'status': status,
      };
      final response = await _api.get<Map<String, dynamic>>(
        '/api/v1/warranty/business/$businessId/codes/person/$personId',
        query: queryParams,
      );
      return WarrantyCodesListResponse.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to list warranty codes by person: $e');
    }
  }

  /// حذف یک کد گارانتی
  Future<WarrantyDeleteResponse> deleteCode(
    int businessId,
    int codeId, {
    bool force = false,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'force': force,
      };
      final response = await _api.delete<Map<String, dynamic>>(
        '/api/v1/warranty/business/$businessId/codes/$codeId',
        query: queryParams,
      );
      return WarrantyDeleteResponse.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to delete warranty code: $e');
    }
  }

  /// حذف گروهی کدهای گارانتی
  Future<WarrantyBulkDeleteResponse> deleteCodes(
    int businessId,
    List<int> codeIds, {
    bool force = false,
  }) async {
    try {
      final payload = {
        'code_ids': codeIds,
        'force': force,
      };
      final response = await _api.post<Map<String, dynamic>>(
        '/api/v1/warranty/business/$businessId/codes/bulk-delete',
        data: payload,
      );
      return WarrantyBulkDeleteResponse.fromJson(response.data?['data'] ?? {});
    } catch (e) {
      throw Exception('Failed to delete warranty codes: $e');
    }
  }
}

// Response Models
class WarrantyCodesListResponse {
  final List<WarrantyCode> items;
  final int total;
  final int limit;
  final int skip;

  WarrantyCodesListResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.skip,
  });

  factory WarrantyCodesListResponse.fromJson(Map<String, dynamic> json) {
    return WarrantyCodesListResponse(
      items: (json['items'] as List<dynamic>)
          .map((e) => WarrantyCode.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'],
      limit: json['limit'],
      skip: json['skip'],
    );
  }
}

class WarrantyActivationResponse {
  final int id;
  final String code;
  final String warrantySerial;
  final WarrantyStatus status;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final String? trackingLinkCode;
  final int? personId;

  WarrantyActivationResponse({
    required this.id,
    required this.code,
    required this.warrantySerial,
    required this.status,
    this.activatedAt,
    this.expiresAt,
    this.trackingLinkCode,
    this.personId,
  });

  factory WarrantyActivationResponse.fromJson(Map<String, dynamic> json) {
    return WarrantyActivationResponse(
      id: json['id'],
      code: json['code'],
      warrantySerial: json['warranty_serial'],
      status: WarrantyStatus.fromString(json['status'] ?? 'generated'),
      activatedAt: json['activated_at'] != null
          ? _parseDateTime(json['activated_at'])
          : null,
      expiresAt: json['expires_at'] != null
          ? _parseDateTime(json['expires_at'])
          : null,
      trackingLinkCode: json['tracking_link_code'],
      personId: json['person_id'],
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

class WarrantyCheckResponse {
  final String code;
  final WarrantyStatus status;
  final DateTime? expiresAt;
  final WarrantyProductInfo? product;
  final WarrantyBusinessInfo? business;

  WarrantyCheckResponse({
    required this.code,
    required this.status,
    this.expiresAt,
    this.product,
    this.business,
  });

  factory WarrantyCheckResponse.fromJson(Map<String, dynamic> json) {
    return WarrantyCheckResponse(
      code: json['code'],
      status: WarrantyStatus.fromString(json['status'] ?? 'generated'),
      expiresAt: json['expires_at'] != null
          ? _parseDateTime(json['expires_at'])
          : null,
      product: json['product'] != null
          ? WarrantyProductInfo.fromJson(json['product'])
          : null,
      business: json['business'] != null
          ? WarrantyBusinessInfo.fromJson(json['business'])
          : null,
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

// Delete Response Models
class WarrantyDeleteResponse {
  final bool success;
  final String message;
  final Map<String, dynamic>? deletedCode;

  WarrantyDeleteResponse({
    required this.success,
    required this.message,
    this.deletedCode,
  });

  factory WarrantyDeleteResponse.fromJson(Map<String, dynamic> json) {
    return WarrantyDeleteResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      deletedCode: json['deleted_code'] as Map<String, dynamic>?,
    );
  }
}

class WarrantyBulkDeleteResponse {
  final bool success;
  final String message;
  final Map<String, int> summary;
  final List<Map<String, dynamic>> deletedCodes;
  final List<Map<String, dynamic>> skippedCodes;
  final List<Map<String, dynamic>> failedCodes;

  WarrantyBulkDeleteResponse({
    required this.success,
    required this.message,
    required this.summary,
    required this.deletedCodes,
    required this.skippedCodes,
    required this.failedCodes,
  });

  factory WarrantyBulkDeleteResponse.fromJson(Map<String, dynamic> json) {
    return WarrantyBulkDeleteResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      summary: Map<String, int>.from(json['summary'] ?? {}),
      deletedCodes: (json['deleted_codes'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      skippedCodes: (json['skipped_codes'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      failedCodes: (json['failed_codes'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }
}
