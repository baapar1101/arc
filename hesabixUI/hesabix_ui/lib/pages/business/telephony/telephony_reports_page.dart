import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../services/telephony/telephony_api.dart';

class TelephonyReportsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonyReportsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<TelephonyReportsPage> createState() => _TelephonyReportsPageState();
}

class _TelephonyReportsPageState extends State<TelephonyReportsPage> with SingleTickerProviderStateMixin {
  final _api = TelephonyApi();
  late final TabController _tabs;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _operators;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await _api.reportSummary(widget.businessId);
      final o = await _api.reportOperators(widget.businessId);
      if (mounted) {
        setState(() {
          _summary = s;
          _operators = o;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totals = _summary?['totals'] as Map? ?? {};
    final hourly = (_summary?['hourly'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final ops = (_operators?['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final maxHour = hourly.fold<int>(1, (m, e) => (e['count'] as int? ?? 0) > m ? (e['count'] as int) : m);

    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش تماس‌ها'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'خلاصه'), Tab(text: 'اپراتورها')],
        ),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _StatCard('کل', '${totals['all'] ?? 0}', scheme.primary),
                        _StatCard('ورودی', '${totals['inbound'] ?? 0}', scheme.tertiary),
                        _StatCard('خروجی', '${totals['outbound'] ?? 0}', scheme.secondary),
                        _StatCard('پاسخ', '${totals['answered'] ?? 0}', const Color(0xFF159947)),
                        _StatCard('از دست‌رفته', '${totals['missed'] ?? 0}', scheme.error),
                        _StatCard('نرخ پاسخ', '${totals['answer_rate'] ?? 0}%', const Color(0xFFD97706)),
                        _StatCard('میانگین مکالمه', '${totals['avg_talk_sec'] ?? 0}s', scheme.outline),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('توزیع ساعتی', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final h in hourly)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                child: Tooltip(
                                  message: 'ساعت ${h['hour']}: ${h['count']}',
                                  child: Container(
                                    height: 20 + (((h['count'] as int? ?? 0) / maxHour) * 120),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [scheme.primary.withValues(alpha: 0.35), scheme.primary],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ops.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = ops[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text('${o['user_name']}'),
                      subtitle: Text(
                        'کل ${o['total']} · پاسخ ${o['answered']} · از دست‌رفته ${o['missed']} · خروجی ${o['outbound']}',
                      ),
                      trailing: Text('${o['avg_talk_sec']}s'),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}
