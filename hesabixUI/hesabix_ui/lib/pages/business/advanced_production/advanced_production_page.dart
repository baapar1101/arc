import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../core/hesabix_back.dart';
import '../../../models/account_model.dart';
import '../../../services/account_service.dart';
import '../../../services/advanced_production_service.dart';
import '../../../services/business_dashboard_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/data_table/data_table_config.dart';
import '../../../widgets/data_table/data_table_widget.dart';
import '../../../widgets/date_input_field.dart';
import '../../../widgets/fx/report_currency_filter_dropdown.dart';
import '../../../widgets/invoice/account_combobox_widget.dart';
import '../../../widgets/invoice/product_combobox_widget.dart';
import '../../../widgets/invoice/warehouse_combobox_widget.dart';

class AdvancedProductionPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final String? initialReport;

  const AdvancedProductionPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    this.initialReport,
  });

  @override
  State<AdvancedProductionPage> createState() => _AdvancedProductionPageState();
}

class _AdvancedProductionPageState extends State<AdvancedProductionPage>
    with SingleTickerProviderStateMixin {
  final _svc = AdvancedProductionService();
  late final TabController _tabs;
  String _report = 'orders';
  String? _reportStatus;
  String _method = 'actual';
  String _ledgerMode = 'unchanged';
  int? _wipAccountId;
  int? _finishedAccountId;
  int? _scrapAccountId;
  int? _varianceAccountId;
  List<Account> _accounts = const [];
  DateTime? _from;
  DateTime? _to;
  int? _fiscalYearId;
  int? _warehouseId;
  int? _currencyId;
  List<Map<String, dynamic>> _fiscalYears = const [];
  bool _loading = true;
  bool _saving = false;
  String _recordKind = 'work_centers';
  String _maintenanceKind = 'breakdown';
  String _qcStage = 'final';
  String _qcResult = 'pass';
  DateTime? _recordDate;
  int? _workCenterId;
  int? _lineId;
  int? _shiftId;
  int? _toLineId;
  int? _machineId;
  int? _productId;
  int? _reportProductId;
  List<Map<String, dynamic>> _workCenters = const [];
  List<Map<String, dynamic>> _lines = const [];
  List<Map<String, dynamic>> _machines = const [];
  List<Map<String, dynamic>> _shifts = const [];
  List<Map<String, dynamic>> _scrapReasons = const [];
  String? _recyclableChoice;
  int? _reasonId;
  final _nominalCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _operatorCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _goodCtrl = TextEditingController();
  final _scrapCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _checkedCtrl = TextEditingController();
  final _rejectedCtrl = TextEditingController();
  final _lotCtrl = TextEditingController();
  final _fixedCostCtrl = TextEditingController();
  final _idleDaysCtrl = TextEditingController();
  Map<String, dynamic> _dashboard = const {};

  bool get _canManage =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('advanced_production', 'manage');

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport ?? 'orders';
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialReport == null ? 0 : 1,
    );
    widget.calendarController.addListener(_rebuild);
    _load();
    _loadFiscalYears();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final items = await BusinessDashboardService(ApiClient()).listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() => _fiscalYears = items);
    } catch (_) {}
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_rebuild);
    _tabs.dispose();
    _nominalCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _minutesCtrl.dispose();
    _operatorCtrl.dispose();
    _reasonCtrl.dispose();
    _goodCtrl.dispose();
    _scrapCtrl.dispose();
    _costCtrl.dispose();
    _checkedCtrl.dispose();
    _rejectedCtrl.dispose();
    _lotCtrl.dispose();
    _fixedCostCtrl.dispose();
    _idleDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await _svc.getSettings(businessId: widget.businessId);
      final dashboard = await _svc.getDashboard(businessId: widget.businessId);
      final centers = await _svc.listMaster(businessId: widget.businessId, kind: 'work_centers');
      final lines = await _svc.listMaster(businessId: widget.businessId, kind: 'lines');
      final machines = await _svc.listMaster(businessId: widget.businessId, kind: 'machines');
      final shifts = await _svc.listMaster(businessId: widget.businessId, kind: 'shifts');
      final scrapReasons = await _svc.listMaster(businessId: widget.businessId, kind: 'scrap_reasons');
      final accounts = await _loadAccounts();
      if (!mounted) return;
      setState(() {
        _method = (settings['costing_method'] ?? 'actual').toString();
        _ledgerMode = (settings['general_ledger_posting'] ?? 'unchanged').toString();
        _wipAccountId = _asId(settings['wip_account_id']);
        _finishedAccountId = _asId(settings['finished_goods_account_id']);
        _scrapAccountId = _asId(settings['scrap_expense_account_id']);
        _varianceAccountId = _asId(settings['cost_variance_account_id']);
        _accounts = accounts;
        _dashboard = dashboard;
        _workCenters = centers;
        _lines = lines;
        _machines = machines;
        _shifts = shifts;
        _scrapReasons = scrapReasons;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await _svc.updateSettings(
        businessId: widget.businessId,
        payload: {
          'costing_method': _method,
          'overhead_mode': 'bom_operations',
          'wip_account_id': _wipAccountId,
          'finished_goods_account_id': _finishedAccountId,
          'scrap_expense_account_id': _scrapAccountId,
          'cost_variance_account_id': _varianceAccountId,
        },
      );
      if (!mounted) return;
      setState(() {
        _method = (saved['costing_method'] ?? _method).toString();
        _ledgerMode = (saved['general_ledger_posting'] ?? _ledgerMode).toString();
        _saving = false;
      });
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).advancedProductionSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  int? _asId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Account? _accountById(int? id) {
    if (id == null) return null;
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  Future<List<Account>> _loadAccounts() async {
    try {
      final response = await AccountService().getAccounts(businessId: widget.businessId);
      final items = response['items'];
      if (items is! List) return const [];
      return items.map((item) => Account.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    } catch (_) {
      return const [];
    }
  }

  String _iso(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _codeLabel(AppLocalizations t, String? code) {
    switch (code) {
      case 'incoming':
        return t.advancedProductionStageIncoming;
      case 'in_process':
        return t.advancedProductionStageInProcess;
      case 'final':
        return t.advancedProductionStageFinal;
      case 'pass':
        return t.advancedProductionResultPass;
      case 'fail':
        return t.advancedProductionResultFail;
      case 'breakdown':
        return t.advancedProductionMaintenanceBreakdown;
      case 'preventive':
        return t.advancedProductionMaintenancePreventive;
      case 'actual':
        return t.advancedProductionCostingActual;
      case 'standard':
        return t.advancedProductionCostingStandard;
      case 'material':
        return t.advancedProductionRoleMaterial;
      case 'output':
        return t.advancedProductionRoleOutput;
      case 'true':
        return t.advancedProductionRecyclableYes;
      case 'false':
        return t.advancedProductionRecyclableNo;
      default:
        return _statusLabel(t, code);
    }
  }

  String _statusLabel(AppLocalizations t, String? status) {
    switch (status) {
      case 'draft':
        return t.advancedProductionStatusDraft;
      case 'released':
        return t.advancedProductionStatusReleased;
      case 'in_progress':
        return t.advancedProductionStatusInProgress;
      case 'completed':
        return t.advancedProductionStatusCompleted;
      case 'cancelled':
        return t.advancedProductionStatusCancelled;
      default:
        return status ?? '';
    }
  }

  String _methodLabel(AppLocalizations t, String method) {
    switch (method) {
      case 'standard':
        return t.advancedProductionCostingStandard;
      case 'weighted_average':
        return t.advancedProductionCostingAverage;
      default:
        return t.advancedProductionCostingActual;
    }
  }

  String _reportTitle(AppLocalizations t, String key) {
    switch (key) {
      case 'progress':
        return t.advancedProductionReportProgress;
      case 'overdue':
        return t.advancedProductionReportOverdue;
      case 'schedule':
        return t.advancedProductionReportSchedule;
      case 'plan_achievement':
        return t.advancedProductionReportPlan;
      case 'open_orders':
        return t.advancedProductionReportOpen;
      case 'cycle_time':
        return t.advancedProductionReportCycle;
      case 'order_costing':
        return t.advancedProductionReportCost;
      case 'material_requirements':
        return t.advancedProductionReportMaterials;
      case 'material_shortage':
        return t.advancedProductionReportShortage;
      case 'material_variance':
        return t.advancedProductionReportVariance;
      case 'scrap':
        return t.advancedProductionReportScrap;
      case 'scrap_by_product':
        return t.advancedProductionReportScrapProduct;
      case 'scrap_rate':
        return t.advancedProductionReportScrapRate;
      case 'finished_goods':
        return t.advancedProductionReportFinished;
      case 'finished_by_product':
        return t.advancedProductionReportFinishedProduct;
      case 'unplanned_production':
        return t.advancedProductionReportUnplanned;
      case 'oee':
        return t.advancedProductionReportOee;
      case 'downtime':
        return t.advancedProductionReportDowntime;
      case 'inspections':
        return t.advancedProductionReportQc;
      case 'maintenance':
        return t.advancedProductionReportMaintenance;
      case 'reliability':
        return t.advancedProductionReportReliability;
      case 'product_profit':
        return t.advancedProductionReportProfit;
      case 'cost_share':
        return t.advancedProductionReportCostShare;
      case 'qc_pass_rate':
        return t.advancedProductionReportPassRate;
      case 'production_daily':
        return t.advancedProductionReportDaily;
      case 'line_output':
        return t.advancedProductionReportLine;
      case 'shift_output':
        return t.advancedProductionReportShift;
      case 'wip_age':
        return t.advancedProductionReportWipAge;
      case 'work_center_output':
        return t.advancedProductionReportCenter;
      case 'capacity_usage':
        return t.advancedProductionReportCapacity;
      case 'qc_rejects':
        return t.advancedProductionReportRejects;
      case 'period_cost':
        return t.advancedProductionReportPeriodCost;
      case 'operator_output':
        return t.advancedProductionReportOperator;
      case 'setup_time':
        return t.advancedProductionReportSetup;
      case 'lot_trace':
        return t.advancedProductionReportLot;
      case 'yield_rate':
        return t.advancedProductionReportYield;
      case 'unused_capacity':
        return t.advancedProductionReportUnused;
      case 'break_even':
        return t.advancedProductionReportBreakEven;
      case 'monthly_comparison':
        return t.advancedProductionReportMonthly;
      case 'material_flow':
        return t.advancedProductionReportFlow;
      case 'production_by_lot':
        return t.advancedProductionReportByLot;
      case 'conversion_efficiency':
        return t.advancedProductionReportConversion;
      case 'low_yield':
        return t.advancedProductionReportLowYield;
      case 'line_maintenance_cost':
        return t.advancedProductionReportLineCost;
      case 'material_price_variance':
        return t.advancedProductionReportPriceVariance;
      case 'product_cost':
        return t.advancedProductionReportProductCost;
      case 'wip_balance':
        return t.advancedProductionReportWip;
      case 'operation_variance':
        return t.advancedProductionReportOperationVariance;
      case 'scrap_by_reason':
        return t.advancedProductionReportScrapReason;
      case 'recyclable_scrap':
        return t.advancedProductionReportRecyclable;
      case 'nonrecyclable_scrap':
        return t.advancedProductionReportNonrecyclable;
      case 'qc_causes':
        return t.advancedProductionReportQcCause;
      case 'machine_output':
        return t.advancedProductionReportMachine;
      case 'downtime_cost':
        return t.advancedProductionReportDowntimeCost;
      case 'held_orders':
        return t.advancedProductionReportHeld;
      case 'material_consumption':
        return t.advancedProductionReportConsumption;
      case 'capacity_required':
        return t.advancedProductionReportCapacityNeed;
      case 'wip_count':
        return t.advancedProductionReportWipCount;
      case 'rework':
        return t.advancedProductionReportRework;
      case 'line_returns':
        return t.advancedProductionReportLineReturn;
      case 'wip_by_center':
        return t.advancedProductionReportWipCenter;
      case 'material_scrap':
        return t.advancedProductionReportMaterialScrap;
      case 'idle_materials':
        return t.advancedProductionReportIdle;
      case 'stage_transfers':
        return t.advancedProductionReportTransfer;
      case 'wage_variance':
        return t.advancedProductionReportWage;
      default:
        return t.advancedProductionReportOrders;
    }
  }

  List<DataTableColumn> _columns(AppLocalizations t) {
    String cell(dynamic item, String key) =>
        item is Map ? item[key]?.toString() ?? '' : '';
    final common = <DataTableColumn>[
      TextColumn(
        'code',
        t.advancedProductionColOrder,
        formatter: (item) {
          final code = cell(item, 'code');
          return code.isEmpty ? cell(item, 'order_code') : code;
        },
      ),
      TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
    ];
    switch (_report) {
      case 'material_requirements':
      case 'material_shortage':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('warehouse_name', t.advancedProductionColWarehouse, formatter: (item) => cell(item, 'warehouse_name')),
          TextColumn('required_quantity', t.advancedProductionColRequired, formatter: (item) => cell(item, 'required_quantity')),
          TextColumn('free_quantity', t.advancedProductionColFree, formatter: (item) => cell(item, 'free_quantity')),
          TextColumn('shortage_quantity', t.advancedProductionColShortage, formatter: (item) => cell(item, 'shortage_quantity')),
        ];
      case 'scrap':
      case 'finished_goods':
      case 'unplanned_production':
        return [
          TextColumn('document_date', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'document_date')),
          TextColumn('document_code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'document_code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'quantity')),
          TextColumn('amount', t.advancedProductionColActual, formatter: (item) => cell(item, 'amount')),
        ];
      case 'scrap_by_product':
      case 'finished_by_product':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'quantity')),
          TextColumn('amount', t.advancedProductionColActual, formatter: (item) => cell(item, 'amount')),
        ];
      case 'scrap_rate':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity', t.advancedProductionReportScrap, formatter: (item) => cell(item, 'quantity')),
          TextColumn('produced_quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'produced_quantity')),
          TextColumn('scrap_percent', t.advancedProductionReportScrapRate, formatter: (item) => cell(item, 'scrap_percent')),
        ];
      case 'product_profit':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('sales_amount', t.advancedProductionColActual, formatter: (item) => cell(item, 'sales_amount')),
          TextColumn('production_cost', t.advancedProductionColStandard, formatter: (item) => cell(item, 'production_cost')),
          TextColumn('margin', t.advancedProductionReportProfit, formatter: (item) => cell(item, 'margin')),
          TextColumn('margin_percent', t.advancedProductionColProgress, formatter: (item) => cell(item, 'margin_percent')),
        ];
      case 'material_variance':
        return [
          TextColumn('order_code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'order_code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('planned_quantity', t.advancedProductionColPlanned, formatter: (item) => cell(item, 'planned_quantity')),
          TextColumn('issued_quantity', t.advancedProductionColIssued, formatter: (item) => cell(item, 'issued_quantity')),
          TextColumn('quantity_variance', t.advancedProductionColVarianceQty, formatter: (item) => cell(item, 'quantity_variance')),
          TextColumn('standard_total', t.advancedProductionColStandard, formatter: (item) => cell(item, 'standard_total')),
          TextColumn('actual_total', t.advancedProductionColActual, formatter: (item) => cell(item, 'actual_total')),
          TextColumn('cost_variance', t.advancedProductionColVarianceCost, formatter: (item) => cell(item, 'cost_variance')),
        ];
      case 'yield_rate':
        return [
          TextColumn('line_name', t.advancedProductionLine, formatter: (item) => cell(item, 'line_name')),
          TextColumn('quantity_good', t.advancedProductionGoodQuantity, formatter: (item) => cell(item, 'quantity_good')),
          TextColumn('quantity_scrap', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity_scrap')),
          TextColumn('yield_percent', t.advancedProductionReportYield, formatter: (item) => cell(item, 'yield_percent')),
        ];
      case 'unused_capacity':
        return [
          TextColumn('line_name', t.advancedProductionLine, formatter: (item) => cell(item, 'line_name')),
          TextColumn('ideal_quantity', t.advancedProductionReportCapacity, formatter: (item) => cell(item, 'ideal_quantity')),
          TextColumn('unused_quantity', t.advancedProductionReportUnused, formatter: (item) => cell(item, 'unused_quantity')),
          TextColumn('utilization_percent', t.advancedProductionColProgress, formatter: (item) => cell(item, 'utilization_percent')),
        ];
      case 'break_even':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('fixed_cost', t.advancedProductionFixedCost, formatter: (item) => cell(item, 'fixed_cost')),
          TextColumn('unit_cost', t.advancedProductionUnitCost, formatter: (item) => cell(item, 'unit_cost')),
          TextColumn('sales_amount', t.advancedProductionColActual, formatter: (item) => cell(item, 'sales_amount')),
          TextColumn('break_even_quantity', t.advancedProductionReportBreakEven, formatter: (item) => cell(item, 'break_even_quantity')),
        ];
      case 'order_costing':
        return [
          ...common,
          TextColumn('standard_materials', t.advancedProductionStandardMaterials, formatter: (item) => cell(item, 'standard_materials')),
          TextColumn('actual_materials', t.advancedProductionActualMaterials, formatter: (item) => cell(item, 'actual_materials')),
          TextColumn('standard_operations', t.advancedProductionStandardOperations, formatter: (item) => cell(item, 'standard_operations')),
          TextColumn('actual_operations', t.advancedProductionActualOperations, formatter: (item) => cell(item, 'actual_operations')),
          TextColumn('valued_total', t.advancedProductionColValued, formatter: (item) => cell(item, 'valued_total')),
          TextColumn('unit_cost', t.advancedProductionUnitCost, formatter: (item) => cell(item, 'unit_cost')),
          TextColumn('cost_variance', t.advancedProductionColVarianceCost, formatter: (item) => cell(item, 'cost_variance')),
        ];
      case 'production_daily':
        return [
          TextColumn('document_date', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'document_date')),
          TextColumn('quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'quantity')),
        ];
      case 'monthly_comparison':
        return [
          TextColumn('period', t.advancedProductionPeriod, formatter: (item) => cell(item, 'period')),
          TextColumn('quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'quantity')),
          TextColumn('amount', t.advancedProductionColActual, formatter: (item) => cell(item, 'amount')),
        ];
      case 'material_flow':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('purchased_quantity', t.advancedProductionPurchased, formatter: (item) => cell(item, 'purchased_quantity')),
          TextColumn('returned_quantity', t.advancedProductionReturned, formatter: (item) => cell(item, 'returned_quantity')),
          TextColumn('consumed_quantity', t.advancedProductionConsumed, formatter: (item) => cell(item, 'consumed_quantity')),
          TextColumn('scrapped_quantity', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'scrapped_quantity')),
          TextColumn('period_net_quantity', t.advancedProductionPeriodNet, formatter: (item) => cell(item, 'period_net_quantity')),
        ];
      case 'production_by_lot':
        return [
          TextColumn('lot_code', t.advancedProductionLotCode, formatter: (item) => cell(item, 'lot_code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('produced_quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'produced_quantity')),
          TextColumn('scrap_quantity', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'scrap_quantity')),
          TextColumn('manufacturing_date', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'manufacturing_date')),
        ];
      case 'conversion_efficiency':
        return [
          TextColumn('code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('material_name', t.advancedProductionReportMaterials, formatter: (item) => cell(item, 'material_name')),
          TextColumn('issued_quantity', t.advancedProductionColIssued, formatter: (item) => cell(item, 'issued_quantity')),
          TextColumn('produced_quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'produced_quantity')),
          TextColumn('conversion_percent', t.advancedProductionReportConversion, formatter: (item) => cell(item, 'conversion_percent')),
        ];
      case 'low_yield':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity_good', t.advancedProductionGoodQuantity, formatter: (item) => cell(item, 'quantity_good')),
          TextColumn('quantity_scrap', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity_scrap')),
          TextColumn('yield_percent', t.advancedProductionReportYield, formatter: (item) => cell(item, 'yield_percent')),
        ];
      case 'line_maintenance_cost':
        return [
          TextColumn('line_name', t.advancedProductionLine, formatter: (item) => cell(item, 'line_name')),
          TextColumn('record_count', t.advancedProductionColOrder, formatter: (item) => cell(item, 'record_count')),
          TextColumn('repair_minutes', t.advancedProductionMinutes, formatter: (item) => cell(item, 'repair_minutes')),
          TextColumn('cost_amount', t.advancedProductionCostAmount, formatter: (item) => cell(item, 'cost_amount')),
        ];
      case 'material_price_variance':
        return [
          TextColumn('order_code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'order_code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('issued_quantity', t.advancedProductionColIssued, formatter: (item) => cell(item, 'issued_quantity')),
          TextColumn('usage_variance', t.advancedProductionUsageVariance, formatter: (item) => cell(item, 'usage_variance')),
          TextColumn('price_variance', t.advancedProductionPriceVariance, formatter: (item) => cell(item, 'price_variance')),
        ];
      case 'product_cost':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('produced_quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'produced_quantity')),
          TextColumn('valued_total', t.advancedProductionColValued, formatter: (item) => cell(item, 'valued_total')),
          TextColumn('unit_cost', t.advancedProductionUnitCost, formatter: (item) => cell(item, 'unit_cost')),
        ];
      case 'wip_balance':
        return [
          TextColumn('code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('actual_total', t.advancedProductionColActual, formatter: (item) => cell(item, 'actual_total')),
          TextColumn('transferred_amount', t.advancedProductionTransferred, formatter: (item) => cell(item, 'transferred_amount')),
          TextColumn('remaining_wip', t.advancedProductionRemainingWip, formatter: (item) => cell(item, 'remaining_wip')),
        ];
      case 'operation_variance':
        return [
          TextColumn('code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('standard_operations', t.advancedProductionColStandard, formatter: (item) => cell(item, 'standard_operations')),
          TextColumn('actual_operations', t.advancedProductionColActual, formatter: (item) => cell(item, 'actual_operations')),
          TextColumn('operation_variance', t.advancedProductionColVarianceCost, formatter: (item) => cell(item, 'operation_variance')),
        ];
      case 'scrap_by_reason':
      case 'recyclable_scrap':
      case 'nonrecyclable_scrap':
        return [
          TextColumn('reason_name', t.advancedProductionScrapReason, formatter: (item) => cell(item, 'reason_name')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('recyclable', t.advancedProductionRecyclable, formatter: (item) => _codeLabel(t, cell(item, 'recyclable'))),
          TextColumn('quantity', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity')),
        ];
      case 'qc_causes':
        return [
          TextColumn('reason_code', t.advancedProductionReason, formatter: (item) => cell(item, 'reason_code')),
          TextColumn('inspection_count', t.advancedProductionColOrder, formatter: (item) => cell(item, 'inspection_count')),
          TextColumn('quantity_rejected', t.advancedProductionRejectedQuantity, formatter: (item) => cell(item, 'quantity_rejected')),
        ];
      case 'machine_output':
        return [
          TextColumn('machine_name', t.advancedProductionMachine, formatter: (item) => cell(item, 'machine_name')),
          TextColumn('quantity_good', t.advancedProductionGoodQuantity, formatter: (item) => cell(item, 'quantity_good')),
          TextColumn('quantity_scrap', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity_scrap')),
          TextColumn('run_minutes', t.advancedProductionMinutes, formatter: (item) => cell(item, 'run_minutes')),
          TextColumn('good_per_hour', t.advancedProductionReportMachine, formatter: (item) => cell(item, 'good_per_hour')),
        ];
      case 'downtime_cost':
        return [
          TextColumn('line_name', t.advancedProductionLine, formatter: (item) => cell(item, 'line_name')),
          TextColumn('minutes', t.advancedProductionMinutes, formatter: (item) => cell(item, 'minutes')),
          TextColumn('cost_amount', t.advancedProductionCostAmount, formatter: (item) => cell(item, 'cost_amount')),
        ];
      case 'held_orders':
        return [
          TextColumn('code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('held_on', t.advancedProductionColStart, formatter: (item) => _displayDate(item, 'held_on')),
          TextColumn('reason', t.advancedProductionHoldReason, formatter: (item) => cell(item, 'reason')),
        ];
      case 'material_consumption':
        return [
          TextColumn('document_date', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'document_date')),
          TextColumn('document_code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'document_code')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity', t.advancedProductionColIssued, formatter: (item) => cell(item, 'quantity')),
          TextColumn('production_order_id', t.advancedProductionOrderId, formatter: (item) => cell(item, 'production_order_id')),
        ];
      case 'capacity_required':
        return [
          TextColumn('code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'code')),
          TextColumn('line_name', t.advancedProductionLine, formatter: (item) => cell(item, 'line_name')),
          TextColumn('remaining_quantity', t.advancedProductionColRemaining, formatter: (item) => cell(item, 'remaining_quantity')),
          TextColumn('required_hours', t.advancedProductionRequiredHours, formatter: (item) => cell(item, 'required_hours')),
        ];
      case 'wip_count':
        return [
          TextColumn('code', t.advancedProductionColOrder, formatter: (item) => cell(item, 'code')),
          TextColumn('counted_on', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'counted_on')),
          TextColumn('counted_quantity', t.advancedProductionCountedQuantity, formatter: (item) => cell(item, 'counted_quantity')),
          TextColumn('book_remaining', t.advancedProductionColRemaining, formatter: (item) => cell(item, 'book_remaining')),
          TextColumn('quantity_variance', t.advancedProductionColVarianceQty, formatter: (item) => cell(item, 'quantity_variance')),
        ];
      case 'wip_by_center':
        return [
          TextColumn('work_center_name', t.advancedProductionReportCenter, formatter: (item) => cell(item, 'work_center_name')),
          TextColumn('order_count', t.advancedProductionColOrder, formatter: (item) => cell(item, 'order_count')),
          TextColumn('remaining_wip', t.advancedProductionRemainingWip, formatter: (item) => cell(item, 'remaining_wip')),
        ];
      case 'material_scrap':
        return [
          TextColumn('document_date', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'document_date')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity')),
          TextColumn('amount', t.advancedProductionColActual, formatter: (item) => cell(item, 'amount')),
        ];
      case 'idle_materials':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('current_stock', t.advancedProductionCurrentStock, formatter: (item) => cell(item, 'current_stock')),
          TextColumn('days_without_movement', t.advancedProductionIdleDays, formatter: (item) => cell(item, 'days_without_movement')),
        ];
      case 'wage_variance':
        return [
          TextColumn('worked_on', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'worked_on')),
          TextColumn('actual_hours', t.advancedProductionActualHours, formatter: (item) => cell(item, 'actual_hours')),
          TextColumn('standard_hours', t.advancedProductionStandardHours, formatter: (item) => cell(item, 'standard_hours')),
          TextColumn('rate_variance', t.advancedProductionPriceVariance, formatter: (item) => cell(item, 'rate_variance')),
          TextColumn('efficiency_variance', t.advancedProductionUsageVariance, formatter: (item) => cell(item, 'efficiency_variance')),
        ];
      case 'stage_transfers':
        return [
          TextColumn('transferred_on', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'transferred_on')),
          TextColumn('from_line_name', t.advancedProductionFromLine, formatter: (item) => cell(item, 'from_line_name')),
          TextColumn('to_line_name', t.advancedProductionToLine, formatter: (item) => cell(item, 'to_line_name')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity')),
        ];
      case 'rework':
      case 'line_returns':
        return [
          TextColumn('occurred_on', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'occurred_on')),
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('quantity', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity')),
        ];
      case 'oee':
      case 'line_output':
      case 'shift_output':
      case 'work_center_output':
      case 'capacity_usage':
      case 'operator_output':
        return [
          TextColumn('line_name', t.advancedProductionLine, formatter: (item) => cell(item, 'line_name')),
          TextColumn('shift_name', t.advancedProductionReportShift, formatter: (item) => cell(item, 'shift_name')),
          TextColumn('work_center_name', t.advancedProductionReportCenter, formatter: (item) => cell(item, 'work_center_name')),
          TextColumn('operator_name', t.advancedProductionOperator, formatter: (item) => cell(item, 'operator_name')),
          TextColumn('quantity_good', t.advancedProductionGoodQuantity, formatter: (item) => cell(item, 'quantity_good')),
          TextColumn('quantity_scrap', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'quantity_scrap')),
          TextColumn('run_minutes', t.advancedProductionMinutes, formatter: (item) => cell(item, 'run_minutes')),
          TextColumn('oee', t.advancedProductionReportOee, formatter: (item) => cell(item, 'oee')),
          TextColumn('utilization_percent', t.advancedProductionColProgress, formatter: (item) => cell(item, 'utilization_percent')),
        ];
      case 'downtime':
      case 'setup_time':
        return [
          TextColumn('started_on', t.advancedProductionColStart, formatter: (item) => _displayDate(item, 'started_on')),
          TextColumn('minutes', t.advancedProductionMinutes, formatter: (item) => cell(item, 'minutes')),
          TextColumn('reason_code', t.advancedProductionReason, formatter: (item) => cell(item, 'reason_code')),
        ];
      case 'inspections':
      case 'qc_rejects':
        return [
          TextColumn('inspected_on', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'inspected_on')),
          TextColumn('stage', t.advancedProductionStage, formatter: (item) => _codeLabel(t, cell(item, 'stage'))),
          TextColumn('result', t.advancedProductionResult, formatter: (item) => _codeLabel(t, cell(item, 'result'))),
          TextColumn('quantity_checked', t.advancedProductionCheckedQuantity, formatter: (item) => cell(item, 'quantity_checked')),
          TextColumn('quantity_rejected', t.advancedProductionRejectedQuantity, formatter: (item) => cell(item, 'quantity_rejected')),
        ];
      case 'qc_pass_rate':
        return [
          TextColumn('stage', t.advancedProductionStage, formatter: (item) => _codeLabel(t, cell(item, 'stage'))),
          TextColumn('quantity_checked', t.advancedProductionCheckedQuantity, formatter: (item) => cell(item, 'quantity_checked')),
          TextColumn('quantity_rejected', t.advancedProductionRejectedQuantity, formatter: (item) => cell(item, 'quantity_rejected')),
          TextColumn('acceptance_percent', t.advancedProductionReportPassRate, formatter: (item) => cell(item, 'acceptance_percent')),
        ];
      case 'maintenance':
        return [
          TextColumn('opened_on', t.advancedProductionColStart, formatter: (item) => _displayDate(item, 'opened_on')),
          TextColumn('maintenance_kind', t.advancedProductionMaintenance, formatter: (item) => _codeLabel(t, cell(item, 'maintenance_kind'))),
          TextColumn('repair_minutes', t.advancedProductionMinutes, formatter: (item) => cell(item, 'repair_minutes')),
          TextColumn('cost_amount', t.advancedProductionCostAmount, formatter: (item) => cell(item, 'cost_amount')),
          TextColumn('spare_quantity', t.advancedProductionScrapQuantity, formatter: (item) => cell(item, 'spare_quantity')),
        ];
      case 'reliability':
        return [
          TextColumn('machine_name', t.advancedProductionMachine, formatter: (item) => cell(item, 'machine_name')),
          TextColumn('breakdown_count', t.advancedProductionReportMaintenance, formatter: (item) => cell(item, 'breakdown_count')),
          TextColumn('mtbf_days', t.advancedProductionReportReliability, formatter: (item) => cell(item, 'mtbf_days')),
          TextColumn('mttr_minutes', t.advancedProductionMinutes, formatter: (item) => cell(item, 'mttr_minutes')),
          TextColumn('cost_amount', t.advancedProductionCostAmount, formatter: (item) => cell(item, 'cost_amount')),
        ];
      case 'cost_share':
        return [
          TextColumn('basis', t.advancedProductionColStandard, formatter: (item) => _codeLabel(t, cell(item, 'basis'))),
          TextColumn('materials', t.advancedProductionReportMaterials, formatter: (item) => cell(item, 'materials')),
          TextColumn('operations', t.advancedProductionReportCost, formatter: (item) => cell(item, 'operations')),
          TextColumn('materials_percent', t.advancedProductionColProgress, formatter: (item) => cell(item, 'materials_percent')),
        ];
      case 'period_cost':
        return [
          TextColumn('product_name', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_name')),
          TextColumn('materials', t.advancedProductionReportMaterials, formatter: (item) => cell(item, 'materials')),
          TextColumn('operations', t.advancedProductionReportCost, formatter: (item) => cell(item, 'operations')),
          TextColumn('total', t.advancedProductionColActual, formatter: (item) => cell(item, 'total')),
        ];
      case 'wip_age':
        return [
          ...common,
          TextColumn('age_days', t.advancedProductionAgeDays, formatter: (item) => cell(item, 'age_days')),
          TextColumn('actual_total', t.advancedProductionColActual, formatter: (item) => cell(item, 'actual_total')),
          TextColumn('started_at', t.advancedProductionColStart, formatter: (item) => _displayDate(item, 'started_at')),
        ];
      case 'lot_trace':
        return [
          TextColumn('lot_code', t.advancedProductionLotCode, formatter: (item) => cell(item, 'lot_code')),
          TextColumn('production_order_id', t.advancedProductionColOrder, formatter: (item) => cell(item, 'production_order_id')),
          TextColumn('product_id', t.advancedProductionColProduct, formatter: (item) => cell(item, 'product_id')),
          TextColumn('role', t.advancedProductionResult, formatter: (item) => _codeLabel(t, cell(item, 'role'))),
        ];
      case 'cycle_time':
        return [
          ...common,
          TextColumn('cycle_hours', t.advancedProductionColCycle, formatter: (item) => cell(item, 'cycle_hours')),
          TextColumn('started_at', t.advancedProductionColStart, formatter: (item) => _displayDate(item, 'started_at')),
          TextColumn('completed_at', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'completed_at')),
        ];
      default:
        return [
          ...common,
          TextColumn('status', t.advancedProductionColStatus, formatter: (item) => _statusLabel(t, cell(item, 'status'))),
          TextColumn('planned_quantity', t.advancedProductionColPlanned, formatter: (item) => cell(item, 'planned_quantity')),
          TextColumn('produced_quantity', t.advancedProductionColProduced, formatter: (item) => cell(item, 'produced_quantity')),
          TextColumn('remaining_quantity', t.advancedProductionColRemaining, formatter: (item) => cell(item, 'remaining_quantity')),
          TextColumn('progress_percent', t.advancedProductionColProgress, formatter: (item) => cell(item, 'progress_percent')),
          TextColumn('due_date', t.advancedProductionColDue, formatter: (item) => _displayDate(item, 'due_date')),
        ];
    }
  }

  String _displayDate(dynamic item, String key) {
    final raw = item is Map ? item[key]?.toString() : null;
    if (raw == null || raw.isEmpty) return '';
    if (raw.contains('T')) {
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return raw;
      return HesabixDateUtils.formatForDisplay(parsed, widget.calendarController.isJalali);
    }
    return HesabixDateUtils.formatApiDateForDisplay(
      raw,
      widget.calendarController.isJalali,
      fallback: raw,
    );
  }

  Map<String, dynamic> _reportParams() {
    return {
      if (_from != null) 'date_from': _iso(_from),
      if (_to != null) 'date_to': _iso(_to),
      if (_report == 'break_even' && _reportProductId != null) 'product_id': _reportProductId,
      if (_report == 'break_even' && _fixedCostCtrl.text.trim().isNotEmpty) 'fixed_cost': _fixedCostCtrl.text.trim(),
      if (_report == 'lot_trace' && _lotCtrl.text.trim().isNotEmpty) 'lot_code': _lotCtrl.text.trim(),
      if (_report == 'idle_materials' && _idleDaysCtrl.text.trim().isNotEmpty) 'days_without_movement': int.tryParse(_idleDaysCtrl.text.trim()),
      if (_reportStatus != null) 'status': _reportStatus,
      if (_fiscalYearId != null) 'fiscal_year_id': _fiscalYearId,
      if (_warehouseId != null) 'warehouse_id': _warehouseId,
      if (_currencyId != null && _documentReport) 'currency_id': _currencyId,
    };
  }

  bool get _documentReport => const {
        'scrap',
        'scrap_by_product',
        'scrap_rate',
        'finished_goods',
        'finished_by_product',
        'unplanned_production',
        'material_consumption',
        'material_scrap',
        'production_daily',
        'monthly_comparison',
        'product_profit',
      }.contains(_report);

  DataTableConfig<Map<String, dynamic>> _table(AppLocalizations t) {
    final base = '/api/v1/advanced-production/business/${widget.businessId}/reports/$_report';
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: base,
      businessId: widget.businessId,
      title: _reportTitle(t, _report),
      columns: _columns(t),
      pageSizeQueryParam: 'limit',
      additionalParams: _reportParams(),
      showExportButtons: true,
      excelEndpoint: '$base/export/excel',
      pdfEndpoint: '$base/export/pdf',
      getExportParams: _reportParams,
      onRowTap: (item) {
        final documentId = item['document_id'];
        if (documentId != null) {
          context.go(context.businessPanelUrl(widget.businessId, 'invoice/$documentId/edit'));
          return;
        }
        final orderId = item['production_order_id'];
        if (orderId == null) return;
        context.go(context.businessPanelUrl(widget.businessId, 'production-orders/$orderId'));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final reports = <String>[
      'orders',
      'progress',
      'overdue',
      'schedule',
      'plan_achievement',
      'open_orders',
      'cycle_time',
      'order_costing',
      'material_requirements',
      'material_shortage',
      'material_variance',
      'scrap',
      'scrap_by_product',
      'scrap_rate',
      'finished_goods',
      'finished_by_product',
      'unplanned_production',
      'oee',
      'downtime',
      'inspections',
      'maintenance',
      'reliability',
      'product_profit',
      'cost_share',
      'qc_pass_rate',
      'production_daily',
      'line_output',
      'shift_output',
      'wip_age',
      'work_center_output',
      'capacity_usage',
      'qc_rejects',
      'period_cost',
      'operator_output',
      'setup_time',
      'lot_trace',
      'yield_rate',
      'unused_capacity',
      'break_even',
      'monthly_comparison',
      'material_flow',
      'production_by_lot',
      'conversion_efficiency',
      'low_yield',
      'line_maintenance_cost',
      'material_price_variance',
      'product_cost',
      'wip_balance',
      'operation_variance',
      'scrap_by_reason',
      'recyclable_scrap',
      'nonrecyclable_scrap',
      'qc_causes',
      'machine_output',
      'downtime_cost',
      'held_orders',
      'material_consumption',
      'capacity_required',
      'wip_count',
      'rework',
      'line_returns',
      'wip_by_center',
      'material_scrap',
      'idle_materials',
      'stage_transfers',
      'wage_variance',
    ];
    return Scaffold(
      appBar: AppBar(
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        title: Text(t.advancedProductionTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: t.advancedProductionDashboard),
            Tab(text: t.advancedProductionReports),
            Tab(text: t.advancedProductionSettings),
            Tab(text: t.advancedProductionRecords),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _dashboardView(t),
                _reportsView(t, reports),
                _settingsView(t),
                _recordsView(t),
              ],
            ),
    );
  }

  void _openReport(String report, {bool today = false, String? day, String? from, String? to, String? status}) {
    DateTime? parsed;
    final source = day ?? from ?? (today ? _dashboard['as_of_date']?.toString() : null);
    if (source != null && source.isNotEmpty) {
      parsed = HesabixDateUtils.parseApiDate(source);
    }
    if (today && parsed == null) {
      final now = DateTime.now();
      parsed = DateTime(now.year, now.month, now.day);
    }
    if (parsed != null) {
      parsed = DateTime(parsed.year, parsed.month, parsed.day);
    }
    final end = to == null ? parsed : HesabixDateUtils.parseApiDate(to);
    setState(() {
      _report = report;
      _reportStatus = status;
      _from = parsed;
      _to = end == null ? parsed : DateTime(end.year, end.month, end.day);
    });
    _tabs.animateTo(1);
  }

  Widget _dashboardView(AppLocalizations t) {
    final cards = <({String title, String value, String report, bool today, String? status})>[
      (title: t.advancedProductionOpenOrders, value: '${_dashboard['open_orders'] ?? 0}', report: 'open_orders', today: false, status: null),
      (title: t.advancedProductionOverdue, value: '${_dashboard['overdue_orders'] ?? 0}', report: 'overdue', today: false, status: null),
      (title: t.advancedProductionInProgress, value: '${_dashboard['in_progress_orders'] ?? 0}', report: 'orders', today: false, status: 'in_progress'),
      (title: t.advancedProductionCompletedToday, value: '${_dashboard['completed_today'] ?? 0}', report: 'orders', today: false, status: null),
      (title: t.advancedProductionOutputToday, value: '${_dashboard['output_quantity_today'] ?? 0}', report: 'finished_goods', today: true, status: null),
      (title: t.advancedProductionShortageLines, value: '${_dashboard['shortage_lines'] ?? 0}', report: 'material_shortage', today: false, status: null),
      (title: t.advancedProductionPlanAchievement, value: _figure(t, _dashboard['plan_achievement_percent']), report: 'plan_achievement', today: false, status: null),
      (title: t.advancedProductionScrapPercent, value: _figure(t, _dashboard['scrap_percent']), report: 'scrap_rate', today: false, status: null),
      (title: t.advancedProductionWeekCost, value: _figure(t, _dashboard['period_cost_week']), report: 'period_cost', today: false, status: null),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.advancedProductionValuationNote),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(
                width: 220,
                child: Card(
                  child: InkWell(
                    onTap: () => _openReport(
                      card.report,
                      today: card.today,
                      status: card.status,
                      from: card.report == 'period_cost' ? _dashboard['period_cost_from']?.toString() : null,
                      to: card.report == 'period_cost' ? _dashboard['period_cost_to']?.toString() : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.title),
                          const SizedBox(height: 8),
                          Text(card.value, style: Theme.of(context).textTheme.headlineSmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(t.advancedProductionWeekOutput),
        const SizedBox(height: 8),
        for (final row in _weekRows())
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_showIso(row['document_date']?.toString())),
            trailing: Text('${row['quantity'] ?? 0}'),
            onTap: () => _openReport('finished_goods', day: row['document_date']?.toString()),
          ),
      ],
    );
  }

  String _figure(AppLocalizations t, dynamic value) {
    if (value == null) return t.advancedProductionNoFigure;
    return value.toString();
  }

  List<Map<String, dynamic>> _weekRows() {
    final raw = _dashboard['week_output'];
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  String _showIso(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    return HesabixDateUtils.formatApiDateForDisplay(
      raw,
      widget.calendarController.isJalali,
      fallback: raw,
    );
  }

  Widget _reportsView(AppLocalizations t, List<String> reports) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: reports.contains(_report) ? _report : 'orders',
                items: [
                  for (final key in reports)
                    DropdownMenuItem(value: key, child: Text(_reportTitle(t, key))),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _report = value;
                    _reportStatus = null;
                  });
                },
              ),
              SizedBox(
                width: 180,
                child: DateInputField(
                  value: _from,
                  calendarController: widget.calendarController,
                  labelText: t.advancedProductionFromDate,
                  onChanged: (value) => setState(() => _from = value),
                ),
              ),
              SizedBox(
                width: 180,
                child: DateInputField(
                  value: _to,
                  calendarController: widget.calendarController,
                  labelText: t.advancedProductionToDate,
                  onChanged: (value) => setState(() => _to = value),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  value: _fiscalYearId,
                  decoration: InputDecoration(labelText: t.fiscalYear, isDense: true),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text(t.all)),
                    for (final year in _fiscalYears)
                      DropdownMenuItem<int?>(
                        value: year['id'] as int?,
                        child: Text('${year['title'] ?? ''}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _fiscalYearId = value),
                ),
              ),
              SizedBox(
                width: 220,
                child: WarehouseComboboxWidget(
                  businessId: widget.businessId,
                  selectedWarehouseId: _warehouseId,
                  label: t.warehouse,
                  hintText: t.all,
                  selectDefaultWhenUnset: false,
                  onChanged: (value) => setState(() => _warehouseId = value),
                ),
              ),
              if (_documentReport)
                ReportCurrencyFilterDropdown(
                  businessId: widget.businessId,
                  isMultiCurrency: widget.authStore.isMultiCurrency,
                  selectedCurrencyId: _currencyId,
                  label: t.currency,
                  allCurrenciesLabel: t.allCurrencies,
                  onChanged: (value) => setState(() => _currencyId = value),
                ),
              if (_report == 'idle_materials')
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _idleDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.advancedProductionIdleDays),
                    onSubmitted: (_) => setState(() {}),
                  ),
                ),
              if (_report == 'lot_trace')
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _lotCtrl,
                    decoration: InputDecoration(labelText: t.advancedProductionLotCode),
                    onSubmitted: (_) => setState(() {}),
                  ),
                ),
              if (_report == 'break_even') ...[
                SizedBox(
                  width: 260,
                  child: ProductComboboxWidget(
                    businessId: widget.businessId,
                    label: t.advancedProductionColProduct,
                    hintText: t.advancedProductionColProduct,
                    onChanged: (product) => setState(() => _reportProductId = product?['id'] as int?),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _fixedCostCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.advancedProductionFixedCost),
                    onSubmitted: (_) => setState(() {}),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: DataTableWidget<Map<String, dynamic>>(
            key: ValueKey('$_report-${_iso(_from)}-${_iso(_to)}-$_fiscalYearId-$_warehouseId-$_currencyId-$_reportProductId-${_lotCtrl.text}-${_fixedCostCtrl.text}-${_idleDaysCtrl.text}-$_reportStatus'),
            config: _table(t),
            fromJson: (json) => json,
          ),
        ),
      ],
    );
  }

  Widget _accountField(String label, int? accountId, ValueChanged<int?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AbsorbPointer(
        absorbing: !_canManage,
        child: AccountComboboxWidget(
          businessId: widget.businessId,
          selectedAccount: _accountById(accountId),
          label: label,
          hintText: label,
          onChanged: (account) => onChanged(account?.id),
        ),
      ),
    );
  }

  Widget _settingsView(AppLocalizations t) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.advancedProductionValuationNote),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _method,
          decoration: InputDecoration(labelText: t.advancedProductionCostingMethod),
          items: [
            DropdownMenuItem(value: 'actual', child: Text(t.advancedProductionCostingActual)),
            DropdownMenuItem(value: 'standard', child: Text(t.advancedProductionCostingStandard)),
            DropdownMenuItem(value: 'weighted_average', child: Text(t.advancedProductionCostingAverage)),
          ],
          onChanged: _canManage ? (value) => setState(() => _method = value ?? 'actual') : null,
        ),
        const SizedBox(height: 8),
        Text(_methodLabel(t, _method)),
        const SizedBox(height: 8),
        Text(_ledgerMode == 'next_production_invoice' ? t.advancedProductionLedgerNext : t.advancedProductionLedgerUnchanged),
        const SizedBox(height: 8),
        Text(t.advancedProductionScrapLedger),
        const SizedBox(height: 16),
        _accountField(t.advancedProductionWipAccount, _wipAccountId, (id) => setState(() => _wipAccountId = id)),
        _accountField(t.advancedProductionFinishedAccount, _finishedAccountId, (id) => setState(() => _finishedAccountId = id)),
        _accountField(t.advancedProductionScrapAccount, _scrapAccountId, (id) => setState(() => _scrapAccountId = id)),
        _accountField(t.advancedProductionVarianceAccount, _varianceAccountId, (id) => setState(() => _varianceAccountId = id)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: !_canManage || _saving ? null : _save,
          child: Text(t.advancedProductionSave),
        ),
      ],
    );
  }

  Future<void> _saveRecord() async {
    final payload = <String, dynamic>{
      'code': _codeCtrl.text.trim(),
      'name': _nameCtrl.text.trim(),
      if (_lineId != null) 'line_id': _lineId,
      if (_recordKind == 'lines' && _workCenterId != null) 'work_center_id': _workCenterId,
      if (_recordKind == 'lines' && _nominalCtrl.text.trim().isNotEmpty) 'nominal_units_per_hour': num.tryParse(_nominalCtrl.text.trim()),
      if (_recordKind == 'shifts' && _startCtrl.text.trim().isNotEmpty) 'start_time': _startCtrl.text.trim(),
      if (_recordKind == 'shifts' && _endCtrl.text.trim().isNotEmpty) 'end_time': _endCtrl.text.trim(),
      if (_machineId != null) 'machine_id': _machineId,
      if (_productId != null) 'product_id': _productId,
      if (_recordDate != null) 'started_on': _iso(_recordDate),
      if (_recordDate != null) 'produced_on': _iso(_recordDate),
      if (_recordDate != null) 'inspected_on': _iso(_recordDate),
      if (_recordDate != null) 'opened_on': _iso(_recordDate),
      if (_minutesCtrl.text.trim().isNotEmpty) 'minutes': int.tryParse(_minutesCtrl.text.trim()),
      if (_minutesCtrl.text.trim().isNotEmpty) 'run_minutes': int.tryParse(_minutesCtrl.text.trim()),
      if (_minutesCtrl.text.trim().isNotEmpty) 'repair_minutes': int.tryParse(_minutesCtrl.text.trim()),
      if (_goodCtrl.text.trim().isNotEmpty) 'quantity_good': num.tryParse(_goodCtrl.text.trim()),
      if (_scrapCtrl.text.trim().isNotEmpty) 'quantity_scrap': num.tryParse(_scrapCtrl.text.trim()),
      if (_costCtrl.text.trim().isNotEmpty) 'cost_amount': num.tryParse(_costCtrl.text.trim()),
      if (_checkedCtrl.text.trim().isNotEmpty) 'quantity_checked': num.tryParse(_checkedCtrl.text.trim()),
      if (_rejectedCtrl.text.trim().isNotEmpty) 'quantity_rejected': num.tryParse(_rejectedCtrl.text.trim()),
      'maintenance_kind': _maintenanceKind,
      'stage': _qcStage,
      'result': _qcResult,
      if (_operatorCtrl.text.trim().isNotEmpty) 'operator_person_id': int.tryParse(_operatorCtrl.text.trim()),
      if (_recordKind == 'downtime') 'reason_code': _reasonCtrl.text.trim().isEmpty ? 'unspecified' : _reasonCtrl.text.trim(),
      if (_recordKind == 'inspections' && _reasonCtrl.text.trim().isNotEmpty) 'reason_code': _reasonCtrl.text.trim(),
      if (_recordKind == 'scrap_reasons' && _recyclableChoice != null) 'recyclable': _recyclableChoice == 'yes',
      if (_recordKind == 'scrap_events' && _reasonId != null) 'reason_id': _reasonId,
      if (_recordKind == 'scrap_events' && _scrapCtrl.text.trim().isNotEmpty) 'quantity': num.tryParse(_scrapCtrl.text.trim()),
      if (_recordKind == 'order_holds' && _codeCtrl.text.trim().isNotEmpty) 'production_order_id': int.tryParse(_codeCtrl.text.trim()),
      if (_recordKind == 'order_holds' && _nameCtrl.text.trim().isNotEmpty) 'reason': _nameCtrl.text.trim(),
      if (_recordKind == 'order_holds' && _operatorCtrl.text.trim().isNotEmpty) 'hold_id': int.tryParse(_operatorCtrl.text.trim()),
      if (_recordKind == 'order_holds' && _operatorCtrl.text.trim().isNotEmpty && _recordDate != null) 'released_on': _iso(_recordDate),
      if (_recordKind == 'outputs' && _machineId != null) 'machine_id': _machineId,
      if (_recordKind == 'outputs' && _shiftId != null) 'shift_id': _shiftId,
      if ((_recordKind == 'order_lines' || _recordKind == 'wip_counts' || _recordKind == 'reworks') && _codeCtrl.text.trim().isNotEmpty)
        'production_order_id': int.tryParse(_codeCtrl.text.trim()),
      if (_recordKind == 'wip_counts' && _scrapCtrl.text.trim().isNotEmpty) 'counted_quantity': num.tryParse(_scrapCtrl.text.trim()),
      if ((_recordKind == 'reworks' || _recordKind == 'line_returns' || _recordKind == 'stage_transfers') && _scrapCtrl.text.trim().isNotEmpty)
        'quantity': num.tryParse(_scrapCtrl.text.trim()),
      if (_recordKind == 'stage_transfers' && _lineId != null) 'from_line_id': _lineId,
      if (_recordKind == 'stage_transfers' && _toLineId != null) 'to_line_id': _toLineId,
      if (_recordKind == 'labor' && _minutesCtrl.text.trim().isNotEmpty) 'actual_hours': num.tryParse(_minutesCtrl.text.trim()),
      if (_recordKind == 'labor' && _goodCtrl.text.trim().isNotEmpty) 'standard_hours': num.tryParse(_goodCtrl.text.trim()),
      if (_recordKind == 'labor' && _costCtrl.text.trim().isNotEmpty) 'standard_hourly_rate': num.tryParse(_costCtrl.text.trim()),
      if (_recordKind == 'labor' && _checkedCtrl.text.trim().isNotEmpty) 'actual_hourly_rate': num.tryParse(_checkedCtrl.text.trim()),
      if (_recordKind == 'labor' && _codeCtrl.text.trim().isNotEmpty) 'production_order_id': int.tryParse(_codeCtrl.text.trim()),
      if (_recordKind == 'labor' && _operatorCtrl.text.trim().isNotEmpty) 'person_id': int.tryParse(_operatorCtrl.text.trim()),
      if (_recordKind == 'downtime' && _costCtrl.text.trim().isNotEmpty) 'cost_amount': num.tryParse(_costCtrl.text.trim()),
      if (_recordDate != null) 'occurred_on': _iso(_recordDate),
    };
    setState(() => _saving = true);
    try {
      await _svc.createMaster(businessId: widget.businessId, kind: _recordKind, payload: payload);
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).advancedProductionSaved);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _recordsView(AppLocalizations t) {
    final canOperate = widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.hasBusinessPermission('advanced_production', 'operate');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.advancedProductionRecordsHelp),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _recordKind,
          decoration: InputDecoration(labelText: t.advancedProductionRecordKind),
          items: [
            DropdownMenuItem(value: 'work_centers', child: Text(t.advancedProductionWorkCenter)),
            DropdownMenuItem(value: 'lines', child: Text(t.advancedProductionLine)),
            DropdownMenuItem(value: 'machines', child: Text(t.advancedProductionMachine)),
            DropdownMenuItem(value: 'shifts', child: Text(t.advancedProductionShift)),
            DropdownMenuItem(value: 'downtime', child: Text(t.advancedProductionReportDowntime)),
            DropdownMenuItem(value: 'outputs', child: Text(t.advancedProductionOutput)),
            DropdownMenuItem(value: 'inspections', child: Text(t.advancedProductionReportQc)),
            DropdownMenuItem(value: 'maintenance', child: Text(t.advancedProductionMaintenance)),
            DropdownMenuItem(value: 'scrap_reasons', child: Text(t.advancedProductionScrapReason)),
            DropdownMenuItem(value: 'scrap_events', child: Text(t.advancedProductionScrapEvent)),
            DropdownMenuItem(value: 'order_holds', child: Text(t.advancedProductionReportHeld)),
            DropdownMenuItem(value: 'order_lines', child: Text(t.advancedProductionReportCapacityNeed)),
            DropdownMenuItem(value: 'wip_counts', child: Text(t.advancedProductionReportWipCount)),
            DropdownMenuItem(value: 'reworks', child: Text(t.advancedProductionReportRework)),
            DropdownMenuItem(value: 'line_returns', child: Text(t.advancedProductionReportLineReturn)),
            DropdownMenuItem(value: 'stage_transfers', child: Text(t.advancedProductionReportTransfer)),
            DropdownMenuItem(value: 'labor', child: Text(t.advancedProductionReportWage)),
          ],
          onChanged: (value) => setState(() => _recordKind = value ?? 'work_centers'),
        ),
        if (_recordKind == 'work_centers' || _recordKind == 'lines' || _recordKind == 'machines' || _recordKind == 'shifts' || _recordKind == 'scrap_reasons' || _recordKind == 'order_holds' || _recordKind == 'order_lines' || _recordKind == 'wip_counts' || _recordKind == 'reworks' || _recordKind == 'labor') ...[
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              labelText: _recordKind == 'order_holds' || _recordKind == 'order_lines' || _recordKind == 'wip_counts' || _recordKind == 'reworks' || _recordKind == 'labor'
                  ? t.advancedProductionOrderId
                  : t.advancedProductionCode,
            ),
            keyboardType: _recordKind == 'order_holds' || _recordKind == 'order_lines' || _recordKind == 'wip_counts' || _recordKind == 'reworks' || _recordKind == 'labor'
                ? TextInputType.number
                : TextInputType.text,
          ),
          if (_recordKind == 'lines' && _workCenters.isNotEmpty)
            DropdownButtonFormField<int>(
              value: _workCenterId,
              decoration: InputDecoration(labelText: t.advancedProductionWorkCenter),
              items: [
                for (final center in _workCenters)
                  DropdownMenuItem(value: center['id'] as int, child: Text('${center['code']} ${center['name']}')),
              ],
              onChanged: (value) => setState(() => _workCenterId = value),
            ),
          if (_recordKind == 'lines')
            TextField(
              controller: _nominalCtrl,
              decoration: InputDecoration(labelText: t.advancedProductionNominalRate),
              keyboardType: TextInputType.number,
            ),
          if (_recordKind == 'shifts') ...[
            TextField(controller: _startCtrl, decoration: InputDecoration(labelText: t.advancedProductionStartTime)),
            TextField(controller: _endCtrl, decoration: InputDecoration(labelText: t.advancedProductionEndTime)),
          ],
          if (_recordKind != 'order_lines' && _recordKind != 'wip_counts' && _recordKind != 'reworks' && _recordKind != 'labor')
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: _recordKind == 'order_holds' ? t.advancedProductionHoldReason : t.advancedProductionName),
            ),
        ],
        if (_recordKind == 'order_holds')
          TextField(controller: _operatorCtrl, decoration: InputDecoration(labelText: t.advancedProductionHoldId), keyboardType: TextInputType.number),
        if (_lines.isNotEmpty && _recordKind != 'work_centers')
          DropdownButtonFormField<int>(
            value: _lineId,
            decoration: InputDecoration(labelText: _recordKind == 'stage_transfers' ? t.advancedProductionFromLine : t.advancedProductionLine),
            items: [
              for (final line in _lines)
                DropdownMenuItem(value: line['id'] as int, child: Text('${line['code']} ${line['name']}')),
            ],
            onChanged: (value) => setState(() => _lineId = value),
          ),
        if (_shifts.isNotEmpty && _recordKind == 'outputs')
          DropdownButtonFormField<int>(
            value: _shiftId,
            decoration: InputDecoration(labelText: t.advancedProductionShift),
            items: [
              for (final shift in _shifts)
                DropdownMenuItem(value: shift['id'] as int, child: Text('${shift['code']} ${shift['name']}')),
            ],
            onChanged: (value) => setState(() => _shiftId = value),
          ),
        if (_machines.isNotEmpty && (_recordKind == 'maintenance' || _recordKind == 'outputs'))
          DropdownButtonFormField<int>(
            value: _machineId,
            decoration: InputDecoration(labelText: t.advancedProductionMachine),
            items: [
              for (final machine in _machines)
                DropdownMenuItem(value: machine['id'] as int, child: Text('${machine['code']} ${machine['name']}')),
            ],
            onChanged: (value) => setState(() => _machineId = value),
          ),
        if (_recordKind == 'scrap_reasons')
          DropdownButtonFormField<String>(
            value: _recyclableChoice,
            decoration: InputDecoration(labelText: t.advancedProductionRecyclable),
            items: [
              DropdownMenuItem(value: 'yes', child: Text(t.advancedProductionRecyclableYes)),
              DropdownMenuItem(value: 'no', child: Text(t.advancedProductionRecyclableNo)),
            ],
            onChanged: (value) => setState(() => _recyclableChoice = value),
          ),
        if (_scrapReasons.isNotEmpty && _recordKind == 'scrap_events')
          DropdownButtonFormField<int>(
            value: _reasonId,
            decoration: InputDecoration(labelText: t.advancedProductionScrapReason),
            items: [
              for (final reason in _scrapReasons)
                DropdownMenuItem(value: reason['id'] as int, child: Text('${reason['code']} ${reason['name']}')),
            ],
            onChanged: (value) => setState(() => _reasonId = value),
          ),
        if (_lines.isNotEmpty && _recordKind == 'stage_transfers')
          DropdownButtonFormField<int>(
            value: _toLineId,
            decoration: InputDecoration(labelText: t.advancedProductionToLine),
            items: [
              for (final line in _lines)
                DropdownMenuItem(value: line['id'] as int, child: Text('${line['code']} ${line['name']}')),
            ],
            onChanged: (value) => setState(() => _toLineId = value),
          ),
        if (_recordKind == 'outputs' || _recordKind == 'inspections' || _recordKind == 'scrap_events' || _recordKind == 'reworks' || _recordKind == 'line_returns' || _recordKind == 'stage_transfers')
          ProductComboboxWidget(
            businessId: widget.businessId,
            label: t.advancedProductionColProduct,
            hintText: t.advancedProductionColProduct,
            onChanged: (product) => setState(() => _productId = product?['id'] as int?),
          ),
        if (_recordKind != 'work_centers' && _recordKind != 'lines')
          DateInputField(
            value: _recordDate,
            calendarController: widget.calendarController,
            labelText: t.advancedProductionFromDate,
            onChanged: (value) => setState(() => _recordDate = value),
          ),
        if (_recordKind == 'downtime' || _recordKind == 'outputs' || _recordKind == 'maintenance' || _recordKind == 'labor')
          TextField(
            controller: _minutesCtrl,
            decoration: InputDecoration(labelText: _recordKind == 'labor' ? t.advancedProductionActualHours : t.advancedProductionMinutes),
            keyboardType: TextInputType.number,
          ),
        if (_recordKind == 'outputs' || _recordKind == 'labor')
          TextField(controller: _operatorCtrl, decoration: InputDecoration(labelText: t.advancedProductionOperator), keyboardType: TextInputType.number),
        if (_recordKind == 'labor') ...[
          TextField(controller: _goodCtrl, decoration: InputDecoration(labelText: t.advancedProductionStandardHours), keyboardType: TextInputType.number),
          TextField(controller: _costCtrl, decoration: InputDecoration(labelText: t.advancedProductionStandardRate), keyboardType: TextInputType.number),
          TextField(controller: _checkedCtrl, decoration: InputDecoration(labelText: t.advancedProductionActualRate), keyboardType: TextInputType.number),
        ],
        if (_recordKind == 'downtime' || _recordKind == 'inspections')
          TextField(controller: _reasonCtrl, decoration: InputDecoration(labelText: t.advancedProductionReason)),
        if (_recordKind == 'scrap_events' || _recordKind == 'wip_counts' || _recordKind == 'reworks' || _recordKind == 'line_returns' || _recordKind == 'stage_transfers')
          TextField(
            controller: _scrapCtrl,
            decoration: InputDecoration(labelText: _recordKind == 'wip_counts' ? t.advancedProductionCountedQuantity : t.advancedProductionScrapQuantity),
            keyboardType: TextInputType.number,
          ),
        if (_recordKind == 'outputs') ...[
          TextField(controller: _goodCtrl, decoration: InputDecoration(labelText: t.advancedProductionGoodQuantity), keyboardType: TextInputType.number),
          TextField(controller: _scrapCtrl, decoration: InputDecoration(labelText: t.advancedProductionScrapQuantity), keyboardType: TextInputType.number),
        ],
        if (_recordKind == 'inspections') ...[
          DropdownButtonFormField<String>(
            value: _qcStage,
            decoration: InputDecoration(labelText: t.advancedProductionStage),
            items: [
              DropdownMenuItem(value: 'incoming', child: Text(t.advancedProductionStageIncoming)),
              DropdownMenuItem(value: 'in_process', child: Text(t.advancedProductionStageInProcess)),
              DropdownMenuItem(value: 'final', child: Text(t.advancedProductionStageFinal)),
            ],
            onChanged: (value) => setState(() => _qcStage = value ?? 'final'),
          ),
          DropdownButtonFormField<String>(
            value: _qcResult,
            decoration: InputDecoration(labelText: t.advancedProductionResult),
            items: [
              DropdownMenuItem(value: 'pass', child: Text(t.advancedProductionResultPass)),
              DropdownMenuItem(value: 'fail', child: Text(t.advancedProductionResultFail)),
            ],
            onChanged: (value) => setState(() => _qcResult = value ?? 'pass'),
          ),
          TextField(controller: _checkedCtrl, decoration: InputDecoration(labelText: t.advancedProductionCheckedQuantity), keyboardType: TextInputType.number),
          TextField(controller: _rejectedCtrl, decoration: InputDecoration(labelText: t.advancedProductionRejectedQuantity), keyboardType: TextInputType.number),
        ],
        if (_recordKind == 'maintenance')
          DropdownButtonFormField<String>(
            value: _maintenanceKind,
            decoration: InputDecoration(labelText: t.advancedProductionMaintenance),
            items: [
              DropdownMenuItem(value: 'breakdown', child: Text(t.advancedProductionMaintenanceBreakdown)),
              DropdownMenuItem(value: 'preventive', child: Text(t.advancedProductionMaintenancePreventive)),
            ],
            onChanged: (value) => setState(() => _maintenanceKind = value ?? 'breakdown'),
          ),
        if (_recordKind == 'maintenance' || _recordKind == 'downtime')
          TextField(controller: _costCtrl, decoration: InputDecoration(labelText: t.advancedProductionCostAmount), keyboardType: TextInputType.number),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: !canOperate || _saving ? null : _saveRecord,
          child: Text(t.advancedProductionSave),
        ),
      ],
    );
  }
}
