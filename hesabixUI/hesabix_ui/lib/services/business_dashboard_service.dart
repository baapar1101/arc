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
      // دریافت کسب و کارهای مالک با POST request
      final ownedResponse = await _apiClient.post<Map<String, dynamic>>(
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

      if (ownedResponse.data?['success'] == true) {
        final ownedItems = ownedResponse.data!['data']['items'] as List<dynamic>;
        businesses.addAll(
          ownedItems.map((item) {
            final business = BusinessWithPermission.fromJson(item);
            return BusinessWithPermission(
              id: business.id,
              name: business.name,
              businessType: business.businessType,
              businessField: business.businessField,
              ownerId: business.ownerId,
              address: business.address,
              phone: business.phone,
              mobile: business.mobile,
              createdAt: business.createdAt,
              isOwner: true,
              role: 'مالک',
              permissions: {},
            );
          }),
        );
      }

      // TODO: در آینده می‌توان کسب و کارهای عضو را نیز اضافه کرد
      // از API endpoint جدید برای کسب و کارهای عضو

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
}
