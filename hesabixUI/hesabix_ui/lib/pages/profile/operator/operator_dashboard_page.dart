import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/support_activity_chart.dart';

class OperatorDashboardPage extends StatefulWidget {
  final CalendarController? calendarController;

  const OperatorDashboardPage({super.key, this.calendarController});

  @override
  State<OperatorDashboardPage> createState() => _OperatorDashboardPageState();
}

class _OperatorDashboardPageState extends State<OperatorDashboardPage> {
  final SupportService _supportService = SupportService(ApiClient());
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _overdue = [];
  List<Map<String, dynamic>> _activity = [];

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
      final results = await Future.wait([
        _supportService.getOperatorDashboardStats(),
        _supportService.getOperatorDashboardOverdue(),
        _supportService.getOperatorDashboardActivity(days: 7),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _overdue = results[1] as List<Map<String, dynamic>>;
        _activity = results[2] as List<Map<String, dynamic>>;
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد پشتیبانی'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          TextButton.icon(
            onPressed: () => context.go('/user/profile/operator'),
            icon: const Icon(Icons.inbox),
            label: const Text('صندوق ورودی'),
          ),
        ],
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
                      _buildStats(theme),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _legendDot(theme.colorScheme.primary, 'ایجاد شده'),
                          const SizedBox(width: 16),
                          _legendDot(Colors.green, 'حل شده'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SupportActivityChart(activity: _activity),
                      const SizedBox(height: 24),
                      Text('تیکت‌های معوق SLA', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_overdue.isEmpty)
                        const Text('تیکت معوقی وجود ندارد')
                      else
                        ..._overdue.map((t) => _overdueTile(t, theme)),
                    ],
                  ),
                ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  Widget _buildStats(ThemeData theme) {
    final s = _stats ?? {};
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statCard('باز', '${s['open_count'] ?? 0}', Icons.inbox, theme.colorScheme.primary),
        _statCard('من', '${s['my_open_count'] ?? 0}', Icons.person, theme.colorScheme.secondary),
        _statCard('معوق SLA', '${s['overdue_count'] ?? 0}', Icons.warning_amber, Colors.red),
        _statCard('حل‌شده امروز', '${s['resolved_today_count'] ?? 0}', Icons.check_circle, Colors.green),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              Text(title),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overdueTile(Map<String, dynamic> t, ThemeData theme) {
    final id = t['id'];
    final slaStatus = '${t['sla_status'] ?? 'breached'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: SlaIndicator(slaStatus: slaStatus),
        title: Text('#$id — ${t['title'] ?? ''}'),
        subtitle: Text('${t['user_name'] ?? ''} • ${t['priority'] ?? ''}'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => context.go('/user/profile/operator?ticket=$id'),
      ),
    );
  }
}
