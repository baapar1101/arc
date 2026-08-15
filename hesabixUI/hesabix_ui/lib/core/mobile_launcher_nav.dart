import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth_store.dart';
import 'mobile_launcher_prefs.dart';
import '../utils/responsive_helper.dart';

/// ناوبری برگشت به خانهٔ لانچر موبایل؛ فقط وقتی resume فعال و عرض «موبایل» است.
/// روی وب عریض / ویندوز دسکتاپ دخالت نمی‌کند (`ResponsiveHelper.isMobile == false`).
class MobileLauncherNav {
  MobileLauncherNav._();

  /// اگر resume لانچر برای این کسب‌وکار فعال باشد مسیر خانه را برمی‌گرداند.
  static Future<String?> launcherHomeIfActive({
    required int? userId,
    required int businessId,
  }) async {
    final resumeId = await MobileLauncherPrefs.resumeBusinessId(userId);
    if (resumeId == null || resumeId != businessId) return null;
    return MobileLauncherPrefs.launcherHomePath(businessId);
  }

  /// مسیر همزمان از کش حافظه (بعد از set/clear/resume یا bootstrap).
  static String? syncLauncherHomeIfActive({
    required int? userId,
    required int businessId,
  }) {
    return MobileLauncherPrefs.syncLauncherHomePath(
      userId: userId,
      businessId: businessId,
    );
  }

  /// آیا در این context باید Back به لانچر برگردد؟
  static bool shouldReturnToLauncher(BuildContext context) {
    return ResponsiveHelper.isMobile(context);
  }

  /// pop در صورت وجود پشته؛ وگرنه در حالت لانچر موبایل به خانهٔ لانچر.
  /// خروجی: true اگر ناوبری انجام شد.
  static Future<bool> popOrReturnToLauncher(
    BuildContext context, {
    required int? userId,
    required int businessId,
    String? fallbackPath,
  }) async {
    if (!context.mounted) return false;
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
      return true;
    }
    if (context.canPop()) {
      context.pop();
      return true;
    }
    if (!shouldReturnToLauncher(context)) {
      if (fallbackPath != null && fallbackPath.isNotEmpty) {
        context.go(fallbackPath);
        return true;
      }
      return false;
    }
    final home = await launcherHomeIfActive(
      userId: userId,
      businessId: businessId,
    );
    if (home == null || !context.mounted) {
      if (fallbackPath != null && fallbackPath.isNotEmpty && context.mounted) {
        context.go(fallbackPath);
        return true;
      }
      return false;
    }
    context.go(home);
    return true;
  }

  static void goLauncherHome(BuildContext context, int businessId) {
    context.go(MobileLauncherPrefs.launcherHomePath(businessId));
  }
}

/// [InheritedWidget] برای خواندن مسیر خانهٔ لانچر از داخل [BusinessShell] و زیرصفحات.
class MobileLauncherBackInfo extends InheritedWidget {
  const MobileLauncherBackInfo({
    super.key,
    required this.launcherHomePath,
    required super.child,
  });

  /// غیرnull فقط وقتی resume برای همین کسب‌وکار فعال است و عرض موبایل است.
  final String? launcherHomePath;

  static String? maybeHomeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MobileLauncherBackInfo>()
        ?.launcherHomePath;
  }

  @override
  bool updateShouldNotify(MobileLauncherBackInfo oldWidget) =>
      oldWidget.launcherHomePath != launcherHomePath;
}

/// رهگیری سیستم Back / gesture در پنل کسب‌وکار وقتی از لانچر آمده‌ایم.
class MobileLauncherBackScope extends StatefulWidget {
  const MobileLauncherBackScope({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.child,
  });

  final int businessId;
  final AuthStore authStore;
  final Widget child;

  @override
  State<MobileLauncherBackScope> createState() => _MobileLauncherBackScopeState();
}

class _MobileLauncherBackScopeState extends State<MobileLauncherBackScope> {
  String? _storedHomePath;

  @override
  void initState() {
    super.initState();
    MobileLauncherPrefs.revision.addListener(_onPrefsRevision);
    widget.authStore.addListener(_onAuthChanged);
    _reload();
  }

  @override
  void didUpdateWidget(covariant MobileLauncherBackScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.authStore != widget.authStore) {
      if (oldWidget.authStore != widget.authStore) {
        oldWidget.authStore.removeListener(_onAuthChanged);
        widget.authStore.addListener(_onAuthChanged);
      }
      _reload();
    }
  }

  @override
  void dispose() {
    MobileLauncherPrefs.revision.removeListener(_onPrefsRevision);
    widget.authStore.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onPrefsRevision() => _reload();

  void _onAuthChanged() => _reload();

  Future<void> _reload() async {
    final path = await MobileLauncherNav.launcherHomeIfActive(
      userId: widget.authStore.currentUserId,
      businessId: widget.businessId,
    );
    if (!mounted) return;
    if (_storedHomePath != path) {
      setState(() => _storedHomePath = path);
    }
  }

  String? _effectiveHome(BuildContext context) {
    if (!MobileLauncherNav.shouldReturnToLauncher(context)) return null;
    return _storedHomePath ??
        MobileLauncherNav.syncLauncherHomeIfActive(
          userId: widget.authStore.currentUserId,
          businessId: widget.businessId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final home = _effectiveHome(context);
    return MobileLauncherBackInfo(
      launcherHomePath: home,
      child: widget.child,
    );
  }
}
