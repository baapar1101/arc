import 'package:dio/dio.dart';
import '../core/api_client.dart';
// duplicate removed
import '../core/fiscal_year_controller.dart';
import '../models/business_dashboard_models.dart';
import '../models/quick_link_tile_models.dart';

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

  /// دریافت سال مالی جاری
  Future<Map<String, dynamic>?> getCurrentFiscalYear(int businessId) async {
    try {
      final res = await _apiClient.get<Map<String, dynamic>>('/api/v1/business/$businessId/fiscal-years/current');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        return data['data'] as Map<String, dynamic>?;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// ویرایش سال مالی جاری (فقط عنوان و تاریخ‌ها)
  Future<Map<String, dynamic>> updateCurrentFiscalYear(
    int businessId, {
    required String title,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '/api/v1/business/$businessId/fiscal-years/current',
        data: {
          'title': title,
          'start_date': startDate.toIso8601String().split('T')[0],
          'end_date': endDate.toIso8601String().split('T')[0],
        },
      );

      if (response.data?['success'] == true) {
        return response.data!['data'] as Map<String, dynamic>;
      } else {
        throw Exception('Failed to update current fiscal year: ${response.data?['message']}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('دسترسی غیرمجاز به این عملیات');
      } else if (e.response?.statusCode == 404) {
        throw Exception('سال مالی جاری یافت نشد');
      } else if (e.response?.statusCode == 400) {
        final errorData = e.response?.data;
        final message = errorData?['message'] ?? 'خطا در به‌روزرسانی سال مالی جاری';
        throw Exception(message);
      } else {
        throw Exception('خطا در به‌روزرسانی سال مالی جاری: ${e.message}');
      }
    } catch (e) {
      throw Exception('خطا در به‌روزرسانی سال مالی جاری: $e');
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

  /// دریافت لیست کسب و کارهای کاربر با pagination
  Future<Map<String, dynamic>> getUserBusinessesPaginated({
    required int take,
    required int skip,
    String sortBy = 'created_at',
    bool sortDesc = true,
    String? search,
  }) async {
    try {
      // استفاده از query parameters به جای body
      final queryParams = <String, dynamic>{
        'take': take,
        'skip': skip,
        'sort_by': sortBy,
        'sort_desc': sortDesc,
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/businesses/list',
        query: queryParams,
      );

      List<BusinessWithPermission> businesses = [];
      Map<String, dynamic>? pagination;

      if (response.data?['success'] == true) {
        final data = response.data!['data'] as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>;
        businesses.addAll(
          items.map((item) => BusinessWithPermission.fromJson(item)),
        );
        pagination = data['pagination'] as Map<String, dynamic>?;
      }

      return {
        'items': businesses,
        'pagination': pagination,
      };
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
    Function(String jobId)? onJobQueued,
  }) async {
    final res = await _api_client_postJson(
      '/api/v1/business/$businessId/dashboard/data',
      {
        'widget_keys': widgetKeys,
        'filters': filters ?? const <String, dynamic>{},
      },
    );
    
    final responseData = (res['data'] as Map?) ?? const {};
    
    // بررسی اینکه آیا job در queue قرار گرفته است
    if (responseData.containsKey('job_id') && responseData.containsKey('status')) {
      final jobId = responseData['job_id'] as String?;
      final status = responseData['status'] as String?;
      
      if (jobId != null && status == 'queued') {
        // اگر job در queue قرار گرفته، callback را فراخوانی کن
        if (onJobQueued != null) {
          onJobQueued(jobId);
        }
        
        // polling برای دریافت نتیجه
        return await _pollJobResult(jobId);
      }
    }
    
    // اگر data مستقیماً برگردانده شده، آن را برگردان
    final data = responseData.containsKey('data') 
        ? (responseData['data'] as Map?) ?? const {}
        : responseData;
    return Map<String, dynamic>.from(data);
  }

  /// Polling برای دریافت نتیجه job
  Future<Map<String, dynamic>> _pollJobResult(String jobId, {int maxAttempts = 60}) async {
    int attempts = 0;
    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      
      try {
        final res = await _apiClient.get<Map<String, dynamic>>('/api/v1/jobs/$jobId');
        final responseData = res.data;
        
        if (responseData != null && responseData.containsKey('data')) {
          final data = responseData['data'];
          
          // بررسی اینکه آیا response مستقیماً widget data است (بدون state)
          // این حالت زمانی رخ می‌دهد که endpoint مستقیماً داده‌ها را برگردانده
          if (data is Map<String, dynamic>) {
            // اگر data شامل widget keys است (مثل latest_sales_invoices, sales_bar_chart)
            // و state یا id ندارد، یعنی مستقیماً widget data است
            final hasWidgetKeys = data.containsKey('latest_sales_invoices') || 
                                 data.containsKey('sales_bar_chart') || 
                                 data.containsKey('checks_today') ||
                                 data.containsKey('top_selling_products') ||
                                 data.containsKey('debtors_summary') ||
                                 data.containsKey('pnl_summary') ||
                                 data.containsKey('quick_links') ||
                                 data.containsKey('crm_calendar');
            final hasJobMetadata = data.containsKey('state') || data.containsKey('id');
            
            if (hasWidgetKeys && !hasJobMetadata) {
              // این یعنی job تمام شده و endpoint مستقیماً widget data را برگردانده
              return Map<String, dynamic>.from(data);
            }
            
            // اگر data شامل state است، یعنی job status است
            if (hasJobMetadata && data.containsKey('state')) {
              final state = data['state'] as String?;
              
              // RQ states: queued, started, finished, failed
              if (state == 'finished') {
                // اگر job تمام شده، نتیجه را برگردان
                final result = data['result'];
                
                // اگر result یک Map است
                if (result is Map<String, dynamic>) {
                  // اگر result شامل success و data است (dashboard job result)
                  if (result.containsKey('success') && result.containsKey('data')) {
                    return Map<String, dynamic>.from(result['data'] as Map? ?? const {});
                  }
                  // اگر result خودش data است (مستقیم)
                  if (result.containsKey('data')) {
                    return Map<String, dynamic>.from(result['data'] as Map? ?? const {});
                  }
                  // اگر result خودش یک Map از widget data است
                  return Map<String, dynamic>.from(result);
                }
                
                // اگر result null است یا نوع دیگری دارد
                return const <String, dynamic>{};
              } else if (state == 'failed') {
                // اگر job ناموفق بود، خطا را throw کن
                final error = data['error'] as String? ?? 'Job failed';
                throw Exception(error);
              }
              // در غیر این صورت (queued, started)، ادامه polling
            }
          }
        }
      } catch (e) {
        // اگر خطا در polling بود، بعد از چند تلاش throw کن
        if (attempts >= maxAttempts - 1) {
          throw Exception('Timeout waiting for job result: $e');
        }
      }
      
      attempts++;
    }
    
    throw Exception('Timeout waiting for job result after $maxAttempts attempts');
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

  // ----- دسترسی سریع -----
  Future<List<QuickLinkPresetOption>> getQuickLinkPresets(int businessId) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/quick-links/presets',
    );
    if (res.data?['success'] != true) {
      throw Exception(res.data?['message'] ?? 'presets error');
    }
    final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
    final list = (data['items'] as List?) ?? const [];
    return list
        .map((e) => QuickLinkPresetOption.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> getQuickLinksRaw(int businessId) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/quick-links',
    );
    if (res.data?['success'] != true) {
      throw Exception(res.data?['message'] ?? 'quick links error');
    }
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> putQuickLinks(int businessId, List<Map<String, dynamic>> items) async {
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/api/v1/business/$businessId/dashboard/quick-links',
      data: {'items': items},
    );
    if (res.data?['success'] != true) {
      throw Exception(res.data?['message'] ?? 'save quick links error');
    }
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
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
