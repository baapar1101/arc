import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/business_dashboard_models.dart';

class BusinessDashboardService {
  final ApiClient _apiClient;

  BusinessDashboardService(this._apiClient);

  /// دریافت داشبورد کسب و کار
  Future<BusinessDashboardResponse> getDashboard(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/dashboard',
      );

      if (response.data?['success'] == true) {
        return BusinessDashboardResponse.fromJson(response.data!['data']);
      } else {
        throw Exception('Failed to load dashboard: ${response.data?['message']}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('دسترسی غیرمجاز به این کسب و کار');
      } else if (e.response?.statusCode == 404) {
        throw Exception('کسب و کار یافت نشد');
      } else {
        throw Exception('خطا در بارگذاری داشبورد: ${e.message}');
      }
    } catch (e) {
      throw Exception('خطا در بارگذاری داشبورد: $e');
    }
  }

  /// دریافت لیست اعضای کسب و کار
  Future<BusinessMembersResponse> getMembers(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/members',
      );

      if (response.data?['success'] == true) {
        return BusinessMembersResponse.fromJson(response.data!['data']);
      } else {
        throw Exception('Failed to load members: ${response.data?['message']}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('دسترسی غیرمجاز به این کسب و کار');
      } else if (e.response?.statusCode == 404) {
        throw Exception('کسب و کار یافت نشد');
      } else {
        throw Exception('خطا در بارگذاری اعضا: ${e.message}');
      }
    } catch (e) {
      throw Exception('خطا در بارگذاری اعضا: $e');
    }
  }

  /// دریافت آمار کسب و کار
  Future<Map<String, dynamic>> getStatistics(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/statistics',
      );

      if (response.data?['success'] == true) {
        return response.data!['data'];
      } else {
        throw Exception('Failed to load statistics: ${response.data?['message']}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('دسترسی غیرمجاز به این کسب و کار');
      } else if (e.response?.statusCode == 404) {
        throw Exception('کسب و کار یافت نشد');
      } else {
        throw Exception('خطا در بارگذاری آمار: ${e.message}');
      }
    } catch (e) {
      throw Exception('خطا در بارگذاری آمار: $e');
    }
  }

  /// دریافت لیست کسب و کارهای کاربر (مالک + عضو)
  Future<List<BusinessWithPermission>> getUserBusinesses() async {
    try {
      // دریافت کسب و کارهای کاربر (مالک + عضو) با POST request
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/businesses/list',
        data: {
          'take': 100,
          'skip': 0,
          'sort_by': 'created_at',
          'sort_desc': true,
          'search': null,
        },
      );

      List<BusinessWithPermission> businesses = [];

      if (response.data?['success'] == true) {
        final items = response.data!['data']['items'] as List<dynamic>;
        businesses.addAll(
          items.map((item) => BusinessWithPermission.fromJson(item)),
        );
      }

      return businesses;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('لطفاً ابتدا وارد شوید');
      } else {
        throw Exception('خطا در بارگذاری کسب و کارها: ${e.message}');
      }
    } catch (e) {
      throw Exception('خطا در بارگذاری کسب و کارها: $e');
    }
  }

  /// دریافت اطلاعات کسب و کار همراه با دسترسی‌های کاربر
  Future<BusinessWithPermission> getBusinessWithPermissions(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/info-with-permissions',
      );

      if (response.data?['success'] == true) {
        final data = response.data!['data'] as Map<String, dynamic>;
        
        // تبدیل اطلاعات کسب و کار
        final businessInfo = data['business_info'] as Map<String, dynamic>;
        final userPermissions = data['user_permissions'] as Map<String, dynamic>? ?? {};
        final isOwner = data['is_owner'] as bool? ?? false;
        final role = data['role'] as String? ?? 'عضو';
        final hasAccess = data['has_access'] as bool? ?? false;
        
        if (!hasAccess) {
          throw Exception('دسترسی غیرمجاز به این کسب و کار');
        }
        
        return BusinessWithPermission(
          id: businessInfo['id'] as int,
          name: businessInfo['name'] as String,
          businessType: businessInfo['business_type'] as String,
          businessField: businessInfo['business_field'] as String,
          ownerId: businessInfo['owner_id'] as int,
          address: businessInfo['address'] as String?,
          phone: businessInfo['phone'] as String?,
          mobile: businessInfo['mobile'] as String?,
          createdAt: businessInfo['created_at'] as String,
          isOwner: isOwner,
          role: role,
          permissions: userPermissions,
        );
      } else {
        throw Exception('Failed to load business info: ${response.data?['message']}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('دسترسی غیرمجاز به این کسب و کار');
      } else if (e.response?.statusCode == 404) {
        throw Exception('کسب و کار یافت نشد');
      } else {
        throw Exception('خطا در بارگذاری اطلاعات کسب و کار: ${e.message}');
      }
    } catch (e) {
      throw Exception('خطا در بارگذاری اطلاعات کسب و کار: $e');
    }
  }
}
