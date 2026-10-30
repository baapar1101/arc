import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../core/hesabix_back.dart';
import '../../../services/fixed_assets_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/data_table/data_table_config.dart';
import '../../../widgets/data_table/data_table_widget.dart';
import '../../../widgets/date_input_field.dart';
import '../../../widgets/permission/access_denied_page.dart';
import 'fixed_assets_report_tables.dart';
import 'fixed_assets_ui.dart';

const _reportKinds = <String>[
  'register',
  'class_summary',
  'depreciation',
  'acquisitions',
  'disposals',
  'idle',
  'locations',
  'expenditures',
];

class FixedAssetsReportsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final String initialKind;

  const FixedAssetsReportsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    this.initialKind = 'register',
  });

  @override
  State<FixedAssetsReportsPage> createState() => _FixedAssetsReportsPageState();
}

class _FixedAssetsReportsPageState extends State<FixedAssetsReportsPage> {
  final FixedAssetsService _svc = FixedAssetsService();

  late String _kind;
  late DateTime _from;
  late DateTime _to;
  int? _classId;
  List<Map<String, dynamic>> _classes = [];
  Map<String, dynamic> _report = const {};
  bool _loading = true;

  bool get _needsDates =>
      _kind == 'class_summary' ||
      _kind == 'depreciation' ||
      _kind == 'acquisitions' ||
      _kind == 'disposals' ||
      _kind == 'expenditures';

  bool get _canView =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'view');

  @override
  void initState() {
    super.initState();
    _kind = _reportKinds.contains(widget.initialKind) ? widget.initialKind : 'register';
    _from = FixedAssetsUi.startOfDisplayYear(widget.calendarController.isJalali);
    _to = DateTime.now();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant FixedAssetsReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialKind != widget.initialKind && _reportKinds.contains(widget.initialKind)) {
      _kind = widget.initialKind;
      _load();
    }
  }

  Future<void> _bootstrap() async {
    try {
      final classes = await _svc.listClasses(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _classes = classes);
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.getReport(
        businessId: widget.businessId,
        kind: _kind,
        fromDate: _needsDates ? HesabixDateUtils.formatForApiDate(_from) : null,
        toDate: _needsDates ? HesabixDateUtils.formatForApiDate(_to) : null,
        classId: _classId,
      );
      if (!mounted) return;
      setState(() {
        _report = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String _title(AppLocalizations t) {
    switch (_kind) {
      case 'class_summary':
        return t.fixedAssetsReportClassSummary;
      case 'depreciation':
        return t.fixedAssetsReportDepreciation;
      case 'acquisitions':
        return t.fixedAssetsReportAcquisitions;
      case 'disposals':
        return t.fixedAssetsReportDisposals;
      case 'idle':
        return t.fixedAssetsReportIdle;
      case 'locations':
        return t.fixedAssetsReportLocations;
      case 'expenditures':
        return t.fixedAssetsReportExpenditures;
      default:
        return t.fixedAssetsReportRegister;
    }
  }

  String _hint(AppLocalizations t) {
    switch (_kind) {
      case 'class_summary':
        return t.fixedAssetsReportClassSummaryHint;
      case 'depreciation':
        return t.fixedAssetsReportDepreciationHint;
      case 'acquisitions':
        return t.fixedAssetsReportAcquisitionsHint;
      case 'disposals':
        return t.fixedAssetsReportDisposalsHint;
      case 'idle':
        return t.fixedAssetsReportIdleHint;
      case 'locations':
        return t.fixedAssetsReportLocationsHint;
      case 'expenditures':
        return t.fixedAssetsReportExpendituresHint;
      default:
        return t.fixedAssetsReportRegisterHint;
    }
  }

  DataTableConfig<Map<String, dynamic>> _table(AppLocalizations t) {
    final jalali = widget.calendarController.isJalali == true;
    switch (_kind) {
      case 'class_summary':
        return FixedAssetsReportTables.classSummary(t: t);
      case 'depreciation':
        return FixedAssetsReportTables.depreciation(t: t, isJalali: jalali);
      case 'acquisitions':
        return FixedAssetsReportTables.acquisitions(t: t, isJalali: jalali);
      case 'disposals':
        return FixedAssetsReportTables.disposals(t: t, isJalali: jalali);
      case 'idle':
        return FixedAssetsReportTables.idle(t: t, isJalali: jalali);
      case 'locations':
        return FixedAssetsReportTables.locations(t: t);
      case 'expenditures':
        return FixedAssetsReportTables.expenditures(t: t, isJalali: jalali);
      default:
        return FixedAssetsReportTables.register(t: t, isJalali: jalali);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canView) return AccessDeniedPage(message: t.accessDenied);
    final items = (_report['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final totals = Map<String, dynamic>.from(_report['totals'] as Map? ?? const {});
    return Scaffold(
        appBar: AppBar(
          leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
          title: Text(_title(t)),
          actions: [
            IconButton(tooltip: t.refresh, icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: ListView(
          padding: FixedAssetsUi.pagePadding,
          children: [
            FixedAssetsUi.sectionCard(
              context: context,
              title: t.fixedAssetsReportFilters,
              icon: Icons.filter_list,
              child: FixedAssetsUi.spacedColumn([
                DropdownButtonFormField<String>(
                  value: _kind,
                  decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsReportKind, prefixIcon: Icons.summarize_outlined),
                  items: [
                    for (final k in _reportKinds)
                      DropdownMenuItem(value: k, child: Text(_kindLabel(t, k))),
                  ],
                  onChanged: (v) {
                    if (v == null || v == _kind) return;
                    context.go(
                      context.businessPanelUrl(
                        widget.businessId,
                        'reports/fixed-assets?kind=$v',
                      ),
                    );
                  },
                ),
                if (_classes.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: _classId,
                    decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsClass, prefixIcon: Icons.category_outlined),
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text(t.fixedAssetsStatusAll)),
                      for (final c in _classes)
                        DropdownMenuItem<int?>(value: int.parse('${c['id']}'), child: Text('${c['name']}')),
                    ],
                    onChanged: (v) {
                      setState(() => _classId = v);
                      _load();
                    },
                  ),
                if (_needsDates) ...[
                  DateInputField(
                    value: _from,
                    calendarController: widget.calendarController,
                    labelText: t.dateFrom,
                    firstDate: FixedAssetsUi.datePickerFirst,
                    lastDate: FixedAssetsUi.datePickerLast,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    onChanged: (d) {
                      if (d == null) return;
                      setState(() => _from = d);
                    },
                  ),
                  DateInputField(
                    value: _to,
                    calendarController: widget.calendarController,
                    labelText: t.dateTo,
                    firstDate: FixedAssetsUi.datePickerFirst,
                    lastDate: FixedAssetsUi.datePickerLast,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    onChanged: (d) {
                      if (d == null) return;
                      setState(() => _to = d);
                    },
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.search),
                      label: Text(t.apply),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            FixedAssetsUi.infoBanner(context, _hint(t)),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (totals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (totals['net_book_value'] != null)
                    Chip(label: Text('${t.fixedAssetsNetBookValue}: ${FixedAssetsUi.money(totals['net_book_value'])}')),
                  if (totals['cost'] != null)
                    Chip(label: Text('${t.fixedAssetsCost}: ${FixedAssetsUi.money(totals['cost'])}')),
                  if (totals['closing_nbv'] != null)
                    Chip(label: Text('${t.fixedAssetsReportClosingNbv}: ${FixedAssetsUi.money(totals['closing_nbv'])}')),
                  if (totals['amount'] != null)
                    Chip(label: Text('${t.fixedAssetsReportDepreciationAmount}: ${FixedAssetsUi.money(totals['amount'])}')),
                  if (totals['proceeds'] != null)
                    Chip(label: Text('${t.fixedAssetsProceeds}: ${FixedAssetsUi.money(totals['proceeds'])}')),
                  if (totals['gain_loss'] != null)
                    Chip(label: Text('${t.fixedAssetsReportGainLoss}: ${FixedAssetsUi.money(totals['gain_loss'])}')),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (!_loading)
              DataTableWidget<Map<String, dynamic>>(
                key: ValueKey('fa-report-$_kind-${items.length}'),
                config: _table(t),
                fromJson: (json) => json,
                calendarController: widget.calendarController,
                localRawItems: items,
              ),
          ],
        ),
    );
  }

  String _kindLabel(AppLocalizations t, String kind) {
    switch (kind) {
      case 'class_summary':
        return t.fixedAssetsReportClassSummary;
      case 'depreciation':
        return t.fixedAssetsReportDepreciation;
      case 'acquisitions':
        return t.fixedAssetsReportAcquisitions;
      case 'disposals':
        return t.fixedAssetsReportDisposals;
      case 'idle':
        return t.fixedAssetsReportIdle;
      case 'locations':
        return t.fixedAssetsReportLocations;
      case 'expenditures':
        return t.fixedAssetsReportExpenditures;
      default:
        return t.fixedAssetsReportRegister;
    }
  }
}
