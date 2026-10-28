import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../services/fixed_assets_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/number_formatters.dart' show formatWithThousands;
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/date_input_field.dart';

class FixedAssetsMainPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const FixedAssetsMainPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<FixedAssetsMainPage> createState() => _FixedAssetsMainPageState();
}

class _FixedAssetsMainPageState extends State<FixedAssetsMainPage> with SingleTickerProviderStateMixin {
  final FixedAssetsService _svc = FixedAssetsService();
  late TabController _tabController;

  bool _loading = true;
  Map<String, dynamic> _dashboard = const {};
  List<Map<String, dynamic>> _assets = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _runs = [];
  Map<String, dynamic> _settings = const {};

  bool get _canManage =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'manage');

  bool get _canOperate =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'operate');

  bool get _canPost =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'post');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.getDashboard(businessId: widget.businessId),
        _svc.listAssets(businessId: widget.businessId),
        _svc.listClasses(businessId: widget.businessId),
        _svc.listRuns(businessId: widget.businessId),
        _svc.getSettings(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      final assetsData = Map<String, dynamic>.from(results[1] as Map);
      final runsData = Map<String, dynamic>.from(results[3] as Map);
      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0] as Map);
        _assets = (assetsData['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _classes = List<Map<String, dynamic>>.from(results[2] as List);
        _runs = (runsData['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _settings = Map<String, dynamic>.from(results[4] as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String _isoDate(DateTime d) => d.toIso8601String().split('T').first;

  Future<void> _createAsset() async {
    final t = AppLocalizations.of(context);
    if (_classes.isEmpty) {
      SnackBarHelper.show(context, message: t.fixedAssetsNoClasses);
      return;
    }
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final salvageCtrl = TextEditingController(text: '0');
    final vatCtrl = TextEditingController(text: '0');
    final lifeCtrl = TextEditingController(text: '120');
    int classId = int.parse('${_classes.first['id']}');
    String kind = 'purchase';
    DateTime acquisition = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.fixedAssetsNewAsset),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        value: classId,
                        decoration: InputDecoration(labelText: t.fixedAssetsClass),
                        items: [
                          for (final c in _classes)
                            DropdownMenuItem(
                              value: int.parse('${c['id']}'),
                              child: Text('${c['name']}'),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => classId = v);
                        },
                      ),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(labelText: t.fixedAssetsAssetName),
                      ),
                      TextField(
                        controller: costCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsCost),
                      ),
                      TextField(
                        controller: salvageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsSalvage),
                      ),
                      TextField(
                        controller: vatCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsVat),
                      ),
                      TextField(
                        controller: lifeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsUsefulLifeMonths),
                      ),
                      DropdownButtonFormField<String>(
                        value: kind,
                        decoration: InputDecoration(labelText: t.fixedAssetsAcquisitionKind),
                        items: [
                          DropdownMenuItem(value: 'purchase', child: Text(t.fixedAssetsKindPurchase)),
                          DropdownMenuItem(value: 'opening', child: Text(t.fixedAssetsKindOpening)),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => kind = v);
                        },
                      ),
                      const SizedBox(height: 8),
                      DateInputField(
                        value: acquisition,
                        calendarController: widget.calendarController,
                        labelText: t.fixedAssetsAcquisitionDate,
                        onChanged: (d) {
                          if (d != null) setLocal(() => acquisition = d);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await _svc.createAsset(
        businessId: widget.businessId,
        payload: {
          'class_id': classId,
          'name': nameCtrl.text.trim(),
          'cost': costCtrl.text.trim(),
          'salvage': salvageCtrl.text.trim(),
          'vat_amount': vatCtrl.text.trim(),
          'useful_life_months': int.tryParse(lifeCtrl.text.trim()),
          'acquisition_kind': kind,
          'acquisition_date': _isoDate(acquisition),
          'commission_date': _isoDate(acquisition),
          'method': 'straight_line',
        },
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsSaved);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _capitalize(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    String cp = 'opening';
    final idCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.fixedAssetsCapitalize),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.fixedAssetsCapitalizeHint),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: cp,
                      decoration: InputDecoration(labelText: t.fixedAssetsCounterparty),
                      items: [
                        DropdownMenuItem(value: 'opening', child: Text(t.fixedAssetsKindOpening)),
                        DropdownMenuItem(value: 'person', child: Text(t.fixedAssetsCounterpartyPerson)),
                        DropdownMenuItem(value: 'bank', child: Text(t.fixedAssetsCounterpartyBank)),
                        DropdownMenuItem(value: 'cash_register', child: Text(t.fixedAssetsCounterpartyCash)),
                        DropdownMenuItem(value: 'petty_cash', child: Text(t.fixedAssetsCounterpartyPetty)),
                        DropdownMenuItem(value: 'account', child: Text(t.fixedAssetsCounterpartyAccount)),
                      ],
                      onChanged: (v) {
                        if (v != null) setLocal(() => cp = v);
                      },
                    ),
                    if (cp != 'opening')
                      TextField(
                        controller: idCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsCounterpartyId),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.fixedAssetsCapitalize)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final payload = <String, dynamic>{'counterparty_type': cp};
    final id = int.tryParse(idCtrl.text.trim());
    if (cp == 'person') payload['person_id'] = id;
    if (cp == 'bank') payload['bank_account_id'] = id;
    if (cp == 'cash_register') payload['cash_register_id'] = id;
    if (cp == 'petty_cash') payload['petty_cash_id'] = id;
    if (cp == 'account') payload['account_id'] = id;
    try {
      await _svc.capitalizeAsset(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsCapitalized);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createRun() async {
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    var year = now.year;
    var month = now.month;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.fixedAssetsNewDepreciationRun),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.fixedAssetsDepreciationGregorianHint),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: '$year',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: t.fixedAssetsPeriodYear),
                      onChanged: (v) => year = int.tryParse(v) ?? year,
                    ),
                    TextFormField(
                      initialValue: '$month',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: t.fixedAssetsPeriodMonth),
                      onChanged: (v) => month = int.tryParse(v) ?? month,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await _svc.createRun(
        businessId: widget.businessId,
        payload: {'period_year': year, 'period_month': month},
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsRunCreated);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _postRun(Map<String, dynamic> run) async {
    final t = AppLocalizations.of(context);
    try {
      await _svc.postRun(businessId: widget.businessId, runId: int.parse('${run['id']}'));
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsRunPosted);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String _statusLabel(AppLocalizations t, Object? status) {
    switch ('$status') {
      case 'draft':
        return t.fixedAssetsStatusDraft;
      case 'capitalized':
        return t.fixedAssetsStatusCapitalized;
      case 'idle':
        return t.fixedAssetsStatusIdle;
      case 'disposed':
        return t.fixedAssetsStatusDisposed;
      default:
        return '$status';
    }
  }

  Widget _assetTrailing(AppLocalizations t, Map<String, dynamic> asset) {
    final status = '${asset['status']}';
    if (status == 'draft' && _canPost) {
      return TextButton(
        onPressed: () => _capitalize(asset),
        child: Text(t.fixedAssetsCapitalize),
      );
    }
    final live = status == 'capitalized' || status == 'idle';
    if (!live) {
      return Text(formatWithThousands(asset['net_book_value']));
    }
    final menu = <PopupMenuEntry<String>>[
      if (_canPost) PopupMenuItem(value: 'dispose', child: Text(t.fixedAssetsDispose)),
      if (_canPost) PopupMenuItem(value: 'subsequent', child: Text(t.fixedAssetsSubsequent)),
      if (_canManage) PopupMenuItem(value: 'estimate', child: Text(t.fixedAssetsEstimateChange)),
      if (_canOperate && status != 'idle')
        PopupMenuItem(value: 'idle', child: Text(t.fixedAssetsMarkIdle)),
      if (_canOperate && status == 'idle')
        PopupMenuItem(value: 'resume', child: Text(t.fixedAssetsResume)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatWithThousands(asset['net_book_value'])),
        if (menu.isNotEmpty)
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'dispose') _disposeAsset(asset);
              if (v == 'subsequent') _subsequent(asset);
              if (v == 'estimate') _estimateChange(asset);
              if (v == 'idle') _markIdle(asset);
              if (v == 'resume') _resume(asset);
            },
            itemBuilder: (ctx) => menu,
          ),
      ],
    );
  }

  Map<String, dynamic> _counterpartyPayload(String type, String idText) {
    final payload = <String, dynamic>{'counterparty_type': type};
    final id = int.tryParse(idText.trim());
    if (type == 'person') payload['person_id'] = id;
    if (type == 'bank') payload['bank_account_id'] = id;
    if (type == 'cash_register') payload['cash_register_id'] = id;
    if (type == 'petty_cash') payload['petty_cash_id'] = id;
    if (type == 'account') payload['account_id'] = id;
    return payload;
  }

  Future<void> _disposeAsset(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    String kind = 'sale';
    String cp = 'bank';
    final proceedsCtrl = TextEditingController();
    final vatCtrl = TextEditingController(text: '0');
    final idCtrl = TextEditingController();
    DateTime disposal = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.fixedAssetsDispose),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: kind,
                        decoration: InputDecoration(labelText: t.fixedAssetsDispose),
                        items: [
                          DropdownMenuItem(value: 'sale', child: Text(t.fixedAssetsSale)),
                          DropdownMenuItem(value: 'scrap', child: Text(t.fixedAssetsScrap)),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => kind = v);
                        },
                      ),
                      if (kind == 'sale') ...[
                        TextField(
                          controller: proceedsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t.fixedAssetsProceeds),
                        ),
                        TextField(
                          controller: vatCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t.fixedAssetsVatOutput),
                        ),
                        DropdownButtonFormField<String>(
                          value: cp,
                          decoration: InputDecoration(labelText: t.fixedAssetsCounterparty),
                          items: [
                            DropdownMenuItem(value: 'person', child: Text(t.fixedAssetsCounterpartyPerson)),
                            DropdownMenuItem(value: 'bank', child: Text(t.fixedAssetsCounterpartyBank)),
                            DropdownMenuItem(value: 'cash_register', child: Text(t.fixedAssetsCounterpartyCash)),
                            DropdownMenuItem(value: 'petty_cash', child: Text(t.fixedAssetsCounterpartyPetty)),
                            DropdownMenuItem(value: 'account', child: Text(t.fixedAssetsCounterpartyAccount)),
                          ],
                          onChanged: (v) {
                            if (v != null) setLocal(() => cp = v);
                          },
                        ),
                        TextField(
                          controller: idCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t.fixedAssetsCounterpartyId),
                        ),
                      ],
                      const SizedBox(height: 8),
                      DateInputField(
                        value: disposal,
                        calendarController: widget.calendarController,
                        labelText: t.fixedAssetsDisposalDate,
                        onChanged: (d) {
                          if (d != null) setLocal(() => disposal = d);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.fixedAssetsDispose)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final payload = <String, dynamic>{
      'kind': kind,
      'disposal_date': _isoDate(disposal),
      'proceeds': kind == 'scrap' ? '0' : proceedsCtrl.text.trim(),
      'vat_output': kind == 'scrap' ? '0' : vatCtrl.text.trim(),
    };
    if (kind == 'sale') {
      payload.addAll(_counterpartyPayload(cp, idCtrl.text));
    }
    try {
      await _svc.disposeAsset(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsDisposed);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _subsequent(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    String kind = 'routine';
    String cp = 'person';
    final amountCtrl = TextEditingController();
    final vatCtrl = TextEditingController(text: '0');
    final lifeCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    DateTime expDate = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.fixedAssetsSubsequent),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: kind,
                        items: [
                          DropdownMenuItem(value: 'routine', child: Text(t.fixedAssetsRoutineRepair)),
                          DropdownMenuItem(value: 'major', child: Text(t.fixedAssetsMajorRepair)),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => kind = v);
                        },
                      ),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsExpenditureAmount),
                      ),
                      TextField(
                        controller: vatCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsVat),
                      ),
                      if (kind == 'major')
                        TextField(
                          controller: lifeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t.fixedAssetsRemainingLife),
                        ),
                      DropdownButtonFormField<String>(
                        value: cp,
                        decoration: InputDecoration(labelText: t.fixedAssetsCounterparty),
                        items: [
                          DropdownMenuItem(value: 'person', child: Text(t.fixedAssetsCounterpartyPerson)),
                          DropdownMenuItem(value: 'bank', child: Text(t.fixedAssetsCounterpartyBank)),
                          DropdownMenuItem(value: 'cash_register', child: Text(t.fixedAssetsCounterpartyCash)),
                          DropdownMenuItem(value: 'petty_cash', child: Text(t.fixedAssetsCounterpartyPetty)),
                          DropdownMenuItem(value: 'account', child: Text(t.fixedAssetsCounterpartyAccount)),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => cp = v);
                        },
                      ),
                      TextField(
                        controller: idCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: t.fixedAssetsCounterpartyId),
                      ),
                      const SizedBox(height: 8),
                      DateInputField(
                        value: expDate,
                        calendarController: widget.calendarController,
                        labelText: t.fixedAssetsAcquisitionDate,
                        onChanged: (d) {
                          if (d != null) setLocal(() => expDate = d);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final payload = <String, dynamic>{
      'kind': kind,
      'amount': amountCtrl.text.trim(),
      'vat_amount': vatCtrl.text.trim(),
      'expenditure_date': _isoDate(expDate),
      ..._counterpartyPayload(cp, idCtrl.text),
    };
    if (kind == 'major' && lifeCtrl.text.trim().isNotEmpty) {
      payload['remaining_useful_life_months'] = int.tryParse(lifeCtrl.text.trim());
    }
    try {
      await _svc.postSubsequentExpenditure(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsExpenditurePosted);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _estimateChange(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    String method = '${asset['method'] ?? 'straight_line'}';
    final lifeCtrl = TextEditingController(text: '${asset['useful_life_months'] ?? ''}');
    final rateCtrl = TextEditingController(text: '${asset['declining_annual_rate'] ?? ''}');
    DateTime effective = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.fixedAssetsEstimateChange),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.fixedAssetsEstimateHint),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: method,
                        items: const [
                          DropdownMenuItem(value: 'straight_line', child: Text('straight_line')),
                          DropdownMenuItem(value: 'declining_balance', child: Text('declining_balance')),
                        ],
                        onChanged: (v) {
                          if (v != null) setLocal(() => method = v);
                        },
                      ),
                      if (method == 'straight_line')
                        TextField(
                          controller: lifeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t.fixedAssetsRemainingLife),
                        ),
                      if (method == 'declining_balance')
                        TextField(
                          controller: rateCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t.fixedAssetsUsefulLifeMonths),
                        ),
                      const SizedBox(height: 8),
                      DateInputField(
                        value: effective,
                        calendarController: widget.calendarController,
                        labelText: t.fixedAssetsDisposalDate,
                        onChanged: (d) {
                          if (d != null) setLocal(() => effective = d);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final payload = <String, dynamic>{
      'method': method,
      'effective_date': _isoDate(effective),
    };
    if (method == 'straight_line') {
      payload['remaining_useful_life_months'] = int.tryParse(lifeCtrl.text.trim());
    } else {
      payload['declining_annual_rate'] = rateCtrl.text.trim();
    }
    try {
      await _svc.changeEstimate(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsEstimateSaved);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _markIdle(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    DateTime idleFrom = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(t.fixedAssetsMarkIdle),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.fixedAssetsIdleHint),
                    const SizedBox(height: 12),
                    DateInputField(
                      value: idleFrom,
                      calendarController: widget.calendarController,
                      labelText: t.fixedAssetsIdleFrom,
                      onChanged: (d) {
                        if (d != null) setLocal(() => idleFrom = d);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    try {
      await _svc.setAssetIdle(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: {'idle_from': _isoDate(idleFrom)},
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsIdleSaved);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _resume(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    try {
      await _svc.resumeAsset(businessId: widget.businessId, assetId: int.parse('${asset['id']}'));
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.fixedAssetsResumed);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.fixedAssetsMenu),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: t.fixedAssetsSettingsTab,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'settings/fixed-assets'),
              ),
            ),
          IconButton(tooltip: t.refresh, icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.fixedAssetsAssetsTab),
            Tab(text: t.fixedAssetsDepreciationTab),
            Tab(text: t.fixedAssetsSettingsTab),
          ],
        ),
      ),
      floatingActionButton: _canOperate && _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _createAsset,
              icon: const Icon(Icons.add),
              label: Text(t.fixedAssetsNewAsset),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _assetsTab(t),
                _runsTab(t),
                _settingsTab(t),
              ],
            ),
    );
  }

  Widget _assetsTab(AppLocalizations t) {
    final counts = Map<String, dynamic>.from(_dashboard['counts'] as Map? ?? const {});
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('${t.fixedAssetsCost}: ${formatWithThousands(_dashboard['cost_total'])}')),
            Chip(label: Text('${t.fixedAssetsNetBookValue}: ${formatWithThousands(_dashboard['net_book_value'])}')),
            Chip(label: Text('${t.fixedAssetsStatusDraft}: ${counts['draft'] ?? 0}')),
            Chip(label: Text('${t.fixedAssetsStatusCapitalized}: ${counts['capitalized'] ?? 0}')),
            Chip(label: Text('${t.fixedAssetsStatusIdle}: ${counts['idle'] ?? 0}')),
            Chip(label: Text('${t.fixedAssetsStatusDisposed}: ${counts['disposed'] ?? 0}')),
          ],
        ),
        const SizedBox(height: 12),
        if (_assets.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.fixedAssetsNoAssets))),
        for (final a in _assets)
          Card(
            child: ListTile(
              title: Text('${a['code']} — ${a['name']}'),
              subtitle: Text(
                '${a['class_name'] ?? ''} · ${_statusLabel(t, a['status'])} · ${t.fixedAssetsCost} ${formatWithThousands(a['cost'])}'
                '${a['status'] == 'idle' ? ' · tax ${a['tax_idle_factor']}' : ''}',
              ),
              trailing: _assetTrailing(t, a),
            ),
          ),
      ],
    );
  }

  Widget _runsTab(AppLocalizations t) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_canOperate)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _createRun,
              icon: const Icon(Icons.calculate_outlined),
              label: Text(t.fixedAssetsNewDepreciationRun),
            ),
          ),
        const SizedBox(height: 12),
        if (_runs.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.fixedAssetsNoRuns))),
        for (final r in _runs)
          Card(
            child: ListTile(
              title: Text('${r['period_year']}/${r['period_month']}'),
              subtitle: Text('${r['status']} · ${formatWithThousands(r['total_amount'])}'),
              trailing: r['status'] == 'draft' && _canPost
                  ? TextButton(
                      onPressed: () => _postRun(r),
                      child: Text(t.fixedAssetsPostRun),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _settingsTab(AppLocalizations t) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.fixedAssetsLegalRulesHint),
        const SizedBox(height: 8),
        Text(
          '${t.fixedAssetsConventionHint}\n'
          '${t.fixedAssetsTaxIdleMonths}: ${_settings['tax_idle_months'] ?? 6} · '
          '${t.fixedAssetsTaxIdleReduction}: ${_settings['tax_idle_factor'] ?? '0.7'}',
        ),
        const SizedBox(height: 12),
        if (_canManage || widget.authStore.hasBusinessPermission('fixed_assets', 'view'))
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'settings/fixed-assets'),
              ),
              icon: const Icon(Icons.settings_outlined),
              label: Text(t.fixedAssetsOpenFullSettings),
            ),
          ),
        const SizedBox(height: 16),
        Text(t.fixedAssetsClassesHint, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final c in _classes)
          ListTile(
            title: Text('${c['name']} (${c['code']})'),
            subtitle: Text(
              '${c['cost_account_code'] ?? ''} / ${c['accum_dep_account_code'] ?? '-'} / ${c['dep_expense_account_code'] ?? '-'}',
            ),
            trailing: c['depreciable'] == true ? null : Text(t.fixedAssetsNotDepreciable),
          ),
      ],
    );
  }
}
