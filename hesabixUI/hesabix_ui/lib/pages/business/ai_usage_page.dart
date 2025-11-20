import 'package:flutter/material.dart';
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
  List<AIUsageLog> _logs = [];
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await _aiService.getUsageStats(
        businessId: widget.businessId,
      );
      final logs = await _aiService.getUsageLogs(
        businessId: widget.businessId,
        limit: 50,
      );
      setState(() {
        _stats = stats;
        _logs = logs;
        _loading = false;
      });
    } catch (e) {
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
        appBar: AppBar(title: const Text('آمار استفاده از AI')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('آمار استفاده از AI'),
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
    if (_stats == null) {
      return const Center(child: Text('داده‌ای وجود ندارد'));
    }

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
                  value: numberFormat.format(_stats!.total['total_tokens'] ?? 0),
                  icon: Icons.token_outlined,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'کل هزینه',
                  value: '${numberFormat.format(_stats!.total['total_cost'] ?? 0)} تومان',
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
                  value: numberFormat.format(_stats!.total['total_requests'] ?? 0),
                  icon: Icons.request_quote_outlined,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'توکن ورودی',
                  value: numberFormat.format(_stats!.total['input_tokens'] ?? 0),
                  icon: Icons.input_outlined,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Daily Stats
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'آمار روزانه',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (_stats!.daily.isEmpty)
                    const Center(child: Text('داده‌ای وجود ندارد'))
                  else
                    ..._stats!.daily.map((day) {
                      final date = DateTime.parse(day['date'] as String);
                      return ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: Text(DateFormat('yyyy/MM/dd', 'fa').format(date)),
                        subtitle: Text(
                          '${numberFormat.format(day['tokens'])} توکن • ${numberFormat.format(day['cost'])} تومان',
                        ),
                        trailing: Text('${day['requests']} درخواست'),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // By Model
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'بر اساس مدل',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (_stats!.byModel.isEmpty)
                    const Center(child: Text('داده‌ای وجود ندارد'))
                  else
                    ..._stats!.byModel.map((model) {
                      return ListTile(
                        leading: const Icon(Icons.smart_toy),
                        title: Text(model['model'] as String),
                        subtitle: Text(
                          '${numberFormat.format(model['tokens'])} توکن • ${numberFormat.format(model['cost'])} تومان',
                        ),
                        trailing: Text('${model['requests']} درخواست'),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab(ThemeData theme, NumberFormat numberFormat) {
    return _logs.isEmpty
        ? const Center(child: Text('لاگی وجود ندارد'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(log.model.substring(0, 1).toUpperCase()),
                    ),
                    title: Text(log.model),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Provider: ${log.provider}'),
                        Text(
                          '${numberFormat.format(log.totalTokens)} توکن • ${numberFormat.format(log.cost)} تومان',
                        ),
                        if (log.createdAt != null)
                          Text(
                            DateFormat('yyyy/MM/dd HH:mm', 'fa').format(log.createdAt!),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(log.paymentMethod),
                      labelStyle: theme.textTheme.bodySmall,
                    ),
                  ),
                );
              },
            ),
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
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

