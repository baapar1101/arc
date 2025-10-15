import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/receipt_payment_document.dart';
import 'package:hesabix_ui/services/receipt_payment_list_service.dart';
import 'package:hesabix_ui/services/receipt_payment_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/invoice_transactions_widget.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/models/invoice_type_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/models/business_dashboard_models.dart';

/// صفحه لیست اسناد دریافت و پرداخت با ویجت جدول
class ReceiptsPaymentsListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const ReceiptsPaymentsListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<ReceiptsPaymentsListPage> createState() => _ReceiptsPaymentsListPageState();
}

class _ReceiptsPaymentsListPageState extends State<ReceiptsPaymentsListPage> {
  late ReceiptPaymentListService _service;
  String? _selectedDocumentType;
  DateTime? _fromDate;
  DateTime? _toDate;
  int _refreshKey = 0; // کلید برای تازه‌سازی جدول

  @override
  void initState() {
    super.initState();
    _service = ReceiptPaymentListService(widget.apiClient);
  }

  /// تازه‌سازی داده‌های جدول
  void _refreshData() {
    setState(() {
      _refreshKey++; // تغییر کلید باعث rebuild شدن جدول می‌شود
    });
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
            // هدر صفحه
            _buildHeader(t),
            
            // فیلترها
            _buildFilters(t),
            
            // جدول داده‌ها
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<ReceiptPaymentDocument>(
                  key: ValueKey(_refreshKey),
                  config: _buildTableConfig(t),
                  fromJson: (json) => ReceiptPaymentDocument.fromJson(json),
                  calendarController: widget.calendarController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت هدر صفحه
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
                  t.receiptsAndPayments,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت اسناد دریافت و پرداخت',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _onAddNew,
            icon: const Icon(Icons.add),
            label: Text(t.add),
          ),
        ],
      ),
    );
  }

  /// ساخت بخش فیلترها
  Widget _buildFilters(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // فیلتر نوع سند
          Expanded(
            flex: 2,
            child: SegmentedButton<String?>(
              segments: [
                ButtonSegment<String?>(
                  value: null,
                  label: Text('همه'),
                  icon: const Icon(Icons.all_inclusive),
                ),
                ButtonSegment<String?>(
                  value: 'receipt',
                  label: Text(t.receipts),
                  icon: const Icon(Icons.download_done_outlined),
                ),
                ButtonSegment<String?>(
                  value: 'payment',
                  label: Text(t.payments),
                  icon: const Icon(Icons.upload_outlined),
                ),
              ],
              selected: {_selectedDocumentType},
              onSelectionChanged: (set) {
                setState(() {
                  _selectedDocumentType = set.first;
                });
                // refresh data when filter changes
                _refreshData();
              },
            ),
          ),
          
          const SizedBox(width: 16),
          
          // فیلتر تاریخ
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
        ],
      ),
    );
  }

  /// ساخت تنظیمات جدول
  DataTableConfig<ReceiptPaymentDocument> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<ReceiptPaymentDocument>(
      endpoint: '/businesses/${widget.businessId}/receipts-payments',
      title: t.receiptsAndPayments,
      excelEndpoint: '/businesses/${widget.businessId}/receipts-payments/export/excel',
      pdfEndpoint: '/businesses/${widget.businessId}/receipts-payments/export/pdf',
      getExportParams: () => {
        'business_id': widget.businessId,
        if (_selectedDocumentType != null) 'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': _fromDate!.toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toIso8601String(),
      },
      columns: [
        // کد سند
        TextColumn(
          'code',
          'کد سند',
          width: ColumnWidth.medium,
          formatter: (item) => item.code,
        ),
        
        // نوع سند
        TextColumn(
          'document_type',
          'نوع',
          width: ColumnWidth.small,
          formatter: (item) => item.documentTypeName,
        ),
        
        // تاریخ سند
        DateColumn(
          'document_date',
          'تاریخ سند',
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),
        
        // مبلغ کل
        NumberColumn(
          'total_amount',
          'مبلغ کل',
          width: ColumnWidth.large,
          formatter: (item) => formatWithThousands(item.totalAmount),
          suffix: ' ریال',
        ),
        
        // نام اشخاص
        TextColumn(
          'person_names',
          'اشخاص',
          width: ColumnWidth.medium,
          formatter: (item) => item.personNames ?? 'نامشخص',
        ),
        
        // تعداد حساب‌ها
        NumberColumn(
          'account_lines_count',
          'حساب‌ها',
          width: ColumnWidth.small,
          formatter: (item) => item.accountLinesCount.toString(),
        ),
        
        // ایجادکننده
        TextColumn(
          'created_by_name',
          'ایجادکننده',
          width: ColumnWidth.medium,
          formatter: (item) => item.createdByName ?? 'نامشخص',
        ),
        
        // تاریخ ثبت
        DateColumn(
          'registered_at',
          'تاریخ ثبت',
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.registeredAt, widget.calendarController.isJalali),
        ),
        
        // عملیات
        ActionColumn(
          'actions',
          'عملیات',
          width: ColumnWidth.medium,
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: (item) => _onView(item),
            ),
            DataTableAction(
              icon: Icons.edit,
              label: 'ویرایش',
              onTap: (item) => _onEdit(item),
            ),
            DataTableAction(
              icon: Icons.delete,
              label: 'حذف',
              onTap: (item) => _onDelete(item),
              isDestructive: true,
            ),
          ],
        ),
      ],
      searchFields: ['code', 'created_by_name'],
      filterFields: ['document_type'],
      dateRangeField: 'document_date',
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showColumnSearch: true,
      showRefreshButton: true,
      showClearFiltersButton: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      showExportButtons: true,
      showExcelExport: true,
      showPdfExport: true,
      defaultPageSize: 20,
      pageSizeOptions: [10, 20, 50, 100],
      additionalParams: {
        if (_selectedDocumentType != null) 'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': _fromDate!.toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toIso8601String(),
      },
      onRowTap: (item) => _onView(item),
      onRowDoubleTap: (item) => _onEdit(item),
      emptyStateMessage: 'هیچ سند دریافت یا پرداختی یافت نشد',
      loadingMessage: 'در حال بارگذاری اسناد...',
      errorMessage: 'خطا در بارگذاری اسناد',
    );
  }

  /// افزودن سند جدید
  void _onAddNew() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => BulkSettlementDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        isReceipt: true, // پیش‌فرض دریافت
        businessInfo: widget.authStore.currentBusiness,
        apiClient: widget.apiClient,
      ),
    );
    
    // اگر سند با موفقیت ثبت شد، جدول را تازه‌سازی کن
    if (result == true) {
      _refreshData();
    }
  }

  /// مشاهده جزئیات سند
  void _onView(ReceiptPaymentDocument document) {
    // TODO: باز کردن صفحه جزئیات سند
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('مشاهده سند ${document.code}'),
      ),
    );
  }

  /// ویرایش سند
  void _onEdit(ReceiptPaymentDocument document) {
    // TODO: باز کردن صفحه ویرایش سند
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ویرایش سند ${document.code}'),
      ),
    );
  }

  /// حذف سند
  void _onDelete(ReceiptPaymentDocument document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('آیا از حذف سند ${document.code} اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performDelete(document);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  /// انجام عملیات حذف
  Future<void> _performDelete(ReceiptPaymentDocument document) async {
    try {
      final success = await _service.delete(document.id);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('سند ${document.code} با موفقیت حذف شد'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('خطا در حذف سند');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در حذف سند: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class BulkSettlementDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final bool isReceipt;
  final BusinessWithPermission? businessInfo;
  final ApiClient apiClient;
  const BulkSettlementDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.isReceipt,
    this.businessInfo,
    required this.apiClient,
  });

  @override
  State<BulkSettlementDialog> createState() => _BulkSettlementDialogState();
}

class _BulkSettlementDialogState extends State<BulkSettlementDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isReceipt;
  int? _selectedCurrencyId;
  final List<_PersonLine> _personLines = <_PersonLine>[];
  final List<InvoiceTransaction> _centerTransactions = <InvoiceTransaction>[];

  @override
  void initState() {
    super.initState();
    _docDate = DateTime.now();
    _isReceipt = widget.isReceipt;
    // اگر ارز پیشفرض موجود است، آن را انتخاب کن، در غیر این صورت null بگذار تا CurrencyPickerWidget خودکار انتخاب کند
    _selectedCurrencyId = widget.businessInfo?.defaultCurrency?.id;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final sumPersons = _personLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCenters = _centerTransactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
    final diff = (_isReceipt ? sumCenters - sumPersons : sumPersons - sumCenters).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.receiptsAndPayments,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(value: true, label: Text(t.receipts)),
                        ButtonSegment<bool>(value: false, label: Text(t.payments)),
                      ],
                      selected: {_isReceipt},
                      onSelectionChanged: (s) => setState(() => _isReceipt = s.first),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: DateInputField(
                        value: _docDate,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                        labelText: 'تاریخ سند',
                        hintText: 'انتخاب تاریخ',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: CurrencyPickerWidget(
                        businessId: widget.businessId,
                        selectedCurrencyId: _selectedCurrencyId,
                        onChanged: (currencyId) => setState(() => _selectedCurrencyId = currencyId),
                        label: 'ارز',
                        hintText: 'انتخاب ارز',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _PersonsPanel(
                        businessId: widget.businessId,
                        lines: _personLines,
                        onChanged: (ls) => setState(() {
                          _personLines.clear();
                          _personLines.addAll(ls);
                        }),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: InvoiceTransactionsWidget(
                          transactions: _centerTransactions,
                          onChanged: (txs) => setState(() {
                            _centerTransactions.clear();
                            _centerTransactions.addAll(txs);
                          }),
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          invoiceType: InvoiceType.sales,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _TotalChip(label: t.people, value: sumPersons),
                          _TotalChip(label: t.accounts, value: sumCenters),
                          _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: diff == 0 && _personLines.isNotEmpty && _centerTransactions.isNotEmpty
                          ? _onSave
                          : null,
                      icon: const Icon(Icons.save),
                      label: Text(t.save),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (!mounted) return;
    
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final service = ReceiptPaymentService(widget.apiClient);
      
      // تبدیل personLines به فرمت مورد نیاز API
      final personLinesData = _personLines.map((line) => {
        'person_id': int.parse(line.personId!),
        'person_name': line.personName,
        'amount': line.amount,
        if (line.description != null && line.description!.isNotEmpty)
          'description': line.description,
      }).toList();
      
      // تبدیل centerTransactions به فرمت مورد نیاز API
      final accountLinesData = _centerTransactions.map((tx) => {
        'account_id': tx.accountId,
        'amount': tx.amount.toDouble(),
        'transaction_type': tx.type.value,
        'transaction_date': tx.transactionDate.toIso8601String(),
        if (tx.commission != null && tx.commission! > 0)
          'commission': tx.commission!.toDouble(),
        if (tx.description != null && tx.description!.isNotEmpty)
          'description': tx.description,
        // اطلاعات اضافی بر اساس نوع تراکنش
        if (tx.type == TransactionType.bank) ...{
          'bank_id': tx.bankId,
          'bank_name': tx.bankName,
        },
        if (tx.type == TransactionType.cashRegister) ...{
          'cash_register_id': tx.cashRegisterId,
          'cash_register_name': tx.cashRegisterName,
        },
        if (tx.type == TransactionType.pettyCash) ...{
          'petty_cash_id': tx.pettyCashId,
          'petty_cash_name': tx.pettyCashName,
        },
        if (tx.type == TransactionType.check) ...{
          'check_id': tx.checkId,
          'check_number': tx.checkNumber,
        },
        if (tx.type == TransactionType.person) ...{
          'person_id': tx.personId,
          'person_name': tx.personName,
        },
      }).toList();
      
      // ارسال به سرور
      await service.createReceiptPayment(
        businessId: widget.businessId,
        documentType: _isReceipt ? 'receipt' : 'payment',
        documentDate: _docDate,
        currencyId: _selectedCurrencyId!,
        personLines: personLinesData,
        accountLines: accountLinesData,
      );
      
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, true);
      
      // نمایش پیام موفقیت
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isReceipt 
              ? 'سند دریافت با موفقیت ثبت شد'
              : 'سند پرداخت با موفقیت ثبت شد',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // نمایش خطا
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _PersonsPanel extends StatefulWidget {
  final int businessId;
  final List<_PersonLine> lines;
  final ValueChanged<List<_PersonLine>> onChanged;
  const _PersonsPanel({
    required this.businessId,
    required this.lines,
    required this.onChanged,
  });

  @override
  State<_PersonsPanel> createState() => _PersonsPanelState();
}

class _PersonsPanelState extends State<_PersonsPanel> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.people, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                onPressed: () {
                  final newLines = List<_PersonLine>.from(widget.lines);
                  newLines.add(_PersonLine.empty());
                  widget.onChanged(newLines);
                },
                icon: const Icon(Icons.add),
                tooltip: t.add,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.lines.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.separated(
                    itemCount: widget.lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final line = widget.lines[i];
                      return _PersonLineTile(
                        businessId: widget.businessId,
                        line: line,
                        onChanged: (l) {
                          final newLines = List<_PersonLine>.from(widget.lines);
                          newLines[i] = l;
                          widget.onChanged(newLines);
                        },
                        onDelete: () {
                          final newLines = List<_PersonLine>.from(widget.lines);
                          newLines.removeAt(i);
                          widget.onChanged(newLines);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PersonLineTile extends StatefulWidget {
  final int businessId;
  final _PersonLine line;
  final ValueChanged<_PersonLine> onChanged;
  final VoidCallback onDelete;
  const _PersonLineTile({
    required this.businessId,
    required this.line,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_PersonLineTile> createState() => _PersonLineTileState();
}

class _PersonLineTileState extends State<_PersonLineTile> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.line.amount == 0 ? '' : widget.line.amount.toStringAsFixed(0);
    _descController.text = widget.line.description ?? '';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: PersonComboboxWidget(
                    businessId: widget.businessId,
                    selectedPerson: widget.line.personId != null 
                        ? Person(
                            id: int.tryParse(widget.line.personId!),
                            businessId: widget.businessId,
                            aliasName: widget.line.personName ?? '',
                            personTypes: const [],
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          )
                        : null,
                    onChanged: (opt) {
                      widget.onChanged(widget.line.copyWith(personId: opt?.id?.toString(), personName: opt?.displayName));
                    },
                    label: t.people,
                    hintText: t.search,
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: t.amount,
                      hintText: '1,000,000',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final val = double.tryParse((v ?? '').replaceAll(',', ''));
                      if (val == null || val <= 0) return t.mustBePositiveNumber;
                      return null;
                    },
                    onChanged: (v) {
                      final val = double.tryParse(v.replaceAll(',', '')) ?? 0;
                      widget.onChanged(widget.line.copyWith(amount: val));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: t.description,
              ),
              onChanged: (v) => widget.onChanged(widget.line.copyWith(description: v.trim().isEmpty ? null : v.trim())),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final bool isError;
  const _TotalChip({required this.label, required this.value, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label: ${formatWithThousands(value)}'),
      backgroundColor: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant),
    );
  }
}

class _PersonLine {
  final String? personId;
  final String? personName;
  final double amount;
  final String? description;

  const _PersonLine({this.personId, this.personName, required this.amount, this.description});

  factory _PersonLine.empty() => const _PersonLine(amount: 0);

  _PersonLine copyWith({String? personId, String? personName, double? amount, String? description}) {
    return _PersonLine(
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
    );
  }
}

