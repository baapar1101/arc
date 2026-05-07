import 'package:flutter/material.dart';
import '../core/auth_store.dart';

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
          final currentUrl = Uri.base.path;
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
          // این ممکن است در splash screen یا loading state اتفاق بیفتد
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
