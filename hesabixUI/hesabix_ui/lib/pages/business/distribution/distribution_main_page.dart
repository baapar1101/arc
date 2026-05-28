import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart' as Hd;
import '../../../l10n/app_localizations.dart';
import '../../../models/person_model.dart';
import '../../../services/distribution_service.dart';
import '../../../services/distribution_offline_queue.dart';
import '../../../utils/distribution_location_helper.dart';
import 'distribution_team_map_page.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart' show SnackBarHelper;
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/distribution/distribution_map_marker.dart';
import '../../../widgets/distribution/distribution_memaps_map.dart';
import '../../../widgets/distribution/distribution_person_location_sheet.dart';
import '../../../widgets/distribution/distribution_return_dialog.dart';
import '../../../widgets/distribution/distribution_visit_sheet.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';
import '../../../widgets/jalali_date_picker.dart';

/// افزونه پخش مویرگی — تجربه میدانی و مدیریت مسیر.
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

class _DistributionMainPageState extends State<DistributionMainPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DistributionService _svc = DistributionService();
  final DistributionOfflineQueue _offlineQueue = DistributionOfflineQueue();
  int _offlinePending = 0;
  bool _enableVanSales = false;
  List<dynamic> _checklistTemplate = [];
  List<dynamic>? _optimizedPlanItems;

  Map<String, dynamic> _summary = {};
  DateTime _planDay = DateTime.now();
  int? _teamTargetUserId;
  Map<String, dynamic>? _dailyPlan;
  List<dynamic> _routes = [];
  List<dynamic> _territories = [];
  final Map<int, List<dynamic>> _stopsByRoute = {};
  Map<String, dynamic>? _visitListPayload;
  List<dynamic> _returns = [];
  Map<String, dynamic>? _activeVisit;

  bool _loadingSummary = false;
  bool _loadingPlan = false;
  bool _loadingRoutes = false;
  bool _loadingVisits = false;
  bool _loadingReturns = false;

  bool get _jalali => widget.calendarController.isJalali;
  bool get _canOperate =>
      widget.authStore.hasBusinessPermission('distribution', 'operate') ||
      widget.authStore.hasBusinessPermission('distribution', 'manage');
  bool get _canManage => widget.authStore.hasBusinessPermission('distribution', 'manage');
  bool get _canView => widget.authStore.hasBusinessPermission('distribution', 'view');
  bool get _canTeam =>
      widget.authStore.hasBusinessPermission('distribution', 'manage') ||
      widget.authStore.hasBusinessPermission('distribution', 'reports_team');

  int get _tabCount {
    var n = 3;
    if (_canOperate) n++;
    if (_canManage) n++;
    return n;
  }

  List<String> get _tabKeys {
    final keys = <String>['field', 'visits', 'returns'];
    if (_canOperate) keys.add('van');
    if (_canManage) keys.add('manage');
    return keys;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadTab(_tabController.index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshOfflineCount();
      await _loadTab(0);
    });
  }

  Future<void> _refreshOfflineCount() async {
    final n = (await _offlineQueue.peek(widget.businessId)).length;
    if (mounted) setState(() => _offlinePending = n);
  }

  void _applySettingsFromSummary() {
    final ds = _summary['distribution_settings'];
    if (ds is Map<String, dynamic>) {
      _enableVanSales = ds['enable_van_sales'] == true;
      final tpl = ds['visit_checklist_template'];
      _checklistTemplate = tpl is List ? tpl : [];
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadTab(int index) async {
    final keys = _tabKeys;
    if (index < 0 || index >= keys.length) return;
    switch (keys[index]) {
      case 'field':
        await Future.wait([_refreshSummary(), _refreshPlan(), _refreshVisits(detectActiveOnly: true)]);
        break;
      case 'visits':
        await _refreshVisits();
        break;
      case 'returns':
        await _refreshReturns();
        break;
      case 'van':
        break;
      case 'manage':
        await _refreshRoutesMaster();
        break;
    }
  }

  Future<void> _refreshSummary() async {
    if (!_canView) return;
    setState(() => _loadingSummary = true);
    try {
      final d = await _svc.getSummary(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _summary = d;
          _applySettingsFromSummary();
        });
      }
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
      final d = await _svc.getDailyPlan(
        businessId: widget.businessId,
        planDate: _iso(_planDay),
        targetUserId: _teamTargetUserId,
      );
      if (mounted) setState(() {
        _dailyPlan = d;
        _optimizedPlanItems = null;
      });
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

  Future<void> _refreshVisits({bool detectActiveOnly = false}) async {
    if (!_canView) return;
    if (!detectActiveOnly) setState(() => _loadingVisits = true);
    try {
      final d = await _svc.listVisits(businessId: widget.businessId, limit: 80, skip: 0);
      if (mounted) {
        final items = (d['items'] as List?) ?? [];
        Map<String, dynamic>? active;
        for (final raw in items) {
          final v = Map<String, dynamic>.from(raw as Map);
          if (v['status'] == 'in_progress') {
            active = v;
            break;
          }
        }
        setState(() {
          _visitListPayload = d;
          _activeVisit = active;
        });
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted && !detectActiveOnly) setState(() => _loadingVisits = false);
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

  Future<void> _openCompleteSheet(int visitId, int? personId) async {
    await showDistributionVisitCompleteSheet(
      context: context,
      businessId: widget.businessId,
      visitId: visitId,
      personId: personId,
      service: _svc,
      checklistTemplate: _checklistTemplate,
      enableVanSales: _enableVanSales,
      onCompleted: () async {
        await _refreshPlan();
        await _refreshSummary();
        await _refreshVisits();
      },
    );
  }

  Future<void> _enqueueOffline(String op, Map<String, dynamic> payload, {required String clientRef}) async {
    await _offlineQueue.enqueue(widget.businessId, {
      'op': op,
      'client_ref': clientRef,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _refreshOfflineCount();
    if (mounted) {
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).distributionOfflinePending,
      );
    }
  }

  Future<void> _syncOffline() async {
    final t = AppLocalizations.of(context);
    try {
      await _offlineQueue.sync(widget.businessId);
      await _refreshOfflineCount();
      await _refreshSummary();
      await _refreshVisits();
      if (mounted) SnackBarHelper.showSuccess(context, message: t.distributionOfflineSynced);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  List<DistributionMapMarker> _planMapMarkers(List<dynamic> items) {
    return items
        .map((raw) => DistributionMapMarker.tryFromPayload(Map<String, dynamic>.from(raw as Map)))
        .whereType<DistributionMapMarker>()
        .toList();
  }

  Future<void> _setPersonLocationFromPlan(Map<String, dynamic> item) async {
    final personId = int.tryParse('${item['person_id']}');
    if (personId == null) return;
    final saved = await showDistributionPersonLocationSheet(
      context: context,
      businessId: widget.businessId,
      personId: personId,
      personName: item['person_name']?.toString() ?? '$personId',
      distributionService: _svc,
      initialLat: double.tryParse('${item['latitude']}'),
      initialLng: double.tryParse('${item['longitude']}'),
    );
    if (saved == true) {
      await _refreshPlan();
    }
  }

  Future<void> _optimizePlanRoute() async {
    final items = (_dailyPlan?['items'] as List?) ?? [];
    if (items.isEmpty) return;
    final routeId = items.first is Map ? (items.first as Map)['route_id'] : null;
    if (routeId == null) return;
    final t = AppLocalizations.of(context);
    try {
      final loc = await readDistributionVisitLocation();
      final data = await _svc.optimizeRoute(
        businessId: widget.businessId,
        routeId: int.parse('$routeId'),
        planDate: _iso(_planDay),
        startLatitude: loc.latitude,
        startLongitude: loc.longitude,
      );
      if (mounted) {
        setState(() => _optimizedPlanItems = (data['items'] as List?) ?? items);
        SnackBarHelper.showSuccess(context, message: t.distributionOptimizeRoute);
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _startVisitFromPlan(Map<String, dynamic> item) async {
    if (!_canOperate) return;
    if (_activeVisit != null) {
      SnackBarHelper.showError(context, message: AppLocalizations.of(context).distributionActiveVisitBanner);
      return;
    }
    final t = AppLocalizations.of(context);
    if (mounted) {
      SnackBarHelper.show(context, message: t.distributionLocationCapturing);
    }
    final loc = await readDistributionVisitLocation();
    final payload = <String, dynamic>{
      'person_id': item['person_id'],
      'route_id': item['route_id'],
      'route_stop_id': item['stop_id'],
      if (loc.latitude != null) 'start_latitude': loc.latitude,
      if (loc.longitude != null) 'start_longitude': loc.longitude,
    };
    try {
      final res = await _svc.startVisit(businessId: widget.businessId, payload: payload);
      if (!mounted) return;
      final msg = loc.latitude != null ? t.distributionLocationCaptured : t.distributionLocationSkipped;
      SnackBarHelper.showSuccess(
        context,
        message: '${t.distributionStartVisit}: #${res['id']} — $msg',
      );
      await _refreshVisits(detectActiveOnly: true);
      await _openCompleteSheet(int.parse('${res['id']}'), int.tryParse('${item['person_id']}'));
    } catch (e) {
      final err = ErrorExtractor.forContext(e, context);
      if (err.contains('GEOFENCE') || err.contains('فاصله')) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text(t.distributionGeofenceOverride),
            content: Text(err),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t.cancel)),
              FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(t.distributionStartVisit)),
            ],
          ),
        );
        if (ok == true) {
          payload['geofence_override'] = true;
          try {
            final res = await _svc.startVisit(businessId: widget.businessId, payload: payload);
            if (!mounted) return;
            await _refreshVisits(detectActiveOnly: true);
            await _openCompleteSheet(int.parse('${res['id']}'), int.tryParse('${item['person_id']}'));
          } catch (e2) {
            await _enqueueOffline('start_visit', payload, clientRef: 'start_${item['person_id']}');
          }
        }
      } else {
        await _enqueueOffline('start_visit', payload, clientRef: 'start_${item['person_id']}');
        if (mounted) SnackBarHelper.showError(context, message: err);
      }
    }
  }

  Future<void> _cancelActiveVisit() async {
    final v = _activeVisit;
    if (v == null || !_canOperate) return;
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionCancelVisit),
        content: Text(t.distributionCancelVisitConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.distributionCancelVisit)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.cancelVisit(
        businessId: widget.businessId,
        visitId: int.parse('${v['id']}'),
        reason: t.distributionCancelVisit,
      );
      await _refreshVisits();
      await _refreshSummary();
      if (mounted) SnackBarHelper.showSuccess(context, message: t.distributionCancelVisit);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String _visitStatusLabel(AppLocalizations t, String? status) {
    switch (status) {
      case 'in_progress':
        return t.distributionStatusInProgress;
      case 'completed':
        return t.distributionStatusCompleted;
      case 'cancelled':
        return t.distributionStatusCancelled;
      default:
        return status ?? '';
    }
  }

  static const _weekdayLabelsFa = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
  static const _weekdayLabelsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _weekdayLabel(AppLocalizations t, int? wd) {
    if (wd == null) return t.distributionWeekdayAny;
    final labels = t.localeName.startsWith('fa') ? _weekdayLabelsFa : _weekdayLabelsEn;
    if (wd >= 0 && wd < labels.length) return labels[wd];
    return '$wd';
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

    final tabs = <Tab>[
      Tab(text: t.distributionTabField, icon: const Icon(Icons.today_outlined)),
      Tab(text: t.distributionTabVisits, icon: const Icon(Icons.place_outlined)),
      Tab(text: t.distributionTabReturns, icon: const Icon(Icons.assignment_return_outlined)),
      if (_canOperate) Tab(text: t.distributionTabVan, icon: const Icon(Icons.local_shipping)),
      if (_canManage) Tab(text: t.distributionTabManage, icon: const Icon(Icons.alt_route)),
    ];

    final tabChildren = <Widget>[
      _fieldTab(t),
      _visitsTab(t),
      _returnsTab(t),
      if (_canOperate) _vanTab(t),
      if (_canManage) _manageTab(t),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(t.distributionMenu),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          if (_canTeam)
            IconButton(
              tooltip: t.distributionTabTeamMap,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DistributionTeamMapPage(
                    businessId: widget.businessId,
                    calendarController: widget.calendarController,
                    canManageLocations: _canManage,
                  ),
                ),
              ),
              icon: const Icon(Icons.map_outlined),
            ),
          if (_offlinePending > 0)
            IconButton(
              tooltip: t.distributionOfflineSync,
              onPressed: _syncOffline,
              icon: Badge(label: Text('$_offlinePending'), child: const Icon(Icons.cloud_sync_outlined)),
            ),
          IconButton(
            tooltip: t.distributionRefresh,
            onPressed: () => _loadTab(_tabController.index),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: tabs,
        ),
      ),
      floatingActionButton: _tabKeys[_tabController.index] == 'returns' && _canOperate
          ? FloatingActionButton.extended(
              onPressed: () => showDistributionReturnDialog(
                context: context,
                businessId: widget.businessId,
                service: _svc,
                onSubmitted: _refreshReturns,
              ),
              icon: const Icon(Icons.assignment_return),
              label: Text(t.distributionReturnCreate),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: tabChildren,
      ),
    );
  }

  Widget _fieldTab(AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async {
        await _refreshSummary();
        await _refreshPlan();
        await _refreshVisits(detectActiveOnly: true);
      },
      child: CustomScrollView(
        slivers: [
          if (_activeVisit != null)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                color: cs.primaryContainer.withValues(alpha: 0.35),
                child: ListTile(
                  leading: Icon(Icons.timelapse, color: cs.primary),
                  title: Text(t.distributionActiveVisitBanner),
                  subtitle: Text(
                    '${_activeVisit!['person_name'] ?? _activeVisit!['person_id']} · '
                    '${_visitStatusLabel(t, _activeVisit!['status']?.toString())}',
                  ),
                  trailing: _canOperate
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: t.distributionCompleteVisit,
                              icon: const Icon(Icons.check_circle),
                              onPressed: () => _openCompleteSheet(
                                int.parse('${_activeVisit!['id']}'),
                                int.tryParse('${_activeVisit!['person_id']}'),
                              ),
                            ),
                            IconButton(
                              tooltip: t.distributionCancelVisit,
                              icon: const Icon(Icons.cancel_outlined),
                              onPressed: _cancelActiveVisit,
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loadingSummary
                  ? const LinearProgressIndicator()
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metricChip(t.distributionVisitsToday, '${_summary['visits_today'] ?? 0}', Icons.route),
                        _metricChip(
                          t.distributionCompletedToday,
                          '${_summary['completed_visits_today'] ?? 0}',
                          Icons.check_circle_outline,
                        ),
                        _metricChip(
                          t.distributionPendingReturns,
                          '${_summary['pending_return_requests'] ?? 0}',
                          Icons.assignment_return,
                        ),
                        _metricChip(
                          t.distributionActiveRoutes,
                          '${_summary['active_routes'] ?? 0}',
                          Icons.map_outlined,
                        ),
                      ],
                    ),
            ),
          ),
          if (_canManage && _summary['distribution_settings'] is Map<String, dynamic>)
            SliverToBoxAdapter(child: _settingsSection(t)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final d = await showAdaptiveDatePicker(
                        context: context,
                        calendarController: widget.calendarController,
                        initialDate: _planDay,
                        helpText: t.distributionSelectDate,
                      );
                      if (d != null) {
                        setState(() => _planDay = d);
                        await _refreshPlan();
                      }
                    },
                    icon: const Icon(Icons.calendar_month),
                    label: Text(Hd.HesabixDateUtils.formatForDisplay(_planDay, _jalali)),
                  ),
                  if (_canOperate)
                  TextButton.icon(
                    onPressed: _loadingPlan ? null : _optimizePlanRoute,
                    icon: const Icon(Icons.route_outlined),
                    label: Text(t.distributionOptimizeRoute),
                  ),
                const Spacer(),
                  if (_canTeam)
                    SizedBox(
                      width: 120,
                      child: TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: t.distributionTeamPlanUserId,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (v) async {
                          setState(() => _teamTargetUserId = int.tryParse(v.trim()));
                          await _refreshPlan();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_offlinePending > 0)
            SliverToBoxAdapter(
              child: MaterialBanner(
                content: Text('${t.distributionOfflinePending}: $_offlinePending'),
                actions: [
                  TextButton(onPressed: _syncOffline, child: Text(t.distributionOfflineSync)),
                ],
              ),
            ),
          if (_loadingPlan)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else
            Builder(
              builder: (context) {
                final items = (_optimizedPlanItems ?? (_dailyPlan?['items'] as List?)) ?? [];
                if (items.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text(t.distributionNoPlan)),
                  );
                }
                final planMarkers = _planMapMarkers(items);
                return SliverMainAxisGroup(
                  slivers: [
                    if (planMarkers.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: DistributionMemapsMap(markers: planMarkers, height: 220),
                        ),
                      ),
                    SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final item = Map<String, dynamic>.from(items[i] as Map);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Card(
                        elevation: 0,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${item['sort_order'] ?? i + 1}'),
                          ),
                          title: Text('${item['person_name'] ?? item['person_id']}'),
                          subtitle: Text('${item['route_code'] ?? ''} · ${item['route_name'] ?? ''}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_canManage)
                                IconButton(
                                  icon: Icon(
                                    item['latitude'] != null ? Icons.edit_location_alt : Icons.add_location_alt_outlined,
                                  ),
                                  tooltip: t.distributionSetPersonLocation,
                                  onPressed: () => _setPersonLocationFromPlan(item),
                                ),
                              if (_canOperate && _activeVisit == null)
                                FilledButton(
                                  onPressed: () => _startVisitFromPlan(item),
                                  child: Text(t.distributionStartVisit),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                  ],
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
    );
  }

  Widget _settingsSection(AppLocalizations t) {
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
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
          SwitchListTile(
            title: Text(t.distributionEnableVanSales),
            value: ds['enable_van_sales'] == true,
            onChanged: (v) => persist({'enable_van_sales': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionRequireGeofence),
            subtitle: Text(t.distributionGeofenceRadius),
            value: ds['require_geofence'] == true,
            onChanged: (v) => persist({'require_geofence': v}),
          ),
          ListTile(
            title: Text(t.distributionGeofenceRadius),
            subtitle: Text('${ds['geofence_radius_meters'] ?? 0} m'),
            trailing: SizedBox(
              width: 72,
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                controller: TextEditingController(text: '${ds['geofence_radius_meters'] ?? 200}'),
                onSubmitted: (v) {
                  final n = int.tryParse(v.trim());
                  if (n != null && n >= 0) persist({'geofence_radius_meters': n});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vanTab(AppLocalizations t) {
    return _VanStockPanel(
      businessId: widget.businessId,
      service: _svc,
      enableVanSales: _enableVanSales,
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
          final status = v['status']?.toString();
          return Card(
            child: ListTile(
              leading: Icon(
                status == 'completed'
                    ? Icons.check_circle
                    : status == 'cancelled'
                        ? Icons.cancel
                        : Icons.timelapse,
              ),
              title: Text(v['person_name']?.toString() ?? '${v['person_id']}'),
              subtitle: Text(
                '${_visitStatusLabel(t, status)} · ${v['outcome'] ?? ''}\n'
                '${Hd.HesabixDateUtils.formatDateTime(_parseDt(v['started_at']), _jalali)}',
              ),
              isThreeLine: true,
              trailing: status == 'in_progress' && _canOperate
                  ? IconButton(
                      icon: const Icon(Icons.check_circle),
                      onPressed: () => _openCompleteSheet(
                        int.parse('${v['id']}'),
                        int.tryParse('${v['person_id']}'),
                      ),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _returnsTab(AppLocalizations t) {
    if (_loadingReturns) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _refreshReturns,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: _returns.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final r = Map<String, dynamic>.from(_returns[i] as Map);
          final lines = (r['lines'] as List?) ?? [];
          return Card(
            child: ExpansionTile(
              leading: Icon(
                r['status'] == 'pending' ? Icons.hourglass_top : Icons.assignment_return,
              ),
              title: Text('#${r['id']} · ${t.distributionSelectPerson} ${r['person_id']}'),
              subtitle: Text('${r['status']} · ${lines.length} ${t.distributionReturnAddLine}'),
              children: [
                ...lines.map((ln) {
                  final m = Map<String, dynamic>.from(ln as Map);
                  return ListTile(
                    dense: true,
                    title: Text(m['product_name']?.toString() ?? 'product ${m['product_id']}'),
                    subtitle: Text('× ${m['quantity']} ${m['reason'] ?? ''}'),
                  );
                }),
                if (r['status'] == 'pending' && _canManage)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _resolveReturn(int.parse('${r['id']}'), 'rejected'),
                            child: Text(t.distributionRejectReturn),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _resolveReturn(int.parse('${r['id']}'), 'approved'),
                            child: Text(t.distributionApproveReturn),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _resolveReturn(int id, String status) async {
    final t = AppLocalizations.of(context);
    try {
      await _svc.resolveReturnRequest(
        businessId: widget.businessId,
        requestId: id,
        payload: {'status': status},
      );
      await _refreshReturns();
      if (mounted) SnackBarHelper.showSuccess(context, message: t.distributionResolveReturnTitle);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _manageTab(AppLocalizations t) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _showCreateTerritoryDialog(t),
                icon: const Icon(Icons.map_outlined),
                label: Text(t.distributionTerritoryCreate),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => _showCreateRouteDialog(t),
                icon: const Icon(Icons.add_road),
                label: Text(t.distributionRouteCreate),
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
                      return Card(
                        child: ExpansionTile(
                          leading: const Icon(Icons.alt_route),
                          title: Text('${r['code']} — ${r['name']}'),
                          subtitle: Text('${r['territory_name'] ?? '—'}'),
                          onExpansionChanged: (ex) {
                            if (ex) _loadStops(rid);
                          },
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _showAddStopDialog(t, rid),
                                    icon: const Icon(Icons.add_location_alt),
                                    label: Text(t.distributionAddStop),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _showAssignmentDialog(t, rid),
                                    icon: const Icon(Icons.person_add_alt),
                                    label: Text(t.distributionAssignVisitor),
                                  ),
                                  IconButton(
                                    tooltip: t.distributionDeleteRoute,
                                    onPressed: () => _confirmDeleteRoute(t, rid),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                            ...(_stopsByRoute[rid] ?? []).map((s) {
                              final m = Map<String, dynamic>.from(s as Map);
                              return ListTile(
                                dense: true,
                                title: Text('${m['person_name'] ?? m['person_id']}'),
                                subtitle: Text(
                                  '${t.distributionSortOrder} ${m['sort_order']} · '
                                  '${t.distributionWeekdayLabel}: ${_weekdayLabel(t, m['weekday'] as int?)}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit_location_alt_outlined),
                                  tooltip: t.distributionSetPersonLocation,
                                  onPressed: () async {
                                    final personId = int.tryParse('${m['person_id']}');
                                    if (personId == null) return;
                                    final saved = await showDistributionPersonLocationSheet(
                                      context: context,
                                      businessId: widget.businessId,
                                      personId: personId,
                                      personName: m['person_name']?.toString() ?? '$personId',
                                      distributionService: _svc,
                                    );
                                    if (saved == true) await _loadStops(rid);
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteRoute(AppLocalizations t, int routeId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionDeleteRoute),
        content: Text(t.distributionDeleteRouteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.distributionDeleteRoute)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.deleteRoute(businessId: widget.businessId, routeId: routeId);
      await _refreshRoutesMaster();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _showCreateTerritoryDialog(AppLocalizations t) async {
    final codeCtl = TextEditingController();
    final nameCtl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.distributionTerritoryCreate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtl,
              decoration: InputDecoration(labelText: t.distributionTerritoryCode, border: const OutlineInputBorder()),
            ),
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(labelText: t.distributionTerritoryName, border: const OutlineInputBorder()),
            ),
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
            child: Text(t.save),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateRouteDialog(AppLocalizations t) async {
    final codeCtl = TextEditingController();
    final nameCtl = TextEditingController();
    int? territoryId;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionRouteCreate),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtl,
                  decoration: InputDecoration(labelText: t.distributionRouteCode, border: const OutlineInputBorder()),
                ),
                TextField(
                  controller: nameCtl,
                  decoration: InputDecoration(labelText: t.distributionRouteName, border: const OutlineInputBorder()),
                ),
                DropdownButtonFormField<int?>(
                  value: territoryId,
                  decoration: InputDecoration(labelText: t.distributionTerritoryName, border: const OutlineInputBorder()),
                  items: [
                    DropdownMenuItem<int?>(value: null, child: Text('—')),
                    ..._territories.map<DropdownMenuItem<int?>>((e) {
                      final m = Map<String, dynamic>.from(e as Map);
                      return DropdownMenuItem<int?>(value: m['id'] as int?, child: Text('${m['code']} ${m['name']}'));
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
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddStopDialog(AppLocalizations t, int routeId) async {
    Person? person;
    final sortCtl = TextEditingController(text: '0');
    int? weekday;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionAddStop),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: person,
                label: t.distributionSelectPerson,
                onChanged: (p) => setD(() => person = p),
              ),
              TextField(
                controller: sortCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t.distributionSortOrder, border: const OutlineInputBorder()),
              ),
              DropdownButtonFormField<int?>(
                value: weekday,
                decoration: InputDecoration(labelText: t.distributionWeekdayLabel, border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(t.distributionWeekdayAny)),
                  ...List.generate(
                    7,
                    (i) => DropdownMenuItem<int?>(value: i, child: Text(_weekdayLabel(t, i))),
                  ),
                ],
                onChanged: (v) => setD(() => weekday = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                if (person == null) return;
                try {
                  await _svc.upsertStop(
                    businessId: widget.businessId,
                    routeId: routeId,
                    payload: <String, dynamic>{
                      'person_id': person!.id,
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
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignmentDialog(AppLocalizations t, int routeId) async {
    final userCtl = TextEditingController();
    DateTime from = DateTime.now();
    DateTime? to;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionAssignVisitor),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'user_id',
                  border: OutlineInputBorder(),
                ),
              ),
              ListTile(
                title: Text(Hd.HesabixDateUtils.formatForDisplay(from, _jalali)),
                subtitle: const Text('valid_from'),
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
                title: Text(to == null ? 'valid_to' : Hd.HesabixDateUtils.formatForDisplay(to!, _jalali)),
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
                      'valid_from': _iso(from),
                      if (to != null) 'valid_to': _iso(to!),
                    },
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
                } catch (e) {
                  if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                }
              },
              child: Text(t.save),
            ),
          ],
        ),
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
}

/// موجودی ون ویزیتور — بارگیری برای مدیر از تب مدیریت.
class _VanStockPanel extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final bool enableVanSales;

  const _VanStockPanel({
    required this.businessId,
    required this.service,
    required this.enableVanSales,
  });

  @override
  State<_VanStockPanel> createState() => _VanStockPanelState();
}

class _VanStockPanelState extends State<_VanStockPanel> {
  Map<String, dynamic>? _stock;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await widget.service.getMyVanStock(businessId: widget.businessId);
      if (mounted) setState(() => _stock = d);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.enableVanSales) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.distributionEnableVanSales, textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading && _stock == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final vanId = _stock?['van_id'];
    final items = (_stock?['items'] as List?) ?? [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (vanId == null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(t.distributionVanStock),
                subtitle: const Text('—'),
              ),
            )
          else
            Text('${t.distributionVanStock} · #${vanId}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...items.map((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            return Card(
              child: ListTile(
                title: Text(m['product_name']?.toString() ?? 'product ${m['product_id']}'),
                trailing: Text('× ${m['quantity'] ?? 0}'),
              ),
            );
          }),
          if (items.isEmpty && vanId != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(t.distributionVanStock)),
            ),
        ],
      ),
    );
  }
}
