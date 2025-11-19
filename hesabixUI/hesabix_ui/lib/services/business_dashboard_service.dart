import 'package:dio/dio.dart';
import '../core/api_client.dart';
// duplicate removed
import '../core/fiscal_year_controller.dart';
import '../models/business_dashboard_models.dart';

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
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/business/$businessId/info-with-permissions',
      );

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
        
        if (!hasAccess) {
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
        
        return businessWithPermission;
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

  // ===== Dashboard V2 (Responsive Widgets) =====

  Future<DashboardDefinitionsResponse> getWidgetDefinitions(int businessId) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/widgets/definitions',
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
    return DashboardDefinitionsResponse.fromJson(data);
  }

  Future<DashboardLayoutProfile> getLayoutProfile({
    required int businessId,
    required String breakpoint,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/layout',
      query: {'breakpoint': breakpoint},
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
    return DashboardLayoutProfile.fromJson(data);
  }

  Future<DashboardLayoutProfile> putLayoutProfile({
    required int businessId,
    required String breakpoint,
    required List<DashboardLayoutItem> items,
  }) async {
    final body = {
      'breakpoint': breakpoint,
      'items': items.map((e) => e.toJson()).toList(),
    };
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/layout',
      data: body,
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
    return DashboardLayoutProfile.fromJson(data);
  }

  Future<Map<String, dynamic>> getWidgetsBatchData({
    required int businessId,
    required List<String> widgetKeys,
    Map<String, dynamic>? filters,
  }) async {
    final res = await _api_client_postJson(
      '/api/v1/business/$businessId/dashboard/data',
      {
        'widget_keys': widgetKeys,
        'filters': filters ?? const <String, dynamic>{},
      },
    );
    final data = (res['data'] as Map?) ?? const {};
    return Map<String, dynamic>.from(data);
  }

  // Business default layout (owner can publish)
  Future<DashboardLayoutProfile?> getBusinessDefaultLayout({
    required int businessId,
    required String breakpoint,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/layout/default',
      query: {'breakpoint': breakpoint},
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
    if (data.isEmpty) return null;
    return DashboardLayoutProfile.fromJson(data);
  }

  Future<DashboardLayoutProfile> putBusinessDefaultLayout({
    required int businessId,
    required String breakpoint,
    required List<DashboardLayoutItem> items,
  }) async {
    final body = {
      'breakpoint': breakpoint,
      'items': items.map((e) => e.toJson()).toList(),
    };
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/layout/default',
      data: body,
    );
    final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
    return DashboardLayoutProfile.fromJson(data);
  }

  Future<Map<String, dynamic>> _api_client_postJson(String path, Map<String, dynamic> body) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(headers: {
        if (fiscalYearController?.fiscalYearId != null)
          'X-Fiscal-Year-ID': fiscalYearController!.fiscalYearId.toString(),
      }),
    );
    if (response.data?['success'] == true) {
      return Map<String, dynamic>.from(response.data!);
    }
    throw Exception(response.data?['message'] ?? 'API error');
  }
}
