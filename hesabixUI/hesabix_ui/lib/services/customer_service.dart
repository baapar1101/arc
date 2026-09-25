import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/customer_model.dart';

class CustomerService {
  final ApiClient _apiClient;

  CustomerService(this._apiClient);

  /// جست‌وجوی مشتری‌ها با پشتیبانی از pagination
  Future<Map<String, dynamic>> searchCustomers({
    required int businessId,
    String? searchQuery,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final requestData = <String, dynamic>{
        'business_id': businessId,
        'page': page,
        'limit': limit,
      };

      if (searchQuery != null && searchQuery.isNotEmpty) {
        requestData['search'] = searchQuery;
      }

      final response = await _apiClient.post(
        '/api/v1/customers/search',
        data: requestData,
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        // تبدیل لیست مشتری‌ها
        final customersJson = data['customers'] as List<dynamic>;
        final customers = customersJson
            .map((json) => Customer.fromJson(json as Map<String, dynamic>))
            .toList();

        return {
          'customers': customers,
          'total': data['total'] as int,
          'page': data['page'] as int,
          'limit': data['limit'] as int,
          'hasMore': data['has_more'] as bool,
        };
      } else {
        throw Exception('خطا در دریافت لیست مشتری‌ها: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('خطا در جست‌وجوی مشتری‌ها: $e');
    }
  }

  /// مشتری موجود را برمی‌گرداند یا پس از بررسی تکراری، مشتری جدید می‌سازد.
  Future<Map<String, dynamic>> quickResolveCustomer({
    required int businessId,
    String? aliasName,
    String? mobile,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/customers/quick-resolve',
      data: {
        'business_id': businessId,
        if (aliasName != null && aliasName.trim().isNotEmpty)
          'alias_name': aliasName.trim(),
        if (mobile != null && mobile.trim().isNotEmpty) 'mobile': mobile.trim(),
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final customers = (data['customers'] as List<dynamic>? ?? const [])
        .map(
          (json) => Customer.fromJson(Map<String, dynamic>.from(json as Map)),
        )
        .toList();
    return {'customers': customers, 'created': data['created'] == true};
  }

  /// دریافت اطلاعات یک مشتری خاص
  Future<Customer?> getCustomerById({
    required int businessId,
    required int customerId,
  }) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/customers/detail/$customerId',
        query: {'business_id': businessId},
      );

      if (response.statusCode == 200) {
        // بررسی اینکه آیا response در wrapper است یا نه
        final responseData = response.data as Map<String, dynamic>;
        final customerJson = responseData['data'] ?? responseData;
        return Customer.fromJson(customerJson as Map<String, dynamic>);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// بررسی دسترسی کاربر به بخش مشتری‌ها
  Future<bool> checkCustomerAccess({
    required int businessId,
    required String authToken,
  }) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/customers/access-check',
        query: {'business_id': businessId},
        options: Options(headers: {'Authorization': 'Bearer $authToken'}),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
