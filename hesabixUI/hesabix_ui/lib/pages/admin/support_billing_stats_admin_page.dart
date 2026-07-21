import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/support_billing_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';

class SupportBillingStatsAdminPage extends StatefulWidget {
  const SupportBillingStatsAdminPage({super.key});

  @override
  State<SupportBillingStatsAdminPage> createState() => _SupportBillingStatsAdminPageState();
}

class _SupportBillingStatsAdminPageState extends State<SupportBillingStatsAdminPage> {
  late final AdminSupportBillingService _service;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _invoices = const [];

  @override
  void initState() {
    super.initState();
    _service = AdminSupportBillingService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await _service.getStats();
      final invoices = await _service.listInvoices(limit: 30);
      final items = (invoices['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _invoices = items;
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

  String _money(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
    return formatWithThousands(n, decimalPlaces: 0);
  }

  Widget _kpi(String title, String value, IconData icon) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodySmall),
                  Text(value, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('آمار پشتیبانی غیر رایگان'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 280,
                            child: _kpi('درآمد دوره', '${_money(s?['revenue'])} ریال', Icons.payments),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi('پرداخت موفق', '${s?['paid_count'] ?? 0}', Icons.check_circle),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi('پرداخت ناموفق', '${s?['failed_count'] ?? 0}', Icons.error_outline),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi('اشتراک فعال', '${s?['active_subscriptions'] ?? 0}', Icons.workspace_premium),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi('در شرف انقضا (۷ روز)', '${s?['expiring_in_7_days'] ?? 0}', Icons.schedule),
                          ),
                          SizedBox(
                            width: 280,
                            child: _kpi('MRR تقریبی', '${_money(s?['approximate_mrr'])} ریال', Icons.trending_up),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('تفکیک پلن‌های فعال', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...((s?['subscriptions_by_period_months'] as Map? ?? {}).entries.map(
                            (e) => ListTile(
                              title: Text('${e.key} ماهه'),
                              trailing: Text('${e.value} اشتراک'),
                            ),
                          )),
                      const SizedBox(height: 16),
                      Text('آخرین صورت‌حساب‌ها', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ..._invoices.map(
                        (inv) => Card(
                          child: ListTile(
                            title: Text(inv['code']?.toString() ?? ''),
                            subtitle: Text(
                              'کاربر #${inv['user_id']} · ${inv['plan_name'] ?? '-'} · '
                              '${_money(inv['amount'])} · ${inv['status']}',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
