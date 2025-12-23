import 'package:dio/dio.dart' as dio;
import '../core/api_client.dart';

class BusinessStorageService {
  final ApiClient _api;
  BusinessStorageService(this._api);

  /// آپلود فایل برای کسب‌وکار
  Future<Map<String, dynamic>> uploadFile({
    required int businessId,
    required List<int> fileBytes,
    required String filename,
    String moduleContext = 'accounting',
    String? contextId,
  }) async {
    final formData = dio.FormData.fromMap({
      'file': dio.MultipartFile.fromBytes(
        fileBytes,
        filename: filename,
      ),
      'module_context': moduleContext,
      if (contextId != null) 'context_id': contextId,
    });

    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/files/upload',
      data: formData,
      options: dio.Options(contentType: 'multipart/form-data'),
    );

    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// دریافت لیست فایل‌های کسب‌وکار
  Future<List<Map<String, dynamic>>> listFiles({
    required int businessId,
    int page = 1,
    int limit = 50,
    String? moduleContext,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (moduleContext != null) 'module_context': moduleContext,
    };

    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/files',
      query: query,
    );

    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    if (data != null && data['items'] is List) {
      return (data['items'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// دریافت لیست فایل‌های کسب‌وکار با اطلاعات pagination
  Future<Map<String, dynamic>> listFilesWithPagination({
    required int businessId,
    int page = 1,
    int limit = 50,
    String? moduleContext,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (moduleContext != null) 'module_context': moduleContext,
    };

    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/files',
      query: query,
    );

    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    if (data != null) {
      return {
        'items': (data['items'] as List?)
                ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            <Map<String, dynamic>>[],
        'pagination': data['pagination'] is Map
            ? Map<String, dynamic>.from(data['pagination'] as Map)
            : <String, dynamic>{},
      };
    }
    return {
      'items': <Map<String, dynamic>>[],
      'pagination': <String, dynamic>{},
    };
  }

  /// حذف فایل
  Future<void> deleteFile({
    required int businessId,
    required String fileId,
  }) async {
    await _api.delete('/api/v1/business/$businessId/storage/files/$fileId');
  }

  /// دریافت وابستگی‌های فایل
  Future<Map<String, dynamic>> getFileUsage({
    required int businessId,
    required String fileId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/files/$fileId/usage',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>? ?? {};
    return {
      'file': data['file'] is Map ? Map<String, dynamic>.from(data['file'] as Map) : <String, dynamic>{},
      'dependencies': (data['dependencies'] as List?)
              ?.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const <Map<String, dynamic>>[],
    };
  }

  /// تغییر نام فایل
  Future<Map<String, dynamic>> renameFile({
    required int businessId,
    required String fileId,
    required String newName,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/files/$fileId/rename',
      data: {'new_name': newName},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// دریافت اطلاعات استفاده از ذخیره‌سازی
  Future<Map<String, dynamic>> getUsageInfo(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/usage',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// دریافت لیست اشتراک‌های فعال
  Future<List<Map<String, dynamic>>> getActiveSubscriptions(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/subscriptions',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// دانلود فایل
  Future<List<int>> downloadFile({
    required int businessId,
    required String fileId,
  }) async {
    final res = await _api.get<List<int>>(
      '/api/v1/business/$businessId/storage/files/$fileId/download',
      options: dio.Options(responseType: dio.ResponseType.bytes),
    );
    return res.data ?? [];
  }
  
  /// دریافت لیست فایل‌های یک context خاص (مثلاً یک سند)
  Future<List<Map<String, dynamic>>> listFilesByContext({
    required int businessId,
    required String moduleContext,
    required String contextId,
  }) async {
    final query = <String, dynamic>{
      'module_context': moduleContext,
      'context_id': contextId,
      'limit': 100, // برای فایل‌های یک سند معمولاً زیاد نیست
    };

    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/files',
      query: query,
    );

    final body = res.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    if (data != null && data['items'] is List) {
      return (data['items'] as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// دریافت لیست پلن‌های قابل اشتراک
  Future<List<Map<String, dynamic>>> getAvailablePlans(int businessId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/plans',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// اشتراک به یک پلن
  Future<Map<String, dynamic>> subscribeToPlan({
    required int businessId,
    required int planId,
    bool autoRenew = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/subscribe',
      data: {
        'plan_id': planId,
        'auto_renew': autoRenew,
      },
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// دریافت لیست صورتحساب‌های ذخیره‌سازی
  Future<Map<String, dynamic>> listInvoices({
    required int businessId,
    int limit = 50,
    int skip = 0,
    String? status,
    String? invoiceType,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      'skip': skip,
      if (status != null) 'status': status,
      if (invoiceType != null) 'invoice_type': invoiceType,
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/invoices',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// پرداخت صورتحساب از کیف پول
  Future<Map<String, dynamic>> payInvoice({
    required int businessId,
    required int invoiceId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/business/$businessId/storage/invoices/$invoiceId/pay',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}

