import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/basalam_integration_service.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:fl_chart/fl_chart.dart';

class BasalamReportsOverviewPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const BasalamReportsOverviewPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<BasalamReportsOverviewPage> createState() =>
      _BasalamReportsOverviewPageState();
}

class _BasalamReportsOverviewPageState extends State<BasalamReportsOverviewPage> {
  final _svc = BasalamIntegrationService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _payload;

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
      final d = await _svc.getReportsOverview(
        businessId: widget.businessId,
        chartDays: 90,
      );
      if (!mounted) return;
      setState(() {
        _payload = d;
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
        title: Text(t.reportsBasalamOverviewTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!),
                    ),
                  )
                : _buildBody(context, theme, t),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    AppLocalizations t,
  ) {
    final summary = (_payload?['summary'] is Map)
        ? _payload!['summary'] as Map<String, dynamic>
        : <String, dynamic>{};
    final rawDays = _payload?['orders_by_day'];
    final days =
        rawDays is List ? rawDays.cast<dynamic>() : const <dynamic>[];

    final chartPoints =
        days.length > 45 ? days.sublist(days.length - 45) : days;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _infoCard(
                theme,
                t.basalamReportsOverviewCardIntegration,
                Icons.power_settings_new,
                summary['integration_enabled'] == true
                    ? t.basalamReportsOverviewStateOn
                    : t.basalamReportsOverviewStateOff,
              ),
              _infoCard(
                theme,
                t.basalamReportsOverviewCardWebhook,
                Icons.webhook,
                summary['webhook_enabled'] == true
                    ? t.basalamReportsOverviewStateOn
                    : t.basalamReportsOverviewStateOff,
              ),
              _infoCard(
                theme,
                t.basalamReportsOverviewCardDlq,
                Icons.warning_amber_outlined,
                '${summary['dead_letter_count'] ?? 0}',
              ),
              _infoCard(
                theme,
                t.reportsBasalamProductConflictsTitle,
                Icons.merge_type,
                '${summary['pending_product_conflicts_count'] ?? 0}',
              ),
              _infoCard(
                theme,
                t.reportsBasalamSyncedInvoicesTitle,
                Icons.receipt_long,
                '${summary['basalam_invoices_in_period'] ?? 0}',
              ),
              _infoCard(
                theme,
                t.basalamReportsOverviewCardNetPeriod,
                Icons.payments_outlined,
                '${summary['basalam_invoices_net_sum_in_period'] ?? 0}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(t.reportsBasalamOverviewSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 8),
          Text(t.reportsBasalamOverviewTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (chartPoints.isEmpty)
            Text(
              t.reportsSearchNoResults,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: math.max(
                    1,
                    chartPoints.fold<double>(0.0, (m, e) {
                      final c = (e is Map)
                          ? (e['count'] as num?)?.toDouble() ?? 0.0
                          : 0.0;
                      return c > m ? c : m;
                    }),
                  ),
                  barGroups: [
                    for (int i = 0; i < chartPoints.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: (chartPoints[i] is Map)
                                ? ((chartPoints[i] as Map)['count'] as num?)
                                        ?.toDouble() ??
                                    0.0
                                : 0.0,
                            width: 6,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, m) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= chartPoints.length) {
                            return const SizedBox.shrink();
                          }
                          final d = (chartPoints[idx] is Map)
                              ? (chartPoints[idx] as Map)['date']?.toString() ??
                                  ''
                              : '';
                          final short =
                              d.length >= 10 ? d.substring(5, 10) : d;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              short,
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 32),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoCard(
    ThemeData theme,
    String title,
    IconData icon,
    String value,
  ) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BasalamSyncedInvoicesReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const BasalamSyncedInvoicesReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<BasalamSyncedInvoicesReportPage> createState() =>
      _BasalamSyncedInvoicesReportPageState();
}

class _BasalamSyncedInvoicesReportPageState
    extends State<BasalamSyncedInvoicesReportPage> {
  DataTableConfig<Map<String, dynamic>> _tableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint:
          '/api/v1/basalam/business/${widget.businessId}/reports/synced-invoices',
      httpMethod: 'GET',
      pageSizeQueryParam: 'take',
      tableId: 'basalam_reports_synced_invoices',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.basalamSyncedInvoicesReportTable,
      title: t.reportsBasalamSyncedInvoicesTitle,
      subtitle: t.basalamReportsSyncedInvoicesTableHint,
      showExportButtons: false,
      enableSorting: false,
      enableGlobalSearch: false,
      showSearch: false,
      showColumnSearch: false,
      columns: [
        TextColumn(
          'code',
          t.reportsBasalamColumnDocumentCode,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'document_date',
          t.reportsBasalamColumnDocumentDate,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'basalam_order_id',
          t.reportsBasalamColumnBasalamOrderId,
          sortable: false,
          searchable: false,
        ),
        NumberColumn(
          'net',
          t.reportsBasalamColumnNet,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'document_type',
          t.reportsBasalamColumnDocumentType,
          sortable: false,
          searchable: false,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsBasalamSyncedInvoicesTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DataTableWidget<Map<String, dynamic>>(
            key: ValueKey('basalam_synced_${widget.businessId}'),
            config: _tableConfig(t),
            fromJson: (json) => Map<String, dynamic>.from(json),
            calendarController: widget.calendarController,
          ),
        ),
      ),
    );
  }
}

class BasalamDeadLetterReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const BasalamDeadLetterReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<BasalamDeadLetterReportPage> createState() =>
      _BasalamDeadLetterReportPageState();
}

class _BasalamDeadLetterReportPageState extends State<BasalamDeadLetterReportPage> {
  final _svc = BasalamIntegrationService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

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
      final d = await _svc.getReportsDeadLetter(
        businessId: widget.businessId,
        limit: 200,
        offset: 0,
      );
      if (!mounted) return;
      final raw = d['items'];
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _items = list;
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

  DataTableConfig<Map<String, dynamic>> _tableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint:
          '/api/v1/basalam/business/${widget.businessId}/reports/dead-letter-local',
      tableId: 'basalam_reports_dead_letter',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.basalamDeadLetterReportTable,
      title: t.reportsBasalamDeadLetterTitle,
      subtitle: t.basalamReportsDeadLetterTableHint,
      showExportButtons: false,
      enableSorting: false,
      enableGlobalSearch: false,
      showSearch: false,
      showColumnSearch: false,
      showPagination: false,
      columns: [
        TextColumn(
          'type',
          t.reportsBasalamColumnDeadLetterType,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'dlq_id',
          t.reportsBasalamColumnDlqId,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'created_at',
          t.reportsBasalamColumnCreatedAt,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'order_id',
          t.reportsBasalamColumnOrderId,
          sortable: false,
          searchable: false,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsBasalamDeadLetterTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: DataTableWidget<Map<String, dynamic>>(
                      key: ValueKey(
                        'basalam_dlq_${widget.businessId}_${_items.length}',
                      ),
                      config: _tableConfig(t),
                      fromJson: (json) => Map<String, dynamic>.from(json),
                      calendarController: widget.calendarController,
                      localRawItems: _items,
                    ),
                  ),
      ),
    );
  }
}

class BasalamProductConflictsReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const BasalamProductConflictsReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<BasalamProductConflictsReportPage> createState() =>
      _BasalamProductConflictsReportPageState();
}

class _BasalamProductConflictsReportPageState
    extends State<BasalamProductConflictsReportPage> {
  final _svc = BasalamIntegrationService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      final d = await _svc.getReportsProductConflicts(
        businessId: widget.businessId,
        limit: 100,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _data = d;
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

  DataTableConfig<Map<String, dynamic>> _tableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint:
          '/api/v1/basalam/business/${widget.businessId}/reports/product-conflicts-local',
      tableId: 'basalam_reports_product_conflicts',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.basalamProductConflictsReportTable,
      title: t.reportsBasalamProductConflictsTitle,
      subtitle: t.basalamReportsProductConflictsTableHint,
      showExportButtons: false,
      enableSorting: false,
      enableGlobalSearch: false,
      showSearch: false,
      showColumnSearch: false,
      showPagination: false,
      columns: [
        TextColumn(
          'conflict_id',
          t.reportsBasalamColumnConflictId,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'type',
          t.reportsBasalamColumnConflictType,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'direction',
          t.reportsBasalamColumnDirection,
          sortable: false,
          searchable: false,
        ),
        TextColumn(
          'reason',
          t.reportsBasalamColumnReason,
          sortable: false,
          searchable: false,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = (_data?['items'] is List)
        ? (_data!['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final summary = (_data?['summary'] is Map)
        ? _data!['summary'] as Map<String, dynamic>
        : <String, dynamic>{};
    final byType = (summary['by_type'] is Map)
        ? Map<String, dynamic>.from(summary['by_type'] as Map)
        : <String, dynamic>{};

    final palette = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.deepOrange,
    ];
    var pi = 0;
    final pieSections = <PieChartSectionData>[
      for (final e in byType.entries)
        if (((e.value as num?)?.toDouble() ?? 0) > 0)
          PieChartSectionData(
            value: (e.value as num).toDouble(),
            title: '${e.key}\n${e.value}',
            radius: 52,
            color: palette[pi++ % palette.length],
            titleStyle: const TextStyle(fontSize: 10, color: Colors.white),
          ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsBasalamProductConflictsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Column(
                    children: [
                      if (pieSections.isNotEmpty)
                        SizedBox(
                          height: 180,
                          child: PieChart(
                            PieChartData(sections: pieSections),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: DataTableWidget<Map<String, dynamic>>(
                            key: ValueKey(
                              'basalam_pc_${widget.businessId}_${items.length}',
                            ),
                            config: _tableConfig(t),
                            fromJson: (json) => Map<String, dynamic>.from(json),
                            calendarController: widget.calendarController,
                            localRawItems: items,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
