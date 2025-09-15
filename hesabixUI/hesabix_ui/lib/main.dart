import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/profile/profile_shell.dart';
import 'pages/profile/profile_dashboard_page.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'core/locale_controller.dart';
import 'core/api_client.dart';
import 'theme/theme_controller.dart';
import 'theme/app_theme.dart';

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
  }

  // Root of application with GoRouter
  @override
  Widget build(BuildContext context) {
    if (_controller == null || _themeController == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final controller = _controller!;
    final themeController = _themeController!;

    final router = GoRouter(
      initialLocation: '/login',
      routes: <RouteBase>[
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => LoginPage(
            localeController: controller,
            themeController: themeController,
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
          builder: (context, state, child) => ProfileShell(child: child),
          routes: [
            GoRoute(
              path: '/user/profile/dashboard',
              name: 'profile_dashboard',
              builder: (context, state) => const ProfileDashboardPage(),
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
