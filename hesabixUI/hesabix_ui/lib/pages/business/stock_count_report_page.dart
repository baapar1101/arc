import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../models/warehouse_document_model.dart';
import '../../l10n/app_localizations.dart';
import '../../core/calendar_controller.dart';
import '../../core/api_client.dart';
import '../../services/list_filter_preferences_service.dart';

class StockCountReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController? calendarController;
  
  const StockCountReportPage({
    super.key,
    required this.businessId,
    this.calendarController,
  });

  @override
  State<StockCountReportPage> createState() => _StockCountReportPageState();
}

class _StockCountReportPageState extends State<StockCountReportPage> {
  final GlobalKey _tableKey = GlobalKey();
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _calendarController = widget.calendarController ?? ApiClient.getCalendarController();
    if (_calendarController == null) {
      CalendarController.load().then((c) {
        if (mounted) {
          setState(() => _calendarController = c);
          c.addListener(_refreshTable);
        }
      });
    } else {
      _calendarController!.addListener(_refreshTable);
    }
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

  String _getStockCountCode(Map<String, dynamic> doc) {
    final extraInfo = doc['extra_info'] as Map<String, dynamic>?;
    return extraInfo?['stock_count_code'] as String? ?? '-';
  }

  String _getStockCountDate(Map<String, dynamic> doc) {
    final extraInfo = doc['extra_info'] as Map<String, dynamic>?;
    final dateStr = extraInfo?['stock_count_date'] as String?;
    if (dateStr != null) {
      try {
        final date = DateTime.parse(dateStr);
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return dateStr;
      }
    }
    return '-';
  }

  String _getNotes(Map<String, dynamic> doc) {
    final extraInfo = doc['extra_info'] as Map<String, dynamic>?;
    return extraInfo?['notes'] as String? ?? '-';
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
          businessId: widget.businessId,
          persistTableFiltersPageId: ListFilterPageIds.stockCountReportTable,
          title: 'گزارش انبار گردانی',
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
          filterFields: const ['status', 'document_date'],
          dateRangeField: 'document_date',
          enableDateRangeFilter: true,
          showFiltersButton: true,
          enableRowSelection: false,
          additionalParams: {
            'doc_type': ['adjustment'],
          },
          columns: [
            ActionColumn('actions', 'عملیات', actions: [
              DataTableAction(
                icon: Icons.visibility,
                label: 'مشاهده',
                onTap: (item) {
                  if (item is WarehouseDocument && item.id != null) {
                    context.go('/business/${widget.businessId}/warehouse-docs/${item.id}');
                  }
                },
              ),
            ]),
            TextColumn(
              'code',
              'کد حواله',
              formatter: (item) => (item as WarehouseDocument).code,
              width: ColumnWidth.small,
            ),
            TextColumn(
              'stock_count_code',
              'کد انبار گردانی',
              formatter: (item) {
                final doc = (item as WarehouseDocument).toJson();
                return _getStockCountCode(doc);
              },
              width: ColumnWidth.medium,
            ),
            TextColumn(
              'stock_count_date',
              'تاریخ انبار گردانی',
              formatter: (item) {
                final doc = (item as WarehouseDocument).toJson();
                return _getStockCountDate(doc);
              },
              width: ColumnWidth.small,
            ),
            TextColumn(
              'document_date',
              'تاریخ حواله',
              formatter: (item) {
                final doc = item as WarehouseDocument;
                if (doc.documentDate != null) {
                  final date = doc.documentDate!;
                  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                }
                return '-';
              },
              width: ColumnWidth.small,
            ),
            TextColumn(
              'status',
              'وضعیت',
              formatter: (item) {
                final status = (item as WarehouseDocument).status;
                switch (status) {
                  case 'draft':
                    return 'پیش‌نویس';
                  case 'posted':
                    return 'پست شده';
                  case 'cancelled':
                    return 'لغو شده';
                  default:
                    return status;
                }
              },
              width: ColumnWidth.small,
              filterType: ColumnFilterType.multiSelect,
              filterOptions: const [
                FilterOption(value: 'draft', label: 'پیش‌نویس'),
                FilterOption(value: 'posted', label: 'پست شده'),
                FilterOption(value: 'cancelled', label: 'لغو شده'),
              ],
            ),
            TextColumn(
              'total_quantity',
              'تعداد کل',
              formatter: (item) {
                final qty = (item as WarehouseDocument).totalQuantity;
                if (qty != null) {
                  return qty.toStringAsFixed(2);
                }
                return '-';
              },
              width: ColumnWidth.small,
            ),
            TextColumn(
              'notes',
              'یادداشت',
              formatter: (item) {
                final doc = (item as WarehouseDocument).toJson();
                final notes = _getNotes(doc);
                return notes.length > 50 ? '${notes.substring(0, 50)}...' : notes;
              },
              width: ColumnWidth.large,
            ),
          ],
        
        expandBodyHeightToFitRows: true,),
      ),
    );
  }
}

