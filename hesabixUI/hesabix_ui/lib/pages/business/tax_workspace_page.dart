import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/errors/api_error.dart';
import '../../utils/responsive_helper.dart';
import '../../services/job_service.dart';

/// صفحه کارپوشه مودیان (لیست فاکتورهای موجود در کارپوشه و وضعیت ارسال به سامانه)
class TaxWorkspacePage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const TaxWorkspacePage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<TaxWorkspacePage> createState() => _TaxWorkspacePageState();
}

class _TaxWorkspacePageState extends State<TaxWorkspacePage> {
  final GlobalKey _tableKey = GlobalKey();

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedInvoiceType;
  String? _selectedTaxStatus;
  int _selectedCount = 0;

  void _refreshData() {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(t, isMobile),
            _buildFilters(t, isMobile),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<Map<String, dynamic>>(
                  key: _tableKey,
                  config: _buildTableConfig(t),
                  fromJson: (json) => Map<String, dynamic>.from(json),
                  calendarController: widget.calendarController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, bool isMobile) {
    final theme = Theme.of(context);
    final padding = ResponsiveHelper.getPadding(context);
    return Container(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.taxWorkspaceTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  t.taxWorkspaceSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Quick Actions و Help
          if (!isMobile)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQuickActionButton(
                  context,
                  t.taxQuickActionSendAllPending,
                  Icons.send,
                  () => _onQuickAction('send_all_pending'),
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  t.taxQuickActionInquireAllSent,
                  Icons.search,
                  () => _onQuickAction('inquire_all_sent'),
                ),
                const SizedBox(width: 8),
                _buildQuickActionButton(
                  context,
                  t.taxQuickActionRetryAllFailed,
                  Icons.refresh,
                  () => _onQuickAction('retry_all_failed'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  tooltip: t.taxHelpTooltip,
                  onPressed: () => _showHelpDialog(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(BuildContext context, String label, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Future<void> _onQuickAction(String action) async {
    final t = AppLocalizations.of(context);
    try {
      final api = widget.apiClient;
      final response = await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/tax-workspace/quick-actions',
        data: {'action': action},
      );
      
      final body = response.data;
      final data = (body?['data'] as Map<String, dynamic>?) ?? const {};
      final jobId = data['job_id'] as String?;
      
      if (jobId != null && jobId.isNotEmpty) {
        // نمایش progress dialog
        _showJobProgressDialog(jobId, 0);
      } else {
        SnackBarHelper.showSuccess(context, message: data['message']?.toString() ?? t.taxOperationSuccess);
        _refreshData();
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxOperationError(ErrorExtractor.forContext(e, context)));
    }
  }

  void _showHelpDialog() {
    final t = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(t.taxHelpTitle),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHelpSection(
                t.taxHelpSectionStatuses,
                [
                  t.taxHelpStatusNotSent,
                  t.taxHelpStatusPending,
                  t.taxHelpStatusSent,
                  t.taxHelpStatusFinalized,
                  t.taxHelpStatusFailed,
                ],
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                t.taxHelpSectionQuickActions,
                [
                  t.taxHelpQuickActionSendPending,
                  t.taxHelpQuickActionInquireSent,
                  t.taxHelpQuickActionRetryFailed,
                ],
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                t.taxHelpSectionImportantNotes,
                [
                  t.taxHelpNoteValidateBeforeSend,
                  t.taxHelpNoteFailedInDLQ,
                  t.taxHelpNoteTimeline,
                  t.taxHelpNoteExport,
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(item)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildFilters(AppLocalizations t, bool isMobile) {
    final padding = ResponsiveHelper.getPadding(context);
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // نوع فاکتور - در موبایل scrollable
          SingleChildScrollView(
            scrollDirection: isMobile ? Axis.horizontal : Axis.vertical,
            child: SegmentedButton<String?>(
              segments: [
                ButtonSegment<String?>(
                  value: null,
                  label: Text(t.all),
                  icon: const Icon(Icons.all_inclusive),
                ),
                ButtonSegment<String?>(
                  value: 'invoice_sales',
                  label: Text(t.invoiceTypeSales),
                  icon: const Icon(Icons.sell_outlined),
                ),
                ButtonSegment<String?>(
                  value: 'invoice_sales_return',
                  label: Text(t.invoiceTypeSalesReturn),
                  icon: const Icon(Icons.undo_outlined),
                ),
              ],
              selected: _selectedInvoiceType != null ? {_selectedInvoiceType} : <String?>{},
              onSelectionChanged: (set) {
                setState(() => _selectedInvoiceType = set.first);
                _refreshData();
              },
            ),
          ),
          const SizedBox(height: 8),
          // فیلترهای تاریخ و وضعیت
          if (isMobile)
            // موبایل: Column layout
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DateInputField(
                        value: _fromDate,
                        calendarController: widget.calendarController,
                        onChanged: (date) {
                          setState(() => _fromDate = date);
                          _refreshData();
                        },
                        labelText: t.dateFrom,
                        hintText: t.selectDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DateInputField(
                        value: _toDate,
                        calendarController: widget.calendarController,
                        onChanged: (date) {
                          setState(() => _toDate = date);
                          _refreshData();
                        },
                        labelText: t.dateTo,
                        hintText: t.selectDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                        });
                        _refreshData();
                      },
                      icon: const Icon(Icons.clear),
                      tooltip: t.clearDateFilter,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedTaxStatus,
                  decoration: InputDecoration(
                    labelText: t.taxStatus,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(t.all),
                    ),
                    DropdownMenuItem(
                      value: 'not_sent',
                      child: Text(t.taxStatusNotSent),
                    ),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text(t.taxStatusPending),
                    ),
                    DropdownMenuItem(
                      value: 'sent',
                      child: Text(t.taxStatusSent),
                    ),
                    DropdownMenuItem(
                      value: 'finalized',
                      child: Text(t.taxStatusFinalized),
                    ),
                    DropdownMenuItem(
                      value: 'failed',
                      child: Text(t.taxStatusFailed),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedTaxStatus = value);
                    _refreshData();
                  },
                ),
              ],
            )
          else
            // دسکتاپ/تبلت: Row layout
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(
                        child: DateInputField(
                          value: _fromDate,
                          calendarController: widget.calendarController,
                          onChanged: (date) {
                            setState(() => _fromDate = date);
                            _refreshData();
                          },
                          labelText: t.dateFrom,
                          hintText: t.selectDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DateInputField(
                          value: _toDate,
                          calendarController: widget.calendarController,
                          onChanged: (date) {
                            setState(() => _toDate = date);
                            _refreshData();
                          },
                          labelText: t.dateTo,
                          hintText: t.selectDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _fromDate = null;
                            _toDate = null;
                          });
                          _refreshData();
                        },
                        icon: const Icon(Icons.clear),
                        tooltip: t.clearDateFilter,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedTaxStatus,
                    decoration: InputDecoration(
                      labelText: t.taxStatus,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(t.all),
                      ),
                      DropdownMenuItem(
                        value: 'not_sent',
                        child: Text(t.taxStatusNotSent),
                      ),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text(t.taxStatusPending),
                      ),
                      DropdownMenuItem(
                        value: 'sent',
                        child: Text(t.taxStatusSent),
                      ),
                      DropdownMenuItem(
                        value: 'finalized',
                        child: Text(t.taxStatusFinalized),
                      ),
                      DropdownMenuItem(
                        value: 'failed',
                        child: Text(t.taxStatusFailed),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedTaxStatus = value);
                      _refreshData();
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/invoices/business/${widget.businessId}/tax-workspace/search',
      title: t.taxWorkspaceTitle,
      businessId: widget.businessId,
      reportModuleKey: 'tax_workspace',
      reportSubtype: 'list',
      enableRowSelection: true,
      enableMultiRowSelection: true,
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showColumnSearch: true,
      showRefreshButton: true,
      showClearFiltersButton: true,
      defaultPageSize: 20,
      pageSizeOptions: const [10, 20, 50, 100],
      customHeaderActions: [
        Tooltip(
          message: t.taxSendSelectedTooltip,
          child: FilledButton.icon(
            onPressed: _selectedCount > 0 ? _onSendSelectedToSystem : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(t.taxSendSelectedButton(_selectedCount)),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: t.taxRemoveSelectedTooltip,
          child: FilledButton.icon(
            onPressed: _selectedCount > 0 ? _onRemoveSelectedFromWorkspace : null,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.remove_circle_outline),
            label: Text(t.taxRemoveSelectedButton(_selectedCount)),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: t.taxInquireSelectedTooltip,
          child: OutlinedButton.icon(
            onPressed: _selectedCount > 0 ? _onInquireSelectedStatus : null,
            icon: const Icon(Icons.sync),
            label: Text(t.taxInquireSelectedButton(_selectedCount)),
          ),
        ),
      ],
      columns: [
        ActionColumn(
          'actions',
          t.actions,
          actions: [
            DataTableAction(
              icon: Icons.cloud_upload_outlined,
              label: t.taxSendSingle,
              onTap: (item) => _onSendSingleToSystem(item as Map<String, dynamic>),
              enabled: (item) {
                final map = item as Map<String, dynamic>;
                final status = map['tax_status']?.toString() ?? 'not_sent';
                // غیرفعال کردن برای فاکتورهای ارسال شده یا قطعی شده
                return status != 'sent' && status != 'finalized';
              },
            ),
            DataTableAction(
              icon: Icons.remove_circle_outline,
              label: t.taxRemoveFromWorkspaceSingle,
              onTap: (item) => _onRemoveSingleFromWorkspace(item as Map<String, dynamic>),
              enabled: (item) {
                final map = item as Map<String, dynamic>;
                final status = map['tax_status']?.toString() ?? 'not_sent';
                // غیرفعال کردن برای فاکتورهای ارسال شده یا قطعی شده
                return status != 'sent' && status != 'finalized';
              },
            ),
          ],
        ),
        TextColumn(
          'code',
          t.code,
          formatter: (item) => (item as Map<String, dynamic>)['code']?.toString() ?? '',
          width: ColumnWidth.small,
        ),
        TextColumn(
          'document_type_name',
          t.type,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            return map['document_type_name']?.toString() ??
                map['document_type']?.toString() ??
                '';
          },
          width: ColumnWidth.medium,
        ),
        DateColumn(
          'document_date',
          t.documentDate,
          width: ColumnWidth.medium,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            final raw = map['document_date'];
            DateTime? dt;
            if (raw is String) {
              dt = DateTime.tryParse(raw);
            } else if (raw is DateTime) {
              dt = raw;
            }
            if (dt == null) return '-';
            return HesabixDateUtils.formatForDisplay(dt, widget.calendarController.isJalali);
          },
        ),
        TextColumn(
          'total_amount',
          t.totalAmount,
          width: ColumnWidth.large,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            final v = map['total_amount'];
            if (v == null) return '-';
            final currencyCode = map['currency_code']?.toString() ?? t.taxCurrencyRial;
            return '${v.toString()} $currencyCode';
          },
        ),
        TextColumn(
          'tax_status',
          t.taxStatus,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            final status = map['tax_status']?.toString() ?? 'not_sent';
            switch (status) {
              case 'pending':
                return t.taxStatusPending;
              case 'sent':
                return t.taxStatusSent;
              case 'finalized':
                return t.taxStatusFinalized;
              case 'failed':
                return t.taxStatusFailed;
              case 'not_sent':
              default:
                return t.taxStatusNotSent;
            }
          },
          width: ColumnWidth.medium,
        ),
        TextColumn(
          'tax_tracking_code',
          t.taxTrackingCode,
          formatter: (item) => (item as Map<String, dynamic>)['tax_tracking_code']?.toString() ?? '-',
          width: ColumnWidth.medium,
        ),
        DateColumn(
          'tax_last_send_at',
          t.taxLastSendAt,
          width: ColumnWidth.medium,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            final raw = map['tax_last_send_at'];
            DateTime? dt;
            if (raw is String) {
              dt = DateTime.tryParse(raw);
            } else if (raw is DateTime) {
              dt = raw;
            }
            if (dt == null) return '-';
            return HesabixDateUtils.formatForDisplay(dt, widget.calendarController.isJalali);
          },
        ),
      ],
      searchFields: const ['code'],
      filterFields: const ['document_type', 'tax_status'],
      dateRangeField: 'document_date',
      onRowSelectionChanged: (rows) {
        setState(() {
          _selectedCount = rows.length;
        });
      },
      additionalParams: {
        'document_type': _selectedInvoiceType,
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        'tax_status': _selectedTaxStatus,
      },
      emptyStateMessage: t.taxWorkspaceEmpty,
      loadingMessage: t.taxWorkspaceLoading,
      errorMessage: t.taxWorkspaceError,
      expandBodyHeightToFitRows: true,
    );
  }

  Future<void> _onSendSingleToSystem(Map<String, dynamic> item) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxSendSingleDialogTitle),
        content: Text(t.taxSendSingleDialogMessage(item['code']?.toString() ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(t.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final api = widget.apiClient;
      await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/${item['id']}/tax-workspace/send-to-system',
        data: const <String, dynamic>{},
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      SnackBarHelper.showSuccess(context, message: t.taxSendSuccess);
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      // استخراج invoice_id از item برای نمایش بهتر خطاها
      final invoiceId = item['id'] is int ? item['id'] as int : int.tryParse(item['id']?.toString() ?? '');
      if (!_handleTaxSendError(e, invoiceId: invoiceId)) {
        SnackBarHelper.showError(context, message: t.taxSendErrorWithMessage(ErrorExtractor.forContext(e, context)));
      }
    }
  }

  Future<void> _onRemoveSingleFromWorkspace(Map<String, dynamic> item) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxRemoveFromWorkspaceDialogTitle),
        content: Text(t.taxRemoveFromWorkspaceDialogMessage(item['code']?.toString() ?? '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.remove_circle_outline),
            label: Text(t.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final api = widget.apiClient;
      await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/${item['id']}/tax-workspace/remove',
        data: const <String, dynamic>{},
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      SnackBarHelper.showSuccess(context, message: t.taxRemoveFromWorkspaceSuccess);
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxRemoveFromWorkspaceErrorWithMessage(ErrorExtractor.forContext(e, context)));
    }
  }

  Future<void> _onSendSelectedToSystem() async {
    final t = AppLocalizations.of(context);
    final dynamic state = _tableKey.currentState;
    if (state == null) return;
    List<Map<String, dynamic>> selectedItems = const [];
    try {
      // ignore: avoid_dynamic_calls
      selectedItems = state.getSelectedItems().cast<Map<String, dynamic>>();
    } catch (_) {
      selectedItems = const [];
    }
    if (selectedItems.isEmpty) return;

    // فیلتر کردن فاکتورهای ارسال شده
    final sendableItems = selectedItems.where((item) {
      final status = item['tax_status']?.toString() ?? 'not_sent';
      return status != 'sent' && status != 'finalized';
    }).toList();

    if (sendableItems.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: t.taxSendSelectedAllAlreadySent,
      );
      return;
    }

    if (sendableItems.length < selectedItems.length) {
      final skippedCount = selectedItems.length - sendableItems.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.taxSendSelectedDialogTitle),
          content: Text(t.taxSendSelectedSomeAlreadySent(skippedCount, sendableItems.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(t.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.taxSendSelectedDialogTitle),
          content: Text(t.taxSendSelectedDialogMessage(sendableItems.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(t.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      final api = widget.apiClient;
      final ids = sendableItems.map((e) => e['id']).toList();
      final response = await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/tax-workspace/send-to-system-batch',
        data: {'invoice_ids': ids, 'use_background': true},
      );
      final body = response.data;
      final result = (body?['data'] as Map<String, dynamic>?) ?? const {};
      final jobId = result['job_id'] as String?;
      
      // اگر job_id وجود داشت، از background job استفاده شده
      if (jobId != null && jobId.isNotEmpty) {
        // نمایش progress dialog با polling
        if (!mounted) return;
        _showJobProgressDialog(jobId, sendableItems.length);
      } else {
        // Fallback: synchronous processing
        final failed = (result['failed'] as List<dynamic>?) ?? const [];
        final succeeded = (result['succeeded'] as List<dynamic>?) ?? const [];

        if (!mounted) return;

        if (failed.isEmpty) {
          SnackBarHelper.showSuccess(context, message: t.taxSendSelectedSuccess);
        } else {
          _showBatchResultDialog(succeeded.length, failed);
        }
        _refreshData();
      }
    } catch (e) {
      if (!mounted) return;
      if (!_handleTaxSendError(e)) {
        SnackBarHelper.showError(context, message: t.taxSendSelectedErrorWithMessage(ErrorExtractor.forContext(e, context)));
      }
    }
  }

  void _showJobProgressDialog(String jobId, int totalCount) {
    final t = AppLocalizations.of(context);
    int sentCount = 0;
    int failedCount = 0;
    bool isCompleted = false;
    List<dynamic> failedItems = [];
    
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          // Polling برای وضعیت job
          Future<void> pollJobStatus() async {
            try {
              final api = widget.apiClient;
              final response = await api.get<Map<String, dynamic>>('/api/v1/jobs/$jobId');
              final jobData = (response.data?['data'] as Map<String, dynamic>?) ?? const {};
              final jobState = jobData['state'] as String? ?? 'unknown';
              
              if (jobState == 'finished' || jobState == 'completed') {
                final result = jobData['result'] as Map<String, dynamic>?;
                if (result != null) {
                  final succeeded = (result['succeeded'] as List<dynamic>?) ?? const [];
                  final failed = (result['failed'] as List<dynamic>?) ?? const [];
                  
                  setState(() {
                    sentCount = succeeded.length;
                    failedCount = failed.length;
                    failedItems = failed;
                    isCompleted = true;
                  });
                  
                  // بستن dialog و نمایش نتیجه
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    if (!mounted) return;
                    
                    if (failed.isEmpty) {
                      SnackBarHelper.showSuccess(context, message: t.taxSendSelectedSuccess);
                    } else {
                      _showBatchResultDialog(sentCount, failed);
                    }
                    _refreshData();
                  }
                }
              } else if (jobState == 'failed' || jobState == 'error') {
                final error = jobData['error'] as String? ?? t.taxUnknownError;
                setState(() {
                  isCompleted = true;
                });
                if (context.mounted) {
                  Navigator.of(context).pop();
                  if (!mounted) return;
                  SnackBarHelper.showError(context, message: t.taxSendSelectedErrorWithMessage(error));
                  _refreshData();
                }
              } else {
                // هنوز در حال اجرا است - ادامه polling
                await Future.delayed(const Duration(seconds: 2));
                if (context.mounted && !isCompleted) {
                  pollJobStatus();
                }
              }
            } catch (e) {
              // در صورت خطا، polling را متوقف می‌کنیم
              if (context.mounted) {
                Navigator.of(context).pop();
                if (!mounted) return;
                SnackBarHelper.showError(context, message: t.taxSendSelectedErrorWithMessage(ErrorExtractor.forContext(e, context)));
                _refreshData();
              }
            }
          }
          
          // شروع polling
          if (!isCompleted) {
            pollJobStatus();
          }
          
          return AlertDialog(
            title: Text(t.taxSendSelectedDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isCompleted) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(t.taxSendingInvoices),
                ] else ...[
                  Icon(
                    failedCount == 0 ? Icons.check_circle : Icons.warning,
                    color: failedCount == 0 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    failedCount == 0 
                        ? t.taxSendSelectedSuccess
                        : t.taxSendingWithError,
                  ),
                ],
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: isCompleted ? 1.0 : null,
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  isCompleted
                      ? t.taxSentCountFailedCount(sentCount, failedCount)
                      : t.taxProcessing,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              if (isCompleted)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t.close),
                )
              else
                TextButton(
                  onPressed: () {
                    // TODO: امکان cancel کردن job
                    Navigator.of(context).pop();
                  },
                  child: Text(t.cancel),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onRemoveSelectedFromWorkspace() async {
    final t = AppLocalizations.of(context);
    final dynamic state = _tableKey.currentState;
    if (state == null) return;
    List<Map<String, dynamic>> selectedItems = const [];
    try {
      // ignore: avoid_dynamic_calls
      selectedItems = state.getSelectedItems().cast<Map<String, dynamic>>();
    } catch (_) {
      selectedItems = const [];
    }
    if (selectedItems.isEmpty) return;

    // فیلتر کردن فاکتورهای ارسال شده
    final removableItems = selectedItems.where((item) {
      final status = item['tax_status']?.toString() ?? 'not_sent';
      return status != 'sent' && status != 'finalized';
    }).toList();

    if (removableItems.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: t.taxRemoveSelectedAllAlreadySent,
      );
      return;
    }

    if (removableItems.length < selectedItems.length) {
      final skippedCount = selectedItems.length - removableItems.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.taxRemoveSelectedDialogTitle),
          content: Text(t.taxRemoveSelectedSomeAlreadySent(skippedCount, removableItems.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.remove_circle_outline),
              label: Text(t.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.taxRemoveSelectedDialogTitle),
          content: Text(t.taxRemoveSelectedDialogMessage(removableItems.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.remove_circle_outline),
              label: Text(t.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final api = widget.apiClient;
      final ids = removableItems.map((e) => e['id']).toList();
      await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/tax-workspace/remove-batch',
        data: {'invoice_ids': ids},
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      SnackBarHelper.showSuccess(context, message: t.taxRemoveSelectedSuccess);
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxRemoveSelectedErrorWithMessage(ErrorExtractor.forContext(e, context)));
    }
  }

  Future<void> _onInquireSelectedStatus() async {
    final t = AppLocalizations.of(context);
    final dynamic state = _tableKey.currentState;
    if (state == null) return;
    List<Map<String, dynamic>> selectedItems = const [];
    try {
      selectedItems = state.getSelectedItems().cast<Map<String, dynamic>>();
    } catch (_) {
      selectedItems = const [];
    }
    if (selectedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxInquireSelectedDialogTitle),
        content: Text(t.taxInquireSelectedDialogMessage(selectedItems.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.sync),
            label: Text(t.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final api = widget.apiClient;
      final ids = selectedItems.map((e) => e['id']).toList();
      final response = await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/tax-workspace/inquire-status',
        data: {'invoice_ids': ids},
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      final data = response.data?['data'];
      final results = (data is Map<String, dynamic> ? data['results'] : null) as List<dynamic>? ?? const [];
      _showInquiryResultDialog(results);
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxInquireSelectedErrorWithMessage(ErrorExtractor.forContext(e, context)));
    }
  }

  bool _handleTaxSendError(Object error, {int? invoiceId}) {
    ApiErrorDetails? apiError;
    if (error is DioException && error.error is ApiErrorDetails) {
      apiError = error.error as ApiErrorDetails;
    } else if (error is ApiErrorDetails) {
      apiError = error;
    } else if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final err = data['error'];
        if (err is Map<String, dynamic>) {
          apiError = ApiErrorDetails(
            code: err['code']?.toString(),
            message: err['message']?.toString(),
            details: err['details'],
          );
        }
      }
    }
    if (apiError == null) {
      return false;
    }
    final code = (apiError.code ?? '').toUpperCase();
    if (code != 'TAX_VALIDATION_FAILED') {
      return false;
    }
    final issues = apiError.details?['issues'];
    final List<dynamic> issueList = issues is List ? issues : const [];
    // استفاده از invoice_id پاس داده شده یا استخراج از request
    int? finalInvoiceId = invoiceId;
    if (finalInvoiceId == null && error is DioException) {
      final requestPath = error.requestOptions.path;
      final match = RegExp(r'/invoices/business/\d+/(\d+)/tax-workspace/send-to-system').firstMatch(requestPath);
      if (match != null) {
        finalInvoiceId = int.tryParse(match.group(1)!);
      }
    }
    _showValidationIssuesDialog(issueList, invoiceId: finalInvoiceId);
    return true;
  }

  void _showBatchResultDialog(int successCount, List<dynamic> failedItems) {
    final t = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        // دسته‌بندی خطاها
        final Map<String, List<Map<String, dynamic>>> categorizedErrors = {};
        for (final item in failedItems) {
          final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
          final errorCode = map['error']?.toString() ?? 'UNKNOWN';
          final category = _categorizeError(errorCode, t);
          if (!categorizedErrors.containsKey(category)) {
            categorizedErrors[category] = [];
          }
          categorizedErrors[category]!.add(map);
        }
        
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                successCount > 0 ? Icons.warning_amber : Icons.error_outline,
                color: successCount > 0 
                    ? Colors.orange
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t.taxSendSelectedPartialTitle(successCount, failedItems.length)),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SizedBox(
              width: double.maxFinite,
              child: failedItems.isEmpty
                  ? Text(t.taxSendSelectedSuccess)
                  : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // خلاصه
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t.taxFailedInvoicesCount(failedItems.length),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // نمایش خطاها به صورت دسته‌بندی شده
                        ...categorizedErrors.entries.map((entry) {
                          final category = entry.key;
                          final items = entry.value;
                          return _buildErrorCategory(category, items, t);
                        }),
                      ],
                    ),
                  ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.close),
            ),
            if (failedItems.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // TODO: Retry failed items
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 18),
                    const SizedBox(width: 8),
                    Text(t.taxRetryFailed),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _categorizeError(String errorCode, AppLocalizations t) {
    final code = errorCode.toUpperCase();
    if (code.contains('VALIDATION') || code.contains('TAX_CODE') || code.contains('MISSING')) {
      return t.taxErrorCategoryValidation;
    } else if (code.contains('NETWORK') || code.contains('TIMEOUT') || code.contains('CONNECTION')) {
      return t.taxErrorCategoryNetwork;
    } else if (code.contains('AUTH') || code.contains('PERMISSION') || code.contains('ACCESS')) {
      return t.taxErrorCategoryAccess;
    } else if (code.contains('FINALIZED') || code.contains('ALREADY')) {
      return t.taxErrorCategoryStatus;
    } else {
      return t.taxErrorCategoryOther;
    }
  }

  Widget _buildErrorCategory(String category, List<Map<String, dynamic>> items, AppLocalizations t) {
    return ExpansionTile(
      leading: Icon(
        _getCategoryIcon(category, t),
        color: _getCategoryColor(category, t),
      ),
      title: Text(category),
      subtitle: Text(t.taxErrorItemsCount(items.length)),
      children: items.map((item) => _buildErrorItem(item, t)).toList(),
    );
  }

  IconData _getCategoryIcon(String category, AppLocalizations t) {
    if (category == t.taxErrorCategoryValidation) return Icons.verified_user;
    if (category == t.taxErrorCategoryNetwork) return Icons.wifi_off;
    if (category == t.taxErrorCategoryAccess) return Icons.lock;
    if (category == t.taxErrorCategoryStatus) return Icons.info;
    return Icons.error_outline;
  }

  Color _getCategoryColor(String category, AppLocalizations t) {
    if (category == t.taxErrorCategoryValidation) return Colors.orange;
    if (category == t.taxErrorCategoryNetwork) return Colors.blue;
    if (category == t.taxErrorCategoryAccess) return Colors.red;
    if (category == t.taxErrorCategoryStatus) return Colors.amber;
    return Colors.grey;
  }

  Widget _buildErrorItem(Map<String, dynamic> item, AppLocalizations t) {
    final invoiceId = item['id'];
    final errorCode = item['error']?.toString() ?? '-';
    final message = item['message']?.toString();
    final issues = item['issues'] as List<dynamic>?;
    
    return ExpansionTile(
      title: Text(t.taxInvoiceNumber(invoiceId)),
      subtitle: Text(message ?? errorCode),
      leading: const Icon(Icons.receipt_long, size: 20),
      children: [
        if (message != null && message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (issues != null && issues.isNotEmpty)
          ...issues.map((issue) {
            final issueMap = issue is Map<String, dynamic> ? issue : <String, dynamic>{};
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.arrow_right, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      issueMap['message']?.toString() ?? issueMap['code']?.toString() ?? '-',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  void _showValidationIssuesDialog(List<dynamic> issues, {int? invoiceId}) {
    final t = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        // دسته‌بندی خطاها بر اساس نوع
        final Map<String, List<Map<String, dynamic>>> categorizedIssues = {};
        for (final issue in issues) {
          final map = issue is Map<String, dynamic> ? issue : <String, dynamic>{};
          final code = map['code']?.toString() ?? 'OTHER';
          String category;
          if (code.contains('PERSON_')) {
            category = 'person';
          } else if (code.contains('PRODUCT_')) {
            category = 'product';
          } else {
            category = 'other';
          }
          if (!categorizedIssues.containsKey(category)) {
            categorizedIssues[category] = [];
          }
          categorizedIssues[category]!.add(map);
        }

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(child: Text(t.taxValidationIssuesTitle)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: issues.isEmpty
                ? Text(t.taxValidationIssuesEmpty)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.error.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t.taxValidationIssuesDescription,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // نمایش خطاهای مربوط به شخص
                        if (categorizedIssues.containsKey('person')) ...[
                          _buildIssueCategoryHeader(
                            context,
                            t.taxValidationIssuesCategoryPerson,
                            Icons.person_outline,
                            Colors.orange,
                          ),
                          const SizedBox(height: 8),
                          ...categorizedIssues['person']!.map((issue) => _buildIssueItem(context, issue, t, invoiceId: invoiceId)),
                          const SizedBox(height: 16),
                        ],
                        // نمایش خطاهای مربوط به کالا
                        if (categorizedIssues.containsKey('product')) ...[
                          _buildIssueCategoryHeader(
                            context,
                            t.taxValidationIssuesCategoryProduct,
                            Icons.inventory_2_outlined,
                            Colors.blue,
                          ),
                          const SizedBox(height: 8),
                          ...categorizedIssues['product']!.map((issue) => _buildIssueItem(context, issue, t, invoiceId: invoiceId)),
                          const SizedBox(height: 16),
                        ],
                        // نمایش سایر خطاها
                        if (categorizedIssues.containsKey('other')) ...[
                          _buildIssueCategoryHeader(
                            context,
                            t.taxValidationIssuesCategoryOther,
                            Icons.warning_outlined,
                            Colors.grey,
                          ),
                          const SizedBox(height: 8),
                          ...categorizedIssues['other']!.map((issue) => _buildIssueItem(context, issue, t, invoiceId: invoiceId)),
                        ],
                      ],
                    ),
                  ),
          ),
          actions: [
            if (invoiceId != null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.pushNamed(
                    'business_edit_invoice',
                    pathParameters: {
                      'business_id': widget.businessId.toString(),
                      'invoice_id': invoiceId.toString(),
                    },
                  );
                },
                icon: const Icon(Icons.edit, size: 18),
                label: Text(t.taxValidationIssuesEditInvoice),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.close),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIssueCategoryHeader(BuildContext context, String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildIssueItem(BuildContext context, Map<String, dynamic> issue, AppLocalizations t, {int? invoiceId}) {
    final message = issue['message']?.toString() ?? '-';
    final code = issue['code']?.toString();
    final meta = issue['meta'] as Map<String, dynamic>?;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (code != null && code.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${t.code}: $code',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (meta != null && meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (meta['person_id'] != null)
                  _buildMetaChip(
                    context,
                    t,
                    Icons.person,
                    '${t.person}: ${meta['person_name'] ?? meta['person_id']}',
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to persons page - user can search and edit from there
                      context.pushNamed(
                        'business_persons',
                        pathParameters: {
                          'business_id': widget.businessId.toString(),
                        },
                      );
                    },
                  ),
                if (meta['product_id'] != null)
                  _buildMetaChip(
                    context,
                    t,
                    Icons.inventory_2,
                    '${t.product}: ${meta['product_name'] ?? meta['product_id']}',
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to products page - user can search and edit from there
                      context.pushNamed(
                        'business_products',
                        pathParameters: {
                          'business_id': widget.businessId.toString(),
                        },
                      );
                    },
                  ),
                if (meta['line_number'] != null)
                  _buildMetaChip(
                    context,
                    t,
                    Icons.numbers,
                    '${t.taxValidationIssuesLineNumber}: ${meta['line_number']}',
                    onTap: invoiceId != null
                        ? () {
                            Navigator.pop(context);
                            context.pushNamed(
                              'business_edit_invoice',
                              pathParameters: {
                                'business_id': widget.businessId.toString(),
                                'invoice_id': invoiceId.toString(),
                              },
                            );
                          }
                        : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaChip(BuildContext context, AppLocalizations t, IconData icon, String label, {VoidCallback? onTap}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: chip,
      );
    }
    return chip;
  }

  void _showInquiryResultDialog(List<dynamic> results) {
    final t = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.taxInquiryResultTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: results.isEmpty
                ? Text(t.taxInquiryResultEmpty)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: results.map((item) {
                      final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                      final reference = map['reference_number']?.toString() ??
                          map['tracking_code']?.toString() ??
                          '-';
                      final status = map['status']?.toString();
                      final errorMessage = map['error_message']?.toString();
                      final inquiryAt = map['inquiry_at']?.toString();
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          _statusIcon(status),
                          color: _statusColor(status, Theme.of(context).colorScheme),
                        ),
                        title: Text(reference),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_statusLabel(status, t)),
                            if (errorMessage != null && errorMessage.isNotEmpty)
                              Text(
                                errorMessage,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Theme.of(context).colorScheme.error),
                              ),
                            if (inquiryAt != null)
                              Text(
                                inquiryAt,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.close),
            ),
          ],
        );
      },
    );
  }

  String _statusLabel(String? status, AppLocalizations t) {
    final normalized = status?.toLowerCase();
    switch (normalized) {
      case 'pending':
        return t.taxStatusPending;
      case 'sent':
        return t.taxStatusSent;
      case 'finalized':
      case 'accepted':
      case 'success':
        return t.taxStatusFinalized;
      case 'failed':
      case 'error':
        return t.taxStatusFailed;
      default:
        return t.taxInquiryStatusUnknown;
    }
  }

  IconData _statusIcon(String? status) {
    final normalized = status?.toLowerCase();
    switch (normalized) {
      case 'finalized':
      case 'accepted':
      case 'success':
        return Icons.check_circle_outline;
      case 'failed':
      case 'error':
        return Icons.error_outline;
      case 'pending':
        return Icons.hourglass_top;
      case 'sent':
        return Icons.send_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color _statusColor(String? status, ColorScheme colorScheme) {
    final normalized = status?.toLowerCase();
    switch (normalized) {
      case 'finalized':
      case 'accepted':
      case 'success':
        return colorScheme.primary;
      case 'failed':
      case 'error':
        return colorScheme.error;
      case 'pending':
        return colorScheme.secondary;
      case 'sent':
        return colorScheme.tertiary;
      default:
        return colorScheme.outline;
    }
  }
}
