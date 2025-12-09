import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/project_model.dart';

/// سرویس مدیریت پروژه‌ها
class ProjectService {
  final ApiClient apiClient;

  ProjectService(this.apiClient);

  /// دریافت لیست پروژه‌های فعال (برای کمبوباکس)
  Future<List<ProjectModel>> listActiveProjects(int businessId) async {
    try {
      final response = await apiClient.get(
        '/api/v1/businesses/$businessId/projects/active',
      );

      if (response.data['success'] == true) {
        final items = (response.data['data']['items'] as List?) ?? [];
        return items.map((item) => ProjectModel.fromJson(item as Map<String, dynamic>)).toList();
      }

      throw Exception('خطا در دریافت لیست پروژه‌های فعال');
    } catch (e) {
      rethrow;
    }
  }

  /// دریافت لیست پروژه‌ها با فیلتر و صفحه‌بندی
  Future<Map<String, dynamic>> listProjects({
    required int businessId,
    String? search,
    String? status,
    bool? isActive,
    int? personId,
    int? managerUserId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final queryParameters = <String, dynamic>{
        'page': page,
        'limit': limit,
      };

      if (search != null && search.isNotEmpty) {
        queryParameters['search'] = search;
      }

      if (status != null) {
        queryParameters['status'] = status;
      }

      if (isActive != null) {
        queryParameters['is_active'] = isActive;
      }

      if (personId != null) {
        queryParameters['person_id'] = personId;
      }

      if (managerUserId != null) {
        queryParameters['manager_user_id'] = managerUserId;
      }

      final response = await apiClient.get(
        '/api/v1/businesses/$businessId/projects',
        query: queryParameters,
      );

      if (response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        final items = (data['items'] as List?)?.map((item) {
          return ProjectModel.fromJson(item as Map<String, dynamic>);
        }).toList() ?? [];

        return {
          'items': items,
          'total': data['total'] as int? ?? 0,
          'page': data['page'] as int? ?? 1,
          'limit': data['limit'] as int? ?? 50,
          'pages': data['pages'] as int? ?? 1,
        };
      }

      throw Exception('خطا در دریافت لیست پروژه‌ها');
    } catch (e) {
      rethrow;
    }
  }

  /// ایجاد پروژه جدید
  Future<Map<String, dynamic>> createProject({
    required int businessId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await apiClient.post(
        '/api/v1/businesses/$businessId/projects',
        data: data,
      );

      if (response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception(response.data['message'] as String? ?? 'خطا در ایجاد پروژه');
    } catch (e) {
      rethrow;
    }
  }

  /// دریافت جزئیات پروژه
  Future<Map<String, dynamic>> getProject(int projectId) async {
    try {
      final response = await apiClient.get('/api/v1/projects/$projectId');

      if (response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception('خطا در دریافت اطلاعات پروژه');
    } catch (e) {
      rethrow;
    }
  }

  /// به‌روزرسانی پروژه
  Future<void> updateProject({
    required int projectId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await apiClient.put(
        '/api/v1/projects/$projectId',
        data: data,
      );

      if (response.data['success'] != true) {
        throw Exception(response.data['message'] as String? ?? 'خطا در به‌روزرسانی پروژه');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// حذف پروژه
  Future<void> deleteProject(int projectId, {bool hardDelete = false}) async {
    try {
      final response = await apiClient.delete(
        '/api/v1/projects/$projectId',
        query: {'hard_delete': hardDelete},
      );

      if (response.data['success'] != true) {
        throw Exception(response.data['message'] as String? ?? 'خطا در حذف پروژه');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// دریافت لیست اسناد یک پروژه
  Future<Map<String, dynamic>> listProjectDocuments({
    required int projectId,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await apiClient.get(
        '/api/v1/projects/$projectId/documents',
        query: {
          'page': page,
          'limit': limit,
        },
      );

      if (response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return {
          'items': data['items'] as List? ?? [],
          'total': data['total'] as int? ?? 0,
          'page': data['page'] as int? ?? 1,
          'limit': data['limit'] as int? ?? 50,
        };
      }

      throw Exception('خطا در دریافت اسناد پروژه');
    } catch (e) {
      rethrow;
    }
  }
}

