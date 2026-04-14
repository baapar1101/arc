import '../core/api_client.dart';

class ZohalService {
  final ApiClient _api;
  ZohalService(this._api);

  // ==================== Admin APIs ====================

  /// دریافت تنظیمات سرویس زحل
  Future<Map<String, dynamic>> getSettings() async {
    final res = await _api.get<Map<String, dynamic>>('/admin/zohal/settings');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// تنظیم پیکربندی سرویس زحل
  Future<Map<String, dynamic>> setSettings({
    String? apiKey,
    String? baseUrl,
    double? lowBalanceThreshold,
  }) async {
    final res = await _api.put<Map<String, dynamic>>('/admin/zohal/settings', data: {
      if (apiKey != null) 'api_key': apiKey,
      if (baseUrl != null) 'base_url': baseUrl,
      if (lowBalanceThreshold != null) 'low_balance_threshold': lowBalanceThreshold,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// لیست سرویس‌های زحل (Admin)
  Future<List<Map<String, dynamic>>> listServices({
    String? category,
    bool? onlyActive,
  }) async {
    final query = <String, dynamic>{};
    if (category != null) query['category'] = category;
    if (onlyActive != null) query['only_active'] = onlyActive.toString();
    
    final res = await _api.get<Map<String, dynamic>>('/admin/zohal/services', query: query);
    final body = res.data as Map<String, dynamic>;
    final items = body['data']?['items'] as List? ?? [];
    return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// دریافت اطلاعات یک سرویس
  Future<Map<String, dynamic>> getService(int serviceId) async {
    final res = await _api.get<Map<String, dynamic>>('/admin/zohal/services/$serviceId');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// فعال/غیرفعال کردن سرویس
  Future<Map<String, dynamic>> toggleService(int serviceId, bool isActive) async {
    final res = await _api.put<Map<String, dynamic>>('/admin/zohal/services/$serviceId/toggle', data: {
      'is_active': isActive,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// به‌روزرسانی قیمت سرویس
  Future<Map<String, dynamic>> updateServicePrice({
    required int serviceId,
    required double basePrice,
    required int currencyId,
  }) async {
    final res = await _api.put<Map<String, dynamic>>('/admin/zohal/services/$serviceId/price', data: {
      'base_price': basePrice,
      'currency_id': currencyId,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// بارگذاری سرویس‌ها از فایل JSON
  Future<Map<String, dynamic>> loadServicesFromJson({
    required String jsonFilePath,
    required int defaultCurrencyId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>('/admin/zohal/services/load-from-json', data: {
      'json_file_path': jsonFilePath,
      'default_currency_id': defaultCurrencyId,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// دریافت آمار استفاده از سرویس‌های زحل
  Future<Map<String, dynamic>> getStatistics({
    String? startDate,
    String? endDate,
    int? businessId,
    int? serviceId,
  }) async {
    final query = <String, dynamic>{};
    if (startDate != null) query['start_date'] = startDate;
    if (endDate != null) query['end_date'] = endDate;
    if (businessId != null) query['business_id'] = businessId.toString();
    if (serviceId != null) query['service_id'] = serviceId.toString();
    
    final res = await _api.get<Map<String, dynamic>>('/admin/zohal/statistics', query: query);
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  // ==================== Business User APIs ====================

  /// لیست سرویس‌های فعال برای کسب‌وکار
  Future<Map<String, dynamic>> listServicesForBusiness({
    required int businessId,
    String? category,
  }) async {
    final query = <String, dynamic>{};
    if (category != null) query['category'] = category;
    
    final res = await _api.get<Map<String, dynamic>>('/businesses/$businessId/zohal/services', query: query);
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// اجرای استعلام
  Future<Map<String, dynamic>> executeInquiry({
    required int businessId,
    required String serviceCode,
    required Map<String, dynamic> requestData,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/businesses/$businessId/zohal/inquiry/$serviceCode',
      data: requestData,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// لیست لاگ‌های استفاده
  Future<Map<String, dynamic>> listLogs({
    required int businessId,
    int? serviceId,
    String? startDate,
    String? endDate,
    int limit = 50,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.toString(),
      'skip': skip.toString(),
    };
    if (serviceId != null) query['service_id'] = serviceId.toString();
    if (startDate != null) query['start_date'] = startDate;
    if (endDate != null) query['end_date'] = endDate;
    
    final res = await _api.get<Map<String, dynamic>>('/businesses/$businessId/zohal/logs', query: query);
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// دریافت جزئیات یک لاگ
  Future<Map<String, dynamic>> getLog({
    required int businessId,
    required int logId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>('/businesses/$businessId/zohal/logs/$logId');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}

