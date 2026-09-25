import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../core/mobile_launcher_prefs.dart';
import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/currency_display_utils.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/profile/business_switcher_widgets.dart';
import '../../widgets/profile/businesses_hub_utils.dart';

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

  BusinessStatistics? _stats;
  bool _statsLoading = true;

  DateTime? _lastBackPressAt;
  bool _desktopRedirectScheduled = false;

  final _dashboardService = BusinessDashboardService(ApiClient());

  String? get _businessName {
    final current = widget.authStore.currentBusiness;
    if (current != null && current.id == widget.businessId) {
      return current.name;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant MobileLauncherHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      _loadStats();
    }
  }

  String _formatSalesValue(BusinessStatistics stats) {
    final currency = stats.currency ??
        (widget.authStore.currentBusiness?.id == widget.businessId
            ? widget.authStore.currentBusiness?.defaultCurrency
            : null);
    final unit = currency == null
        ? ''
        : currencyUnitLabelFromBusinessCurrencyMap(
            currency.toUnitMap(),
            fallback: '',
          );
    return formatAmountWithCurrencyUnit(
      stats.totalSales,
      unit: unit,
      decimalPlaces: currency?.decimalPlaces ?? 0,
    );
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final dash = await _dashboardService.getDashboard(widget.businessId);
      if (!mounted) return;
      setState(() {
        _stats = dash.statistics;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stats = null;
        _statsLoading = false;
      });
    }
  }

  void _reloadAppearance() {
    setState(() {
      _bgArgb = MobileLauncherPrefs.backgroundColorArgb(
        widget.authStore.currentUserId,
      );
      _gridColumns =
          MobileLauncherPrefs.gridColumns(widget.authStore.currentUserId);
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
    await MobileLauncherPrefs.clearResumeLauncher(
      widget.authStore.currentUserId,
    );
    if (!mounted) return;
    SnackBarHelper.show(context, message: t.mobileLauncherDisableHomeLauncherDone);
    context.go('/user/profile/dashboard');
  }

  Future<void> _openAppearance() async {
    await context.push<void>(
      MobileLauncherPrefs.launcherAppearancePath(widget.businessId),
    );
    if (!mounted) return;
    _reloadAppearance();
  }

  Future<void> _showBusinessSwitcher(AppLocalizations t) async {
    await showGlassModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return _LauncherBusinessSwitcherSheet(
          authStore: widget.authStore,
          currentBusinessId: widget.businessId,
          service: _dashboardService,
          onSelected: (businessId) async {
            Navigator.of(sheetCtx).pop();
            if (businessId == widget.businessId) return;
            await MobileLauncherPrefs.setResumeLauncher(
              widget.authStore.currentUserId,
              businessId,
            );
            if (!mounted) return;
            context.go(MobileLauncherPrefs.launcherHomePath(businessId));
          },
        );
      },
    );
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

  List<_LauncherAction> _buildActions(AppLocalizations t) {
    final auth = widget.authStore;
    final bid = widget.businessId;
    final canAddInvoice = auth.hasBusinessPermission('invoices', 'add');
    final canViewInvoices = auth.hasBusinessPermission('invoices', 'view');
    final canViewPeople = auth.hasBusinessPermission('people', 'view');
    final canViewProducts = auth.hasBusinessPermission('products', 'view');
    final canViewTxn = auth.hasBusinessPermission('people_transactions', 'view');
    final canViewReports = auth.hasBusinessPermission('reports', 'view');
    final canSettings = auth.hasBusinessPermission('settings', 'join');

    final actions = <_LauncherAction>[];

    if (canAddInvoice) {
      actions.add(
        _LauncherAction(
          id: 'quick_sales',
          icon: Icons.point_of_sale_rounded,
          label: t.mobileLauncherQuickSalesTile,
          accent: const Color(0xFF00897B),
          emphasized: true,
          onTap: () => context.go(
            MobileLauncherPrefs.launcherQuickSalesPath(bid),
          ),
        ),
      );
      actions.add(
        _LauncherAction(
          id: 'new_invoice',
          icon: Icons.note_add_rounded,
          label: t.mobileLauncherNewInvoiceTile,
          accent: const Color(0xFF1976D2),
          onTap: () => context.go(
            context.businessPanelUrl(bid, 'invoice/new'),
          ),
        ),
      );
    }

    if (canViewInvoices) {
      actions.add(
        _LauncherAction(
          id: 'invoices',
          icon: Icons.receipt_long_rounded,
          label: t.invoices,
          accent: const Color(0xFF5E35B1),
          onTap: () => context.go(context.businessPanelUrl(bid, 'invoice')),
        ),
      );
    }

    if (canViewPeople) {
      actions.add(
        _LauncherAction(
          id: 'people',
          icon: Icons.people_alt_rounded,
          label: t.people,
          accent: const Color(0xFF0288D1),
          onTap: () => context.go(context.businessPanelUrl(bid, 'persons')),
        ),
      );
    }

    if (canViewProducts) {
      actions.add(
        _LauncherAction(
          id: 'products',
          icon: Icons.inventory_2_rounded,
          label: t.products,
          accent: const Color(0xFFEF6C00),
          onTap: () => context.go(context.businessPanelUrl(bid, 'products')),
        ),
      );
    }

    if (canViewTxn) {
      actions.add(
        _LauncherAction(
          id: 'receipts',
          icon: Icons.swap_horiz_rounded,
          label: t.receiptsAndPayments,
          accent: const Color(0xFF43A047),
          onTap: () =>
              context.go(context.businessPanelUrl(bid, 'receipts-payments')),
        ),
      );
    }

    if (canViewReports) {
      actions.add(
        _LauncherAction(
          id: 'reports',
          icon: Icons.insights_rounded,
          label: t.reports,
          accent: const Color(0xFF6A1B9A),
          onTap: () => context.go(context.businessPanelUrl(bid, 'reports')),
        ),
      );
    }

    if (canSettings) {
      actions.add(
        _LauncherAction(
          id: 'settings',
          icon: Icons.settings_rounded,
          label: t.settings,
          accent: const Color(0xFF546E7A),
          onTap: () => context.go(context.businessPanelUrl(bid, 'settings')),
        ),
      );
    }

    actions.add(
      _LauncherAction(
        id: 'full_panel',
        icon: Icons.dashboard_customize_rounded,
        label: t.mobileLauncherOpenFullPanel,
        accent: const Color(0xFF3949AB),
        onTap: () => context.go('/business/$bid/dashboard'),
      ),
    );

    return actions;
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
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || kIsWeb) return;
        await _onLauncherWillPop(t);
      },
      child: FutureBuilder<(int, int)>(
        future: Future.wait<int>([_bgArgb, _gridColumns]).then(
          (v) => (v[0], v[1]),
        ),
        builder: (context, snap) {
          final argb =
              snap.data?.$1 ?? MobileLauncherPrefs.defaultBackgroundArgb;
          final preferredColumns =
              snap.data?.$2 ?? MobileLauncherPrefs.defaultGridColumns;
          final bg = Color(argb);
          final light = _isLight(bg);
          final onBg = light ? Colors.black87 : Colors.white;
          final onBgMuted = onBg.withValues(alpha: 0.72);
          final cardBg = light
              ? Colors.white.withValues(alpha: 0.94)
              : Colors.white.withValues(alpha: 0.12);
          final cardBorder = light
              ? Colors.black.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.14);
          final width = MediaQuery.sizeOf(context).width;
          final maxColumnsByWidth = width < 360
              ? 2
              : width < 520
                  ? 3
                  : 4;
          final crossAxisCount =
              preferredColumns.clamp(2, maxColumnsByWidth).toInt();
          final actions = _buildActions(t);
          final businessName = _businessName ??
              '${t.mobileLauncherBusinessFallback} #${widget.businessId}';

          if (snap.connectionState == ConnectionState.done) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applySystemOverlay(bg);
            });
          }

          return Scaffold(
            backgroundColor: bg,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bg,
                    Color.lerp(bg, light ? Colors.white : Colors.black, 0.12)!,
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LauncherHeader(
                      brandName: BrandConfig.mobileLauncherBrandName(t),
                      businessName: businessName,
                      onBg: onBg,
                      onBgMuted: onBgMuted,
                      light: light,
                      onBusinessTap: () => _showBusinessSwitcher(t),
                      onAccountTap: () =>
                          context.go('/user/profile/dashboard'),
                      accountTooltip: t.mobileLauncherBackToAccount,
                      menuItems: [
                        PopupMenuItem<String>(
                          value: 'appearance',
                          child: Row(
                            children: [
                              const Icon(Icons.palette_outlined, size: 20),
                              const SizedBox(width: 12),
                              Text(t.mobileLauncherAppearanceTile),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'switch',
                          child: Row(
                            children: [
                              const Icon(Icons.swap_horiz_rounded, size: 20),
                              const SizedBox(width: 12),
                              Text(t.mobileLauncherSwitchBusiness),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem<String>(
                          value: 'disable_home',
                          child: Row(
                            children: [
                              const Icon(Icons.home_outlined, size: 20),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(t.mobileLauncherDisableHomeLauncherMenu),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onMenuSelected: (v) async {
                        switch (v) {
                          case 'appearance':
                            await _openAppearance();
                          case 'switch':
                            await _showBusinessSwitcher(t);
                          case 'disable_home':
                            await _disableLauncherHome(t);
                        }
                      },
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: onBg,
                        backgroundColor: cardBg,
                        onRefresh: () async {
                          _reloadAppearance();
                          await _loadStats();
                        },
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          slivers: [
                            if (_statsLoading || _stats != null)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    12,
                                  ),
                                  child: _LauncherSummaryStrip(
                                    loading: _statsLoading,
                                    stats: _stats,
                                    salesValue: _stats == null
                                        ? null
                                        : _formatSalesValue(_stats!),
                                    cardBg: cardBg,
                                    borderColor: cardBorder,
                                    onBg: onBg,
                                    onBgMuted: onBgMuted,
                                    salesLabel: t.mobileLauncherSummarySales,
                                    recentLabel: t.mobileLauncherSummaryRecent,
                                  ),
                                ),
                              ),
                            if (actions.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Text(
                                      t.mobileLauncherNoTiles,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: onBgMuted,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  24,
                                ),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 0.92,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final action = actions[index];
                                      return _LauncherTile(
                                        action: action,
                                        bg: cardBg,
                                        borderColor: cardBorder,
                                        fg: onBg,
                                        lightSurface: light,
                                        index: index,
                                      );
                                    },
                                    childCount: actions.length,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LauncherAction {
  const _LauncherAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.emphasized = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool emphasized;
}

class _LauncherHeader extends StatelessWidget {
  const _LauncherHeader({
    required this.brandName,
    required this.businessName,
    required this.onBg,
    required this.onBgMuted,
    required this.light,
    required this.onBusinessTap,
    required this.onAccountTap,
    required this.accountTooltip,
    required this.menuItems,
    required this.onMenuSelected,
  });

  final String brandName;
  final String businessName;
  final Color onBg;
  final Color onBgMuted;
  final bool light;
  final VoidCallback onBusinessTap;
  final VoidCallback onAccountTap;
  final String accountTooltip;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: light
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(5),
                child: Image.asset(
                  'assets/images/logo32.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  brandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: onBg,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
              ),
              IconButton(
                tooltip: accountTooltip,
                icon: Icon(Icons.person_outline_rounded, color: onBg),
                onPressed: onAccountTap,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: onBg),
                onSelected: onMenuSelected,
                itemBuilder: (ctx) => menuItems,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBusinessTap,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                decoration: BoxDecoration(
                  color: light
                      ? Colors.white.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: light
                        ? Colors.black.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      BusinessSwitcherAvatar(name: businessName, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: onBg,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(context)
                                  .mobileLauncherTapToSwitchBusiness,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: onBgMuted),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: onBgMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LauncherSummaryStrip extends StatelessWidget {
  const _LauncherSummaryStrip({
    required this.loading,
    required this.stats,
    this.salesValue,
    required this.cardBg,
    required this.borderColor,
    required this.onBg,
    required this.onBgMuted,
    required this.salesLabel,
    required this.recentLabel,
  });

  final bool loading;
  final BusinessStatistics? stats;
  final String? salesValue;
  final Color cardBg;
  final Color borderColor;
  final Color onBg;
  final Color onBgMuted;
  final String salesLabel;
  final String recentLabel;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: loading
          ? Row(
              children: [
                Expanded(child: _summarySkeleton(onBgMuted)),
                const SizedBox(width: 12),
                Expanded(child: _summarySkeleton(onBgMuted)),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _SummaryMetric(
                    label: salesLabel,
                    value: salesValue ??
                        formatter.format(stats!.totalSales.round()),
                    icon: Icons.trending_up_rounded,
                    onBg: onBg,
                    onBgMuted: onBgMuted,
                    accent: const Color(0xFF00897B),
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: borderColor,
                ),
                Expanded(
                  child: _SummaryMetric(
                    label: recentLabel,
                    value: formatter.format(stats!.recentTransactions),
                    icon: Icons.receipt_outlined,
                    onBg: onBg,
                    onBgMuted: onBgMuted,
                    accent: const Color(0xFF1976D2),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summarySkeleton(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 10,
          width: 64,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 16,
          width: 88,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.onBg,
    required this.onBgMuted,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color onBg;
  final Color onBgMuted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: onBgMuted,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: onBg,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LauncherTile extends StatefulWidget {
  const _LauncherTile({
    required this.action,
    required this.bg,
    required this.borderColor,
    required this.fg,
    required this.lightSurface,
    required this.index,
  });

  final _LauncherAction action;
  final Color bg;
  final Color borderColor;
  final Color fg;
  final bool lightSurface;
  final int index;

  @override
  State<_LauncherTile> createState() => _LauncherTileState();
}

class _LauncherTileState extends State<_LauncherTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 320 + (widget.index * 40).clamp(0, 280)),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final accent = action.accent;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              action.onTap();
            },
            borderRadius: BorderRadius.circular(18),
            splashColor: accent.withValues(alpha: 0.14),
            highlightColor: accent.withValues(alpha: 0.06),
            child: Ink(
              decoration: BoxDecoration(
                color: widget.bg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: action.emphasized
                      ? accent.withValues(alpha: 0.45)
                      : widget.borderColor,
                  width: action.emphasized ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: accent.withValues(
                          alpha: widget.lightSurface ? 0.14 : 0.22,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(action.icon, size: 28, color: accent),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      action.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: widget.fg,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LauncherBusinessSwitcherSheet extends StatefulWidget {
  const _LauncherBusinessSwitcherSheet({
    required this.authStore,
    required this.currentBusinessId,
    required this.service,
    required this.onSelected,
  });

  final AuthStore authStore;
  final int currentBusinessId;
  final BusinessDashboardService service;
  final ValueChanged<int> onSelected;

  @override
  State<_LauncherBusinessSwitcherSheet> createState() =>
      _LauncherBusinessSwitcherSheetState();
}

class _LauncherBusinessSwitcherSheetState
    extends State<_LauncherBusinessSwitcherSheet> {
  late Future<List<BusinessWithPermission>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.getUserBusinesses();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;

    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                t.mobileLauncherSwitchBusiness,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<BusinessWithPermission>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          t.mobileLauncherBusinessesLoadError,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final list = (snap.data ?? [])
                      .where(
                        (b) => !businessBlocksAccess(
                          b.isDeleted,
                          b.isDeletionPending,
                        ),
                      )
                      .toList();
                  if (list.isEmpty) {
                    return Center(child: Text(t.mobileLauncherNoBusinesses));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final b = list[index];
                      final selected = b.id == widget.currentBusinessId;
                      return ListTile(
                        leading: BusinessSwitcherAvatar(name: b.name, size: 40),
                        title: Text(
                          b.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          businessSwitcherMetaLine(b, t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? Icon(
                                Icons.check_circle_rounded,
                                color: theme.colorScheme.primary,
                              )
                            : const Icon(Icons.chevron_left_rounded),
                        selected: selected,
                        onTap: () => widget.onSelected(b.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
