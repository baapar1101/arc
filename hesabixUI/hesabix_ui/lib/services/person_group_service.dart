import '../core/api_client.dart';
import '../models/person_group_model.dart';

class PersonGroupService {
  final ApiClient _apiClient;

  PersonGroupService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<List<PersonGroup>> listGroups({
    required int businessId,
    int skip = 0,
    int take = 200,
    bool activeOnly = false,
    bool rootOnly = true,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/persons/businesses/$businessId/person-groups',
      query: {
        'skip': skip,
        'take': take,
        'active_only': activeOnly,
        'root_only': rootOnly,
      },
    );
    if (response.statusCode != 200) {
      throw Exception('خطا در دریافت گروه‌های اشخاص');
    }
    final data = response.data['data'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];
    return items.map((e) => PersonGroup.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<PersonGroup> getGroup(int businessId, int groupId) async {
    final response = await _apiClient.get(
      '/api/v1/persons/businesses/$businessId/person-groups/$groupId',
    );
    if (response.statusCode != 200) {
      throw Exception('خطا در دریافت گروه');
    }
    return PersonGroup.fromJson(Map<String, dynamic>.from(response.data['data'] as Map));
  }

  Future<PersonGroup> createGroup(int businessId, PersonGroupCreateRequest body) async {
    final response = await _apiClient.post(
      '/api/v1/persons/businesses/$businessId/person-groups',
      data: body.toJson(),
    );
    if (response.statusCode != 200) {
      throw Exception('خطا در ایجاد گروه');
    }
    return PersonGroup.fromJson(Map<String, dynamic>.from(response.data['data'] as Map));
  }

  Future<PersonGroup> updateGroup(int businessId, int groupId, PersonGroupUpdateRequest body) async {
    final response = await _apiClient.patch(
      '/api/v1/persons/businesses/$businessId/person-groups/$groupId',
      data: body.toJson(),
    );
    if (response.statusCode != 200) {
      throw Exception('خطا در ویرایش گروه');
    }
    return PersonGroup.fromJson(Map<String, dynamic>.from(response.data['data'] as Map));
  }

  Future<void> deleteGroup(int businessId, int groupId) async {
    final response = await _apiClient.delete(
      '/api/v1/persons/businesses/$businessId/person-groups/$groupId',
    );
    if (response.statusCode != 200) {
      throw Exception('خطا در حذف گروه');
    }
  }
}
