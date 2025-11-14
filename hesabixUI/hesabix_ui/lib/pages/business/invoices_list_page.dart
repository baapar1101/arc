import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/invoice_list_item.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';
import 'package:hesabix_ui/services/invoice_service.dart';

/// صفحه لیست فاکتورها با ویجت جدول عمومی
class InvoicesListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const InvoicesListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<InvoicesListPage> createState() => _InvoicesListPageState();
}

class _InvoicesListPageState extends State<InvoicesListPage> {
  final GlobalKey _tableKey = GlobalKey();
  final InvoiceService _invoiceService = InvoiceService();

  String? _selectedInvoiceType;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool? _isProforma; // null=همه، true=پیشفاکتور، false=قطعی

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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(t),
            _buildFilters(t),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<InvoiceListItem>(
                  key: _tableKey,
                  config: _buildTableConfig(t),
                  fromJson: (json) => InvoiceListItem.fromJson(json),
                  calendarController: widget.calendarController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.invoices, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(t.invoicesListManage, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          // دکمه افزودن فاکتور (در آینده به فرم ایجاد وصل میشود)
          FilledButton.icon(
            onPressed: _onAddNew,
            icon: const Icon(Icons.add),
            label: Text(t.add),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String?>(
                  segments: [
                    ButtonSegment<String?>(value: null, label: Text(t.all), icon: const Icon(Icons.all_inclusive)),
                    ButtonSegment<String?>(value: 'invoice_sales', label: Text(t.invoiceTypeSales), icon: const Icon(Icons.sell_outlined)),
                    ButtonSegment<String?>(value: 'invoice_purchase', label: Text(t.invoiceTypePurchase), icon: const Icon(Icons.shopping_cart_outlined)),
                    ButtonSegment<String?>(value: 'invoice_sales_return', label: Text(t.invoiceTypeSalesReturn), icon: const Icon(Icons.undo_outlined)),
                    ButtonSegment<String?>(value: 'invoice_purchase_return', label: Text(t.invoiceTypePurchaseReturn), icon: const Icon(Icons.undo)),
                    ButtonSegment<String?>(value: 'invoice_production', label: Text(t.invoiceTypeProduction), icon: const Icon(Icons.factory_outlined)),
                    ButtonSegment<String?>(value: 'invoice_direct_consumption', label: Text(t.invoiceTypeDirectConsumption), icon: const Icon(Icons.dining_outlined)),
                    ButtonSegment<String?>(value: 'invoice_waste', label: Text(t.invoiceTypeWaste), icon: const Icon(Icons.delete_outline)),
                  ],
                  selected: _selectedInvoiceType != null ? {_selectedInvoiceType} : <String?>{},
                  onSelectionChanged: (set) {
                    setState(() => _selectedInvoiceType = set.first);
                    _refreshData();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                child: SegmentedButton<bool?>(
                  segments: [
                    ButtonSegment<bool?>(value: null, label: Text(t.all)),
                    ButtonSegment<bool?>(value: true, label: Text(t.proforma)),
                    ButtonSegment<bool?>(value: false, label: Text(t.finalized)),
                  ],
                  selected: {_isProforma},
                  onSelectionChanged: (set) {
                    setState(() => _isProforma = set.first);
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

  DataTableConfig<InvoiceListItem> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<InvoiceListItem>(
      endpoint: '/invoices/business/${widget.businessId}/search',
      title: t.invoices,
      excelEndpoint: '/invoices/business/${widget.businessId}/export/excel',
      pdfEndpoint: '/invoices/business/${widget.businessId}/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'invoices',
      reportSubtype: 'list',
      columns: [
        // عملیات
        ActionColumn(
          'actions',
          t.actions,
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: t.view,
              onTap: (item) => _onView(item as InvoiceListItem),
            ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.edit,
                label: t.edit,
                onTap: (item) => _onEdit(item as InvoiceListItem),
              ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.delete,
                label: t.delete,
                onTap: (item) => _onDelete(item as InvoiceListItem),
                isDestructive: true,
              ),
          ],
        ),
        // کد سند
        TextColumn('code', t.code, formatter: (item) => item.code, width: ColumnWidth.small),
        // نوع
        TextColumn('document_type', t.type, formatter: (item) => item.documentTypeName, width: ColumnWidth.medium),
        // تاریخ سند
        DateColumn(
          'document_date',
          t.documentDate,
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),
        // مبلغ کل
        NumberColumn(
          'total_amount',
          t.totalAmount,
          width: ColumnWidth.large,
          formatter: (item) => item.totalAmount != null ? formatWithThousands(item.totalAmount!) : '-',
          suffix: ' ریال',
        ),
        // ارز
        TextColumn('currency_code', t.currency, formatter: (item) => item.currencyCode ?? t.unknown, width: ColumnWidth.small),
        // ایجادکننده
        TextColumn('created_by_name', t.createdBy, formatter: (item) => item.createdByName ?? t.unknown, width: ColumnWidth.medium),
        // وضعیت
        TextColumn('is_proforma', t.status, formatter: (item) => item.isProforma ? t.proforma : t.finalized, width: ColumnWidth.small),
      ],
      searchFields: const ['code', 'description'],
      filterFields: const ['document_type'],
      dateRangeField: 'document_date',
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showColumnSearch: true,
      showRefreshButton: true,
      showClearFiltersButton: true,
      enableRowSelection: false,
      enableMultiRowSelection: false,
      defaultPageSize: 20,
      pageSizeOptions: const [10, 20, 50, 100],
      additionalParams: {
        'document_type': _selectedInvoiceType,
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
        if (_isProforma != null) 'is_proforma': _isProforma,
      },
      onRowTap: (item) => _onView(item as InvoiceListItem),
      emptyStateMessage: t.noInvoicesFound,
      loadingMessage: t.loadingInvoices,
      errorMessage: t.errorLoadingInvoices,
    );
  }

  Future<void> _onAddNew() async {
    if (!mounted) return;
    await context.pushNamed(
      'business_new_invoice',
      pathParameters: {
        'business_id': widget.businessId.toString(),
      },
    );
    if (!mounted) return;
    _refreshData();
  }

  Future<void> _onView(InvoiceListItem item) async {
    await showDialog(
      context: context,
      builder: (_) => DocumentDetailsDialog(
        documentId: item.id,
        calendarController: widget.calendarController,
      ),
    );
  }

  Future<void> _onEdit(InvoiceListItem item) async {
    if (!mounted) return;
    await context.pushNamed(
      'business_edit_invoice',
      pathParameters: {
        'business_id': widget.businessId.toString(),
        'invoice_id': item.id.toString(),
      },
    );
    if (!mounted) return;
    _refreshData();
  }

  Future<void> _onDelete(InvoiceListItem item) async {
    final t = AppLocalizations.of(context);
    // نمایش dialog تأیید
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(t.deleteConfirmTitle),
        content: Text(t.deleteInvoiceConfirm(item.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // نمایش لودینگ
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await _invoiceService.deleteInvoice(
        businessId: widget.businessId,
        invoiceId: item.id,
      );

      // همیشه ابتدا لودینگ را ببندیم (حتی اگر mounted=false شده باشد)
      // از navigator از پیش گرفته‌شده استفاده می‌کنیم تا pop روی route درست انجام شود
      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.deletedInvoiceSuccess(item.code)),
            backgroundColor: Colors.green,
          ),
        );
        _refreshData();
      } else {
        throw Exception(t.deleteInvoiceError);
      }
    } catch (e) {
      // اطمینان از بسته شدن لودینگ در صورت بروز خطا
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.deleteInvoiceErrorWithMessage(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}


