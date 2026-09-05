import 'dart:async';

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
import '../distribution_reports_dashboard_page.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart' show SnackBarHelper;
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/distribution/distribution_map_marker.dart';
import '../../../widgets/distribution/distribution_memaps_map.dart';
import '../../../core/distribution_map_tiles.dart';
import '../../../widgets/distribution/distribution_person_location_sheet.dart';
import '../../../widgets/distribution/distribution_return_dialog.dart';
import '../../../widgets/distribution/distribution_ui_helpers.dart';
import '../../../widgets/distribution/distribution_visit_sheet.dart';
import '../../../widgets/distribution/distribution_van_panel.dart';
import '../../../widgets/distribution/distribution_settlement_panel.dart';
import '../../../widgets/distribution/distribution_targets_section.dart';
import '../../../widgets/distribution/distribution_commercial_panel.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';
import '../../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../../widgets/jalali_date_picker.dart';
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

class _DistributionMainPageState extends State<DistributionMainPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DistributionService _svc = DistributionService();
  Timer? _heartbeatTimer;
  final DistributionOfflineQueue _offlineQueue = DistributionOfflineQueue();
  int _offlinePending = 0;
  bool _enableVanSales = false;
  bool _enablePresell = false;
  bool _enablePromotions = false;
  bool _enableSuggestedOrder = true;
  final TextEditingController _memapsKeyCtl = TextEditingController();
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

  int get _tabCount {
    var n = 3;
    if (_canOperate) n += 3; // settlement + van + commercial
    if (_canManage) n++;
    return n;
  }

  List<String> get _tabKeys {
    final keys = <String>['field', 'visits', 'returns'];
    if (_canOperate) {
      keys.add('settlement');
      keys.add('van');
      keys.add('commercial');
    }
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
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) => _sendLiveHeartbeat());
    });
  }

  Future<void> _sendLiveHeartbeat() async {
    final v = _activeVisit;
    if (v == null || !_canOperate) return;
    final id = int.tryParse('${v['id']}');
    if (id == null) return;
    try {
      final loc = await readDistributionVisitLocation();
      if (loc.latitude == null || loc.longitude == null) return;
      await _svc.visitHeartbeat(
        businessId: widget.businessId,
        visitId: id,
        latitude: loc.latitude!,
        longitude: loc.longitude!,
      );
    } catch (_) {
      // silent — موقعیت زنده بهترین‌تلاش است
    }
  }

  Future<void> _refreshOfflineCount() async {
    final n = (await _offlineQueue.peek(widget.businessId)).length;
    if (mounted) setState(() => _offlinePending = n);
  }

  void _applySettingsFromSummary() {
    final ds = _summary['distribution_settings'];
    if (ds is Map<String, dynamic>) {
      _enableVanSales = ds['enable_van_sales'] == true;
      _enablePresell = ds['enable_presell'] == true;
      _enablePromotions = ds['enable_promotions'] == true;
      _enableSuggestedOrder = ds['enable_suggested_order'] != false;
      final tpl = ds['visit_checklist_template'];
      _checklistTemplate = tpl is List ? tpl : [];
      final key = (ds['memaps_api_key'] ?? '').toString();
      if (_memapsKeyCtl.text != key) {
        _memapsKeyCtl.text = key;
      }
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _tabController.dispose();
    _memapsKeyCtl.dispose();
    super.dispose();
  }

  DistributionMapTileConfig get _mapTiles {
    final ds = _summary['distribution_settings'];
    return DistributionMapTileConfig.fromSettings(ds is Map<String, dynamic> ? ds : null);
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
      case 'settlement':
        break;
      case 'van':
        break;
      case 'commercial':
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
      enablePresell: _enablePresell,
      enableSuggestedOrder: _enableSuggestedOrder,
      enablePromotions: _enablePromotions,
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
    await _offlineQueue.enqueue(widget.businessId, {
      'op': op,
      'client_ref': clientRef,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
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
    final items = await _offlineQueue.peek(widget.businessId);
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
      final res = await _offlineQueue.sync(widget.businessId);
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

  /// وضعیت توقف نسبت به ویزیت‌های امروز: done | current | pending
  String _planStopKind(int? personId) {
    if (personId == null) return 'pending';
    final activePid = int.tryParse('${_activeVisit?['person_id']}');
    if (activePid != null && activePid == personId) return 'current';
    final today = DateTime(_planDay.year, _planDay.month, _planDay.day);
    final items = (_visitListPayload?['items'] as List?) ?? [];
    for (final raw in items) {
      final v = Map<String, dynamic>.from(raw as Map);
      if (v['status'] != 'completed') continue;
      if (int.tryParse('${v['person_id']}') != personId) continue;
      final started = _parseDt(v['started_at']) ?? _parseDt(v['ended_at']);
      if (started == null) continue;
      final d = DateTime(started.year, started.month, started.day);
      if (d == today) return 'done';
    }
    return 'pending';
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

  String _visitStatusLabel(AppLocalizations t, String? status) =>
      distributionVisitStatusLabel(t, status);

  static const _weekdayLabelsFa = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
  static const _weekdayLabelsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _weekdayLabel(AppLocalizations t, int? wd) {
    if (wd == null) return t.distributionWeekdayAny;
    final labels = t.localeName.startsWith('fa') ? _weekdayLabelsFa : _weekdayLabelsEn;
    if (wd >= 0 && wd < labels.length) return labels[wd];
    return '$wd';
  }

  void _openReports() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DistributionReportsDashboardPage(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
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
      Tab(text: t.distributionTabField, icon: const Icon(Icons.today_outlined)),
      Tab(text: t.distributionTabVisits, icon: const Icon(Icons.place_outlined)),
      Tab(text: t.distributionTabReturns, icon: const Icon(Icons.assignment_return_outlined)),
      if (_canOperate) Tab(text: t.distributionTabSettlement, icon: const Icon(Icons.account_balance_wallet_outlined)),
      if (_canOperate) Tab(text: t.distributionTabVan, icon: const Icon(Icons.local_shipping)),
      if (_canOperate) Tab(text: t.distributionTabCommercial, icon: const Icon(Icons.storefront_outlined)),
      if (_canManage) Tab(text: t.distributionTabManage, icon: const Icon(Icons.alt_route)),
    ];

    final tabChildren = <Widget>[
      _fieldTab(t),
      _visitsTab(t),
      _returnsTab(t),
      if (_canOperate)
        DistributionSettlementPanel(
          businessId: widget.businessId,
          service: _svc,
          calendarController: widget.calendarController,
          canManage: _canManage,
          canSettle: widget.authStore.hasBusinessPermission('distribution', 'settle') || _canManage,
          currentUserId: widget.authStore.currentUserId,
        ),
      if (_canOperate) _vanTab(t),
      if (_canOperate)
        DistributionCommercialPanel(
          businessId: widget.businessId,
          service: _svc,
          calendarController: widget.calendarController,
          canManage: _canManage,
          canOperate: _canOperate,
        ),
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
    final theme = Theme.of(context);
    final planItems = (_optimizedPlanItems ?? (_dailyPlan?['items'] as List?)) ?? [];
    var doneCount = 0;
    var remainingCount = 0;
    Map<String, dynamic>? nextStop;
    for (final raw in planItems) {
      final item = Map<String, dynamic>.from(raw as Map);
      final pid = int.tryParse('${item['person_id']}');
      final kind = _planStopKind(pid);
      if (kind == 'done') {
        doneCount++;
      } else {
        remainingCount++;
        nextStop ??= item;
      }
    }
    final progress = planItems.isEmpty ? 0.0 : doneCount / planItems.length;

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
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timelapse, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t.distributionActiveVisitBanner, style: theme.textTheme.titleSmall),
                        ),
                        distributionStatusChip(context, t, _activeVisit!['status']?.toString()),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_activeVisit!['person_name'] ?? _activeVisit!['person_id']}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (_canOperate) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _openCompleteSheet(
                          int.parse('${_activeVisit!['id']}'),
                          int.tryParse('${_activeVisit!['person_id']}'),
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(t.distributionCompleteVisitCta),
                      ),
                      TextButton(
                        onPressed: _cancelActiveVisit,
                        child: Text(t.distributionCancelVisit),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(t.distributionDayProgress, style: theme.textTheme.titleMedium),
                      ),
                      Text(
                        '$doneCount / ${planItems.length}',
                        style: theme.textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _loadingPlan ? null : progress,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.check, size: 16),
                        label: Text('${t.distributionStopsDone}: $doneCount'),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.more_horiz, size: 16),
                        label: Text('${t.distributionStopsRemaining}: $remainingCount'),
                      ),
                      if (!_loadingSummary)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.assignment_return, size: 16),
                          label: Text('${t.distributionPendingReturns}: ${_summary['pending_return_requests'] ?? 0}'),
                        ),
                    ],
                  ),
                  if (nextStop != null && _activeVisit == null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${t.distributionNextStop}: ${nextStop['person_name'] ?? nextStop['person_id']}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: t.distributionMoreActions,
                    onSelected: (v) async {
                      if (v == 'optimize' && _canOperate) await _optimizePlanRoute();
                      if (v == 'pdf') await _printDailyPlan();
                      if (v == 'map' && _canTeam) _openTeamMap();
                      if (v == 'reports') _openReports();
                    },
                    itemBuilder: (ctx) => [
                      if (_canOperate)
                        PopupMenuItem(value: 'optimize', child: Text(t.distributionOptimizeRoute)),
                      PopupMenuItem(value: 'pdf', child: Text(t.distributionPrintDailyPlan)),
                      if (_canTeam) PopupMenuItem(value: 'map', child: Text(t.distributionTabTeamMap)),
                      PopupMenuItem(value: 'reports', child: Text(t.distributionGoToReports)),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(t.distributionMoreActions, style: theme.textTheme.labelLarge),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_canTeam)
                    FutureBuilder<BusinessUsersResponse>(
                      future: BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId),
                      builder: (context, snap) {
                        final users = snap.data?.users ?? const <BusinessUser>[];
                        return SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<int?>(
                            value: _teamTargetUserId,
                            isDense: true,
                            decoration: InputDecoration(
                              labelText: t.distributionSelectVisitor,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('—')),
                              ...users.map(
                                (u) => DropdownMenuItem<int?>(
                                  value: u.userId,
                                  child: Text(
                                    u.userName.isNotEmpty ? u.userName : '${u.userId}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) async {
                              setState(() => _teamTargetUserId = v);
                              await _refreshPlan();
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          if (_offlinePending > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Material(
                  color: cs.tertiaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    leading: Badge(
                      label: Text('$_offlinePending'),
                      child: const Icon(Icons.cloud_queue_outlined),
                    ),
                    title: Text(t.distributionOfflineQueued),
                    subtitle: Text('${t.distributionOfflinePending}: $_offlinePending'),
                    trailing: TextButton(onPressed: _showOfflineQueueSheet, child: Text(t.distributionViewQueue)),
                  ),
                ),
              ),
            ),
          if (_loadingPlan)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (planItems.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: distributionEmptyState(
                context: context,
                icon: Icons.route_outlined,
                title: t.distributionNoPlan,
                subtitle: t.distributionEmptyVisitsHint,
              ),
            )
          else
            SliverMainAxisGroup(
              slivers: [
                if (_planMapMarkers(planItems).isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DistributionMemapsMap(
                          markers: _planMapMarkers(planItems),
                          height: 200,
                          tileConfig: _mapTiles,
                        ),
                      ),
                    ),
                  ),
                SliverList.separated(
                  itemCount: planItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final item = Map<String, dynamic>.from(planItems[i] as Map);
                    final pid = int.tryParse('${item['person_id']}');
                    final kind = _planStopKind(pid);
                    final lat = double.tryParse('${item['latitude']}');
                    final lng = double.tryParse('${item['longitude']}');
                    final phone = item['person_mobile']?.toString();
                    final nextId = nextStop == null ? null : '${nextStop['stop_id']}';
                    final isNext = nextId != null && '${item['stop_id']}' == nextId;
                    final kindLabel = kind == 'done'
                        ? t.distributionStopDone
                        : kind == 'current'
                            ? t.distributionStopCurrent
                            : t.distributionStopPending;
                    final kindColor = kind == 'done'
                        ? cs.primary
                        : kind == 'current'
                            ? cs.tertiary
                            : cs.outline;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Material(
                        elevation: isNext && kind == 'pending' ? 1 : 0,
                        color: kind == 'current'
                            ? cs.tertiaryContainer.withValues(alpha: 0.35)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: kindColor.withValues(alpha: 0.15),
                                    foregroundColor: kindColor,
                                    child: Text('${item['sort_order'] ?? i + 1}'),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item['person_name'] ?? item['person_id']}',
                                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                        Text(
                                          '${item['route_code'] ?? ''} · ${item['route_name'] ?? ''}',
                                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(kindLabel, style: TextStyle(color: kindColor, fontSize: 12)),
                                    side: BorderSide(color: kindColor.withValues(alpha: 0.4)),
                                    backgroundColor: kindColor.withValues(alpha: 0.08),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 4,
                                children: [
                                  if (phone != null && phone.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: () => openDistributionPhoneDialer(phone),
                                      icon: const Icon(Icons.call_outlined, size: 18),
                                      label: Text(t.distributionCallCustomer),
                                    ),
                                  if (lat != null && lng != null)
                                    TextButton.icon(
                                      onPressed: () => openDistributionMapsNavigation(lat, lng),
                                      icon: const Icon(Icons.navigation_outlined, size: 18),
                                      label: Text(t.distributionNavigate),
                                    ),
                                  if (_canManage)
                                    TextButton.icon(
                                      onPressed: () => _setPersonLocationFromPlan(item),
                                      icon: Icon(
                                        item['latitude'] != null
                                            ? Icons.edit_location_alt
                                            : Icons.add_location_alt_outlined,
                                        size: 18,
                                      ),
                                      label: Text(t.distributionSetPersonLocation),
                                    ),
                                ],
                              ),
                              if (_canOperate && _activeVisit == null && kind != 'done') ...[
                                const SizedBox(height: 4),
                                FilledButton(
                                  onPressed: () => _startVisitFromPlan(item),
                                  child: Text(t.distributionStartVisit),
                                ),
                              ],
                              if (_canOperate && kind == 'current' && _activeVisit != null) ...[
                                const SizedBox(height: 4),
                                FilledButton.tonal(
                                  onPressed: () => _openCompleteSheet(
                                    int.parse('${_activeVisit!['id']}'),
                                    int.tryParse('${_activeVisit!['person_id']}'),
                                  ),
                                  child: Text(t.distributionCompleteVisitCta),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  Widget _settingsSection(AppLocalizations t) {
    final ds = _summary['distribution_settings'] as Map<String, dynamic>;
    final mapSource = (ds['map_tile_source'] ?? 'osm').toString() == 'memaps' ? 'memaps' : 'osm';
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(t.distributionMapSectionTitle, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.distributionMapTileSource, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  t.distributionMapTileSourceHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.distributionMapTileSourceOsm),
                  value: 'osm',
                  groupValue: mapSource,
                  onChanged: (v) {
                    if (v != null) persist({'map_tile_source': v});
                  },
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.distributionMapTileSourceMemaps),
                  value: 'memaps',
                  groupValue: mapSource,
                  onChanged: (v) {
                    if (v != null) persist({'map_tile_source': v});
                  },
                ),
              ],
            ),
          ),
          if (mapSource == 'memaps')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _memapsKeyCtl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: t.distributionMemapsApiKey,
                  helperText: t.distributionMemapsApiKeyHint,
                  helperMaxLines: 4,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: t.save,
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () => persist({'memaps_api_key': _memapsKeyCtl.text.trim()}),
                  ),
                ),
                onSubmitted: (v) => persist({'memaps_api_key': v.trim()}),
              ),
            ),
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
            title: Text(t.distributionEnablePresell),
            subtitle: Text(t.distributionEnablePresellHint),
            value: ds['enable_presell'] == true,
            onChanged: (v) => persist({'enable_presell': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionEnablePromotions),
            value: ds['enable_promotions'] == true,
            onChanged: (v) => persist({'enable_promotions': v}),
          ),
          SwitchListTile(
            title: Text(t.distributionEnableSuggestedOrder),
            value: ds['enable_suggested_order'] != false,
            onChanged: (v) => persist({'enable_suggested_order': v}),
          ),
          ListTile(
            title: Text(t.distributionVisitorMaxDiscount),
            subtitle: Text('${ds['visitor_max_discount_percent'] ?? 0} %'),
            trailing: SizedBox(
              width: 72,
              child: TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                controller: TextEditingController(text: '${ds['visitor_max_discount_percent'] ?? 0}'),
                onSubmitted: (v) {
                  final n = double.tryParse(v.trim().replaceAll(',', '.'));
                  if (n != null && n >= 0 && n <= 100) persist({'visitor_max_discount_percent': n});
                },
              ),
            ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: WarehouseComboboxWidget(
              businessId: widget.businessId,
              selectedWarehouseId: ds['default_source_warehouse_id'] is int
                  ? ds['default_source_warehouse_id'] as int
                  : int.tryParse('${ds['default_source_warehouse_id'] ?? ''}'),
              label: t.distributionDefaultWarehouse,
              onChanged: (id) => persist({'default_source_warehouse_id': id}),
            ),
          ),
          ListTile(
            title: Text(t.distributionChecklistTitle),
            subtitle: Text(
              ((_checklistTemplate).isEmpty)
                  ? t.distributionChecklistAddItem
                  : '${_checklistTemplate.length} ${t.distributionChecklistAddItem}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final ctl = TextEditingController();
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: Text(t.distributionChecklistAddItem),
                    content: TextField(
                      controller: ctl,
                      decoration: InputDecoration(
                        labelText: t.distributionChecklistTitle,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t.cancel)),
                      FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(t.save)),
                    ],
                  ),
                );
                if (ok != true || ctl.text.trim().isEmpty) return;
                final next = List<dynamic>.from(_checklistTemplate)
                  ..add({'id': 'c_${DateTime.now().millisecondsSinceEpoch}', 'label': ctl.text.trim(), 'required': false});
                await persist({'visit_checklist_template': next});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _vanTab(AppLocalizations t) {
    return DistributionVanPanel(
      businessId: widget.businessId,
      service: _svc,
      enableVanSales: _enableVanSales,
      canManage: _canManage,
    );
  }

  Widget _visitsTab(AppLocalizations t) {
    if (_loadingVisits) return const Center(child: CircularProgressIndicator());
    final items = (_visitListPayload?['items'] as List?) ?? [];
    if (items.isEmpty) {
      return distributionEmptyState(
        context: context,
        icon: Icons.place_outlined,
        title: t.distributionEmptyVisits,
        subtitle: t.distributionEmptyVisitsHint,
        action: FilledButton.tonal(
          onPressed: () => _tabController.animateTo(0),
          child: Text(t.distributionGoToField),
        ),
      );
    }
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
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: ListTile(
              leading: Icon(
                status == 'completed'
                    ? Icons.check_circle
                    : status == 'cancelled'
                        ? Icons.cancel
                        : Icons.timelapse,
                color: distributionStatusColor(context, status),
              ),
              title: Text(v['person_name']?.toString() ?? '${v['person_id']}'),
              subtitle: Text(
                '${distributionOutcomeLabel(t, v['outcome']?.toString())}\n'
                '${Hd.HesabixDateUtils.formatDateTime(_parseDt(v['started_at']), _jalali)}',
              ),
              isThreeLine: true,
              trailing: status == 'in_progress' && _canOperate
                  ? FilledButton(
                      onPressed: () => _openCompleteSheet(
                        int.parse('${v['id']}'),
                        int.tryParse('${v['person_id']}'),
                      ),
                      child: Text(t.distributionCompleteVisitCta),
                    )
                  : distributionStatusChip(context, t, status),
            ),
          );
        },
      ),
    );
  }

  Widget _returnsTab(AppLocalizations t) {
    if (_loadingReturns) return const Center(child: CircularProgressIndicator());
    final filtered = _returnsPendingOnly
        ? _returns.where((r) => Map<String, dynamic>.from(r as Map)['status'] == 'pending').toList()
        : _returns;
    return RefreshIndicator(
      onRefresh: _refreshReturns,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(t.distributionFilterPending), icon: const Icon(Icons.hourglass_top)),
                  ButtonSegment(value: false, label: Text(t.distributionFilterAll), icon: const Icon(Icons.list)),
                ],
                selected: {_returnsPendingOnly},
                onSelectionChanged: (s) => setState(() => _returnsPendingOnly = s.first),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: distributionEmptyState(
                context: context,
                icon: Icons.assignment_return_outlined,
                title: t.distributionEmptyReturns,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final r = Map<String, dynamic>.from(filtered[i] as Map);
                  final lines = (r['lines'] as List?) ?? [];
                  final pending = r['status'] == 'pending';
                  return Card(
                    elevation: 0,
                    child: ExpansionTile(
                      leading: Icon(
                        pending ? Icons.hourglass_top : Icons.assignment_return,
                        color: distributionStatusColor(context, r['status']?.toString()),
                      ),
                      title: Text('#${r['id']} · ${r['person_name'] ?? '${t.distributionSelectPerson} ${r['person_id']}'}'),
                      subtitle: Text('${distributionReturnStatusLabel(t, r['status']?.toString())} · ${lines.length} ${t.distributionReturnAddLine}'),
                      trailing: pending && _canApproveReturns
                          ? null
                          : distributionStatusChip(context, t, r['status']?.toString(), isReturn: true),
                      children: [
                        ...lines.map((ln) {
                          final m = Map<String, dynamic>.from(ln as Map);
                          return ListTile(
                            dense: true,
                            title: Text(m['product_name']?.toString() ?? 'product ${m['product_id']}'),
                            subtitle: Text('× ${m['quantity']} ${m['reason'] ?? ''}'),
                          );
                        }),
                        if (pending && _canApproveReturns)
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
            ),
        ],
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
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(t.distributionTargetsTitle, style: Theme.of(context).textTheme.titleMedium),
        ),
        DistributionTargetsSection(
          businessId: widget.businessId,
          service: _svc,
          calendarController: widget.calendarController,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(t.distributionManageSectionRoutes, style: Theme.of(context).textTheme.titleMedium),
        ),
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
        if (_loadingRoutes)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ..._routes.map((raw) {
            final r = Map<String, dynamic>.from(raw as Map);
            final rid = r['id'] as int;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
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
                                tileConfig: _mapTiles,
                              );
                              if (saved == true) await _loadStops(rid);
                            },
                          ),
                          IconButton(
                            tooltip: t.distributionDeleteStop,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final sid = int.tryParse('${m['id']}');
                              if (sid == null) return;
                              try {
                                await _svc.deleteStop(
                                  businessId: widget.businessId,
                                  routeId: rid,
                                  stopId: sid,
                                );
                                await _loadStops(rid);
                                if (mounted) {
                                  SnackBarHelper.showSuccess(
                                    context,
                                    message: t.distributionSettingsSaved,
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  SnackBarHelper.showError(
                                    context,
                                    message: ErrorExtractor.forContext(e, context),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        if (_summary['distribution_settings'] is Map<String, dynamic>) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(t.distributionManageSectionSettings, style: Theme.of(context).textTheme.titleMedium),
          ),
          _settingsSection(t),
        ],
        const SizedBox(height: 48),
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
    DateTime from = DateTime.now();
    DateTime? to;
    int? selectedUserId;
    List<BusinessUser> users = const [];
    try {
      final res = await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId);
      users = res.users;
    } catch (_) {}
    List<dynamic> existing = const [];
    try {
      existing = await _svc.listAssignments(businessId: widget.businessId, routeId: routeId);
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionAssignVisitor),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedUserId,
                    decoration: InputDecoration(
                      labelText: t.distributionSelectVisitor,
                      border: const OutlineInputBorder(),
                    ),
                    items: users
                        .map(
                          (u) => DropdownMenuItem<int>(
                            value: u.userId,
                            child: Text(u.userName.isNotEmpty ? u.userName : 'user ${u.userId}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setD(() => selectedUserId = v),
                  ),
                  ListTile(
                    title: Text(Hd.HesabixDateUtils.formatForDisplay(from, _jalali)),
                    subtitle: Text(t.distributionAssignmentFrom),
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
                  if (existing.isNotEmpty) ...[
                    const Divider(),
                    ...existing.map((raw) {
                      final m = Map<String, dynamic>.from(raw as Map);
                      return ListTile(
                        dense: true,
                        title: Text(m['user_name']?.toString() ?? 'user ${m['user_id']}'),
                        subtitle: Text('${t.distributionAssignmentFrom}: ${m['valid_from']} → ${t.distributionAssignmentTo}: ${m['valid_to'] ?? '∞'}'),
                        trailing: IconButton(
                          tooltip: t.distributionDeleteAssignment,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final aid = int.tryParse('${m['id']}');
                            if (aid == null) return;
                            try {
                              await _svc.deleteAssignment(
                                businessId: widget.businessId,
                                assignmentId: aid,
                              );
                              existing = await _svc.listAssignments(
                                businessId: widget.businessId,
                                routeId: routeId,
                              );
                              setD(() {});
                            } catch (e) {
                              if (mounted) {
                                SnackBarHelper.showError(
                                  context,
                                  message: ErrorExtractor.forContext(e, context),
                                );
                              }
                            }
                          },
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: selectedUserId == null
                  ? null
                  : () async {
                      try {
                        await _svc.createAssignment(
                          businessId: widget.businessId,
                          payload: <String, dynamic>{
                            'route_id': routeId,
                            'user_id': selectedUserId,
                            'valid_from': _iso(from),
                            if (to != null) 'valid_to': _iso(to!),
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
                        }
                      } catch (e) {
                        if (mounted) {
                          SnackBarHelper.showError(
                            context,
                            message: ErrorExtractor.forContext(e, context),
                          );
                        }
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
