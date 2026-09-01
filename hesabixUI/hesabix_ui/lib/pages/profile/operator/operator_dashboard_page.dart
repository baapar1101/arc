import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/support/sla_indicator.dart';
import 'package:hesabix_ui/widgets/support/support_activity_chart.dart';
import 'package:hesabix_ui/widgets/support/operator_inbox_list.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

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

  void _openInbox(OperatorInboxView view) {
    context.go('/user/profile/operator?view=${view.name}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('داشبورد پشتیبانی'),
        actions: [
          IconButton(onPressed: _load, icon: Icon(Icons.refresh)),
          TextButton.icon(
            onPressed: () => context.go('/user/profile/operator'),
            icon: const Icon(Icons.inbox_outlined),
            label: const Text('صندوق ورودی'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStats(theme),
                      const SizedBox(height: 20),
                      Text('فعالیت ۷ روز اخیر', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _legendDot(theme.colorScheme.primary, 'ایجاد شده'),
                          const SizedBox(width: 16),
                          _legendDot(SemanticColorResolver.positive(context), 'حل شده'),
                        ],
                      ),
                      SizedBox(height: 8),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SupportActivityChart(activity: _activity),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text('تیکت‌های معوق SLA', style: theme.textTheme.titleMedium),
                          const Spacer(),
                          TextButton(onPressed: () => _openInbox(OperatorInboxView.overdue), child: Text('مشاهده همه')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_overdue.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, color: SemanticColorResolver.positive(context)),
                                const SizedBox(width: 12),
                                const Expanded(child: Text('تیکت معوقی وجود ندارد — عالی است!')),
                              ],
                            ),
                          ),
                        )
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
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildStats(ThemeData theme) {
    final s = _stats ?? {};
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 48) / 5;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _statCard('باز', '${s['open_count'] ?? 0}', Icons.inbox_outlined, theme.colorScheme.primary, () => _openInbox(OperatorInboxView.all), width: w.clamp(120, 200)),
            _statCard('من', '${s['my_open_count'] ?? 0}', Icons.person_outline, theme.colorScheme.secondary, () => _openInbox(OperatorInboxView.mine), width: w.clamp(120, 200)),
            _statCard('خوانده‌نشده', '${s['unread_count'] ?? 0}', Icons.mark_email_unread_outlined, theme.colorScheme.tertiary, () => _openInbox(OperatorInboxView.unread), width: w.clamp(120, 200)),
            _statCard('معوق SLA', '${s['overdue_count'] ?? 0}', Icons.warning_amber_outlined, theme.colorScheme.error, () => _openInbox(OperatorInboxView.overdue), width: w.clamp(120, 200)),
            _statCard('حل‌شده امروز', '${s['resolved_today_count'] ?? 0}', Icons.check_circle_outline, SemanticColorResolver.positive(context), () => _openInbox(OperatorInboxView.all), width: w.clamp(120, 200)),
          ],
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color, VoidCallback onTap, {required double width}) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 10),
                Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                Text(title),
              ],
            ),
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
        title: Text('#$id — ${t['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${t['user_name'] ?? ''} • ${t['priority'] ?? ''}'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => context.go('/user/profile/operator?ticket=$id'),
      ),
    );
  }
}
