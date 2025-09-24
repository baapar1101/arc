import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import 'pages/system_settings_page.dart';
import 'pages/admin/storage_management_page.dart';
import 'pages/admin/system_configuration_page.dart';
import 'pages/admin/user_management_page.dart';
import 'pages/admin/system_logs_page.dart';
import 'pages/admin/email_settings_page.dart';
import 'pages/business/business_shell.dart';
import 'pages/business/dashboard/business_dashboard_page.dart';
import 'pages/business/users_permissions_page.dart';
import 'core/locale_controller.dart';
import 'core/calendar_controller.dart';
import 'core/api_client.dart';
import 'theme/theme_controller.dart';
import 'theme/app_theme.dart';
import 'core/auth_store.dart';
import 'core/permission_guard.dart';
import 'widgets/simple_splash_screen.dart';
import 'widgets/url_tracker.dart';

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
                  if (_controller == null) {
                    loadingMessage = 'loadingLanguageSettings';
                  } else if (_calendarController == null) {
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
        locale: const Locale('en'),
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
    final router = GoRouter(
      initialLocation: '/',
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
              path: '/user/profile/new-business',
              name: 'profile_new_business',
              builder: (context, state) => const NewBusinessPage(),
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
                // بررسی دسترسی SuperAdmin
                if (_authStore == null) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                
                if (!_authStore!.isSuperAdmin) {
                  return PermissionGuard.buildAccessDeniedPage();
                }
                return const SystemSettingsPage();
              },
              routes: [
                GoRoute(
                  path: 'storage',
                  name: 'system_settings_storage',
                  builder: (context, state) {
                    if (_authStore == null || !_authStore!.isSuperAdmin) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const AdminStorageManagementPage();
                  },
                ),
                GoRoute(
                  path: 'configuration',
                  name: 'system_settings_configuration',
                  builder: (context, state) {
                    if (_authStore == null || !_authStore!.isSuperAdmin) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemConfigurationPage();
                  },
                ),
                GoRoute(
                  path: 'users',
                  name: 'system_settings_users',
                  builder: (context, state) {
                    if (_authStore == null || !_authStore!.isSuperAdmin) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const UserManagementPage();
                  },
                ),
                GoRoute(
                  path: 'logs',
                  name: 'system_settings_logs',
                  builder: (context, state) {
                    if (_authStore == null || !_authStore!.isSuperAdmin) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const SystemLogsPage();
                  },
                ),
                GoRoute(
                  path: 'email',
                  name: 'system_settings_email',
                  builder: (context, state) {
                    if (_authStore == null || !_authStore!.isSuperAdmin) {
                      return PermissionGuard.buildAccessDeniedPage();
                    }
                    return const EmailSettingsPage();
                  },
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/business/:business_id',
          name: 'business_shell',
          builder: (context, state) {
            final businessId = int.parse(state.pathParameters['business_id']!);
            return BusinessShell(
              businessId: businessId,
              authStore: _authStore!,
              localeController: controller,
              calendarController: _calendarController!,
              themeController: themeController,
              child: const SizedBox.shrink(), // Will be replaced by child routes
            );
          },
          routes: [
            GoRoute(
              path: 'dashboard',
              name: 'business_dashboard',
              builder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return BusinessShell(
                  businessId: businessId,
                  authStore: _authStore!,
                  localeController: controller,
                  calendarController: _calendarController!,
                  themeController: themeController,
                  child: BusinessDashboardPage(businessId: businessId),
                );
              },
            ),
            GoRoute(
              path: 'users-permissions',
              name: 'business_users_permissions',
              builder: (context, state) {
                final businessId = int.parse(state.pathParameters['business_id']!);
                return BusinessShell(
                  businessId: businessId,
                  authStore: _authStore!,
                  localeController: controller,
                  calendarController: _calendarController!,
                  themeController: themeController,
                  child: UsersPermissionsPage(
                    businessId: businessId.toString(),
                    authStore: _authStore!,
                    calendarController: _calendarController!,
                  ),
                );
              },
            ),
            // TODO: Add other business routes (sales, accounting, etc.)
          ],
        ),
      ],
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
