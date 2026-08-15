import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'business_nav.dart';
import 'business_route_paths.dart';
import 'mobile_launcher_nav.dart';
import 'mobile_launcher_prefs.dart';
import '../utils/responsive_helper.dart';

/// دکمهٔ داخل برنامه فقط جایی که سیستم‌عامل Back ثابت ندارد.
/// اندروید نیتیو Back/ژست دارد؛ وب و ویندوز و iOS دکمه را نشان می‌دهند.
bool shouldShowHesabixBackButton() {
  if (kIsWeb) return true;
  return defaultTargetPlatform != TargetPlatform.android;
}

/// والد منطقی مسیر نسبی پنل (بدون `/business/:id/tabN`).
///
/// `null` یعنی ریشه (داشبورد) — دکمه/ناوبری مقصد دیگری ندارد مگر لانچر.
String? logicalBusinessBackParent(String pathTail) {
  var tail = pathTail.split('?').first.trim();
  if (tail.startsWith('/')) tail = tail.substring(1);
  if (tail.endsWith('/')) tail = tail.substring(0, tail.length - 1);
  if (tail.isEmpty || tail == 'dashboard') return null;

  if (_level1RelativePaths.contains(tail)) return 'dashboard';

  String? bestPrefix;
  for (final l1 in _level1RelativePaths) {
    if (l1 == 'dashboard') continue;
    if (tail.startsWith('$l1/')) {
      if (bestPrefix == null || l1.length > bestPrefix.length) {
        bestPrefix = l1;
      }
    }
  }
  if (bestPrefix != null) return bestPrefix;

  final explicit = _explicitParentByTail[tail];
  if (explicit != null) return explicit;

  final slash = tail.lastIndexOf('/');
  if (slash > 0) return tail.substring(0, slash);

  return 'dashboard';
}

bool isBusinessDashboardRelative(String pathTail) {
  var tail = pathTail.split('?').first.trim();
  if (tail.startsWith('/')) tail = tail.substring(1);
  return tail.isEmpty || tail == 'dashboard';
}

/// بازگشت واحد پنل کسب‌وکار (و در صورت نبود پشته، والد منطقی).
///
/// تب را نمی‌بندد. تاریخچهٔ مرورگر را صدا نمی‌زند.
Future<void> hesabixNavigateBack(
  BuildContext context, {
  int? businessId,
  String? fallbackRelativePath,
}) async {
  if (!context.mounted) return;

  final interceptor = HesabixBackScope.interceptorOf(context);
  if (interceptor != null) {
    final allowDefault = await interceptor();
    if (!allowDefault || !context.mounted) return;
  }

  if (!context.mounted) return;

  final rootNav = Navigator.of(context, rootNavigator: true);
  if (rootNav.canPop()) {
    rootNav.pop();
    return;
  }

  final router = GoRouter.maybeOf(context);
  if (router != null && router.canPop()) {
    router.pop();
    return;
  }
  if (context.canPop()) {
    context.pop();
    return;
  }

  final bid = businessId ?? _businessIdFromContext(context);
  if (bid == null) {
    _navigateNonBusinessFallback(context);
    return;
  }

  final currentPath = _currentPath(context);
  final tail = BusinessRoutePaths.stripBusinessPrefixAndTab(currentPath, bid);
  final launcherHome = _launcherHome(context, bid);

  var relative = fallbackRelativePath?.trim();
  if (relative != null && relative.startsWith('/')) {
    relative = BusinessRoutePaths.stripBusinessPrefixAndTab(relative, bid);
  }
  relative ??= logicalBusinessBackParent(tail);

  final atRoot = relative == null || isBusinessDashboardRelative(tail);
  if (atRoot) {
    if (launcherHome != null && launcherHome.isNotEmpty) {
      context.go(launcherHome);
    }
    return;
  }

  // سطح ۱ (والد داشبورد) در لانچر موبایل → خانهٔ لانچر
  if (relative == 'dashboard' &&
      launcherHome != null &&
      launcherHome.isNotEmpty) {
    context.go(launcherHome);
    return;
  }

  if (relative == tail) return;
  context.go(context.businessPanelUrl(bid, relative));
}

void popBusinessOrLauncher(
  BuildContext context,
  int businessId, {
  String? fallbackPath,
}) {
  String? relative;
  if (fallbackPath != null && fallbackPath.isNotEmpty) {
    relative = fallbackPath.startsWith('/business/')
        ? BusinessRoutePaths.stripBusinessPrefixAndTab(fallbackPath, businessId)
        : fallbackPath;
  }
  hesabixNavigateBack(
    context,
    businessId: businessId,
    fallbackRelativePath: relative,
  );
}

Widget? hesabixBackAppBarLeading(
  BuildContext context, {
  int? businessId,
  String? fallbackRelativePath,
}) {
  if (!shouldShowHesabixBackButton()) return null;
  return HesabixBackButton(
    businessId: businessId,
    fallbackRelativePath: fallbackRelativePath,
  );
}

/// سازگاری با leadingهای قبلی؛ روی اندروید نیتیو `null` است تا جا نگیرد.
Widget? businessSubpageBackLeading(BuildContext context, int businessId) {
  return hesabixBackAppBarLeading(context, businessId: businessId);
}

class HesabixBackButton extends StatelessWidget {
  const HesabixBackButton({
    super.key,
    this.businessId,
    this.fallbackRelativePath,
    this.color,
    this.iconSize,
    this.onPressed,
  });

  final int? businessId;
  final String? fallbackRelativePath;
  final Color? color;
  final double? iconSize;

  /// اگر ست شود به‌جای منطق پیش‌فرض؛ برای موارد خاص. سیستم‌عامل همچنان [HesabixBackScope] را می‌زند.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!shouldShowHesabixBackButton()) return const SizedBox.shrink();
    return IconButton(
      icon: Icon(Icons.arrow_back, color: color, size: iconSize),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ??
          () {
            hesabixNavigateBack(
              context,
              businessId: businessId,
              fallbackRelativePath: fallbackRelativePath,
            );
          },
    );
  }
}

/// ثبت تأیید «تغییرات ذخیره نشده» و امثال آن. خروجی `true` یعنی ادامهٔ بازگشت پیش‌فرض.
class HesabixBackInterceptor extends StatefulWidget {
  const HesabixBackInterceptor({
    super.key,
    required this.onWillPop,
    required this.child,
  });

  final Future<bool> Function() onWillPop;
  final Widget child;

  @override
  State<HesabixBackInterceptor> createState() => _HesabixBackInterceptorState();
}

class _HesabixBackInterceptorState extends State<HesabixBackInterceptor> {
  HesabixBackScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = HesabixBackScope.maybeStateOf(context);
    if (!identical(_scope, next)) {
      _scope?.unregister(widget.onWillPop);
      _scope = next;
      _scope?.register(widget.onWillPop);
    }
  }

  @override
  void didUpdateWidget(covariant HesabixBackInterceptor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onWillPop, widget.onWillPop)) {
      _scope?.unregister(oldWidget.onWillPop);
      _scope?.register(widget.onWillPop);
    }
  }

  @override
  void dispose() {
    _scope?.unregister(widget.onWillPop);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// رهگیری Back سیستم‌عامل در پنل کسب‌وکار. تب را نمی‌بندد.
class HesabixBackScope extends StatefulWidget {
  const HesabixBackScope({
    super.key,
    required this.businessId,
    required this.child,
  });

  final int businessId;
  final Widget child;

  static HesabixBackScopeState? maybeStateOf(BuildContext context) {
    return context.findAncestorStateOfType<HesabixBackScopeState>();
  }

  static Future<bool> Function()? interceptorOf(BuildContext context) {
    final ancestor = maybeStateOf(context);
    if (ancestor != null) return ancestor._interceptor;
    final el = context;
    if (el is StatefulElement && el.state is HesabixBackScopeState) {
      return (el.state as HesabixBackScopeState)._interceptor;
    }
    return null;
  }

  @override
  State<HesabixBackScope> createState() => HesabixBackScopeState();
}

class HesabixBackScopeState extends State<HesabixBackScope> {
  final List<Future<bool> Function()> _interceptors = [];

  Future<bool> Function()? get _interceptor =>
      _interceptors.isEmpty ? null : _interceptors.last;

  void register(Future<bool> Function() fn) {
    _interceptors.add(fn);
  }

  void unregister(Future<bool> Function() fn) {
    _interceptors.remove(fn);
  }

  bool _allowSystemPop(BuildContext context) {
    final bid = widget.businessId;
    final path = _currentPath(context);
    final tail = BusinessRoutePaths.stripBusinessPrefixAndTab(path, bid);
    if (!isBusinessDashboardRelative(tail)) return false;
    return _launcherHome(context, bid) == null;
  }

  @override
  Widget build(BuildContext context) {
    final allowPop = _allowSystemPop(context);
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!context.mounted) return;
        await hesabixNavigateBack(context, businessId: widget.businessId);
      },
      child: widget.child,
    );
  }
}

String _currentPath(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router != null) return router.state.uri.path;
  try {
    return GoRouterState.of(context).uri.path;
  } catch (_) {
    return '';
  }
}

int? _businessIdFromContext(BuildContext context) {
  final path = _currentPath(context);
  final m = RegExp(r'^/business/(\d+)').firstMatch(path);
  if (m != null) return int.tryParse(m.group(1)!);
  try {
    final raw = GoRouterState.of(context).pathParameters['business_id'];
    return int.tryParse(raw ?? '');
  } catch (_) {
    return null;
  }
}

String? _launcherHome(BuildContext context, int businessId) {
  final fromInfo = MobileLauncherBackInfo.maybeHomeOf(context);
  if (fromInfo != null && fromInfo.isNotEmpty) return fromInfo;
  if (!MobileLauncherNav.shouldReturnToLauncher(context)) return null;
  if (!ResponsiveHelper.isMobile(context)) return null;
  return MobileLauncherPrefs.syncLauncherHomePathForBusiness(businessId);
}

void _navigateNonBusinessFallback(BuildContext context) {
  final path = _currentPath(context);
  if (path.startsWith('/user/profile/') &&
      path != '/user/profile/dashboard') {
    context.go('/user/profile/dashboard');
    return;
  }
}

/// مقصدهای منوی کناری / هاب‌های سطح ۱ → بازگشت به داشبورد (یا لانچر).
const Set<String> _level1RelativePaths = {
  'dashboard',
  'persons',
  'products',
  'product-attributes',
  'catalog-spec-fields',
  'barcode-labels',
  'accounts',
  'petty-cash',
  'cash-box',
  'wallet',
  'loan-facilities',
  'quick-sales',
  'invoice',
  'receipts-payments',
  'expense-income',
  'transfers',
  'checks',
  'documents',
  'chart-of-accounts',
  'opening-balance',
  'year-end-closing',
  'currency-revaluation',
  'reports',
  'basalam',
  'woocommerce',
  'plugin-marketplace',
  'hscript',
  'warehouses',
  'warehouse-docs',
  'stock-count',
  'goods-expense-income',
  'storage-files',
  'tax-workspace',
  'ai/chat',
  'ai/subscription',
  'ai/usage',
  'ai/skills/marketplace',
  'ai/skills/publisher',
  'workflows',
  'crm',
  'crm/dashboard',
  'crm/tasks',
  'crm/web-chat',
  'crm/notes-calendar',
  'crm/leads',
  'crm/deals',
  'crm/activities',
  'crm/customer-360',
  'crm/reports',
  'crm/process-definitions',
  'crm/sequences',
  'warranty',
  'repair-shop',
  'customer-club',
  'payroll',
  'telephony',
  'distribution',
  'zohal/inquiries',
  'settings',
  'report-templates',
  'price-lists',
};

/// صفحاتی که مسیرشان زیر هاب نیست ولی از هاب تنظیمات (یا ماژول) باز می‌شوند.
const Map<String, String> _explicitParentByTail = {
  'users-permissions': 'settings',
  'projects': 'settings',
  'document-monetization': 'settings',
  'notification-templates': 'settings',
  'repair-shop-settings': 'repair-shop',
  'repair-shop-technicians': 'repair-shop',
  'installments-report': 'reports',
};
