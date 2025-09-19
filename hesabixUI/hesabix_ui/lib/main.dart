import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'pages/login_page.dart';
import 'pages/profile/profile_shell.dart';
import 'pages/profile/profile_dashboard_page.dart';
import 'pages/profile/new_business_page.dart';
import 'pages/profile/businesses_page.dart';
import 'pages/profile/support_page.dart';
import 'pages/profile/change_password_page.dart';
import 'pages/profile/marketing_page.dart';
import 'pages/system_settings_page.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'core/locale_controller.dart';
import 'core/calendar_controller.dart';
import 'core/api_client.dart';
import 'theme/theme_controller.dart';
import 'theme/app_theme.dart';
import 'core/auth_store.dart';
import 'core/permission_guard.dart';

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

  @override
  void initState() {
    super.initState();
    LocaleController.load().then((c) {
      setState(() {
        _controller = c
          ..addListener(() {
            // Update ApiClient language header on change
            ApiClient.setCurrentLocale(c.locale);
            setState(() {});
          });
        ApiClient.setCurrentLocale(c.locale);
      });
    });

    CalendarController.load().then((cc) {
      setState(() {
        _calendarController = cc
          ..addListener(() {
            setState(() {});
          });
        ApiClient.bindCalendarController(cc);
      });
    });

    final tc = ThemeController();
    tc.load().then((_) {
      setState(() {
        _themeController = tc
          ..addListener(() {
            setState(() {});
          });
      });
    });

    final store = AuthStore();
    store.load().then((_) {
      setState(() {
        _authStore = store
          ..addListener(() {
            setState(() {});
          });
        ApiClient.bindAuthStore(store);
      });
    });
  }

  // Root of application with GoRouter
  @override
  Widget build(BuildContext context) {
    // اگر هنوز loading است، یک router ساده با loading page بساز
    if (_controller == null || _calendarController == null || _themeController == null || _authStore == null) {
      final loadingRouter = GoRouter(
        redirect: (context, state) {
          // در حین loading، هیچ redirect نکن - URL را حفظ کن
          return null;
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          // برای سایر مسیرها هم loading page نمایش بده
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/user/profile/dashboard',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/user/profile/marketing',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/user/profile/new-business',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/user/profile/businesses',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/user/profile/support',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/user/profile/change-password',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/user/profile/system-settings',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
          // Catch-all route برای هر URL دیگر
          GoRoute(
            path: '/:path(.*)',
            builder: (context, state) => const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading...'),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

      return MaterialApp.router(
        title: 'Hesabix',
        routerConfig: loadingRouter,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('fa')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
      );
    }

    final controller = _controller!;
    final themeController = _themeController!;

    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        final currentPath = state.uri.path;
        
        // اگر authStore هنوز load نشده، منتظر بمان
        if (_authStore == null) {
          return null;
        }
        
        final hasKey = _authStore!.apiKey != null && _authStore!.apiKey!.isNotEmpty;
        
        // اگر API key ندارد
        if (!hasKey) {
          // اگر در login نیست، به login برود
          if (currentPath != '/login') {
            return '/login';
          }
          // اگر در login است، بماند
          return null;
        }
        
        // اگر API key دارد
        // اگر در login است، به dashboard برود
        if (currentPath == '/login') {
          return '/user/profile/dashboard';
        }
        
        // اگر در root است، به dashboard برود
        if (currentPath == '/') {
          return '/user/profile/dashboard';
        }
        
        // برای سایر صفحات (شامل صفحات profile)، redirect نکن (بماند)
        // این مهم است: اگر کاربر در صفحات profile است، بماند
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
              builder: (context, state) => const SupportPage(),
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
            ),
          ],
        ),
      ],
    );

    return AnimatedBuilder(
      animation: Listenable.merge([controller, themeController]),
      builder: (context, _) {
        return MaterialApp.router(
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
        );
      },
    );
  }
}
