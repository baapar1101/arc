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
                Text(
                  'فاکتورها',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت لیست فاکتورها',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
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
                  segments: const [
                    ButtonSegment<String?>(value: null, label: Text('همه'), icon: Icon(Icons.all_inclusive)),
                    ButtonSegment<String?>(value: 'invoice_sales', label: Text('فروش'), icon: Icon(Icons.sell_outlined)),
                    ButtonSegment<String?>(value: 'invoice_purchase', label: Text('خرید'), icon: Icon(Icons.shopping_cart_outlined)),
                    ButtonSegment<String?>(value: 'invoice_sales_return', label: Text('برگشت فروش'), icon: Icon(Icons.undo_outlined)),
                    ButtonSegment<String?>(value: 'invoice_purchase_return', label: Text('برگشت خرید'), icon: Icon(Icons.undo)),
                    ButtonSegment<String?>(value: 'invoice_production', label: Text('تولید'), icon: Icon(Icons.factory_outlined)),
                    ButtonSegment<String?>(value: 'invoice_direct_consumption', label: Text('مصرف مستقیم'), icon: Icon(Icons.dining_outlined)),
                    ButtonSegment<String?>(value: 'invoice_waste', label: Text('ضایعات'), icon: Icon(Icons.delete_outline)),
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
                        labelText: 'از تاریخ',
                        hintText: 'انتخاب تاریخ شروع',
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
                        labelText: 'تا تاریخ',
                        hintText: 'انتخاب تاریخ پایان',
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
                      tooltip: 'پاک کردن فیلتر تاریخ',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SegmentedButton<bool?>(
                  segments: const [
                    ButtonSegment<bool?>(value: null, label: Text('همه')),
                    ButtonSegment<bool?>(value: true, label: Text('پیشفاکتور')),
                    ButtonSegment<bool?>(value: false, label: Text('قطعی')),
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
      title: 'فاکتورها',
      excelEndpoint: '/invoices/business/${widget.businessId}/export/excel',
      pdfEndpoint: '/invoices/business/${widget.businessId}/export/pdf',
      columns: [
        // عملیات
        ActionColumn(
          'actions',
          'عملیات',
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: (item) => _onView(item as InvoiceListItem),
            ),
          ],
        ),
        // کد سند
        TextColumn('code', 'کد', formatter: (item) => item.code, width: ColumnWidth.small),
        // نوع
        TextColumn('document_type', 'نوع', formatter: (item) => item.documentTypeName, width: ColumnWidth.medium),
        // تاریخ سند
        DateColumn(
          'document_date',
          'تاریخ',
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),
        // مبلغ کل
        NumberColumn(
          'total_amount',
          'مبلغ کل',
          width: ColumnWidth.large,
          formatter: (item) => item.totalAmount != null ? formatWithThousands(item.totalAmount!) : '-',
          suffix: ' ریال',
        ),
        // ارز
        TextColumn('currency_code', 'ارز', formatter: (item) => item.currencyCode ?? 'نامشخص', width: ColumnWidth.small),
        // ایجادکننده
        TextColumn('created_by_name', 'ایجادکننده', formatter: (item) => item.createdByName ?? 'نامشخص', width: ColumnWidth.medium),
        // وضعیت
        TextColumn('is_proforma', 'وضعیت', formatter: (item) => item.isProforma ? 'پیشفاکتور' : 'قطعی', width: ColumnWidth.small),
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
      emptyStateMessage: 'هیچ فاکتوری یافت نشد',
      loadingMessage: 'در حال بارگذاری فاکتورها...',
      errorMessage: 'خطا در بارگذاری فاکتورها',
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
}


