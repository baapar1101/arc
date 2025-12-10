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
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/invoice/invoice_import_dialog.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/project/project_selector_widget.dart';

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
  late final BusinessDashboardService _dashboardService = BusinessDashboardService(widget.apiClient);

  String? _selectedInvoiceType;
  bool _isInitialized = false;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool? _isProforma; // null=همه، true=پیشفاکتور، false=قطعی

  int? _selectedFiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = [];
  int? _selectedProjectId; // فیلتر پروژه
  List<FilterOption> _projectFilterOptions = [];
  bool _loadingProjects = false;
  
  void _refreshData() {
    // استفاده از addPostFrameCallback تا بعد از rebuild اجرا شود
    // این باعث می‌شود که widget.config با مقادیر جدید فیلترها rebuild شده باشد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = _tableKey.currentState;
      if (state != null) {
        try {
          // ignore: avoid_dynamic_calls
          (state as dynamic).refresh();
          return;
        } catch (_) {}
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _loadProjects();
    // بعد از اولین build، flag را set کن
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _isInitialized = true;
      }
    });
  }

  /// بارگذاری لیست پروژه‌ها برای فیلتر
  Future<void> _loadProjects() async {
    if (!mounted) return;
    setState(() => _loadingProjects = true);
    
    try {
      final response = await widget.apiClient.post(
        '/businesses/${widget.businessId}/projects/search',
        data: {
          'take': 1000,
          'skip': 0,
          'is_active': true,
        },
      );
      
      if (response.data['success'] == true) {
        final List<dynamic> projects = response.data['data']['items'] ?? [];
        if (mounted) {
          setState(() {
            _projectFilterOptions = projects.map((p) => FilterOption(
              value: p['id'].toString(),
              label: p['name'] ?? 'پروژه ${p['id']}',
              description: p['code'],
            )).toList();
            _loadingProjects = false;
          });
        }
      }
    } catch (e) {
      debugPrint('خطا در بارگذاری پروژه‌ها: $e');
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  Future<void> _loadFiscalYears() async {
    try {
      final items = await _dashboardService.listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        // اگر سال مالی انتخاب نشده، سال مالی جاری را انتخاب کن
        if (_selectedFiscalYearId == null && _fiscalYears.isNotEmpty) {
          final current = _fiscalYears.firstWhere(
            (fy) => fy['is_current'] == true,
            orElse: () => _fiscalYears.first,
          );
          _selectedFiscalYearId = current['id'] as int?;
        }
      });
    } catch (_) {
      // ignore errors
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // اگر صفحه قبلاً initialize شده بود، داده‌ها را refresh کن
    // این برای زمانی است که از صفحه دیگری (مثل ثبت فاکتور) به این صفحه برمی‌گردیم
    if (_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshData();
        }
      });
    }
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
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _onAddNew,
              icon: const Icon(Icons.add),
              label: Text(t.add),
            )
          : null,
    );
  }

  Widget _buildHeader(AppLocalizations t, bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.getPadding(context),
        ResponsiveHelper.getPadding(context),
        ResponsiveHelper.getPadding(context),
        8,
      ),
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
          // دکمه افزودن فاکتور - فقط در دسکتاپ نمایش داده می‌شود
          if (!isMobile)
            FilledButton.icon(
              onPressed: _onAddNew,
              icon: const Icon(Icons.add),
              label: Text(t.add),
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
          // نوع فاکتور - همیشه scrollable افقی
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String?>(
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
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
          const SizedBox(height: 8),
          // فیلتر سال مالی و پروژه
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
          if (_fiscalYears.isNotEmpty)
                SizedBox(
                width: isMobile ? double.infinity : 280,
                child: DropdownButtonFormField<int>(
                  value: _selectedFiscalYearId,
                  decoration: InputDecoration(
                    labelText: t.fiscalYear,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                  items: _fiscalYears.map<DropdownMenuItem<int>>((fy) {
                    final id = fy['id'] as int?;
                    final title = (fy['title'] ?? '').toString();
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(
                        title.isNotEmpty ? title : 'FY ${id ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedFiscalYearId = val;
                    });
                    _refreshData();
                  },
                ),
              ),
              // فیلتر پروژه
              SizedBox(
                width: isMobile ? double.infinity : 280,
                child: _buildProjectFilter(),
              ),
            ],
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
                SegmentedButton<bool?>(
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

  Widget _buildProjectFilter() {
    return ProjectSelectorWidget(
      businessId: widget.businessId,
      apiClient: widget.apiClient,
      selectedProjectId: _selectedProjectId,
      onChanged: (projectId) {
        setState(() {
          _selectedProjectId = projectId;
        });
        _refreshData();
      },
      authStore: widget.authStore, // برای بررسی دسترسی به ایجاد پروژه
      calendarController: widget.calendarController, // برای دیالوگ ایجاد پروژه
      allowNull: true,
      labelText: 'پروژه',
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
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.drive_folder_upload,
                label: t.taxAddToWorkspaceSingle,
                onTap: (item) => _onAddToTaxWorkspace(item as InvoiceListItem),
              ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.folder_off,
                label: t.taxRemoveFromWorkspaceSingle,
                onTap: (item) => _onRemoveFromTaxWorkspace(item as InvoiceListItem),
              ),
          ],
        ),
        // کد سند
        TextColumn('code', t.code, formatter: (item) => item.code, width: ColumnWidth.small),
        // نوع (نمایش خوانا؛ و استفاده از فیلد document_type_name برای خروجی‌ها)
        TextColumn(
          'document_type_name',
          t.type,
          width: ColumnWidth.medium,
          formatter: (item) {
            final it = item as InvoiceListItem;
            final friendly = (it.documentTypeName).trim();
            if (friendly.isNotEmpty && friendly != it.documentType) {
              return friendly;
            }
            switch (it.documentType) {
              case 'invoice_sales':
                return t.invoiceTypeSales;
              case 'invoice_sales_return':
                return t.invoiceTypeSalesReturn;
              case 'invoice_purchase':
                return t.invoiceTypePurchase;
              case 'invoice_purchase_return':
                return t.invoiceTypePurchaseReturn;
              case 'invoice_direct_consumption':
                return t.invoiceTypeDirectConsumption;
              case 'invoice_production':
                return t.invoiceTypeProduction;
              case 'invoice_waste':
                return t.invoiceTypeWaste;
              default:
                return it.documentType;
            }
          },
        ),
        // طرف حساب
        TextColumn(
          'counterparty',
          'طرف حساب',
          width: ColumnWidth.medium,
          formatter: (item) {
            final it = item as InvoiceListItem;
            return (it.counterparty == null || it.counterparty!.trim().isEmpty) ? t.unknown : it.counterparty!;
          },
        ),
        // تاریخ سند
        DateColumn(
          'document_date',
          t.documentDate,
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),
        // مبلغ کل
        TextColumn(
          'total_amount',
          t.totalAmount,
          width: ColumnWidth.large,
          formatter: (item) => item.totalAmount != null ? '${formatWithThousands(item.totalAmount!, decimalPlaces: 2)} ${item.currencyCode ?? 'ریال'}' : '-',
        ),
        // اقساطی؟
        CustomColumn(
          'is_installment_sale',
          t.installmentColumn,
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          builder: (dynamic item, int index) {
            final invoice = item as InvoiceListItem;
            if (!invoice.isInstallmentSale) {
              return const SizedBox.shrink();
            }
            return const Icon(Icons.check_circle, color: Colors.green, size: 18);
          },
          tooltip: t.installmentsTitle,
        ),
        // ارز
        TextColumn('currency_code', t.currency, formatter: (item) => item.currencyCode ?? t.unknown, width: ColumnWidth.small),
        // ایجادکننده
        TextColumn('created_by_name', t.createdBy, formatter: (item) => item.createdByName ?? t.unknown, width: ColumnWidth.medium),
        // پروژه
        TextColumn(
          'project_name',
          'پروژه',
          width: ColumnWidth.medium,
          formatter: (item) => item.projectName ?? '-',
          searchable: true,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: _projectFilterOptions,
        ),
        // پیش‌فاکتور (تیک برای true، خالی برای false)
        CustomColumn(
          'is_proforma',
          t.proforma,
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          builder: (dynamic item, int index) {
            final invoice = item as InvoiceListItem;
            return invoice.isProforma
                ? const Icon(Icons.check, size: 18, color: Colors.black87)
                : const SizedBox.shrink();
          },
          tooltip: t.proforma,
        ),
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
      showExportButtons: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      defaultPageSize: 20,
      pageSizeOptions: const [10, 20, 50, 100],
      additionalParams: {
        'document_type': _selectedInvoiceType,
        if (_fromDate != null) 'from_date': _fromDate!.toUtc().toIso8601String(),
        if (_toDate != null) 'to_date': _toDate!.toUtc().toIso8601String(),
        if (_isProforma != null) 'is_proforma': _isProforma,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      },
      onRowTap: (item) => _onView(item as InvoiceListItem),
      emptyStateMessage: t.noInvoicesFound,
      loadingMessage: t.loadingInvoices,
      errorMessage: t.errorLoadingInvoices,
      customHeaderActions: [
        Tooltip(
          message: 'ایمپورت فاکتورها از فایل Excel',
          child: IconButton(
            onPressed: _onImport,
            icon: const Icon(Icons.upload_file),
            tooltip: 'ایمپورت از اکسل',
          ),
        ),
      ],
    );
  }

  Future<void> _onImport() async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => InvoiceImportDialog(
        businessId: widget.businessId,
      ),
    );
    if (result == true && mounted) {
      _refreshData();
    }
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
    
    // دریافت اطلاعات حذف
    Map<String, dynamic>? deleteInfo;
    try {
      deleteInfo = await _invoiceService.getInvoiceDeleteInfo(
        businessId: widget.businessId,
        invoiceId: item.id,
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'خطا در دریافت اطلاعات: $e');
      return;
    }
    
    // بررسی کارپوشه مودیان
    if (deleteInfo['is_in_tax_workspace'] == true) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.deleteInvoiceTaxWorkspaceError);
      return;
    }
    
    // ساخت محتوای هشدار
    final List<Widget> warningWidgets = [
      Text(t.deleteInvoiceConfirm(item.code)),
      const SizedBox(height: 16),
    ];
    
    // نمایش اطلاعات اسناد دریافت/پرداخت
    final receiptPayments = deleteInfo['receipt_payment_documents'] as List<dynamic>?;
    if (receiptPayments != null && receiptPayments.isNotEmpty) {
      final nonZeroPayments = receiptPayments.where((p) => p['is_zero'] != true).toList();
      if (nonZeroPayments.isNotEmpty) {
        warningWidgets.add(
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payment, size: 20, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      t.deleteInvoiceReceiptPaymentsWarning,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...nonZeroPayments.take(3).map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${p['code']} (${p['type'] == 'receipt' ? 'دریافت' : 'پرداخت'}): ${formatWithThousands(p['amount'] ?? 0)}',
                    style: TextStyle(fontSize: 12),
                  ),
                )),
                if (nonZeroPayments.length > 3)
                  Text(
                    'و ${nonZeroPayments.length - 3} سند دیگر...',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        );
        warningWidgets.add(const SizedBox(height: 12));
      }
    }
    
    // نمایش اطلاعات حواله‌های انبار
    final warehouseDocs = deleteInfo['warehouse_documents'] as List<dynamic>?;
    if (warehouseDocs != null && warehouseDocs.isNotEmpty) {
      final finalizedWarehouses = warehouseDocs.where((w) => w['is_finalized'] == true).toList();
      if (finalizedWarehouses.isNotEmpty) {
        warningWidgets.add(
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2, size: 20, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      t.deleteInvoiceWarehouseWarning,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...finalizedWarehouses.take(3).map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${w['code']}',
                    style: TextStyle(fontSize: 12),
                  ),
                )),
              ],
            ),
          ),
        );
        warningWidgets.add(const SizedBox(height: 12));
      }
    }
    
    // نمایش اطلاعات اقساط
    if (deleteInfo['has_installments'] == true) {
      final installmentInfo = deleteInfo['installment_info'] as Map<String, dynamic>?;
      if (installmentInfo != null) {
        warningWidgets.add(
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.deleteInvoiceInstallmentsWarning(
                      installmentInfo['count']?.toString() ?? '0',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        warningWidgets.add(const SizedBox(height: 12));
      }
    }
    
    // نمایش dialog تأیید
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(t.deleteConfirmTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: warningWidgets,
          ),
        ),
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
        SnackBarHelper.showSuccess(context, message: t.deletedInvoiceSuccess(item.code));
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
      SnackBarHelper.showError(context, message: t.deleteInvoiceErrorWithMessage(e.toString()));
    }
  }

  Future<void> _onAddToTaxWorkspace(InvoiceListItem item) async {
    final t = AppLocalizations.of(context);

    // فقط برای فاکتورهای فروش و برگشت از فروش و غیر پیش‌نویس
    final isSalesOrReturn = item.documentType == 'invoice_sales' || item.documentType == 'invoice_sales_return';
    if (!isSalesOrReturn || item.isProforma) {
      SnackBarHelper.showWarning(context, message: t.taxAddToWorkspaceNotAllowed);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxAddToWorkspaceDialogTitle),
        content: Text(t.taxAddToWorkspaceDialogMessage(item.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.drive_folder_upload),
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
      final success = await _invoiceService.addToTaxWorkspace(
        businessId: widget.businessId,
        invoiceId: item.id,
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      if (success) {
        SnackBarHelper.showSuccess(context, message: t.taxAddToWorkspaceSuccess(item.code));
        _refreshData();
      } else {
        throw Exception(t.taxAddToWorkspaceError);
      }
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxAddToWorkspaceErrorWithMessage(e.toString()));
    }
  }

  Future<void> _onRemoveFromTaxWorkspace(InvoiceListItem item) async {
    final t = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxRemoveFromWorkspaceDialogTitle),
        content: Text(t.taxRemoveFromWorkspaceDialogMessage(item.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.folder_off),
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
      final success = await _invoiceService.removeFromTaxWorkspace(
        businessId: widget.businessId,
        invoiceId: item.id,
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      if (success) {
        SnackBarHelper.showSuccess(context, message: t.taxRemoveFromWorkspaceSuccess);
        _refreshData();
      } else {
        throw Exception(t.taxRemoveFromWorkspaceError);
      }
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.taxRemoveFromWorkspaceErrorWithMessage(e.toString()));
    }
  }
}


