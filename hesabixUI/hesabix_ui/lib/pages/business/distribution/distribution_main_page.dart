import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart' as Hd;
import '../../../l10n/app_localizations.dart';
import '../../../services/distribution_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart' show SnackBarHelper;
import '../../../widgets/jalali_date_picker.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// افزونه پخش مویرگی — داشبورد، برنامه روز، مسیرها، ویزیت، مرجوعی.
class DistributionMainPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const DistributionMainPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<DistributionMainPage> createState() => _DistributionMainPageState();
}

class _DistributionMainPageState extends State<DistributionMainPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DistributionService _svc = DistributionService();

  Map<String, dynamic> _summary = {};
  DateTime _planDay = DateTime.now();
  Map<String, dynamic>? _dailyPlan;
  List<dynamic> _routes = [];
  List<dynamic> _territories = [];
  Map<int, List<dynamic>> _stopsByRoute = {};
  Map<String, dynamic>? _visitListPayload;
  List<dynamic> _returns = [];

  bool _loadingSummary = false;
  bool _loadingPlan = false;
  bool _loadingRoutes = false;
  bool _loadingVisits = false;
  bool _loadingReturns = false;

  bool get _canOperate =>
      widget.authStore.hasBusinessPermission('distribution', 'operate') ||
      widget.authStore.hasBusinessPermission('distribution', 'manage');

  bool get _canManage => widget.authStore.hasBusinessPermission('distribution', 'manage');

  bool get _canView => widget.authStore.hasBusinessPermission('distribution', 'view');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTab(_tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTab(0));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTab(int index) async {
    switch (index) {
      case 0:
        await _refreshSummary();
        break;
      case 1:
        await _refreshPlan();
        break;
      case 2:
        await _refreshRoutesMaster();
        break;
      case 3:
        await _refreshVisits();
        break;
      case 4:
        await _refreshReturns();
        break;
    }
  }

  bool get _jalali => widget.calendarController.isJalali;

  Future<void> _pickPlanDay() async {
    final d = await showAdaptiveDatePicker(
      context: context,
      calendarController: widget.calendarController,
      initialDate: _planDay,
      helpText: AppLocalizations.of(context).distributionSelectDate,
    );
    if (d != null) {
      setState(() => _planDay = d);
      await _refreshPlan();
    }
  }

  Future<void> _refreshSummary() async {
    if (!_canView) return;
    setState(() => _loadingSummary = true);
    try {
      final d = await _svc.getSummary(businessId: widget.businessId);
      if (mounted) setState(() => _summary = d);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _refreshPlan() async {
    if (!_canView) return;
    setState(() => _loadingPlan = true);
    try {
      final iso =
          '${_planDay.year.toString().padLeft(4, '0')}-${_planDay.month.toString().padLeft(2, '0')}-${_planDay.day.toString().padLeft(2, '0')}';
      final d = await _svc.getDailyPlan(businessId: widget.businessId, planDate: iso);
      if (mounted) setState(() => _dailyPlan = d);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingPlan = false);
    }
  }

  Future<void> _refreshRoutesMaster() async {
    if (!_canView) return;
    setState(() => _loadingRoutes = true);
    try {
      final t = await _svc.listTerritories(businessId: widget.businessId);
      final r = await _svc.listRoutes(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _territories = t;
          _routes = r;
          _stopsByRoute.clear();
        });
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingRoutes = false);
    }
  }

  Future<void> _loadStops(int routeId) async {
    try {
      final s = await _svc.listRouteStops(businessId: widget.businessId, routeId: routeId);
      if (mounted) setState(() => _stopsByRoute[routeId] = s);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _refreshVisits() async {
    if (!_canView) return;
    setState(() => _loadingVisits = true);
    try {
      final d = await _svc.listVisits(businessId: widget.businessId, limit: 80, skip: 0);
      if (mounted) setState(() => _visitListPayload = d);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingVisits = false);
    }
  }

  Future<void> _refreshReturns() async {
    if (!_canView) return;
    setState(() => _loadingReturns = true);
    try {
      final r = await _svc.listReturnRequests(businessId: widget.businessId);
      if (mounted) setState(() => _returns = r);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingReturns = false);
    }
  }

  Future<void> _startVisitFromPlan(Map<String, dynamic> item) async {
    if (!_canOperate) return;
    try {
      final res = await _svc.startVisit(
        businessId: widget.businessId,
        payload: <String, dynamic>{
          'person_id': item['person_id'],
          'route_id': item['route_id'],
          'route_stop_id': item['stop_id'],
        },
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: '${AppLocalizations.of(context).distributionStartVisit}: #${res['id']}',
      );
      await _showCompleteVisitSheet(int.parse('${res['id']}'));
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _showCompleteVisitSheet(int visitId) async {
    final t = AppLocalizations.of(context);
    String outcome = 'order';
    final docCtl = TextEditingController();
    final dealCtl = TextEditingController();
    final reasonCtl = TextEditingController();
    final noteCtl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 8,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.distributionCompleteVisit, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: outcome,
                    decoration: InputDecoration(labelText: t.distributionCompleteVisit),
                    items: [
                      DropdownMenuItem(value: 'order', child: Text(t.distributionOutcomeOrder)),
                      DropdownMenuItem(value: 'no_order', child: Text(t.distributionOutcomeNoOrder)),
                      DropdownMenuItem(value: 'cancelled', child: Text(t.distributionOutcomeCancelled)),
                    ],
                    onChanged: (v) => setModal(() => outcome = v ?? 'order'),
                  ),
                  TextField(
                    controller: docCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.distributionDocumentIdHint),
                  ),
                  TextField(
                    controller: dealCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t.distributionDealIdHint),
                  ),
                  if (outcome == 'no_order')
                    TextField(
                      controller: reasonCtl,
                      decoration: InputDecoration(labelText: t.distributionNoOrderReason),
                    ),
                  TextField(
                    controller: noteCtl,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: t.distributionNotesLabel),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final payload = <String, dynamic>{
                        'outcome': outcome,
                        if (docCtl.text.trim().isNotEmpty) 'document_id': int.tryParse(docCtl.text.trim()),
                        if (dealCtl.text.trim().isNotEmpty) 'deal_id': int.tryParse(dealCtl.text.trim()),
                        if (noteCtl.text.trim().isNotEmpty) 'notes': noteCtl.text.trim(),
                        if (outcome == 'no_order' && reasonCtl.text.trim().isNotEmpty)
                          'no_order_reason': reasonCtl.text.trim(),
                      };
                      try {
                        await _svc.completeVisit(
                          businessId: widget.businessId,
                          visitId: visitId,
                          payload: payload,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          SnackBarHelper.showSuccess(context, message: t.distributionCompleteVisit);
                          await _refreshPlan();
                          await _refreshSummary();
                          await _refreshVisits();
                        }
                      } catch (e) {
                        if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                      }
                    },
                    child: Text(t.distributionCompleteVisit),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showCreateTerritoryDialog() async {
    final codeCtl = TextEditingController();
    final nameCtl = TextEditingController();
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionTabRoutes),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codeCtl, decoration: const InputDecoration(labelText: 'Code')),
            TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Name')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(
            onPressed: () async {
              try {
                await _svc.createTerritory(
                  businessId: widget.businessId,
                  payload: {'code': codeCtl.text.trim(), 'name': nameCtl.text.trim()},
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _refreshRoutesMaster();
              } catch (e) {
                if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateRouteDialog() async {
    final codeCtl = TextEditingController();
    final nameCtl = TextEditingController();
    int? territoryId;
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) {
          return AlertDialog(
            title: Text(t.distributionTabRoutes),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: codeCtl, decoration: const InputDecoration(labelText: 'Code')),
                  TextField(controller: nameCtl, decoration: const InputDecoration(labelText: 'Name')),
                  DropdownButtonFormField<int?>(
                    value: territoryId,
                    decoration: const InputDecoration(labelText: 'Territory (optional)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('—')),
                      ..._territories.map<DropdownMenuItem<int?>>((e) {
                        final m = Map<String, dynamic>.from(e as Map);
                        return DropdownMenuItem<int?>(
                          value: m['id'] as int?,
                          child: Text('${m['code']} ${m['name']}'),
                        );
                      }),
                    ],
                    onChanged: (v) => setD(() => territoryId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
              FilledButton(
                onPressed: () async {
                  try {
                    await _svc.createRoute(
                      businessId: widget.businessId,
                      payload: <String, dynamic>{
                        'code': codeCtl.text.trim(),
                        'name': nameCtl.text.trim(),
                        if (territoryId != null) 'territory_id': territoryId,
                      },
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _refreshRoutesMaster();
                  } catch (e) {
                    if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddStopDialog(int routeId) async {
    final personCtl = TextEditingController();
    final sortCtl = TextEditingController(text: '0');
    int? weekday;
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) {
          return AlertDialog(
            title: const Text('Stop'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: personCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'person_id'),
                ),
                TextField(
                  controller: sortCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'sort_order'),
                ),
                DropdownButtonFormField<int?>(
                  value: weekday,
                  decoration: const InputDecoration(labelText: 'Weekday (ISO 0=Mon, empty=any)'),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Any')),
                    ...List.generate(7, (i) => DropdownMenuItem<int?>(value: i, child: Text('$i'))),
                  ],
                  onChanged: (v) => setD(() => weekday = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
              FilledButton(
                onPressed: () async {
                  try {
                    await _svc.upsertStop(
                      businessId: widget.businessId,
                      routeId: routeId,
                      payload: <String, dynamic>{
                        'person_id': int.parse(personCtl.text.trim()),
                        'sort_order': int.tryParse(sortCtl.text.trim()) ?? 0,
                        'weekday': weekday,
                      },
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadStops(routeId);
                  } catch (e) {
                    if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAssignmentDialog(int routeId) async {
    final userCtl = TextEditingController();
    final t = AppLocalizations.of(context);
    DateTime from = DateTime.now();
    DateTime? to;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) {
          return AlertDialog(
            title: const Text('Assignment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: userCtl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'user_id'),
                ),
                ListTile(
                  title: Text(Hd.HesabixDateUtils.formatForDisplay(from, _jalali)),
                  subtitle: Text('valid_from'),
                  onTap: () async {
                    final d = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: from,
                    );
                    if (d != null) setD(() => from = d);
                  },
                ),
                ListTile(
                  title: Text(to == null ? 'valid_to (optional)' : Hd.HesabixDateUtils.formatForDisplay(to!, _jalali)),
                  onTap: () async {
                    final d = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: to ?? from,
                    );
                    setD(() => to = d);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
              FilledButton(
                onPressed: () async {
                  try {
                    await _svc.createAssignment(
                      businessId: widget.businessId,
                      payload: <String, dynamic>{
                        'route_id': routeId,
                        'user_id': int.parse(userCtl.text.trim()),
                        'valid_from':
                            '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
                        if (to != null)
                          'valid_to':
                              '${to!.year}-${to!.month.toString().padLeft(2, '0')}-${to!.day.toString().padLeft(2, '0')}',
                      },
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) SnackBarHelper.showSuccess(context, message: 'OK');
                  } catch (e) {
                    if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showReturnDialog() async {
    final personCtl = TextEditingController();
    final jsonCtl = TextEditingController(text: '[{"product_id":1,"quantity":1,"reason":""}]');
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionReturnCreate),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: personCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'person_id'),
              ),
              TextField(
                controller: jsonCtl,
                maxLines: 5,
                decoration: InputDecoration(labelText: t.distributionLinesJson),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(
            onPressed: () async {
              try {
                final lines = jsonDecode(jsonCtl.text) as List<dynamic>;
                await _svc.createReturnRequest(
                  businessId: widget.businessId,
                  payload: <String, dynamic>{
                    'person_id': int.parse(personCtl.text.trim()),
                    'lines': lines,
                  },
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _refreshReturns();
              } catch (e) {
                if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
              }
            },
            child: Text(t.distributionReturnCreate),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveReturn(int id) async {
    if (!_canManage) return;
    final t = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionCompleteVisit),
        content: const Text('Approve or reject this return request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                await _svc.resolveReturnRequest(
                  businessId: widget.businessId,
                  requestId: id,
                  payload: {'status': 'rejected'},
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _refreshReturns();
              } catch (e) {
                if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
              }
            },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _svc.resolveReturnRequest(
                  businessId: widget.businessId,
                  requestId: id,
                  payload: {'status': 'approved'},
                );
                if (ctx.mounted) Navigator.pop(ctx);
                await _refreshReturns();
              } catch (e) {
                if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
              }
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canView) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t.distributionMenu),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: Center(child: Text(t.accessDenied)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.distributionMenu),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          IconButton(
            tooltip: t.distributionRefresh,
            onPressed: () => _loadTab(_tabController.index),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: t.distributionTabDashboard),
            Tab(text: t.distributionTabToday),
            Tab(text: t.distributionTabRoutes),
            Tab(text: t.distributionTabVisits),
            Tab(text: t.distributionTabReturns),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _dashboardTab(t),
          _todayTab(t),
          _routesTab(t),
          _visitsTab(t),
          _returnsTab(t),
        ],
      ),
    );
  }

  Widget _dashboardTab(AppLocalizations t) {
    if (_loadingSummary) return const Center(child: CircularProgressIndicator());
    final cs = Theme.of(context).colorScheme;
    Widget card(String title, String value, IconData icon) {
      return Card(
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.labelMedium),
                    Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshSummary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          card(t.distributionVisitsToday, '${_summary['visits_today'] ?? 0}', Icons.route),
          const SizedBox(height: 8),
          card(t.distributionCompletedToday, '${_summary['completed_visits_today'] ?? 0}', Icons.check_circle_outline),
          const SizedBox(height: 8),
          card(t.distributionPendingReturns, '${_summary['pending_return_requests'] ?? 0}', Icons.assignment_return),
          const SizedBox(height: 8),
          card(t.distributionActiveRoutes, '${_summary['active_routes'] ?? 0}', Icons.map_outlined),
          const SizedBox(height: 24),
          if (_canManage && _summary['distribution_settings'] is Map<String, dynamic>) ...[
            Builder(
              builder: (ctx) {
                final ds = _summary['distribution_settings'] as Map<String, dynamic>;
                Future<void> persist(Map<String, dynamic> patch) async {
                  try {
                    await _svc.updateDistributionSettings(
                      businessId: widget.businessId,
                      payload: <String, dynamic>{
                        'shared_routing_catalog': ds['shared_routing_catalog'] == true,
                        'require_visit_in_daily_plan': ds['require_visit_in_daily_plan'] == true,
                        ...patch,
                      },
                    );
                    if (!mounted) return;
                    SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
                    await _refreshSummary();
                  } catch (e) {
                    if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      title: Text(t.distributionSharedRoutingCatalog),
                      subtitle: Text(t.distributionSharedRoutingCatalogHint),
                      value: ds['shared_routing_catalog'] == true,
                      onChanged: (v) => persist({'shared_routing_catalog': v}),
                    ),
                    SwitchListTile(
                      title: Text(t.distributionRequireVisitInDailyPlan),
                      subtitle: Text(t.distributionRequireVisitInDailyPlanHint),
                      value: ds['require_visit_in_daily_plan'] == true,
                      onChanged: (v) => persist({'require_visit_in_daily_plan': v}),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          Text(
            'CRM & Workflow',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            t.localeName.startsWith('fa')
                ? 'پس از پایان ویزیت، فعالیت یادداشت در CRM ثبت می‌شود و می‌توانید در اتوماسیون‌ها از تریگر «تکمیل ویزیت میدانی» استفاده کنید.'
                : 'Closing a visit logs a CRM note activity and fires the workflow trigger «distribution.visit.completed».',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _todayTab(AppLocalizations t) {
    return Column(
      children: [
        Material(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _pickPlanDay,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(Hd.HesabixDateUtils.formatForDisplay(_planDay, _jalali)),
                ),
                const Spacer(),
                if (_canOperate)
                  Text(
                    t.distributionStartVisit,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loadingPlan
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refreshPlan,
                  child: Builder(
                    builder: (context) {
                      final items = (_dailyPlan?['items'] as List?) ?? [];
                      if (items.isEmpty) {
                        return ListView(
                          children: [
                            const SizedBox(height: 48),
                            Center(child: Text(t.distributionNoPlan)),
                          ],
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final item = Map<String, dynamic>.from(items[i] as Map);
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${item['sort_order'] ?? ''}')),
                              title: Text('${item['person_name'] ?? item['person_id']}'),
                              subtitle: Text(
                                '${item['route_code'] ?? ''} · ${item['route_name'] ?? ''}',
                              ),
                              trailing: _canOperate
                                  ? FilledButton(
                                      onPressed: () => _startVisitFromPlan(item),
                                      child: Text(t.distributionStartVisit),
                                    )
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _routesTab(AppLocalizations t) {
    return Column(
      children: [
        if (_canManage)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                FilledButton.tonal(
                  onPressed: _showCreateTerritoryDialog,
                  child: const Text('Territory'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _showCreateRouteDialog,
                  child: const Text('Route'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loadingRoutes
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refreshRoutesMaster,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _routes.length,
                    itemBuilder: (ctx, i) {
                      final r = Map<String, dynamic>.from(_routes[i] as Map);
                      final rid = r['id'] as int;
                      return ExpansionTile(
                        leading: const Icon(Icons.alt_route),
                        title: Text('${r['code']} — ${r['name']}'),
                        subtitle: Text('${r['territory_name'] ?? '—'}'),
                        onExpansionChanged: (ex) {
                          if (ex) _loadStops(rid);
                        },
                        children: [
                          if (_canManage)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showAddStopDialog(rid),
                                    icon: const Icon(Icons.add_location_alt),
                                    label: const Text('Stop'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _showAssignmentDialog(rid),
                                    icon: const Icon(Icons.person_add_alt),
                                    label: const Text('Assign'),
                                  ),
                                ],
                              ),
                            ),
                          ...(_stopsByRoute[rid] ?? []).map(
                            (s) {
                              final m = Map<String, dynamic>.from(s as Map);
                              return ListTile(
                                dense: true,
                                title: Text('${m['person_name'] ?? m['person_id']}'),
                                subtitle: Text('order ${m['sort_order']} · day ${m['weekday'] ?? 'any'}'),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _visitsTab(AppLocalizations t) {
    if (_loadingVisits) return const Center(child: CircularProgressIndicator());
    final items = (_visitListPayload?['items'] as List?) ?? [];
    return RefreshIndicator(
      onRefresh: _refreshVisits,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final v = Map<String, dynamic>.from(items[i] as Map);
          return Card(
            child: ListTile(
              title: Text(v['person_name']?.toString() ?? '${v['person_id']}'),
              subtitle: Text(
                '${v['status']} · ${v['outcome'] ?? ''}\n'
                '${Hd.HesabixDateUtils.formatDateTime(_parseDt(v['started_at']), _jalali)}',
              ),
              isThreeLine: true,
              trailing: v['status'] == 'in_progress' && _canOperate
                  ? IconButton(
                      icon: const Icon(Icons.check_circle),
                      onPressed: () => _showCompleteVisitSheet(int.parse('${v['id']}')),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  DateTime? _parseDt(dynamic s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s.toString());
    } catch (_) {
      return null;
    }
  }

  Widget _returnsTab(AppLocalizations t) {
    if (_loadingReturns) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        if (_canOperate)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _showReturnDialog,
                icon: const Icon(Icons.assignment_return),
                label: Text(t.distributionReturnCreate),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshReturns,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _returns.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final r = Map<String, dynamic>.from(_returns[i] as Map);
                return Card(
                  child: ListTile(
                    title: Text('#${r['id']} · person ${r['person_id']}'),
                    subtitle: Text('${r['status']} · ${jsonEncode(r['lines'])}'),
                    trailing: r['status'] == 'pending' && _canManage
                        ? TextButton(
                            onPressed: () => _resolveReturn(int.parse('${r['id']}')),
                            child: Text(t.distributionCompleteVisit),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
