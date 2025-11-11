import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'pages/profile/notifications_settings_page.dart';
import 'pages/profile/notification_templates_admin_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'l10n/app_localizations.dart';

import 'pages/login_page.dart';
import 'pages/profile/profile_shell.dart';
import 'pages/profile/profile_dashboard_page.dart';
import 'pages/profile/new_business_page.dart';
import 'pages/profile/businesses_page.dart';
import 'pages/profile/support_page.dart';
import 'pages/profile/change_password_page.dart';
import 'pages/profile/marketing_page.dart';
import 'pages/profile/operator/operator_tickets_page.dart';
import 'pages/profile/announcements_page.dart';
import 'pages/system_settings_page.dart';
import 'pages/admin/storage_management_page.dart';
import 'pages/admin/system_configuration_page.dart';
import 'pages/admin/user_management_page.dart';
import 'pages/admin/system_logs_page.dart';
import 'pages/admin/email_settings_page.dart';
import 'pages/admin/announcements_admin_page.dart';
import 'pages/business/business_shell.dart';
import 'pages/business/dashboard/business_dashboard_page.dart';
import 'pages/business/users_permissions_page.dart';
import 'pages/business/accounts_page.dart';
import 'pages/business/bank_accounts_page.dart';
import 'pages/business/wallet_page.dart';
import 'pages/business/wallet_payment_result_page.dart';
import 'pages/admin/wallet_settings_page.dart';
import 'pages/admin/payment_gateways_page.dart';
import 'pages/business/invoices_list_page.dart';
import 'pages/business/new_invoice_page.dart';
import 'pages/business/edit_invoice_page.dart';
import 'pages/business/settings_page.dart';
import 'pages/business/business_info_settings_page.dart';
import 'pages/business/reports_page.dart';
import 'pages/business/kardex_page.dart';
import 'pages/business/persons_page.dart';
import 'pages/business/product_attributes_page.dart';
import 'pages/business/products_page.dart';
import 'pages/business/price_lists_page.dart';
import 'pages/business/price_list_items_page.dart';
import 'pages/business/cash_registers_page.dart';
import 'pages/business/petty_cash_page.dart';
import 'pages/business/checks_page.dart';
import 'pages/business/plugin_marketplace_page.dart';
import 'pages/business/marketplace_invoices_page.dart';
import 'pages/business/check_form_page.dart';
import 'pages/business/receipts_payments_list_page.dart';
import 'pages/business/expense_income_list_page.dart';
import 'pages/business/transfers_page.dart';
import 'pages/business/documents_page.dart';
import 'pages/business/warehouses_page.dart';
import 'pages/business/inventory_transfers_page.dart';
import 'pages/error_404_page.dart';
import 'core/locale_controller.dart';
import 'core/calendar_controller.dart';
import 'core/api_client.dart';
import 'theme/theme_controller.dart';
import 'theme/app_theme.dart';
import 'core/auth_store.dart';
import 'core/permission_guard.dart';
import 'widgets/simple_splash_screen.dart';
import 'widgets/url_tracker.dart';
import 'pages/business/opening_balance_page.dart';
import 'pages/business/report_templates_page.dart';
import 'pages/business/backup/backup_page.dart';
import 'pages/business/backup/restore_page.dart';

void main() {
  // Use path-based routing instead of hash routing
  usePathUrlStrategy();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  LocaleController? _controller;
  CalendarController? _calendarController;
  ThemeController? _themeController;
  AuthStore? _authStore;
  bool _isLoading = true;
  DateTime? _loadStartTime;

  @override
  void initState() {
    super.initState();
    _loadStartTime = DateTime.now();
    _loadControllers();
  }

  Future<void> _loadControllers() async {
    // بارگذاری تمام کنترلرها
    final localeController = await LocaleController.load();
    final calendarController = await CalendarController.load();
    final themeController = ThemeController();
    await themeController.load();
    final authStore = AuthStore();
    // بایند کردن AuthStore قبل از load برای ارسال هدر Authorization در درخواست‌های اولیه
    ApiClient.bindAuthStore(authStore);
    await authStore.load();
    
    // تنظیم کنترلرها
    setState(() {
      _controller = localeController;
      _calendarController = calendarController;
      _themeController = themeController;
      _authStore = authStore;
    });
    
    // اضافه کردن listeners
    _controller!.addListener(() {
      ApiClient.setCurrentLocale(_controller!.locale);
      setState(() {});
    });
    
    _calendarController!.addListener(() {
      setState(() {});
    });
    
    _themeController!.addListener(() {
      setState(() {});
    });
    
    _authStore!.addListener(() {
      setState(() {});
    });
    
    // تنظیم API Client
    ApiClient.setCurrentLocale(_controller!.locale);
    ApiClient.bindCalendarController(_calendarController!);
    ApiClient.bindAuthStore(_authStore!);
    
    // اطمینان از حداقل 1 ثانیه نمایش splash screen
    final elapsed = DateTime.now().difference(_loadStartTime!);
    const minimumDuration = Duration(seconds: 1);
    if (elapsed < minimumDuration) {
      await Future.delayed(minimumDuration - elapsed);
    }
    
    // ذخیره URL فعلی قبل از اتمام loading
    if (_authStore != null) {
      try {
        final currentUrl = Uri.base.path;
        print('🔍 LOADING DEBUG: Current URL before finishing loading: $currentUrl');
        
        if (currentUrl.isNotEmpty && 
            currentUrl != '/' && 
            currentUrl != '/login' &&
            (currentUrl.startsWith('/user/profile/') || currentUrl.startsWith('/business/'))) {
          print('🔍 LOADING DEBUG: Saving current URL: $currentUrl');
          await _authStore!.saveLastUrl(currentUrl);
        }
      } catch (e) {
        print('🔍 LOADING DEBUG: Error saving current URL: $e');
      }
    }
    
    // اتمام loading
    if (mounted) {
      print('🔍 LOADING DEBUG: Finishing loading, setting _isLoading to false');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Root of application with GoRouter
  @override
  Widget build(BuildContext context) {
    print('🔍 BUILD DEBUG: Building app, _isLoading: $_isLoading');
    print('🔍 BUILD DEBUG: Controllers - locale: ${_controller != null}, calendar: ${_calendarController != null}, theme: ${_themeController != null}, auth: ${_authStore != null}');
    
    // اگر هنوز loading است، splash screen نمایش بده
    if (_isLoading || 
        _controller == null || 
        _calendarController == null || 
        _themeController == null || 
        _authStore == null) {
      print('🔍 BUILD DEBUG: Still loading, showing splash screen');
      final loadingRouter = GoRouter(
        redirect: (context, state) {
          // در حین loading، هیچ redirect نکن - URL را حفظ کن
          return null;
        },
        routes: <RouteBase>[
          // برای تمام مسیرها splash screen نمایش بده
          GoRoute(
            path: '/:path(.*)',
            builder: (context, state) {
              // تشخیص نوع loading بر اساس controller های موجود
              String loadingMessage = 'Initializing...';
              if (_controller == null) {
                loadingMessage = 'Loading language settings...';
              } else if (_calendarController == null) {
                loadingMessage = 'Loading calendar settings...';
              } else if (_themeController == null) {
                loadingMessage = 'Loading theme settings...';
              } else if (_authStore == null) {
                loadingMessage = 'Loading authentication...';
              }
              
              // اگر controller موجود است، از locale آن استفاده کن
              if (_controller != null) {
                final isFa = _controller!.locale.languageCode == 'fa';
                if (isFa) {
                  if (_calendarController == null) {
                    loadingMessage = 'loadingCalendarSettings';
                  } else if (_themeController == null) {
                    loadingMessage = 'loadingThemeSettings';
                  } else if (_authStore == null) {
                    loadingMessage = 'loadingAuthentication';
                  } else {
                    loadingMessage = 'initializing';
                  }
                }
              }
              
              return Builder(
                builder: (context) {
                  final t = AppLocalizations.of(context);
                  String localizedMessage = loadingMessage;
                  
                  // تبدیل کلیدهای ترجمه به متن
                  switch (loadingMessage) {
                    case 'loadingLanguageSettings':
                      localizedMessage = t.loadingLanguageSettings;
                      break;
                    case 'loadingCalendarSettings':
                      localizedMessage = t.loadingCalendarSettings;
                      break;
                    case 'loadingThemeSettings':
                      localizedMessage = t.loadingThemeSettings;
                      break;
                    case 'loadingAuthentication':
                      localizedMessage = t.loadingAuthentication;
                      break;
                    case 'initializing':
                      localizedMessage = t.initializing;
                      break;
                    default:
                      localizedMessage = loadingMessage;
                  }
                  
                  return SimpleSplashScreen(
                    message: localizedMessage,
                    showLogo: true,
                    displayDuration: const Duration(seconds: 1),
                    locale: _controller?.locale,
                    authStore: _authStore,
                    onComplete: () {
                      // این callback زمانی فراخوانی می‌شود که splash screen تمام شود
                      // اما ما از splash controller استفاده می‌کنیم
                      print('🔍 SPLASH DEBUG: Splash screen completed');
                    },
                  );
                },
              );
            },
          ),
        ],
      );

      return MaterialApp.router(
        title: 'Hesabix',
        routerConfig: loadingRouter,
        locale: _controller?.locale ?? const Locale('fa'),
        supportedLocales: const [Locale('en'), Locale('fa')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
      );
    }

    final controller = _controller!;
    final themeController = _themeController!;

    print('🔍 BUILD DEBUG: All controllers loaded, creating main router');
    // حفظ URL فعلی مرورگر هنگام سوئیچ از لودینگ به روتر اصلی
    final currentInitialLocation = () {
      final base = Uri.base;
      final path = base.path.isNotEmpty ? base.path : '/';
      final query = base.hasQuery ? '?${base.query}' : '';
      final fragment = base.fragment.isNotEmpty ? '#${base.fragment}' : '';
      return '$path$query$fragment';
    }();

    final router = GoRouter(
      initialLocation: currentInitialLocation,
      redirect: (context, state) async {
        final currentPath = state.uri.path;
        final fullUri = state.uri.toString();
        print('🔍 REDIRECT DEBUG: Current path: $currentPath');
        print('🔍 REDIRECT DEBUG: Full URI: $fullUri');
        
        // اگر authStore هنوز load نشده، منتظر بمان
        if (_authStore == null) {
          print('🔍 REDIRECT DEBUG: AuthStore is null, staying on current path');
          return null;
        }
        
        final hasKey = _authStore!.apiKey != null && _authStore!.apiKey!.isNotEmpty;
        print('🔍 REDIRECT DEBUG: Has API key: $hasKey');
        
        // اگر API key ندارد
        if (!hasKey) {
          print('🔍 REDIRECT DEBUG: No API key');
          // اگر در login نیست، به login برود
          if (currentPath != '/login') {
            print('🔍 REDIRECT DEBUG: Redirecting to login from $currentPath');
            return '/login';
          }
          // اگر در login است، بماند
          print('🔍 REDIRECT DEBUG: Already on login, staying');
          return null;
        }
        
        // اگر API key دارد
        print('🔍 REDIRECT DEBUG: Has API key, checking current path');
        
        // اگر در login است، به dashboard برود
        if (currentPath == '/login') {
          print('🔍 REDIRECT DEBUG: On login page, redirecting to dashboard');
          return '/user/profile/dashboard';
        }
        
        // اگر در root است، آخرین URL را بررسی کن
        if (currentPath == '/') {
          print('🔍 REDIRECT DEBUG: On root path, checking last URL');
          // اگر آخرین URL موجود است و معتبر است، به آن برود
          final lastUrl = await _authStore!.getLastUrl();
          print('🔍 REDIRECT DEBUG: Last URL: $lastUrl');
          
          if (lastUrl != null && 
              lastUrl.isNotEmpty && 
              lastUrl != '/' && 
              lastUrl != '/login' &&
              (lastUrl.startsWith('/user/profile/') || lastUrl.startsWith('/business/'))) {
            print('🔍 REDIRECT DEBUG: Redirecting to last URL: $lastUrl');
            return lastUrl;
          }
          // وگرنه به dashboard برود (فقط اگر در root باشیم)
          print('🔍 REDIRECT DEBUG: No valid last URL, redirecting to dashboard');
          return '/user/profile/dashboard';
        }
        
        // برای سایر صفحات (شامل صفحات profile و business)، redirect نکن (بماند)
        // این مهم است: اگر کاربر در صفحات profile یا business است، بماند
        print('🔍 REDIRECT DEBUG: On other page ($currentPath), staying on current path');
        // ذخیره مسیر فعلی به عنوان آخرین URL معتبر
        if (currentPath.isNotEmpty &&
            currentPath != '/' &&
            currentPath != '/login' &&
            (currentPath.startsWith('/user/profile/') || currentPath.startsWith('/business/'))) {
          try {
            await _authStore!.saveLastUrl(currentPath);
            print('🔍 REDIRECT DEBUG: Saved last URL: $currentPath');
          } catch (e) {
            // صرفاً لاگ برای خطای غیر بحرانی ذخیره آدرس
            print('🔍 REDIRECT DEBUG: Error saving last URL: $e');
          }
        }
        return null;
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => LoginPage(
            localeController: controller,
            calendarController: _calendarController!,
            themeController: themeController,
            authStore: _authStore!,
          ),
        ),
        GoRoute(
          path: '/wallet/payment-result',
          name: 'wallet_payment_result',
          builder: (context, state) => WalletPaymentResultPage(authStore: _authStore!),
        ),
        ShellRoute(
          builder: (context, state, child) => ProfileShell(
            authStore: _authStore!,
            localeController: controller,
            calendarController: _calendarController!,
            themeController: themeController,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/user/profile/dashboard',
              name: 'profile_dashboard',
              builder: (context, state) => const ProfileDashboardPage(),
            ),
            GoRoute(
              path: '/user/profile/announcements',
              name: 'profile_announcements',
              builder: (context, state) => const AnnouncementsPage(),
            ),
            GoRoute(
              path: '/user/profile/new-business',
              name: 'profile_new_business',
              builder: (context, state) => NewBusinessPage(calendarController: _calendarController!),
            ),
            GoRoute(
              path: '/user/profile/businesses',
              name: 'profile_businesses',
              builder: (context, state) => const BusinessesPage(),
            ),
            GoRoute(
              path: '/user/profile/support',
              name: 'profile_support',
              builder: (context, state) => SupportPage(calendarController: _calendarController),
            ),
            GoRoute(
              path: '/user/profile/marketing',
              name: 'profile_marketing',
              builder: (context, state) => MarketingPage(calendarController: _calendarController!),
            ),
            GoRoute(
              path: '/user/profile/change-password',
              name: 'profile_change_password',
              builder: (context, state) => const ChangePasswordPage(),
            ),
            GoRoute(
              path: '/user/profile/operator',
              name: 'profile_operator',
              builder: (context, state) {
                // بررسی دسترسی اپراتور پشتیبانی
                if (_authStore == null) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                
                if (!_authStore!.canAccessSupportOperator) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                return OperatorTicketsPage(calendarController: _calendarController);
              },
            ),
            GoRoute(
              path: '/user/profile/system-settings',
              name: 'profile_system_settings',
              builder: (context, state) {
                // بررسی دسترسی تنظیمات سیستم (SuperAdmin یا مجوز system_settings)
                if (_authStore == null) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                if (!allowed) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                return const SystemSettingsPage();
              },
              routes: [
                GoRoute(
                  path: 'wallet',
                  name: 'system_settings_wallet',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const WalletSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'payment-gateways',
                  name: 'system_settings_payment_gateways',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const PaymentGatewaysPage();
                  },
                ),
                GoRoute(
                  path: 'storage',
                  name: 'system_settings_storage',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AdminStorageManagementPage();
                  },
                ),
                GoRoute(
                  path: 'configuration',
                  name: 'system_settings_configuration',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemConfigurationPage();
                  },
                ),
                GoRoute(
                  path: 'users',
                  name: 'system_settings_users',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const UserManagementPage();
                  },
                ),
                GoRoute(
                  path: 'logs',
                  name: 'system_settings_logs',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemLogsPage();
                  },
                ),
                GoRoute(
                  path: 'email',
                  name: 'system_settings_email',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const EmailSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'announcements',
                  name: 'system_settings_announcements',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AnnouncementsAdminPage();
                  },
                ),
                GoRoute(
                  path: 'notifications',
                  name: 'system_settings_notifications',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const NotificationsSettingsPage();
                  },
                ),
                GoRoute(
                  path: 'notification-templates',
                  name: 'system_settings_notification_templates',
                  builder: (context, state) {
                    if (_authStore == null) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    final allowed = _authStore!.isSuperAdmin || _authStore!.hasAppPermission('system_settings');
                    if (!allowed) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const NotificationTemplatesAdminPage();
                  },
                ),
              ],
            ),
          ],
        ),
        ShellRoute(
          builder: (context, state, child) {
            final businessId = int.parse(state.pathParameters['business_id']!);
            return BusinessShell(
              businessId: businessId,
              authStore: _authStore!,
              localeController: controller,
              calendarController: _calendarController!,
              themeController: themeController,
              child: child,
            );
          },
          routes: [
            GoRoute(
              path: '/business/:business_id/dashboard',
              name: 'business_dashboard',
              pageBuilder: (context, state) => NoTransitionPage(
                child: BusinessDashboardPage(
                  businessId: int.parse(state.pathParameters['business_id']!),
                  authStore: _authStore!,
                  calendarController: _calendarController!,
                ),
              ),
            ),
            GoRoute(
              path: '/business/:business_id/users-permissions',
              name: 'business_users_permissions',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: UsersPermissionsPage(
                    businessId: businessId.toString(),
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/opening-balance',
              name: 'business_opening_balance',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: OpeningBalancePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/chart-of-accounts',
              name: 'business_chart_of_accounts',
              pageBuilder: (context, state) => NoTransitionPage(
                child: AccountsPage(
                  businessId: int.parse(state.pathParameters['business_id']!),
                  authStore: _authStore!,
                ),
              ),
            ),
            GoRoute(
              path: '/business/:business_id/accounts',
              name: 'business_accounts',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: BankAccountsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/petty-cash',
              name: 'business_petty_cash',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PettyCashPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/cash-box',
              name: 'business_cash_box',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CashRegistersPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/wallet',
              name: 'business_wallet',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WalletPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/user/profile/system-settings/wallet',
              name: 'system_wallet_settings',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: WalletSettingsPage(),
              ),
            ),
            GoRoute(
              path: '/business/:business_id/invoice',
              name: 'business_invoice',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InvoicesListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/invoice/new',
              name: 'business_new_invoice',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: NewInvoicePage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/invoice/:invoice_id/edit',
              name: 'business_edit_invoice',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final invoiceId = int.parse(state.pathParameters['invoice_id']!);
                return NoTransitionPage(
                  child: EditInvoicePage(
                    businessId: businessId,
                    invoiceId: invoiceId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports',
              name: 'business_reports',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ReportsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/reports/kardex',
              name: 'business_reports_kardex',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // Parse person_id(s) from query
                final qp = state.uri.queryParameters;
                final qpAll = state.uri.queryParametersAll;
                final Set<int> initialPersonIds = <int>{};
                final single = int.tryParse(qp['person_id'] ?? '');
                if (single != null) initialPersonIds.add(single);
                final multi = (qpAll['person_id'] ?? const <String>[]) 
                    .map((e) => int.tryParse(e))
                    .whereType<int>();
                initialPersonIds.addAll(multi);
                // Also parse from extra
                try {
                  if (state.extra is Map) {
                    final extra = state.extra as Map;
                    final list = extra['person_ids'];
                    if (list is List) {
                      for (final v in list) {
                        if (v is int) initialPersonIds.add(v);
                        else {
                          final p = int.tryParse('$v');
                          if (p != null) initialPersonIds.add(p);
                        }
                      }
                    }
                  }
                } catch (_) {}
                return NoTransitionPage(
                  child: KardexPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    initialPersonIds: initialPersonIds.toList(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings',
              name: 'business_settings',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // گارد دسترسی: فقط کاربرانی که دسترسی join دارند
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: SettingsPage(
                    businessId: businessId,
                    localeController: controller,
                    calendarController: _calendarController!,
                    themeController: themeController,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/backup',
              name: 'business_settings_backup',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(child: PermissionGuard.buildAccessDeniedPage());
                }
                return NoTransitionPage(child: BusinessBackupPage(businessId: businessId));
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/restore',
              name: 'business_settings_restore',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(child: PermissionGuard.buildAccessDeniedPage());
                }
                return NoTransitionPage(child: BusinessRestorePage(businessId: businessId));
              },
            ),
            GoRoute(
              path: '/business/:business_id/settings/business',
              name: 'business_settings_business',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                if (!_authStore!.hasBusinessPermission('settings', 'join')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: BusinessInfoSettingsPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/product-attributes',
              name: 'business_product_attributes',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ProductAttributesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/products',
              name: 'business_products',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ProductsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/price-lists',
              name: 'business_price_lists',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PriceListsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/price-lists/:price_list_id/items',
              name: 'business_price_list_items',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final priceListId = int.parse(state.pathParameters['price_list_id']!);
                return NoTransitionPage(
                  child: PriceListItemsPage(
                    businessId: businessId,
                    priceListId: priceListId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/persons',
              name: 'business_persons',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: PersonsPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            // Receipts & Payments: list with data table
            GoRoute(
              path: '/business/:business_id/receipts-payments',
              name: 'business_receipts_payments',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ReceiptsPaymentsListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/expense-income',
              name: 'business_expense_income',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ExpenseIncomeListPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/transfers',
              name: 'business_transfers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: TransfersPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/warehouses',
              name: 'business_warehouses',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: WarehousesPage(
                    businessId: businessId,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/inventory-transfers',
              name: 'business_inventory_transfers',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: InventoryTransfersPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/documents',
              name: 'business_documents',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: DocumentsPage(
                    businessId: businessId,
                    calendarController: _calendarController!,
                    authStore: _authStore!,
                    apiClient: ApiClient(),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/report-templates',
              name: 'business_report_templates',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ReportTemplatesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/plugin-marketplace',
              name: 'business_plugin_marketplace',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                // گارد دسترسی مشاهده بازار
                if (!_authStore!.hasBusinessPermission('marketplace', 'view')) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: PluginMarketplacePage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/plugin-marketplace/invoices',
              name: 'business_plugin_marketplace_invoices',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final allowed = _authStore!.hasBusinessPermission('marketplace', 'invoices') ||
                    _authStore!.hasBusinessPermission('marketplace', 'view');
                if (!allowed) {
                  return NoTransitionPage(
                    child: PermissionGuard.buildAccessDeniedPage(),
                  );
                }
                return NoTransitionPage(
                  child: MarketplaceInvoicesPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/checks',
              name: 'business_checks',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: ChecksPage(
                    businessId: businessId,
                    authStore: _authStore!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/checks/new',
              name: 'business_new_check',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return NoTransitionPage(
                  child: CheckFormPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/business/:business_id/checks/:check_id/edit',
              name: 'business_edit_check',
              pageBuilder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                final checkId = int.tryParse(state.pathParameters['check_id'] ?? '0');
                return NoTransitionPage(
                  child: CheckFormPage(
                    businessId: businessId,
                    authStore: _authStore!,
                    checkId: checkId,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            // TODO: Add other business routes (sales, accounting, etc.)
          ],
        ),
        // صفحه 404 برای مسیرهای نامعتبر
        GoRoute(
          path: '/404',
          name: 'error_404',
          builder: (context, state) => const Error404Page(),
        ),
      ],
      errorBuilder: (context, state) => const Error404Page(),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([controller, themeController]),
      builder: (context, _) {
        return UrlTracker(
          authStore: _authStore!,
          child: MaterialApp.router(
            title: 'Hesabix',
            theme: AppTheme.build(
              isDark: false,
              locale: controller.locale,
              seed: themeController.seedColor,
            ),
            darkTheme: AppTheme.build(
              isDark: true,
              locale: controller.locale,
              seed: themeController.seedColor,
            ),
            themeMode: themeController.mode,
            routerConfig: router,
            locale: controller.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
          ),
        );
      },
    );
  }
}
