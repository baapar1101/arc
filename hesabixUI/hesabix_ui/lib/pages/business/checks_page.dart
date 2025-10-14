import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth_store.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/permission/permission_widgets.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../models/person_model.dart';

class ChecksPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const ChecksPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<ChecksPage> createState() => _ChecksPageState();
}

class _ChecksPageState extends State<ChecksPage> {
  final GlobalKey _tableKey = GlobalKey();
  Person? _selectedPerson;

  void _refresh() {
    try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('checks')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      body: DataTableWidget<Map<String, dynamic>>(
        key: _tableKey,
        config: _buildConfig(t, context),
        fromJson: (json) => json,
      ),
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildConfig(AppLocalizations t, BuildContext context) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/checks/businesses/${widget.businessId}/checks',
      title: (t.localeName == 'fa') ? 'چک‌ها' : 'Checks',
      excelEndpoint: '/api/v1/checks/businesses/${widget.businessId}/checks/export/excel',
      pdfEndpoint: '/api/v1/checks/businesses/${widget.businessId}/checks/export/pdf',
      getExportParams: () => {'business_id': widget.businessId, if (_selectedPerson != null) 'person_id': _selectedPerson!.id},
      additionalParams: { if (_selectedPerson != null) 'person_id': _selectedPerson!.id },
      showBackButton: true,
      onBack: () => Navigator.of(context).maybePop(),
      showTableIcon: false,
      showRowNumbers: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      showColumnSearch: true,
      showActiveFilters: true,
      showClearFiltersButton: true,
      columns: [
        TextColumn(
          'type',
          'نوع',
          width: ColumnWidth.small,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: const [
            FilterOption(value: 'received', label: 'دریافتی'),
            FilterOption(value: 'transferred', label: 'واگذار شده'),
          ],
          formatter: (row) => (row['type'] == 'received') ? 'دریافتی' : (row['type'] == 'transferred' ? 'واگذار شده' : '-'),
        ),
        TextColumn('person_name', 'شخص', width: ColumnWidth.large,
          formatter: (row) => (row['person_name'] ?? '-'),
        ),
        DateColumn(
          'issue_date',
          'تاریخ صدور',
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.dateRange,
          formatter: (row) => (row['issue_date'] ?? '-'),
        ),
        DateColumn(
          'due_date',
          'تاریخ سررسید',
          width: ColumnWidth.medium,
          filterType: ColumnFilterType.dateRange,
          formatter: (row) => (row['due_date'] ?? '-'),
        ),
        TextColumn('check_number', 'شماره چک', width: ColumnWidth.medium,
          formatter: (row) => (row['check_number'] ?? '-'),
        ),
        TextColumn('sayad_code', 'شناسه صیاد', width: ColumnWidth.medium,
          formatter: (row) => (row['sayad_code'] ?? '-'),
        ),
        TextColumn('bank_name', 'بانک', width: ColumnWidth.medium,
          formatter: (row) => (row['bank_name'] ?? '-'),
        ),
        TextColumn('branch_name', 'شعبه', width: ColumnWidth.medium,
          formatter: (row) => (row['branch_name'] ?? '-'),
        ),
        NumberColumn('amount', 'مبلغ', width: ColumnWidth.medium,
          formatter: (row) => (row['amount']?.toString() ?? '-'),
        ),
        TextColumn('currency', 'ارز', width: ColumnWidth.small,
          formatter: (row) => (row['currency'] ?? '-'),
        ),
        ActionColumn('actions', t.actions, actions: [
          DataTableAction(
            icon: Icons.edit,
            label: t.edit,
            onTap: (row) {
              final id = row is Map<String, dynamic> ? row['id'] : null;
              if (id is int) {
                context.go('/business/${widget.businessId}/checks/$id/edit');
              }
            },
          ),
        ]),
      ],
      searchFields: ['check_number','sayad_code','bank_name','branch_name','person_name'],
      filterFields: ['type','currency','issue_date','due_date'],
      defaultPageSize: 20,
      customHeaderActions: [
        // فیلتر شخص
        SizedBox(
          width: 280,
          child: PersonComboboxWidget(
            businessId: widget.businessId,
            selectedPerson: _selectedPerson,
            onChanged: (p) {
              setState(() { _selectedPerson = p; });
              _refresh();
            },
            isRequired: false,
            label: 'شخص',
            hintText: 'جست‌وجوی شخص',
          ),
        ),
        const SizedBox(width: 8),
        PermissionButton(
          section: 'checks',
          action: 'add',
          authStore: widget.authStore,
          child: Tooltip(
            message: t.add,
            child: IconButton(
              onPressed: () => context.go('/business/${widget.businessId}/checks/new'),
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ],
      onRowTap: (row) {
        final id = row is Map<String, dynamic> ? row['id'] : null;
        if (id is int) {
          context.go('/business/${widget.businessId}/checks/$id/edit');
        }
      },
    );
  }
}


