import 'package:flutter/foundation.dart';

import '../../utils/error_extractor.dart';
import '../in_app_notifications_hub.dart';
import 'softphone_engine.dart';
import 'telephony_api.dart';

/// وضعیت جلسه تلفن برای یک کسب‌وکار در کلاینت.
class TelephonySessionController extends ChangeNotifier {
  TelephonySessionController({TelephonyApi? api}) : _api = api ?? TelephonyApi();

  final TelephonyApi _api;
  int? _businessId;
  bool _pluginLikelyActive = false;
  bool _loading = false;
  String? _error;

  Map<String, dynamic>? contextData;
  Map<String, dynamic>? activeCall;
  Map<String, dynamic>? screenPop;
  bool screenPopVisible = false;
  bool pendingPostCall = false;
  int? _pendingPostCallId;
  final Set<int> _shownPostCallIds = {};
  DateTime? _lastPostCallAt;

  bool get loading => _loading;
  String? get error => _error;
  int? get businessId => _businessId;
  bool get pluginLikelyActive => _pluginLikelyActive;

  String get presenceLabel {
    final softEngine = SoftphoneEngineStore.instance.engine;
    if (softEngine != null && softEngine.businessId == _businessId) {
      switch (softEngine.state) {
        case SoftphoneConnectionState.ringing:
          return 'ringing';
        case SoftphoneConnectionState.inCall:
          return 'in_call';
        case SoftphoneConnectionState.registered:
          return 'idle';
        case SoftphoneConnectionState.error:
        case SoftphoneConnectionState.reconnecting:
          return 'offline';
        default:
          break;
      }
    }
    final status = '${activeCall?['status'] ?? ''}';
    if (status == 'ringing') return 'ringing';
    if (status == 'answered') return 'in_call';
    final pbx = contextData?['pbx_connections'];
    if (pbx is List && pbx.isNotEmpty) {
      final online = pbx.any((e) => '${(e as Map)['status']}' == 'online');
      if (!online) return 'offline';
    }
    if (contextData?['has_extension'] == true) return 'idle';
    return 'no_extension';
  }

  String? get endpointMode {
    final primary = contextData?['primary'];
    if (primary is Map) return '${primary['endpoint_mode'] ?? 'desk'}';
    final soft = contextData?['softphone'];
    if (soft is Map) return '${soft['endpoint_mode'] ?? ''}';
    return null;
  }

  String? get primaryExtension {
    final primary = contextData?['primary'];
    if (primary is Map) return '${primary['extension'] ?? ''}';
    return null;
  }

  int get missedToday {
    final v = contextData?['missed_today'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  void bindBusiness(int businessId, {bool pluginActive = true}) {
    if (_businessId == businessId && _pluginLikelyActive == pluginActive) return;
    if (_businessId != businessId) {
      _shownPostCallIds.clear();
    }
    _businessId = businessId;
    _pluginLikelyActive = pluginActive;
    if (pluginActive) {
      refresh();
    } else {
      contextData = null;
      activeCall = null;
      screenPop = null;
      screenPopVisible = false;
      pendingPostCall = false;
      _pendingPostCallId = null;
      notifyListeners();
    }
  }

  void attachWs() {
    InAppNotificationsHub.instance.addRawMessageListener(_onWs);
  }

  void detachWs() {
    InAppNotificationsHub.instance.removeRawMessageListener(_onWs);
  }

  void _onWs(Map<String, dynamic> msg) {
    final type = '${msg['type'] ?? ''}';
    if (!type.startsWith('telephony.')) return;
    final bid = msg['business_id'];
    final biz = bid is int ? bid : int.tryParse('$bid');
    if (_businessId == null || biz != _businessId) return;

    if (type == 'telephony.incoming_call' ||
        type == 'telephony.outbound_ringing' ||
        type == 'telephony.call_answered') {
      final callId = msg['call_id'];
      final id = callId is int ? callId : int.tryParse('$callId');
      if (id != null) {
        unawaitedOpenPop(id);
      }
    } else if (type == 'telephony.call_ended' || type == 'telephony.call_missed') {
      final callId = msg['call_id'];
      final id = callId is int ? callId : int.tryParse('$callId');
      activeCall = {
        ...?activeCall,
        'status': type == 'telephony.call_missed' ? 'missed' : 'completed',
        if (id != null) 'id': id,
      };
      if (id != null && !_shownPostCallIds.contains(id) && _pendingPostCallId != id) {
        final last = _lastPostCallAt;
        if (pendingPostCall || (last != null && DateTime.now().difference(last).inSeconds < 8)) {
          _shownPostCallIds.add(id);
        } else {
          pendingPostCall = true;
          _pendingPostCallId = id;
          _lastPostCallAt = DateTime.now();
        }
      }
      // بستن Screen Pop تا Post-Call sheet جای آن را بگیرد
      screenPopVisible = false;
      notifyListeners();
      refresh();
    }
  }

  /// یک‌بار مصرف برای جلوگیری از باز شدن چندبارهٔ شیت پس از تماس.
  bool takePendingPostCall() {
    if (!pendingPostCall) return false;
    pendingPostCall = false;
    final id = _pendingPostCallId;
    if (id != null) {
      _shownPostCallIds.add(id);
      _lastPostCallAt = DateTime.now();
      if (_shownPostCallIds.length > 40) {
        final extra = _shownPostCallIds.length - 40;
        _shownPostCallIds.removeAll(_shownPostCallIds.take(extra).toList());
      }
    }
    return true;
  }

  void clearPendingPostCall() {
    final id = _pendingPostCallId;
    if (id != null) _shownPostCallIds.add(id);
    pendingPostCall = false;
    _pendingPostCallId = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final bid = _businessId;
    if (bid == null || !_pluginLikelyActive) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      contextData = await _api.getMyContext(bid);
      _error = null;
    } catch (e) {
      _error = ErrorExtractor.userMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> unawaitedOpenPop(int callId) async {
    final bid = _businessId;
    if (bid == null) return;
    try {
      final ctx = await _api.screenPopContext(bid, callId);
      screenPop = ctx;
      activeCall = ctx['call'] is Map ? Map<String, dynamic>.from(ctx['call'] as Map) : {'id': callId};
      screenPopVisible = true;
      notifyListeners();
    } catch (_) {}
  }

  void closeScreenPop() {
    screenPopVisible = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> clickToCall({
    required String destination,
    int? personId,
    int? leadId,
  }) async {
    final bid = _businessId;
    if (bid == null) return null;

    // اگر Softphone Relay آنلاین است، تماس از داخل اپ برود (نه Originate به گوشی خارجی)
    final engine = SoftphoneEngineStore.instance.engine;
    final mode = endpointMode;
    if (engine != null &&
        engine.businessId == bid &&
        engine.isReady &&
        (mode == null || mode == 'relay' || mode.isEmpty)) {
      await engine.dial(destination, personId: personId, leadId: leadId);
      activeCall = engine.activeCall;
      notifyListeners();
      return {'call': activeCall, 'via': 'softphone_relay'};
    }

    final result = await _api.clickToCall(bid, {
      'destination': destination,
      if (personId != null) 'person_id': personId,
      if (leadId != null) 'lead_id': leadId,
    });
    activeCall = result['call'] is Map ? Map<String, dynamic>.from(result['call'] as Map) : null;
    notifyListeners();
    return result;
  }

  Future<void> hangupActiveCall() async {
    final bid = _businessId;
    final callId = int.tryParse('${activeCall?['id'] ?? ''}');
    if (bid == null || callId == null) return;
    await _api.controlCall(bid, callId, action: 'hangup');
  }

  Future<void> saveCallNote({
    required int callId,
    String? note,
    String? category,
    String? outcome,
  }) async {
    final bid = _businessId;
    if (bid == null) return;
    await _api.patchCall(bid, callId, {
      if (note != null) 'note': note,
      if (category != null) 'category': category,
      if (outcome != null) 'outcome': outcome,
    });
    await refresh();
  }
}

/// کنترلر سراسری سبک برای Phone Bar داخل BusinessShell.
class TelephonySessionStore {
  TelephonySessionStore._();
  static final TelephonySessionStore instance = TelephonySessionStore._();

  final TelephonySessionController controller = TelephonySessionController();
  bool _wsAttached = false;

  void ensureWs() {
    if (_wsAttached) return;
    controller.attachWs();
    _wsAttached = true;
  }
}
