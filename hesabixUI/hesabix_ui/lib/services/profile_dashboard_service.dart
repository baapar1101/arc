import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/business_dashboard_models.dart';
import 'business_dashboard_service.dart';
import 'support_service.dart';
import 'announcements_service.dart';

/// سرویس داشبورد پروفایل کاربر
///
/// تلاش می‌کند از اندپوینت‌های پروفایل استفاده کند. در صورت عدم وجود
/// (مثلاً 404)، برای MVP از fallback محلی استفاده می‌کند تا UI کار کند.
class ProfileDashboardService {
  final ApiClient _apiClient;
  final BusinessDashboardService _businessService;

  ProfileDashboardService(this._apiClient)
      : _businessService = BusinessDashboardService(_apiClient);

  // --- تعاریف ویجت‌ها ---
  Future<DashboardDefinitionsResponse> getWidgetDefinitions() async {
    try {
      final res = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/profile/dashboard/widgets/definitions',
      );
      final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
      final defs = DashboardDefinitionsResponse.fromJson(data);
      if (defs.items.isEmpty || defs.columns.isEmpty) {
        return _fallbackDefinitions();
      }
      return defs;
    } on DioException catch (e) {
      // اگر اندپوینت وجود ندارد یا هر خطایی بود، fallback
      if (e.response?.statusCode == 404) {
        return _fallbackDefinitions();
      }
      return _fallbackDefinitions();
    } catch (_) {
      return _fallbackDefinitions();
    }
  }

  // --- پروفایل چیدمان ---
  Future<DashboardLayoutProfile> getLayoutProfile({
    required String breakpoint,
  }) async {
    try {
      final res = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/profile/dashboard/layout',
        query: {'breakpoint': breakpoint},
      );
      final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
      final profile = DashboardLayoutProfile.fromJson(data);
      if (profile.items.isEmpty) {
        // از پیش‌فرض مبتنی بر تعاریف بساز
        final defs = await getWidgetDefinitions();
        return _buildDefaultLayout(defs, breakpoint);
      }
      return profile;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final defs = await getWidgetDefinitions();
        return _buildDefaultLayout(defs, breakpoint);
      }
      final defs = await getWidgetDefinitions();
      return _buildDefaultLayout(defs, breakpoint);
    } catch (_) {
      final defs = await getWidgetDefinitions();
      return _buildDefaultLayout(defs, breakpoint);
    }
  }

  Future<DashboardLayoutProfile> putLayoutProfile({
    required String breakpoint,
    required List<DashboardLayoutItem> items,
  }) async {
    try {
      final body = {
        'breakpoint': breakpoint,
        'items': items.map((e) => e.toJson()).toList(),
      };
      final res = await _apiClient.put<Map<String, dynamic>>(
        '/api/v1/profile/dashboard/layout',
        data: body,
      );
      final data = res.data?['data'] as Map<String, dynamic>? ?? const {};
      return DashboardLayoutProfile.fromJson(data);
    } catch (_) {
      // اگر ذخیره نشد، همان ورودی را به عنوان حالت فعلی برگردان
      return DashboardLayoutProfile(
        breakpoint: breakpoint,
        columns: _fallbackColumns()[breakpoint] ?? 8,
        items: items,
        version: 1,
        updatedAt: '',
      );
    }
  }

  // --- داده‌ی ویجت‌ها (Batch) ---
  Future<Map<String, dynamic>> getWidgetsBatchData({
    required List<String> widgetKeys,
    Map<String, dynamic>? filters,
  }) async {
    // تلاش برای استفاده از اندپوینت پروفایل
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/v1/profile/dashboard/data',
        data: {
          'widget_keys': widgetKeys,
          'filters': filters ?? const <String, dynamic>{},
        },
      );
      if (response.data?['success'] == true) {
        final data = response.data!['data'] as Map<String, dynamic>? ?? const {};
        final out = Map<String, dynamic>.from(data);
        // پر کردن داده‌ی ویجت‌هایی که سرور نداد با fallback
        return _withFallbackData(out, widgetKeys);
      }
    } catch (_) {
      // ادامه می‌دهیم تا fallback پر شود
    }
    return _fallbackBatchData(widgetKeys);
  }

  // --- Fallbacks ---
  DashboardDefinitionsResponse _fallbackDefinitions() {
    final columns = _fallbackColumns();
    final items = <DashboardWidgetDefinition>[
      DashboardWidgetDefinition(
        key: 'profile_recent_businesses',
        title: 'کسب‌وکارهای شما',
        icon: 'business',
        version: 1,
        permissionsRequired: const <String>[],
        defaults: {
          'xs': {'colSpan': 1, 'rowSpan': 2},
          'sm': {'colSpan': 2, 'rowSpan': 2},
          'md': {'colSpan': 4, 'rowSpan': 2},
          'lg': {'colSpan': 4, 'rowSpan': 2},
          'xl': {'colSpan': 4, 'rowSpan': 2},
        },
      ),
      DashboardWidgetDefinition(
        key: 'profile_announcements',
        title: 'اعلان‌ها',
        icon: 'notifications',
        version: 1,
        permissionsRequired: const <String>[],
        defaults: {
          'xs': {'colSpan': 1, 'rowSpan': 2},
          'sm': {'colSpan': 2, 'rowSpan': 2},
          'md': {'colSpan': 4, 'rowSpan': 2},
          'lg': {'colSpan': 4, 'rowSpan': 2},
          'xl': {'colSpan': 4, 'rowSpan': 2},
        },
      ),
      DashboardWidgetDefinition(
        key: 'profile_support_tickets',
        title: 'تیکت‌های پشتیبانی',
        icon: 'support_agent',
        version: 1,
        permissionsRequired: const <String>[],
        defaults: {
          'xs': {'colSpan': 1, 'rowSpan': 2},
          'sm': {'colSpan': 2, 'rowSpan': 2},
          'md': {'colSpan': 4, 'rowSpan': 2},
          'lg': {'colSpan': 4, 'rowSpan': 2},
          'xl': {'colSpan': 4, 'rowSpan': 2},
        },
      ),
      DashboardWidgetDefinition(
        key: 'profile_onboarding_checklist',
        title: 'چک‌لیست شروع',
        icon: 'checklist',
        version: 1,
        permissionsRequired: const <String>[],
        defaults: {
          'xs': {'colSpan': 1, 'rowSpan': 2},
          'sm': {'colSpan': 2, 'rowSpan': 2},
          'md': {'colSpan': 4, 'rowSpan': 2},
          'lg': {'colSpan': 4, 'rowSpan': 2},
          'xl': {'colSpan': 4, 'rowSpan': 2},
        },
      ),
    ];
    return DashboardDefinitionsResponse(columns: columns, items: items);
  }

  Map<String, int> _fallbackColumns() => const <String, int>{
        'xs': 1,
        'sm': 4,
        'md': 8,
        'lg': 12,
        'xl': 12,
      };

  DashboardLayoutProfile _buildDefaultLayout(
    DashboardDefinitionsResponse defs,
    String breakpoint,
  ) {
    final cols = defs.columns[breakpoint] ?? 8;
    int order = 1;
    final items = <DashboardLayoutItem>[];
    for (final d in defs.items) {
      final dflt = d.defaults[breakpoint] ?? const <String, int>{};
      final colSpan =
          (dflt['colSpan'] ?? (cols / 2).floor()).clamp(1, cols);
      final rowSpan = dflt['rowSpan'] ?? 2;
      items.add(DashboardLayoutItem(
        key: d.key,
        order: order++,
        colSpan: colSpan,
        rowSpan: rowSpan,
        hidden: false,
      ));
    }
    return DashboardLayoutProfile(
      breakpoint: breakpoint,
      columns: cols,
      items: items,
      version: 1,
      updatedAt: '',
    );
  }

  Map<String, dynamic> _fallbackBatchData(List<String> keys) {
    final out = <String, dynamic>{};
    return _withFallbackData(out, keys);
  }

  Map<String, dynamic> _withFallbackData(
    Map<String, dynamic> base,
    List<String> keys,
  ) {
    final out = Map<String, dynamic>.from(base);
    for (final k in keys) {
      if (out.containsKey(k)) continue;
      if (k == 'profile_recent_businesses') {
        out[k] = {
          'items': <Map<String, dynamic>>[],
        };
      } else if (k == 'profile_announcements') {
        out[k] = {
          'items': <Map<String, dynamic>>[
            {
              'title': 'به حسابیکس خوش آمدید',
              'body': 'به‌زودی تجربه داشبورد شخصی‌سازی‌شده را خواهید داشت.',
              'time': DateTime.now().toIso8601String(),
            },
          ],
        };
      } else if (k == 'profile_support_tickets') {
        out[k] = {
          'items': <Map<String, dynamic>>[
            {
              'id': 1001,
              'subject': 'سؤال درباره صدور فاکتور',
              'status': 'باز',
              'updated_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
            },
            {
              'id': 1000,
              'subject': 'مشکل ورود به حساب',
              'status': 'بسته',
              'updated_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
            },
          ],
        };
      } else if (k == 'profile_onboarding_checklist') {
        out[k] = {
          'items': <Map<String, dynamic>>[
            {'key': 'create_business', 'title': 'ایجاد اولین کسب‌وکار', 'done': false},
            {'key': 'add_person', 'title': 'افزودن اولین مخاطب', 'done': false},
            {'key': 'issue_invoice', 'title': 'صدور اولین فاکتور', 'done': false},
          ],
        };
      }
    }
    return out;
  }

  // کمک‌متد برای تأمین داده واقعی برخی ویجت‌ها (مثل لیست کسب‌وکارها)
  Future<Map<String, dynamic>> hydrateSpecialWidgets(
    Map<String, dynamic> currentData,
    List<String> keys,
  ) async {
    final out = Map<String, dynamic>.from(currentData);
    if (keys.contains('profile_recent_businesses')) {
      try {
        final businesses = await _businessService.getUserBusinesses();
        out['profile_recent_businesses'] = {
          'items': businesses
              .map((b) => {
                    'id': b.id,
                    'name': b.name,
                    'role': b.role,
                    'is_owner': b.isOwner,
                  })
              .toList(),
        };
      } catch (_) {
        // در سکوت ادامه می‌دهیم؛ داده‌ی موجود کافی است
      }
    }
    if (keys.contains('profile_support_tickets')) {
      try {
        final support = SupportService(_apiClient);
        final res = await support.searchUserTickets({
          'page': 1,
          'limit': 5,
          'sort_by': 'updated_at',
          'sort_desc': true,
        });
        out['profile_support_tickets'] = {
          'items': res.items.map((t) {
            return {
              'id': t.id,
              'subject': t.title,
              'status': t.status?.name ?? '',
              'updated_at': t.updatedAt.toIso8601String(),
            };
          }).toList(),
        };
      } catch (_) {
        // fallback باقی می‌ماند
      }
    }
    if (keys.contains('profile_announcements')) {
      try {
        final ann = AnnouncementsService(_apiClient);
        final res = await ann.listAnnouncements(page: 1, limit: 5);
        final items = (res['items'] as List? ?? const <dynamic>[])
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        out['profile_announcements'] = {'items': items};
      } catch (_) {
        // fallback باقی می‌ماند
      }
    }
    return out;
  }
}


