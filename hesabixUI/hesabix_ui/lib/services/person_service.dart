import '../core/api_client.dart';
import '../models/person_model.dart';

class PersonService {
  final ApiClient _apiClient;

  PersonService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// دریافت لیست اشخاص یک کسب و کار
  Future<Map<String, dynamic>> getPersons({
    required int businessId,
    int page = 1,
    int limit = 20,
    String? search,
    List<String>? searchFields,
    String? sortBy,
    bool sortDesc = true,
    Map<String, dynamic>? filters,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'take': limit,
        'skip': (page - 1) * limit,
        'sort_desc': sortDesc,
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
        // اگر search_fields مشخص نشده، فیلدهای پیش‌فرض را استفاده کن
        if (searchFields == null || searchFields.isEmpty) {
          queryParams['search_fields'] = ['alias_name', 'first_name', 'last_name', 'company_name', 'mobile', 'email'];
        }
      }

      if (searchFields != null && searchFields.isNotEmpty) {
        queryParams['search_fields'] = searchFields;
      }

      if (sortBy != null && sortBy.isNotEmpty) {
        queryParams['sort_by'] = sortBy;
      }

      if (filters != null && filters.isNotEmpty) {
        // تبدیل Map به لیست برای API با پشتیبانی از person_type و person_types
        final List<Map<String, dynamic>> filtersList = <Map<String, dynamic>>[];
        filters.forEach((key, value) {
          // یکسان‌سازی: اگر person_type ارسال شود، به person_types (لیستی) تبدیل می‌کنیم
          if (key == 'person_type') {
            final List<dynamic> values = value is List ? List<dynamic>.from(value) : <dynamic>[value];
            filtersList.add({
              'property': 'person_types',
              'operator': 'in',
              'value': values,
            });
            return;
          }

          if (key == 'person_types') {
            final List<dynamic> values = value is List ? List<dynamic>.from(value) : <dynamic>[value];
            filtersList.add({
              'property': 'person_types',
              'operator': 'in',
              'value': values,
            });
            return;
          }

          // سایر فیلترها: اگر مقدار لیست باشد از in، در غیر این صورت از = استفاده می‌کنیم
          final bool isList = value is List;
          filtersList.add({
            'property': key,
            'operator': isList ? 'in' : '=',
            'value': value,
          });
        });
        queryParams['filters'] = filtersList;
      }

      // Debug: نمایش پارامترهای ارسالی
      print('PersonService API Call:');
      print('URL: /api/v1/persons/businesses/$businessId/persons');
      print('Data: $queryParams');
      
      final response = await _apiClient.post(
        '/api/v1/persons/businesses/$businessId/persons',
        data: queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        print('PersonService Response Data: $data');
        return data;
      } else {
        throw Exception('خطا در دریافت لیست اشخاص');
      }
    } catch (e) {
      throw Exception('خطا در دریافت لیست اشخاص: $e');
    }
  }

  /// دریافت جزئیات یک شخص
  Future<Person> getPerson(int personId) async {
    try {
      final response = await _apiClient.get('/api/v1/persons/persons/$personId');

      if (response.statusCode == 200) {
        return Person.fromJson(response.data['data']);
      } else {
        throw Exception('خطا در دریافت جزئیات شخص');
      }
    } catch (e) {
      throw Exception('خطا در دریافت جزئیات شخص: $e');
    }
  }

  /// ایجاد شخص جدید
  Future<Person> createPerson({
    required int businessId,
    required PersonCreateRequest personData,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/persons/businesses/$businessId/persons/create',
        data: personData.toJson(),
      );

      if (response.statusCode == 200) {
        return Person.fromJson(response.data['data']);
      } else {
        throw Exception('خطا در ایجاد شخص');
      }
    } catch (e) {
      throw Exception('خطا در ایجاد شخص: $e');
    }
  }

  /// ویرایش شخص
  Future<Person> updatePerson({
    required int personId,
    required PersonUpdateRequest personData,
  }) async {
    try {
      final response = await _apiClient.put(
        '/api/v1/persons/persons/$personId',
        data: personData.toJson(),
      );

      if (response.statusCode == 200) {
        return Person.fromJson(response.data['data']);
      } else {
        throw Exception('خطا در ویرایش شخص');
      }
    } catch (e) {
      throw Exception('خطا در ویرایش شخص: $e');
    }
  }

  /// حذف شخص
  Future<bool> deletePerson(int personId) async {
    try {
      final response = await _apiClient.delete('/api/v1/persons/persons/$personId');

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('خطا در حذف شخص');
      }
    } catch (e) {
      throw Exception('خطا در حذف شخص: $e');
    }
  }

  /// دریافت خلاصه اشخاص
  Future<Map<String, dynamic>> getPersonsSummary(int businessId) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/persons/businesses/$businessId/persons/summary',
      );

      if (response.statusCode == 200) {
        return response.data['data'];
      } else {
        throw Exception('خطا در دریافت خلاصه اشخاص');
      }
    } catch (e) {
      throw Exception('خطا در دریافت خلاصه اشخاص: $e');
    }
  }

  /// تبدیل لیست اشخاص از JSON
  List<Person> parsePersonsList(Map<String, dynamic> data) {
    final List<dynamic> items = data['items'] ?? [];
    return items.map((item) => Person.fromJson(item)).toList();
  }

  /// دریافت اطلاعات صفحه‌بندی
  Map<String, dynamic> getPaginationInfo(Map<String, dynamic> data) {
    return data['pagination'] ?? {};
  }

  /// دریافت اطلاعات جستجو
  Map<String, dynamic> getQueryInfo(Map<String, dynamic> data) {
    return data['query_info'] ?? {};
  }
}
