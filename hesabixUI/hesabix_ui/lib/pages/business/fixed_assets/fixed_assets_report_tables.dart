import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/date_utils.dart';
import '../../../widgets/data_table/data_table_config.dart';
import 'fixed_assets_ui.dart';

class FixedAssetsReportTables {
  FixedAssetsReportTables._();

  static const bool _fit = true;
  static const bool _parentScroll = true;

  static String _date(Map<String, dynamic> row, String key, bool isJalali) {
    return HesabixDateUtils.formatApiDateForDisplay(row[key], isJalali, rawValue: row['${key}_raw']);
  }

  static String _money(dynamic row, String key) {
    return FixedAssetsUi.money((row as Map)[key]);
  }

  static DataTableConfig<Map<String, dynamic>> _base({
    required String tableId,
    required String title,
    required List<String> searchFields,
    required List<DataTableColumn> columns,
  }) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_$tableId',
      tableId: tableId,
      title: title,
      showSearch: true,
      showFilters: false,
      showPagination: true,
      defaultPageSize: 25,
      showExportButtons: false,
      showColumnSearch: false,
      enableGlobalSearch: true,
      searchFields: searchFields,
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      expandBodyHeightToFitRows: _fit,
      deferVerticalScrollToParent: _parentScroll,
      columns: columns,
    );
  }

  static DataTableConfig<Map<String, dynamic>> register({
    required AppLocalizations t,
    required bool isJalali,
  }) {
    return _base(
      tableId: 'fa_report_register',
      title: t.fixedAssetsReportRegister,
      searchFields: const ['code', 'name', 'serial_number', 'class_name'],
      columns: [
        TextColumn('code', t.fixedAssetsPlaquePrefix, width: ColumnWidth.small, formatter: (r) => '${(r as Map)['code'] ?? ''}'),
        TextColumn('name', t.fixedAssetsAssetName, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['name'] ?? ''}'),
        TextColumn('class_name', t.fixedAssetsClass, formatter: (r) => '${(r as Map)['class_name'] ?? ''}'),
        TextColumn('status', t.status, width: ColumnWidth.small, formatter: (r) => FixedAssetsUi.statusLabel(t, (r as Map)['status'])),
        DateColumn('acquisition_date', t.fixedAssetsAcquisitionDate, formatter: (r) => _date(r as Map<String, dynamic>, 'acquisition_date', isJalali)),
        NumberColumn('cost', t.fixedAssetsCost, formatter: (r) => _money(r, 'cost')),
        NumberColumn('accum_depreciation', t.fixedAssetsClassAccumAccount, formatter: (r) => _money(r, 'accum_depreciation')),
        NumberColumn('net_book_value', t.fixedAssetsNetBookValue, formatter: (r) => _money(r, 'net_book_value')),
        TextColumn('location_name', t.fixedAssetsLocation, formatter: (r) => '${(r as Map)['location_name'] ?? t.fixedAssetsNone}'),
        TextColumn('custodian_name', t.fixedAssetsCustodian, formatter: (r) => '${(r as Map)['custodian_name'] ?? t.fixedAssetsNone}'),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> classSummary({required AppLocalizations t}) {
    return _base(
      tableId: 'fa_report_classes',
      title: t.fixedAssetsReportClassSummary,
      searchFields: const ['class_code', 'class_name'],
      columns: [
        TextColumn('class_name', t.fixedAssetsClass, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['class_name'] ?? ''}'),
        NumberColumn('live_count', t.fixedAssetsReportLiveCount, formatter: (r) => '${(r as Map)['live_count'] ?? 0}'),
        NumberColumn('opening_nbv', t.fixedAssetsReportOpeningNbv, formatter: (r) => _money(r, 'opening_nbv')),
        NumberColumn('additions', t.fixedAssetsReportAdditions, formatter: (r) => _money(r, 'additions')),
        NumberColumn('major_repairs', t.fixedAssetsMajorRepair, formatter: (r) => _money(r, 'major_repairs')),
        NumberColumn('depreciation', t.fixedAssetsDepreciationTab, formatter: (r) => _money(r, 'depreciation')),
        NumberColumn('disposals_nbv', t.fixedAssetsReportDisposalsNbv, formatter: (r) => _money(r, 'disposals_nbv')),
        NumberColumn('closing_nbv', t.fixedAssetsReportClosingNbv, formatter: (r) => _money(r, 'closing_nbv')),
        NumberColumn('closing_cost', t.fixedAssetsCost, formatter: (r) => _money(r, 'closing_cost')),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> depreciation({
    required AppLocalizations t,
    required bool isJalali,
  }) {
    return _base(
      tableId: 'fa_report_depreciation',
      title: t.fixedAssetsReportDepreciation,
      searchFields: const ['code', 'name', 'class_name'],
      columns: [
        TextColumn('period', t.fixedAssetsPeriodMonth, formatter: (r) {
          final m = r as Map;
          return '${m['period_year']}/${m['period_month']}';
        }),
        TextColumn('code', t.fixedAssetsPlaquePrefix, width: ColumnWidth.small, formatter: (r) => '${(r as Map)['code'] ?? ''}'),
        TextColumn('name', t.fixedAssetsAssetName, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['name'] ?? ''}'),
        TextColumn('class_name', t.fixedAssetsClass, formatter: (r) => '${(r as Map)['class_name'] ?? ''}'),
        NumberColumn('amount', t.fixedAssetsReportDepreciationAmount, formatter: (r) => _money(r, 'amount')),
        NumberColumn('tax_preview_amount', t.fixedAssetsReportTaxPreview, formatter: (r) => _money(r, 'tax_preview_amount')),
        NumberColumn('book_value_after', t.fixedAssetsNetBookValue, formatter: (r) => _money(r, 'book_value_after')),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> acquisitions({
    required AppLocalizations t,
    required bool isJalali,
  }) {
    return _base(
      tableId: 'fa_report_acquisitions',
      title: t.fixedAssetsReportAcquisitions,
      searchFields: const ['code', 'name', 'class_name'],
      columns: [
        DateColumn('acquisition_date', t.fixedAssetsAcquisitionDate, formatter: (r) => _date(r as Map<String, dynamic>, 'acquisition_date', isJalali)),
        TextColumn('code', t.fixedAssetsPlaquePrefix, width: ColumnWidth.small, formatter: (r) => '${(r as Map)['code'] ?? ''}'),
        TextColumn('name', t.fixedAssetsAssetName, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['name'] ?? ''}'),
        TextColumn('class_name', t.fixedAssetsClass, formatter: (r) => '${(r as Map)['class_name'] ?? ''}'),
        TextColumn('acquisition_kind', t.fixedAssetsAcquisitionKind, formatter: (r) {
          final m = r as Map;
          final k = '${m['acquisition_kind']}';
          if (k == 'opening') return t.fixedAssetsKindOpening;
          if (m['invoice_id'] != null) return t.fixedAssetsFromInvoice;
          return t.fixedAssetsKindPurchase;
        }),
        NumberColumn('cost', t.fixedAssetsCost, formatter: (r) => _money(r, 'cost')),
        NumberColumn('vat_amount', t.fixedAssetsVat, formatter: (r) => _money(r, 'vat_amount')),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> disposals({
    required AppLocalizations t,
    required bool isJalali,
  }) {
    return _base(
      tableId: 'fa_report_disposals',
      title: t.fixedAssetsReportDisposals,
      searchFields: const ['code', 'name', 'class_name'],
      columns: [
        DateColumn('disposal_date', t.fixedAssetsDisposalDate, formatter: (r) => _date(r as Map<String, dynamic>, 'disposal_date', isJalali)),
        TextColumn('code', t.fixedAssetsPlaquePrefix, width: ColumnWidth.small, formatter: (r) => '${(r as Map)['code'] ?? ''}'),
        TextColumn('name', t.fixedAssetsAssetName, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['name'] ?? ''}'),
        TextColumn('disposal_kind', t.fixedAssetsDispose, formatter: (r) {
          final k = '${(r as Map)['disposal_kind']}';
          return k == 'scrap' ? t.fixedAssetsScrap : t.fixedAssetsSale;
        }),
        NumberColumn('cost', t.fixedAssetsCost, formatter: (r) => _money(r, 'cost')),
        NumberColumn('net_book_value', t.fixedAssetsNetBookValue, formatter: (r) => _money(r, 'net_book_value')),
        NumberColumn('proceeds', t.fixedAssetsProceeds, formatter: (r) => _money(r, 'proceeds')),
        NumberColumn('gain_loss', t.fixedAssetsReportGainLoss, formatter: (r) => _money(r, 'gain_loss')),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> idle({
    required AppLocalizations t,
    required bool isJalali,
  }) {
    return _base(
      tableId: 'fa_report_idle',
      title: t.fixedAssetsReportIdle,
      searchFields: const ['code', 'name', 'class_name'],
      columns: [
        TextColumn('code', t.fixedAssetsPlaquePrefix, width: ColumnWidth.small, formatter: (r) => '${(r as Map)['code'] ?? ''}'),
        TextColumn('name', t.fixedAssetsAssetName, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['name'] ?? ''}'),
        TextColumn('class_name', t.fixedAssetsClass, formatter: (r) => '${(r as Map)['class_name'] ?? ''}'),
        DateColumn('idle_from', t.fixedAssetsIdleFrom, formatter: (r) => _date(r as Map<String, dynamic>, 'idle_from', isJalali)),
        NumberColumn('net_book_value', t.fixedAssetsNetBookValue, formatter: (r) => _money(r, 'net_book_value')),
        TextColumn('tax_idle_factor', t.fixedAssetsReportTaxIdleFactor, formatter: (r) => '${(r as Map)['tax_idle_factor'] ?? ''}'),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> locations({required AppLocalizations t}) {
    return _base(
      tableId: 'fa_report_locations',
      title: t.fixedAssetsReportLocations,
      searchFields: const ['code', 'name', 'location_name', 'custodian_name'],
      columns: [
        TextColumn('location_name', t.fixedAssetsLocation, formatter: (r) => '${(r as Map)['location_name'] ?? t.fixedAssetsNone}'),
        TextColumn('custodian_name', t.fixedAssetsCustodian, formatter: (r) => '${(r as Map)['custodian_name'] ?? t.fixedAssetsNone}'),
        TextColumn('code', t.fixedAssetsPlaquePrefix, width: ColumnWidth.small, formatter: (r) => '${(r as Map)['code'] ?? ''}'),
        TextColumn('name', t.fixedAssetsAssetName, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['name'] ?? ''}'),
        TextColumn('serial_number', t.fixedAssetsSerial, formatter: (r) => '${(r as Map)['serial_number'] ?? ''}'),
        NumberColumn('net_book_value', t.fixedAssetsNetBookValue, formatter: (r) => _money(r, 'net_book_value')),
      ],
    );
  }

  static DataTableConfig<Map<String, dynamic>> expenditures({
    required AppLocalizations t,
    required bool isJalali,
  }) {
    return _base(
      tableId: 'fa_report_expenditures',
      title: t.fixedAssetsReportExpenditures,
      searchFields: const ['code', 'name', 'class_name', 'description'],
      columns: [
        DateColumn('expenditure_date', t.fixedAssetsEffectiveDate, formatter: (r) => _date(r as Map<String, dynamic>, 'expenditure_date', isJalali)),
        TextColumn('code', t.fixedAssetsPlaquePrefix, width: ColumnWidth.small, formatter: (r) => '${(r as Map)['code'] ?? ''}'),
        TextColumn('name', t.fixedAssetsAssetName, width: ColumnWidth.large, formatter: (r) => '${(r as Map)['name'] ?? ''}'),
        TextColumn('kind', t.fixedAssetsSubsequent, formatter: (r) {
          final k = '${(r as Map)['kind']}';
          return k == 'major' ? t.fixedAssetsMajorRepair : t.fixedAssetsRoutineRepair;
        }),
        NumberColumn('amount', t.fixedAssetsExpenditureAmount, formatter: (r) => _money(r, 'amount')),
        NumberColumn('vat_amount', t.fixedAssetsVat, formatter: (r) => _money(r, 'vat_amount')),
      ],
    );
  }
}
