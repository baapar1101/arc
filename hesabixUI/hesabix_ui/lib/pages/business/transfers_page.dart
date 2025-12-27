import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/api_client.dart';
import '../../models/transfer_document.dart';
import '../../services/transfer_service.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../widgets/date_input_field.dart';
import '../../widgets/transfer/transfer_form_dialog.dart';
import '../../widgets/transfer/transfer_details_dialog.dart';
import '../../utils/snackbar_helper.dart';

class TransfersPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final ApiClient apiClient;

  const TransfersPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    required this.apiClient,
  });

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  // کنترل جدول برای دسترسی به refresh
  final GlobalKey _tableKey = GlobalKey();
  DateTime? _fromDate;
  DateTime? _toDate;
  List<FilterOption> _projectFilterOptions = [];
  bool _loadingProjects = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
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
                child: DataTableWidget<TransferDocument>(
                  key: _tableKey,
                  config: _buildTableConfig(t),
                  fromJson: (json) => TransferDocument.fromJson(json),
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
                  t.transfers,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت اسناد انتقال وجه',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'افزودن انتقال جدید',
            child: FilledButton.icon(
              onPressed: _onAddNew,
              icon: const Icon(Icons.add),
              label: Text(t.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
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

  DataTableConfig<TransferDocument> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<TransferDocument>(
      endpoint: '/businesses/${widget.businessId}/transfers',
      title: t.transfers,
      excelEndpoint: '/businesses/${widget.businessId}/transfers/export/excel',
      pdfEndpoint: '/businesses/${widget.businessId}/transfers/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'transfers',
      reportSubtype: 'list',
      getExportParams: () => {
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
      },
      columns: [
        TextColumn(
          'code',
          'کد سند',
          width: ColumnWidth.medium,
          formatter: (it) => it.code,
        ),
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (it) => (it.description ?? '').isNotEmpty ? it.description! : _composeDesc(it),
        ),
        TextColumn(
          'source',
          'مبدا',
          width: ColumnWidth.large,
          formatter: (it) => _composeSource(it),
        ),
        TextColumn(
          'destination',
          'مقصد',
          width: ColumnWidth.large,
          formatter: (it) => _composeDestination(it),
        ),
        DateColumn(
          'document_date',
          'تاریخ سند',
          width: ColumnWidth.medium,
          formatter: (it) => HesabixDateUtils.formatForDisplay(it.documentDate, widget.calendarController.isJalali),
        ),
        TextColumn(
          'total_amount',
          'مبلغ کل',
          width: ColumnWidth.large,
          formatter: (it) => '${formatWithThousands(it.totalAmount)} ${it.currencyCode ?? 'ریال'}',
        ),
        TextColumn(
          'created_by_name',
          'ایجادکننده',
          width: ColumnWidth.medium,
          formatter: (it) => it.createdByName ?? 'نامشخص',
        ),
        DateColumn(
          'registered_at',
          'تاریخ ثبت',
          width: ColumnWidth.medium,
          formatter: (it) => HesabixDateUtils.formatForDisplay(it.registeredAt, widget.calendarController.isJalali),
        ),
        TextColumn(
          'project_name',
          'پروژه',
          width: ColumnWidth.medium,
          formatter: (it) => it.projectName ?? '-',
          searchable: true,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: _projectFilterOptions,
        ),
        ActionColumn(
          'actions',
          'عملیات',
          width: ColumnWidth.medium,
          actions: [
            DataTableAction(icon: Icons.visibility, label: 'مشاهده', onTap: (it) => _onView(it as TransferDocument)),
            DataTableAction(icon: Icons.edit, label: 'ویرایش', onTap: (it) => _onEdit(it as TransferDocument)),
            DataTableAction(icon: Icons.delete, label: 'حذف', onTap: (it) => _onDelete(it as TransferDocument), isDestructive: true),
          ],
        ),
      ],
      searchFields: ['code', 'created_by_name', 'source', 'destination'],
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
      // انتخاب سطرها در این صفحه استفاده خاصی ندارد
      additionalParams: {
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
      },
      onRowTap: (item) => _onView(item as TransferDocument),
      onRowDoubleTap: (item) => _onEdit(item as TransferDocument),
      emptyStateMessage: 'هیچ سند انتقالی یافت نشد',
      loadingMessage: 'در حال بارگذاری اسناد انتقال...',
      errorMessage: 'خطا در بارگذاری اسناد انتقال',
    );
  }

  String _typeFa(String? t) {
    switch (t) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواه';
      default:
        return t ?? '';
    }
  }

  String _composeSource(TransferDocument it) {
    return '${_typeFa(it.sourceType)} ${it.sourceName ?? ''}'.trim();
  }

  String _composeDestination(TransferDocument it) {
    return '${_typeFa(it.destinationType)} ${it.destinationName ?? ''}'.trim();
  }

  String _composeDesc(TransferDocument it) {
    final src = _composeSource(it);
    final dst = _composeDestination(it);
    if (src.isEmpty && dst.isEmpty) return '';
    return 'انتقال $src → $dst';
  }

  void _onAddNew() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TransferFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        authStore: widget.authStore,
        apiClient: widget.apiClient,
        onSuccess: () {},
      ),
    );
    if (result == true) _refreshData();
  }

  void _onView(TransferDocument item) async {
    final svc = TransferService(widget.apiClient);
    final full = await svc.getById(item.id);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => TransferDetailsDialog(
        document: full,
        calendarController: widget.calendarController,
      ),
    );
  }

  void _onEdit(TransferDocument item) async {
    final svc = TransferService(widget.apiClient);
    final full = await svc.getById(item.id);
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TransferFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        authStore: widget.authStore,
        apiClient: widget.apiClient,
        initial: full,
        onSuccess: () {},
      ),
    );
    if (result == true) _refreshData();
  }

  void _onDelete(TransferDocument item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف انتقال'),
        content: Text('آیا از حذف سند ${item.code} مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final svc = TransferService(widget.apiClient);
        await svc.deleteById(item.id);
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'حذف شد');
        }
        _refreshData();
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, message: 'خطا: $e');
        }
      }
    }
  }
}
