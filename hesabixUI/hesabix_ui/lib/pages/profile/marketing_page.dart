import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/referral_store.dart';
import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../widgets/jalali_date_picker.dart';
import '../../widgets/date_input_field.dart';

class MarketingPage extends StatefulWidget {
  final CalendarController calendarController;
  const MarketingPage({super.key, required this.calendarController});

  @override
  State<MarketingPage> createState() => _MarketingPageState();
}

class _MarketingPageState extends State<MarketingPage> {
  String? _referralCode;
  bool _loading = false;
  int? _todayCount;
  int? _monthCount;
  int? _totalCount;
  int? _rangeCount;
  DateTime? _fromDate;
  DateTime? _toDate;
  // list state
  bool _loadingList = false;
  int _page = 1;
  int _limit = 10;
  int _total = 0;
  List<Map<String, dynamic>> _items = const [];
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadReferralCode();
    _fetchStats();
    _fetchList();
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
        _page = 1;
        _fetchList(withRange: true);
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadReferralCode() async {
    final code = await ReferralStore.getUserReferralCode();
    if (!mounted) return;
    setState(() {
      _referralCode = code;
    });
  }

  Future<void> _fetchStats({bool withRange = false}) async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final params = <String, dynamic>{};
      if (withRange && _fromDate != null && _toDate != null) {
        // use ISO8601 date-time boundaries: start at 00:00, end next day 00:00
        final start = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
        final endExclusive = DateTime(_toDate!.year, _toDate!.month, _toDate!.day).add(const Duration(days: 1));
        params['start'] = start.toIso8601String();
        params['end'] = endExclusive.toIso8601String();
      }
      final res = await api.get<Map<String, dynamic>>('/api/v1/auth/referrals/stats', query: params);
      final body = res.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          setState(() {
            _todayCount = (data['today'] as num?)?.toInt();
            _monthCount = (data['this_month'] as num?)?.toInt();
            _totalCount = (data['total'] as num?)?.toInt();
            _rangeCount = (data['range'] as num?)?.toInt();
          });
        }
      }
    } catch (_) {
      // silent fail: نمایش خطا ضروری نیست
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _fetchList({bool withRange = false}) async {
    setState(() => _loadingList = true);
    try {
      final api = ApiClient();
      final params = <String, dynamic>{
        'page': _page,
        'limit': _limit,
      };
      final q = _searchCtrl.text.trim();
      if (q.isNotEmpty) params['search'] = q;
      if (withRange && _fromDate != null && _toDate != null) {
        final start = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
        final endExclusive = DateTime(_toDate!.year, _toDate!.month, _toDate!.day).add(const Duration(days: 1));
        params['start'] = start.toIso8601String();
        params['end'] = endExclusive.toIso8601String();
      }
      final res = await api.get<Map<String, dynamic>>('/api/v1/auth/referrals/list', query: params);
      final body = res.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          setState(() {
            _items = items;
            _total = (data['total'] as num?)?.toInt() ?? 0;
            _page = (data['page'] as num?)?.toInt() ?? _page;
            _limit = (data['limit'] as num?)?.toInt() ?? _limit;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  void _applyFilters() {
    _page = 1;
    _fetchStats(withRange: true);
    _fetchList(withRange: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final code = _referralCode;
    final inviteLink = (code == null || code.isEmpty) ? null : ReferralStore.buildInviteLink(code);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.marketingReport, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (code == null || code.isEmpty) Text(t.loading, style: Theme.of(context).textTheme.bodyMedium),
          if (inviteLink != null) ...[
            Row(
              children: [
                Expanded(child: SelectableText(inviteLink)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: inviteLink));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(t.copied)));
                  },
                  icon: const Icon(Icons.link),
                  label: Text(t.copyLink),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(title: t.today, value: _todayCount, loading: _loading),
              _StatCard(title: t.thisMonth, value: _monthCount, loading: _loading),
              _StatCard(title: t.total, value: _totalCount, loading: _loading),
              _StatCard(title: '${t.dateFrom}-${t.dateTo}', value: _rangeCount, loading: _loading),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DateInputField(
                  value: _fromDate,
                  onChanged: (date) {
                    setState(() {
                      _fromDate = date;
                    });
                  },
                  labelText: t.dateFrom,
                  calendarController: widget.calendarController,
                  enabled: !_loading,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DateInputField(
                  value: _toDate,
                  onChanged: (date) {
                    setState(() {
                      _toDate = date;
                    });
                  },
                  labelText: t.dateTo,
                  calendarController: widget.calendarController,
                  enabled: !_loading,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading || _fromDate == null || _toDate == null ? null : _applyFilters,
                child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t.applyFilter),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t.email,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _limit,
                items: const [10, 20, 50].map((e) => DropdownMenuItem(value: e, child: Text('per: ' + e.toString()))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _limit = v);
                  _page = 1;
                  _fetchList(withRange: true);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (_loadingList)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      DataColumn(label: Text(t.firstName)),
                      DataColumn(label: Text(t.lastName)),
                      DataColumn(label: Text(t.email)),
                      DataColumn(label: Text(t.register)),
                    ],
                    rows: _items.map((e) {
                      final createdAt = (e['created_at'] as String?) ?? '';
                      DateTime? date;
                      if (createdAt.isNotEmpty) {
                        try {
                          date = DateTime.parse(createdAt.substring(0, 10));
                        } catch (e) {
                          // Ignore parsing errors
                        }
                      }
                      final dateStr = date != null 
                          ? HesabixDateUtils.formatForDisplay(date, widget.calendarController.isJalali)
                          : '';
                      return DataRow(cells: [
                        DataCell(Text((e['first_name'] ?? '') as String)),
                        DataCell(Text((e['last_name'] ?? '') as String)),
                        DataCell(Text((e['email'] ?? '') as String)),
                        DataCell(Text(dateStr)),
                      ]);
                    }).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Text('${((_page - 1) * _limit + 1).clamp(0, _total)} - ${(_page * _limit).clamp(0, _total)} / $_total'),
                      const Spacer(),
                      IconButton(
                        onPressed: _page > 1 && !_loadingList ? () { setState(() => _page -= 1); _fetchList(withRange: true); } : null,
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Prev',
                      ),
                      IconButton(
                        onPressed: (_page * _limit) < _total && !_loadingList ? () { setState(() => _page += 1); _fetchList(withRange: true); } : null,
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Next',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title; 
  final int? value; 
  final bool loading;
  const _StatCard({required this.title, required this.value, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              loading
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text((value ?? 0).toString(), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}


