import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/distribution_map_tiles.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/distribution_service.dart';
import '../../../services/distribution_offline_queue.dart';
import '../../../services/distribution_offline_catalog.dart';
import '../../../utils/distribution_location_helper.dart';
import 'distribution_field_tab.dart';
import 'distribution_manage_tab.dart';
import 'distribution_returns_tab.dart';
import 'distribution_team_map_page.dart';
import 'distribution_visits_tab.dart';
import '../distribution_reports_dashboard_page.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart' show SnackBarHelper;
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/distribution/distribution_setup_plan_sheet.dart';
import '../../../widgets/distribution/distribution_setup_wizard_sheet.dart';
import '../../../widgets/distribution/distribution_new_outlet_sheet.dart';
import '../../../widgets/distribution/distribution_person_location_sheet.dart';
import '../../../widgets/distribution/distribution_return_dialog.dart';
import '../../../widgets/distribution/distribution_field_helpers.dart';
import '../../../widgets/distribution/distribution_visit_sheet.dart';
import '../../../widgets/distribution/distribution_van_panel.dart';
import '../../../widgets/distribution/distribution_settlement_panel.dart';
import '../../../widgets/distribution/distribution_commercial_panel.dart';
import '../../../core/api_client.dart';
import '../../../models/business_user_model.dart';
import '../../../services/business_user_service.dart';
import '../../../services/bytes_export/bytes_export_service.dart';

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

class _DistributionMainPageState extends State<DistributionMainPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final GlobalKey<DistributionManageTabState> _manageKey = GlobalKey<DistributionManageTabState>();
  final DistributionService _svc = DistributionService();
  Timer? _heartbeatTimer;
  final DistributionOfflineQueue _offlineQueue = DistributionOfflineQueue();
  int _offlinePending = 0;
  bool _enableVanSales = false;
  bool _enablePresell = false;
  bool _enablePromotions = false;
  bool _enableSuggestedOrder = true;
  bool _shareLiveLocation = false;
  bool _requireLocationConsent = true;
  bool _locationConsent = false;
  String _workspace = 'field';
  bool _planPublished = false;
  bool _planLocked = false;
  bool _autoApplyPromotions = true;
  bool _requirePodSignature = false;
  bool _requirePodPhoto = false;
  bool _enablePerfectStore = true;
  bool _setupCompleted = true;
  String _navProvider = 'neshan';
  Map<String, dynamic>? _scorecard;
  bool? _liveGpsOk;
  final TextEditingController _memapsKeyCtl = TextEditingController();
  List<dynamic> _checklistTemplate = [];
  List<dynamic>? _optimizedPlanItems;

  Map<String, dynamic> _summary = {};
  DateTime _planDay = DateTime.now();
  int? _teamTargetUserId;
  Map<String, dynamic>? _dailyPlan;
  Map<String, dynamic>? _visitListPayload;
  List<dynamic> _returns = [];
  Map<String, dynamic>? _activeVisit;

  bool _loadingSummary = false;
  bool _loadingPlan = false;
  bool _loadingVisits = false;
  bool _loadingReturns = false;
  bool _returnsPendingOnly = true;

  bool get _jalali => widget.calendarController.isJalali;
  bool get _canOperate =>
      widget.authStore.hasBusinessPermission('distribution', 'operate') ||
      widget.authStore.hasBusinessPermission('distribution', 'manage');
  bool get _canManage => widget.authStore.hasBusinessPermission('distribution', 'manage');
  bool get _canApproveReturns =>
      widget.authStore.hasBusinessPermission('distribution', 'approve_returns') || _canManage;
  bool get _canView => widget.authStore.hasBusinessPermission('distribution', 'view');
  bool get _canTeam =>
      widget.authStore.hasBusinessPermission('distribution', 'manage') ||
      widget.authStore.hasBusinessPermission('distribution', 'reports_team');

  int get _tabCount => _tabKeys.length;

  List<String> get _tabKeys {
    final keys = <String>[];
    if (_canOperate) {
      keys.addAll(['field', 'visits', 'returns']);
      keys.add('settlement');
      if (_enableVanSales) keys.add('van');
      if (_enablePresell || _canManage) keys.add('commercial');
    } else {
      keys.addAll(['visits', 'returns']);
    }
    if (_canManage) keys.add('manage');
    return keys;
  }

  void _syncTabController() {
    final n = _tabKeys.length;
    if (_tabController.length == n) return;
    final oldIndex = _tabController.index.clamp(0, n - 1);
    _tabController.dispose();
    _tabController = TabController(length: n, vsync: this, initialIndex: oldIndex);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadTab(_tabController.index);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadTab(_tabController.index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshOfflineCount();
      await _refreshSummary();
      await _loadTab(0);
      _startLiveHeartbeat();
    });
  }

  void _startLiveHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) => _sendLiveHeartbeat(preferCached: true));
    _sendLiveHeartbeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLiveHeartbeat();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _heartbeatTimer?.cancel();
    }
  }

  Future<void> _sendLiveHeartbeat({bool preferCached = false}) async {
    if (!_canOperate || !_shareLiveLocation) return;
    if (_requireLocationConsent && !_locationConsent) return;
    if (_activeVisit == null) return;
    try {
      final loc = await readDistributionVisitLocation(preferCached: preferCached);
      if (loc.latitude == null || loc.longitude == null) {
        if (mounted && _liveGpsOk != false) setState(() => _liveGpsOk = false);
        return;
      }
      if (mounted && _liveGpsOk != true) setState(() => _liveGpsOk = true);
      final visitId = int.tryParse('${_activeVisit?['id']}');
      await _svc.reportLiveLocation(
        businessId: widget.businessId,
        latitude: loc.latitude!,
        longitude: loc.longitude!,
        visitId: visitId,
      );
    } catch (_) {
      // silent — موقعیت زنده بهترین‌تلاش است
    }
  }

  Future<void> _refreshOfflineCount() async {
    final uid = widget.authStore.currentUserId;
    if (uid == null) {
      if (mounted) setState(() => _offlinePending = 0);
      return;
    }
    final n = (await _offlineQueue.peek(widget.businessId, userId: uid)).length;
    if (mounted) setState(() => _offlinePending = n);
  }

  void _applySettingsFromSummary() {
    final ds = _summary['distribution_settings'];
    if (ds is Map<String, dynamic>) {
      _enableVanSales = ds['enable_van_sales'] == true;
      _enablePresell = ds['enable_presell'] == true;
      _enablePromotions = ds['enable_promotions'] == true;
      _enableSuggestedOrder = ds['enable_suggested_order'] != false;
      _shareLiveLocation = ds['share_live_location'] == true;
      _requireLocationConsent = ds['require_location_consent'] != false;
      _autoApplyPromotions = ds['auto_apply_promotions'] != false;
      _requirePodSignature = ds['require_pod_signature'] == true;
      _requirePodPhoto = ds['require_pod_photo'] == true;
      _enablePerfectStore = ds['enable_perfect_store'] != false;
      _setupCompleted = ds['setup_completed'] == true;
      _navProvider = (ds['nav_provider'] ?? 'neshan').toString();
      final tpl = ds['visit_checklist_template'];
      _checklistTemplate = tpl is List ? tpl : [];
      final key = (ds['memaps_api_key'] ?? '').toString();
      if (key.isNotEmpty && _memapsKeyCtl.text != key) {
        _memapsKeyCtl.text = key;
      }
    }
    _locationConsent = _summary['location_consent'] == true;
    final ws = (_summary['workspace'] ?? '').toString();
    if (ws.isNotEmpty) _workspace = ws;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _tabController.dispose();
    _memapsKeyCtl.dispose();
    super.dispose();
  }

  DistributionMapTileConfig get _mapTiles {
    final ds = _summary['distribution_settings'];
    return DistributionMapTileConfig.fromSettings(ds is Map<String, dynamic> ? ds : null);
  }

  String _iso(DateTime d) => distributionIsoDate(d);

  Future<void> _loadTab(int index) async {
    final keys = _tabKeys;
    if (index < 0 || index >= keys.length) return;
    switch (keys[index]) {
      case 'field':
        await Future.wait([
          _refreshSummary(),
          _refreshPlan(),
          _refreshVisits(detectActiveOnly: true),
          _refreshScorecard(),
        ]);
        if (_canManage && !_setupCompleted && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          final t = AppLocalizations.of(context);
          SnackBarHelper.show(context, message: t.distributionSetupNeeded);
        }
        break;
      case 'visits':
        await _refreshVisits();
        break;
      case 'returns':
        await _refreshReturns();
        break;
      case 'settlement':
        break;
      case 'van':
        break;
      case 'commercial':
        break;
      case 'manage':
        await _manageKey.currentState?.reload();
        break;
    }
  }

  Future<void> _refreshScorecard() async {
    if (!_canView) return;
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      final d = await _svc.getScorecard(
        businessId: widget.businessId,
        fromDate: _iso(from),
        toDate: _iso(now),
        targetUserId: _teamTargetUserId,
      );
      if (mounted) setState(() => _scorecard = d['kpi'] is Map ? Map<String, dynamic>.from(d['kpi'] as Map) : d);
    } catch (_) {}
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
        _syncTabController();
        if (mounted) setState(() {});
        unawaited(_sendLiveHeartbeat());
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
        _planPublished = d['published'] == true;
        _planLocked = d['locked'] == true;
      });
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingPlan = false);
    }
  }

  void _goToManage() {
    final i = _tabKeys.indexOf('manage');
    if (i >= 0) _tabController.animateTo(i);
  }

  Future<void> _openSetupPlan(AppLocalizations t) async {
    if (!_canManage) return;
    List<dynamic> routes = const [];
    try {
      routes = await _svc.listRoutes(businessId: widget.businessId);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      return;
    }
    if (!mounted) return;
    if (routes.isEmpty) {
      SnackBarHelper.show(context, message: t.distributionNoRoutesYet);
      _goToManage();
      return;
    }
    final userId = await showDistributionSetupPlanSheet(
      context: context,
      businessId: widget.businessId,
      service: _svc,
      calendarController: widget.calendarController,
      routes: routes,
      planDate: _planDay,
    );
    if (userId == null || !mounted) return;
    setState(() => _teamTargetUserId = userId);
    SnackBarHelper.showSuccess(context, message: t.distributionPlanAssigned);
    await _refreshPlan();
  }

  Future<void> _refreshVisits({bool detectActiveOnly = false}) async {
    if (!_canView) return;
    if (!detectActiveOnly) setState(() => _loadingVisits = true);
    try {
      final d = await _svc.listVisits(businessId: widget.businessId, limit: 80, skip: 0);
      if (mounted) {
        final items = (d['items'] as List?) ?? [];
        Map<String, dynamic>? active;
        final myId = widget.authStore.currentUserId;
        for (final raw in items) {
          final v = Map<String, dynamic>.from(raw as Map);
          if (v['status'] != 'in_progress') continue;
          final owner = int.tryParse('${v['user_id']}');
          if (myId != null && owner != null && owner != myId) continue;
          active = v;
          break;
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
      enablePresell: _enablePresell,
      enableSuggestedOrder: _enableSuggestedOrder,
      enablePromotions: _enablePromotions,
      autoApplyPromotions: _autoApplyPromotions,
      requirePodSignature: _requirePodSignature,
      requirePodPhoto: _requirePodPhoto,
      enablePerfectStore: _enablePerfectStore,
      navProvider: _navProvider,
      onOfflineEnqueue: (payload) {
        final hint = payload['op_hint']?.toString();
        if (hint == 'complete_visit_with_presell') {
          final p = Map<String, dynamic>.from(payload)..remove('op_hint');
          return _enqueueOffline(
            'complete_visit_with_presell',
            p,
            clientRef: 'presell_visit_$visitId',
          );
        }
        if (hint == 'create_presell_order') {
          final p = Map<String, dynamic>.from(payload)..remove('op_hint');
          return _enqueueOffline('create_presell_order', p, clientRef: 'presell_$visitId');
        }
        return _enqueueOffline(
          'complete_visit',
          payload,
          clientRef: 'complete_$visitId',
        );
      },
      onCompleted: () async {
        await _refreshPlan();
        await _refreshSummary();
        await _refreshVisits();
      },
    );
  }

  Future<void> _enqueueOffline(String op, Map<String, dynamic> payload, {required String clientRef}) async {
    final uid = widget.authStore.currentUserId;
    if (uid == null) return;
    await _offlineQueue.enqueue(widget.businessId, {
      'op': op,
      'client_ref': clientRef,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    }, userId: uid);
    await _refreshOfflineCount();
    if (mounted) {
      SnackBarHelper.showSuccess(
        context,
        message: AppLocalizations.of(context).distributionOfflineQueued,
      );
    }
  }

  Future<void> _showOfflineQueueSheet() async {
    final t = AppLocalizations.of(context);
    final uid = widget.authStore.currentUserId;
    final items = uid == null
        ? <Map<String, dynamic>>[]
        : await _offlineQueue.peek(widget.businessId, userId: uid);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.distributionOfflineQueueTitle, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(t.distributionOfflineSynced, textAlign: TextAlign.center),
                  )
                else
                  ...items.map((m) {
                    final op = m['op']?.toString() ?? '—';
                    final at = m['created_at']?.toString() ?? '';
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.cloud_queue_outlined),
                      title: Text(op),
                      subtitle: Text(at),
                    );
                  }),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _syncOffline();
                    },
                    icon: const Icon(Icons.cloud_sync_outlined),
                    label: Text(t.distributionOfflineSync),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncOffline() async {
    final t = AppLocalizations.of(context);
    try {
      final uid = widget.authStore.currentUserId;
      if (uid == null) return;
      final res = await _offlineQueue.sync(widget.businessId, userId: uid);
      await _refreshOfflineCount();
      await _refreshSummary();
      await _refreshVisits();
      if (!mounted) return;
      final remaining = res['remaining'] as int? ?? 0;
      if (remaining > 0) {
        SnackBarHelper.showError(context, message: t.distributionOfflinePartial);
      } else {
        SnackBarHelper.showSuccess(context, message: t.distributionOfflineSynced);
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
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
      tileConfig: _mapTiles,
    );
    if (saved == true) {
      await _refreshPlan();
    }
  }

  Future<void> _printDailyPlan() async {
    final t = AppLocalizations.of(context);
    try {
      final bytes = await _svc.downloadDailyPlanPdf(
        businessId: widget.businessId,
        planDate: _iso(_planDay),
        targetUserId: _teamTargetUserId,
      );
      await BytesExportService.export(
        bytes: bytes,
        filename: 'distribution_daily_plan_${_iso(_planDay)}.pdf',
        mimeType: 'application/pdf',
      );
      if (mounted) SnackBarHelper.showSuccess(context, message: t.distributionPdfExported);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
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
        persist: _canManage,
      );
      if (mounted) {
        setState(() => _optimizedPlanItems = (data['items'] as List?) ?? items);
        SnackBarHelper.showSuccess(
          context,
          message: data['persisted'] == true ? t.distributionApplyOptimize : t.distributionOptimizeRoute,
        );
        if (data['persisted'] == true) {
          await _refreshPlan();
        }
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<int?> _pickSupervisorIfWanted() async {
    final t = AppLocalizations.of(context);
    List<BusinessUser> users = const [];
    try {
      users = (await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId)).users;
    } catch (_) {
      return null;
    }
    if (!mounted || users.isEmpty) return null;
    int? selected;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionJointVisit),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.distributionJointVisitHint),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionSupervisor,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ...users
                      .where((u) => u.userId != widget.authStore.currentUserId)
                      .map(
                        (u) => DropdownMenuItem<int?>(
                          value: u.userId,
                          child: Text(u.userName.isNotEmpty ? u.userName : '${u.userId}'),
                        ),
                      ),
                ],
                onChanged: (v) => setD(() => selected = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.distributionStartVisit)),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    return selected;
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
      if (item['carried_over'] == true) 'is_carried_over': true,
      if (loc.latitude != null) 'start_latitude': loc.latitude,
      if (loc.longitude != null) 'start_longitude': loc.longitude,
    };
    if (_canManage) {
      final users = await _pickSupervisorIfWanted();
      if (users != null) payload['supervisor_user_id'] = users;
    }
    try {
      final res = await _svc.startVisit(businessId: widget.businessId, payload: payload);
      if (!mounted) return;
      final msg = loc.latitude != null ? t.distributionLocationCaptured : t.distributionLocationSkipped;
      SnackBarHelper.showSuccess(
        context,
        message: '${t.distributionStartVisit}: #${res['id']} — $msg\n${t.distributionVisitStayHint}',
      );
      await _refreshVisits(detectActiveOnly: true);
    } catch (e) {
      final err = ErrorExtractor.forContext(e, context);
      if (err.contains('GEOFENCE') || err.contains('فاصله')) {
        if (!_canManage) {
          if (mounted) {
            SnackBarHelper.showError(context, message: '$err\n${t.distributionGeofenceOverrideManageOnly}');
          }
          return;
        }
        final reasonCtl = TextEditingController();
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text(t.distributionGeofenceOverride),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(err),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t.distributionGeofenceOverrideReason,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t.cancel)),
              FilledButton(
                onPressed: () {
                  if (reasonCtl.text.trim().length < 3) return;
                  Navigator.pop(dctx, true);
                },
                child: Text(t.distributionStartVisit),
              ),
            ],
          ),
        );
        if (ok == true) {
          payload['geofence_override'] = true;
          payload['geofence_override_reason'] = reasonCtl.text.trim();
          try {
            await _svc.startVisit(businessId: widget.businessId, payload: payload);
            if (!mounted) return;
            SnackBarHelper.showSuccess(context, message: t.distributionVisitStayHint);
            await _refreshVisits(detectActiveOnly: true);
          } catch (e2) {
            await _enqueueOffline('start_visit', payload, clientRef: 'start_${item['person_id']}');
            if (mounted) {
              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e2, context));
            }
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
      await _enqueueOffline(
        'cancel_visit',
        {'visit_id': v['id'], 'reason': t.distributionCancelVisit},
        clientRef: 'cancel_${v['id']}',
      );
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _grantLocationConsent() async {
    try {
      await _svc.updateMyPreferences(
        businessId: widget.businessId,
        payload: const {'location_consent': true},
      );
      if (mounted) setState(() => _locationConsent = true);
      unawaited(_sendLiveHeartbeat());
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _revokeLocationConsent() async {
    try {
      await _svc.updateMyPreferences(
        businessId: widget.businessId,
        payload: const {'location_consent': false},
      );
      if (mounted) setState(() => _locationConsent = false);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _togglePublishPlan() async {
    try {
      if (_planPublished) {
        await _svc.unpublishDailyPlan(
          businessId: widget.businessId,
          planDate: _iso(_planDay),
          targetUserId: _teamTargetUserId,
        );
      } else {
        await _svc.publishDailyPlan(
          businessId: widget.businessId,
          payload: <String, dynamic>{
            'plan_date': _iso(_planDay),
            if (_teamTargetUserId != null) 'target_user_id': _teamTargetUserId,
            'locked': true,
          },
        );
      }
      await _refreshPlan();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _publishAllAssignedPlans() async {
    final t = AppLocalizations.of(context);
    try {
      final data = await _svc.publishDailyPlan(
        businessId: widget.businessId,
        payload: <String, dynamic>{
          'plan_date': _iso(_planDay),
          'all_assigned': true,
          'locked': true,
        },
      );
      await _refreshPlan();
      if (!mounted) return;
      final count = int.tryParse('${data['published_count']}') ?? 0;
      SnackBarHelper.showSuccess(
        context,
        message: count == 0 ? t.distributionPlanPublishAllEmpty : t.distributionPlanPublishAllDone,
      );
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _openReports() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DistributionReportsDashboardPage(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          canSelectVisitor: _canTeam,
        ),
      ),
    );
  }

  void _openTeamMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DistributionTeamMapPage(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          canManageLocations: _canManage,
        ),
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

    final tabs = <Tab>[
      if (_canOperate) Tab(text: t.distributionTabField, icon: const Icon(Icons.today_outlined)),
      Tab(text: t.distributionTabVisits, icon: const Icon(Icons.place_outlined)),
      Tab(text: t.distributionTabReturns, icon: const Icon(Icons.assignment_return_outlined)),
      if (_canOperate) Tab(text: t.distributionTabSettlement, icon: const Icon(Icons.account_balance_wallet_outlined)),
      if (_canOperate && _enableVanSales) Tab(text: t.distributionTabVan, icon: const Icon(Icons.local_shipping)),
      if (_canOperate && (_enablePresell || _canManage))
        Tab(text: t.distributionTabCommercial, icon: const Icon(Icons.storefront_outlined)),
      if (_canManage) Tab(text: t.distributionTabManage, icon: const Icon(Icons.alt_route)),
    ];

    final tabChildren = <Widget>[
      if (_canOperate)
        DistributionFieldTab(
          t: t,
          calendarController: widget.calendarController,
          service: _svc,
          businessId: widget.businessId,
          data: DistributionFieldTabData(
            planDay: _planDay,
            teamTargetUserId: _teamTargetUserId,
            dailyPlan: _dailyPlan,
            optimizedPlanItems: _optimizedPlanItems,
            summary: _summary,
            scorecard: _scorecard,
            activeVisit: _activeVisit,
            visitListPayload: _visitListPayload,
            loadingPlan: _loadingPlan,
            loadingSummary: _loadingSummary,
            offlinePending: _offlinePending,
            shareLiveLocation: _shareLiveLocation,
            requireLocationConsent: _requireLocationConsent,
            locationConsent: _locationConsent,
            liveGpsOk: _liveGpsOk,
            planPublished: _planPublished,
            planLocked: _planLocked,
            setupCompleted: _setupCompleted,
            canOperate: _canOperate,
            canManage: _canManage,
            canTeam: _canTeam,
            navProvider: _navProvider,
            mapTiles: _mapTiles,
          ),
          actions: DistributionFieldTabActions(
            onRefresh: () async {
              await _refreshSummary();
              await _refreshPlan();
              await _refreshVisits(detectActiveOnly: true);
            },
            onPlanDayChanged: (d) async {
              setState(() => _planDay = d);
              await _refreshPlan();
            },
            onTeamTargetChanged: (v) async {
              setState(() => _teamTargetUserId = v);
              await _refreshPlan();
            },
            onGrantConsent: _grantLocationConsent,
            onRevokeConsent: _revokeLocationConsent,
            onTogglePublish: _togglePublishPlan,
            onPublishAll: _publishAllAssignedPlans,
            onCompleteVisit: _openCompleteSheet,
            onCancelVisit: _cancelActiveVisit,
            onStartVisit: _startVisitFromPlan,
            onSetupPlan: () => _openSetupPlan(t),
            onGoToManage: _goToManage,
            onOptimize: _optimizePlanRoute,
            onPrintPlan: _printDailyPlan,
            onOpenTeamMap: _openTeamMap,
            onOpenReports: _openReports,
            onSetPersonLocation: _setPersonLocationFromPlan,
            onShowOfflineQueue: _showOfflineQueueSheet,
            onOpenSetupWizard: () async {
              final ok = await showDistributionSetupWizard(
                context: context,
                businessId: widget.businessId,
                service: _svc,
              );
              if (ok) {
                await _refreshSummary();
                await _refreshPlan();
              }
            },
          ),
        ),
      DistributionVisitsTab(
        t: t,
        jalali: _jalali,
        loading: _loadingVisits,
        canOperate: _canOperate,
        visitListPayload: _visitListPayload,
        onRefresh: () => _refreshVisits(),
        onGoToField: () => _tabController.animateTo(0),
        onCompleteVisit: _openCompleteSheet,
      ),
      DistributionReturnsTab(
        t: t,
        loading: _loadingReturns,
        pendingOnly: _returnsPendingOnly,
        canApproveReturns: _canApproveReturns,
        returns: _returns,
        onPendingOnlyChanged: (v) => setState(() => _returnsPendingOnly = v),
        onRefresh: _refreshReturns,
        onResolve: _resolveReturn,
      ),
      if (_canOperate)
        DistributionSettlementPanel(
          businessId: widget.businessId,
          service: _svc,
          calendarController: widget.calendarController,
          canManage: _canManage,
          canSettle: widget.authStore.hasBusinessPermission('distribution', 'settle') || _canManage,
          currentUserId: widget.authStore.currentUserId,
        ),
      if (_canOperate && _enableVanSales)
        DistributionVanPanel(
          businessId: widget.businessId,
          service: _svc,
          enableVanSales: _enableVanSales,
          canManage: _canManage,
          authStore: widget.authStore,
        ),
      if (_canOperate && (_enablePresell || _canManage))
        DistributionCommercialPanel(
          businessId: widget.businessId,
          service: _svc,
          calendarController: widget.calendarController,
          canManage: _canManage,
          canOperate: _canOperate,
          requirePodSignature: _requirePodSignature,
          requirePodPhoto: _requirePodPhoto,
        ),
      if (_canManage)
        DistributionManageTab(
          key: _manageKey,
          businessId: widget.businessId,
          service: _svc,
          calendarController: widget.calendarController,
          settings: _summary['distribution_settings'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(_summary['distribution_settings'] as Map)
              : null,
          checklistTemplate: _checklistTemplate,
          memapsKeyController: _memapsKeyCtl,
          mapTiles: _mapTiles,
          onSettingsSaved: _refreshSummary,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _workspace == 'supervisor'
              ? t.distributionWorkspaceSupervisor
              : _workspace == 'office'
                  ? t.distributionWorkspaceOffice
                  : t.distributionMenu,
        ),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          if (_canTeam)
            IconButton(
              tooltip: t.distributionTabTeamMap,
              onPressed: _openTeamMap,
              icon: const Icon(Icons.map_outlined),
            ),
          IconButton(
            tooltip: t.distributionGoToReports,
            onPressed: _openReports,
            icon: const Icon(Icons.analytics_outlined),
          ),
          if (_offlinePending > 0)
            IconButton(
              tooltip: t.distributionOfflineQueueTitle,
              onPressed: _showOfflineQueueSheet,
              icon: Badge(label: Text('$_offlinePending'), child: const Icon(Icons.cloud_queue_outlined)),
            ),
          IconButton(
            tooltip: t.distributionOfflinePack,
            onPressed: () async {
              try {
                final uid = widget.authStore.currentUserId;
                if (uid == null) return;
                await DistributionOfflineCatalog.refresh(
                  businessId: widget.businessId,
                  userId: uid,
                  service: _svc,
                );
                if (mounted) {
                  SnackBarHelper.showSuccess(context, message: t.distributionOfflinePackDone);
                }
              } catch (e) {
                if (mounted) {
                  SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                }
              }
            },
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          if (_canManage)
            IconButton(
              tooltip: t.distributionWizardTitle,
              onPressed: () async {
                final ok = await showDistributionSetupWizard(
                  context: context,
                  businessId: widget.businessId,
                  service: _svc,
                );
                if (ok) {
                  await _refreshSummary();
                  await _refreshPlan();
                }
              },
              icon: const Icon(Icons.auto_fix_high_outlined),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: tabs,
        ),
      ),
      floatingActionButton: _canOperate &&
              (_tabKeys[_tabController.index] == 'returns' || _tabKeys[_tabController.index] == 'field')
          ? FloatingActionButton.extended(
              onPressed: _tabKeys[_tabController.index] == 'returns'
                  ? () => showDistributionReturnDialog(
                        context: context,
                        businessId: widget.businessId,
                        service: _svc,
                        onSubmitted: _refreshReturns,
                      )
                  : () async {
                      final planItems = (_dailyPlan?['items'] as List?) ?? [];
                      final rid = planItems.isEmpty
                          ? null
                          : int.tryParse('${(planItems.first as Map)['route_id']}');
                      final ok = await showDistributionNewOutletSheet(
                        context: context,
                        businessId: widget.businessId,
                        service: _svc,
                        routeId: rid,
                      );
                      if (ok) await _refreshPlan();
                    },
              icon: Icon(_tabKeys[_tabController.index] == 'returns' ? Icons.assignment_return : Icons.storefront_outlined),
              label: Text(
                _tabKeys[_tabController.index] == 'returns' ? t.distributionReturnCreate : t.distributionNewOutlet,
              ),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: tabChildren,
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

}
