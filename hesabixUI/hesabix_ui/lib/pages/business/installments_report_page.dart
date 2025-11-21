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
  const _SummaryCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }

  Widget _buildTableArea(AppLocalizations t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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

  List<DataColumn> _buildTableColumns(AppLocalizations t) {
    return [
      DataColumn(label: Text(t.installmentsTableInvoice)),
      DataColumn(label: Text(t.installmentsTableInstallment)),
      DataColumn(label: Text(t.installmentsTablePerson)),
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

  DataRow _buildDataRow(Map<String, dynamic> row, AppLocalizations t, ThemeData theme) {
    return DataRow(
      cells: [
        DataCell(Text(row['invoice_code']?.toString() ?? '-')),
        DataCell(Text(row['seq']?.toString() ?? '-')),
        DataCell(Text(row['person_name']?.toString() ?? '-')),
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

  Widget _buildPagination(AppLocalizations t) {
    final total = (_pagination?['total'] as num?)?.toInt() ?? _items.length;
    final totalPages = total == 0 ? 1 : ((total - 1) ~/ _pageSize) + 1;
    final canGoPrev = _currentPage > 1;
    final hasNext = _pagination?['has_next'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text('${t.page} $_currentPage / $totalPages'),
          const Spacer(),
          Text(t.installmentsRowsPerPage),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _pageSize,
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
          ),
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

  Widget _buildSummary(AppLocalizations t) {
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
    super.dispose();
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
    } catch (_) {}
  }

  Future<void> _fetch({bool resetPage = false}) async {
    if (resetPage) {
      _currentPage = 1;
    }
    setState(() => _loading = true);
    try {
      final body = <String, dynamic>{
        if (_status != null && _status!.isNotEmpty) 'status': _status,
        if (_fromDate != null) 'due_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'due_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
        if (_selectedInvoiceId != null) 'invoice_id': _selectedInvoiceId,
        'take': _pageSize,
        'skip': (_currentPage - 1) * _pageSize,
      };

      final res = await widget.apiClient.post<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/installments/search',
        data: body,
      );
      final data = Map<String, dynamic>.from(res.data?['data'] ?? const {});
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      final pagination = (data['pagination'] is Map<String, dynamic>) ? Map<String, dynamic>.from(data['pagination'] as Map) : <String, dynamic>{};
      final stats = (data['stats'] is Map<String, dynamic>) ? Map<String, dynamic>.from(data['stats'] as Map) : <String, dynamic>{};
      setState(() {
        _items = items;
        _pagination = pagination.isEmpty ? null : pagination;
        _stats = stats.isEmpty ? null : stats;
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.installmentsFetchError}: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
        child: Column(
          children: [
            _buildFilters(t),
            _buildSummary(t),
            Expanded(child: _buildTableArea(t)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<int>(
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
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
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
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      value: _fromDate,
                      onChanged: (d) => setState(() => _fromDate = d),
                      calendarController: widget.calendarController,
                      labelText: t.installmentsFiltersDueFrom,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      value: _toDate,
                      onChanged: (d) => setState(() => _toDate = d),
                      calendarController: widget.calendarController,
                      labelText: t.installmentsFiltersDueTo,
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: PersonComboboxWidget(
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
                  ),
                  SizedBox(
                    width: 240,
                    child: TextFormField(
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
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _loading ? null : () => _fetch(resetPage: true),
                    icon: const Icon(Icons.search),
                    label: Text(t.search),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _exportExcel,
                    icon: const Icon(Icons.download),
                    label: Text(t.exportToExcel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    setState(() => _loading = true);
    try {
      final body = <String, dynamic>{
        if (_status != null && _status!.isNotEmpty) 'status': _status,
        if (_fromDate != null) 'due_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'due_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
        if (_selectedInvoiceId != null) 'invoice_id': _selectedInvoiceId,
      };

      final bytes = await widget.apiClient.post<List<int>>(
        '/api/v1/invoices/business/${widget.businessId}/installments/export/excel',
        data: body,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {'Accept': 'application/octet-stream'},
        ),
      );
      final data = bytes.data ?? <int>[];
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          data,
          'installments_${widget.businessId}.xlsx',
          mimeType: 'application/octet-stream',
        );
      } else {
        if (mounted) {
          final t = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.installmentsExportWebOnly)),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.installmentsExportError}: ${e.toString()}'), backgroundColor: Colors.red),
      );
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
                width: 520,
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



