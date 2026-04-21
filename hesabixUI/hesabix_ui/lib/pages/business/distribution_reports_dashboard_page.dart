import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

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
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final visits = (_data?['visits'] is Map) ? _data!['visits'] as Map<String, dynamic> : null;
    final ret = (_data?['returns'] is Map) ? _data!['returns'] as Map<String, dynamic> : null;
    final byUser = _data?['by_user'];

    return Scaffold(
      appBar: AppBar(title: Text(t.reportsDistributionDashboardTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.reportsDistributionDashboardSubtitle),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _from,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _from = d);
                    },
                    child: Text('${_iso(_from)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _to,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setState(() => _to = d);
                    },
                    child: Text('${_iso(_to)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _targetUserCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'User ID (optional, managers)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loading ? null : _load, child: Text(t.distributionRefresh)),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            if (!_loading && visits != null) ...[
              Text('Visits total: ${visits['total_records']}'),
              Text('Completed: ${visits['completed']} / Cancelled: ${visits['cancelled']} / In progress: ${visits['in_progress']}'),
              const SizedBox(height: 8),
              Text('Outcomes: ${visits['by_outcome']}'),
            ],
            if (!_loading && ret != null) ...[
              const SizedBox(height: 12),
              Text('Returns pending: ${ret['pending']} / approved: ${ret['approved']} / rejected: ${ret['rejected']}'),
            ],
            if (!_loading && byUser is List && byUser.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('By user:', style: Theme.of(context).textTheme.titleSmall),
              ...byUser.map<Widget>((row) {
                final m = Map<String, dynamic>.from(row as Map);
                return Text('user ${m['user_id']}: ${m['visit_count']} visits');
              }),
            ],
          ],
        ),
      ),
    );
  }
}
