import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';

/// خانهٔ لانچر موبایل (شبکهٔ کاشی‌ها؛ زیرشاخهٔ `/mobile-launcher/:id/home`).
class MobileLauncherHomePage extends StatefulWidget {
  const MobileLauncherHomePage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  final int businessId;
  final AuthStore authStore;

  @override
  State<MobileLauncherHomePage> createState() => _MobileLauncherHomePageState();
}

class _MobileLauncherHomePageState extends State<MobileLauncherHomePage> {
  late Future<int> _bgArgb = MobileLauncherPrefs.backgroundColorArgb(
    widget.authStore.currentUserId,
  );
  late Future<int> _gridColumns =
      MobileLauncherPrefs.gridColumns(widget.authStore.currentUserId);
  late Future<int> _gridRows =
      MobileLauncherPrefs.gridRows(widget.authStore.currentUserId);
  late Future<String?> _businessName = _loadBusinessName();

  DateTime? _lastBackPressAt;
  bool _desktopRedirectScheduled = false;

  Future<String?> _loadBusinessName() async {
    try {
      final api = ApiClient();
      final service = BusinessDashboardService(api);
      final businesses = await service.getUserBusinesses();
      for (final b in businesses) {
        if (b.id == widget.businessId) return b.name;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _reloadBackground() {
    setState(() {
      _bgArgb = MobileLauncherPrefs.backgroundColorArgb(
        widget.authStore.currentUserId,
      );
    });
  }

  void _reloadGridLayout() {
    setState(() {
      _gridColumns = MobileLauncherPrefs.gridColumns(widget.authStore.currentUserId);
      _gridRows = MobileLauncherPrefs.gridRows(widget.authStore.currentUserId);
    });
  }

  void _reloadBusinessName() {
    setState(() {
      _businessName = _loadBusinessName();
    });
  }

  bool _isLight(Color c) => c.computeLuminance() > 0.55;

  void _applySystemOverlay(Color bg) {
    if (kIsWeb) return;
    final lightBg = _isLight(bg);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: lightBg ? Brightness.dark : Brightness.light,
        statusBarBrightness: lightBg ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: bg.withValues(alpha: 0.94),
        systemNavigationBarIconBrightness:
            lightBg ? Brightness.dark : Brightness.light,
      ),
    );
  }

  Future<void> _disableLauncherHome(AppLocalizations t) async {
    await MobileLauncherPrefs.clearResumeLauncher(widget.authStore.currentUserId);
    if (!mounted) return;
    SnackBarHelper.show(context, message: t.mobileLauncherDisableHomeLauncherDone);
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle());
    }
    super.dispose();
  }

  Future<void> _onLauncherWillPop(AppLocalizations t) async {
    if (kIsWeb) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final now = DateTime.now();
    const windowMs = 2200;
    if (_lastBackPressAt != null &&
        now.difference(_lastBackPressAt!).inMilliseconds < windowMs) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPressAt = now;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(t.mobileLauncherExitAppHint),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!ResponsiveHelper.isMobile(context)) {
      if (!_desktopRedirectScheduled) {
        _desktopRedirectScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/business/${widget.businessId}/dashboard');
        });
      }
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: kIsWeb,
      onPopInvoked: (didPop) async {
        if (didPop || kIsWeb) return;
        await _onLauncherWillPop(t);
      },
      child: FutureBuilder<(int, int, int, String?)>(
        future: Future.wait<dynamic>([_bgArgb, _gridColumns, _gridRows, _businessName]).then(
          (v) => (v[0] as int, v[1] as int, v[2] as int, v[3] as String?),
        ),
        builder: (context, snap) {
          final argb = snap.data?.$1 ?? MobileLauncherPrefs.defaultBackgroundArgb;
          final preferredColumns = snap.data?.$2 ?? MobileLauncherPrefs.defaultGridColumns;
          final preferredRows = snap.data?.$3 ?? MobileLauncherPrefs.defaultGridRows;
          final businessName = snap.data?.$4;
          final canOpenQuickSales =
              widget.authStore.hasBusinessPermission('invoices', 'add');
          final bg = Color(argb);
          final onBg = _isLight(bg) ? Colors.black87 : Colors.white;
          final cardBg = _isLight(bg)
              ? Colors.white.withValues(alpha: 0.92)
              : Colors.black.withValues(alpha: 0.25);
          final cardBorder = _isLight(bg)
              ? Colors.black.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.18);
          final width = MediaQuery.of(context).size.width;
          final maxColumnsByWidth = width < 360
              ? 2
              : width < 460
                  ? 3
                  : 4;
          final crossAxisCount = preferredColumns.clamp(2, maxColumnsByWidth);
          final visibleRows = preferredRows.clamp(2, 6);
          const spacing = 16.0;
          const horizontalPadding = 32.0;
          const tileAspectRatio = 0.9;
          final tileWidth =
              (width - horizontalPadding - ((crossAxisCount - 1) * spacing)) /
                  crossAxisCount;
          final tileHeight = tileWidth / tileAspectRatio;
          final gridViewportHeight =
              (tileHeight * visibleRows) + (spacing * (visibleRows - 1));

          if (snap.connectionState == ConnectionState.done) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applySystemOverlay(bg);
            });
          }

          return Scaffold(
            appBar: AppBar(
              backgroundColor: _isLight(bg)
                  ? Colors.white.withValues(alpha: 0.32)
                  : Colors.black.withValues(alpha: 0.22),
              foregroundColor: onBg,
              elevation: 0,
              titleSpacing: 12,
              title: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/logo32.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          t.mobileLauncherBrandName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: onBg,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          businessName ?? '${t.mobileLauncherBusinessFallback} #${widget.businessId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: onBg.withValues(alpha: 0.88),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: t.mobileLauncherBackToAccount,
                  icon: Icon(Icons.person_outline, color: onBg),
                  onPressed: () =>
                      context.go('/user/profile/dashboard'),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: onBg),
                  onSelected: (v) async {
                    if (v == 'disable_home') {
                      await _disableLauncherHome(t);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem<String>(
                      value: 'disable_home',
                      child: Text(t.mobileLauncherDisableHomeLauncherMenu),
                    ),
                  ],
                ),
              ],
            ),
            body: DecoratedBox(
              decoration: BoxDecoration(color: bg),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    height: gridViewportHeight,
                    child: GridView.count(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: tileAspectRatio,
                      padding: EdgeInsets.zero,
                      children: [
                        _LauncherTile(
                          icon: Icons.palette_outlined,
                          label: t.mobileLauncherAppearanceTile,
                          bg: cardBg,
                          borderColor: cardBorder,
                          fg: onBg,
                          onTap: () async {
                            await context.push<void>(
                              MobileLauncherPrefs.launcherAppearancePath(
                                widget.businessId,
                              ),
                            );
                            _reloadBackground();
                            _reloadGridLayout();
                            _reloadBusinessName();
                          },
                        ),
                        _LauncherTile(
                          icon: Icons.dashboard_customize_outlined,
                          label: t.mobileLauncherOpenFullPanel,
                          bg: cardBg,
                          borderColor: cardBorder,
                          fg: onBg,
                          onTap: () => context.go(
                            '/business/${widget.businessId}/dashboard',
                          ),
                        ),
                      _LauncherTile(
                        icon: Icons.point_of_sale_outlined,
                        label: t.mobileLauncherQuickSalesTile,
                        bg: cardBg,
                        borderColor: cardBorder,
                        fg: onBg,
                        enabled: canOpenQuickSales,
                        onTap: canOpenQuickSales
                            ? () => context.go(
                                  MobileLauncherPrefs.launcherQuickSalesPath(
                                    widget.businessId,
                                  ),
                                )
                            : () => SnackBarHelper.showError(
                                  context,
                                  message: t.noPermission,
                                ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LauncherTile extends StatelessWidget {
  const _LauncherTile({
    required this.icon,
    required this.label,
    required this.bg,
    required this.borderColor,
    required this.fg,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color borderColor;
  final Color fg;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: enabled ? fg.withValues(alpha: 0.12) : Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: enabled ? bg : bg.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 36,
                  color: enabled ? fg : fg.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: enabled ? fg : fg.withValues(alpha: 0.58),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
