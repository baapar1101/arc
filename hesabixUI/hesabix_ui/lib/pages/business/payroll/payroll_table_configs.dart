import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/date_utils.dart';
import '../../../widgets/data_table/data_table_config.dart';
import 'payroll_calendar_utils.dart';
import 'payroll_ui.dart';

/// پیکربندی جداول یکپارچه حقوق و دستمزد (DataTableWidget + localRawItems).
class PayrollTableConfigs {
  PayrollTableConfigs._();

  static String _formatApiDate(
    Map<String, dynamic> row,
    String key,
    bool isJalali,
  ) {
    return HesabixDateUtils.formatApiDateForDisplay(
      row[key],
      isJalali,
      rawValue: row['${key}_raw'],
    );
  }

  static DataTableConfig<Map<String, dynamic>> runs({
    required AppLocalizations t,
    required bool isJalali,
    void Function(Map<String, dynamic> row)? onOpen,
  }) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_payroll_runs',
      tableId: 'payroll_runs',
      title: t.payrollRunsTab,
      showSearch: true,
      showFilters: false,
      showPagination: true,
      defaultPageSize: 25,
      showExportButtons: false,
      showColumnSearch: false,
      enableGlobalSearch: true,
      searchFields: const ['title', 'code', 'status'],
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      onRowTap: onOpen == null ? null : (item) => onOpen(Map<String, dynamic>.from(item as Map)),
      columns: [
        TextColumn(
          'title',
          t.payrollRunTitle,
          width: ColumnWidth.large,
          formatter: (row) {
            final m = row as Map<String, dynamic>;
            final title = '${m['title'] ?? ''}'.trim();
            return title.isNotEmpty ? title : '${m['code'] ?? '-'}';
          },
        ),
        TextColumn(
          'code',
          t.localeName == 'fa' ? 'کد' : 'Code',
          width: ColumnWidth.small,
          formatter: (row) => '${(row as Map<String, dynamic>)['code'] ?? '-'}',
        ),
        DateColumn(
          'run_date',
          t.payrollRunDate,
          width: ColumnWidth.medium,
          formatter: (row) => _formatApiDate(row as Map<String, dynamic>, 'run_date', isJalali),
        ),
        TextColumn(
          'status',
          t.status,
          width: ColumnWidth.small,
          formatter: (row) => PayrollUi.runStatusLabel(t, (row as Map)['status'] as String?),
        ),
        NumberColumn(
          'net_total',
          t.payrollNetTotal,
          width: ColumnWidth.medium,
          formatter: (row) => PayrollUi.formatMoney((row as Map)['net_total']),
        ),
        NumberColumn(
          'gross_total',
          t.payrollGrossTotal,
          width: ColumnWidth.medium,
          formatter: (row) => PayrollUi.formatMoney((row as Map)['gross_total']),
        ),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> periods({
    required AppLocalizations t,
    required bool isJalali,
    required bool canOperate,
    void Function(Map<String, dynamic> period)? onClose,
  }) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_payroll_periods',
      tableId: 'payroll_periods',
      title: t.payrollPeriodsTab,
      showSearch: true,
      showFilters: false,
      showPagination: true,
      defaultPageSize: 25,
      showExportButtons: false,
      showColumnSearch: false,
      enableGlobalSearch: true,
      searchFields: const ['title', 'status'],
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      columns: [
        TextColumn(
          'title',
          t.payrollPeriod,
          width: ColumnWidth.large,
          formatter: (row) => PayrollCalendarUtils.periodTitle(row as Map<String, dynamic>, isJalali),
        ),
        TextColumn(
          'year_month',
          t.payrollPeriodYear,
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          formatter: (row) {
            final m = row as Map<String, dynamic>;
            final y = (m['year'] as num?)?.toInt();
            final mo = (m['month'] as num?)?.toInt();
            if (y == null || mo == null) return '-';
            return PayrollCalendarUtils.formatPeriodYearMonth(y, mo, isJalali);
          },
        ),
        DateColumn(
          'start_date',
          t.payrollPeriodStartDate,
          width: ColumnWidth.medium,
          formatter: (row) => _formatApiDate(row as Map<String, dynamic>, 'start_date', isJalali),
        ),
        DateColumn(
          'end_date',
          t.payrollPeriodEndDate,
          width: ColumnWidth.medium,
          formatter: (row) => _formatApiDate(row as Map<String, dynamic>, 'end_date', isJalali),
        ),
        TextColumn(
          'status',
          t.status,
          width: ColumnWidth.small,
          formatter: (row) => PayrollUi.periodStatusLabel(t, (row as Map)['status'] as String?),
        ),
        if (canOperate && onClose != null)
          ActionColumn('actions', t.actions, actions: [
            DataTableAction(
              icon: Icons.lock_outline,
              label: t.payrollClosePeriod,
              onTap: (item) => onClose(Map<String, dynamic>.from(item as Map)),
              enabled: (item) => (item as Map)['status'] != 'closed',
            ),
          ]),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> items({
    required AppLocalizations t,
    required bool canManage,
    String Function(String? kind)? kindLabel,
    void Function(Map<String, dynamic> item)? onEdit,
  }) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_payroll_items',
      tableId: 'payroll_items',
      title: t.payrollItemsTab,
      showSearch: true,
      showFilters: false,
      showPagination: true,
      defaultPageSize: 25,
      showExportButtons: false,
      showColumnSearch: false,
      enableGlobalSearch: true,
      searchFields: const ['name', 'code', 'item_kind'],
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      onRowTap: canManage && onEdit != null
          ? (item) => onEdit(Map<String, dynamic>.from(item as Map))
          : null,
      columns: [
        TextColumn(
          'name',
          t.payrollItemName,
          width: ColumnWidth.large,
          formatter: (row) => '${(row as Map)['name'] ?? '-'}',
        ),
        TextColumn(
          'code',
          t.localeName == 'fa' ? 'کد' : 'Code',
          width: ColumnWidth.small,
          formatter: (row) => '${(row as Map)['code'] ?? '-'}',
        ),
        TextColumn(
          'item_kind',
          t.payrollItemKindLabel,
          width: ColumnWidth.medium,
          formatter: (row) => kindLabel?.call((row as Map)['item_kind'] as String?) ?? '${(row as Map)['item_kind'] ?? '-'}',
        ),
        TextColumn(
          'account_id',
          t.localeName == 'fa' ? 'حساب' : 'Account',
          width: ColumnWidth.small,
          sortable: false,
          formatter: (row) => (row as Map)['account_id'] != null ? '✓' : '-',
        ),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> employees({
    required AppLocalizations t,
    required bool isJalali,
    required bool canManage,
    required List<Map<String, dynamic>> departments,
    void Function(Map<String, dynamic> emp)? onEdit,
  }) {
    String deptName(Map<String, dynamic> emp) {
      final deptId = (emp['department_id'] as num?)?.toInt();
      if (deptId == null) return '-';
      for (final d in departments) {
        if ((d['id'] as num?)?.toInt() == deptId) {
          return '${d['name'] ?? d['code'] ?? '-'}';
        }
      }
      return '-';
    }

    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_payroll_employees',
      tableId: 'payroll_employees',
      title: t.payrollEmployeesTab,
      showSearch: true,
      showFilters: false,
      showPagination: true,
      defaultPageSize: 25,
      showExportButtons: false,
      showColumnSearch: false,
      enableGlobalSearch: true,
      searchFields: const ['employee_code', 'person_name', 'job_title'],
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      onRowTap: canManage && onEdit != null
          ? (item) => onEdit(Map<String, dynamic>.from(item as Map))
          : null,
      columns: [
        TextColumn(
          'employee_code',
          t.payrollEmployeeCode,
          width: ColumnWidth.small,
          formatter: (row) => '${(row as Map)['employee_code'] ?? '-'}',
        ),
        TextColumn(
          'person_name',
          t.payrollEmployeesTab,
          width: ColumnWidth.large,
          formatter: (row) {
            final m = row as Map<String, dynamic>;
            return '${m['person_name'] ?? m['employee_code'] ?? '-'}';
          },
        ),
        TextColumn(
          'job_title',
          t.payrollJobTitle,
          width: ColumnWidth.medium,
          formatter: (row) => '${(row as Map)['job_title'] ?? '-'}',
        ),
        TextColumn(
          'department',
          t.payrollDepartmentsTab,
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          formatter: (row) => deptName(row as Map<String, dynamic>),
        ),
        DateColumn(
          'hire_date',
          t.payrollHireDate,
          width: ColumnWidth.medium,
          formatter: (row) => _formatApiDate(row as Map<String, dynamic>, 'hire_date', isJalali),
        ),
        NumberColumn(
          'base_salary',
          t.payrollBaseSalary,
          width: ColumnWidth.medium,
          formatter: (row) {
            final v = (row as Map)['base_salary'];
            return v == null ? '-' : PayrollUi.formatMoney(v);
          },
        ),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> settingsItems({
    required AppLocalizations t,
    required bool canManage,
    String Function(String? kind)? kindLabel,
    void Function(Map<String, dynamic> item)? onEdit,
  }) {
    return items(
      t: t,
      canManage: canManage,
      kindLabel: kindLabel,
      onEdit: onEdit,
    );
  }

  static DataTableConfig<Map<String, dynamic>> itemSummaryReport({
    required AppLocalizations t,
    required String Function(dynamic) fmtMoney,
  }) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_payroll_report_items',
      tableId: 'payroll_report_items',
      title: t.payrollItemSummaryReport,
      showSearch: false,
      showFilters: false,
      showPagination: false,
      showExportButtons: false,
      showColumnSearch: false,
      enableSorting: false,
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      columns: [
        TextColumn(
          'item_name',
          t.payrollItemName,
          sortable: false,
          formatter: (row) {
            final m = row as Map<String, dynamic>;
            return '${m['item_name'] ?? m['item_code'] ?? '-'}';
          },
        ),
        TextColumn(
          'item_kind',
          t.payrollItemKindLabel,
          sortable: false,
          formatter: (row) => '${(row as Map)['item_kind'] ?? '-'}',
        ),
        NumberColumn(
          'total_amount',
          t.payrollGrossTotal,
          sortable: false,
          formatter: (row) => fmtMoney((row as Map)['total_amount']),
        ),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> employeeSummaryReport({
    required AppLocalizations t,
    required String Function(dynamic) fmtMoney,
  }) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_payroll_report_employees',
      tableId: 'payroll_report_employees',
      title: t.payrollEmployeeSummaryReport,
      showSearch: false,
      showFilters: false,
      showPagination: false,
      showExportButtons: false,
      showColumnSearch: false,
      enableSorting: false,
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      columns: [
        TextColumn(
          'employee_code',
          t.payrollEmployeeCode,
          sortable: false,
          formatter: (row) => '${(row as Map)['employee_code'] ?? '-'}',
        ),
        TextColumn(
          'person_name',
          t.payrollEmployeesTab,
          sortable: false,
          formatter: (row) => '${(row as Map)['person_name'] ?? '-'}',
        ),
        NumberColumn(
          'gross_total',
          t.payrollGrossTotal,
          sortable: false,
          formatter: (row) => fmtMoney((row as Map)['gross_total']),
        ),
        NumberColumn(
          'deduction_total',
          t.payrollDeductionTotal,
          sortable: false,
          formatter: (row) => fmtMoney((row as Map)['deduction_total']),
        ),
        NumberColumn(
          'net_total',
          t.payrollNetTotal,
          sortable: false,
          formatter: (row) => fmtMoney((row as Map)['net_total']),
        ),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> periodOverviewReport({
    required AppLocalizations t,
    required bool isJalali,
    required String Function(dynamic) fmtMoney,
  }) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_payroll_report_periods',
      tableId: 'payroll_report_periods',
      title: t.payrollPeriodOverviewReport,
      showSearch: false,
      showFilters: false,
      showPagination: false,
      showExportButtons: false,
      showColumnSearch: false,
      enableSorting: false,
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      columns: [
        TextColumn(
          'title',
          t.payrollPeriod,
          sortable: false,
          formatter: (row) => PayrollCalendarUtils.periodTitle(row as Map<String, dynamic>, isJalali),
        ),
        NumberColumn(
          'run_count',
          t.payrollRunsTab,
          sortable: false,
          formatter: (row) => PayrollUi.formatCount((row as Map)['run_count'] ?? 0),
        ),
        NumberColumn(
          'gross_total',
          t.payrollGrossTotal,
          sortable: false,
          formatter: (row) => fmtMoney((row as Map)['gross_total']),
        ),
        NumberColumn(
          'net_total',
          t.payrollNetTotal,
          sortable: false,
          formatter: (row) => fmtMoney((row as Map)['net_total']),
        ),
      ],
    );
  }
}
