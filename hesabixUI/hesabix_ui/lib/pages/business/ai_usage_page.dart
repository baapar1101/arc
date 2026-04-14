import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:intl/intl.dart';

class AIUsagePage extends StatefulWidget {
  final int? businessId;
  final AuthStore authStore;

  const AIUsagePage({
    super.key,
    this.businessId,
    required this.authStore,
  });

  @override
  State<AIUsagePage> createState() => _AIUsagePageState();
}

class _AIUsagePageState extends State<AIUsagePage> {
  late final AIService _aiService;
  final GlobalKey _logsTableKey = GlobalKey();
  final GlobalKey _dailyTableKey = GlobalKey();
  late final NumberFormat _numberFormatter;
  late final DateFormat _logDateFormat;
  late final DateFormat _dailyDateFormat;
  bool _loading = true;
  String? _error;
  AIUsageStats? _stats;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _numberFormatter = NumberFormat.decimalPattern('fa');
    _logDateFormat = DateFormat('yyyy/MM/dd HH:mm', 'fa');
    _dailyDateFormat = DateFormat('yyyy/MM/dd', 'fa');
    _load();
  }

  Future<void> _load() async {
    debugPrint('[AIUsagePage] شروع بارگذاری داده‌ها...');
    debugPrint('[AIUsagePage] businessId: ${widget.businessId}');
    
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      debugPrint('[AIUsagePage] در حال دریافت آمار...');
      final stats = await _aiService.getUsageStats(
        businessId: widget.businessId,
      );
      debugPrint('[AIUsagePage] آمار دریافت شد');
      debugPrint('[AIUsagePage] total: ${stats.total}');
      debugPrint('[AIUsagePage] daily length: ${stats.daily.length}');
      debugPrint('[AIUsagePage] byModel length: ${stats.byModel.length}');
      
      if (!mounted) return;
      
      setState(() {
        _stats = stats;
        _loading = false;
      });
      
      debugPrint('[AIUsagePage] بارگذاری با موفقیت انجام شد');
    } catch (e, stackTrace) {
      debugPrint('[AIUsagePage] خطا در بارگذاری: $e');
      debugPrint('[AIUsagePage] StackTrace: $stackTrace');
      
      if (!mounted) return;
      
      setState(() {
        _error = '$e';
        _loading = false;
      });
    } finally {
      _refreshLogsTable();
      _refreshDailyTable();
    }
  }

  void _refreshLogsTable() {
    try {
      final current = _logsTableKey.currentState as dynamic;
      current?.refresh();
    } catch (e) {
      debugPrint('[AIUsagePage] refresh logs table failed: $e');
    }
  }

  void _refreshDailyTable() {
    try {
      final current = _dailyTableKey.currentState as dynamic;
      current?.refresh();
    } catch (e) {
      debugPrint('[AIUsagePage] refresh daily table failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('آمار استفاده از AI'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else if (widget.businessId != null) {
                context.go('/business/${widget.businessId}/dashboard');
              }
            },
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('آمار استفاده از AI'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (widget.businessId != null) {
              context.go('/business/${widget.businessId}/dashboard');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        initialIndex: _selectedTab,
        child: Column(
          children: [
            TabBar(
              tabs: const [
                Tab(text: 'آمار کلی', icon: Icon(Icons.bar_chart)),
                Tab(text: 'لاگ استفاده', icon: Icon(Icons.list)),
              ],
              onTap: (index) => setState(() => _selectedTab = index),
            ),
            Expanded(
              child: _error != null && _stats == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('خطا: $_error'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _load,
                            child: const Text('تلاش مجدد'),
                          ),
                        ],
                      ),
                    )
                  : _selectedTab == 0
                      ? _buildStatsTab(theme)
                      : _buildLogsTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab(ThemeData theme) {
    final stats = _stats;
    debugPrint('[AIUsagePage] _buildStatsTab - stats: ${stats != null}');
    
    if (stats == null) {
      debugPrint('[AIUsagePage] _buildStatsTab - stats is null, نمایش پیام خالی');
      return const Center(child: Text('داده‌ای وجود ندارد'));
    }

    try {
      debugPrint('[AIUsagePage] _buildStatsTab - استخراج مقادیر از stats.total');
      debugPrint('[AIUsagePage] stats.total: ${stats.total}');
      
      final totalTokens = (stats.total['total_tokens'] as num?)?.toInt() ?? 0;
      final totalCost = (stats.total['total_cost'] as num?)?.toDouble() ?? 0.0;
      final totalRequests = (stats.total['total_requests'] as num?)?.toInt() ?? 0;
      final inputTokens = (stats.total['input_tokens'] as num?)?.toInt() ?? 0;
      
      debugPrint('[AIUsagePage] totalTokens: $totalTokens, totalCost: $totalCost, totalRequests: $totalRequests, inputTokens: $inputTokens');
      
      debugPrint('[AIUsagePage] ساخت SingleChildScrollView...');
      debugPrint('[AIUsagePage] theme.textTheme.titleLarge: ${theme.textTheme.titleLarge}');
      
      return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'کل توکن',
                  value: _numberFormatter.format(totalTokens),
                  icon: Icons.token_outlined,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'کل هزینه',
                  value: '${_numberFormatter.format(totalCost)} تومان',
                  icon: Icons.attach_money,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'کل درخواست‌ها',
                  value: _numberFormatter.format(totalRequests),
                  icon: Icons.request_quote_outlined,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'توکن ورودی',
                  value: _numberFormatter.format(inputTokens),
                  icon: Icons.input_outlined,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Daily Stats Table (DataTableWidget)
          SizedBox(
            height: 420,
            child: DataTableWidget<Map<String, dynamic>>(
              key: _dailyTableKey,
              config: _buildDailyTableConfig(),
              fromJson: (json) => Map<String, dynamic>.from(json as Map),
            ),
          ),
          const SizedBox(height: 24),
          // By Model Table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'بر اساس مدل',
                    style: theme.textTheme.titleLarge ?? theme.textTheme.titleMedium ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (stats.byModel.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: Text('داده‌ای وجود ندارد')),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('مدل')),
                          DataColumn(label: Text('توکن'), numeric: true),
                          DataColumn(label: Text('هزینه'), numeric: true),
                          DataColumn(label: Text('درخواست'), numeric: true),
                        ],
                        rows: stats.byModel.map((model) {
                          try {
                            final modelName = model['model'] as String? ?? 'نامشخص';
                            final tokens = (model['tokens'] as num?)?.toInt() ?? 0;
                            final cost = (model['cost'] as num?)?.toDouble() ?? 0.0;
                            final requests = (model['requests'] as num?)?.toInt() ?? 0;
                            
                            return DataRow(
                              cells: [
                                DataCell(Text(modelName)),
                                DataCell(Text(_numberFormatter.format(tokens))),
                                DataCell(Text('${_numberFormatter.format(cost)} تومان')),
                                DataCell(Text(_numberFormatter.format(requests))),
                              ],
                            );
                          } catch (e) {
                            debugPrint('[AIUsagePage] خطا در پردازش model entry: $e');
                            return DataRow(
                              cells: [
                                const DataCell(Text('خطا')),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                              ],
                            );
                          }
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    } catch (e, stackTrace) {
      debugPrint('[AIUsagePage] خطا در _buildStatsTab: $e');
      debugPrint('[AIUsagePage] StackTrace: $stackTrace');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('خطا در نمایش آمار: $e'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _load,
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildLogsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DataTableWidget<AIUsageLog>(
        key: _logsTableKey,
        config: _buildLogsTableConfig(),
        fromJson: AIUsageLog.fromJson,
      ),
    );
  }

  DataTableConfig<AIUsageLog> _buildLogsTableConfig() {
    final params = <String, dynamic>{};
    if (widget.businessId != null) {
      params['business_id'] = widget.businessId;
    }

    return DataTableConfig<AIUsageLog>(
      endpoint: '/api/v1/ai/usage/logs/table',
      title: 'لاگ استفاده',
      tableId: 'ai_usage_logs',
      showTableIcon: false,
      showSearch: true,
      showFilters: true,
      showColumnSearch: true,
      showPagination: true,
      enableSorting: true,
      defaultSortBy: 'created_at',
      defaultSortDesc: true,
      searchFields: const ['model', 'provider', 'payment_method'],
      additionalParams: params.isEmpty ? null : params,
      emptyStateMessage: 'هیچ لاگی ثبت نشده است',
      columns: [
        TextColumn(
          'provider',
          'ارائه‌دهنده',
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: const [
            FilterOption(value: 'openai', label: 'OpenAI'),
            FilterOption(value: 'azure', label: 'Azure OpenAI'),
            FilterOption(value: 'anthropic', label: 'Anthropic'),
            FilterOption(value: 'local', label: 'Local'),
            FilterOption(value: 'hesabix', label: 'Hesabix'),
          ],
          formatter: (item) => _providerLabel((item as AIUsageLog).provider),
        ),
        TextColumn(
          'model',
          'مدل',
          width: ColumnWidth.medium,
          formatter: (item) => (item as AIUsageLog).model,
        ),
        NumberColumn(
          'input_tokens',
          'توکن ورودی',
          width: ColumnWidth.medium,
          formatter: (item) => _numberFormatter.format((item as AIUsageLog).inputTokens),
        ),
        NumberColumn(
          'output_tokens',
          'توکن خروجی',
          width: ColumnWidth.medium,
          formatter: (item) => _numberFormatter.format((item as AIUsageLog).outputTokens),
        ),
        NumberColumn(
          'total_tokens',
          'کل توکن',
          width: ColumnWidth.medium,
          formatter: (item) => _numberFormatter.format((item as AIUsageLog).totalTokens),
        ),
        NumberColumn(
          'cost',
          'هزینه',
          width: ColumnWidth.medium,
          decimalPlaces: 2,
          formatter: (item) => '${_numberFormatter.format((item as AIUsageLog).cost)} تومان',
        ),
        TextColumn(
          'payment_method',
          'روش پرداخت',
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: const [
            FilterOption(value: 'free', label: 'رایگان'),
            FilterOption(value: 'subscription', label: 'اشتراک'),
            FilterOption(value: 'wallet', label: 'کیف پول'),
          ],
          formatter: (item) => _paymentMethodLabel((item as AIUsageLog).paymentMethod),
        ),
        DateColumn(
          'created_at',
          'تاریخ',
          width: ColumnWidth.large,
          showTime: true,
          filterType: ColumnFilterType.dateRange,
          formatter: (item) => _formatLogDate((item as AIUsageLog).createdAt),
        ),
      ],
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildDailyTableConfig() {
    final params = <String, dynamic>{};
    if (widget.businessId != null) {
      params['business_id'] = widget.businessId;
    }

    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/ai/usage/daily/table',
      title: 'آمار روزانه',
      tableId: 'ai_usage_daily',
      showTableIcon: false,
      showSearch: true,
      showFilters: true,
      showColumnSearch: false,
      showPagination: true,
      enableSorting: true,
      defaultSortBy: 'date',
      defaultSortDesc: true,
      additionalParams: params.isEmpty ? null : params,
      columns: [
        DateColumn(
          'date',
          'تاریخ',
          showTime: false,
          filterType: ColumnFilterType.dateRange,
          formatter: (item) => _formatDailyDate((item as Map<String, dynamic>)['date']),
        ),
        NumberColumn(
          'tokens',
          'کل توکن',
          width: ColumnWidth.medium,
          formatter: (item) => _formatNumberField(item as Map<String, dynamic>, 'tokens'),
        ),
        NumberColumn(
          'cost',
          'هزینه',
          width: ColumnWidth.medium,
          decimalPlaces: 2,
          formatter: (item) => _formatCurrencyField(item as Map<String, dynamic>, 'cost'),
        ),
        NumberColumn(
          'requests',
          'درخواست',
          width: ColumnWidth.medium,
          formatter: (item) => _formatNumberField(item as Map<String, dynamic>, 'requests'),
        ),
      ],
    );
  }

  String _formatNumberField(Map<String, dynamic> item, String key) {
    final value = item[key] ?? 0;
    return _numberFormatter.format(value);
  }

  String _formatCurrencyField(Map<String, dynamic> item, String key) {
    final value = item[key] ?? 0;
    return '${_numberFormatter.format(value)} تومان';
  }

  String _formatDailyDate(dynamic value) {
    if (value == null) return '-';
    try {
      final date = value is DateTime ? value : DateTime.parse(value.toString());
      return _dailyDateFormat.format(date.toLocal());
    } catch (_) {
      return value.toString();
    }
  }

  String _providerLabel(String? provider) {
    final value = provider?.toLowerCase() ?? '';
    switch (value) {
      case 'openai':
        return 'OpenAI';
      case 'azure':
        return 'Azure OpenAI';
      case 'anthropic':
        return 'Anthropic';
      case 'local':
        return 'مدل محلی';
      case 'hesabix':
        return 'Hesabix';
      default:
        return provider ?? '-';
    }
  }

  String _paymentMethodLabel(String? method) {
    final value = method?.toLowerCase() ?? '';
    switch (value) {
      case 'free':
        return 'رایگان';
      case 'subscription':
        return 'اشتراک';
      case 'wallet':
        return 'کیف پول';
      default:
        return method ?? '-';
    }
  }

  String _formatLogDate(DateTime? date) {
    if (date == null) return '-';
    try {
      return _logDateFormat.format(date.toLocal());
    } catch (_) {
      return date.toString();
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: (theme.textTheme.headlineSmall ?? theme.textTheme.titleLarge ?? theme.textTheme.titleMedium)?.copyWith(
                fontWeight: FontWeight.bold,
              ) ?? TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

