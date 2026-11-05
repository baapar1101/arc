import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../core/business_route_paths.dart';
import '../../core/business_panel_ui_store.dart';
import '../../core/locale_controller.dart';
import '../../core/calendar_controller.dart';
import '../../core/mobile_launcher_nav.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/combined_user_menu_button.dart';
import '../../widgets/fx/daily_fx_rates_toolbar_chip.dart';
import '../../models/person_model.dart';
import '../../widgets/person/person_form_dialog.dart';
import '../../widgets/banking/bank_account_form_dialog.dart';
import '../../widgets/banking/cash_register_form_dialog.dart';
import '../../widgets/banking/petty_cash_form_dialog.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../widgets/category/category_tree_dialog.dart';
import '../../services/business_dashboard_service.dart';
import '../../services/marketplace_service.dart';
import '../../widgets/marketplace/plugin_marketplace_utils.dart';
import '../../core/api_client.dart';
import '../../core/fiscal_year_controller.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../theme/brand_logo.dart';
import 'receipts_payments_list_page.dart' show BulkSettlementDialog;
import '../../widgets/document/document_form_dialog.dart';
import '../../widgets/wallet/wallet_top_up_dialog.dart';
import '../../widgets/notification_bell_button.dart';
import '../../widgets/transfer/transfer_form_dialog.dart';
import '../../widgets/expense_income/expense_income_form_dialog.dart';
import '../../widgets/warehouse/warehouse_form_dialog.dart';
import '../../widgets/warehouse/warehouse_doc_wizard_dialog.dart';
import '../../widgets/warehouse/warehouse_document_form_dialog.dart';
import '../../services/invoice_service.dart';
import '../../services/warehouse_service.dart';
import '../../utils/warehouse_invoice_lines.dart';
import '../../services/business_menu_preferences_service.dart';
import '../../widgets/ai/ai_chat_dialog.dart';
import '../../widgets/ai/ai_quick_start.dart';
import '../../widgets/calculator/calculator_dialog.dart';
import '../../widgets/business/business_shell_glyphs.dart';
import '../../widgets/telephony/telephony_phone_bar.dart';
import '../../widgets/telephony/telephony_incoming_call_overlay.dart';
import '../../core/date_utils.dart';
import '../../utils/error_extractor.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/tokens/extensions.dart';
import '../../utils/snackbar_helper.dart';
import 'check_form_page.dart';
import 'bank_accounts_page.dart';
import 'persons_page.dart';
import 'cash_registers_page.dart';
import 'petty_cash_page.dart';
import 'checks_page.dart';
import 'invoices_list_page.dart';
import 'receipts_payments_list_page.dart';
import 'expense_income_list_page.dart';
import 'transfers_page.dart';
import 'documents_page.dart';
import 'loan_facilities_page.dart';
import 'business_shell_side_nav_scope.dart';

class BusinessShell extends StatefulWidget {
  final int businessId;
  final Widget child;
  final AuthStore authStore;
  final LocaleController? localeController;
  final CalendarController? calendarController;
  final ThemeController? themeController;

  const BusinessShell({
    super.key,
    required this.businessId,
    required this.child,
    required this.authStore,
    this.localeController,
    this.calendarController,
    this.themeController,
  });

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  /// ارتفاع نوار ابزار آبی (لوگو، اکشن‌ها) — فشرده‌تر از [kToolbarHeight] پیش‌فرض.
  static const double _kBizAppBarToolbarHeight = 44;
  /// نوار دوم: تب‌ها / نام کسب‌وکار و زمان — نزدیک به نصف ارتفاع قبلی (۴۴).
  static const double _kUnifiedBizTabBarHeight = 24;
  static const double _kBizTabStripVerticalPadding = 2;
  /// ارتفاع ثابت بدنهٔ هر تب داخل نوار (نوار − پدینگ عمودی).
  static const double _kBizTabChipInnerHeight =
      _kUnifiedBizTabBarHeight - (_kBizTabStripVerticalPadding * 2);
  static const double _kBizTabMinWidth = 80;
  static const double _kBizTabMaxWidth = 156;
  static const double _kBizTabMetaGlyphSize = 12;
  static const double _kBizTabOverflowSize = 20;

  int _hoverIndex = -1;
  final Map<String, bool> _expandedMenuByKey = {};
  final BusinessDashboardService _businessService = BusinessDashboardService(ApiClient());
  final MarketplaceService _marketplaceService = MarketplaceService();
  List<Map<String, dynamic>> _businessPlugins = [];
  bool _pluginsLoaded = false;
  int? _pluginsLoadedForBusinessId;
  String? _lastRouteLocation;
  int _lastPluginsRefreshNonce = 0;
  bool _isBusinessLoading = false;
  String? _businessLoadError;
  Timer? _dateTimeUpdateTimer;
  final BusinessMenuPreferencesService _menuPreferencesService =
      BusinessMenuPreferencesService(ApiClient());
  BusinessMenuPreferencesDto _menuPreferences = BusinessMenuPreferencesDto.empty();

  /// فقط زمانی که `NavigationRail`/ریل کناری برای دسکتاپ نشان داده می‌شود؛ موبایل از drawer استفاده می‌کند.
  bool _desktopRailVisible = true;

  void _onBusinessPanelUiChanged() {
    if (!mounted) return;
    final nonce = BusinessPanelUiStore.instance.pluginsRefreshNonce;
    if (nonce != _lastPluginsRefreshNonce) {
      _lastPluginsRefreshNonce = nonce;
      _loadBusinessPlugins(force: true);
    }
    setState(() {});
  }

  String _bu(String rel) => context.businessPanelUrl(widget.businessId, rel);

  /// در دسکتاپ + حالت «تب»: بر اساس [reuseAcrossTabs]؛ در موبایل/تک‌صفحه همان مسیر [_bu].
  Future<void> _navigateMenuPath(
    BuildContext ctx,
    String menuUrl, {
    required bool desktopRail,
    required bool reuseAcrossTabs,
  }) async {
    await BusinessPanelUiStore.instance.hydrateIfNeeded();
    if (!ctx.mounted) return;
    BusinessPanelUiStore.instance.navigateSidebarFromMenuUrl(
      businessId: widget.businessId,
      menuUrl: menuUrl,
      go: (loc) => ctx.go(loc),
      fallbackOnly: !desktopRail,
      reuseAcrossTabs: reuseAcrossTabs,
    );
  }

  bool _reuseAcrossTabsForSidebarGesture({required bool longPress}) {
    final store = BusinessPanelUiStore.instance;
    if (store.mode != BusinessPanelNavigationMode.tabs) return true;
    if (store.sidebarTabBehavior != BusinessPanelSidebarTabBehavior.newTabViaLongPress) {
      return true;
    }
    return longPress;
  }

  /// عنوان نمایشی تب؛ برای مسیرهای خارج از درخت منو از [t] و [_fallbackTabTitleForRouteTail] استفاده می‌شود.
  String _tabTitleForBusinessPath(
    String path,
    int businessId,
    List<_MenuItem> menuRoot,
    AppLocalizations t,
  ) {
    final pathNorm = path.split('?').first;
    final pathTail = BusinessRoutePaths.stripBusinessPrefixAndTab(pathNorm, businessId);
    final pathTailBase = pathTail.split('?').first;

    var best = '';
    var bestLen = 0;
    void walk(List<_MenuItem> items) {
      for (final item in items) {
        final p = item.path;
        if (p == null) continue;
        final menuNorm = p.split('?').first;
        final menuTail = BusinessRoutePaths.stripBusinessPrefixAndTab(menuNorm, businessId);
        final menuTailBase = menuTail.split('?').first;
        if (menuTailBase.isEmpty) continue;
        final nested = pathTailBase.startsWith('$menuTailBase/');
        if (pathTailBase != menuTailBase && !nested) continue;
        if (menuTailBase.length >= bestLen) {
          bestLen = menuTailBase.length;
          best = item.label;
        }
        final ch = item.children;
        if (ch != null) walk(ch);
      }
    }

    walk(menuRoot);
    if (best.isNotEmpty) return best;
    final localizedTail = _fallbackTabTitleForRouteTail(pathTailBase, t);
    if (localizedTail != null) return localizedTail;
    try {
      if (pathTailBase.isNotEmpty) return pathTailBase.replaceAll('/', ' / ');
    } catch (_) {}
    return path;
  }

  /// مسیرهایی که در [allMenuItems] نیستند یا پیشوند «repair-shop» ندارند (تیره به‌جای /).
  String? _fallbackTabTitleForRouteTail(String pathTailBase, AppLocalizations t) {
    switch (pathTailBase) {
      case 'users-permissions':
        return t.usersAndPermissions;
      case 'price-lists':
        return t.priceLists;
      case 'projects':
        return t.businessPanelTabRouteProjects;
      case 'installments-report':
        return t.installmentsReportTitle;
      case 'document-monetization':
        return t.documentMonetizationTitle;
      case 'repair-shop-technicians':
        return t.businessPanelTabRouteRepairTechnicians;
      case 'repair-shop-settings':
        return t.businessPanelTabRouteRepairShopSettings;
      case 'payroll':
        return t.payrollMenu;
      case 'advanced-production':
        return t.advancedProductionMenu;
      case 'office-automation':
        return t.oaCartable;
      case 'office-automation/org':
        return t.oaOrg;
      case 'office-automation/external-orgs':
        return t.oaExternalOrgs;
      case 'office-automation/archive':
        return t.oaArchiveTree;
      case 'office-automation/reports':
        return t.oaReports;
      case 'settings/office-automation':
        return t.oaSettings;
      case 'fixed-assets':
        return t.fixedAssetsMenu;
      case 'settings/fixed-assets':
        return t.fixedAssetsSettingsPageTitle;
      case 'telephony':
        return t.telephonyMenu;
      case 'telephony/calls':
        return t.telephonyCallHistoryShort;
      case 'telephony/live':
        return t.telephonyLiveDashboardTitle;
      case 'telephony/reports':
        return t.telephonyReportsTitle;
      case 'telephony/softphone':
        return t.telephonySoftphoneTitle;
      case 'settings/telephony':
        return t.telephonySettingsTitle;
      case 'digipay':
        return t.digipayMenuTitle;
      case 'settings/digipay':
        return t.settingsDigipayTitle;
      case 'distribution':
        return t.distributionMenu;
      case 'hscript':
        return t.reportsHscriptTitle;
      default:
        break;
    }
    if (pathTailBase.startsWith('telephony/')) {
      return t.telephonyMenu;
    }
    if (pathTailBase.startsWith('payroll/')) {
      return t.payrollMenu;
    }
    if (pathTailBase.startsWith('advanced-production')) {
      return t.advancedProductionMenu;
    }
    if (pathTailBase.startsWith('office-automation')) {
      return t.oaMenu;
    }
    if (pathTailBase.startsWith('hscript')) {
      return t.reportsHscriptTitle;
    }
    if (RegExp(r'^price-lists/\d+/items$').hasMatch(pathTailBase)) {
      return t.businessPanelTabRoutePriceListItems;
    }
    return null;
  }

  /// تطبیق مسیر منو با [location] بر اساس بخش منطقی مسیر (بدون توجه به شمارهٔ تب).
  bool _businessMenuPathMatchesLocation(String location, String menuPath, int businessId) {
    final locTail =
        BusinessRoutePaths.stripBusinessPrefixAndTab(location.split('?').first, businessId).split('?').first;
    final menuTail =
        BusinessRoutePaths.stripBusinessPrefixAndTab(menuPath.split('?').first, businessId).split('?').first;
    if (menuTail.isEmpty) return false;
    return locTail == menuTail || locTail.startsWith('$menuTail/');
  }

  Future<bool> _confirmClosePinnedTab(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.push_pin_rounded, color: cs.primary),
          title: Text(t.businessPanelTabPinnedCloseTitle),
          content: Text(t.businessPanelTabPinnedCloseMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.businessPanelTabPinnedCloseConfirm),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  void _showPinnedKeptSnackBar(BuildContext context, int count) {
    if (count <= 0 || !context.mounted) return;
    final t = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.businessPanelTabPinnedKeptSnackbar(count))),
    );
  }

  Future<void> _requestCloseTab(
    BuildContext context,
    String path,
    void Function(String location) go,
  ) async {
    final store = BusinessPanelUiStore.instance;
    final bid = widget.businessId;
    if (store.isTabPinned(bid, path)) {
      final ok = await _confirmClosePinnedTab(context);
      if (!ok || !context.mounted) return;
      store.closeTab(bid, path, go, force: true);
      return;
    }
    store.closeTab(bid, path, go);
  }

  Future<void> _showDesktopTabActionDialog(
    BuildContext context,
    List<_MenuItem> menuRoot,
    BusinessPanelTabSession session,
    String path,
  ) async {
    final store = BusinessPanelUiStore.instance;
    final bid = widget.businessId;
    void go(String loc) => context.go(loc);
    final pinned = session.isPathPinned(path);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(
            _tabTitleForBusinessPath(path, bid, menuRoot, t),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                title: Text(pinned ? t.businessPanelTabUnpin : t.businessPanelTabPin),
                onTap: () {
                  Navigator.pop(ctx);
                  store.toggleTabPinned(bid, path);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(t.businessPanelTabCloseThisTab),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!context.mounted) return;
                  await _requestCloseTab(context, path, go);
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text(t.businessPanelTabCloseTabsToTheRight),
                onTap: () {
                  Navigator.pop(ctx);
                  final kept = store.closeTabsToTheRightOf(bid, path, go);
                  if (context.mounted) _showPinnedKeptSnackBar(context, kept);
                },
              ),
              ListTile(
                leading: const Icon(Icons.arrow_back),
                title: Text(t.businessPanelTabCloseTabsToTheLeft),
                onTap: () {
                  Navigator.pop(ctx);
                  final kept = store.closeTabsToTheLeftOf(bid, path, go);
                  if (context.mounted) _showPinnedKeptSnackBar(context, kept);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          ],
        );
      },
    );
  }

  Future<void> _showAllTabsManagementDialog(BuildContext context, List<_MenuItem> menuRoot) async {
    final store = BusinessPanelUiStore.instance;
    final bid = widget.businessId;
    void go(String loc) => context.go(loc);
    if (store.tabsForBusiness(bid) == null) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: store,
          builder: (ctx, _) {
            final t = AppLocalizations.of(ctx)!;
            final session = store.tabsForBusiness(bid);
            if (session == null || session.paths.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(ctx).canPop()) Navigator.pop(ctx);
              });
              return const SizedBox.shrink();
            }
            return AlertDialog(
              title: Text(t.businessPanelTabAllTabsTitle),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: session.paths.length,
                  itemBuilder: (_, i) {
                    final p = session.paths[i];
                    final title = _tabTitleForBusinessPath(p, bid, menuRoot, t);
                    final sel = p == session.activePath;
                    final isPinned = session.isPinnedAt(i);
                    return ListTile(
                      dense: true,
                      selected: sel,
                      leading: Icon(
                        isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        size: 18,
                        color: isPinned
                            ? Theme.of(ctx).colorScheme.primary
                            : Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(ctx);
                        store.selectTab(bid, p, go);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: isPinned ? t.businessPanelTabUnpin : t.businessPanelTabPin,
                            icon: Icon(
                              isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                              size: 20,
                            ),
                            onPressed: () => store.toggleTabPinned(bid, p),
                          ),
                          IconButton(
                            tooltip: isPinned
                                ? t.businessPanelTabClosePinnedTooltip
                                : MaterialLocalizations.of(ctx).closeButtonTooltip,
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () async {
                              if (isPinned) {
                                final ok = await _confirmClosePinnedTab(ctx);
                                if (!ok || !ctx.mounted) return;
                                store.closeTab(bid, p, go, force: true);
                              } else {
                                store.closeTab(bid, p, go);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    final kept = store.closeAllTabs(bid, go);
                    Navigator.pop(ctx);
                    if (context.mounted) _showPinnedKeptSnackBar(context, kept);
                  },
                  child: Text(t.businessPanelTabCloseAllTabs),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.close)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopTabChip(
    BuildContext context,
    List<_MenuItem> menuRoot,
    BusinessPanelTabSession session,
    String path,
  ) {
    final store = BusinessPanelUiStore.instance;
    final bid = widget.businessId;
    final active = path == session.activePath;
    final pinned = session.isPathPinned(path);
    final t = AppLocalizations.of(context)!;
    final label = _tabTitleForBusinessPath(path, bid, menuRoot, t);
    void goLoc(String loc) => context.go(loc);

    final cs = Theme.of(context).colorScheme;
    final bool isDarkStrip = Theme.of(context).brightness == Brightness.dark;
    final chipFg = active ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.92);
    final chipFgStrong = active ? cs.onSurface : cs.onSurfaceVariant;
    final chipClose = chipFg.withValues(alpha: active ? 0.72 : 0.62);
    final chipPin = pinned
        ? cs.primary.withValues(alpha: active ? 0.95 : 0.82)
        : cs.outline.withValues(alpha: 0.55);

    final BorderRadius chipRadius = BorderRadius.circular(6);

    final Color chipBg = active
        ? Color.alphaBlend(
            cs.primary.withValues(alpha: isDarkStrip ? 0.26 : 0.13),
            cs.surface,
          )
        : cs.surfaceContainerHighest.withValues(alpha: isDarkStrip ? 0.52 : 0.72);

    final Color chipBorder = active
        ? cs.primary.withValues(alpha: isDarkStrip ? 0.72 : 0.52)
        : pinned
            ? cs.primary.withValues(alpha: isDarkStrip ? 0.42 : 0.28)
            : cs.outline.withValues(alpha: isDarkStrip ? 0.38 : 0.22);

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _kBizTabMinWidth, maxWidth: _kBizTabMaxWidth),
        child: Material(
          elevation: active ? (isDarkStrip ? 2 : 1) : 0,
          shadowColor: cs.shadow.withValues(alpha: active ? 0.18 : 0.08),
          color: chipBg,
          shape: RoundedRectangleBorder(
            borderRadius: chipRadius,
            side: BorderSide(color: chipBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: chipRadius,
            hoverColor: cs.primary.withValues(alpha: isDarkStrip ? 0.09 : 0.06),
            splashColor: cs.primary.withValues(alpha: 0.10),
            onTap: () => store.selectTab(bid, path, goLoc),
            onLongPress: () => _showDesktopTabActionDialog(context, menuRoot, session, path),
            child: SizedBox(
              height: _kBizTabChipInnerHeight,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 7, end: 1),
                child: Row(
                  children: [
                    if (pinned)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 5),
                        child: Transform.rotate(
                          angle: -0.6,
                          child: Icon(Icons.push_pin_rounded, size: 10, color: chipPin),
                        ),
                      )
                    else
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? cs.primary : cs.outline.withValues(alpha: 0.55),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontSize: 11,
                              height: 1.0,
                              letterSpacing: active ? 0.12 : 0.01,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              color: active ? chipFgStrong : chipFg,
                            ),
                      ),
                    ),
                    Tooltip(
                      message: pinned
                          ? t.businessPanelTabClosePinnedTooltip
                          : MaterialLocalizations.of(context).closeButtonTooltip,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _requestCloseTab(context, path, goLoc),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: pinned ? cs.primary.withValues(alpha: 0.75) : chipClose,
                          ),
                        ),
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

  Widget _denseStripMetaCapsule({
    required ColorScheme cs,
    required bool isDark,
    required Widget child,
    double maxW = 220,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxW,
        maxHeight: _kBizTabChipInnerHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: cs.surface.withValues(alpha: isDark ? 0.52 : 0.94),
          border: Border.all(color: cs.outline.withValues(alpha: isDark ? 0.38 : 0.22)),
        ),
        child: SizedBox(
          height: _kBizTabChipInnerHeight,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 7),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _denseBusinessIdentityRow({
    required ThemeData theme,
    required ColorScheme cs,
    required bool isDark,
    required String businessName,
    required Color titleColor,
    required bool expanded,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: isDark ? 0.35 : 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: BusinessShellStorefrontGlyph(
              size: _kBizTabMetaGlyphSize,
              color: cs.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            businessName,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              height: 1.0,
              letterSpacing: 0.08,
              color: titleColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
          ),
        ),
      ],
    );
  }

  Widget _denseDateTimeRow({
    required ThemeData theme,
    required Color muted,
    required String dateTimeStr,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 12, color: muted.withValues(alpha: 0.95)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            dateTimeStr,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
              height: 1.0,
              letterSpacing: 0.01,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// یک خط فشرده: نام کسب‌وکار + آیکون • تب‌ها (کنار نام، با اسکرول) • زمان • منوی تب‌ها
  ///
  /// [menuRoot] باید **منوی کامل** ([allMenuItems]) باشد نه [menuItems] فیلترشده،
  /// تا عنوان تب‌ها از همان برچسب‌های محلی منو به‌دست آید (و به `products` خام نیفتد).
  Widget _buildUnifiedDesktopTabStrip({
    required BuildContext context,
    required List<_MenuItem> menuRoot,
    required Color barBg,
    required Color stripBottomBorder,
    required String businessName,
    required String dateTimeStr,
    required bool isMobile,
  }) {
    final store = BusinessPanelUiStore.instance;
    final bid = widget.businessId;
    final session = store.tabsForBusiness(bid);
    if (session == null || session.paths.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color stripFg = cs.onSurfaceVariant;
    final Color stripFgTitle = cs.onSurface;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final Widget businessTitle = _denseStripMetaCapsule(
      cs: cs,
      isDark: isDark,
      maxW: 200,
      child: _denseBusinessIdentityRow(
        theme: theme,
        cs: cs,
        isDark: isDark,
        businessName: businessName,
        titleColor: stripFgTitle,
        expanded: false,
        textAlign: isRtl ? TextAlign.right : TextAlign.left,
      ),
    );

    final Widget dateWidget = !isMobile
        ? _denseStripMetaCapsule(
            cs: cs,
            isDark: isDark,
            maxW: 220,
            child: _denseDateTimeRow(
              theme: theme,
              muted: stripFg,
              dateTimeStr: dateTimeStr,
            ),
          )
        : const SizedBox.shrink();

    final t = AppLocalizations.of(context)!;
    final Widget overflowBtn = Tooltip(
      message: t.businessPanelTabListTooltip,
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.55 : 0.82),
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _showAllTabsManagementDialog(context, menuRoot),
          child: SizedBox(
            width: _kBizTabOverflowSize,
            height: _kBizTabOverflowSize,
            child: Icon(
              Icons.more_horiz_rounded,
              color: stripFgTitle.withValues(alpha: 0.85),
              size: 14,
            ),
          ),
        ),
      ),
    );

    final Widget tabRegion = Expanded(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: isRtl,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsetsDirectional.only(start: 6, end: 8),
            child: Row(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in session.paths)
                  _buildDesktopTabChip(context, menuRoot, session, p),
              ],
            ),
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: stripBottomBorder)),
      ),
      child: SizedBox(
        height: _kUnifiedBizTabBarHeight,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 10,
            end: 8,
            top: _kBizTabStripVerticalPadding,
            bottom: _kBizTabStripVerticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              businessTitle,
              const SizedBox(width: 8),
              tabRegion,
              if (!isMobile) ...[
                const SizedBox(width: 6),
                dateWidget,
              ],
              const SizedBox(width: 6),
              overflowBtn,
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    BusinessPanelUiStore.instance.addListener(_onBusinessPanelUiChanged);
    // اطمینان از bind بودن AuthStore برای ApiClient (جهت هدرها و تنظیمات)
    try {
      ApiClient.bindAuthStore(widget.authStore);
    } catch (_) {}
    // سال مالی انتخاب‌شده در داشبورد را برای گزارش‌ها/هدر از همان ابتدا bind کن
    unawaited(FiscalYearController.load(widget.businessId));
    // اضافه کردن listener برای AuthStore
    widget.authStore.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    
    // بارگذاری اطلاعات کسب و کار و دسترسی‌ها
    _loadBusinessInfo();
    _loadBusinessPlugins();
    _loadMenuPreferences();
    // به‌روزرسانی خودکار ساعت در نوار بالا هر دقیقه
    _dateTimeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    BusinessPanelUiStore.instance.removeListener(_onBusinessPanelUiChanged);
    _dateTimeUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BusinessShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId) {
      _pluginsLoaded = false;
      _pluginsLoadedForBusinessId = null;
      unawaited(FiscalYearController.load(widget.businessId));
      _loadBusinessPlugins(force: true);
      _loadMenuPreferences();
    }
  }

  Future<void> _loadMenuPreferences() async {
    try {
      final data = await _menuPreferencesService.getPreferences(widget.businessId);
      if (!mounted) return;
      setState(() => _menuPreferences = data);
    } catch (_) {}
  }

    Future<void> showAddReceiptPaymentDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => BulkSettlementDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          isReceipt: true, // پیش‌فرض دریافت
          businessInfo: widget.authStore.currentBusiness,
          apiClient: ApiClient(),
          authStore: widget.authStore,
        ),
      );
      if (result == true) {
        // Refresh the receipts payments page if it's currently open
        _refreshReceiptsPaymentsPageIfOpen();
      }
    }

    Future<void> showAddTransferDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => TransferFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          authStore: widget.authStore,
          apiClient: ApiClient(),
        ),
      );
      if (result == true) {
        _refreshTransfersPageIfOpen();
      }
    }

    Future<void> showAddExpenseIncomeDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => ExpenseIncomeFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          isIncome: false, // پیش‌فرض هزینه؛ قابل تغییر داخل دیالوگ
          businessInfo: widget.authStore.currentBusiness,
          apiClient: ApiClient(),
        ),
      );
      if (result == true) {
        _refreshExpenseIncomePageIfOpen();
      }
    }

    Future<void> showAddCheckDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (context) => CheckFormDialog(
          businessId: widget.businessId,
          authStore: widget.authStore,
          calendarController: calendarController,
          onSuccess: () {
            _refreshChecksPageIfOpen();
          },
        ),
      );
      if (result == true) {
        _refreshChecksPageIfOpen();
      }
    }

    void _refreshCurrentPage() {
    // Force a rebuild of the current page
    setState(() {
      // This will cause the current page to rebuild
      // and if it's PettyCashPage, it will refresh its data
    });
  }

    /// Refresh the bank accounts page if it's currently open
    void _refreshBankAccountsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final accountsPath = _bu('accounts');
        if (currentPath == accountsPath) {
          // Try to get the page state and refresh the page
          final pageState = BankAccountsPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        // If we can't determine the current path or refresh, just refresh current page
        _refreshCurrentPage();
      }
    }

    /// Refresh the persons page if it's currently open
    void _refreshPersonsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final personsPath = _bu('persons');
        if (currentPath == personsPath) {
          final pageState = PersonsPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the cash registers page if it's currently open
    void _refreshCashRegistersPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final cashBoxPath = _bu('cash-box');
        if (currentPath == cashBoxPath) {
          final pageState = CashRegistersPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the petty cash page if it's currently open
    void _refreshPettyCashPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final pettyCashPath = _bu('petty-cash');
        if (currentPath == pettyCashPath) {
          final pageState = PettyCashPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the checks page if it's currently open
    void _refreshChecksPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final checksPath = _bu('checks');
        if (currentPath == checksPath) {
          final pageState = ChecksPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the invoices page if it's currently open
    void _refreshInvoicesPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final invoicesPath = _bu('invoice');
        if (currentPath == invoicesPath) {
          final pageState = InvoicesListPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the receipts payments page if it's currently open
    void _refreshReceiptsPaymentsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final receiptsPaymentsPath = _bu('receipts-payments');
        if (currentPath == receiptsPaymentsPath) {
          final pageState = ReceiptsPaymentsListPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the expense income page if it's currently open
    void _refreshExpenseIncomePageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final expenseIncomePath = _bu('expense-income');
        if (currentPath == expenseIncomePath) {
          final pageState = ExpenseIncomeListPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the transfers page if it's currently open
    void _refreshTransfersPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final transfersPath = _bu('transfers');
        if (currentPath == transfersPath) {
          final pageState = TransfersPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    /// Refresh the documents page if it's currently open
    void _refreshDocumentsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final documentsPath = _bu('documents');
        if (currentPath == documentsPath) {
          final pageState = DocumentsPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    Future<void> showWalletTopUpDialog() async {
      if (!context.mounted) return;
      await WalletTopUpDialog.show(
        context: context,
        businessId: widget.businessId,
        onSuccess: () {
          // در صورت نیاز می‌توانید callback اضافه کنید
        },
        onError: (error) {
          // خطا در ویجت مدیریت می‌شود
        },
      );
    }

  Future<void> _loadBusinessInfo() async {
    if (widget.authStore.currentBusiness?.id == widget.businessId) {
      return; // اطلاعات قبلاً بارگذاری شده
    }

    if (mounted) {
      setState(() {
        _isBusinessLoading = true;
        _businessLoadError = null;
      });
    }

    try {
      final businessData = await _businessService.getBusinessWithPermissions(widget.businessId);
      await widget.authStore.setCurrentBusiness(businessData);
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        final msg = ErrorExtractor.extractErrorMessage(e, t);
        setState(() {
          _businessLoadError = msg;
        });
        SnackBarHelper.showError(
          context,
          message: msg,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusinessLoading = false;
        });
      }
    }
  }

  Future<void> _loadBusinessPlugins({bool force = false}) async {
    if (!force &&
        _pluginsLoaded &&
        _pluginsLoadedForBusinessId == widget.businessId) {
      return;
    }

    try {
      final plugins = await _marketplaceService.listBusinessPlugins(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _businessPlugins = plugins.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _pluginsLoaded = true;
          _pluginsLoadedForBusinessId = widget.businessId;
        });
      }
    } catch (e) {
      // خطا را نادیده می‌گیریم تا منو کار کند
      if (mounted) {
        setState(() {
          _pluginsLoaded = true;
          _pluginsLoadedForBusinessId = widget.businessId;
        });
      }
    }
  }

  bool _isBusinessOwner() {
    final current = widget.authStore.currentBusiness;
    return current != null && current.id == widget.businessId && current.isOwner;
  }

  bool _isPluginCodeLicensed(String code) {
    for (final plug in _businessPlugins) {
      if (plug['plugin_code'] != code) continue;
      if (marketplacePluginLicenseActive(plug)) return true;
    }
    return false;
  }

  bool _showPluginGatedMenu(bool isPluginActive) => isPluginActive;

  void _maybeRefreshPluginsAfterMarketplace(String location) {
    final prev = _lastRouteLocation;
    _lastRouteLocation = location;
    if (prev != null &&
        prev.contains('/plugin-marketplace') &&
        !location.contains('/plugin-marketplace')) {
      _loadBusinessPlugins(force: true);
    }
  }

  bool _isWarrantyPluginActive() {
    // پیدا کردن پلاگین گارانتی
    try {
      final warrantyPlugin = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'product_warranty',
        orElse: () => <String, dynamic>{},
      );
      return warrantyPlugin['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isRepairShopPluginActive() {
    // پیدا کردن پلاگین تعمیرگاه
    try {
      final repairShopPlugin = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'repair_shop_management',
        orElse: () => <String, dynamic>{},
      );
      return repairShopPlugin['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isCustomerClubPluginActive() {
    try {
      final plug = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'customer_club',
        orElse: () => <String, dynamic>{},
      );
      return plug['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isDistributionPluginActive() {
    try {
      final plug = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'distribution',
        orElse: () => <String, dynamic>{},
      );
      return plug['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isAdvancedAccountingMenuItem(_MenuItem item) {
    if (kAdvancedAccountingMenuKeys.contains(item.key)) return true;
    final path = item.path;
    if (path == null) return false;
    return path.contains('/year-end-closing') ||
        path.contains('/currency-revaluation') ||
        path.contains('/loan-facilities') ||
        path.contains('/report-templates');
  }

  bool _isPayrollPluginActive() => _isPluginCodeLicensed('payroll');

  bool _isAdvancedProductionPluginActive() =>
      _isPluginCodeLicensed('advanced_production');

  bool _isOfficeAutomationPluginActive() => _isPluginCodeLicensed('office_automation');

  bool _isFixedAssetsPluginActive() => _isPluginCodeLicensed('fixed_assets');

  bool _isTelephonyPluginActive() => _isPluginCodeLicensed('asterisk_issabel_connector');

  bool _isWooCommerceHesabixPluginActive() {
    try {
      final plug = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'woocommerce_hesabix',
        orElse: () => <String, dynamic>{},
      );
      return plug['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isDigipayPluginActive() => _isPluginCodeLicensed('digipay_credit');

  bool _isBasalamPluginActive() {
    try {
      final plug = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'basalam_connector',
        orElse: () => <String, dynamic>{},
      );
      return plug['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  bool _isMoadianPluginActive() {
    try {
      final plug = _businessPlugins.firstWhere(
        (plugin) => plugin['plugin_code'] == 'moadian_tax_integration',
        orElse: () => <String, dynamic>{},
      );
      return plug['is_active'] == true;
    } catch (e) {
      return false;
    }
  }

  void _openQuickAiChat(BuildContext context) {
    AIChatDialog.show(
      context,
      authStore: widget.authStore,
      businessId: widget.businessId,
      calendarController: widget.calendarController,
    );
  }

  Future<void> _openAiQuickStart(BuildContext context) async {
    await AiQuickStart.open(context);
  }

  void _openCalculator(BuildContext context) {
    CalculatorDialog.show(context);
  }

  static ButtonStyle get _bizToolbarIconStyle => IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _bizToolbarIconButton({
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: _bizToolbarIconStyle,
      onPressed: onPressed,
      onLongPress: onLongPress,
      icon: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final currentBusiness = widget.authStore.currentBusiness;
    final bool isCorrectBusiness = currentBusiness != null && currentBusiness.id == widget.businessId;
    final bool hasPermissions = widget.authStore.businessPermissions != null;

    // اگر در بارگذاری اطلاعات کسب‌وکار خطا داشتیم و هنوز کسب‌وکار فعلی با این صفحه هم‌خوان نیست،
    // به‌جای نمایش پیام «دسترسی ندارید»، یک صفحه خطای شفاف نمایش می‌دهیم.
    if (_businessLoadError != null && !isCorrectBusiness) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.businessDashboard),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 24),
                Text(
                  'خطا در بارگذاری اطلاعات کسب و کار یا دسترسی‌ها.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _businessLoadError ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    _loadBusinessInfo();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('تلاش مجدد برای بارگذاری'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // تا زمانی که اطلاعات کسب‌وکار و دسترسی‌ها به‌طور کامل بارگذاری نشده‌اند،
    // صفحه اصلی را با یک لودر ساده نمایش می‌دهیم تا پیام «عدم دسترسی» به‌صورت موقت دیده نشود.
    if (_isBusinessLoading || !isCorrectBusiness || !hasPermissions) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'در حال بارگذاری اطلاعات کسب و کار و دسترسی‌ها...',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final bool useRail = ResponsiveHelper.useShellPersistentNavigation(context);
    final bool railExtended = ResponsiveHelper.shellNavigationRailExtended(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    String location = _bu('dashboard'); // default location
    try {
      location = GoRouterState.of(context).uri.toString();
    } catch (e) {
      // اگر GoRouterState در دسترس نیست، از default استفاده کن
    }
    _maybeRefreshPluginsAfterMarketplace(location);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ساختار متمرکز منو
    final allMenuItems = <_MenuItem>[
      _MenuItem(
        key: 'dashboard',
        label: t.businessDashboard,
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        path: _bu('dashboard'),
        type: _MenuItemType.simple,
      ),
      _MenuItem(
        key: 'sep_practical_tools',
        label: t.practicalTools,
        icon: Icons.category,
        selectedIcon: Icons.category,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        key: 'persons',
        label: t.people,
        icon: Icons.people,
        selectedIcon: Icons.people,
        path: _bu('persons'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'group:products',
        label: t.productsAndServices,
        icon: Icons.inventory_2,
        selectedIcon: Icons.inventory_2,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            key: 'products',
            label: t.products,
            icon: Icons.shopping_cart,
            selectedIcon: Icons.shopping_cart,
            path: _bu('products'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'product-bundles',
            label: t.productBundlesMenu,
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            path: _bu('product-bundles'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'categories',
            label: t.categories,
            icon: Icons.category,
            selectedIcon: Icons.category,
            path: _bu('categories'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'product-attributes',
            label: t.productAttributes,
            icon: Icons.tune,
            selectedIcon: Icons.tune,
            path: _bu('product-attributes'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'catalog-spec-fields',
            label: t.catalogSpecFieldsMenu,
            icon: Icons.view_list_outlined,
            selectedIcon: Icons.view_list,
            path: _bu('catalog-spec-fields'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'barcode-labels',
            label: t.barcodeLabelsMenu,
            icon: Icons.qr_code_2_outlined,
            selectedIcon: Icons.qr_code_2,
            path: _bu('barcode-labels'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
      ),
      _MenuItem(
        key: 'group:accounts',
        label: t.banking,
        icon: Icons.account_balance,
        selectedIcon: Icons.account_balance,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            key: 'accounts',
            label: t.accounts,
            icon: Icons.account_balance_wallet,
            selectedIcon: Icons.account_balance_wallet,
            path: _bu('accounts'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'petty-cash',
            label: t.pettyCash,
            icon: Icons.money,
            selectedIcon: Icons.money,
            path: _bu('petty-cash'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'cash-box',
            label: t.cashBox,
            icon: Icons.savings,
            selectedIcon: Icons.savings,
            path: _bu('cash-box'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'wallet',
            label: t.wallet,
            icon: Icons.wallet,
            selectedIcon: Icons.wallet,
            path: _bu('wallet'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'loan-facilities',
            label: t.loanFacilities,
            icon: Icons.real_estate_agent_outlined,
            selectedIcon: Icons.real_estate_agent,
            path: _bu('loan-facilities'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
        ],
      ),
      _MenuItem(
        key: 'sep_accounting',
        label: t.accounting,
        icon: Icons.calculate,
        selectedIcon: Icons.calculate,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        key: 'quick-sales',
        label: t.quickSalesMenu,
        icon: Icons.point_of_sale,
        selectedIcon: Icons.point_of_sale,
        path: _bu('quick-sales'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'invoice',
        label: t.invoice,
        icon: Icons.receipt,
        selectedIcon: Icons.receipt,
        path: _bu('invoice'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'receipts-payments',
        label: t.receiptsAndPayments,
        icon: Icons.account_balance_wallet,
        selectedIcon: Icons.account_balance_wallet,
        path: _bu('receipts-payments'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'expense-income',
        label: t.expenseAndIncome,
        icon: Icons.account_balance_wallet,
        selectedIcon: Icons.account_balance_wallet,
        path: _bu('expense-income'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'transfers',
        label: t.transfers,
        icon: Icons.swap_horiz,
        selectedIcon: Icons.swap_horiz,
        path: _bu('transfers'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'checks',
        label: t.checks,
        icon: Icons.receipt_long,
        selectedIcon: Icons.receipt_long,
        path: _bu('checks'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'documents',
        label: t.documents,
        icon: Icons.description,
        selectedIcon: Icons.description,
        path: _bu('documents'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'group:chart-of-accounts',
        label: t.accountingMenu,
        icon: Icons.calculate,
        selectedIcon: Icons.calculate,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            key: 'chart-of-accounts',
            label: t.chartOfAccounts,
            icon: Icons.table_chart,
            selectedIcon: Icons.table_chart,
            path: _bu('chart-of-accounts'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'opening-balance',
            label: t.openingBalance,
            icon: Icons.play_arrow,
            selectedIcon: Icons.play_arrow,
            path: _bu('opening-balance'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'year-end-closing',
            label: t.yearEndClosing,
            icon: Icons.stop,
            selectedIcon: Icons.stop,
            path: _bu('year-end-closing'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          if (widget.authStore.isMultiCurrency)
          _MenuItem(
            key: 'currency-revaluation',
            label: t.currencyRevaluation,
            icon: Icons.payments,
            selectedIcon: Icons.payments,
            path: _bu('currency-revaluation'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
      ),
      _MenuItem(
        key: 'reports',
        label: t.reports,
        icon: Icons.assessment,
        selectedIcon: Icons.assessment,
        path: _bu('reports'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'sep_services_plugins',
        label: t.servicesAndPlugins,
        icon: Icons.extension,
        selectedIcon: Icons.extension,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        key: 'basalam',
        label: t.basalamIntegrationMenuTitle,
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
        path: _bu('basalam'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'woocommerce',
        label: t.woocommerceIntegrationMenuTitle,
        icon: Icons.shopping_cart_outlined,
        selectedIcon: Icons.shopping_cart,
        path: _bu('woocommerce'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'digipay',
        label: t.digipayMenuTitle,
        icon: Icons.credit_score_outlined,
        selectedIcon: Icons.credit_score,
        path: _bu('digipay'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'hscript',
        label: t.reportsHscriptTitle,
        icon: Icons.code_outlined,
        selectedIcon: Icons.code,
        path: _bu('hscript'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'group:warehouses',
        label: t.warehouseManagement,
        icon: Icons.warehouse,
        selectedIcon: Icons.warehouse,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            key: 'warehouses',
            label: t.warehouses,
            icon: Icons.store,
            selectedIcon: Icons.store,
            path: _bu('warehouses'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'warehouse-docs',
            label: t.warehouseDocsMenu,
            icon: Icons.description,
            selectedIcon: Icons.description,
            path: _bu('warehouse-docs'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'stock-count',
            label: t.stockCountMenu,
            icon: Icons.inventory,
            selectedIcon: Icons.inventory,
            path: _bu('stock-count'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'quick-sales-stock-discrepancies',
            label: t.quickSalesStockDiscrepanciesMenu,
            icon: Icons.rule_folder_outlined,
            selectedIcon: Icons.rule_folder,
            path: _bu('quick-sales-stock-discrepancies'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'goods-expense-income',
            label: t.goodsExpenseIncomeMenu,
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            path: _bu('goods-expense-income'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'production-orders',
            label: t.productionOrdersMenu,
            icon: Icons.precision_manufacturing_outlined,
            selectedIcon: Icons.precision_manufacturing,
            path: _bu('production-orders'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
        ],
      ),
      _MenuItem(
        key: 'storage-files',
        label: t.storageSpace,
        icon: Icons.storage,
        selectedIcon: Icons.storage,
        path: _bu('storage-files'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'tax-workspace',
        label: t.taxpayers,
        icon: Icons.account_balance,
        selectedIcon: Icons.account_balance,
        path: _bu('tax-workspace'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'group:ai',
        label: t.aiMenu,
        icon: Icons.smart_toy_outlined,
        selectedIcon: Icons.smart_toy,
        path: null, // برای منوی بازشونده
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            key: 'ai/chat',
            label: t.aiAssistantMenu,
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            path: _bu('ai/chat'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'ai/subscription',
            label: t.aiSubscriptionMenu,
            icon: Icons.subscriptions_outlined,
            selectedIcon: Icons.subscriptions,
            path: _bu('ai/subscription'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'ai/usage',
            label: t.aiUsageMenu,
            icon: Icons.bar_chart_outlined,
            selectedIcon: Icons.bar_chart,
            path: _bu('ai/usage'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'ai/skills/marketplace',
            label: t.aiSkillsMarketplaceMenu,
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront,
            path: _bu('ai/skills/marketplace'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'ai/skills/publisher',
            label: t.aiSkillsPublisherMenu,
            icon: Icons.payments_outlined,
            selectedIcon: Icons.payments,
            path: _bu('ai/skills/publisher'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
      ),
      _MenuItem(
        key: 'workflows',
        label: t.workflows,
        icon: Icons.hub_outlined,
        selectedIcon: Icons.hub,
        path: _bu('workflows'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'group:crm',
        label: t.crmMenu,
        icon: Icons.handshake_outlined,
        selectedIcon: Icons.handshake,
        path: _bu('crm/dashboard'),
        type: _MenuItemType.expandable,
        children: [
          // کار روزانه
          _MenuItem(
            key: 'crm/tasks',
            label: t.crmMenuTasks,
            icon: Icons.task_alt_outlined,
            selectedIcon: Icons.task_alt,
            path: _bu('crm/tasks'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'crm/web-chat',
            label: t.crmMenuWebChat,
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            path: _bu('crm/web-chat'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'crm/notes-calendar',
            label: t.crmMenuNotesCalendar,
            icon: Icons.calendar_month_outlined,
            selectedIcon: Icons.calendar_month,
            path: _bu('crm/notes-calendar'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          // قیف فروش
          _MenuItem(
            key: 'crm/leads',
            label: t.crmMenuLeads,
            icon: Icons.contact_phone_outlined,
            selectedIcon: Icons.contact_phone,
            path: _bu('crm/leads'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'crm/deals',
            label: t.crmMenuDeals,
            icon: Icons.trending_up_outlined,
            selectedIcon: Icons.trending_up,
            path: _bu('crm/deals'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'crm/activities',
            label: t.crmMenuActivities,
            icon: Icons.history,
            selectedIcon: Icons.history,
            path: _bu('crm/activities'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'crm/customer-360',
            label: t.crmMenuCustomer360,
            icon: Icons.person_search_outlined,
            selectedIcon: Icons.person_search,
            path: _bu('crm/customer-360'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          // بینش
          _MenuItem(
            key: 'crm/dashboard',
            label: t.crmMenuDashboard,
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            path: _bu('crm/dashboard'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          _MenuItem(
            key: 'crm/reports',
            label: t.crmMenuReports,
            icon: Icons.assessment_outlined,
            selectedIcon: Icons.assessment,
            path: _bu('crm/reports'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
          // پیکربندی
          _MenuItem(
            key: 'crm/process-definitions',
            label: t.crmMenuProcessDefinitions,
            icon: Icons.account_tree_outlined,
            selectedIcon: Icons.account_tree,
            path: _bu('crm/process-definitions'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'crm/sequences',
            label: t.crmMenuSequences,
            icon: Icons.timeline_outlined,
            selectedIcon: Icons.timeline,
            path: _bu('crm/sequences'),
            type: _MenuItemType.simple,
            hasAddButton: false,
          ),
        ],
      ),
      _MenuItem(
        key: 'warranty',
        label: t.warranty,
        icon: Icons.verified_user,
        selectedIcon: Icons.verified_user,
        path: _bu('warranty'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'repair-shop',
        label: t.repairShopMenu,
        icon: Icons.build_circle_outlined,
        selectedIcon: Icons.build_circle,
        path: _bu('repair-shop'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'customer-club',
        label: t.customerClubMenu,
        icon: Icons.card_giftcard_outlined,
        selectedIcon: Icons.card_giftcard,
        path: _bu('customer-club'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'payroll',
        label: t.payrollMenu,
        icon: Icons.payments_outlined,
        selectedIcon: Icons.payments,
        path: _bu('payroll'),
        type: _MenuItemType.simple,
        hasAddButton: true,
      ),
      _MenuItem(
        key: 'advanced-production',
        label: t.advancedProductionMenu,
        icon: Icons.precision_manufacturing_outlined,
        selectedIcon: Icons.precision_manufacturing,
        path: _bu('advanced-production'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'group:office-automation',
        label: t.oaMenu,
        icon: Icons.mark_email_unread_outlined,
        selectedIcon: Icons.mark_email_unread,
        path: null,
        type: _MenuItemType.expandable,
        children: [
          _MenuItem(
            key: 'office-automation',
            label: t.oaCartable,
            icon: Icons.inbox_outlined,
            selectedIcon: Icons.inbox,
            path: _bu('office-automation'),
            type: _MenuItemType.simple,
            hasAddButton: true,
          ),
          _MenuItem(
            key: 'office-automation/org',
            label: t.oaOrg,
            icon: Icons.account_tree_outlined,
            selectedIcon: Icons.account_tree,
            path: _bu('office-automation/org'),
            type: _MenuItemType.simple,
          ),
          _MenuItem(
            key: 'office-automation/external-orgs',
            label: t.oaExternalOrgs,
            icon: Icons.apartment_outlined,
            selectedIcon: Icons.apartment,
            path: _bu('office-automation/external-orgs'),
            type: _MenuItemType.simple,
          ),
          _MenuItem(
            key: 'office-automation/archive',
            label: t.oaArchiveTree,
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            path: _bu('office-automation/archive'),
            type: _MenuItemType.simple,
          ),
          _MenuItem(
            key: 'office-automation/reports',
            label: t.oaReports,
            icon: Icons.bar_chart_outlined,
            selectedIcon: Icons.bar_chart,
            path: _bu('office-automation/reports'),
            type: _MenuItemType.simple,
          ),
        ],
      ),
      _MenuItem(
        key: 'fixed-assets',
        label: t.fixedAssetsMenu,
        icon: Icons.chair_alt_outlined,
        selectedIcon: Icons.chair_alt,
        path: _bu('fixed-assets'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'telephony',
        label: t.telephonyMenu,
        icon: Icons.phone_in_talk_outlined,
        selectedIcon: Icons.phone_in_talk,
        path: _bu('telephony'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'distribution',
        label: t.distributionMenu,
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping,
        path: _bu('distribution'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'zohal/inquiries',
        label: t.inquiries,
        icon: Icons.search_outlined,
        selectedIcon: Icons.search,
        path: _bu('zohal/inquiries'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'sep_others',
        label: t.others,
        icon: Icons.more_horiz,
        selectedIcon: Icons.more_horiz,
        path: null, // آیتم جداکننده
        type: _MenuItemType.separator,
      ),
      _MenuItem(
        key: 'report-templates',
        label: t.templates,
        icon: Icons.picture_as_pdf,
        selectedIcon: Icons.picture_as_pdf,
        path: _bu('report-templates'),
        type: _MenuItemType.simple,
      ),
      _MenuItem(
        key: 'plugin-marketplace',
        label: t.pluginMarketplace,
        icon: Icons.store,
        selectedIcon: Icons.store,
        path: _bu('plugin-marketplace'),
        type: _MenuItemType.simple,
        hasAddButton: false,
      ),
      _MenuItem(
        key: 'settings',
        label: t.settings,
        icon: Icons.settings,
        selectedIcon: Icons.settings,
        path: _bu('settings'),
        type: _MenuItemType.simple,
      ),
    ];

    // فیلتر کردن منو بر اساس دسترسی‌ها
    final menuItems = _applyMenuPreferences(_getFilteredMenuItems(allMenuItems));

    int selectedIndex = 0;
    for (int i = 0; i < menuItems.length; i++) {
      final item = menuItems[i];
      if (item.type == _MenuItemType.separator) continue; // نادیده گرفتن آیتم جداکننده
      
      if (item.type == _MenuItemType.simple && item.path != null &&
          _businessMenuPathMatchesLocation(location, item.path!, widget.businessId)) {
        selectedIndex = i;
        break;
      } else if (item.type == _MenuItemType.expandable && item.children != null) {
        for (int j = 0; j < item.children!.length; j++) {
          final child = item.children![j];
          if (child.path != null &&
              _businessMenuPathMatchesLocation(location, child.path!, widget.businessId)) {
            selectedIndex = i;
            _setExpandableMenuOpen(item, true);
            break;
          }
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await BusinessPanelUiStore.instance.hydrateIfNeeded();
      if (!mounted) return;
      // مسیر را در خود callback بخوان تا URL کهنه‌ی build قبلی
      // (مثلاً بعد از بستن تب و قبل از go) جلسه تب را زنده نکند.
      final ctx = context;
      if (!ctx.mounted) return;
      String syncPath;
      try {
        syncPath = GoRouterState.of(ctx).uri.path;
      } catch (_) {
        syncPath = Uri.tryParse(location)?.path ?? _bu('dashboard');
      }
      if (syncPath.isEmpty) {
        syncPath = _bu('dashboard');
      }
      BusinessPanelUiStore.instance.onBusinessRouteChanged(
        widget.businessId,
        syncPath,
        isDesktop: useRail,
      );
    });

    Future<void> onSelect(int index, {bool longPress = false}) async {
      final item = menuItems[index];
      if (item.type == _MenuItemType.separator) return; // آیتم جداکننده قابل کلیک نیست
      
          if (item.type == _MenuItemType.simple && item.path != null) {
        final reuseAcrossTabs = _reuseAcrossTabsForSidebarGesture(longPress: longPress);
        try {
          if (!context.mounted) return;
          final ctx = context;
          if (GoRouterState.of(ctx).uri.toString() != item.path!) {
            if (item.key == 'categories') {
              // باز کردن دیالوگ دسته‌بندی‌ها به جای ناوبری
              if (widget.authStore.canReadSection('categories')) {
                if (!ctx.mounted) return;
                await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => CategoryTreeDialog(
                    businessId: widget.businessId,
                    authStore: widget.authStore,
                  ),
                );
              }
            } else {
              await _navigateMenuPath(ctx, item.path!, desktopRail: useRail, reuseAcrossTabs: reuseAcrossTabs);
            }
          }
        } catch (e) {
          // اگر GoRouterState در دسترس نیست، مستقیماً به مسیر برود
          if (!context.mounted) return;
          final ctx = context;
            if (item.key == 'categories') {
              if (widget.authStore.canReadSection('categories')) {
                if (!ctx.mounted) return;
                await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => CategoryTreeDialog(
                    businessId: widget.businessId,
                    authStore: widget.authStore,
                  ),
                );
              }
            } else {
              await _navigateMenuPath(ctx, item.path!, desktopRail: useRail, reuseAcrossTabs: reuseAcrossTabs);
            }
        }
      } else if (item.type == _MenuItemType.expandable) {
        setState(() => _toggleExpandableMenu(item));
      }
    }

    Future<void> onSelectChild(int parentIndex, int childIndex, {bool longPress = false}) async {
      final parent = menuItems[parentIndex];
      if (parent.type == _MenuItemType.expandable && parent.children != null) {
        final child = parent.children![childIndex];
        if (child.key == 'categories') {
          if (widget.authStore.canReadSection('categories')) {
            await showDialog<bool>(
              context: context,
              builder: (ctx) => CategoryTreeDialog(
                businessId: widget.businessId,
                authStore: widget.authStore,
              ),
            );
          }
          return;
        }
        if (child.path != null) {
          final reuseAcrossTabs = _reuseAcrossTabsForSidebarGesture(longPress: longPress);
          try {
            if (GoRouterState.of(context).uri.toString() != child.path!) {
              await _navigateMenuPath(context, child.path!, desktopRail: useRail, reuseAcrossTabs: reuseAcrossTabs);
            }
          } catch (e) {
            // اگر GoRouterState در دسترس نیست، مستقیماً به مسیر برود
            await _navigateMenuPath(context, child.path!, desktopRail: useRail, reuseAcrossTabs: reuseAcrossTabs);
          }
        }
      }
    }


    Future<void> onLogout() async {
      await widget.authStore.saveApiKey(null);
      if (!context.mounted) return;
      // از SnackBarHelper برای نمایش پیام خروج استفاده می‌کنیم تا روی همه لایه‌ها نمایش داده شود
      SnackBarHelper.showSuccess(
        context,
        message: t.logoutDone,
      );
      context.go('/login');
    }

    Future<void> showAddPersonDialog() async {
      final result = await showDialog<Person?>(
        context: context,
        builder: (context) => PersonFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            _refreshPersonsPageIfOpen();
          },
        ),
      );
      if (result != null) {
        _refreshPersonsPageIfOpen();
      }
    }

    void _refreshProductsPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final productsPath = _bu('products');
        if (currentPath == productsPath) {
          // If we're on the products page, refresh it
          _refreshCurrentPage();
        }
      } catch (_) {
        // If GoRouterState is not available, try to refresh anyway
        _refreshCurrentPage();
      }
    }

    Future<void> showAddProductDialog() async {
      final result = await showDialog<Object?>(
        context: context,
        builder: (context) => ProductFormDialog(
          businessId: widget.businessId,
          authStore: widget.authStore,
          onSuccess: () {
            // Refresh the products page if it's currently open
            _refreshProductsPageIfOpen();
          },
        ),
      );
      if (result != null && result != false) {
        // Product was successfully added (returns true or int ID), refresh if products page is open
        _refreshProductsPageIfOpen();
      }
    }

    Future<void> showAddCashBoxDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => CashRegisterFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the cash registers page if it's currently open
            _refreshCashRegistersPageIfOpen();
          },
        ),
      );
      if (result == true) {
        // Cash register was successfully added, refresh the cash registers page if open
        _refreshCashRegistersPageIfOpen();
      }
    }

    Future<void> showAddPettyCashDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => PettyCashFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the petty cash page if it's currently open
            _refreshPettyCashPageIfOpen();
          },
        ),
      );
      if (result == true) {
        // Petty cash was successfully added, refresh the petty cash page if open
        _refreshPettyCashPageIfOpen();
      }
    }

    Future<void> showAddBankAccountDialog() async {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => BankAccountFormDialog(
          businessId: widget.businessId,
          onSuccess: () {
            // Refresh the bank accounts page if it's currently open
            _refreshBankAccountsPageIfOpen();
          },
        ),
      );
      if (result == true) {
        // Bank account was successfully added, refresh the bank accounts page if open
        _refreshBankAccountsPageIfOpen();
      }
    }

    Future<void> showAddDocumentDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => DocumentFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          authStore: widget.authStore,
          apiClient: ApiClient(),
          fiscalYearId: null,
          currencyId: null, // از CurrencyPickerWidget (پیش‌فرض کسب‌وکار) دریافت می‌شود
        ),
      );
      if (result == true) {
        // Document was successfully added, refresh the documents page if open
        _refreshDocumentsPageIfOpen();
      }
    }

    void _refreshLoanFacilitiesPageIfOpen() {
      try {
        final currentPath = GoRouterState.of(context).uri.path;
        final lfPath = _bu('loan-facilities');
        if (currentPath == lfPath) {
          final pageState = LoanFacilitiesPage.getPageState(widget.businessId);
          if (pageState != null && pageState.mounted) {
            pageState.refresh();
            return;
          }
        }
      } catch (_) {
        _refreshCurrentPage();
      }
    }

    Future<void> showLoanFacilityCreateDialog() async {
      if (!context.mounted) return;
      final ctx = context;
      final calendarController = widget.calendarController ?? await CalendarController.load();
      if (!ctx.mounted) return;
      await LoanFacilitiesPage.showUpsertFacilityDialog(
        context: ctx,
        businessId: widget.businessId,
        calendarController: calendarController,
        authStore: widget.authStore,
        onSuccess: _refreshLoanFacilitiesPageIfOpen,
      );
    }

    Future<void> showAddWarehouseDialog() async {
      final result = await WarehouseFormDialog.show(
        context,
        businessId: widget.businessId,
        onSuccess: () {
          // Refresh the warehouses page if it's currently open
          _refreshCurrentPage();
        },
      );
      if (result == true) {
        // Warehouse was successfully added, refresh the current page
        _refreshCurrentPage();
      }
    }

  Future<void> showAddWarehouseDocumentDialog() async {
    if (!context.mounted) return;
    final calendarController = widget.calendarController ?? await CalendarController.load();
    final result = await showDialog<WarehouseDocWizardResult>(
      context: context,
      builder: (context) => WarehouseDocWizardDialog(
        businessId: widget.businessId,
        apiClient: ApiClient(),
        calendarController: calendarController,
      ),
    );
    if (result == null) return;
    
    if (result.isManual) {
      // Manual document creation
      final calendarController = widget.calendarController ?? await CalendarController.load();
      await showDialog(
        context: context,
        builder: (_) => WarehouseDocumentFormDialog(
          businessId: widget.businessId,
          calendarController: calendarController,
          onSuccess: () => _refreshCurrentPage(),
        ),
      );
      return;
    }
    
    // Handle invoice-based document creation
    await _handleInvoiceWizardResult(result);
  }

    void openMenuAddAction(_MenuItem item) {
      switch (item.key) {
        case 'persons':
          showAddPersonDialog();
        case 'products':
          showAddProductDialog();
        case 'accounts':
          showAddBankAccountDialog();
        case 'petty-cash':
          showAddPettyCashDialog();
        case 'cash-box':
          showAddCashBoxDialog();
        case 'wallet':
          showWalletTopUpDialog();
        case 'checks':
          showAddCheckDialog();
        case 'invoice':
          context.go(_bu('invoice/new'));
        case 'receipts-payments':
          showAddReceiptPaymentDialog();
        case 'expense-income':
          showAddExpenseIncomeDialog();
        case 'transfers':
          showAddTransferDialog();
        case 'documents':
          showAddDocumentDialog();
        case 'warehouses':
          showAddWarehouseDialog();
        case 'warehouse-docs':
          showAddWarehouseDocumentDialog();
        case 'goods-expense-income':
          context.go(_bu('goods-expense-income'));
        case 'production-orders':
          context.go(_bu('production-orders'));
        case 'crm/process-definitions':
          context.go('${_bu('crm/process-definitions')}?openAdd=1');
        case 'crm/leads':
          context.go('${_bu('crm/leads')}?openAdd=1');
        case 'crm/deals':
          context.go('${_bu('crm/deals')}?openAdd=1');
        case 'crm/activities':
          context.go('${_bu('crm/activities')}?openAdd=1');
        case 'loan-facilities':
          showLoanFacilityCreateDialog();
      }
    }

    bool isExpanded(_MenuItem item) => _isExpandableMenuOpen(item);

    int getTotalMenuItemsCount() {
      int count = 0;
      for (final item in menuItems) {
        if (item.type == _MenuItemType.separator) {
          count++; // آیتم جداکننده هم شمرده می‌شود
        } else {
          count++; // آیتم اصلی
          // نمایش زیرمجموعه‌ها در همه حالت‌ها (Rail و Extended)
          if (item.type == _MenuItemType.expandable && isExpanded(item)) {
            count += item.children?.length ?? 0;
          }
        }
      }
      return count;
    }


    final shellColors = context.shellColors;
    final Color appBarBg = shellColors.topBarBackground;
    final Color appBarFg = shellColors.topBarForeground;

    final launcherHomePath = MobileLauncherBackInfo.maybeHomeOf(context);
    final bool isMobile = !useRail;
    final String businessName = currentBusiness?.name ?? '';
    final TextStyle? appBarTitleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: appBarFg,
          fontWeight: FontWeight.w700,
          height: 1.1,
        );

    final appBar = AppBar(
      primary: false,
      toolbarHeight: _kBizAppBarToolbarHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      iconTheme: IconThemeData(color: appBarFg, size: 21),
      actionsIconTheme: IconThemeData(color: appBarFg, size: 21),
      automaticallyImplyLeading: false,
      leadingWidth: isMobile ? 44 : null,
      titleSpacing: 0,
      title: Row(
        children: [
          SizedBox(width: useRail ? 2 : 4),
          if (useRail)
            IconButton(
              tooltip: _desktopRailVisible
                  ? t.businessShellHideSidebarTooltip
                  : t.businessShellShowSidebarTooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _desktopRailVisible = !_desktopRailVisible),
              icon: BusinessShellMenuGlyph(
                color: appBarFg,
                size: 21,
                sidebarOpen: _desktopRailVisible,
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 22,
              maxWidth: isMobile ? 72 : 160,
            ),
            child: const BrandLogo(height: 22),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                BrandConfig.appTitle(t),
                style: appBarTitleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else if (businessName.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                businessName,
                style: appBarTitleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      leading: useRail
          ? null
          : Builder(
              builder: (ctx) => IconButton(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: BusinessShellMenuGlyph(color: appBarFg, size: 21, sidebarOpen: false),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: t.menu,
              ),
            ),
      actions: [
        DailyFxRatesToolbarChip(
          businessId: widget.businessId,
          authStore: widget.authStore,
          iconColor: appBarFg,
          iconOnly: isMobile,
        ),
        NotificationBellButton(
          authStore: widget.authStore,
          iconColor: appBarFg,
          denseToolbar: true,
        ),
        TelephonyPhoneBarHost(
          businessId: widget.businessId,
          authStore: widget.authStore,
          pluginActive: _isTelephonyPluginActive(),
          iconColor: appBarFg,
        ),
        if (!isMobile) ...[
          _bizToolbarIconButton(
            tooltip: t.businessShellAiChatTooltip,
            icon: Icon(Icons.smart_toy_outlined, color: appBarFg, size: 21),
            onPressed: () => _openQuickAiChat(context),
            onLongPress: () => _openAiQuickStart(context),
          ),
          _bizToolbarIconButton(
            tooltip: t.businessShellCalculatorTooltip,
            icon: Icon(Icons.calculate_outlined, color: appBarFg, size: 21),
            onPressed: () => _openCalculator(context),
          ),
        ],
        CombinedUserMenuButton(
          authStore: widget.authStore,
          localeController: widget.localeController,
          calendarController: widget.calendarController,
          themeController: widget.themeController,
          denseToolbar: true,
        ),
        if (isMobile)
          PopupMenuButton<String>(
            tooltip: t.businessShellMoreToolsTooltip,
            padding: EdgeInsets.zero,
            iconSize: 21,
            offset: const Offset(0, 8),
            icon: Icon(Icons.more_vert_rounded, color: appBarFg, size: 21),
            style: _bizToolbarIconStyle,
            onSelected: (value) {
              switch (value) {
                case 'ai':
                  _openQuickAiChat(context);
                case 'ai_quick':
                  _openAiQuickStart(context);
                case 'calculator':
                  _openCalculator(context);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'ai',
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(t.businessShellAiChatTooltip),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'ai_quick',
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(t.aiQuickLauncherTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'calculator',
                child: Row(
                  children: [
                    const Icon(Icons.calculate_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(t.businessShellCalculatorTooltip),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(width: 2),
      ],
    );

    // نوار دوم: تب‌ها یا نام کسب‌وکار / تاریخ (فقط دسکتاپ)
    final bool isJalali = widget.calendarController?.isJalali ?? true;
    final String dateTimeStr = HesabixDateUtils.formatDateTimeWithWeekday(
      DateTime.now(),
      isJalali,
      t.localeName,
    );
    final Color secondaryStripBg = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.175 : 0.10),
      isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
    );
    final Color stripBottomBorder = scheme.outline.withValues(alpha: isDark ? 0.58 : 0.48);
    final Color stripMuted = scheme.onSurfaceVariant;
    final Color stripTitle = scheme.onSurface;

    final ThemeData shellStripTheme = Theme.of(context);

    final Widget businessTopBar = DecoratedBox(
      decoration: BoxDecoration(
        color: secondaryStripBg,
        border: Border(bottom: BorderSide(color: stripBottomBorder)),
      ),
      child: SizedBox(
        height: _kUnifiedBizTabBarHeight,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 10,
            end: 8,
            top: _kBizTabStripVerticalPadding,
            bottom: _kBizTabStripVerticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _denseBusinessIdentityRow(
                  theme: shellStripTheme,
                  cs: scheme,
                  isDark: isDark,
                  businessName: businessName,
                  titleColor: stripTitle,
                  expanded: true,
                ),
              ),
              if (!isMobile)
                _denseStripMetaCapsule(
                  cs: scheme,
                  isDark: isDark,
                  maxW: 220,
                  child: _denseDateTimeRow(
                    theme: shellStripTheme,
                    muted: stripMuted,
                    dateTimeStr: dateTimeStr,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final uiStore = BusinessPanelUiStore.instance;
    final bool showBizTabs =
        useRail && uiStore.shouldShowTabStrip(widget.businessId, isDesktop: true);
    final Widget shellMainChild = widget.child;
    final double topInset = MediaQuery.paddingOf(context).top;
    final double topStripHeight = isMobile ? 0 : _kUnifiedBizTabBarHeight;

    final PreferredSizeWidget preferredAppBar = PreferredSize(
      preferredSize: Size.fromHeight(topInset + _kBizAppBarToolbarHeight + topStripHeight),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (topInset > 0) SizedBox(height: topInset),
          SizedBox(
            height: _kBizAppBarToolbarHeight,
            child: appBar,
          ),
          if (!isMobile)
            SizedBox(
              height: _kUnifiedBizTabBarHeight,
              child: showBizTabs
                  ? _buildUnifiedDesktopTabStrip(
                      context: context,
                      menuRoot: allMenuItems,
                      barBg: secondaryStripBg,
                      stripBottomBorder: stripBottomBorder,
                      businessName: businessName,
                      dateTimeStr: dateTimeStr,
                      isMobile: isMobile,
                    )
                  : businessTopBar,
            ),
        ],
      ),
    );

    // Overlayهای تلفن وقتی غیرفعال‌اند SizedBox.shrink برمی‌گردانند (غیر Positioned).
    // Stack با fit پیش‌فرض در قید شل، خودش را به همان صفر جمع می‌کند و ناوبری دیده نمی‌شود.
    final content = ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SizedBox.expand(child: shellMainChild),
            TelephonyScreenPopLayer(
              businessId: widget.businessId,
              authStore: widget.authStore,
              pluginActive: _isTelephonyPluginActive(),
            ),
            TelephonyIncomingCallOverlay(
              businessId: widget.businessId,
              authStore: widget.authStore,
              pluginActive: _isTelephonyPluginActive(),
            ),
          ],
        ),
      ),
    );

    // Side colors and styles
    final nav = context.shellNav;
    final textTheme = Theme.of(context).textTheme;
    final Color sideBg = Theme.of(context).brightness == Brightness.dark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerLow;
    final Color sideFg = scheme.onSurfaceVariant;
    final Color activeBg = scheme.primaryContainer;
    final Color activeFg = scheme.onPrimaryContainer;

    if (useRail) {
      return BusinessShellSideNavScope(
        desktopRailSupported: true,
        desktopRailVisible: _desktopRailVisible,
        setDesktopRailVisible: (visible) => setState(() => _desktopRailVisible = visible),
        child: Scaffold(
        appBar: preferredAppBar,
        body: Row(
          children: [
            if (_desktopRailVisible) ...[
            Container(
              width: nav.widthFor(extended: railExtended),
              height: double.infinity,
              color: sideBg,
              child: ListView.builder(
                padding: nav.listPadding,
                itemCount: getTotalMenuItemsCount(),
                itemBuilder: (ctx, index) {
                  // محاسبه ایندکس منو و تشخیص نوع آیتم
                  int menuIndex = 0;
                  int childIndex = -1;
                  bool isChildItem = false;
                  
                  int currentIndex = 0;
                  for (int i = 0; i < menuItems.length; i++) {
                    final item = menuItems[i];
                    
                    if (currentIndex == index) {
                      menuIndex = i;
                      break;
                    }
                    currentIndex++;
                    
                    // نمایش زیرمجموعه‌ها در همه حالت‌ها (Rail و Extended)
                    if (item.type == _MenuItemType.expandable && isExpanded(item)) {
                      final childrenCount = item.children?.length ?? 0;
                      if (index >= currentIndex && index < currentIndex + childrenCount) {
                        menuIndex = i;
                        childIndex = index - currentIndex;
                        isChildItem = true;
                        break;
                      }
                      currentIndex += childrenCount;
                    }
                  }
                  
                  final item = menuItems[menuIndex];
                  final bool isHovered = index == _hoverIndex;
                  final bool isSelected = menuIndex == selectedIndex;
                  final bool active = isSelected || isHovered;
                  final BorderRadius br = nav.itemBorderRadius(
                    flush: isSelected || isHovered,
                  );
                  final Color bgColor = active
                      ? (isHovered && !isSelected ? activeBg.withValues(alpha: 0.85) : activeBg)
                      : Colors.transparent;
                  
                  if (isChildItem && item.children != null && childIndex >= 0 && childIndex < item.children!.length) {
                    // زیرآیتم با انیمیشن و بهبود بصری
                    final child = item.children![childIndex];
                    final bool isChildSelected = child.path != null &&
                        _businessMenuPathMatchesLocation(location, child.path!, widget.businessId);
                    final bool isChildHovered = index == _hoverIndex;
                    final bool isChildActive = isChildSelected || isChildHovered;
                    final BorderRadius childBr = nav.itemBorderRadius(
                      flush: isChildSelected || isChildHovered,
                    );
                    final Color childBgColor = isChildActive
                        ? (isChildHovered && !isChildSelected 
                            ? (isDark ? activeBg.withValues(alpha: 0.5) : activeBg.withValues(alpha: 0.7))
                            : activeBg)
                        : Colors.transparent;
                    
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hoverIndex = index),
                        onExit: (_) => setState(() => _hoverIndex = -1),
                        child: InkWell(
                          borderRadius: childBr,
                          onTap: () => onSelectChild(menuIndex, childIndex, longPress: false),
                          onLongPress: (useRail &&
                                  BusinessPanelUiStore.instance.mode ==
                                      BusinessPanelNavigationMode.tabs &&
                                  BusinessPanelUiStore.instance.sidebarTabBehavior ==
                                      BusinessPanelSidebarTabBehavior.newTabViaLongPress)
                              ? () => onSelectChild(menuIndex, childIndex, longPress: true)
                              : null,
                          child: Container(
                            margin: EdgeInsets.zero,
                            padding: nav.childPaddingFor(extended: railExtended),
                            decoration: BoxDecoration(
                              color: childBgColor,
                              borderRadius: childBr,
                            ),
                            child: Tooltip(
                              message: child.label,
                              waitDuration: const Duration(milliseconds: 500),
                              child: Row(
                                mainAxisAlignment: railExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                                children: [
                                  _buildSidebarMenuIcon(
                                    child,
                                    color: isChildActive ? activeFg : sideFg,
                                    size: nav.iconSizeFor(extended: railExtended, child: true),
                                    active: isChildActive,
                                  ),
                                  if (railExtended) ...[
                                    SizedBox(width: nav.iconLabelGap),
                                    Expanded(
                                      child: Text(
                                        child.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: nav.childLabelStyle(
                                          textTheme,
                                          color: isChildActive ? activeFg : sideFg,
                                          active: isChildActive,
                                        ),
                                      ),
                                    ),
                                    if (child.hasAddButton && _canAddForSection(_sectionForMenuItem(child, t)))
                                      _sidebarAddAffordance(
                                        nav: nav,
                                        foreground: isChildActive ? activeFg : sideFg,
                                        background: isChildActive
                                            ? activeFg.withValues(alpha: 0.15)
                                            : sideFg.withValues(alpha: 0.1),
                                        onTap: () => openMenuAddAction(child),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  } else {
                    // آیتم اصلی (ساده، بازشونده، یا جداکننده)
                    if (item.type == _MenuItemType.separator) {
                      // آیتم جداکننده
                      return Container(
                        margin: nav.separatorPaddingFor(extended: railExtended),
                        child: Row(
                          children: [
                            if (railExtended) ...[
                              Expanded(
                                child: Divider(
                                  color: sideFg.withValues(alpha: 0.3),
                                  thickness: 1,
                                ),
                              ),
                              SizedBox(width: nav.iconLabelGap),
                              Text(
                                item.label,
                                style: nav.separatorLabelStyle(
                                  textTheme,
                                  color: sideFg.withValues(alpha: 0.7),
                                ),
                              ),
                              SizedBox(width: nav.iconLabelGap),
                              Expanded(
                                child: Divider(
                                  color: sideFg.withValues(alpha: 0.3),
                                  thickness: 1,
                                ),
                              ),
                            ] else ...[
                              Expanded(
                                child: Divider(
                                  color: sideFg.withValues(alpha: 0.3),
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    } else {
                      // آیتم ساده یا آیتم بازشونده
                      final chrome = _sidebarItemChrome(
                        item,
                        selected: isSelected,
                        hovered: isHovered,
                        fallbackFg: active ? activeFg : sideFg,
                        fallbackBg: bgColor,
                      );
                      Widget menuItemWidget = MouseRegion(
                        onEnter: (_) => setState(() => _hoverIndex = index),
                        onExit: (_) => setState(() => _hoverIndex = -1),
                        child: InkWell(
                          borderRadius: br,
                          onTap: () {
                            if (item.type == _MenuItemType.expandable) {
                              setState(() => _toggleExpandableMenu(item));
                            } else {
                              onSelect(menuIndex, longPress: false);
                            }
                          },
                          onLongPress: (!useRail ||
                                  item.type != _MenuItemType.simple ||
                                  item.path == null ||
                                  BusinessPanelUiStore.instance.mode !=
                                      BusinessPanelNavigationMode.tabs ||
                                  BusinessPanelUiStore.instance.sidebarTabBehavior !=
                                      BusinessPanelSidebarTabBehavior.newTabViaLongPress)
                              ? null
                              : () => onSelect(menuIndex, longPress: true),
                          child: Container(
                            margin: EdgeInsets.zero,
                            padding: nav.parentPaddingFor(extended: railExtended),
                            decoration: BoxDecoration(
                              color: chrome.bg,
                              borderRadius: br,
                            ),
                            child: Row(
                              mainAxisAlignment: railExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _buildSidebarMenuIcon(
                                      item,
                                      color: chrome.fg,
                                      size: nav.iconSizeFor(extended: railExtended, child: false),
                                      active: active,
                                    ),
                                    // آیکون expand/collapse کوچک در گوشه برای حالت Rail
                                    if (!railExtended && item.type == _MenuItemType.expandable)
                                      Positioned(
                                        right: -3,
                                        bottom: -3,
                                        child: Container(
                                          width: nav.expandBadgeSize,
                                          height: nav.expandBadgeSize,
                                          decoration: BoxDecoration(
                                            color: sideBg,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: sideFg.withValues(alpha: 0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: AnimatedRotation(
                                            turns: isExpanded(item) ? 0.5 : 0,
                                            duration: const Duration(milliseconds: 200),
                                            curve: Curves.easeInOut,
                                            child: Icon(
                                              Icons.expand_more,
                                              color: sideFg,
                                              size: nav.expandBadgeSize - 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (railExtended) ...[
                                  SizedBox(width: nav.iconLabelGap),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: nav.parentLabelStyle(
                                        textTheme,
                                        color: chrome.fg,
                                        active: active ||
                                            context.shellColors.sidebarFooterForeground(item.key) != null,
                                      ),
                                    ),
                                  ),
                                  if (item.type == _MenuItemType.expandable)
                                    AnimatedRotation(
                                      turns: isExpanded(item) ? 0.5 : 0,
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeInOut,
                                      child: Icon(
                                        Icons.expand_more,
                                        color: sideFg,
                                        size: nav.expandIconSize,
                                      ),
                                    )
                                  else if (item.hasAddButton)
                                    Builder(builder: (ctx) {
                                      final section = _sectionForMenuItem(item, t);
                                      final canAdd = section != null && (widget.authStore.hasBusinessPermission(section, 'add'));
                                      if (!canAdd) return const SizedBox.shrink();
                                      return _sidebarAddAffordance(
                                        nav: nav,
                                        foreground: sideFg,
                                        background: sideFg.withValues(alpha: 0.1),
                                        onTap: () => openMenuAddAction(item),
                                      );
                                    }),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                      
                      // اضافه کردن Tooltip برای حالت Rail (عرض کم)
                      if (!railExtended) {
                        menuItemWidget = Tooltip(
                          message: item.label,
                          waitDuration: const Duration(milliseconds: 500),
                          child: menuItemWidget,
                        );
                      }
                      
                      return menuItemWidget;
                    }
                  }
                },
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            ],
            Expanded(child: content),
          ],
        ),
      ),
      );
    }

      return BusinessShellSideNavScope(
        desktopRailSupported: false,
        desktopRailVisible: false,
        setDesktopRailVisible: (_) {},
        child: Scaffold(
        appBar: preferredAppBar,
      drawer: Drawer(
        backgroundColor: sideBg,
        child: SafeArea(
          child: ListView(
            padding: nav.listPadding,
            children: [
              if (launcherHomePath != null) ...[
                ListTile(
                  leading: Icon(Icons.apps_rounded, color: sideFg, size: nav.parentIconExtended),
                  title: Text(
                    t.businessShellBackToLauncher,
                    style: nav.parentLabelStyle(textTheme, color: sideFg, active: true),
                  ),
                  onTap: () {
                    context.pop();
                    context.go(launcherHomePath);
                  },
                ),
                const Divider(),
              ],
              // آیتم‌های منو
              for (int i = 0; i < menuItems.length; i++) ...[
                Builder(builder: (ctx) {
                  final item = menuItems[i];
                  final bool active = i == selectedIndex;
                  
                  if (item.type == _MenuItemType.separator) {
                    // آیتم جداکننده در منوی موبایل
                    return Container(
                      margin: nav.separatorPaddingExtended,
                      child: Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: sideFg.withValues(alpha: 0.3),
                              thickness: 1,
                            ),
                          ),
                          SizedBox(width: nav.iconLabelGap),
                          Text(
                            item.label,
                            style: nav.separatorLabelStyle(
                              textTheme,
                              color: sideFg.withValues(alpha: 0.7),
                            ),
                          ),
                          SizedBox(width: nav.iconLabelGap),
                          Expanded(
                            child: Divider(
                              color: sideFg.withValues(alpha: 0.3),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  } else if (item.type == _MenuItemType.simple) {
                    final section = _sectionForMenuItem(item, t);
                    final canAdd = section != null && (widget.authStore.hasBusinessPermission(section, 'add'));
                    final chrome = _sidebarItemChrome(
                      item,
                      selected: active,
                      hovered: false,
                      fallbackFg: active ? activeFg : sideFg,
                      fallbackBg: active ? activeBg : Colors.transparent,
                    );
                    return ListTile(
                      leading: _buildSidebarMenuIcon(
                        item,
                        color: chrome.fg,
                        size: nav.iconSizeFor(extended: true, child: false),
                        active: active,
                      ),
                      title: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nav.parentLabelStyle(
                          textTheme,
                          color: chrome.fg,
                          active: active ||
                              context.shellColors.sidebarFooterForeground(item.key) != null,
                        ),
                      ),
                      selected: active,
                      tileColor: chrome.bg,
                      selectedTileColor: chrome.bg,
                      trailing: (item.hasAddButton && canAdd)
                          ? _sidebarAddAffordance(
                              nav: nav,
                              foreground: sideFg,
                              background: sideFg.withValues(alpha: 0.1),
                              onTap: () {
                                context.pop();
                                openMenuAddAction(item);
                              },
                            )
                          : null,
                      onTap: () {
                        context.pop();
                        onSelect(i);
                      },
                    );
                  } else if (item.type == _MenuItemType.expandable) {
                    // فیلتر کردن زیرآیتم‌ها بر اساس دسترسی
                    final visibleChildren = (item.children ?? []).where((child) => _hasAccessToMenuItem(child)).toList();
                    return ExpansionTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      tilePadding: nav.parentPaddingExtended,
                      childrenPadding: EdgeInsetsDirectional.only(start: nav.iconLabelGap),
                      leading: _buildSidebarMenuIcon(
                        item,
                        color: sideFg,
                        size: nav.iconSizeFor(extended: true, child: false),
                        active: false,
                      ),
                      title: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nav.parentLabelStyle(textTheme, color: sideFg, active: false),
                      ),
                      initiallyExpanded: isExpanded(item),
                      onExpansionChanged: (expanded) {
                        setState(() => _setExpandableMenuOpen(item, expanded));
                      },
                      children: visibleChildren.map((child) {
                        final childSection = _sectionForMenuItem(child, t);
                        final childCanAdd = child.hasAddButton && _canAddForSection(childSection);
                        return ListTile(
                        leading: SizedBox(width: nav.childIconExtended),
                        title: Text(
                          child.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nav.childLabelStyle(textTheme, color: sideFg, active: false),
                        ),
                        trailing: childCanAdd ? _sidebarAddAffordance(
                          nav: nav,
                          foreground: sideFg,
                          background: sideFg.withValues(alpha: 0.1),
                          onTap: () {
                            context.pop();
                            openMenuAddAction(child);
                          },
                        ) : null,
                        onTap: () {
                          context.pop();
                          onSelectChild(i, item.children!.indexOf(child));
                        },
                        );
                      }).toList(),
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ],
              
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(t.logout),
                onTap: onLogout,
              ),
            ],
          ),
        ),
      ),
      body: content,
    ),
      );
  }

  Future<void> _handleInvoiceWizardResult(WarehouseDocWizardResult wizardResult) async {
    if (wizardResult.invoiceId == null) return;
    
    final apiClient = ApiClient();
    final invoiceService = InvoiceService(apiClient: apiClient);
    
    bool loaderDismissed = false;
    void dismissLoader() {
      if (!loaderDismissed && mounted) {
        loaderDismissed = true;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).then((_) => loaderDismissed = true);

    try {
      final invoiceData = await invoiceService.getInvoice(
        businessId: widget.businessId,
        invoiceId: wizardResult.invoiceId!,
      );
      final warehouseService = WarehouseService(apiClient: apiClient);
      final quantitiesData = await warehouseService.getInvoiceLineQuantities(
        businessId: widget.businessId,
        invoiceId: wizardResult.invoiceId!,
      );
      dismissLoader();
      if (!mounted) return;
      
      final invoiceItem = Map<String, dynamic>.from(invoiceData['item'] ?? const {});
      final quantities = InvoiceLineQuantitiesIndex.fromApiResponse(quantitiesData);
      final initialLines = extractWarehouseLinesFromInvoice(
        invoiceItem,
        wizardResult.docType ?? 'issue',
        quantities: quantities,
      );
      
      if (initialLines.isEmpty) {
        SnackBarHelper.showInfo(
          context,
          message: 'هیچ کالایی برای این فاکتور ثبت نشده است',
        );
        return;
      }
      if (!quantities.hasAnyRemaining) {
        SnackBarHelper.showInfo(
          context,
          message: 'همه اقلام این فاکتور قبلاً حواله شده‌اند',
        );
        return;
      }
      
        final calendarController = widget.calendarController ?? await CalendarController.load();
        await showDialog(
          context: context,
          builder: (_) => WarehouseDocumentFormDialog(
            businessId: widget.businessId,
            calendarController: calendarController,
            initialDocType: wizardResult.docType,
            lockDocType: true,
            initialLines: initialLines,
            sourceInvoiceId: wizardResult.invoiceId,
            sourceInvoiceCode: wizardResult.invoiceCode,
            sourceInvoiceType: wizardResult.sourceLabel,
            onSuccess: () => _refreshCurrentPage(),
          ),
        );
    } catch (e) {
      dismissLoader();
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در دریافت فاکتور: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      dismissLoader();
    }
  }

  String _expandableMenuKey(_MenuItem item) {
    final key = item.key?.trim();
    if (key != null && key.isNotEmpty) return key;
    return item.label;
  }

  bool _isExpandableMenuOpen(_MenuItem item) =>
      _expandedMenuByKey[_expandableMenuKey(item)] ?? false;

  void _setExpandableMenuOpen(_MenuItem item, bool open) {
    _expandedMenuByKey[_expandableMenuKey(item)] = open;
  }

  void _toggleExpandableMenu(_MenuItem item) {
    final key = _expandableMenuKey(item);
    _expandedMenuByKey[key] = !(_expandedMenuByKey[key] ?? false);
  }

  Widget _sidebarAddAffordance({
    required AppShellNavMetrics nav,
    required Color foreground,
    required Color background,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(nav.addButtonRadius),
        ),
        child: SizedBox(
          width: nav.addButtonSize,
          height: nav.addButtonSize,
          child: Icon(Icons.add, size: nav.addIconSize, color: foreground),
        ),
      ),
    );
  }

  Widget _buildSidebarMenuIcon(
    _MenuItem item, {
    required Color color,
    required double size,
    required bool active,
  }) {
    if (item.key == 'telephony') {
      return BusinessShellTelephonyGlyph(
        color: color,
        size: size,
        filled: active,
      );
    }
    return Icon(
      active ? item.selectedIcon : item.icon,
      color: color,
      size: size,
    );
  }

  String _menuKey(_MenuItem item) {
    if (item.key != null && item.key!.trim().isNotEmpty) {
      return item.key!;
    }
    final p = item.path;
    if (p != null && p.trim().isNotEmpty) {
      final normalized = p.split('?').first;
      final tail = BusinessRoutePaths.stripBusinessPrefixAndTab(normalized, widget.businessId);
      if (tail.isNotEmpty) return tail;
    }
    if (item.type == _MenuItemType.expandable) {
      final children = item.children ?? const <_MenuItem>[];
      for (final child in children) {
        final kp = child.path;
        if (kp == null || kp.isEmpty) continue;
        final childTail = BusinessRoutePaths.stripBusinessPrefixAndTab(kp.split('?').first, widget.businessId);
        if (childTail.isNotEmpty) {
          final segment = childTail.split('/').first;
          if (segment.isNotEmpty) return 'group:$segment';
        }
      }
    }
    return 'label:${item.label.trim()}';
  }

  List<_MenuItem> _applyMenuPreferences(List<_MenuItem> items) {
    final hidden = _menuPreferences.hiddenKeys.toSet();

    List<_MenuItem> applyChildren(_MenuItem parent) {
      final children = parent.children ?? const <_MenuItem>[];
      if (children.isEmpty) return children;
      final parentKey = _menuKey(parent);
      final order = _menuPreferences.childrenOrder[parentKey] ?? const <String>[];
      final filtered = children.where((child) => !hidden.contains(_menuKey(child))).toList();
      if (order.isEmpty) return filtered;

      final byKey = <String, _MenuItem>{for (final it in filtered) _menuKey(it): it};
      final out = <_MenuItem>[];
      for (final key in order) {
        final found = byKey.remove(key);
        if (found != null) out.add(found);
      }
      out.addAll(byKey.values);
      return out;
    }

    final visibleRoot = items
        .where((item) =>
            item.type == _MenuItemType.separator || !hidden.contains(_menuKey(item)))
        .map((item) => item.type == _MenuItemType.expandable
            ? item.copyWith(children: applyChildren(item))
            : item)
        .toList();

    final order = _menuPreferences.rootOrder;
    if (order.isEmpty) return _pinSidebarFooterItems(visibleRoot);
    final byKey = <String, _MenuItem>{for (final it in visibleRoot) _menuKey(it): it};
    final nonSepKeys =
        byKey.entries.where((e) => e.value.type != _MenuItemType.separator).map((e) => e.key).toSet();
    // اگر ترجیحات قدیمی/ناسازگار باشند، ترتیب پیش‌فرض فعلی حفظ شود (جداکننده‌ها در محاسبه لحاظ نمی‌شوند).
    final knownNonSep =
        order.where(nonSepKeys.contains).length;
    final knownCount = knownNonSep;
    if (knownCount < 3 || knownCount * 3 < byKey.length) {
      return _pinSidebarFooterItems(visibleRoot);
    }
    final out = <_MenuItem>[];
    for (final key in order) {
      final found = byKey.remove(key);
      if (found != null) out.add(found);
    }
    out.addAll(byKey.values);
    return _pinSidebarFooterItems(out);
  }

  /// بازار افزونه‌ها و تنظیمات همیشه انتهای منوی کناری می‌مانند.
  List<_MenuItem> _pinSidebarFooterItems(List<_MenuItem> items) {
    const footerKeys = ['plugin-marketplace', 'settings'];
    final footer = <String, _MenuItem>{};
    final rest = <_MenuItem>[];
    for (final it in items) {
      final key = it.key;
      if (key != null && footerKeys.contains(key)) {
        footer[key] = it;
      } else {
        rest.add(it);
      }
    }
    for (final key in footerKeys) {
      final found = footer[key];
      if (found != null) rest.add(found);
    }
    return rest;
  }

  ({Color fg, Color bg}) _sidebarItemChrome(
    _MenuItem item, {
    required bool selected,
    required bool hovered,
    required Color fallbackFg,
    required Color fallbackBg,
  }) {
    final shell = context.shellColors;
    final fg = shell.sidebarFooterForeground(item.key);
    final fill = shell.sidebarFooterFill(item.key);
    if (fg == null || fill == null) {
      return (fg: fallbackFg, bg: fallbackBg);
    }
    final Color bg;
    if (selected) {
      bg = Color.alphaBlend(fg.withValues(alpha: 0.22), fill);
    } else if (hovered) {
      bg = Color.alphaBlend(fg.withValues(alpha: 0.10), fill);
    } else {
      bg = fill;
    }
    return (fg: fg, bg: bg);
  }

  // فیلتر کردن منو بر اساس دسترسی‌ها
  List<_MenuItem> _getFilteredMenuItems(List<_MenuItem> allItems) {
    
    final filteredItems = allItems.where((item) {
      if (item.type == _MenuItemType.separator) {
        return true;
      }
      
      if (item.type == _MenuItemType.simple) {
        final hasAccess = _hasAccessToMenuItem(item);
        return hasAccess;
      }
      
      if (item.type == _MenuItemType.expandable) {
        final hasAccess = _hasAccessToExpandableMenuItem(item);
        return hasAccess;
      }
      
      return false;
    }).toList();
    
    return filteredItems;
  }

  bool _hasAccessToMenuItem(_MenuItem item) {
    final t = AppLocalizations.of(context);
    final section = _sectionForMenuItem(item, t);

    if (item.path != null && item.path!.contains('/woocommerce')) {
      if (!_isWooCommerceHesabixPluginActive()) {
        return false;
      }
      if (widget.authStore.currentBusiness?.isOwner == true) {
        return true;
      }
      return widget.authStore.hasBusinessPermission('woocommerce', 'view');
    }

    if (item.path != null && item.path!.contains('/digipay')) {
      if (!_isDigipayPluginActive()) {
        return false;
      }
      if (widget.authStore.currentBusiness?.isOwner == true) {
        return true;
      }
      return widget.authStore.hasBusinessPermission('digipay', 'view');
    }

    if (item.path != null && item.path!.contains('/crm/web-chat')) {
      if (widget.authStore.currentBusiness?.isOwner == true) return true;
      return widget.authStore.canViewCrmWebChat();
    }
    
    // داشبورد اصلی کسب‌وکار همیشه قابل مشاهده است (داشبورد CRM تابع canReadSection('crm') است)
    if (item.path != null &&
        item.path!.endsWith('/dashboard') &&
        !item.path!.contains('/crm/')) {
      return true;
    }
    
    // بررسی فعال بودن پلاگین گارانتی
    if (section == 'warranty') {
      if (!_showPluginGatedMenu(_isWarrantyPluginActive())) {
        return false;
      }
    }
    
    // بررسی فعال بودن پلاگین تعمیرگاه
    if (section == 'repair_shop') {
      if (!_showPluginGatedMenu(_isRepairShopPluginActive())) {
        return false;
      }
    }

    // باشگاه مشتریان
    if (section == 'customer_club') {
      if (!_showPluginGatedMenu(_isCustomerClubPluginActive())) {
        return false;
      }
    }

    // پخش مویرگی
    if (section == 'distribution') {
      if (!_showPluginGatedMenu(_isDistributionPluginActive())) {
        return false;
      }
    }

    // حقوق و دستمزد
    if (section == 'payroll') {
      if (!_showPluginGatedMenu(_isPayrollPluginActive())) {
        return false;
      }
    }

    if (section == 'advanced_production') {
      if (!_showPluginGatedMenu(_isAdvancedProductionPluginActive())) {
        return false;
      }
    }

    if (section == 'office_automation') {
      if (!_showPluginGatedMenu(_isOfficeAutomationPluginActive())) {
        return false;
      }
    }

    if (section == 'fixed_assets') {
      if (!_showPluginGatedMenu(_isFixedAssetsPluginActive())) {
        return false;
      }
    }

    // طراحی برچسب بارکد
    if (section == 'barcode_labels') {
      if (!_showPluginGatedMenu(_isPluginCodeLicensed('barcode_label_studio'))) {
        return false;
      }
    }

    // مرکز تماس استریسک/ایزابل
    if (section == 'telephony') {
      if (!_showPluginGatedMenu(_isTelephonyPluginActive())) {
        return false;
      }
    }

    // اتصال باسلام
    if (section == 'basalam') {
      if (!_showPluginGatedMenu(_isBasalamPluginActive())) {
        return false;
      }
    }

    // سامانه مودیان
    if (section == 'moadian') {
      if (!_showPluginGatedMenu(_isMoadianPluginActive())) {
        return false;
      }
    }

    if (_isAdvancedAccountingMenuItem(item)) {
      if (!_showPluginGatedMenu(
        _isPluginCodeLicensed(kAdvancedAccountingPluginCode),
      )) {
        return false;
      }
    }
    
    // اگر سکشن تعریف نشده، نمایش داده نشود
    if (section == null) {
      return false;
    }
    
    // بررسی دسترسی‌های مختلف برای نمایش منو
    // اگر کاربر مالک است، همه منوها قابل مشاهده هستند
    if (_isBusinessOwner()) {
      return true;
    }
    
    // برای کاربران عضو، بررسی دسترسی
    // تنظیمات: نیازمند دسترسی join
    if (section == 'settings' && item.key == 'settings') {
      final hasJoin = widget.authStore.hasBusinessPermission('settings', 'join');
      final canManageDefaultShortcuts = widget.authStore.hasBusinessPermission(
        'quick_sales',
        'manage_default_payment_shortcuts',
      );
      return hasJoin || canManageDefaultShortcuts;
    }
    
    // استعلامات: نیازمند دسترسی read برای settings
    if (section == 'settings' && item.key == 'zohal/inquiries') {
      final hasRead = widget.authStore.hasBusinessPermission('settings', 'read') || 
                      widget.authStore.hasBusinessPermission('settings', 'join');
      return hasRead;
    }

    // سایر سکشن‌ها: بررسی دسترسی view
    final hasAccess = widget.authStore.canReadSection(section);
    
    // Debug: بررسی دقیق‌تر دسترسی‌ها
    // viewPerm is checked implicitly through hasAccess
    
    return hasAccess;
  }

  bool _hasAccessToExpandableMenuItem(_MenuItem item) {
    if (item.children == null) {
      return false;
    }
    
    
    // اگر حداقل یکی از زیرآیتم‌ها قابل دسترسی باشد، منو نمایش داده شود
    final hasAccess = item.children!.any((child) => _hasAccessToMenuItem(child));
    
    return hasAccess;
  }

  /// بررسی دسترسی افزودن برای یک سکشن (CRM از write و بقیه از add استفاده می‌کنند)
  bool _canAddForSection(String? section) {
    if (section == null) return false;
    if (section == 'crm') {
      return widget.authStore.hasBusinessPermission(section, 'write');
    }
    return widget.authStore.hasBusinessPermission(section, 'add');
  }

  // تبدیل کلید/برچسب منو به کلید سکشن دسترسی
  String? _sectionForMenuItem(_MenuItem item, AppLocalizations t) {
    final key = item.key;
    if (key != null) {
      if (key.startsWith('crm/') || key == 'group:crm') return 'crm';
      if (key.startsWith('ai/') || key == 'group:ai') return 'ai';
      if (key.startsWith('office-automation') || key == 'group:office-automation') {
        return 'office_automation';
      }
      switch (key) {
        case 'persons':
          return 'people';
        case 'products':
        case 'product-bundles':
        case 'catalog-spec-fields':
          return 'products';
        case 'categories':
          return 'categories';
        case 'product-attributes':
          return 'product_attributes';
        case 'barcode-labels':
          return 'barcode_labels';
        case 'accounts':
          return 'bank_accounts';
        case 'petty-cash':
          return 'petty_cash';
        case 'cash-box':
          return 'cash';
        case 'wallet':
          return 'wallet';
        case 'loan-facilities':
          return 'loan_facilities';
        case 'quick-sales':
        case 'invoice':
          return 'invoices';
        case 'receipts-payments':
          return 'people_transactions';
        case 'expense-income':
          return 'expenses_income';
        case 'transfers':
          return 'transfers';
        case 'checks':
          return 'checks';
        case 'documents':
          return 'accounting_documents';
        case 'chart-of-accounts':
          return 'chart_of_accounts';
        case 'opening-balance':
          return 'opening_balance';
        case 'year-end-closing':
          return 'fiscal_years';
        case 'currency-revaluation':
          return 'currency_revaluation';
        case 'reports':
        case 'hscript':
          return 'reports';
        case 'basalam':
          return 'basalam';
        case 'woocommerce':
          return 'woocommerce';
        case 'digipay':
          return 'digipay';
        case 'warehouses':
          return 'warehouses';
        case 'warehouse-docs':
        case 'stock-count':
          return 'warehouse_transfers';
        case 'quick-sales-stock-discrepancies':
        case 'production-orders':
          return 'inventory';
        case 'goods-expense-income':
          return 'goods_expense_income';
        case 'storage-files':
          return 'storage';
        case 'tax-workspace':
          return 'moadian';
        case 'workflows':
        case 'zohal/inquiries':
        case 'settings':
          return 'settings';
        case 'warranty':
          return 'warranty';
        case 'repair-shop':
          return 'repair_shop';
        case 'customer-club':
          return 'customer_club';
        case 'payroll':
          return 'payroll';
        case 'advanced-production':
          return 'advanced_production';
        case 'fixed-assets':
          return 'fixed_assets';
        case 'telephony':
          return 'telephony';
        case 'distribution':
          return 'distribution';
        case 'report-templates':
          return 'report_templates';
        case 'plugin-marketplace':
          return 'marketplace';
      }
    }
    final path = item.path;
    if (path != null) {
      if (path.contains('/report-templates')) return 'report_templates';
      if (path.contains('/hscript')) return 'reports';
      if (path.contains('/payroll')) return 'payroll';
      if (path.contains('/advanced-production')) return 'advanced_production';
      if (path.contains('/office-automation')) return 'office_automation';
      if (path.contains('/fixed-assets')) return 'fixed_assets';
      if (path.contains('/barcode-labels')) return 'barcode_labels';
      if (path.contains('/telephony')) return 'telephony';
      if (path.contains('/customer-club')) return 'customer_club';
      if (path.contains('/repair-shop')) return 'repair_shop';
      if (path.contains('/warranty')) return 'warranty';
      if (path.contains('/distribution')) return 'distribution';
      if (path.contains('/tax-workspace')) return 'moadian';
      if (path.contains('/crm/')) return 'crm';
      if (path.contains('/ai/')) return 'ai';
    }
    return _sectionForLabel(item.label, t);
  }

  // تبدیل برچسب محلی‌شده منو به کلید سکشن دسترسی (پشتیبان برای آیتم بدون کلید)
  String? _sectionForLabel(String label, AppLocalizations t) {
    if (label == t.reports || label == t.reportsHscriptTitle) return 'reports';
    if (label == t.people) return 'people';
    if (label == t.crmMenu ||
        label == t.crmMenuDashboard ||
        label == t.crmMenuProcessDefinitions ||
        label == t.crmMenuLeads ||
        label == t.crmMenuDeals ||
        label == t.crmMenuActivities ||
        label == t.crmMenuReports ||
        label == t.crmMenuNotesCalendar ||
        label == t.crmMenuWebChat ||
        label == t.crmMenuTasks ||
        label == t.crmMenuCustomer360 ||
        label == t.crmMenuSequences) {
      return 'crm';
    }
    if (label == t.products ||
        label == t.productBundlesMenu ||
        label == t.catalogSpecFieldsMenu) {
      return 'products';
    }
    if (label == t.categories) return 'categories';
    if (label == t.productAttributes) return 'product_attributes';
    if (label == t.accounts) return 'bank_accounts';
    if (label == t.pettyCash) return 'petty_cash';
    if (label == t.cashBox) return 'cash';
    if (label == t.wallet) return 'wallet';
    if (label == t.loanFacilities) return 'loan_facilities';
    if (label == t.checks) return 'checks';
    if (label == t.quickSalesMenu || label == t.invoice) return 'invoices';
    if (label == t.receiptsAndPayments) return 'people_transactions';
    if (label == t.expenseAndIncome) return 'expenses_income';
    if (label == t.transfers) return 'transfers';
    if (label == t.documents) return 'accounting_documents';
    if (label == t.yearEndClosing) return 'fiscal_years';
    if (label == t.chartOfAccounts) return 'chart_of_accounts';
    if (label == t.openingBalance) return 'opening_balance';
    if (label == t.currencyRevaluation) return 'currency_revaluation';
    if (label == t.warehouses) return 'warehouses';
    if (label == t.warehouseDocsMenu || label == t.stockCountMenu) {
      return 'warehouse_transfers';
    }
    if (label == t.quickSalesStockDiscrepanciesMenu ||
        label == t.productionOrdersMenu) {
      return 'inventory';
    }
    if (label == t.goodsExpenseIncomeMenu) return 'goods_expense_income';
    if (label == t.storageSpace) return 'storage';
    if (label == t.taxpayers) return 'moadian';
    if (label == t.settings || label == t.inquiries || label == t.workflows) {
      return 'settings';
    }
    if (label == t.templates) return 'report_templates';
    if (label == t.pluginMarketplace) return 'marketplace';
    if (label == t.warranty) return 'warranty';
    if (label == t.repairShopMenu) return 'repair_shop';
    if (label == t.customerClubMenu) return 'customer_club';
    if (label == t.payrollMenu || label == t.payrollTitle) return 'payroll';
    if (label == t.advancedProductionMenu || label == t.advancedProductionTitle) {
      return 'advanced_production';
    }
    if (label == t.oaMenu ||
        label == t.oaOrg ||
        label == t.oaCartable ||
        label == t.oaExternalOrgs ||
        label == t.oaArchiveTree ||
        label == t.oaReports) {
      return 'office_automation';
    }
    if (label == t.fixedAssetsMenu || label == t.fixedAssetsTitle) {
      return 'fixed_assets';
    }
    if (label == t.distributionMenu) return 'distribution';
    if (label == t.telephonyMenu) return 'telephony';
    if (label == t.basalamIntegrationMenuTitle) return 'basalam';
    if (label == t.woocommerceIntegrationMenuTitle) return 'woocommerce';
    if (label == t.digipayMenuTitle) return 'digipay';
    if (label == t.aiMenu ||
        label == t.aiAssistantMenu ||
        label == t.aiSubscriptionMenu ||
        label == t.aiUsageMenu ||
        label == t.aiSkillsMarketplaceMenu ||
        label == t.aiSkillsPublisherMenu) {
      return 'ai';
    }
    return null;
  }

}

enum _MenuItemType { simple, expandable, separator }

class _MenuItem {
  final String? key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? path;
  final _MenuItemType type;
  final List<_MenuItem>? children;
  final bool hasAddButton;
  
  const _MenuItem({
    this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.path,
    required this.type,
    this.children,
    this.hasAddButton = false,
  });

  _MenuItem copyWith({
    String? key,
    String? label,
    IconData? icon,
    IconData? selectedIcon,
    String? path,
    _MenuItemType? type,
    List<_MenuItem>? children,
    bool? hasAddButton,
  }) {
    return _MenuItem(
      key: key ?? this.key,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      selectedIcon: selectedIcon ?? this.selectedIcon,
      path: path ?? this.path,
      type: type ?? this.type,
      children: children ?? this.children,
      hasAddButton: hasAddButton ?? this.hasAddButton,
    );
  }
}
