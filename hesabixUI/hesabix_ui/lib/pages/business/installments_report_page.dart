import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/services/invoice_service.dart';
import '../../utils/snackbar_helper.dart';


class InstallmentsReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final ApiClient apiClient;
  const InstallmentsReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.apiClient,
  });

  @override
  State<InstallmentsReportPage> createState() => _InstallmentsReportPageState();
}

class _StatusOption {
  const _StatusOption(this.value, this.label);
  final String? value;
  final String label;
}

class _SummaryTile {
  const _SummaryTile(this.title, this.value);
  final String title;
  final dynamic value;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, this.compact = false});

  final String title;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: compact ? 148 : 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: compact ? 2 : null,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: (compact ? theme.textTheme.titleSmall : theme.textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _InstallmentsReportPageState extends State<InstallmentsReportPage> {
  List<Map<String, dynamic>> _fiscalYears = <Map<String, dynamic>>[];
  int? _selectedFiscalYearId;
  Person? _selectedPerson;
  int? _selectedInvoiceId;
  String? _status; // pending|partial|paid|overdue
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = false;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  Map<String, dynamic>? _pagination;
  Map<String, dynamic>? _stats;
  final TextEditingController _invoiceController = TextEditingController();
  int _pageSize = 50;
  int _currentPage = 1;
  static const List<int> _pageSizeOptions = <int>[25, 50, 100, 200];
  /// نمای پرونده (گروه فاکتور) در مقابل جدول تخت اقساط
  bool _viewPortfolios = true;
  String? _bucket;
  final TextEditingController _minOverdueController = TextEditingController();
  List<Map<String, dynamic>> _groupedItems = <Map<String, dynamic>>[];

  static const double _mobileBreakpoint = 600;

  bool _isMobileWidth(double w) => w < _mobileBreakpoint;

  String? _extractFilenameFromContentDisposition(String? contentDisposition) {
    if (contentDisposition == null || contentDisposition.trim().isEmpty) return null;
    // Try RFC5987 filename*=
    final starMatch = RegExp(r"filename\*\s*=\s*utf-8''([^;]+)", caseSensitive: false).firstMatch(contentDisposition);
    if (starMatch != null) {
      final raw = starMatch.group(1);
      if (raw != null && raw.isNotEmpty) {
        try {
          return Uri.decodeFull(raw);
        } catch (_) {
          return raw;
        }
      }
    }
    // Fallback: filename="..."
    final quoted = RegExp(r'filename\s*=\s*"([^"]+)"', caseSensitive: false).firstMatch(contentDisposition);
    if (quoted != null) return quoted.group(1);
    // Fallback: filename=...
    final plain = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(contentDisposition);
    if (plain != null) return plain.group(1)?.trim();
    return null;
  }

  bool _looksLikeXlsx(List<int> bytes) {
    // XLSX is a ZIP container; signature: PK\x03\x04
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
  }

  ({String filename, String mimeType}) _resolveDownloadMeta({
    required Response<List<int>> response,
    required List<int> data,
    required String fallbackBaseName,
    required String fallbackExt,
    required String fallbackMime,
  }) {
    final contentType = response.headers.value('content-type')?.toLowerCase();
    final cd = response.headers.value('content-disposition');
    final headerFilename = _extractFilenameFromContentDisposition(cd);

    // If backend fell back to CSV, use .csv and correct mime.
    if (contentType != null && contentType.contains('text/csv')) {
      final name = headerFilename ?? '$fallbackBaseName.csv';
      return (filename: name, mimeType: 'text/csv');
    }

    // If content-type indicates PDF
    if (contentType != null && contentType.contains('application/pdf')) {
      final name = headerFilename ?? '$fallbackBaseName.pdf';
      return (filename: name, mimeType: 'application/pdf');
    }

    // If bytes look like XLSX, prefer XLSX regardless of content-type.
    if (_looksLikeXlsx(data)) {
      final name = headerFilename ?? '$fallbackBaseName.xlsx';
      return (
        filename: name,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      );
    }

    // Default: keep fallback.
    final name = headerFilename ?? '$fallbackBaseName.$fallbackExt';
    return (filename: name, mimeType: fallbackMime);
  }

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }

  Widget _buildTableArea(AppLocalizations t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewPortfolios) {
      if (_groupedItems.isEmpty) {
        return Center(child: Text(t.noDataFound));
      }
      return _buildGroupedTable(t);
    }
    if (_items.isEmpty) {
      return Center(child: Text(t.noDataFound));
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: _buildTableColumns(t),
                    rows: _items.map((row) => _buildDataRow(row, t, theme)).toList(),
                    columnSpacing: 36,
                    headingTextStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    dataTextStyle: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            _buildPagination(t),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedTable(AppLocalizations t) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: [
                      DataColumn(label: Text(t.installmentsTableInvoice)),
                      DataColumn(label: Text(t.installmentsTablePerson)),
                      DataColumn(label: Text(t.installmentsTableMobile)),
                      DataColumn(label: Text(t.installmentsGroupedNextDue)),
                      DataColumn(label: Text(t.installmentsGroupedWorstStatus)),
                      DataColumn(numeric: true, label: Text(t.installmentsGroupedInstallments)),
                      DataColumn(numeric: true, label: Text(t.installmentsGroupedPaidCount)),
                      DataColumn(numeric: true, label: Text(t.installmentsGroupedOverdueCount)),
                      DataColumn(numeric: true, label: Text(t.installmentsGroupedRemainingSum)),
                    ],
                    rows: _groupedItems.map((row) {
                      final invId = (row['invoice_id'] as num?)?.toInt() ?? 0;
                      return DataRow(
                        onSelectChanged: (_) => _openInstallmentDetail(invId),
                        cells: [
                          DataCell(Text(row['invoice_code']?.toString() ?? '-')),
                          DataCell(Text(row['person_name']?.toString() ?? '-')),
                          DataCell(Text(row['person_mobile']?.toString() ?? '-')),
                          DataCell(Text(_formatDateValue(row, 'next_due_date'))),
                          DataCell(_buildStatusChip(row['worst_status']?.toString(), t, theme)),
                          DataCell(Text(row['installment_count']?.toString() ?? '-')),
                          DataCell(Text(row['paid_installment_count']?.toString() ?? '-')),
                          DataCell(Text(row['overdue_installment_count']?.toString() ?? '-')),
                          DataCell(Text(_formatNumber(row['remaining_sum']))),
                        ],
                      );
                    }).toList(),
                    columnSpacing: 28,
                    headingTextStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    dataTextStyle: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            _buildPagination(t),
          ],
        ),
      ),
    );
  }

  List<DataColumn> _buildTableColumns(AppLocalizations t) {
    return [
      DataColumn(label: Text(t.installmentsTableInvoice)),
      DataColumn(label: Text(t.installmentsTableInstallment)),
      DataColumn(label: Text(t.installmentsTablePerson)),
      DataColumn(label: Text(t.installmentsTableMobile)),
      DataColumn(label: Text(t.installmentsTableDueDate)),
      DataColumn(label: Text(t.installmentsTableStatus)),
      DataColumn(numeric: true, label: Text(t.installmentsTablePrincipal)),
      DataColumn(numeric: true, label: Text(t.installmentsTableInterest)),
      DataColumn(numeric: true, label: Text(t.installmentsTableTotal)),
      DataColumn(numeric: true, label: Text(t.installmentsTablePaid)),
      DataColumn(numeric: true, label: Text(t.installmentsTableRemaining)),
      DataColumn(numeric: true, label: Text(t.installmentsTableLateFee)),
      DataColumn(numeric: true, label: Text(t.installmentsTableOverdueDays)),
    ];
  }

  Widget _kvLine(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _installmentPaymentsContent(AppLocalizations t, ThemeData theme, Map<String, dynamic> it) {
    final pays = (it['payments'] as List?) ?? const [];
    final stRow = it['status']?.toString();
    final paidRow = (it['paid_amount'] as num?)?.toDouble() ?? 0;
    final paidEvidence = paidRow > 0.009 || stRow == 'partial' || stRow == 'paid';
    if (pays.isEmpty && paidEvidence) {
      return Text(t.installmentsPaymentsDetailMissing, style: theme.textTheme.bodySmall);
    }
    if (pays.isEmpty) {
      return Text(t.installmentsNoPaymentsYet, style: theme.textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: pays.map((p) {
        final pm = p is Map<String, dynamic> ? p : <String, dynamic>{};
        final code = pm['document_code']?.toString() ?? '';
        final d = pm['document_date']?.toString() ?? '';
        final amt = _formatNumber(pm['amount']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('$code • $d • $amt', style: theme.textTheme.bodySmall),
        );
      }).toList(),
    );
  }

  Widget _buildScheduleNarrowCard(AppLocalizations t, ThemeData theme, Map<String, dynamic> it) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${it['seq']?.toString() ?? '-'}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _buildStatusChip(it['status']?.toString(), t, theme),
              ],
            ),
            const SizedBox(height: 8),
            _kvLine(t.installmentsTableDueDate, _formatDateValue(it, 'due_date'), theme),
            _kvLine(t.installmentsTableTotal, _formatNumber(it['total']), theme),
            _kvLine(t.installmentsTablePaid, _formatNumber(it['paid_amount']), theme),
            _kvLine(t.installmentsTableRemaining, _formatNumber(it['remaining']), theme),
            const SizedBox(height: 8),
            Text(t.installmentsPaymentsColumn, style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            _installmentPaymentsContent(t, theme, it),
          ],
        ),
      ),
    );
  }

  Widget _buildPortfolioCard(AppLocalizations t, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final invId = (row['invoice_id'] as num?)?.toInt() ?? 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openInstallmentDetail(invId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row['invoice_code']?.toString() ?? '-',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusChip(row['worst_status']?.toString(), t, theme),
                ],
              ),
              const SizedBox(height: 8),
              _kvLine(t.installmentsTablePerson, row['person_name']?.toString() ?? '-', theme),
              if ((row['person_mobile']?.toString() ?? '').isNotEmpty)
                _kvLine(t.installmentsTableMobile, row['person_mobile']?.toString() ?? '-', theme),
              _kvLine(t.installmentsGroupedNextDue, _formatDateValue(row, 'next_due_date'), theme),
              _kvLine(t.installmentsGroupedInstallments, row['installment_count']?.toString() ?? '-', theme),
              _kvLine(t.installmentsGroupedPaidCount, row['paid_installment_count']?.toString() ?? '-', theme),
              _kvLine(t.installmentsGroupedOverdueCount, row['overdue_installment_count']?.toString() ?? '-', theme),
              const SizedBox(height: 4),
              Text(
                '${t.installmentsGroupedRemainingSum}: ${_formatNumber(row['remaining_sum'])}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlatInstallmentCard(AppLocalizations t, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final invId = (row['invoice_id'] as num?)?.toInt() ?? 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openInstallmentDetail(invId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${row['invoice_code']?.toString() ?? '-'} · ${t.installmentsTableInstallment} ${row['seq']?.toString() ?? '-'}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _buildStatusChip(row['status']?.toString(), t, theme),
                ],
              ),
              const SizedBox(height: 8),
              _kvLine(t.installmentsTablePerson, row['person_name']?.toString() ?? '-', theme),
              if ((row['person_mobile']?.toString() ?? '').isNotEmpty)
                _kvLine(t.installmentsTableMobile, row['person_mobile']?.toString() ?? '-', theme),
              _kvLine(t.installmentsTableDueDate, _formatDateValue(row, 'due_date'), theme),
              _kvLine(t.installmentsTablePrincipal, _formatNumber(row['principal']), theme),
              _kvLine(t.installmentsTableInterest, _formatNumber(row['interest']), theme),
              _kvLine(t.installmentsTableTotal, _formatNumber(row['total']), theme),
              _kvLine(t.installmentsTablePaid, _formatNumber(row['paid_amount']), theme),
              _kvLine(t.installmentsTableRemaining, _formatNumber(row['remaining']), theme),
              _kvLine(t.installmentsTableLateFee, _formatNumber(row['late_fee_amount']), theme),
              _kvLine(t.installmentsTableOverdueDays, row['overdue_days']?.toString() ?? '-', theme),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(Map<String, dynamic> row, AppLocalizations t, ThemeData theme) {
    final invId = (row['invoice_id'] as num?)?.toInt() ?? 0;
    return DataRow(
      onSelectChanged: (_) => _openInstallmentDetail(invId),
      cells: [
        DataCell(Text(row['invoice_code']?.toString() ?? '-')),
        DataCell(Text(row['seq']?.toString() ?? '-')),
        DataCell(Text(row['person_name']?.toString() ?? '-')),
        DataCell(Text(row['person_mobile']?.toString() ?? '-')),
        DataCell(Text(_formatDateValue(row, 'due_date'))),
        DataCell(_buildStatusChip(row['status']?.toString(), t, theme)),
        DataCell(Text(_formatNumber(row['principal']))),
        DataCell(Text(_formatNumber(row['interest']))),
        DataCell(Text(_formatNumber(row['total']))),
        DataCell(Text(_formatNumber(row['paid_amount']))),
        DataCell(Text(_formatNumber(row['remaining']))),
        DataCell(Text(_formatNumber(row['late_fee_amount']))),
        DataCell(Text(row['overdue_days']?.toString() ?? '-')),
      ],
    );
  }

  Widget _buildStatusChip(String? status, AppLocalizations t, ThemeData theme) {
    final color = _statusColor(status, theme);
    return Chip(
      label: Text(_statusLabel(t, status)),
      backgroundColor: color.withOpacity(0.15),
      labelStyle: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Color _statusColor(String? status, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    switch (status) {
      case 'paid':
        return colorScheme.primary;
      case 'partial':
        return colorScheme.tertiary;
      case 'overdue':
        return colorScheme.error;
      default:
        return colorScheme.outline;
    }
  }

  String _statusLabel(AppLocalizations t, String? status) {
    switch (status) {
      case 'paid':
        return t.installmentsStatusPaid;
      case 'partial':
        return t.installmentsStatusPartial;
      case 'overdue':
        return t.installmentsStatusOverdue;
      case 'pending':
      default:
        return t.installmentsStatusPending;
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '-';
    final num? numeric = value is num ? value : num.tryParse(value.toString());
    if (numeric == null) return '-';
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatter = NumberFormat.decimalPattern(locale);
    return formatter.format(numeric);
  }

  String _formatDateValue(Map<String, dynamic> row, String key) {
    final dynamic value = row[key];
    if (value == null) return '-';
    if (value is String) {
      return value.isEmpty ? '-' : value;
    }
    if (value is Map<String, dynamic>) {
      final dateOnly = value['date_only'] ?? value['formatted'] ?? value['date_time'];
      if (dateOnly == null) {
        return '-';
      }
      return dateOnly.toString();
    }
    if (value is DateTime) {
      final formatter = DateFormat('yyyy/MM/dd', Localizations.localeOf(context).toLanguageTag());
      return formatter.format(value);
    }
    return value.toString();
  }

  Widget _buildPagination(AppLocalizations t, {bool compact = false}) {
    final total = (_pagination?['total'] as num?)?.toInt() ??
        (_viewPortfolios ? _groupedItems.length : _items.length);
    final totalPages = total == 0 ? 1 : ((total - 1) ~/ _pageSize) + 1;
    final canGoPrev = _currentPage > 1;
    final hasNext = _pagination?['has_next'] == true;
    final pageSizeDropdown = DropdownButton<int>(
      value: _pageSize,
      isExpanded: compact,
      onChanged: _loading
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                _pageSize = value;
                _currentPage = 1;
              });
              _fetch();
            },
      items: _pageSizeOptions
          .map(
            (size) => DropdownMenuItem<int>(
              value: size,
              child: Text(size.toString()),
            ),
          )
          .toList(),
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${t.page} $_currentPage / $totalPages',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: !_loading && canGoPrev ? () => _changePage(_currentPage - 1) : null,
                      icon: const Icon(Icons.chevron_right),
                      tooltip: t.page,
                    ),
                    IconButton(
                      onPressed: !_loading && hasNext ? () => _changePage(_currentPage + 1) : null,
                      icon: const Icon(Icons.chevron_left),
                      tooltip: t.page,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(t.installmentsRowsPerPage, style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(flex: 3, child: pageSizeDropdown),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text('${t.page} $_currentPage / $totalPages'),
          const Spacer(),
          Text(t.installmentsRowsPerPage),
          const SizedBox(width: 8),
          pageSizeDropdown,
          IconButton(
            onPressed: !_loading && canGoPrev ? () => _changePage(_currentPage - 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            onPressed: !_loading && hasNext ? () => _changePage(_currentPage + 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }

  void _changePage(int newPage) {
    if (newPage == _currentPage || newPage < 1) {
      return;
    }
    setState(() => _currentPage = newPage);
    _fetch();
  }

  List<_StatusOption> _statusOptions(AppLocalizations t) => <_StatusOption>[
        _StatusOption(null, t.installmentsStatusAll),
        _StatusOption('pending', t.installmentsStatusPending),
        _StatusOption('partial', t.installmentsStatusPartial),
        _StatusOption('overdue', t.installmentsStatusOverdue),
        _StatusOption('paid', t.installmentsStatusPaid),
      ];

  void _clearInvoiceSelection() {
    setState(() {
      _selectedInvoiceId = null;
      _invoiceController.clear();
    });
  }

  Widget _buildSummary(AppLocalizations t, {required bool compact}) {
    final stats = _stats;
    if (stats == null) {
      return const SizedBox.shrink();
    }
    final tiles = [
      _SummaryTile(t.installmentsSummaryPrincipal, stats['principal_total']),
      _SummaryTile(t.installmentsSummaryInterest, stats['interest_total']),
      _SummaryTile(t.installmentsSummaryTotal, stats['amount_total']),
      _SummaryTile(t.installmentsSummaryPaid, stats['paid_total']),
      _SummaryTile(t.installmentsSummaryRemaining, stats['remaining_total']),
      _SummaryTile(t.installmentsSummaryLateFee, stats['late_fee_total']),
    ];
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tiles.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final tile = tiles[i];
                  return _SummaryCard(
                    title: tile.title,
                    value: _formatNumber(tile.value),
                    compact: true,
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: tiles
                .map(
                  (tile) => _SummaryCard(
                    title: tile.title,
                    value: _formatNumber(tile.value),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _minOverdueController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildSearchBody({required bool includePaging}) {
    final body = <String, dynamic>{
      if (_status != null && _status!.isNotEmpty) 'status': _status,
      if (_fromDate != null) 'due_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'due_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
      if (_selectedInvoiceId != null) 'invoice_id': _selectedInvoiceId,
      if (_bucket != null && _bucket!.isNotEmpty) 'bucket': _bucket,
      if (_viewPortfolios) 'group_by': 'invoice',
    };
    final mod = int.tryParse(_minOverdueController.text.trim());
    if (mod != null && mod > 0) {
      body['min_overdue_days'] = mod;
    }
    if (includePaging) {
      body['take'] = _pageSize;
      body['skip'] = (_currentPage - 1) * _pageSize;
    }
    return body;
  }

  Map<String, dynamic> _buildExportBody() {
    final b = _buildSearchBody(includePaging: false);
    b.remove('group_by');
    return b;
  }

  Future<void> _openInstallmentDetail(int invoiceId) async {
    if (invoiceId <= 0) return;
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final dialogW = MediaQuery.sizeOf(ctx).width - 48;
        final contentWidth = dialogW.clamp(280.0, 720.0);
        final useNarrowSchedule = dialogW < 520;
        return AlertDialog(
          title: Text(t.installmentsDetailTitle),
          content: SizedBox(
            width: contentWidth,
            child: FutureBuilder<Map<String, dynamic>>(
              future: InvoiceService(apiClient: widget.apiClient).getInstallmentPlan(
                businessId: widget.businessId,
                invoiceId: invoiceId,
              ),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Text('${snap.error}');
                }
                final data = snap.data ?? const <String, dynamic>{};
                final plan = (data['plan'] is Map<String, dynamic>) ? data['plan'] as Map<String, dynamic> : const <String, dynamic>{};
                final sched = (plan['schedule'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('${data['invoice_code'] ?? ''}'),
                      const SizedBox(height: 12),
                      if (useNarrowSchedule)
                        ...sched.map((it) => _buildScheduleNarrowCard(t, theme, it))
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            showCheckboxColumn: false,
                            columns: [
                              DataColumn(label: Text(t.installmentsTableInstallment)),
                              DataColumn(label: Text(t.installmentsTableDueDate)),
                              DataColumn(label: Text(t.installmentsTableStatus)),
                              DataColumn(numeric: true, label: Text(t.installmentsTableTotal)),
                              DataColumn(numeric: true, label: Text(t.installmentsTablePaid)),
                              DataColumn(numeric: true, label: Text(t.installmentsTableRemaining)),
                              DataColumn(label: Text(t.installmentsPaymentsColumn)),
                            ],
                            rows: sched.map((it) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(it['seq']?.toString() ?? '-')),
                                  DataCell(Text(_formatDateValue(it, 'due_date'))),
                                  DataCell(_buildStatusChip(it['status']?.toString(), t, theme)),
                                  DataCell(Text(_formatNumber(it['total']))),
                                  DataCell(Text(_formatNumber(it['paid_amount']))),
                                  DataCell(Text(_formatNumber(it['remaining']))),
                                  DataCell(_installmentPaymentsContent(t, theme, it)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.close)),
          ],
        );
      },
    );
  }

  Future<void> _loadFiscalYears() async {
    try {
      final resp = await widget.apiClient.get<Map<String, dynamic>>(
        '/api/v1/business/${widget.businessId}/fiscal-years',
      );
      final data = Map<String, dynamic>.from(resp.data?['data'] ?? {});
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      setState(() {
        _fiscalYears = items;
        _selectedFiscalYearId = items.firstWhere(
          (e) => (e['is_current'] == true),
          orElse: () => (items.isNotEmpty ? items.first : const <String, dynamic>{}),
        )['id'] as int?;
      });
      if (mounted) {
        await _fetch(resetPage: true);
      }
    } catch (_) {}
  }

  Future<void> _fetch({bool resetPage = false}) async {
    if (resetPage) {
      _currentPage = 1;
    }
    setState(() => _loading = true);
    try {
      final body = _buildSearchBody(includePaging: true);

      final res = await widget.apiClient.post<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/installments/search',
        data: body,
      );
      final data = Map<String, dynamic>.from(res.data?['data'] ?? const {});
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      final grouped = (data['grouped_items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      final pagination = (data['pagination'] is Map<String, dynamic>) ? Map<String, dynamic>.from(data['pagination'] as Map) : <String, dynamic>{};
      final stats = (data['stats'] is Map<String, dynamic>) ? Map<String, dynamic>.from(data['stats'] as Map) : <String, dynamic>{};
      setState(() {
        _items = items;
        _groupedItems = grouped;
        _pagination = pagination.isEmpty ? null : pagination;
        _stats = stats.isEmpty ? null : stats;
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: '${t.installmentsFetchError}: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = _isMobileWidth(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.installmentsReportTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _fetch(),
            icon: const Icon(Icons.refresh),
            tooltip: t.reload,
          ),
        ],
      ),
      body: SafeArea(
        child: isMobile
            ? _buildMobileBody(t)
            : Column(
                children: [
                  _buildFilters(t, compact: false),
                  _buildSummary(t, compact: false),
                  Expanded(child: _buildTableArea(t)),
                ],
              ),
      ),
    );
  }

  Widget _buildMobileBody(AppLocalizations t) {
    final hasRows = _viewPortfolios ? _groupedItems.isNotEmpty : _items.isNotEmpty;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildFilters(t, compact: true)),
        SliverToBoxAdapter(child: _buildSummary(t, compact: true)),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (_viewPortfolios ? _groupedItems.isEmpty : _items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text(t.noDataFound)),
          )
        else if (_viewPortfolios)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final row = _groupedItems[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildPortfolioCard(t, row),
                  );
                },
                childCount: _groupedItems.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final row = _items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildFlatInstallmentCard(t, row),
                  );
                },
                childCount: _items.length,
              ),
            ),
          ),
        if (!_loading && hasRows) ...[
          SliverToBoxAdapter(child: _buildPagination(t, compact: true)),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ],
    );
  }

  Widget _buildViewModeChips(AppLocalizations t) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(t.installmentsViewPortfolios),
          selected: _viewPortfolios,
          onSelected: (sel) {
            if (!sel) return;
            setState(() {
              _viewPortfolios = true;
              _currentPage = 1;
            });
            _fetch(resetPage: true);
          },
        ),
        ChoiceChip(
          label: Text(t.installmentsViewFlat),
          selected: !_viewPortfolios,
          onSelected: (sel) {
            if (!sel) return;
            setState(() {
              _viewPortfolios = false;
              _currentPage = 1;
            });
            _fetch(resetPage: true);
          },
        ),
      ],
    );
  }

  Widget _buildFilterFields(AppLocalizations t, {required bool fullWidth}) {
    Widget sized(Widget child, double desktopW) {
      return SizedBox(
        width: fullWidth ? double.infinity : desktopW,
        child: child,
      );
    }

    final fields = <Widget>[
      sized(
        DropdownButtonFormField<int>(
          value: _selectedFiscalYearId,
          items: _fiscalYears
              .map((fy) => DropdownMenuItem<int>(
                    value: fy['id'] as int?,
                    child: Text('${fy['title'] ?? ''}'),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedFiscalYearId = v),
          decoration: InputDecoration(
            labelText: t.installmentsFiltersFiscalYear,
            border: const OutlineInputBorder(),
          ),
        ),
        220,
      ),
      sized(
        DropdownButtonFormField<String?>(
          value: _status,
          items: _statusOptions(t)
              .map((opt) => DropdownMenuItem<String?>(
                    value: opt.value,
                    child: Text(opt.label),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _status = v),
          decoration: InputDecoration(
            labelText: t.installmentsFiltersStatus,
            border: const OutlineInputBorder(),
          ),
        ),
        200,
      ),
      sized(
        DropdownButtonFormField<String?>(
          value: _bucket,
          items: <DropdownMenuItem<String?>>[
            DropdownMenuItem<String?>(value: null, child: Text(t.installmentsBucketAll)),
            DropdownMenuItem<String?>(value: 'unpaid', child: Text(t.installmentsBucketUnpaid)),
            DropdownMenuItem<String?>(value: 'upcoming', child: Text(t.installmentsBucketUpcoming)),
            DropdownMenuItem<String?>(value: 'overdue_only', child: Text(t.installmentsBucketOverdueOnly)),
          ],
          onChanged: (v) => setState(() => _bucket = v),
          decoration: InputDecoration(
            labelText: t.installmentsFiltersBucket,
            border: const OutlineInputBorder(),
          ),
        ),
        220,
      ),
      sized(
        TextFormField(
          controller: _minOverdueController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: t.installmentsMinOverdueDaysLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        120,
      ),
      sized(
        DateInputField(
          value: _fromDate,
          onChanged: (d) => setState(() => _fromDate = d),
          calendarController: widget.calendarController,
          labelText: t.installmentsFiltersDueFrom,
        ),
        200,
      ),
      sized(
        DateInputField(
          value: _toDate,
          onChanged: (d) => setState(() => _toDate = d),
          calendarController: widget.calendarController,
          labelText: t.installmentsFiltersDueTo,
        ),
        200,
      ),
      sized(
        PersonComboboxWidget(
          businessId: widget.businessId,
          selectedPerson: _selectedPerson,
          onChanged: (p) => setState(() {
            _selectedPerson = p;
            _selectedInvoiceId = null;
            _invoiceController.clear();
          }),
          label: t.installmentsFiltersPerson,
          hintText: t.installmentsFiltersPersonHint,
        ),
        240,
      ),
      sized(
        TextFormField(
          controller: _invoiceController,
          readOnly: true,
          decoration: InputDecoration(
            labelText: t.installmentsFiltersInvoice,
            hintText: t.installmentsFiltersInvoiceHint,
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedInvoiceId != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: t.clear,
                    onPressed: _loading ? null : _clearInvoiceSelection,
                  ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: t.installmentsFiltersInvoiceButton,
                  onPressed: _loading ? null : _pickInvoice,
                ),
              ],
            ),
          ),
        ),
        240,
      ),
    ];

    if (fullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            fields[i],
            if (i < fields.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: fields,
    );
  }

  Widget _buildFilterActionButtons(AppLocalizations t, {required bool fullWidth}) {
    final searchBtn = FilledButton.icon(
      onPressed: _loading ? null : () => _fetch(resetPage: true),
      icon: const Icon(Icons.search),
      label: Text(t.search),
    );
    final excelBtn = FilledButton.icon(
      onPressed: _loading ? null : _exportExcel,
      icon: const Icon(Icons.table_chart),
      label: Text(t.exportToExcel),
    );
    final pdfBtn = FilledButton.icon(
      onPressed: _loading ? null : _exportPdf,
      icon: const Icon(Icons.picture_as_pdf),
      label: Text(t.exportToPdf),
    );
    if (fullWidth) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [searchBtn, excelBtn, pdfBtn],
      );
    }
    return Row(
      children: [
        searchBtn,
        const SizedBox(width: 12),
        excelBtn,
        const SizedBox(width: 12),
        pdfBtn,
      ],
    );
  }

  Widget _buildFilters(AppLocalizations t, {required bool compact}) {
    final desktopBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildViewModeChips(t),
        const SizedBox(height: 12),
        _buildFilterFields(t, fullWidth: false),
        const SizedBox(height: 16),
        _buildFilterActionButtons(t, fullWidth: false),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildViewModeChips(t),
                  ),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(t.filtersAndSearch),
                      initiallyExpanded: false,
                      childrenPadding: EdgeInsets.zero,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildFilterFields(t, fullWidth: true),
                              const SizedBox(height: 16),
                              _buildFilterActionButtons(t, fullWidth: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: desktopBody,
              ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    setState(() => _loading = true);
    try {
      final body = _buildExportBody();

      final resp = await widget.apiClient.post<List<int>>(
        '/api/v1/invoices/business/${widget.businessId}/installments/export/excel',
        data: body,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {'Accept': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, text/csv'},
        ),
      );
      final data = resp.data ?? <int>[];
      if (kIsWeb) {
        final meta = _resolveDownloadMeta(
          response: resp,
          data: data,
          fallbackBaseName: 'installments_${widget.businessId}',
          fallbackExt: 'xlsx',
          fallbackMime: 'application/octet-stream',
        );
        await web_utils.saveBytesAsFileWeb(
          data,
          meta.filename,
          mimeType: meta.mimeType,
        );
      } else {
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.show(context, message: t.installmentsExportWebOnly);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: '${t.installmentsExportError}: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _loading = true);
    try {
      final body = _buildExportBody();

      final resp = await widget.apiClient.post<List<int>>(
        '/api/v1/invoices/business/${widget.businessId}/installments/export/pdf',
        data: body,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {'Accept': 'application/pdf'},
        ),
      );
      final data = resp.data ?? <int>[];
      if (kIsWeb) {
        final meta = _resolveDownloadMeta(
          response: resp,
          data: data,
          fallbackBaseName: 'installments_${widget.businessId}',
          fallbackExt: 'pdf',
          fallbackMime: 'application/pdf',
        );
        await web_utils.saveBytesAsFileWeb(
          data,
          meta.filename,
          mimeType: meta.mimeType,
        );
      } else {
        if (mounted) {
          final t = AppLocalizations.of(context);
          SnackBarHelper.show(context, message: t.installmentsExportWebOnly);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: '${t.installmentsExportError}: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickInvoice() async {
    final svc = InvoiceService(apiClient: widget.apiClient);
    final t = AppLocalizations.of(context);
    final TextEditingController q = TextEditingController();
    List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    bool loading = false;
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            Future<void> run() async {
              setStateDialog(() {
                loading = true;
              });
              try {
                final filters = <String, dynamic>{};
                if (_selectedPerson != null) {
                  filters['person_id'] = _selectedPerson!.id;
                }
                final data = await svc.searchInvoices(
                  businessId: widget.businessId,
                  page: 1,
                  limit: 20,
                  search: q.text.trim().isEmpty ? null : q.text.trim(),
                  filters: filters.isEmpty ? null : filters,
                );
                final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
                setStateDialog(() {
                  results = items;
                });
              } catch (_) {
                setStateDialog(() {
                  results = <Map<String, dynamic>>[];
                });
              } finally {
                setStateDialog(() {
                  loading = false;
                });
              }
            }
            return AlertDialog(
              title: Text(t.installmentsInvoicePickerTitle),
              content: SizedBox(
                width: (MediaQuery.sizeOf(ctx).width - 48).clamp(280.0, 520.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: q,
                      decoration: InputDecoration(
                        labelText: t.installmentsInvoicePickerSearchLabel,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => run(),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: run,
                      icon: const Icon(Icons.search),
                      label: Text(t.search),
                    ),
                    const SizedBox(height: 8),
                    if (loading) const LinearProgressIndicator(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (c, i) {
                          final it = results[i];
                          return ListTile(
                            leading: const Icon(Icons.receipt_long),
                            title: Text(it['code']?.toString() ?? '-'),
                            subtitle: Text(it['description']?.toString() ?? ''),
                            onTap: () => Navigator.pop(ctx, it),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
              ],
            );
          },
        );
      },
    ).then((picked) {
      if (picked is Map<String, dynamic>) {
        final id = picked['id'] as int?;
        if (id != null) {
          setState(() {
            _selectedInvoiceId = id;
            _invoiceController.text = id.toString();
          });
        }
      }
    });
  }
}



