import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/business_dashboard_models.dart';
import '../core/fiscal_year_controller.dart';

class BusinessDashboardService {
  final ApiClient _apiClient;
  final FiscalYearController? fiscalYearController;

  BusinessDashboardService(this._apiClient, {this.fiscalYearController});

  /// دریافت داشبورد کسب و کار
  Future<BusinessDashboardResponse> getDashboard(int businessId) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/dashboard',
        options: Options(headers: {
          if (fiscalYearController?.fiscalYearId != null)
            'X-Fiscal-Year-ID': fiscalYearController!.fiscalYearId.toString(),
        }),
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
        options: Options(headers: {
          if (fiscalYearController?.fiscalYearId != null)
            'X-Fiscal-Year-ID': fiscalYearController!.fiscalYearId.toString(),
        }),
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

  Future<List<Map<String, dynamic>>> listFiscalYears(int businessId) async {
    final res = await _apiClient.get<Map<String, dynamic>>('/api/v1/business/$businessId/fiscal-years');
    final data = res.data as Map<String, dynamic>;
    final items = (data['data']?['items'] as List?) ?? const [];
    return items.cast<Map<String, dynamic>>();
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
    print('=== getBusinessWithPermissions START ===');
    print('Business ID: $businessId');
    
    try {
      print('Calling API: /api/v1/business/$businessId/info-with-permissions');
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/info-with-permissions',
      );

      print('API Response received:');
      print('  - Success: ${response.data?['success']}');
      print('  - Message: ${response.data?['message']}');
      print('  - Data: ${response.data?['data']}');

      if (response.data?['success'] == true) {
        final data = response.data!['data'] as Map<String, dynamic>;
        
        // تبدیل اطلاعات کسب و کار
        final businessInfo = data['business_info'] as Map<String, dynamic>;
        // نرمال‌سازی دسترسی‌ها: هم Map پشتیبانی می‌شود و هم List<String> مثل 'inventory.read'
        final dynamic userPermissionsRaw = data['user_permissions'];
        final Map<String, dynamic> userPermissions = <String, dynamic>{};
        if (userPermissionsRaw is Map<String, dynamic>) {
          userPermissions.addAll(userPermissionsRaw);
        } else if (userPermissionsRaw is List) {
          for (final item in userPermissionsRaw) {
            if (item is String) {
              final parts = item.split('.');
              if (parts.length >= 2) {
                final String section = parts[0];
                final String action = parts[1];
                final Map<String, dynamic> sectionPerms =
                    (userPermissions[section] as Map<String, dynamic>?) ?? <String, dynamic>{};
                sectionPerms[action] = true;
                userPermissions[section] = sectionPerms;
              }
            }
          }
        }
        final isOwner = data['is_owner'] as bool? ?? false;
        final role = data['role'] as String? ?? 'عضو';
        final hasAccess = data['has_access'] as bool? ?? false;
        
        print('Parsed data:');
        print('  - Business Info: $businessInfo');
        print('  - User Permissions: $userPermissions');
        print('  - Is Owner: $isOwner');
        print('  - Role: $role');
        print('  - Has Access: $hasAccess');
        
        if (!hasAccess) {
          print('Access denied by API');
          throw Exception('دسترسی غیرمجاز به این کسب و کار');
        }
        
        // ساخت یک Map ترکیبی از اطلاعات کسب و کار + متادیتاهای دسترسی کاربر
        final Map<String, dynamic> combined = <String, dynamic>{
          ...businessInfo,
          'is_owner': isOwner,
          'role': role,
          'permissions': userPermissions,
        };

        // اگر سرور ارز پیش‌فرض یا لیست ارزها را نیز ارسال کرد، اضافه کنیم
        if (data.containsKey('default_currency')) {
          combined['default_currency'] = data['default_currency'];
        }
        if (data.containsKey('currencies')) {
          combined['currencies'] = data['currencies'];
        }

        // استفاده از fromJson برای مدیریت امن انواع (مثلاً created_at می‌تواند String یا Map باشد)
        final businessWithPermission = BusinessWithPermission.fromJson(
          Map<String, dynamic>.from(combined),
        );
        
        print('BusinessWithPermission created:');
        print('  - Name: ${businessWithPermission.name}');
        print('  - ID: ${businessWithPermission.id}');
        print('  - Is Owner: ${businessWithPermission.isOwner}');
        print('  - Role: ${businessWithPermission.role}');
        print('  - Permissions: ${businessWithPermission.permissions}');
        
        print('=== getBusinessWithPermissions END ===');
        return businessWithPermission;
      } else {
        print('API returned error: ${response.data?['message']}');
        throw Exception('Failed to load business info: ${response.data?['message']}');
      }
    } on DioException catch (e) {
      print('DioException occurred:');
      print('  - Status Code: ${e.response?.statusCode}');
      print('  - Response Data: ${e.response?.data}');
      print('  - Message: ${e.message}');
      
      if (e.response?.statusCode == 403) {
        throw Exception('دسترسی غیرمجاز به این کسب و کار');
      } else if (e.response?.statusCode == 404) {
        throw Exception('کسب و کار یافت نشد');
      } else {
        throw Exception('خطا در بارگذاری اطلاعات کسب و کار: ${e.message}');
      }
    } catch (e) {
      print('General Exception: $e');
      throw Exception('خطا در بارگذاری اطلاعات کسب و کار: $e');
    }
  }
}
