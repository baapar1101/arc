import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/profile/profile_shell.dart';
import 'pages/profile/profile_dashboard_page.dart';
import 'pages/profile/new_business_page.dart';
import 'pages/profile/businesses_page.dart';
import 'pages/profile/support_page.dart';
import 'pages/profile/change_password_page.dart';
import 'pages/profile/marketing_page.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'core/locale_controller.dart';
import 'core/api_client.dart';
import 'theme/theme_controller.dart';
import 'theme/app_theme.dart';
import 'core/auth_store.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  LocaleController? _controller;
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
    if (_controller == null || _themeController == null || _authStore == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final controller = _controller!;
    final themeController = _themeController!;

    final router = GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final hasKey = _authStore!.apiKey != null && _authStore!.apiKey!.isNotEmpty;
        final loggingIn = state.matchedLocation == '/login';
        if (!hasKey && !loggingIn) return '/login';
        if (hasKey && loggingIn) return '/user/profile/dashboard';
        return null;
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => LoginPage(
            localeController: controller,
            themeController: themeController,
            authStore: _authStore!,
          ),
        ),
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => HomePage(
            localeController: controller,
            themeController: themeController,
          ),
        ),
        ShellRoute(
          builder: (context, state, child) => ProfileShell(child: child, authStore: _authStore!, localeController: controller, themeController: themeController),
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
              builder: (context, state) => const MarketingPage(),
            ),
            GoRoute(
              path: '/user/profile/change-password',
              name: 'profile_change_password',
              builder: (context, state) => const ChangePasswordPage(),
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
