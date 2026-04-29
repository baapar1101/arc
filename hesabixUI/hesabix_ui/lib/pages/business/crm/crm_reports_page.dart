import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

/// صفحه گزارشات CRM
class CrmReportsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CrmReportsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CrmReportsPage> createState() => _CrmReportsPageState();
}

class _CrmReportsPageState extends State<CrmReportsPage> with SingleTickerProviderStateMixin {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  late TabController _tabController;
  int _currentTab = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<dynamic> _pipelineData = [];
  List<dynamic> _leadFunnelData = [];
  List<dynamic> _leadSourcesData = [];
  List<dynamic> _employeeData = [];
  bool _employeeRestrictedToSelf = false;
  List<dynamic> _salesTrendData = [];
  List<Map<String, dynamic>> _processDefs = [];
  Map<String, dynamic> _weightedForecast = {};
  String? _pipelineFromDate;
  String? _pipelineToDate;
  String? _leadFunnelFromDate;
  String? _leadFunnelToDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _currentTab) {
        setState(() => _currentTab = _tabController.index);
      }
    });
    unawaited(_bootstrap());
  }

  /// شناسه‌های عددی JSON ممکن است `int` یا `double` باشند.
  int? _crmInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString());
  }

  Future<void> _bootstrap() async {
    await _loadProcessDefs();
    if (!mounted) return;
    await _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProcessDefs() async {
    try {
      final res = await _crmService.listProcessDefinitions(businessId: widget.businessId);
      final list = res is List ? res : (res is Map && res['data'] is List ? res['data'] as List : <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _processDefs = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'بارگذاری فهرست فرایندها ناموفق بود: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      int? pipelineDefId;
      for (final e in _processDefs) {
        if (e['process_type'] == 'sales_pipeline') {
          pipelineDefId = _crmInt(e['id']);
          break;
        }
      }
      final futures = await Future.wait([
        _crmService.getSummary(businessId: widget.businessId),
        _crmService.getPipelineReport(businessId: widget.businessId, processDefinitionId: pipelineDefId, fromDate: _pipelineFromDate, toDate: _pipelineToDate),
        _crmService.getLeadFunnelReport(businessId: widget.businessId, fromDate: _leadFunnelFromDate, toDate: _leadFunnelToDate),
        _crmService.getLeadSourcesReport(businessId: widget.businessId),
        _crmService.getEmployeePerformanceReport(businessId: widget.businessId),
        _crmService.getSalesTrendReport(businessId: widget.businessId, months: 6),
        _crmService.getWeightedForecast(businessId: widget.businessId, processDefinitionId: pipelineDefId),
      ]);
      if (!mounted) return;
      final empRes = futures[4] is Map ? Map<String, dynamic>.from(futures[4] as Map) : null;
      setState(() {
        _summary = futures[0] is Map ? Map<String, dynamic>.from(futures[0] as Map) : null;
        _pipelineData = futures[1] is List ? List<dynamic>.from(futures[1] as List) : [];
        _leadFunnelData = futures[2] is List ? List<dynamic>.from(futures[2] as List) : [];
        _leadSourcesData = futures[3] is List ? List<dynamic>.from(futures[3] as List) : [];
        _employeeData = empRes?['data'] is List ? List<dynamic>.from(empRes!['data'] as List) : [];
        _employeeRestrictedToSelf = empRes?['restricted_to_self'] == true;
        _salesTrendData = futures[5] is List ? List<dynamic>.from(futures[5] as List) : [];
        _weightedForecast = futures[6] is Map ? Map<String, dynamic>.from(futures[6] as Map) : {};
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
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده گزارشات CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارشات CRM'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : null,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _bootstrap,
            tooltip: 'بروزرسانی',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'خلاصه'),
            Tab(text: 'پایپلاین'),
            Tab(text: 'قیف سرنخ'),
            Tab(text: 'منابع'),
            Tab(text: 'عملکرد کارمندان'),
            Tab(text: 'روند فروش'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(onPressed: _bootstrap, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _bootstrap,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSummaryTab(),
                      _buildPipelineTab(),
                      _buildLeadFunnelTab(),
                      _buildLeadSourcesTab(),
                      _buildEmployeePerformanceTab(),
                      _buildSalesTrendTab(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryTab() {
    final s = _summary ?? {};
    final formatter = NumberFormat('#,##0');
    final items = <(String, String, IconData)>[
      ('سرنخ‌ها', '${s['total_leads'] ?? 0}', Icons.contact_phone),
      ('تبدیل شده', '${s['converted_leads'] ?? 0}', Icons.person_add),
      ('نرخ تبدیل', '${s['conversion_rate'] ?? 0}%', Icons.percent),
      ('فرصت فروش', '${s['total_deals'] ?? 0}', Icons.trending_up),
      ('بسته شده', '${s['closed_deals'] ?? 0}', Icons.check_circle),
      ('مبلغ کل', formatter.format((s['total_deals_amount'] as num?) ?? 0), Icons.account_balance_wallet),
      ('پیش‌بینی درآمد (موزون)', formatter.format((_weightedForecast['weighted_total'] as num?) ?? 0), Icons.insights),
    ];

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final inner = box.maxWidth;
          const gap = 12.0;
          final nCols =
              inner < 420 ? 1 : inner < 760 ? 2 : inner < 1100 ? 3 : 4;
          final cardW = (inner - gap * (nCols - 1)) / nCols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items
                .map(
                  (e) => SizedBox(
                    width: cardW,
                    child: _summaryCard(e.$1, e.$2, e.$3),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 26, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 480;
                  final fromBtn = TextButton(
                    onPressed: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setState(() {
                          _pipelineFromDate =
                              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                          _loadAll();
                        });
                      }
                    },
                    child: Text(
                      _pipelineFromDate != null && HesabixDateUtils.parseFromAPI(_pipelineFromDate) != null
                          ? HesabixDateUtils.formatForDisplay(
                              HesabixDateUtils.parseFromAPI(_pipelineFromDate),
                              ApiClient.getCalendarController()?.isJalali ?? true,
                            )
                          : 'از',
                    ),
                  );
                  final toBtn = TextButton(
                    onPressed: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setState(() {
                          _pipelineToDate =
                              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                          _loadAll();
                        });
                      }
                    },
                    child: Text(
                      _pipelineToDate != null && HesabixDateUtils.parseFromAPI(_pipelineToDate) != null
                          ? HesabixDateUtils.formatForDisplay(
                              HesabixDateUtils.parseFromAPI(_pipelineToDate),
                              ApiClient.getCalendarController()?.isJalali ?? true,
                            )
                          : 'تا',
                    ),
                  );
                  final clearBtn = (_pipelineFromDate != null || _pipelineToDate != null)
                      ? TextButton(
                          onPressed: () => setState(() {
                            _pipelineFromDate = null;
                            _pipelineToDate = null;
                            _loadAll();
                          }),
                          child: const Text('پاک کردن'),
                        )
                      : null;
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'بازه تاریخ (بر اساس ایجاد فرصت):',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            fromBtn,
                            toBtn,
                            if (clearBtn != null) clearBtn,
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          'بازه تاریخ (بر اساس ایجاد فرصت):',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      fromBtn,
                      toBtn,
                      if (clearBtn != null) clearBtn,
                    ],
                  );
                },
              ),
            ),
          ),
          if (_pipelineData.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('داده‌ای موجود نیست.')))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final chartH = box.maxWidth < 400 ? 220.0 : 260.0;
                    return SizedBox(
                      height: chartH,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: (_pipelineData.map((e) => ((e['deal_count'] as num?) ?? 0).toDouble()).fold<double>(0, (a, b) => a > b ? a : b) * 1.2).clamp(1.0, double.infinity),
                          barTouchData: BarTouchData(enabled: true),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, meta) {
                                final i = v.toInt();
                                if (i >= 0 && i < _pipelineData.length) {
                                  final name = _pipelineData[i]['stage_name']?.toString() ?? '';
                                  return Padding(padding: const EdgeInsets.only(top: 8), child: Text(name.length > 8 ? '${name.substring(0, 8)}...' : name, style: const TextStyle(fontSize: 10)));
                                }
                                return const SizedBox();
                              },
                            )),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                          barGroups: List.generate(_pipelineData.length, (i) {
                            final cnt = ((_pipelineData[i]['deal_count'] as num?) ?? 0).toDouble();
                            return BarChartGroupData(
                              x: i,
                              barRods: [BarChartRodData(toY: cnt, width: 20, color: Theme.of(context).colorScheme.primary)],
                              showingTooltipIndicators: [0],
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: box.maxWidth),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('مرحله')),
                              DataColumn(label: Text('تعداد')),
                              DataColumn(label: Text('مبلغ (ریال)')),
                            ],
                            rows: _pipelineData.map<DataRow>((e) {
                              final amt = (e['total_amount'] as num?) ?? 0;
                              return DataRow(cells: [
                                DataCell(Text(e['stage_name']?.toString() ?? '')),
                                DataCell(Text('${e['deal_count'] ?? 0}')),
                                DataCell(Text(NumberFormat('#,##0').format(amt))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLeadFunnelTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 480;
                  final fromBtn = TextButton(
                    onPressed: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setState(() {
                          _leadFunnelFromDate =
                              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                          _loadAll();
                        });
                      }
                    },
                    child: Text(
                      _leadFunnelFromDate != null && HesabixDateUtils.parseFromAPI(_leadFunnelFromDate) != null
                          ? HesabixDateUtils.formatForDisplay(
                              HesabixDateUtils.parseFromAPI(_leadFunnelFromDate),
                              ApiClient.getCalendarController()?.isJalali ?? true,
                            )
                          : 'از',
                    ),
                  );
                  final toBtn = TextButton(
                    onPressed: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setState(() {
                          _leadFunnelToDate =
                              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                          _loadAll();
                        });
                      }
                    },
                    child: Text(
                      _leadFunnelToDate != null && HesabixDateUtils.parseFromAPI(_leadFunnelToDate) != null
                          ? HesabixDateUtils.formatForDisplay(
                              HesabixDateUtils.parseFromAPI(_leadFunnelToDate),
                              ApiClient.getCalendarController()?.isJalali ?? true,
                            )
                          : 'تا',
                    ),
                  );
                  final clearBtn = (_leadFunnelFromDate != null || _leadFunnelToDate != null)
                      ? TextButton(
                          onPressed: () => setState(() {
                            _leadFunnelFromDate = null;
                            _leadFunnelToDate = null;
                            _loadAll();
                          }),
                          child: const Text('پاک کردن'),
                        )
                      : null;
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'بازه تاریخ (بر اساس ایجاد سرنخ):',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            fromBtn,
                            toBtn,
                            if (clearBtn != null) clearBtn,
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          'بازه تاریخ (بر اساس ایجاد سرنخ):',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      fromBtn,
                      toBtn,
                      if (clearBtn != null) clearBtn,
                    ],
                  );
                },
              ),
            ),
          ),
          if (_leadFunnelData.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('داده‌ای موجود نیست.')))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final chartH = box.maxWidth < 400 ? 220.0 : 260.0;
                    return SizedBox(
                      height: chartH,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: (_leadFunnelData.map((e) => ((e['lead_count'] as num?) ?? 0).toDouble()).fold<double>(0, (a, b) => a > b ? a : b) * 1.2).clamp(1.0, double.infinity),
                          barTouchData: BarTouchData(enabled: true),
                          titlesData: FlTitlesData(
                            show: true,
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, meta) {
                                final i = v.toInt();
                                if (i >= 0 && i < _leadFunnelData.length) {
                                  final name = _leadFunnelData[i]['stage_name']?.toString() ?? '';
                                  return Padding(padding: const EdgeInsets.only(top: 8), child: Text(name.length > 8 ? '${name.substring(0, 8)}...' : name, style: const TextStyle(fontSize: 10)));
                                }
                                return const SizedBox();
                              },
                            )),
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                          barGroups: List.generate(_leadFunnelData.length, (i) {
                            final cnt = ((_leadFunnelData[i]['lead_count'] as num?) ?? 0).toDouble();
                            return BarChartGroupData(
                              x: i,
                              barRods: [BarChartRodData(toY: cnt, width: 20, color: Theme.of(context).colorScheme.secondary)],
                              showingTooltipIndicators: [0],
                            );
                          }),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: box.maxWidth),
                          child: DataTable(
                            columns: const [DataColumn(label: Text('مرحله')), DataColumn(label: Text('تعداد سرنخ'))],
                            rows: _leadFunnelData.map<DataRow>((e) => DataRow(cells: [
                              DataCell(Text(e['stage_name']?.toString() ?? '')),
                              DataCell(Text('${e['lead_count'] ?? 0}')),
                            ])).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLeadSourcesTab() {
    if (_leadSourcesData.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.source, size: 64, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 16), const Text('داده‌ای موجود نیست.')]));
    }
    final total = _leadSourcesData.fold<int>(0, (s, e) => s + ((e['count'] as num?)?.toInt() ?? 0));
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final h = box.maxWidth < 400 ? 200.0 : 240.0;
              return SizedBox(
                height: h,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: box.maxWidth < 400 ? 32 : 40,
                    sections: List.generate(_leadSourcesData.length, (i) {
                      final cnt = (_leadSourcesData[i]['count'] as num?) ?? 0;
                      final pct = total > 0 ? (cnt / total * 100) : 0;
                      return PieChartSectionData(
                        value: cnt.toDouble(),
                        title: '${pct.toStringAsFixed(0)}%',
                        color: _chartColor(i),
                      );
                    }),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, box) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('منبع')),
                        DataColumn(label: Text('تعداد')),
                        DataColumn(label: Text('درصد')),
                      ],
                      rows: _leadSourcesData.map<DataRow>((e) {
                        final cnt = (e['count'] as num?) ?? 0;
                        final pct = total > 0 ? (cnt / total * 100).toStringAsFixed(1) : '0';
                        return DataRow(cells: [
                          DataCell(Text(e['source_code']?.toString() ?? 'نامشخص')),
                          DataCell(Text('$cnt')),
                          DataCell(Text('$pct%')),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _chartColor(int i) {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.teal, Colors.pink];
    return colors[i % colors.length];
  }

  Widget _buildEmployeePerformanceTab() {
    if (_employeeData.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people, size: 64, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 16), const Text('داده‌ای موجود نیست.')]));
    }
    final formatter = NumberFormat('#,##0');
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_employeeRestrictedToSelf)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('فقط عملکرد شما نمایش داده می‌شود. برای مشاهده عملکرد همه کارمندان، دسترسی «گزارش عملکرد کارمندان (همه تیم)» لازم است.')),
                    ],
                  ),
                ),
              ),
            ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, box) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('کارمند')),
                        DataColumn(label: Text('سرنخ')),
                        DataColumn(label: Text('تبدیل شده')),
                        DataColumn(label: Text('نرخ تبدیل')),
                        DataColumn(label: Text('فرصت')),
                        DataColumn(label: Text('بسته شده')),
                        DataColumn(label: Text('مبلغ کل')),
                        DataColumn(label: Text('فعالیت')),
                      ],
                      rows: _employeeData.map<DataRow>((e) => DataRow(cells: [
                        DataCell(Text(e['user_name']?.toString() ?? '')),
                        DataCell(Text('${e['leads_count'] ?? 0}')),
                        DataCell(Text('${e['converted_leads'] ?? 0}')),
                        DataCell(Text('${e['conversion_rate'] ?? 0}%')),
                        DataCell(Text('${e['deals_count'] ?? 0}')),
                        DataCell(Text('${e['closed_deals'] ?? 0}')),
                        DataCell(Text(formatter.format((e['total_amount'] as num?) ?? 0))),
                        DataCell(Text('${e['activities_count'] ?? 0}')),
                      ])).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTrendTab() {
    if (_salesTrendData.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.show_chart, size: 64, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 16), const Text('داده‌ای موجود نیست.')]));
    }
    final maxAmt = _salesTrendData.fold<double>(0, (s, e) {
      final a = ((e['amount'] as num?) ?? 0).toDouble();
      return a > s ? a : s;
    });
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final chartH = box.maxWidth < 400 ? 220.0 : 260.0;
              return SizedBox(
                height: chartH,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (maxAmt * 1.2).clamp(1.0, double.infinity),
                    barTouchData: BarTouchData(enabled: true),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i >= 0 && i < _salesTrendData.length) {
                            return Padding(padding: const EdgeInsets.only(top: 8), child: Text(_salesTrendData[i]['period']?.toString() ?? '', style: const TextStyle(fontSize: 10)));
                          }
                          return const SizedBox();
                        },
                      )),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, meta) => Text(NumberFormat.compact().format(v), style: const TextStyle(fontSize: 9)))),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(_salesTrendData.length, (i) {
                      final amt = ((_salesTrendData[i]['amount'] as num?) ?? 0).toDouble();
                      return BarChartGroupData(
                        x: i,
                        barRods: [BarChartRodData(toY: amt, width: 16, color: Theme.of(context).colorScheme.tertiary)],
                        showingTooltipIndicators: [0],
                      );
                    }),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, box) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('بازه')),
                        DataColumn(label: Text('تعداد')),
                        DataColumn(label: Text('مبلغ')),
                      ],
                      rows: _salesTrendData.map<DataRow>((e) => DataRow(cells: [
                            DataCell(Text(e['period']?.toString() ?? '')),
                            DataCell(Text('${e['count'] ?? 0}')),
                            DataCell(Text(NumberFormat('#,##0').format((e['amount'] as num?) ?? 0))),
                          ])).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
