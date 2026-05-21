import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../core/business_nav.dart';
import '../../core/business_named_route_locations.dart';
import '../../services/marketplace_service.dart';
import '../../services/wallet_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/responsive_helper.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/marketplace/plugin_catalog_card.dart';
import '../../widgets/marketplace/plugin_detail_sheet.dart';
import '../../widgets/marketplace/plugin_marketplace_empty_state.dart';
import '../../widgets/marketplace/plugin_marketplace_hero.dart';
import '../../widgets/marketplace/plugin_marketplace_skeleton.dart';
import '../../widgets/marketplace/plugin_marketplace_utils.dart';
import '../../widgets/marketplace/plugin_purchase_confirm_dialog.dart';
import '../../widgets/marketplace/plugin_wallet_banner.dart';
import '../../widgets/wallet/wallet_top_up_dialog.dart';

class PluginMarketplacePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  /// مسیر نسبی بازگشت پس از خرید (مثلاً tax-workspace) از query پارامتر returnTo
  final String? returnToPath;

  const PluginMarketplacePage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.returnToPath,
  });

  @override
  State<PluginMarketplacePage> createState() => _PluginMarketplacePageState();
}

class _PluginMarketplacePageState extends State<PluginMarketplacePage> with SingleTickerProviderStateMixin {
  final MarketplaceService _marketplace = MarketplaceService();
  final WalletService _wallet = WalletService(ApiClient());

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _plugins = const [];
  Map<String, dynamic>? _walletOverview;
  List<Map<String, dynamic>> _businessPlugins = const [];
  String? _categoryFilter;
  int _hiddenNoPlansCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isCatalogTab => _tabController.index == 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _marketplace.listPlugins();
      final overview = await _wallet.getOverview(businessId: widget.businessId);
      final businessPlugins = await _marketplace.listBusinessPlugins(businessId: widget.businessId);
      var hidden = 0;
      for (final p in items) {
        final plans = (p['plans'] as List?) ?? const [];
        if (plans.isEmpty) hidden++;
      }
      if (!mounted) return;
      setState(() {
        _plugins = items;
        _walletOverview = overview;
        _businessPlugins = businessPlugins.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _hiddenNoPlansCount = hidden;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${AppLocalizations.of(context).pluginMarketplaceError}: ${ErrorExtractor.forContext(e, context)}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _walletCurrency => walletCurrencySymbol(_walletOverview);

  double get _availableBalance => (_walletOverview?['available_balance'] ?? 0).toDouble();

  bool get _canBuy => widget.authStore.hasBusinessPermission('marketplace', 'buy');

  bool get _canViewInvoices =>
      widget.authStore.hasBusinessPermission('marketplace', 'invoices') ||
      widget.authStore.hasBusinessPermission('marketplace', 'view');

  List<Map<String, dynamic>> get _visiblePlugins {
    return _plugins.where((p) {
      final plans = (p['plans'] as List?) ?? const [];
      return plans.isNotEmpty;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredPlugins({required bool myTab}) {
    final q = _searchController.text.trim().toLowerCase();
    Iterable<Map<String, dynamic>> list = _visiblePlugins;

    if (myTab) {
      final licensedIds = _businessPlugins
          .where((bp) => bp.isNotEmpty)
          .map((bp) => (bp['plugin_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      list = list.where((p) => licensedIds.contains((p['id'] as num?)?.toInt()));
    }

    if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
      list = list.where((p) => p['category'] == _categoryFilter);
    }

    if (q.isNotEmpty) {
      list = list.where((p) {
        final name = (p['name'] ?? '').toString().toLowerCase();
        final desc = (p['description'] ?? '').toString().toLowerCase();
        final code = (p['code'] ?? '').toString().toLowerCase();
        return name.contains(q) || desc.contains(q) || code.contains(q);
      });
    }

    return list.toList();
  }

  double? get _globalCheapestPlan {
    double? min;
    for (final p in _visiblePlugins) {
      final plans = (p['plans'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final c = cheapestPlanPrice(plans);
      if (c != null && (min == null || c < min)) min = c;
    }
    return min;
  }

  int get _activePluginCount {
    return _businessPlugins.where((bp) => bp['is_active'] == true || bp['is_trial'] == true).length;
  }

  Future<void> _startTrial(int pluginId) async {
    final t = AppLocalizations.of(context);
    if (!_canBuy) {
      SnackBarHelper.show(context, message: t.pluginMarketplaceNoPermissionBuy);
      return;
    }
    setState(() => _busy = true);
    try {
      await _marketplace.startTrial(businessId: widget.businessId, pluginId: pluginId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.pluginMarketplaceTrialSuccess);
      await _load();
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: _trialErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _trialErrorMessage(Object e) {
    final t = AppLocalizations.of(context);
    final raw = e.toString();
    if (raw.contains('TRIAL_ALREADY_USED')) return t.pluginMarketplaceStatusTrialExpired;
    if (raw.contains('TRIAL_NOT_ALLOWED')) return t.pluginMarketplaceStatusTrialExpired;
    if (raw.contains('PLUGIN_ALREADY_ACTIVE')) return t.pluginMarketplaceStatusActive;
    return '${t.pluginMarketplaceError}: ${ErrorExtractor.forContext(e, context)}';
  }

  Future<void> _purchase(int pluginId, int planId) async {
    final t = AppLocalizations.of(context);
    if (!_canBuy) {
      SnackBarHelper.show(context, message: t.pluginMarketplaceNoPermissionBuy);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await _marketplace.purchase(
        businessId: widget.businessId,
        pluginId: pluginId,
        planId: planId,
      );
      if (!mounted) return;
      final status = (res['status'] ?? '').toString();
      if (status == 'paid') {
        await _showPurchaseSuccess(pluginId: pluginId);
        await _load();
      } else if (status == 'insufficient_funds') {
        await _showInsufficientFunds(res);
      } else {
        SnackBarHelper.show(context, message: '${t.pluginMarketplaceError}: $status');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: _purchaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _purchaseErrorMessage(Object e) {
    final t = AppLocalizations.of(context);
    final raw = e.toString();
    if (raw.contains('PLUGIN_NOT_FOUND')) return t.pluginMarketplaceError;
    if (raw.contains('PLAN_NOT_FOUND')) return t.pluginMarketplaceError;
    return '${t.pluginMarketplaceError}: ${ErrorExtractor.forContext(e, context)}';
  }

  Future<void> _showInsufficientFunds(Map<String, dynamic> res) async {
    final t = AppLocalizations.of(context);
    final required = (res['required_amount'] ?? 0).toDouble();
    final available = (res['available_amount'] ?? 0).toDouble();
    final shortfall = (res['shortfall'] ?? 0).toDouble();
    final sym = _walletCurrency;

    final goWallet = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.pluginMarketplaceInsufficientFundsTitle),
        content: Text(
          t.pluginMarketplaceInsufficientFundsBody(
            formatWithThousands(required, decimalPlaces: 0) + ' $sym',
            formatWithThousands(available, decimalPlaces: 0) + ' $sym',
            formatWithThousands(shortfall, decimalPlaces: 0) + ' $sym',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.pluginMarketplaceWalletTopUp),
          ),
        ],
      ),
    );
    if (goWallet == true && mounted) {
      await WalletTopUpDialog.show(
        context: context,
        businessId: widget.businessId,
        currencyLabel: sym,
        onSuccess: _load,
      );
    }
  }

  Future<void> _showPurchaseSuccess({required int pluginId}) async {
    final t = AppLocalizations.of(context);
    Map<String, dynamic>? plugin;
    for (final p in _visiblePlugins) {
      if ((p['id'] as num?)?.toInt() == pluginId) {
        plugin = p;
        break;
      }
    }
    final code = plugin?['code']?.toString();
    final setupRoute = code != null ? pluginSetupRouteByCode[code] : null;
    final hasReturn = widget.returnToPath != null && widget.returnToPath!.trim().isNotEmpty;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: Theme.of(ctx).colorScheme.primary, size: 40),
        title: Text(t.pluginMarketplacePurchaseSuccess),
        content: Text(t.pluginMarketplacePaymentFromWallet),
        actions: [
          if (hasReturn)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go(context.businessPanelUrl(widget.businessId, widget.returnToPath!.trim()));
              },
              child: Text(t.pluginMarketplaceReturnToPrevious),
            ),
          if (setupRoute != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                BusinessNamedRoutes.goNamed(
                  context,
                  businessId: widget.businessId,
                  routeName: setupRoute,
                );
              },
              child: Text(t.pluginMarketplaceConfigurePlugin),
            )
          else
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
        ],
      ),
    );
  }

  Future<void> _confirmAndPurchase({
    required Map<String, dynamic> plugin,
    required Map<String, dynamic> plan,
  }) async {
    final t = AppLocalizations.of(context);
    final pluginId = plugin['id'] as int;
    final planId = plan['id'] as int;
    final pluginName = (plugin['name'] ?? '-') as String;
    final period = plan['period']?.toString();
    final price = (plan['price'] ?? 0).toDouble();
    final currencySymbol = currencySymbolFromPlan(plan, _walletCurrency);

    final confirmed = await PluginPurchaseConfirmDialog.show(
      context,
      pluginName: pluginName,
      periodLabel: pluginPeriodLabel(t, period),
      price: price,
      currencySymbol: currencySymbol,
      walletBalance: _availableBalance,
      walletCurrency: _walletCurrency,
    );
    if (confirmed == true) {
      await _purchase(pluginId, planId);
    }
  }

  void _openPluginDetail(Map<String, dynamic> plugin) {
    final pluginId = (plugin['id'] as num?)?.toInt() ?? 0;
    final status = businessPluginForId(_businessPlugins, pluginId);
    final trialAllowed = plugin['trial_allowed'] == true;
    final trialDays = plugin['trial_days'] as int?;

    PluginDetailSheet.show(
      context,
      plugin: plugin,
      pluginStatus: status,
      walletCurrency: _walletCurrency,
      canBuy: _canBuy,
      trialAllowed: trialAllowed,
      trialDays: trialDays,
      hasUsedTrial: hasUsedTrial(status),
      onStartTrial: trialAllowed && !hasUsedTrial(status)
          ? () => _startTrial(pluginId)
          : null,
      onPurchasePlan: (pl) {
        Navigator.of(context).pop();
        _confirmAndPurchase(plugin: plugin, plan: pl);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (!widget.authStore.hasBusinessPermission('marketplace', 'view')) {
      return Scaffold(
        appBar: AppBar(title: Text(t.pluginMarketplace)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(t.pluginMarketplaceNoPermissionView, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pluginMarketplace),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.pluginMarketplaceBrowseTab),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.pluginMarketplaceMyPluginsTab),
                  if (_activePluginCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(
                      label: Text('$_activePluginCount'),
                      backgroundColor: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.pluginMarketplaceRefresh,
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _error != null && !_loading
                    ? _ErrorBody(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            const SliverToBoxAdapter(child: PluginMarketplaceHero()),
                            if (!_loading && _walletOverview != null)
                              SliverToBoxAdapter(
                                child: PluginWalletBanner(
                                  businessId: widget.businessId,
                                  availableBalance: _availableBalance,
                                  currencySymbol: _walletCurrency,
                                  cheapestPlanPrice: _globalCheapestPlan,
                                  canViewInvoices: _canViewInvoices,
                                  onAfterTopUp: _load,
                                ),
                              ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              sliver: SliverToBoxAdapter(child: _buildSearchAndFilters(t, catalogTab: _isCatalogTab)),
                            ),
                            if (_isCatalogTab && _hiddenNoPlansCount > 0)
                              SliverPadding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                sliver: SliverToBoxAdapter(
                                  child: Text(
                                    t.pluginMarketplaceNoPlansHidden,
                                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                            if (_loading)
                              const SliverToBoxAdapter(child: PluginMarketplaceSkeleton())
                            else
                              _buildPluginGrid(t),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          if (_busy && !_loading)
            const Positioned.fill(
              child: IgnorePointer(
                child: ModalBarrier(dismissible: false, color: Color(0x22000000)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPluginGrid(AppLocalizations t) {
    final items = _filteredPlugins(myTab: !_isCatalogTab);
    if (items.isEmpty) {
      return SliverFillRemaining(
        child: PluginMarketplaceEmptyState(
          myPluginsTab: !_isCatalogTab,
          onRefresh: _load,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.crossAxisExtent;
          final crossAxisCount = w >= ResponsiveHelper.shellNavigationRailExtendedMinWidth
              ? 3
              : w >= 720
                  ? 2
                  : 1;

          if (crossAxisCount == 1) {
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (c, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < items.length - 1 ? 12 : 0),
                  child: _cardFor(items[i]),
                ),
                childCount: items.length,
              ),
            );
          }

          const double rowGap = 14;
          final cellW = (w - rowGap * (crossAxisCount - 1)) / crossAxisCount;
          final rowCount = (items.length + crossAxisCount - 1) ~/ crossAxisCount;
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (c, row) {
                return Padding(
                  padding: EdgeInsets.only(bottom: row < rowCount - 1 ? rowGap : 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int col = 0; col < crossAxisCount; col++) ...[
                        if (col > 0) const SizedBox(width: rowGap),
                        SizedBox(
                          width: cellW,
                          child: row * crossAxisCount + col >= items.length
                              ? const SizedBox.shrink()
                              : _cardFor(items[row * crossAxisCount + col]),
                        ),
                      ],
                    ],
                  ),
                );
              },
              childCount: rowCount,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchAndFilters(AppLocalizations t, {required bool catalogTab}) {
    final cs = Theme.of(context).colorScheme;
    final categories = <String?>[null, ...kPluginMarketplaceCategories];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            labelText: t.pluginMarketplaceSearchHint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() {}),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (_) => setState(() {}),
          onChanged: (_) => setState(() {}),
        ),
        if (catalogTab) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final selected = _categoryFilter == cat;
                final label = cat == null ? t.pluginMarketplaceCategoryAll : pluginCategoryLabel(t, cat);
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() => _categoryFilter = cat),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cardFor(Map<String, dynamic> plugin) {
    final pluginId = (plugin['id'] as num?)?.toInt() ?? 0;
    final status = businessPluginForId(_businessPlugins, pluginId);
    return PluginCatalogCard(
      plugin: plugin,
      pluginStatus: status,
      walletCurrency: _walletCurrency,
      trialAllowed: plugin['trial_allowed'] == true,
      trialDays: plugin['trial_days'] as int?,
      onOpen: () => _openPluginDetail(plugin),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 56, color: cs.error),
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(t.pluginMarketplaceRetry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
