import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/core/auth_store.dart';
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
  bool _loading = true;
  String? _error;
  AIUsageStats? _stats;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numberFormat = NumberFormat.decimalPattern('fa');

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
      body: Column(
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
                    ? _buildStatsTab(theme, numberFormat)
                    : _buildLogsTab(theme, numberFormat),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTab(ThemeData theme, NumberFormat numberFormat) {
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
                  value: numberFormat.format(totalTokens),
                  icon: Icons.token_outlined,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'کل هزینه',
                  value: '${numberFormat.format(totalCost)} تومان',
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
                  value: numberFormat.format(totalRequests),
                  icon: Icons.request_quote_outlined,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'توکن ورودی',
                  value: numberFormat.format(inputTokens),
                  icon: Icons.input_outlined,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Daily Stats Table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'آمار روزانه',
                    style: theme.textTheme.titleLarge ?? theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (stats.daily.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: Text('داده‌ای وجود ندارد')),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('تاریخ')),
                          DataColumn(label: Text('توکن'), numeric: true),
                          DataColumn(label: Text('هزینه'), numeric: true),
                          DataColumn(label: Text('درخواست'), numeric: true),
                        ],
                        rows: stats.daily.map((day) {
                          try {
                            final dateStr = day['date'];
                            DateTime date;
                            String dateFormatted = '';
                            if (dateStr is String) {
                              try {
                                date = DateTime.parse(dateStr);
                                dateFormatted = DateFormat('yyyy/MM/dd', 'fa').format(date);
                              } catch (e) {
                                dateFormatted = dateStr.toString();
                              }
                            } else if (dateStr is DateTime) {
                              date = dateStr;
                              dateFormatted = DateFormat('yyyy/MM/dd', 'fa').format(date);
                            } else {
                              dateFormatted = dateStr?.toString() ?? '';
                            }
                            
                            final tokens = (day['tokens'] as num?)?.toInt() ?? 0;
                            final cost = (day['cost'] as num?)?.toDouble() ?? 0.0;
                            final requests = (day['requests'] as num?)?.toInt() ?? 0;
                            
                            return DataRow(
                              cells: [
                                DataCell(Text(dateFormatted)),
                                DataCell(Text(numberFormat.format(tokens))),
                                DataCell(Text('${numberFormat.format(cost)} تومان')),
                                DataCell(Text(numberFormat.format(requests))),
                              ],
                            );
                          } catch (e) {
                            debugPrint('[AIUsagePage] خطا در پردازش daily entry: $e');
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
                    style: theme.textTheme.titleLarge ?? theme.textTheme.titleMedium,
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
                                DataCell(Text(numberFormat.format(tokens))),
                                DataCell(Text('${numberFormat.format(cost)} تومان')),
                                DataCell(Text(numberFormat.format(requests))),
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

  Widget _buildLogsTab(ThemeData theme, NumberFormat numberFormat) {
    return FutureBuilder<List<AIUsageLog>>(
      future: _aiService.getUsageLogs(
        businessId: widget.businessId,
        limit: 100,
        skip: 0,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('خطا: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _load,
                  child: const Text('تلاش مجدد'),
                ),
              ],
            ),
          );
        }
        
        final logs = snapshot.data ?? [];
        
        if (logs.isEmpty) {
          return const Center(child: Text('لاگی وجود ندارد'));
        }
        
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('مدل')),
                DataColumn(label: Text('ارائه‌دهنده')),
                DataColumn(label: Text('توکن ورودی'), numeric: true),
                DataColumn(label: Text('توکن خروجی'), numeric: true),
                DataColumn(label: Text('کل توکن'), numeric: true),
                DataColumn(label: Text('هزینه'), numeric: true),
                DataColumn(label: Text('روش پرداخت')),
                DataColumn(label: Text('تاریخ')),
              ],
              rows: logs.map((log) {
                String dateFormatted = '';
                if (log.createdAt != null) {
                  try {
                    dateFormatted = DateFormat('yyyy/MM/dd HH:mm', 'fa').format(log.createdAt as DateTime);
                  } catch (e) {
                    dateFormatted = log.createdAt.toString();
                  }
                }
                
                return DataRow(
                  cells: [
                    DataCell(Text(log.model)),
                    DataCell(Text(log.provider)),
                    DataCell(Text(numberFormat.format(log.inputTokens))),
                    DataCell(Text(numberFormat.format(log.outputTokens))),
                    DataCell(Text(numberFormat.format(log.totalTokens))),
                    DataCell(Text('${numberFormat.format(log.cost)} تومان')),
                    DataCell(Text(log.paymentMethod)),
                    DataCell(Text(dateFormatted)),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
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

