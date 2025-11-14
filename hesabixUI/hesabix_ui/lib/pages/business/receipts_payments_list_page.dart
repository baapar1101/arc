import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/receipt_payment_document.dart';
import 'package:hesabix_ui/services/receipt_payment_list_service.dart';
import 'package:hesabix_ui/services/invoice_service.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/receipt_payment_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
// removed duplicate import
import 'package:hesabix_ui/widgets/invoice/invoice_transactions_widget.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/models/invoice_type_model.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
// removed duplicate import
import 'package:hesabix_ui/models/business_dashboard_models.dart';
import 'dart:html' as html;

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
  // کلید کنترل جدول برای دسترسی به selection و refresh
  final GlobalKey _tableKey = GlobalKey();
  int _selectedCount = 0; // تعداد سطرهای انتخاب‌شده

  @override
  void initState() {
    super.initState();
    _service = ReceiptPaymentListService(widget.apiClient);
  }

  /// تازه‌سازی داده‌های جدول
  void _refreshData() {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // استفاده از متد عمومی refresh در ویجت جدول
        // نوت: دسترسی دینامیک چون State کلاس خصوصی است
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
            // هدر صفحه
            _buildHeader(t),
            
            // فیلترها
            _buildFilters(t),
            
            // جدول داده‌ها
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<ReceiptPaymentDocument>(
                  key: _tableKey,
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
              selected: _selectedDocumentType != null ? {_selectedDocumentType} : <String?>{},
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
      businessId: widget.businessId,
      reportModuleKey: 'receipts_payments',
      reportSubtype: 'list',
      // دکمه حذف گروهی در هدر جدول
      customHeaderActions: [
        Tooltip(
          message: 'حذف انتخاب‌شده‌ها',
          child: FilledButton.icon(
            onPressed: _selectedCount > 0 ? _onBulkDelete : null,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.delete_forever),
            label: Text('حذف (${_selectedCount})'),
          ),
        ),
      ],
      getExportParams: () => {
        'business_id': widget.businessId,
        // همیشه document_type را ارسال کن، حتی اگر null باشد
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
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
        
        // توضیحات
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (item) => item.description ?? '',
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
      onRowSelectionChanged: (rows) {
        setState(() {
          _selectedCount = rows.length;
        });
      },
      additionalParams: {
        // همیشه document_type را ارسال کن، حتی اگر null باشد
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
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
  void _onView(ReceiptPaymentDocument document) async {
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سند یافت نشد')),
        );
        return;
      }

      // نمایش دیالوگ مشاهده جزئیات
      await showDialog(
        context: context,
        builder: (_) => ReceiptPaymentViewDialog(
          document: fullDoc,
          calendarController: widget.calendarController,
          businessId: widget.businessId,
          apiClient: widget.apiClient,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در بارگذاری جزئیات: $e')),
      );
    }
  }

  /// ویرایش سند
  void _onEdit(ReceiptPaymentDocument document) async {
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سند یافت نشد')),
        );
        return;
      }

      final result = await showDialog<bool>(
        context: context,
        builder: (_) => BulkSettlementDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          isReceipt: fullDoc.isReceipt,
          businessInfo: widget.authStore.currentBusiness,
          apiClient: widget.apiClient,
          initialDocument: fullDoc,
        ),
      );

      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در آماده‌سازی ویرایش: $e')),
      );
    }
  }

  /// حذف سند
  void _onDelete(ReceiptPaymentDocument document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('حذف سند ${document.code} غیرقابل بازگشت است. آیا ادامه می‌دهید؟'),
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
      // نمایش لودینگ هنگام حذف
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final success = await _service.delete(document.id);
      if (success) {
        if (mounted) {
          Navigator.pop(context); // بستن لودینگ
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('سند ${document.code} با موفقیت حذف شد'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _selectedCount = 0; // پاک‌سازی شمارنده انتخاب پس از حذف
          });
          _refreshData();
        }
      } else {
        if (mounted) Navigator.pop(context);
        throw Exception('خطا در حذف سند');
      }
    } catch (e) {
      if (mounted) {
        // بستن لودینگ در صورت بروز خطا
        Navigator.pop(context);

        String message = 'خطا در حذف سند';
        int? statusCode;
        if (e is DioException) {
          statusCode = e.response?.statusCode;
          final data = e.response?.data;
          try {
            final detail = (data is Map<String, dynamic>) ? data['detail'] : null;
            if (detail is Map<String, dynamic>) {
              final err = detail['error'];
              if (err is Map<String, dynamic>) {
                final m = err['message'];
                if (m is String && m.trim().isNotEmpty) {
                  message = m;
                }
              }
            }
          } catch (_) {
            // ignore parse errors
          }

          if (statusCode == 404) {
            message = 'سند یافت نشد یا قبلاً حذف شده است';
            _refreshData();
          } else if (statusCode == 403) {
            message = 'دسترسی لازم برای حذف این سند را ندارید';
          } else if (statusCode == 409) {
            // پیام از سرور استخراج شده است (مثلاً سند قفل/دارای وابستگی)
            if (message == 'خطا در حذف سند') {
              message = 'حذف این سند امکان‌پذیر نیست';
            }
          }
        } else {
          message = e.toString();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// حذف گروهی اسناد انتخاب‌شده
  Future<void> _onBulkDelete() async {
    // استخراج آیتم‌های انتخاب‌شده از جدول
    final state = _tableKey.currentState;
    if (state == null) return;

    List<dynamic> selectedItems = const [];
    try {
      // ignore: avoid_dynamic_calls
      selectedItems = (state as dynamic).getSelectedItems();
    } catch (_) {}

    if (selectedItems.isEmpty) return;

    // نگاشت به مدل و شناسه‌ها
    final docs = selectedItems.cast<ReceiptPaymentDocument>();
    final ids = docs.map((d) => d.id).toList();
    final codes = docs.map((d) => d.code).toList();

    // تایید کاربر
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تأیید حذف گروهی'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تعداد اسناد انتخاب‌شده: ${ids.length}'),
              const SizedBox(height: 8),
              Text('این عملیات غیرقابل بازگشت است. ادامه می‌دهید؟'),
              if (codes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('نمونه کدها: ${codes.take(5).join(', ')}${codes.length > 5 ? ' ...' : ''}'),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // نمایش لودینگ
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _service.deleteMultiple(ids);
      if (!mounted) return;
      Navigator.pop(context); // بستن لودینگ
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ids.length} سند با موفقیت حذف شد'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _selectedCount = 0; // پاک‌سازی شمارنده انتخاب پس از حذف گروهی
      });
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // بستن لودینگ
      String message = 'خطا در حذف اسناد';
      if (e is DioException) {
        message = e.message ?? message;
      } else {
        message = e.toString();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class BulkSettlementDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final bool isReceipt;
  final BusinessWithPermission? businessInfo;
  final ApiClient apiClient;
  final ReceiptPaymentDocument? initialDocument;
  const BulkSettlementDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.isReceipt,
    this.businessInfo,
    required this.apiClient,
    this.initialDocument,
  });

  @override
  State<BulkSettlementDialog> createState() => _BulkSettlementDialogState();
}

class _BulkSettlementDialogState extends State<BulkSettlementDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isReceipt;
  int? _selectedCurrencyId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_PersonLine> _personLines = <_PersonLine>[];
  final List<InvoiceTransaction> _centerTransactions = <InvoiceTransaction>[];
  // اقساط
  int? _installmentInvoiceId;
  List<Map<String, dynamic>> _installmentSchedule = <Map<String, dynamic>>[];
  final Map<int, double> _allocationsBySeq = <int, double>{};
  Person? _installmentPerson;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDocument;
    if (initial != null) {
      // حالت ویرایش: پرکردن اولیه از سند
      _isReceipt = initial.isReceipt;
      _docDate = initial.documentDate;
      _selectedCurrencyId = initial.currencyId;
      _descriptionController.text = initial.description ?? '';
      // تبدیل خطوط اشخاص
      _personLines.clear();
      for (final pl in initial.personLines) {
        _personLines.add(
          _PersonLine(
            personId: pl.personId?.toString(),
            personName: pl.personName,
            amount: pl.amount,
            description: pl.description,
          ),
        );
      }
      // تبدیل خطوط حساب‌ها (حذف خطوط کارمزد)
      _centerTransactions.clear();
      for (final al in initial.accountLines) {
        final isCommission = (al.extraInfo != null && (al.extraInfo!['is_commission_line'] == true));
        if (isCommission) continue;
        final t = TransactionType.fromValue(al.transactionType ?? '') ?? TransactionType.person;
        _centerTransactions.add(
          InvoiceTransaction(
            id: al.id.toString(),
            type: t,
            bankId: al.extraInfo?['bank_id']?.toString(),
            bankName: al.extraInfo?['bank_name']?.toString(),
            cashRegisterId: al.extraInfo?['cash_register_id']?.toString(),
            cashRegisterName: al.extraInfo?['cash_register_name']?.toString(),
            pettyCashId: al.extraInfo?['petty_cash_id']?.toString(),
            pettyCashName: al.extraInfo?['petty_cash_name']?.toString(),
            checkId: al.extraInfo?['check_id']?.toString(),
            checkNumber: al.extraInfo?['check_number']?.toString(),
            personId: al.extraInfo?['person_id']?.toString(),
            personName: al.extraInfo?['person_name']?.toString(),
            accountId: al.accountId.toString(),
            accountName: al.accountName,
            transactionDate: al.transactionDate ?? _docDate,
            amount: al.amount,
            commission: al.commission,
            description: al.description,
          ),
        );
      }
    } else {
      // حالت ایجاد
      _docDate = DateTime.now();
      _isReceipt = widget.isReceipt;
      _selectedCurrencyId = widget.businessInfo?.defaultCurrency?.id;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
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
                    if (widget.initialDocument == null)
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات کلی سند',
                    hintText: 'توضیحات اختیاری...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
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
              // تخصیص به اقساط (اختیاری)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Text('تخصیص به اقساط (اختیاری)'),
                            const Spacer(),
                            SizedBox(
                              width: 260,
                              child: PersonComboboxWidget(
                                businessId: widget.businessId,
                                selectedPerson: _installmentPerson,
                                label: 'مشتری',
                                hintText: 'انتخاب مشتری',
                                onChanged: (p) => setState(() {
                                  _installmentPerson = p;
                                  // پاک‌سازی انتخاب فاکتور
                                  _installmentInvoiceId = null;
                                  _installmentSchedule = [];
                                  _allocationsBySeq.clear();
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _pickInvoiceForInstallments,
                              child: Text(_installmentInvoiceId == null ? 'انتخاب فاکتور' : 'تغییر فاکتور'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_installmentSchedule.isNotEmpty)
                          Column(
                            children: [
                              Row(
                                children: const [
                                  Expanded(child: Text('قسط')),
                                  Expanded(child: Text('سررسید')),
                                  Expanded(child: Text('باقیمانده')),
                                  SizedBox(width: 120, child: Text('مبلغ تخصیص', textAlign: TextAlign.end)),
                                ],
                              ),
                              const Divider(),
                              ..._installmentSchedule.map((it) {
                                final seq = (it['seq'] as num?)?.toInt() ?? 0;
                                final due = (it['due_date'] as String?) ?? '-';
                                final remaining = (it['remaining'] as num?)?.toDouble() ??
                                    (((it['total'] as num?)?.toDouble() ?? 0) - ((it['paid_amount'] as num?)?.toDouble() ?? 0));
                                final current = _allocationsBySeq[seq] ?? 0.0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text('#$seq')),
                                      Expanded(child: Text(due)),
                                      Expanded(child: Text(remaining.toStringAsFixed(0))),
                                      SizedBox(
                                        width: 120,
                                        child: TextFormField(
                                          textAlign: TextAlign.end,
                                          initialValue: current > 0 ? current.toStringAsFixed(0) : '',
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          onChanged: (v) {
                                            final val = double.tryParse(v.replaceAll(',', '')) ?? 0;
                                            setState(() {
                                              if (val <= 0) {
                                                _allocationsBySeq.remove(seq);
                                              } else {
                                                _allocationsBySeq[seq] = val;
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                      ],
                    ),
                  ),
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
      
      // ساخت extra_info (تخصیص اقساط در صورت وجود)
      Map<String, dynamic>? extraInfo;
      if (_installmentInvoiceId != null && _allocationsBySeq.isNotEmpty) {
        final allocations = _allocationsBySeq.entries
            .where((e) => (e.value) > 0)
            .map((e) => {'seq': e.key, 'amount': e.value})
            .toList();
        if (allocations.isNotEmpty) {
          extraInfo = {
            'settlements': [
              {
                'invoice_id': _installmentInvoiceId,
                'allocations': allocations,
              }
            ],
          };
        }
      }
      // اگر initialDocument وجود دارد، حالت ویرایش
      if (widget.initialDocument != null) {
        await service.updateReceiptPayment(
          documentId: widget.initialDocument!.id,
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          personLines: personLinesData,
          accountLines: accountLinesData,
          extraInfo: extraInfo,
        );
      } else {
        // ایجاد سند جدید
        await service.createReceiptPayment(
          businessId: widget.businessId,
          documentType: _isReceipt ? 'receipt' : 'payment',
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          personLines: personLinesData,
          accountLines: accountLinesData,
          extraInfo: extraInfo,
        );
      }
      
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, true);
      
      // نمایش پیام موفقیت
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialDocument != null
              ? 'سند با موفقیت ویرایش شد'
              : (_isReceipt ? 'سند دریافت با موفقیت ثبت شد' : 'سند پرداخت با موفقیت ثبت شد'),
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

  Future<void> _loadInstallmentPlan() async {
    if (_installmentInvoiceId == null) return;
    try {
      final svc = InvoiceService(apiClient: widget.apiClient);
      final data = await svc.getInstallmentPlan(
        businessId: widget.businessId,
        invoiceId: _installmentInvoiceId!,
      );
      // بررسی هم‌ارزی ارز سند دریافت با ارز فاکتور اقساطی
      final planCurrencyId = (data['currency_id'] as num?)?.toInt();
      if (_selectedCurrencyId != null && planCurrencyId != null && _selectedCurrencyId != planCurrencyId) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ارز فاکتور اقساط با ارز سند دریافت متفاوت است. لطفاً ارزی همسان انتخاب کنید.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _installmentSchedule = const <Map<String, dynamic>>[];
          _allocationsBySeq.clear();
        });
        return;
      }
      final plan = (data['plan'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final schedule = (plan['schedule'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      setState(() {
        _installmentSchedule = schedule;
        _allocationsBySeq.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا در دریافت اقساط: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickInvoiceForInstallments() async {
    final svc = InvoiceService(apiClient: widget.apiClient);
    final TextEditingController searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    bool loading = false;
    await showDialog(
      context: context,
      builder: (ctx) {
        Future<void> doSearch() async {
          loading = true;
          (ctx as Element).markNeedsBuild();
          try {
            final bodyFilters = <String, dynamic>{};
            if (_installmentPerson != null) {
              bodyFilters['person_id'] = _installmentPerson!.id;
            }
            if (_selectedCurrencyId != null) {
              bodyFilters['currency_id'] = _selectedCurrencyId;
            }
            final data = await svc.searchInvoices(
              businessId: widget.businessId,
              page: 1,
              limit: 20,
              search: searchCtrl.text.trim().isEmpty ? null : searchCtrl.text.trim(),
              filters: bodyFilters.isEmpty ? null : bodyFilters,
            );
            final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
            results = items;
          } catch (e) {
            results = <Map<String, dynamic>>[];
          } finally {
            loading = false;
            (ctx).markNeedsBuild();
          }
        }

        return AlertDialog(
          title: const Text('انتخاب فاکتور'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'جستجو (کد/شرح/...)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => doSearch(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: doSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('جستجو'),
                    ),
                    const SizedBox(width: 8),
                    if (_installmentPerson != null)
                      Chip(label: Text('مشتری: ${_installmentPerson!.displayName}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading) const LinearProgressIndicator(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (c, i) {
                      final it = results[i];
                      return ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: Text(it['code']?.toString() ?? '-'),
                        subtitle: Text(it['description']?.toString() ?? ''),
                        onTap: () {
                          Navigator.pop(ctx, it);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
          ],
        );
      },
    ).then((picked) async {
      if (picked is Map<String, dynamic>) {
        final id = picked['id'] as int?;
        if (id != null) {
          setState(() {
            _installmentInvoiceId = id;
          });
          await _loadInstallmentPlan();
        }
      }
    });
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
                    inputFormatters: [
                      EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
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

/// دیالوگ مشاهده جزئیات سند دریافت/پرداخت
class ReceiptPaymentViewDialog extends StatefulWidget {
  final ReceiptPaymentDocument document;
  final CalendarController calendarController;
  final int businessId;
  final ApiClient apiClient;

  const ReceiptPaymentViewDialog({
    super.key,
    required this.document,
    required this.calendarController,
    required this.businessId,
    required this.apiClient,
  });

  @override
  State<ReceiptPaymentViewDialog> createState() => _ReceiptPaymentViewDialogState();
}

class _ReceiptPaymentViewDialogState extends State<ReceiptPaymentViewDialog> {
  bool _isGeneratingPdf = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final doc = widget.document;
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر دیالوگ
            _buildHeader(t, doc),
            
            // محتوای اصلی
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اطلاعات کلی سند
                    _buildDocumentInfo(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط اشخاص
                    _buildPersonLines(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط حساب‌ها
                    _buildAccountLines(t, doc),
                  ],
                ),
              ),
            ),
            
            // دکمه‌های پایین
            _buildFooter(t),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'جزئیات سند ${doc.documentTypeName}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'کد سند: ${doc.code}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'بستن',
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentInfo(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات کلی سند',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildInfoRow('نوع سند', doc.documentTypeName),
            _buildInfoRow('تاریخ سند', HesabixDateUtils.formatForDisplay(doc.documentDate, widget.calendarController.isJalali)),
            _buildInfoRow('تاریخ ثبت', HesabixDateUtils.formatForDisplay(doc.registeredAt, widget.calendarController.isJalali)),
            _buildInfoRow('ارز', doc.currencyCode ?? 'نامشخص'),
            _buildInfoRow('ایجادکننده', doc.createdByName ?? 'نامشخص'),
            _buildInfoRow('مبلغ کل', formatWithThousands(doc.totalAmount) + ' ریال'),
            if (doc.description != null && doc.description!.isNotEmpty)
              _buildInfoRow('توضیحات', doc.description!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonLines(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط اشخاص (${doc.personLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.personLines.isEmpty)
              const Text('هیچ خط شخصی یافت نشد')
            else
              ...doc.personLines.map((line) => _buildPersonLineItem(line)),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonLineItem(PersonLine line) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.personName ?? 'نامشخص',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (line.description != null && line.description!.isNotEmpty)
                  Text(
                    line.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            formatWithThousands(line.amount) + ' ریال',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountLines(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط حساب‌ها (${doc.accountLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.accountLines.isEmpty)
              const Text('هیچ خط حسابی یافت نشد')
            else
              ...doc.accountLines.map((line) => _buildAccountLineItem(line)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountLineItem(AccountLine line) {
    final isCommission = line.extraInfo?['is_commission_line'] == true;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCommission 
            ? Theme.of(context).colorScheme.error 
            : Theme.of(context).colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isCommission 
          ? Theme.of(context).colorScheme.errorContainer.withOpacity(0.1)
          : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.accountName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'کد: ${line.accountCode}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (line.transactionType != null)
                      Text(
                        'نوع: ${_getTransactionTypeName(line.transactionType!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Text(
                formatWithThousands(line.amount) + ' ریال',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (line.description != null && line.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              line.description!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (isCommission) ...[
            const SizedBox(height: 4),
            Text(
              'کارمزد',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getTransactionTypeName(String type) {
    switch (type) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواهگردان';
      case 'check':
        return 'چک';
      case 'person':
        return 'شخص';
      default:
        return type;
    }
  }

  Widget _buildFooter(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isGeneratingPdf ? null : _generatePdf,
            icon: _isGeneratingPdf 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf),
            label: Text(_isGeneratingPdf ? AppLocalizations.of(context).generating : AppLocalizations.of(context).exportToPdf),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      // ایجاد PDF از سند
      final pdfBytes = await widget.apiClient.downloadPdf(
        '/receipts-payments/${widget.document.id}/pdf',
      );

      // ذخیره فایل
      await _savePdfFile(pdfBytes, widget.document.code);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).pdfSuccess),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).pdfError}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  Future<void> _savePdfFile(List<int> bytes, String filename) async {
    try {
      // استفاده از dart:html برای دانلود فایل در وب
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename.endsWith('.pdf') ? filename : '$filename.pdf')
        ..click();
      html.Url.revokeObjectUrl(url);
      
      print('✅ PDF downloaded successfully: $filename');
    } catch (e) {
      print('❌ Error downloading PDF: $e');
      rethrow;
    }
  }
}

