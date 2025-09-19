import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/referral_store.dart';
import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/data_table/data_table.dart';

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
  Set<int> _selectedRows = <int>{};

  @override
  void initState() {
    super.initState();
    _loadReferralCode();
    _fetchStats();
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
      // silent fail
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Localizations.of<AppLocalizations>(context, AppLocalizations)!;
    final code = _referralCode;
    final inviteLink = (code == null || code.isEmpty) ? null : ReferralStore.buildInviteLink(code);
    final theme = Theme.of(context);
    
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.analytics, 
                      size: 24, 
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.marketingReport,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          t.marketingReportSubtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Referral Link Card
            if (inviteLink != null) ...[
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.link, 
                              color: theme.colorScheme.onPrimaryContainer,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            t.yourReferralLink,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                inviteLink,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: inviteLink));
                                if (!mounted) return;
                                final messenger = ScaffoldMessenger.of(context);
                                messenger
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text(t.copied),
                                      backgroundColor: theme.colorScheme.primary,
                                    ),
                                  );
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: Text(t.copyLink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // Stats Cards
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _StatCard(
                  title: t.today,
                  value: _todayCount,
                  loading: _loading,
                  icon: Icons.today,
                  color: Colors.blue,
                ),
                _StatCard(
                  title: t.thisMonth,
                  value: _monthCount,
                  loading: _loading,
                  icon: Icons.calendar_month,
                  color: Colors.green,
                ),
                _StatCard(
                  title: t.total,
                  value: _totalCount,
                  loading: _loading,
                  icon: Icons.people,
                  color: Colors.orange,
                ),
                _StatCard(
                  title: '${t.dateFrom}-${t.dateTo}',
                  value: _rangeCount,
                  loading: _loading,
                  icon: Icons.date_range,
                  color: Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Data Table using new widget
            DataTableWidget<Map<String, dynamic>>(
              config: DataTableConfig<Map<String, dynamic>>(
                title: t.referralList,
                endpoint: '/api/v1/auth/referrals/list',
                excelEndpoint: '/api/v1/auth/referrals/export/excel',
                pdfEndpoint: '/api/v1/auth/referrals/export/pdf',
                getExportParams: () => {
                  'user_id': 'current_user', // Example parameter
                },
                            columns: [
                  TextColumn(
                    'first_name',
                    t.firstName,
                    sortable: true,
                    searchable: true,
                    width: ColumnWidth.small,
                  ),
                  TextColumn(
                    'last_name',
                    t.lastName,
                    sortable: true,
                    searchable: true,
                    width: ColumnWidth.small,
                  ),
                  TextColumn(
                    'email',
                    t.email,
                    sortable: true,
                    searchable: true,
                    width: ColumnWidth.large,
                  ),
                  DateColumn(
                    'created_at',
                    t.register,
                    sortable: true,
                    searchable: true,
                    width: ColumnWidth.medium,
                    showTime: false,
                  ),
                ],
                searchFields: ['first_name', 'last_name', 'email'],
                filterFields: ['first_name', 'last_name', 'email', 'created_at'],
                dateRangeField: 'created_at',
                showSearch: true,
                showFilters: true,
                showColumnSearch: true,
                showPagination: true,
                showActiveFilters: true,
                enableSorting: true,
                enableGlobalSearch: true,
                enableDateRangeFilter: true,
                showRowNumbers: true,
                enableRowSelection: true,
                enableMultiRowSelection: true,
                selectedRows: _selectedRows,
                onRowSelectionChanged: (selectedRows) {
                                setState(() {
                    _selectedRows = selectedRows;
                                });
                              },
                defaultPageSize: 20,
                pageSizeOptions: const [10, 20, 50, 100],
                showRefreshButton: true,
                showClearFiltersButton: true,
                emptyStateMessage: 'هیچ معرفی‌ای یافت نشد',
                loadingMessage: 'در حال بارگذاری معرفی‌ها...',
                errorMessage: 'خطا در بارگذاری معرفی‌ها',
                enableHorizontalScroll: true,
                minTableWidth: 600,
                showBorder: true,
                borderRadius: BorderRadius.circular(8),
                padding: const EdgeInsets.all(16),
                onDateRangeApply: (fromDate, toDate) {
                                setState(() {
                    _fromDate = fromDate;
                    _toDate = toDate;
                  });
                  _fetchStats(withRange: true);
                },
                onDateRangeClear: () {
                  setState(() {
                    _fromDate = null;
                    _toDate = null;
                  });
                  _fetchStats();
                },
              ),
              fromJson: (json) => json,
              calendarController: widget.calendarController,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int? value;
  final bool loading;
  final IconData icon;
  final Color color;
  
  const _StatCard({
    required this.title,
    required this.value,
    required this.loading,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              loading
                  ? const SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      (value ?? 0).toString(),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}