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
      }

      if (searchFields != null && searchFields.isNotEmpty) {
        queryParams['search_fields'] = searchFields;
      }

      if (sortBy != null && sortBy.isNotEmpty) {
        queryParams['sort_by'] = sortBy;
      }

      if (filters != null && filters.isNotEmpty) {
        // تبدیل Map به لیست برای API
        final filtersList = filters.entries.map((e) => {
          'property': e.key,
          'operator': 'in', // برای فیلترهای چندتایی از عملگر 'in' استفاده می‌کنیم
          'value': e.value,
        }).toList();
        queryParams['filters'] = filtersList;
      }

      final response = await _apiClient.post(
        '/api/v1/persons/businesses/$businessId/persons',
        data: queryParams,
      );

      if (response.statusCode == 200) {
        return response.data['data'];
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
