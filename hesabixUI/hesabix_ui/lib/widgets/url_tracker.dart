import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/auth_store.dart';
import '../main.dart' show navigatorKey;

class UrlTracker extends StatefulWidget {
  final Widget child;
  final AuthStore authStore;

  const UrlTracker({
    super.key,
    required this.child,
    required this.authStore,
  });

  @override
  State<UrlTracker> createState() => _UrlTrackerState();
}

class _UrlTrackerState extends State<UrlTracker> {
  String? _lastTrackedUrl;

  @override
  void initState() {
    super.initState();
    _trackCurrentUrl();
  }

  void _trackCurrentUrl() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final ctx = navigatorKey.currentContext;
          if (ctx == null) return;
          final currentUrl = GoRouterState.of(ctx).uri.path;
          if (currentUrl != _lastTrackedUrl &&
              currentUrl.isNotEmpty &&
              currentUrl != '/' &&
              currentUrl != '/login' &&
              (currentUrl.startsWith('/user/profile/') ||
                  currentUrl.startsWith('/business/') ||
                  currentUrl.startsWith('/mobile-launcher/'))) {
            _lastTrackedUrl = currentUrl;
            widget.authStore.saveLastUrl(currentUrl);
          }
        } catch (e) {
          // اگر GoRouterState در دسترس نیست، URL را track نکن
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // هر بار که widget rebuild می‌شود، URL فعلی را track کن
    _trackCurrentUrl();
    return widget.child;
  }
}
