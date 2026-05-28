import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as Hd;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

/// گزارش خلاصهٔ ویزیت و مرجوعی (مرکز گزارشات).
class DistributionReportsDashboardPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const DistributionReportsDashboardPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<DistributionReportsDashboardPage> createState() =>
      _DistributionReportsDashboardPageState();
}

class _DistributionReportsDashboardPageState extends State<DistributionReportsDashboardPage> {
  final DistributionService _svc = DistributionService();
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = false;
  final TextEditingController _targetUserCtl = TextEditingController();

  bool get _jalali => widget.calendarController.isJalali;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tid = int.tryParse(_targetUserCtl.text.trim());
      final d = await _svc.getReportsDashboard(
        businessId: widget.businessId,
        fromDate: _iso(_from),
        toDate: _iso(_to),
        targetUserId: tid,
      );
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final d = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: isFrom ? _from : _to,
      helpText: AppLocalizations.of(context).distributionSelectDate,
    );
    if (d != null) setState(() => isFrom ? _from = d : _to = d);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _targetUserCtl.dispose();
    super.dispose();
  }

  Widget _statCard(String title, String value, IconData icon, ColorScheme cs) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.primary, size: 22),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final visits = (_data?['visits'] is Map) ? _data!['visits'] as Map<String, dynamic> : null;
    final ret = (_data?['returns'] is Map) ? _data!['returns'] as Map<String, dynamic> : null;
    final byUser = _data?['by_user'];
    final byOutcome = visits?['by_outcome'] is Map ? visits!['by_outcome'] as Map<String, dynamic> : null;

    return Scaffold(
      appBar: AppBar(title: Text(t.reportsDistributionDashboardTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(t.reportsDistributionDashboardSubtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.date_range),
                    label: Text(Hd.HesabixDateUtils.formatForDisplay(_from, _jalali)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.date_range),
                    label: Text(Hd.HesabixDateUtils.formatForDisplay(_to, _jalali)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _targetUserCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.distributionTeamPlanUserId,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.analytics_outlined),
              label: Text(t.distributionRefresh),
            ),
            const SizedBox(height: 24),
            if (!_loading && visits != null) ...[
              Text(t.distributionReportsVisitsTotal, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statCard(
                    t.distributionReportsVisitsTotal,
                    '${visits['total_records'] ?? 0}',
                    Icons.route,
                    cs,
                  ),
                  const SizedBox(width: 8),
                  _statCard(
                    t.distributionStatusCompleted,
                    '${visits['completed'] ?? 0}',
                    Icons.check_circle_outline,
                    cs,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statCard(
                    t.distributionStatusCancelled,
                    '${visits['cancelled'] ?? 0}',
                    Icons.cancel_outlined,
                    cs,
                  ),
                  const SizedBox(width: 8),
                  _statCard(
                    t.distributionStatusInProgress,
                    '${visits['in_progress'] ?? 0}',
                    Icons.timelapse,
                    cs,
                  ),
                ],
              ),
              if (byOutcome != null && byOutcome.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(t.distributionReportsOutcomeBreakdown, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...byOutcome.entries.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.pie_chart_outline),
                    title: Text(e.key),
                    trailing: Text('${e.value}'),
                  ),
                ),
              ],
            ],
            if (!_loading && ret != null) ...[
              const SizedBox(height: 20),
              Text(t.distributionReportsReturnsSummary, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statCard('pending', '${ret['pending'] ?? 0}', Icons.hourglass_top, cs),
                  const SizedBox(width: 8),
                  _statCard('approved', '${ret['approved'] ?? 0}', Icons.thumb_up_alt_outlined, cs),
                  const SizedBox(width: 8),
                  _statCard('rejected', '${ret['rejected'] ?? 0}', Icons.thumb_down_alt_outlined, cs),
                ],
              ),
            ],
            if (!_loading && byUser is List && byUser.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(t.distributionPermissionReportsTeam, style: Theme.of(context).textTheme.titleMedium),
              ...byUser.map<Widget>((row) {
                final m = Map<String, dynamic>.from(row as Map);
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('user ${m['user_id']}'),
                  trailing: Text('${m['visit_count']}'),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
