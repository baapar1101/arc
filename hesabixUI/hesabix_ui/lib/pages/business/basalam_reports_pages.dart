import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/basalam_integration_service.dart';
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
  State<BasalamReportsOverviewPage> createState() => _BasalamReportsOverviewPageState();
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
      final d = await _svc.getReportsOverview(businessId: widget.businessId, chartDays: 90);
      if (!mounted) return;
      setState(() {
        _payload = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
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
    final summary = (_payload?['summary'] is Map) ? _payload!['summary'] as Map<String, dynamic> : <String, dynamic>{};
    final rawDays = _payload?['orders_by_day'];
    final days = rawDays is List ? rawDays.cast<dynamic>() : const <dynamic>[];

    final chartPoints = days.length > 45 ? days.sublist(days.length - 45) : days;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _infoCard(theme, '${t.reportsBasalamSection} · sync', Icons.power_settings_new,
                  summary['integration_enabled'] == true ? 'ON' : 'OFF'),
              _infoCard(theme, 'Webhook', Icons.webhook, summary['webhook_enabled'] == true ? 'ON' : 'OFF'),
              _infoCard(theme, 'DLQ', Icons.warning_amber_outlined, '${summary['dead_letter_count'] ?? 0}'),
              _infoCard(theme, t.reportsBasalamProductConflictsTitle, Icons.merge_type,
                  '${summary['pending_product_conflicts_count'] ?? 0}'),
              _infoCard(theme, t.reportsBasalamSyncedInvoicesTitle, Icons.receipt_long,
                  '${summary['basalam_invoices_in_period'] ?? 0}'),
              _infoCard(theme, 'Net (period)', Icons.payments_outlined,
                  '${summary['basalam_invoices_net_sum_in_period'] ?? 0}'),
            ],
          ),
          const SizedBox(height: 16),
          Text(t.reportsBasalamOverviewTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (chartPoints.isEmpty)
            Text(t.reportsSearchNoResults, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline))
          else
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: math.max(
                    1,
                    chartPoints.fold<double>(0, (m, e) {
                      final c = (e is Map) ? (e['count'] as num?)?.toDouble() ?? 0 : 0;
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
                                ? ((chartPoints[i] as Map)['count'] as num?)?.toDouble() ?? 0
                                : 0,
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
                          if (idx < 0 || idx >= chartPoints.length) return const SizedBox.shrink();
                          final d = (chartPoints[idx] is Map) ? (chartPoints[idx] as Map)['date']?.toString() ?? '' : '';
                          final short = d.length >= 10 ? d.substring(5, 10) : d;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(short, style: const TextStyle(fontSize: 9)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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

  Widget _infoCard(ThemeData theme, String title, IconData icon, String value) {
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

class BasalamSyncedInvoicesReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const BasalamSyncedInvoicesReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<BasalamSyncedInvoicesReportPage> createState() => _BasalamSyncedInvoicesReportPageState();
}

class _BasalamSyncedInvoicesReportPageState extends State<BasalamSyncedInvoicesReportPage> {
  final _svc = BasalamIntegrationService();
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  int _skip = 0;
  int _total = 0;
  static const _take = 40;

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
  }

  Future<void> _fetch({required bool reset}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _skip = 0;
        _rows.clear();
      }
    });
    try {
      final d = await _svc.getReportsSyncedInvoices(
        businessId: widget.businessId,
        skip: _skip,
        take: _take,
      );
      if (!mounted) return;
      final items = d['items'];
      final list = items is List ? items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      setState(() {
        _rows.addAll(list);
        _total = (d['total'] as num?)?.toInt() ?? _rows.length;
        _skip += list.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsBasalamSyncedInvoicesTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
              child: ListView.builder(
                itemCount: _rows.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == _rows.length) {
                    if (_rows.length >= _total) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: _loading
                            ? const CircularProgressIndicator()
                            : TextButton(onPressed: () => _fetch(reset: false), child: Text(t.loanFacilityLoadMore)),
                      ),
                    );
                  }
                  final r = _rows[i];
                  return ListTile(
                    title: Text('${r['code'] ?? '-'}  ·  ${r['document_date'] ?? ''}'),
                    subtitle: Text('Basalam: ${r['basalam_order_id'] ?? '-'}  ·  net: ${r['net'] ?? 0}'),
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

class BasalamDeadLetterReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const BasalamDeadLetterReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<BasalamDeadLetterReportPage> createState() => _BasalamDeadLetterReportPageState();
}

class _BasalamDeadLetterReportPageState extends State<BasalamDeadLetterReportPage> {
  final _svc = BasalamIntegrationService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final d = await _svc.getReportsDeadLetter(businessId: widget.businessId, limit: 200, offset: 0);
      if (!mounted) return;
      final raw = d['items'];
      final list = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.reportsBasalamDeadLetterTitle),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('type')),
                        DataColumn(label: Text('dlq_id')),
                        DataColumn(label: Text('created_at')),
                        DataColumn(label: Text('order_id')),
                      ],
                      rows: [
                        for (final r in _items)
                          DataRow(
                            cells: [
                              DataCell(Text('${r['type'] ?? ''}')),
                              DataCell(Text('${r['dlq_id'] ?? ''}')),
                              DataCell(Text('${r['created_at'] ?? ''}')),
                              DataCell(Text('${r['order_id'] ?? ''}')),
                            ],
                          ),
                      ],
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
  State<BasalamProductConflictsReportPage> createState() => _BasalamProductConflictsReportPageState();
}

class _BasalamProductConflictsReportPageState extends State<BasalamProductConflictsReportPage> {
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
      final d = await _svc.getReportsProductConflicts(businessId: widget.businessId, limit: 100, offset: 0);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = (_data?['items'] is List) ? (_data!['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
    final summary = (_data?['summary'] is Map) ? _data!['summary'] as Map<String, dynamic> : <String, dynamic>{};
    final byType = (summary['by_type'] is Map) ? Map<String, dynamic>.from(summary['by_type'] as Map) : <String, dynamic>{};

    final palette = [
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.purple,
      Colors.teal,
      Colors.deepOrange,
    ];
    int pi = 0;
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
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
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('conflict_id')),
                              DataColumn(label: Text('type')),
                              DataColumn(label: Text('direction')),
                              DataColumn(label: Text('reason')),
                            ],
                            rows: [
                              for (final r in items)
                                DataRow(
                                  cells: [
                                    DataCell(Text('${r['conflict_id'] ?? ''}')),
                                    DataCell(Text('${r['type'] ?? ''}')),
                                    DataCell(Text('${r['direction'] ?? ''}')),
                                    DataCell(Text('${r['reason'] ?? ''}')),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
