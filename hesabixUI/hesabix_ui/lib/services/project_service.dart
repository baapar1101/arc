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

  Future<List<Map<String, dynamic>>> listProjectActivity({
    required int businessId,
    required int projectId,
    int limit = 200,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/projects/$projectId/activity',
      query: {'limit': limit},
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listProjectFiles({
    required int businessId,
    required int projectId,
    int limit = 200,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/projects/$projectId/files',
      query: {'limit': limit},
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<ProjectCycleModel>> listCycles({
    required int businessId,
    required int projectId,
  }) async {
    final workflow = await getCycleWorkflow(
      businessId: businessId,
      projectId: projectId,
    );
    return workflow.cycles;
  }

  Future<({List<ProjectCycleModel> cycles, Set<int> backlogTaskIds})>
      getCycleWorkflow({
    required int businessId,
    required int projectId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/projects/$projectId/cycles',
    );
    final data = Map<String, dynamic>.from(response.data['data'] as Map);
    final items = (data['items'] as List?) ?? const [];
    final cycles = items
        .whereType<Map>()
        .map(
          (e) => ProjectCycleModel.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
    final backlog = ((data['backlog_task_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toSet();
    return (cycles: cycles, backlogTaskIds: backlog);
  }

  Future<void> addTaskToCycle({
    required int businessId,
    required int projectId,
    required int cycleId,
    required int taskId,
  }) async {
    await apiClient.post(
      '/api/v1/businesses/$businessId/projects/$projectId/cycles/$cycleId/tasks/$taskId',
    );
  }

  Future<List<int>> carryOverCycle({
    required int businessId,
    required int projectId,
    required int sourceCycleId,
    required int targetCycleId,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/projects/$projectId/cycles/$sourceCycleId/carry-over',
      data: {'target_cycle_id': targetCycleId},
    );
    return ((response.data['data']?['task_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
  }

  Future<ProjectCycleModel> createCycle({
    required int businessId, required int projectId, required Map<String,dynamic> data,
  }) async {
    final r=await apiClient.post('/api/v1/businesses/$businessId/projects/$projectId/cycles', data:data);
    return ProjectCycleModel.fromJson(Map<String,dynamic>.from(r.data['data']['cycle'] as Map));
  }

  Future<ProjectCycleModel> updateCycle({
    required int businessId, required int projectId, required int cycleId, required Map<String,dynamic> data,
  }) async {
    final r=await apiClient.patch('/api/v1/businesses/$businessId/projects/$projectId/cycles/$cycleId', data:data);
    return ProjectCycleModel.fromJson(Map<String,dynamic>.from(r.data['data']['cycle'] as Map));
  }

  Future<void> deleteCycle({
    required int businessId, required int projectId, required int cycleId,
  }) => apiClient.delete('/api/v1/businesses/$businessId/projects/$projectId/cycles/$cycleId');

  Future<List<ProjectMilestoneModel>> listMilestones({
    required int businessId,
    required int projectId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/projects/$projectId/milestones',
    );
    final items = (response.data['data']?['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map(
          (e) => ProjectMilestoneModel.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<ProjectMilestoneModel> createMilestone({
    required int businessId,
    required int projectId,
    required Map<String, dynamic> data,
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/projects/$projectId/milestones',
      data: data,
    );
    return ProjectMilestoneModel.fromJson(
      Map<String, dynamic>.from(
        response.data['data']['milestone'] as Map,
      ),
    );
  }

  Future<ProjectMilestoneModel> updateMilestone({
    required int businessId,
    required int projectId,
    required int milestoneId,
    required Map<String, dynamic> data,
  }) async {
    final response = await apiClient.patch(
      '/api/v1/businesses/$businessId/projects/$projectId/milestones/$milestoneId',
      data: data,
    );
    return ProjectMilestoneModel.fromJson(
      Map<String, dynamic>.from(
        response.data['data']['milestone'] as Map,
      ),
    );
  }

  Future<void> deleteMilestone({
    required int businessId,
    required int projectId,
    required int milestoneId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/projects/$projectId/milestones/$milestoneId',
    );
  }

  Future<Map<String, dynamic>> getTimeline({
    required int businessId,
    required int projectId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/projects/$projectId/timeline',
    );
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<Map<String, dynamic>> getWorkspace({
    required int businessId,
    required int projectId,
  }) async {
    final response = await apiClient.get(
      '/api/v1/businesses/$businessId/projects/$projectId/workspace',
    );
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<Map<String, dynamic>> saveMember({
    required int businessId,
    required int projectId,
    required int userId,
    String role = 'member',
  }) async {
    final response = await apiClient.post(
      '/api/v1/businesses/$businessId/projects/$projectId/members',
      data: {'user_id': userId, 'role': role},
    );
    return Map<String, dynamic>.from(response.data['data']['member'] as Map);
  }

  Future<void> removeMember({
    required int businessId,
    required int projectId,
    required int userId,
  }) async {
    await apiClient.delete(
      '/api/v1/businesses/$businessId/projects/$projectId/members/$userId',
    );
  }

}