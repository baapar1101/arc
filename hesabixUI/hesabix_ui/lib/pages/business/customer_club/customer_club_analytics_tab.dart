import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/customer_club_service.dart';
import '../../../utils/snackbar_helper.dart';

/// تب تحلیل RFM و CLV — طراحی کارتی با فیلتر سگمنت و جستجو.
class CustomerClubAnalyticsTab extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CustomerClubAnalyticsTab({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CustomerClubAnalyticsTab> createState() => _CustomerClubAnalyticsTabState();
}

class _CustomerClubAnalyticsTabState extends State<CustomerClubAnalyticsTab> {
  final CustomerClubService _svc = CustomerClubService();
  final TextEditingController _searchCtl = TextEditingController();

  bool _loadingBoot = true;
  bool _loadingPersons = false;
  bool _recalculating = false;

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _rows = [];
  int _totalPersons = 0;
  int _skip = 0;
  final int _pageSize = 25;

  bool _analysisDisabled = false;

  String _sortField = 'monetary_total';
  String _sortDir = 'desc';
  String? _segmentFilter;

  bool get _canManage =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('customer_club', 'manage');

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loadingBoot = true);
    try {
      final settings = await _svc.getSettings(businessId: widget.businessId);
      final rfm = settings['rfm_analytics_enabled'] == true;
      final clv = settings['clv_analytics_enabled'] == true;
      if (mounted) {
        setState(() {
          _analysisDisabled = !rfm && !clv;
        });
      }
      await _loadSummary();
      if (!_analysisDisabled) {
        await _loadPersons(reset: true);
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    } finally {
      if (mounted) setState(() => _loadingBoot = false);
    }
  }

  Future<void> _loadSummary() async {
    try {
      final data = await _svc.getRfmSummary(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _summary = Map<String, dynamic>.from(data));
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    }
  }

  Future<void> _loadPersons({bool reset = false}) async {
    if (_analysisDisabled) return;
    setState(() => _loadingPersons = true);
    final skip = reset ? 0 : _skip;
    try {
      final data = await _svc.listRfmPersons(
        businessId: widget.businessId,
        skip: skip,
        limit: _pageSize,
        segmentLabel: _segmentFilter,
        q: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        sort: _sortField,
        sortDir: _sortDir,
      );
      if (!mounted) return;
      final items = data['items'];
      final total = data['total'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        if (reset) {
          _rows = list;
        } else {
          _rows = [..._rows, ...list];
        }
        _totalPersons = total is int ? total : int.tryParse('$total') ?? 0;
        _skip = _rows.length;
      });
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    } finally {
      if (mounted) setState(() => _loadingPersons = false);
    }
  }

  Future<void> _onRecalculate() async {
    if (!_canManage) return;
    setState(() => _recalculating = true);
    try {
      await _svc.recalculateRfm(businessId: widget.businessId);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).customerClubAnalyticsRecalculateDone);
      await _loadSummary();
      await _loadPersons(reset: true);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is num && v == v.roundToDouble()) return v.toStringAsFixed(0).replaceFirst(RegExp(r'\.?0+$'), '');
    return v.toString();
  }

  List<Map<String, dynamic>> _segmentChipsData() {
    final segs = _summary?['segments'];
    if (segs is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in segs) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_loadingBoot) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_analysisDisabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights_outlined, size: 56, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                t.customerClubAnalyticsDisabled,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final win = _summary?['window'];
    final months = win is Map ? int.tryParse('${win['months']}') ?? 12 : 12;
    final start = win is Map ? '${win['start'] ?? ''}' : '';
    final end = win is Map ? '${win['end'] ?? ''}' : '';

    return RefreshIndicator(
      onRefresh: () async {
        await _loadSummary();
        await _loadPersons(reset: true);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    borderRadius: BorderRadius.circular(16),
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_graph, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t.customerClubAnalyticsTitle,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (_canManage)
                                FilledButton.tonalIcon(
                                  onPressed: _recalculating ? null : _onRecalculate,
                                  icon: _recalculating
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.calculate_outlined, size: 20),
                                  label: Text(_recalculating ? t.customerClubAnalyticsRecalculating : t.customerClubAnalyticsRecalculate),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t.customerClubAnalyticsWindow(start, end, months),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              _StatChip(
                                icon: Icons.groups_outlined,
                                label: t.customerClubAnalyticsTotalPersons,
                                value: '${_summary?['total_persons'] ?? _totalPersons}',
                                theme: theme,
                              ),
                              _StatChip(
                                icon: Icons.schedule,
                                label: t.customerClubAnalyticsLastRun,
                                value: '${_summary?['computed_at'] ?? '—'}'.split('.').first,
                                theme: theme,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(t.customerClubAnalyticsHint, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: t.customerClubAnalyticsSearch,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    onSubmitted: (_) => _loadPersons(reset: true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: t.customerClubAnalyticsSortLabel,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                          ),
                          value: _sortField,
                          items: [
                            DropdownMenuItem(value: 'monetary_total', child: Text(t.customerClubAnalyticsSortMonetary)),
                            DropdownMenuItem(value: 'recency_days', child: Text(t.customerClubAnalyticsSortRecency)),
                            DropdownMenuItem(value: 'frequency_count', child: Text(t.customerClubAnalyticsSortFrequency)),
                            DropdownMenuItem(value: 'clv_estimate', child: Text(t.customerClubAnalyticsSortClv)),
                            DropdownMenuItem(value: 'segment_label', child: Text(t.customerClubAnalyticsSortSegment)),
                            DropdownMenuItem(value: 'composite_score', child: Text(t.customerClubAnalyticsSortComposite)),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _sortField = v);
                            _loadPersons(reset: true);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: '',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                          ),
                          value: _sortDir,
                          items: [
                            DropdownMenuItem(value: 'desc', child: Text(t.customerClubSortDesc)),
                            DropdownMenuItem(value: 'asc', child: Text(t.customerClubSortAsc)),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _sortDir = v);
                            _loadPersons(reset: true);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(t.customerClubAnalyticsFilterSegment, style: theme.textTheme.labelLarge),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: FilterChip(
                            label: Text(t.customerClubAnalyticsAllSegments),
                            selected: _segmentFilter == null,
                            onSelected: (_) {
                              setState(() => _segmentFilter = null);
                              _loadPersons(reset: true);
                            },
                          ),
                        ),
                        ..._segmentChipsData().map((seg) {
                          final lab = seg['label']?.toString() ?? '';
                          final cnt = seg['count'];
                          final sel = _segmentFilter == lab;
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: FilterChip(
                              label: Text(lab.isEmpty ? '($cnt)' : '$lab ($cnt)'),
                              selected: sel,
                              onSelected: (_) {
                                setState(() => _segmentFilter = lab.isEmpty ? null : lab);
                                _loadPersons(reset: true);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _loadingPersons ? null : () => _loadPersons(reset: true),
                        icon: const Icon(Icons.refresh),
                        label: Text(t.customerClubAnalyticsRefresh),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_rows.isEmpty && !_loadingPersons)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t.customerClubAnalyticsNoData,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final hasMoreButton = _rows.length < _totalPersons && _totalPersons > 0;
                    if (i >= _rows.length) {
                      if (!hasMoreButton) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: OutlinedButton(
                            onPressed: _loadingPersons ? null : () => _loadPersons(reset: false),
                            child: Text(t.customerClubAnalyticsLoadMore),
                          ),
                        ),
                      );
                    }
                    final r = _rows[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        title: Text(
                          r['person_name']?.toString() ?? '—',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${t.customerClubAnalyticsSegment}: ${r['segment_label'] ?? '—'} · CLV: ${_fmt(r['clv_estimate'])}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _kv(theme, t.customerClubAnalyticsR, _fmt(r['r_score'])),
                                _kv(theme, t.customerClubAnalyticsF, _fmt(r['f_score'])),
                                _kv(theme, t.customerClubAnalyticsM, _fmt(r['m_score'])),
                                _kv(theme, t.customerClubAnalyticsCell, r['rfm_cell']?.toString() ?? '—'),
                                _kv(theme, t.customerClubAnalyticsRecency, _fmt(r['recency_days'])),
                                _kv(theme, t.customerClubAnalyticsFrequency, _fmt(r['frequency_count'])),
                                _kv(theme, t.customerClubAnalyticsMonetary, _fmt(r['monetary_total'])),
                                _kv(theme, t.customerClubAnalyticsCLV, _fmt(r['clv_estimate'])),
                                _kv(theme, t.customerClubCompositeScore, _fmt(r['composite_score'])),
                                _kv(theme, t.customerClubAnalyticsLoyaltyBalance, _fmt(r['loyalty_balance_points'])),
                                _kv(theme, t.customerClubPerson, '${r['person_id'] ?? ''}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: _rows.length + ((_rows.length < _totalPersons && _totalPersons > 0) ? 1 : 0),
                ),
              ),
            ),
          if (_loadingPersons && _rows.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(k, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
