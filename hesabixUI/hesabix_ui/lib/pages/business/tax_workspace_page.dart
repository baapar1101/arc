import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import '../../utils/snackbar_helper.dart';
import '../../services/errors/api_error.dart';
import '../../utils/responsive_helper.dart';

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
        ],
      ),
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
            ),
            DataTableAction(
              icon: Icons.remove_circle_outline,
              label: t.taxRemoveFromWorkspaceSingle,
              onTap: (item) => _onRemoveSingleFromWorkspace(item as Map<String, dynamic>),
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
        NumberColumn(
          'total_amount',
          t.totalAmount,
          width: ColumnWidth.large,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            final v = map['total_amount'];
            if (v == null) return '-';
            return v.toString();
          },
          suffix: ' ریال',
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
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
        'tax_status': _selectedTaxStatus,
      },
      emptyStateMessage: t.taxWorkspaceEmpty,
      loadingMessage: t.taxWorkspaceLoading,
      errorMessage: t.taxWorkspaceError,
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.taxSendSuccess),
          backgroundColor: Colors.green,
        ),
      );
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      if (!_handleTaxSendError(e)) {
      SnackBarHelper.showError(context, message: t.taxSendErrorWithMessage(e.toString()));
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.taxRemoveFromWorkspaceSuccess),
          backgroundColor: Colors.green,
        ),
      );
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxRemoveFromWorkspaceErrorWithMessage(e.toString()));
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxSendSelectedDialogTitle),
        content: Text(t.taxSendSelectedDialogMessage(selectedItems.length)),
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
      final ids = selectedItems.map((e) => e['id']).toList();
      final response = await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/tax-workspace/send-to-system-batch',
        data: {'invoice_ids': ids},
      );
      final body = response.data;
      final result = (body?['data'] as Map<String, dynamic>?) ?? const {};
      final failed = (result['failed'] as List<dynamic>?) ?? const [];
      final succeeded = (result['succeeded'] as List<dynamic>?) ?? const [];

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      if (failed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.taxSendSelectedSuccess),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _showBatchResultDialog(succeeded.length, failed);
      }
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      if (!_handleTaxSendError(e)) {
      SnackBarHelper.showError(context, message: t.taxSendSelectedErrorWithMessage(e.toString()));
      }
    }
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxRemoveSelectedDialogTitle),
        content: Text(t.taxRemoveSelectedDialogMessage(selectedItems.length)),
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
      final ids = selectedItems.map((e) => e['id']).toList();
      await api.post<Map<String, dynamic>>(
        '/invoices/business/${widget.businessId}/tax-workspace/remove-batch',
        data: {'invoice_ids': ids},
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.taxRemoveSelectedSuccess),
          backgroundColor: Colors.green,
        ),
      );
      _refreshData();
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxRemoveSelectedErrorWithMessage(e.toString()));
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
      SnackBarHelper.showError(context, message: t.taxInquireSelectedErrorWithMessage(e.toString()));
    }
  }

  bool _handleTaxSendError(Object error) {
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
    _showValidationIssuesDialog(issueList);
    return true;
  }

  void _showBatchResultDialog(int successCount, List<dynamic> failedItems) {
    final t = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.taxSendSelectedPartialTitle(successCount, failedItems.length)),
          content: SizedBox(
            width: double.maxFinite,
            child: failedItems.isEmpty
                ? Text(t.taxSendSelectedSuccess)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: failedItems.map((item) {
                      final map = item is Map<String, dynamic> ? item : <String, dynamic>{};
                      final invoiceId = map['id'];
                      final errorCode = map['error']?.toString() ?? '-';
                      final message = map['message']?.toString();
                      final issues = map['issues'];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.error_outline, color: Colors.redAccent),
                        title: Text(t.taxBatchFailedRow(invoiceId?.toString() ?? '-')),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message == null || message.isEmpty
                                  ? errorCode
                                  : '$errorCode — $message',
                            ),
                            if (issues is List && issues.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              ...issues.map((issue) {
                                final issueMap = issue is Map<String, dynamic>
                                    ? issue
                                    : <String, dynamic>{};
                                final msg = issueMap['message']?.toString() ?? '-';
                                final code = issueMap['code']?.toString();
                                return Text(
                                  code == null || code.isEmpty ? '• $msg' : '• [$code] $msg',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                                );
                              }),
                            ],
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

  void _showValidationIssuesDialog(List<dynamic> issues) {
    final t = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxValidationIssuesTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: issues.isEmpty
              ? Text(t.taxValidationIssuesEmpty)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.taxValidationIssuesDescription,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ...issues.map(
                      (issue) {
                        final map = issue is Map<String, dynamic> ? issue : <String, dynamic>{};
                        final message = map['message']?.toString() ?? '-';
                        final code = map['code']?.toString();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.error_outline, color: Colors.redAccent),
                          title: Text(message),
                          subtitle: code != null && code.isNotEmpty
                              ? Text('${t.code}: $code')
                              : null,
                        );
                      },
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
        ],
      ),
    );
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
