import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import '../../services/warehouse_service.dart';
import '../../services/invoice_service.dart';
import '../../core/api_client.dart';
import '../../widgets/warehouse/warehouse_document_form_dialog.dart';
import '../../widgets/warehouse/warehouse_document_details_dialog.dart';
import '../../widgets/warehouse/warehouse_doc_wizard_dialog.dart';
import '../../utils/web/web_utils.dart' as web_utils;
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../models/warehouse_document_model.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../l10n/app_localizations.dart';
import '../../utils/snackbar_helper.dart';

class WarehouseDocsPage extends StatefulWidget {
  final int businessId;
  const WarehouseDocsPage({super.key, required this.businessId});

  @override
  State<WarehouseDocsPage> createState() => _WarehouseDocsPageState();
}

class _WarehouseDocsPageState extends State<WarehouseDocsPage> {
  late final ApiClient _apiClient;
  late final WarehouseService _svc;
  late final InvoiceService _invoiceService;
  final GlobalKey _tableKey = GlobalKey();
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _svc = WarehouseService(apiClient: _apiClient);
    _invoiceService = InvoiceService(apiClient: _apiClient);
    CalendarController.load().then((c) {
      if (mounted) {
        setState(() => _calendarController = c);
        // Add listener to refresh table when calendar changes
        c.addListener(_refreshTable);
      }
    });
  }

  @override
  void dispose() {
    _calendarController?.removeListener(_refreshTable);
    super.dispose();
  }

  void _refreshTable() {
    try {
      final current = _tableKey.currentState as dynamic;
      current?.refresh();
    } catch (_) {}
  }

  Future<void> _onAddNew() async {
    final wizardResult = await showDialog<WarehouseDocWizardResult>(
      context: context,
      builder: (_) => WarehouseDocWizardDialog(
        businessId: widget.businessId,
        apiClient: _apiClient,
        calendarController: _calendarController,
      ),
    );
    if (wizardResult == null) return;
    if (wizardResult.isManual) {
      await showDialog(
        context: context,
        builder: (_) => WarehouseDocumentFormDialog(
          businessId: widget.businessId,
          calendarController: _calendarController,
          onSuccess: () => _refreshTable(),
        ),
      );
      return;
    }
    await _handleInvoiceWizardResult(wizardResult);
  }

  Future<void> _handleInvoiceWizardResult(WarehouseDocWizardResult wizardResult) async {
    if (wizardResult.invoiceId == null) return;
    bool loaderDismissed = false;
    void dismissLoader() {
      if (!loaderDismissed && mounted) {
        loaderDismissed = true;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).then((_) => loaderDismissed = true);

    try {
      final invoiceData = await _invoiceService.getInvoice(
        businessId: widget.businessId,
        invoiceId: wizardResult.invoiceId!,
      );
      dismissLoader();
      if (!mounted) return;
      final invoiceItem = Map<String, dynamic>.from(invoiceData['item'] ?? const {});
      final initialLines = _extractLinesFromInvoice(invoiceItem, wizardResult.docType ?? 'issue');
      if (initialLines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هیچ کالایی برای این فاکتور ثبت نشده است')),
        );
        return;
      }
      final dateStr = invoiceItem['document_date']?.toString();
      final initialDate = dateStr == null ? null : DateTime.tryParse(dateStr);

      await showDialog(
        context: context,
        builder: (_) => WarehouseDocumentFormDialog(
          businessId: widget.businessId,
          calendarController: _calendarController,
          initialDocType: wizardResult.docType,
          lockDocType: true,
          initialDocumentDate: initialDate,
          initialLines: initialLines,
          sourceInvoiceId: wizardResult.invoiceId,
          sourceInvoiceCode: wizardResult.invoiceCode,
          sourceInvoiceType: wizardResult.sourceLabel,
          onSuccess: () => _refreshTable(),
        ),
      );
    } catch (e) {
      dismissLoader();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در دریافت فاکتور: $e')),
      );
    } finally {
      dismissLoader();
    }
  }

  List<Map<String, dynamic>> _extractLinesFromInvoice(Map<String, dynamic> invoice, String docType) {
    final movementFallback = docType == 'receipt' ? 'in' : 'out';
    final rawLines = List<dynamic>.from(invoice['product_lines'] ?? const []);
    final List<Map<String, dynamic>> result = [];
    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (map['product_id'] == null) continue;
      final qty = _toDouble(map['quantity']);
      if (qty <= 0) continue;
      final extra = Map<String, dynamic>.from(map['extra_info'] ?? const {});
      final warehouseId = _toInt(map['warehouse_id'] ?? extra['warehouse_id']);
      final movement = (extra['movement'] ?? movementFallback).toString();
      result.add({
        'product_id': map['product_id'],
        'quantity': qty,
        'warehouse_id': warehouseId,
        'movement': movement,
        'extra_info': extra,
      });
    }
    return result;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.isNotEmpty) return int.tryParse(value);
    return null;
  }

  String _getDocTypeLabel(String docType, AppLocalizations t) {
    switch (docType) {
      case 'receipt':
        return t.docTypeReceipt;
      case 'issue':
        return t.docTypeIssue;
      case 'transfer':
        return t.docTypeTransfer;
      case 'adjustment':
        return t.docTypeAdjustment;
      case 'production_in':
        return t.docTypeProductionIn;
      case 'production_out':
        return t.docTypeProductionOut;
      default:
        return docType;
    }
  }

  String _getStatusLabel(String status, AppLocalizations t) {
    switch (status) {
      case 'draft':
        return t.statusDraft;
      case 'posted':
        return t.statusPosted;
      case 'cancelled':
        return t.statusCancelled;
      default:
        return status;
    }
  }

  Future<void> _exportPdf(int docId) async {
    try {
      final api = ApiClient();
      final bytes = await api.downloadPdf(
        '/warehouse-docs/business/${widget.businessId}/$docId/pdf',
      );
      if (!mounted) return;
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          bytes,
          'warehouse_doc_$docId.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('دانلود PDF در موبایل به زودی...')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در دانلود PDF: $e')),
      );
    }
  }

  Future<void> _deleteWarehouseDoc(
    WarehouseDocument doc,
    AppLocalizations t,
  ) async {
    if (doc.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteWarehouseDocument),
        content: Text('آیا از حذف حواله ${doc.code} مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.deleteWarehouseDocument),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _svc.deleteDoc(businessId: widget.businessId, docId: doc.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.deleteWarehouseDocument}: ${t.operationSuccessful}')),
      );
      _refreshTable();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.operationFailed}: $e')),
      );
    }
  }

  Future<void> _bulkDeleteSelected(AppLocalizations t) async {
    final dynamic state = _tableKey.currentState;
    final selectedItems = state?.getSelectedItems() as List<dynamic>? ?? const <dynamic>[];
    if (selectedItems.isEmpty) {
      if (mounted) {
        SnackBarHelper.showError(context, message: t.noRowsSelectedError);
      }
      return;
    }

    final drafts = selectedItems.whereType<WarehouseDocument>().where((doc) => doc.id != null && doc.status == 'draft').toList();
    if (drafts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('هیچ حواله پیش‌نویسی برای حذف انتخاب نشده است')));
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteWarehouseDocument),
        content: Text('آیا از حذف ${drafts.length} حواله پیش‌نویس مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.delete)),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final ids = drafts.map((e) => e.id!).toList();
      final result = await _svc.bulkDeleteDocs(businessId: widget.businessId, ids: ids);
      if (!mounted) return;
      final deleted = result['deleted_count'] ?? 0;
      final skipped = (result['skipped'] as List<dynamic>? ?? const []).length;
      final errors = (result['errors'] as List<dynamic>? ?? const []).length;
      final buffer = StringBuffer('$deleted حواله حذف شد');
      if (skipped > 0) buffer.write(' | $skipped مورد به دلیل وضعیت نامعتبر حذف نشد');
      if (errors > 0) buffer.write(' | $errors خطا');
      SnackBarHelper.show(context, message: buffer.toString());
      _refreshTable();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: '${t.operationFailed}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    
    if (_calendarController == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: DataTableWidget<WarehouseDocument>(
        key: _tableKey,
        calendarController: _calendarController,
        fromJson: (m) => WarehouseDocument.fromJson(m),
        config: DataTableConfig<WarehouseDocument>(
          endpoint: '/api/v1/warehouse-docs/business/${widget.businessId}/search',
          title: t.warehouseDocuments,
          showBackButton: true,
          onBack: () {
            if (!mounted) return;
            if (context.canPop()) {
              context.pop();
            }
          },
          showTableIcon: false,
          showSearch: true,
          showPagination: true,
          showRowNumbers: true,
          enableSorting: true,
          defaultSortBy: 'document_date',
          defaultSortDesc: true,
          searchFields: const ['code'],
          filterFields: const ['doc_type', 'status', 'document_date'],
          dateRangeField: 'document_date',
          enableDateRangeFilter: true,
          showFiltersButton: true,
          enableRowSelection: true,
          enableMultiRowSelection: true,
          customHeaderActions: [
            Tooltip(
              message: t.createWarehouseDocument,
              child: IconButton(
                onPressed: _onAddNew,
                icon: const Icon(Icons.add),
              ),
            ),
            Tooltip(
              message: t.deleteWarehouseDocument,
              child: IconButton(
                onPressed: () => _bulkDeleteSelected(t),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ),
          ],
          columns: [
            ActionColumn('actions', t.actions, actions: [
              DataTableAction(
                icon: Icons.visibility,
                label: t.viewWarehouseDocument,
                onTap: (item) {
                  if (item is WarehouseDocument && item.id != null) {
                    showDialog(
                      context: context,
                      builder: (_) => WarehouseDocumentDetailsDialog(
                        businessId: widget.businessId,
                        documentId: item.id!,
                      ),
                    ).then((_) => _refreshTable());
                  }
                },
              ),
              DataTableAction(
                icon: Icons.print,
                label: t.printWarehouseDocument,
                onTap: (item) {
                  if (item is WarehouseDocument && item.id != null) {
                    _exportPdf(item.id!);
                  }
                },
              ),
              DataTableAction(
                icon: Icons.publish,
                label: t.postWarehouseDocument,
                onTap: (item) async {
                  if (item is WarehouseDocument && item.id != null && item.status == 'draft') {
                    try {
                      await _svc.postDoc(businessId: widget.businessId, docId: item.id!);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${t.postWarehouseDocument}: ${t.operationSuccessful}')),
                      );
                      _refreshTable();
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطا: $e')),
                      );
                    }
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('این عملیات فقط برای حواله‌های پیش‌نویس قابل انجام است')),
                    );
                  }
                },
                enabled: true,
              ),
              DataTableAction(
                icon: Icons.delete,
                label: t.deleteWarehouseDocument,
                isDestructive: true,
                onTap: (item) {
                  if (item is! WarehouseDocument || item.id == null) {
                    return;
                  }
                  if (item.status != 'draft') {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('فقط حواله‌های پیش‌نویس قابل حذف هستند')),
                    );
                    return;
                  }
                  _deleteWarehouseDoc(item, t);
                },
              ),
            ]),
            TextColumn(
              'code',
              t.warehouseDocumentCode,
              formatter: (item) => (item as WarehouseDocument).code,
              width: ColumnWidth.small,
            ),
            TextColumn(
              'doc_type',
              t.warehouseDocumentType,
              formatter: (item) => _getDocTypeLabel((item as WarehouseDocument).docType, t),
              width: ColumnWidth.medium,
              filterType: ColumnFilterType.multiSelect,
              filterOptions: [
                FilterOption(value: 'receipt', label: t.docTypeReceipt),
                FilterOption(value: 'issue', label: t.docTypeIssue),
                FilterOption(value: 'transfer', label: t.docTypeTransfer),
                FilterOption(value: 'adjustment', label: t.docTypeAdjustment),
                FilterOption(value: 'production_in', label: t.docTypeProductionIn),
                FilterOption(value: 'production_out', label: t.docTypeProductionOut),
              ],
            ),
            TextColumn(
              'status',
              t.warehouseDocumentStatus,
              formatter: (item) => _getStatusLabel((item as WarehouseDocument).status, t),
              width: ColumnWidth.small,
              filterType: ColumnFilterType.multiSelect,
              filterOptions: [
                FilterOption(value: 'draft', label: t.statusDraft),
                FilterOption(value: 'posted', label: t.statusPosted),
                FilterOption(value: 'cancelled', label: t.statusCancelled),
              ],
            ),
            DateColumn(
              'document_date',
              t.warehouseDocumentDate,
              formatter: (item) {
                final doc = item as WarehouseDocument;
                if (doc.documentDate == null) return '';
                return HesabixDateUtils.formatForDisplay(
                  doc.documentDate,
                  _calendarController?.isJalali ?? false,
                );
              },
              showTime: false,
              width: ColumnWidth.small,
            ),
            NumberColumn(
              'total_quantity',
              t.warehouseDocumentTotalQuantity,
              formatter: (item) => (item as WarehouseDocument).totalQuantity?.toString() ?? '0',
              decimalPlaces: 2,
              width: ColumnWidth.small,
            ),
          ],
          onRowTap: (item) {
            if (item is WarehouseDocument && item.id != null) {
              showDialog(
                context: context,
                builder: (_) => WarehouseDocumentDetailsDialog(
                  businessId: widget.businessId,
                  documentId: item.id!,
                ),
              ).then((_) => _refreshTable());
            }
          },
        ),
      ),
    );
  }
}
