import 'package:dio/dio.dart' as dio;

import '../core/api_client.dart';
import '../models/business_models.dart';

class BusinessApiService {
  static const String _basePath = '/api/v1/businesses';
  static final ApiClient _apiClient = ApiClient();
  static const String _currencyPath = '/api/v1/currencies';

  // ایجاد کسب و کار جدید
  static Future<BusinessResponse> createBusiness(BusinessData businessData) async {
    final response = await _apiClient.post(
      _basePath,
      data: businessData.toJson(),
    );

    if (response.data['success'] == true) {
      return BusinessResponse.fromJson(response.data['data']);
    } else {
      throw Exception(response.data['message'] ?? 'خطا در ایجاد کسب و کار');
    }
  }

  // دریافت فهرست ارزها
  static Future<List<Map<String, dynamic>>> getCurrencies() async {
    final response = await _apiClient.get(_currencyPath);
    if (response.data['success'] == true) {
      final List<dynamic> items = response.data['data'];
      return items.cast<Map<String, dynamic>>();
    } else {
      throw Exception(response.data['message'] ?? 'خطا در دریافت فهرست ارزها');
    }
  }

  // دریافت لیست کسب و کارها
  static Future<List<BusinessResponse>> getBusinesses({
    int page = 1,
    int perPage = 10,
    String? search,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    final queryParams = <String, dynamic>{
      'take': perPage,
      'skip': (page - 1) * perPage,
    };

    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    if (sortBy != null) {
      queryParams['sort_by'] = sortBy;
      queryParams['sort_desc'] = sortDesc;
    }

    final response = await _apiClient.post(
      '$_basePath/search',
      data: queryParams,
    );

    if (response.data['success'] == true) {
      final List<dynamic> items = response.data['data']['items'];
      return items.map((item) => BusinessResponse.fromJson(item)).toList();
    } else {
      throw Exception(response.data['message'] ?? 'خطا در دریافت لیست کسب و کارها');
    }
  }

  // دریافت جزئیات یک کسب و کار
  static Future<BusinessResponse> getBusiness(int businessId) async {
    final response = await _apiClient.get('$_basePath/$businessId');

    if (response.data['success'] == true) {
      return BusinessResponse.fromJson(response.data['data']);
    } else {
      throw Exception(response.data['message'] ?? 'خطا در دریافت جزئیات کسب و کار');
    }
  }

  // ویرایش کسب و کار
  static Future<BusinessResponse> updateBusiness(
    int businessId,
    BusinessData businessData,
  ) async {
    final response = await _apiClient.put(
      '$_basePath/$businessId',
      data: businessData.toJson(),
    );

    if (response.data['success'] == true) {
      return BusinessResponse.fromJson(response.data['data']);
    } else {
      throw Exception(response.data['message'] ?? 'خطا در ویرایش کسب و کار');
    }
  }

  // حذف کسب و کار
  static Future<void> deleteBusiness(int businessId) async {
    final response = await _apiClient.delete('$_basePath/$businessId');

    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'خطا در حذف کسب و کار');
    }
  }

  // دریافت آمار کسب و کارها
  static Future<Map<String, dynamic>> getBusinessStats() async {
    final response = await _apiClient.get('$_basePath/summary/stats');

    if (response.data['success'] == true) {
      return response.data['data'];
    } else {
      throw Exception(response.data['message'] ?? 'خطا در دریافت آمار کسب و کارها');
    }
  }

  // آپلود لوگوی کسب‌وکار
  static Future<Map<String, dynamic>> uploadLogo({
    required int businessId,
    required String filename,
    required List<int> bytes,
  }) async {
    final formData = dio.FormData.fromMap({
      'file': dio.MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _apiClient.post<Map<String, dynamic>>(
      '$_basePath/$businessId/logo',
      data: formData,
      options: dio.Options(contentType: 'multipart/form-data'),
    );
    if (response.data != null && response.data!['success'] == true) {
      return (response.data!['data'] as Map).cast<String, dynamic>();
    } else {
      throw Exception(response.data?['message'] ?? 'خطا در آپلود لوگو');
    }
  }

  // آپلود مهر/امضای کسب‌وکار
  static Future<Map<String, dynamic>> uploadStamp({
    required int businessId,
    required String filename,
    required List<int> bytes,
  }) async {
    final formData = dio.FormData.fromMap({
      'file': dio.MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _apiClient.post<Map<String, dynamic>>(
      '$_basePath/$businessId/stamp',
      data: formData,
      options: dio.Options(contentType: 'multipart/form-data'),
    );
    if (response.data != null && response.data!['success'] == true) {
      return (response.data!['data'] as Map).cast<String, dynamic>();
    } else {
      throw Exception(response.data?['message'] ?? 'خطا در آپلود مهر/امضا');
    }
  }

  /// دریافت تنظیمات چاپ فاکتورهای کسب‌وکار (عمومی و به تفکیک نوع فاکتور)
  static Future<Map<String, dynamic>> getPrintSettings(int businessId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '$_basePath/$businessId/print-settings',
    );
    final data = response.data;
    if (data != null && data['success'] == true) {
      return (data['data'] as Map).cast<String, dynamic>();
    } else {
      throw Exception(data?['message'] ?? 'خطا در دریافت تنظیمات چاپ');
    }
  }

  /// به‌روزرسانی تنظیمات چاپ فاکتورهای کسب‌وکار
  static Future<Map<String, dynamic>> updatePrintSettings(
    int businessId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _apiClient.put<Map<String, dynamic>>(
      '$_basePath/$businessId/print-settings',
      data: payload,
    );
    final data = response.data;
    if (data != null && data['success'] == true) {
      return (data['data'] as Map).cast<String, dynamic>();
    } else {
      throw Exception(data?['message'] ?? 'خطا در ذخیره تنظیمات چاپ');
    }
  }
}
