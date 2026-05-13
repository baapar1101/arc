import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/woocommerce_integration_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

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
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
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
    final fa = t.localeName.startsWith('fa');
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _infoCard(theme, t.reportsWooRecentOrdersTitle, Icons.shopping_bag_outlined,
                  '${s['orders_total'] ?? 0}'),
              _infoCard(theme, t.reportsWooCatalogTitle, Icons.inventory_2_outlined,
                  '${s['products_total'] ?? 0}'),
              _infoCard(theme, fa ? 'مشتریان' : 'Customers', Icons.people_outline, '${s['customers_total'] ?? 0}'),
              _infoCard(theme, fa ? 'سفارش ۷ روز اخیر' : 'Orders (7d)', Icons.trending_up, '${s['orders_last_7_days'] ?? 0}'),
              _infoCard(theme, fa ? 'ذخیرهٔ سفارش' : 'Order storage', Icons.storage, '${s['orders_storage'] ?? '-'}'),
            ],
          ),
          if (remote.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t.reportsWooBridgeTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _infoCard(theme, fa ? 'نسخهٔ پل' : 'Bridge', Icons.hub, '${remote['bridge_version'] ?? '-'}'),
                _infoCard(theme, 'WooCommerce', Icons.shopping_cart, '${remote['wc_version'] ?? '-'}'),
                _infoCard(theme, 'WordPress', Icons.language, '${remote['wp_version'] ?? '-'}'),
                _infoCard(theme, fa ? 'افزونهٔ ArcWOC' : 'ArcWOC plugin', Icons.extension, '${remote['plugin_version'] ?? '-'}'),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text('${t.reportsWooOverviewTitle} · ${t.reportsWooOverviewSubtitle}',
              style: theme.textTheme.titleSmall),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsWooRecentOrdersTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : _rows.isEmpty
                    ? Center(child: Text(t.reportsSearchNoResults))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('#')),
                            DataColumn(label: Text('status')),
                            DataColumn(label: Text('total')),
                            DataColumn(label: Text('email')),
                          ],
                          rows: _rows
                              .map(
                                (r) => DataRow(
                                  cells: [
                                    DataCell(Text('${r['id'] ?? ''}')),
                                    DataCell(Text('${r['number'] ?? ''}')),
                                    DataCell(Text('${r['status'] ?? ''}')),
                                    DataCell(Text('${r['total'] ?? ''}')),
                                    DataCell(Text('${r['billing_email'] ?? ''}')),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsWooCatalogTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : _rows.isEmpty
                    ? Center(child: Text(t.reportsSearchNoResults))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('name')),
                            DataColumn(label: Text('SKU')),
                            DataColumn(label: Text('price')),
                          ],
                          rows: _rows
                              .map(
                                (r) => DataRow(
                                  cells: [
                                    DataCell(Text('${r['id'] ?? ''}')),
                                    DataCell(Text('${r['name'] ?? ''}')),
                                    DataCell(Text('${r['sku'] ?? ''}')),
                                    DataCell(Text('${r['price'] ?? ''}')),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsWooBridgeTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final e in (_remote ?? {}).entries)
                        Card(
                          child: ListTile(
                            title: Text(e.key, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                            subtitle: Text('${e.value}', style: theme.textTheme.bodyMedium),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
