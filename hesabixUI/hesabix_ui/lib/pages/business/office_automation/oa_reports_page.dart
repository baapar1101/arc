import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/date_utils.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_ui.dart';

class OaReportsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaReportsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<OaReportsPage> createState() => _OaReportsPageState();
}

class _OaReportsPageState extends State<OaReportsPage> with SingleTickerProviderStateMixin {
  final OfficeAutomationService _svc = OfficeAutomationService();
  late TabController _tabs;
  bool _loading = true;
  Map<String, dynamic> _delay = const {};
  Map<String, dynamic> _volume = const {};
  Map<String, dynamic> _perf = const {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
      final delay = await _svc.delayReport(businessId: widget.businessId);
      final volume = await _svc.volumeReport(businessId: widget.businessId);
      final perf = await _svc.performanceReport(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _delay = delay;
        _volume = volume;
        _perf = perf;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> data) =>
      List<Map<String, dynamic>>.from((data['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaReports),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: t.oaDelayReport),
            Tab(text: t.oaVolumeReport),
            Tab(text: t.oaPerformanceReport),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _table(
                  empty: t.oaEmptyFolder,
                  rows: _itemsOf(_delay),
                  builder: (r) {
                    final days = (r['days_late'] as num?)?.toInt() ?? (r['overdue_days'] as num?)?.toInt() ?? 0;
                    final due = HesabixDateUtils.formatApiDateForDisplay(
                      r['due_at'],
                      ApiClient.getCalendarController()?.isJalali ?? true,
                      rawValue: r['due_at_raw'],
                      fallback: '',
                    );
                    return ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text('${r['subject'] ?? r['position_title'] ?? ''}'),
                      subtitle: Text(
                        [
                          r['number'] ?? r['secretariat_number'] ?? '',
                          r['to_position_title'] ?? '',
                          if (due.isNotEmpty) due,
                          t.oaDaysLate(days),
                        ].where((e) => e.toString().trim().isNotEmpty).join(' · '),
                      ),
                    );
                  },
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    OaSectionCard(
                      title: t.oaVolumeReport,
                      child: Column(
                        children: [
                          for (final e in Map<String, dynamic>.from(_volume['by_kind'] as Map? ?? const {}).entries)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(oaKindLabel(t, '${e.key}')),
                              trailing: Text('${e.value}'),
                            ),
                          for (final e in Map<String, dynamic>.from(_volume['by_status'] as Map? ?? const {}).entries)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(oaStatusLabel(t, '${e.key}')),
                              trailing: Text('${e.value}'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                _table(
                  empty: t.oaEmptyFolder,
                  rows: _itemsOf(_perf),
                  builder: (r) => ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: Text('${r['position_title'] ?? r['title'] ?? ''}'),
                    subtitle: Text('${t.oaAvgDays}: ${r['avg_days'] ?? 0}'),
                    trailing: Text('${r['count'] ?? r['completed'] ?? ''}'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _table({
    required String empty,
    required List<Map<String, dynamic>> rows,
    required Widget Function(Map<String, dynamic>) builder,
  }) {
    if (rows.isEmpty) return Center(child: Text(empty));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => Card(child: builder(rows[i])),
    );
  }
}
