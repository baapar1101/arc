import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/business_nav.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/woocommerce_integration_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';

String _wooBridgeFieldTitle(AppLocalizations t, String key) {
  switch (key) {
    case 'bridge_version':
      return t.wooBridgeFieldBridgeVersion;
    case 'wc_version':
      return t.wooBridgeFieldWcVersion;
    case 'wp_version':
      return t.wooBridgeFieldWpVersion;
    case 'plugin_version':
      return t.wooBridgeFieldPluginVersion;
    default:
      return t.wooBridgeFieldGenericTitle(key);
  }
}

Widget _reportsWooSettingsPromoCard(BuildContext context, int businessId) {
  final t = AppLocalizations.of(context);
  final theme = Theme.of(context);
  return Card(
    child: ListTile(
      leading: Icon(
        Icons.settings_suggest_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(t.reportsWooSettingsPromoTitle),
      subtitle: Text(t.reportsWooSettingsPromoSubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
            context.businessPanelUrl(businessId, 'settings/woocommerce'),
          ),
    ),
  );
}

List<Widget> _reportsWooAppBarActions(
  BuildContext context,
  AppLocalizations t,
  int businessId,
  VoidCallback onRefresh,
) {
  return [
    IconButton(
      tooltip: t.woocommerceGoToSettingsTooltip,
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => context.push(
            context.businessPanelUrl(businessId, 'settings/woocommerce'),
          ),
    ),
    IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh)),
  ];
}

class WooCommerceReportsOverviewPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const WooCommerceReportsOverviewPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<WooCommerceReportsOverviewPage> createState() => _WooCommerceReportsOverviewPageState();
}

class _WooCommerceReportsOverviewPageState extends State<WooCommerceReportsOverviewPage> {
  final _svc = WoocommerceIntegrationService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _healthWrap;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _svc.reportsSummary(businessId: widget.businessId);
      Map<String, dynamic>? health;
      try {
        health = await _svc.testBridge(businessId: widget.businessId);
      } catch (_) {
        health = null;
      }
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _healthWrap = health;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsWooOverviewTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: _reportsWooAppBarActions(context, t, widget.businessId, _load),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : _buildBody(context, theme, t),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, AppLocalizations t) {
    final s = _summary ?? const <String, dynamic>{};
    final counts = (s['counts_by_status'] is Map)
        ? Map<String, dynamic>.from(s['counts_by_status'] as Map)
        : const <String, dynamic>{};
    final remote = (_healthWrap?['remote'] is Map)
        ? Map<String, dynamic>.from(_healthWrap!['remote'] as Map)
        : const <String, dynamic>{};

    final entries = counts.entries.where((e) => (e.value as num?)?.toDouble() != 0).toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _reportsWooSettingsPromoCard(context, widget.businessId),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _infoCard(theme, t.reportsWooRecentOrdersTitle, Icons.shopping_bag_outlined,
                  '${s['orders_total'] ?? 0}'),
              _infoCard(theme, t.reportsWooCatalogTitle, Icons.inventory_2_outlined,
                  '${s['products_total'] ?? 0}'),
              _infoCard(theme, t.reportsWooStatCustomers, Icons.people_outline, '${s['customers_total'] ?? 0}'),
              _infoCard(theme, t.reportsWooStatOrders7d, Icons.trending_up, '${s['orders_last_7_days'] ?? 0}'),
              _infoCard(theme, t.reportsWooStatOrderStorage, Icons.storage, '${s['orders_storage'] ?? '-'}'),
            ],
          ),
          if (remote.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t.reportsWooBridgeTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(t.reportsWooBridgeSubtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _infoCard(theme, t.reportsWooStatBridgeVersion, Icons.hub, '${remote['bridge_version'] ?? '-'}'),
                _infoCard(theme, t.reportsWooStatWcVersion, Icons.shopping_cart, '${remote['wc_version'] ?? '-'}'),
                _infoCard(theme, t.reportsWooStatWpVersion, Icons.language, '${remote['wp_version'] ?? '-'}'),
                _infoCard(theme, t.reportsWooStatPluginVersion, Icons.extension, '${remote['plugin_version'] ?? '-'}'),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text(
            t.reportsWooOverviewChartCaption(t.reportsWooOverviewTitle, t.reportsWooOverviewSubtitle),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(t.reportsSearchNoResults, style: TextStyle(color: theme.colorScheme.outline))
          else
            SizedBox(
              height: 240,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: [
                          for (int i = 0; i < entries.length; i++)
                            PieChartSectionData(
                              value: (entries[i].value as num).toDouble(),
                              title: '',
                              radius: 52,
                              color: _chartColor(theme, i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.circle, size: 12, color: _chartColor(theme, i)),
                          title: Text(e.key, style: const TextStyle(fontSize: 13)),
                          trailing: Text('${e.value}'),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _chartColor(ThemeData theme, int i) {
    final colors = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      Colors.teal,
      Colors.deepOrange,
      Colors.indigo,
    ];
    return colors[i % colors.length];
  }

  Widget _infoCard(ThemeData theme, String title, IconData icon, String value) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(height: 8),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class WooCommerceRecentOrdersReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const WooCommerceRecentOrdersReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<WooCommerceRecentOrdersReportPage> createState() => _WooCommerceRecentOrdersReportPageState();
}

class _WooCommerceRecentOrdersReportPageState extends State<WooCommerceRecentOrdersReportPage> {
  final _svc = WoocommerceIntegrationService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  int _dataEpoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _svc.listOrders(businessId: widget.businessId, page: 1, perPage: 50);
      final items = raw['items'];
      final list = items is List
          ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
        _dataEpoch++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  DataTableConfig<Map<String, dynamic>> _tableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/_local/woocommerce/recent-orders',
      tableId: 'woo_report_recent_orders',
      title: t.reportsWooRecentOrdersTitle,
      subtitle: t.reportsWooTableHintOrders,
      columns: [
        TextColumn('id', t.woocommerceColumnOrderId),
        TextColumn('number', t.woocommerceColumnOrderNumber),
        TextColumn('status', t.woocommerceColumnOrderStatus),
        TextColumn('total', t.woocommerceColumnOrderTotal),
        TextColumn('billing_email', t.woocommerceColumnBillingEmail),
      ],
      searchFields: const ['id', 'number', 'status', 'billing_email', 'total'],
      showFilters: false,
      showPagination: true,
      showRefreshButton: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      defaultPageSize: 20,
      enableColumnSettings: true,
      showColumnSearch: false,
      emptyStateMessage: t.reportsSearchNoResults,
      minTableWidth: 640,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsWooRecentOrdersTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: _reportsWooAppBarActions(context, t, widget.businessId, _load),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _reportsWooSettingsPromoCard(context, widget.businessId),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          t.reportsWooTableHintOrders,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: DataTableWidget<Map<String, dynamic>>(
                            key: ValueKey(_dataEpoch),
                            config: _tableConfig(t),
                            fromJson: (json) => Map<String, dynamic>.from(json as Map),
                            calendarController: widget.calendarController,
                            localRawItems: _rows,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class WooCommerceCatalogReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const WooCommerceCatalogReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<WooCommerceCatalogReportPage> createState() => _WooCommerceCatalogReportPageState();
}

class _WooCommerceCatalogReportPageState extends State<WooCommerceCatalogReportPage> {
  final _svc = WoocommerceIntegrationService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  int _dataEpoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _svc.listProducts(businessId: widget.businessId, page: 1, perPage: 50);
      final items = raw['items'];
      final list = items is List
          ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
        _dataEpoch++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  DataTableConfig<Map<String, dynamic>> _tableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/_local/woocommerce/catalog',
      tableId: 'woo_report_catalog',
      title: t.reportsWooCatalogTitle,
      subtitle: t.reportsWooTableHintCatalog,
      columns: [
        TextColumn('id', t.woocommerceColumnProductId),
        TextColumn('name', t.woocommerceColumnProductName),
        TextColumn('sku', t.woocommerceColumnSku),
        TextColumn('type', t.woocommerceColumnProductType),
        TextColumn('price', t.woocommerceColumnPrice),
      ],
      searchFields: const ['id', 'name', 'sku', 'type', 'price'],
      showFilters: false,
      showPagination: true,
      showRefreshButton: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      defaultPageSize: 20,
      enableColumnSettings: true,
      showColumnSearch: false,
      emptyStateMessage: t.reportsSearchNoResults,
      minTableWidth: 640,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsWooCatalogTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: _reportsWooAppBarActions(context, t, widget.businessId, _load),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _reportsWooSettingsPromoCard(context, widget.businessId),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          t.reportsWooTableHintCatalog,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: DataTableWidget<Map<String, dynamic>>(
                            key: ValueKey(_dataEpoch),
                            config: _tableConfig(t),
                            fromJson: (json) => Map<String, dynamic>.from(json as Map),
                            calendarController: widget.calendarController,
                            localRawItems: _rows,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class WooCommerceBridgeHealthReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const WooCommerceBridgeHealthReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<WooCommerceBridgeHealthReportPage> createState() => _WooCommerceBridgeHealthReportPageState();
}

class _WooCommerceBridgeHealthReportPageState extends State<WooCommerceBridgeHealthReportPage> {
  final _svc = WoocommerceIntegrationService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _remote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wrap = await _svc.testBridge(businessId: widget.businessId);
      final inner = wrap['remote'];
      if (!mounted) return;
      setState(() {
        _remote = inner is Map ? Map<String, dynamic>.from(inner) : const {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final keys = (_remote ?? {}).keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsWooBridgeTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: _reportsWooAppBarActions(context, t, widget.businessId, _load),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _reportsWooSettingsPromoCard(context, widget.businessId),
                      const SizedBox(height: 8),
                      Text(t.reportsWooBridgeTableHint, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      for (final k in keys)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(_wooBridgeFieldTitle(t, k)),
                            subtitle: SelectableText(
                              '${_remote![k]}',
                              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
