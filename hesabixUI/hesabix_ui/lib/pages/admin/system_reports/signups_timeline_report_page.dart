import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/date_formatters.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

/// گزارش تعداد عضویت در بازهٔ تاریخی با تجمیع روز/هفته/ماه.
class SignupsTimelineReportPage extends StatefulWidget {
  const SignupsTimelineReportPage({super.key});

  @override
  State<SignupsTimelineReportPage> createState() => _SignupsTimelineReportPageState();
}

class _SignupsTimelineReportPageState extends State<SignupsTimelineReportPage> {
  final _api = ApiClient();
  bool _loading = false;
  bool _hasRunQuery = false;
  String? _error;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String _granularity = 'day';
  List<Map<String, dynamic>> _rows = [];
  int? _totalInRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '/api/v1/users/stats/signups-timeline',
        query: {
          'start_date': _isoDate(_range.start),
          'end_date': _isoDate(_range.end),
          'granularity': _granularity,
        },
      );
      if (!mounted) return;
      final body = res.data;
      if (!mounted) return;
      final data = body != null && body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : null;
      if (data == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _hasRunQuery = true;
          _rows = [];
          _totalInRange = null;
        });
        return;
      }
      final raw = data['buckets'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map<String, dynamic>) {
            list.add(e);
          }
        }
      }
      final tot = data['total_in_range'];
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasRunQuery = true;
        _rows = list;
        _totalInRange = tot is int ? tot : int.tryParse('$tot');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasRunQuery = true;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _pickRange() async {
    final t = AppLocalizations.of(context);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
      helpText: t.systemReportSignupsPickRange,
    );
    if (picked != null && mounted) {
      setState(() => _range = picked);
    }
  }

  String _formatPeriod(dynamic v) => DateFormatters.formatServerDateTime(v);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.systemReportSignupsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings/reports'),
        ),
        actions: [
          IconButton(
            tooltip: t.systemReportRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t.systemReportSignupsDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            label: Text(
              '${_isoDate(_range.start)}  —  ${_isoDate(_range.end)}',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: t.systemReportGranularityLabel,
                    border: const OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _granularity,
                      items: [
                        DropdownMenuItem(value: 'day', child: Text(t.systemReportGranularityDay)),
                        DropdownMenuItem(value: 'week', child: Text(t.systemReportGranularityWeek)),
                        DropdownMenuItem(value: 'month', child: Text(t.systemReportGranularityMonth)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _granularity = v);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _load,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t.systemReportApplyRange),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          if (_totalInRange != null) ...[
            const SizedBox(height: 16),
            Text(
              '${t.systemReportTotalInRange}: $_totalInRange',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 16),
          if (_hasRunQuery && _rows.isEmpty && !_loading && _error == null)
            Text(
              t.systemReportSignupsEmptyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            )
          else if (_rows.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(t.systemReportPeriodColumn)),
                  DataColumn(label: Text(t.systemReportCountColumn), numeric: true),
                ],
                rows: _rows.map((b) {
                  return DataRow(
                    cells: [
                      DataCell(Text(_formatPeriod(b['period_start']))),
                      DataCell(Text('${b['count'] ?? '—'}')),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
