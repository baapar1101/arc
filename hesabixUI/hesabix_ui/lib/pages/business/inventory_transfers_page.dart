import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/transfer/inventory_transfer_form_dialog.dart';

class InventoryTransfersPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  const InventoryTransfersPage({super.key, required this.businessId, required this.calendarController});

  @override
  State<InventoryTransfersPage> createState() => _InventoryTransfersPageState();
}

class _InventoryTransfersPageState extends State<InventoryTransfersPage> {
  final GlobalKey _tableKey = GlobalKey();

  void _refreshTable() {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        (state as dynamic).refresh();
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _onAddNew() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => InventoryTransferFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
      ),
    );
    if (res == true) _refreshTable();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('انتقال موجودی بین انبارها', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                FilledButton.icon(onPressed: _onAddNew, icon: const Icon(Icons.add), label: const Text('افزودن انتقال')),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DataTableWidget<Map<String, dynamic>>(
                key: _tableKey,
                config: DataTableConfig<Map<String, dynamic>>(
                  endpoint: '/api/v1/inventory-transfers/business/${widget.businessId}/query',
                  excelEndpoint: '/api/v1/inventory-transfers/business/${widget.businessId}/export/excel',
                  pdfEndpoint: '/api/v1/inventory-transfers/business/${widget.businessId}/export/pdf',
                  businessId: widget.businessId,
                  reportModuleKey: 'inventory_transfers',
                  reportSubtype: 'list',
                  title: 'انتقال موجودی بین انبارها',
                  showBackButton: true,
                  showSearch: false,
                  showPagination: true,
                  showRowNumbers: true,
                  enableSorting: true,
                  showExportButtons: true,
                  columns: [
                    TextColumn('code', 'کد سند', formatter: (it) => (it as Map<String, dynamic>)['code']?.toString()),
                    DateColumn('document_date', 'تاریخ سند', formatter: (it) => (it as Map<String, dynamic>)['document_date']?.toString()),
                    TextColumn('description', 'شرح', formatter: (it) => (it as Map<String, dynamic>)['description']?.toString()),
                  ],
                  searchFields: const [],
                  defaultPageSize: 20,
                ),
                fromJson: (json) => Map<String, dynamic>.from(json as Map),
                calendarController: widget.calendarController,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


