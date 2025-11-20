import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/warehouse_service.dart';
import '../../core/api_client.dart';
import '../../widgets/warehouse/warehouse_document_form_dialog.dart';
import '../../widgets/warehouse/warehouse_document_details_dialog.dart';
import '../../utils/web/web_utils.dart' as web_utils;
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../models/warehouse_document_model.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../l10n/app_localizations.dart';

class WarehouseDocsPage extends StatefulWidget {
  final int businessId;
  const WarehouseDocsPage({super.key, required this.businessId});

  @override
  State<WarehouseDocsPage> createState() => _WarehouseDocsPageState();
}

class _WarehouseDocsPageState extends State<WarehouseDocsPage> {
  final _svc = WarehouseService();
  final GlobalKey _tableKey = GlobalKey();
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
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
          onBack: () => Navigator.of(context).maybePop(),
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
          customHeaderActions: [
            Tooltip(
              message: t.createWarehouseDocument,
              child: IconButton(
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => WarehouseDocumentFormDialog(
                      businessId: widget.businessId,
                      onSuccess: () => _refreshTable(),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
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
