import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/app_config.dart';
import '../../core/android_notification_keepalive_platform.dart';
import '../../core/auth_store.dart';
import '../android_notification_keepalive/android_notification_keepalive_service.dart';
import 'softphone_android_launch.dart';
import 'softphone_incoming_notifications.dart';
import 'softphone_pcm_media.dart';
import 'softphone_ringtone.dart';
import 'softphone_ws_client.dart';
import 'telephony_api.dart';

enum SoftphoneConnectionState {
  idle,
  connecting,
  registered,
  ringing,
  inCall,
  reconnecting,
  error,
  ended,
}

/// موتور Softphone Relay — کنترل‌پلن + PCM واقعی (میکروفون/پخش).
///
/// اندروید: با Foreground Service زنده می‌ماند؛ در پس‌زمینه/بسته شدن UI
/// اعلان تمام‌صفحه تماس ورودی نشان داده می‌شود و WS به FGS منتقل می‌شود.
class SoftphoneEngine extends ChangeNotifier with WidgetsBindingObserver {
  SoftphoneEngine({
    required this.businessId,
    required this.authStore,
    TelephonyApi? api,
  }) : _api = api ?? TelephonyApi() {
    WidgetsBinding.instance.addObserver(this);
    if (supportsSoftphoneIncomingNotifications) {
      unawaited(_incomingNotif.initialize(onAction: _onIncomingNotificationAction));
    }
    if (supportsAndroidNotificationKeepAlive) {
      _keepAlive.setOnSoftphoneMessage(_onFgsSoftphoneMessage);
    }
  }

  final int businessId;
  final AuthStore authStore;
  final TelephonyApi _api;
  final SoftphoneIncomingNotifications _incomingNotif = createSoftphoneIncomingNotifications();
  final AndroidNotificationKeepAliveService _keepAlive = createAndroidNotificationKeepAliveService();

  SoftphoneWsClient? _ws;
  SoftphonePcmMedia? _media;
  SoftphoneRingtone? _ringtone;
  Timer? _heartbeat;
  Timer? _silenceFallback;
  Timer? _reconnectTimer;
  bool _micLive = false;
  bool _wantOnline = false;
  bool _uiHoldingWs = true;
  int _reconnectAttempt = 0;

  SoftphoneConnectionState state = SoftphoneConnectionState.idle;
  String? error;
  String? sessionId;
  String? mediaTicket;
  String? mediaProfile;
  Map<String, dynamic>? session;
  Map<String, dynamic>? health;
  Map<String, dynamic>? activeCall;
  bool muted = false;
  bool bridgeActive = false;
  bool mediaReady = false;
  int incomingPcmFrames = 0;
  int outgoingPcmFrames = 0;

  bool get isReady =>
      state == SoftphoneConnectionState.registered ||
      state == SoftphoneConnectionState.ringing ||
      state == SoftphoneConnectionState.inCall;

  String get statusDetail {
    final parts = <String>[];
    if (mediaReady) parts.add('صوت آماده');
    if (_micLive) parts.add('میکروفون');
    if (bridgeActive) parts.add('پل فعال');
    if (muted) parts.add('بی‌صدا');
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Future<Map<String, dynamic>> refreshHealth() async {
    health = await _api.softphoneHealth(businessId);
    notifyListeners();
    return health!;
  }

  Future<void> register({String? mode}) async {
    final apiKey = authStore.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      error = 'کلید API یافت نشد';
      state = SoftphoneConnectionState.error;
      notifyListeners();
      return;
    }
    state = SoftphoneConnectionState.connecting;
    error = null;
    notifyListeners();

    try {
      await Permission.microphone.request();
    } catch (_) {}

    try {
      _media ??= createSoftphonePcmMedia(sampleRate: 8000, numChannels: 1);
      try {
        await _media!.start();
        mediaReady = true;
      } catch (e) {
        // Signaling must still connect; live audio retries on bridge.active.
        mediaReady = false;
        error = 'مدیا آماده نشد: $e';
      }

      final created = await _api.createSoftphoneSession(businessId, {
        if (mode != null) 'mode': mode,
        'client_info': {
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'engine': 'softphone_relay_r1',
          'media': 'pcm_ws_v1_live',
        },
      });
      session = created['session'] is Map ? Map<String, dynamic>.from(created['session'] as Map) : null;
      sessionId = '${session?['session_id'] ?? created['session_id'] ?? ''}';
      mediaTicket = '${created['media_ticket'] ?? ''}';
      mediaProfile = '${created['media_profile'] ?? 'pcm_ws_v1'}';
      health = created['health'] is Map ? Map<String, dynamic>.from(created['health'] as Map) : health;

      if (sessionId == null || sessionId!.isEmpty || mediaTicket == null || mediaTicket!.isEmpty) {
        throw StateError('سشن Softphone ناقص برگشت');
      }

      _ws?.disconnect();
      _ws = createSoftphoneWsClient();
      _uiHoldingWs = true;
      _wantOnline = true;
      _ws!.connect(
        apiKey: apiKey,
        businessId: businessId,
        sessionId: sessionId!,
        mediaTicket: mediaTicket!,
        onJson: _onWsJson,
        onPcm: _onWsPcm,
        onError: (e) {
          error = '$e';
          state = SoftphoneConnectionState.reconnecting;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          if (state != SoftphoneConnectionState.ended && state != SoftphoneConnectionState.idle) {
            state = SoftphoneConnectionState.reconnecting;
            notifyListeners();
            if (_wantOnline && _uiHoldingWs) {
              _scheduleReconnect();
            }
          }
        },
      );

      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 45), (_) async {
        final sid = sessionId;
        if (sid == null) return;
        try {
          session = await _api.softphoneHeartbeat(businessId, sid);
        } catch (_) {}
      });

      await _enableAndroidPresence(uiHoldingWs: true);
      unawaited(_consumePendingIncomingAction());
    } catch (e) {
      error = '$e';
      state = SoftphoneConnectionState.error;
      mediaReady = false;
      notifyListeners();
    }
  }

  void _onWsJson(Map<String, dynamic> msg) {
    final type = '${msg['type'] ?? ''}';
    switch (type) {
      case 'auth_ok':
        state = SoftphoneConnectionState.registered;
        error = null;
        notifyListeners();
        break;
      case 'incoming_ring':
        state = SoftphoneConnectionState.ringing;
        final incomingId = msg['call_id'];
        activeCall = {
          ...?activeCall,
          if (incomingId != null) 'id': incomingId,
          'from': msg['from'] ?? activeCall?['from'],
          'extension': msg['extension'] ?? activeCall?['extension'],
          'channel': msg['channel'] ?? activeCall?['channel'],
          'status': 'ringing',
          'direction': 'inbound',
        };
        unawaited(_startRingtone());
        unawaited(_showAndroidIncomingNotification());
        unawaited(softphoneLaunchAppToForeground());
        if (int.tryParse('${activeCall?['id'] ?? ''}') == null) {
          unawaited(_resolveIncomingCallId());
        }
        notifyListeners();
        break;
      case 'bridge.starting':
        unawaited(_stopRingtone());
        bridgeActive = false;
        state = SoftphoneConnectionState.inCall;
        if (msg['call_id'] != null) {
          activeCall = {...?activeCall, 'id': msg['call_id'], 'status': 'answered'};
        }
        notifyListeners();
        break;
      case 'bridge.active':
        unawaited(_stopRingtone());
        bridgeActive = true;
        state = SoftphoneConnectionState.inCall;
        unawaited(_startLiveMedia());
        notifyListeners();
        break;
      case 'bridge.ended':
      case 'bridge.failed':
        unawaited(_stopRingtone());
        unawaited(_incomingNotif.cancelIncomingCall());
        bridgeActive = false;
        unawaited(_stopLiveMedia());
        if (state == SoftphoneConnectionState.inCall || state == SoftphoneConnectionState.ringing) {
          state = SoftphoneConnectionState.registered;
        }
        activeCall = null;
        notifyListeners();
        break;
      case 'mute_ok':
        muted = msg['muted'] == true;
        notifyListeners();
        break;
    }
  }

  void _onWsPcm(List<int> pcm, String sid) {
    incomingPcmFrames += 1;
    if (!muted) {
      _media?.playPcm(pcm);
    }
    if (incomingPcmFrames % 50 == 0) notifyListeners();
  }

  Future<void> _startLiveMedia() async {
    _silenceFallback?.cancel();
    final media = _media;
    final sid = sessionId;
    final ws = _ws;
    if (media == null || sid == null || ws == null) return;

    try {
      if (!media.isReady) {
        await media.start();
        mediaReady = true;
      }
      if (!muted && !media.isMicActive) {
        await media.startMic((Uint8List chunk) {
          if (!bridgeActive || muted) return;
          if (!_ws!.isConnected) return;
          _ws!.sendPcm(sid, chunk);
          outgoingPcmFrames += 1;
          if (outgoingPcmFrames % 50 == 0) notifyListeners();
        });
        _micLive = true;
      }
    } catch (e) {
      // اگر میکروفون بالا نیامد، سکوت بفرست تا پل Asterisk قطع نشود
      error = 'میکروفون: $e — ارسال سکوت موقت';
      _startSilenceFallback();
      notifyListeners();
      return;
    }

    // اگر فریم میکروفون دیر رسید، برای چند ثانیه اول سکوت هم بفرست تا AudioSocket زنده بماند
    _startSilenceFallback(onlyWhenNoMicFrames: true);
    notifyListeners();
  }

  void _startSilenceFallback({bool onlyWhenNoMicFrames = false}) {
    _silenceFallback?.cancel();
    final silence = List<int>.filled(320, 0); // 20ms @ 8kHz
    var ticks = 0;
    _silenceFallback = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!bridgeActive || muted) return;
      final sid = sessionId;
      final ws = _ws;
      if (sid == null || ws == null || !ws.isConnected) return;
      if (onlyWhenNoMicFrames && _micLive && outgoingPcmFrames > 5) {
        // میکروفون زنده است؛ fallback را متوقف کن
        if (ticks > 25) {
          _silenceFallback?.cancel();
          _silenceFallback = null;
        }
        ticks++;
        return;
      }
      ws.sendPcm(sid, silence);
      outgoingPcmFrames += 1;
      ticks++;
    });
  }

  Future<void> _stopLiveMedia() async {
    _silenceFallback?.cancel();
    _silenceFallback = null;
    try {
      await _media?.stopMic();
    } catch (_) {}
    _micLive = false;
  }

  Future<void> dial(String destination, {int? personId, int? leadId}) async {
    final sid = sessionId;
    if (sid == null) throw StateError('ابتدا Softphone را آنلاین کنید');
    if (!isReady || _ws == null || !_ws!.isConnected) {
      throw StateError('کانال Softphone وصل نیست؛ دوباره آنلاین شوید');
    }
    final result = await _api.softphoneOutboundCall(businessId, {
      'session_id': sid,
      'destination': destination,
      if (personId != null) 'person_id': personId,
      if (leadId != null) 'lead_id': leadId,
    });
    activeCall = result['call'] is Map ? Map<String, dynamic>.from(result['call'] as Map) : null;
    state = SoftphoneConnectionState.ringing;
    notifyListeners();
  }

  Future<void> answer(int callId) async {
    final sid = sessionId;
    if (sid == null) throw StateError('سشن Softphone نیست');
    if (_ws == null || !_ws!.isConnected) {
      // ممکن است WS در FGS باشد — اول reclaim کن
      await _reclaimSoftphoneWsFromFgs();
      if (_ws == null || !_ws!.isConnected) {
        throw StateError('کانال Softphone وصل نیست؛ دوباره آنلاین شوید');
      }
    }
    await _stopRingtone();
    await _incomingNotif.cancelIncomingCall();
    final result = await _api.softphoneAnswerCall(businessId, callId, {'session_id': sid});
    activeCall = result['call'] is Map ? Map<String, dynamic>.from(result['call'] as Map) : {'id': callId};
    state = SoftphoneConnectionState.inCall;
    notifyListeners();
  }

  Future<void> rejectIncoming() => hangup();

  Future<void> hangup() async {
    final callId = int.tryParse('${activeCall?['id'] ?? ''}');
    final sid = sessionId;
    await _stopRingtone();
    await _incomingNotif.cancelIncomingCall();
    _ws?.sendJson({'type': 'hangup_media', 'reason': 'user_hangup', if (sid != null) 'session_id': sid});
    if (callId != null) {
      try {
        await _api.controlCall(
          businessId,
          callId,
          action: 'hangup',
          extra: sid != null ? {'session_id': sid} : null,
        );
      } catch (_) {}
    }
    bridgeActive = false;
    await _stopLiveMedia();
    activeCall = null;
    state = SoftphoneConnectionState.registered;
    notifyListeners();
  }

  String get incomingCallerDisplay {
    final from = '${activeCall?['from'] ?? ''}'.trim();
    if (from.isNotEmpty && from != 'null') return from;
    return 'شماره ناشناس';
  }

  int? get activeCallId => int.tryParse('${activeCall?['id'] ?? ''}');

  Future<void> _startRingtone() async {
    try {
      _ringtone ??= createSoftphoneRingtone();
      await _ringtone!.start();
    } catch (_) {}
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtone?.stop();
    } catch (_) {}
  }

  Future<void> _resolveIncomingCallId() async {
    try {
      final res = await _api.listCalls(
        businessId,
        direction: 'inbound',
        status: 'ringing',
        limit: 5,
      );
      final items = res['items'];
      if (items is! List || items.isEmpty) return;
      final ext = '${session?['extension'] ?? health?['extension'] ?? ''}'.trim();
      Map<String, dynamic>? match;
      for (final raw in items) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final callExt = '${m['extension'] ?? ''}'.trim();
        if (ext.isEmpty || callExt == ext || callExt.isEmpty) {
          match = m;
          break;
        }
      }
      match ??= Map<String, dynamic>.from(items.first as Map);
      final id = match['id'];
      if (id == null) return;
      if (state != SoftphoneConnectionState.ringing) return;
      activeCall = {
        ...?activeCall,
        'id': id,
        'from': activeCall?['from'] ?? match['from_number'] ?? match['from_number_raw'],
        'status': 'ringing',
        'direction': 'inbound',
      };
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    _ws?.sendJson({'type': 'mute', 'muted': value});
    if (value) {
      await _media?.stopMic();
      _micLive = false;
    } else if (bridgeActive) {
      await _startLiveMedia();
    }
    notifyListeners();
  }

  Future<void> sendDtmf(String digit) async {
    final callId = int.tryParse('${activeCall?['id'] ?? ''}');
    final sid = sessionId;
    if (callId == null || sid == null) return;
    _ws?.sendJson({'type': 'dtmf', 'digit': digit, 'call_id': callId});
    await _api.softphoneDtmf(businessId, callId, {'digit': digit, 'session_id': sid});
  }

  Future<void> unregister() async {
    _wantOnline = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _stopRingtone();
    await _incomingNotif.cancelIncomingCall();
    await _stopLiveMedia();
    final sid = sessionId;
    _ws?.disconnect();
    _ws = null;
    try {
      await _media?.stop();
    } catch (_) {}
    _media = null;
    mediaReady = false;
    if (supportsAndroidNotificationKeepAlive) {
      await _keepAlive.disableSoftphonePresence(stopIfOnlySoftphone: true);
    }
    if (sid != null) {
      try {
        await _api.endSoftphoneSession(businessId, sid);
      } catch (_) {}
    }
    sessionId = null;
    mediaTicket = null;
    session = null;
    activeCall = null;
    bridgeActive = false;
    state = SoftphoneConnectionState.ended;
    notifyListeners();
    state = SoftphoneConnectionState.idle;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_wantOnline) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_onAppResumed());
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
        // فقط FGS را زنده نگه دار؛ WS را در UI نگه می‌داریم (جلوگیری از handoff روی نوتیفیکیشن شید)
        unawaited(_enableAndroidPresence(uiHoldingWs: true));
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_onAppBackgrounded(forceHandoff: true));
        break;
    }
  }

  Future<void> _onAppResumed() async {
    await _keepAlive.updateUiAttached(true);
    await _reclaimSoftphoneWsFromFgs();
    await _consumePendingIncomingAction();
  }

  Future<void> _onAppBackgrounded({bool forceHandoff = false}) async {
    await _keepAlive.updateUiAttached(false);
    // در حین مکالمه/زنگ WS را در UI نگه دار تا PCM قطع نشود
    if (!forceHandoff &&
        (state == SoftphoneConnectionState.inCall || state == SoftphoneConnectionState.ringing)) {
      await _enableAndroidPresence(uiHoldingWs: true);
      return;
    }
    // انتقال حضور Softphone به FGS تا بعد از بستن UI هم زنگ برسد
    _uiHoldingWs = false;
    await _enableAndroidPresence(uiHoldingWs: false);
    // بستن WS لوکال تا FGS همان session را بگیرد (handoff)
    try {
      _ws?.disconnect();
    } catch (_) {}
    _ws = null;
  }

  Future<void> _enableAndroidPresence({required bool uiHoldingWs}) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    final apiKey = authStore.apiKey;
    final sid = sessionId;
    final ticket = mediaTicket;
    if (apiKey == null || sid == null || ticket == null) return;
    final ext = '${session?['extension'] ?? health?['extension'] ?? ''}'.trim();
    _uiHoldingWs = uiHoldingWs;
    await _keepAlive.enableSoftphonePresence(
      apiKey: apiKey,
      businessId: businessId,
      sessionId: sid,
      mediaTicket: ticket,
      extension: ext,
      apiBaseUrl: AppConfig.apiBaseUrl,
      uiHoldingWs: uiHoldingWs,
    );
  }

  Future<void> _reclaimSoftphoneWsFromFgs() async {
    if (!_wantOnline) return;
    final apiKey = authStore.apiKey;
    final sid = sessionId;
    final ticket = mediaTicket;
    if (apiKey == null || sid == null || ticket == null) return;
    if (_ws?.isConnected == true) {
      await _keepAlive.setSoftphoneUiHoldingWs(true);
      _uiHoldingWs = true;
      return;
    }
    _uiHoldingWs = true;
    await _keepAlive.setSoftphoneUiHoldingWs(true);
    _ws?.disconnect();
    _ws = createSoftphoneWsClient();
    _ws!.connect(
      apiKey: apiKey,
      businessId: businessId,
      sessionId: sid,
      mediaTicket: ticket,
      onJson: _onWsJson,
      onPcm: _onWsPcm,
      onError: (e) {
        error = '$e';
        state = SoftphoneConnectionState.reconnecting;
        notifyListeners();
        _scheduleReconnect();
      },
      onDone: () {
        if (_wantOnline && _uiHoldingWs && state != SoftphoneConnectionState.idle) {
          state = SoftphoneConnectionState.reconnecting;
          notifyListeners();
          _scheduleReconnect();
        }
      },
    );
  }

  void _scheduleReconnect() {
    if (!_wantOnline || !_uiHoldingWs) return;
    _reconnectTimer?.cancel();
    final delaySec = (1 << _reconnectAttempt.clamp(0, 4)).clamp(1, 16);
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      if (!_wantOnline || !_uiHoldingWs) return;
      try {
        if (sessionId != null && mediaTicket != null && authStore.apiKey != null) {
          await _reclaimSoftphoneWsFromFgs();
          _reconnectAttempt = 0;
        } else {
          await register();
          _reconnectAttempt = 0;
        }
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Future<void> _showAndroidIncomingNotification() async {
    if (!supportsSoftphoneIncomingNotifications) return;
    final ext = '${activeCall?['extension'] ?? session?['extension'] ?? health?['extension'] ?? ''}'.trim();
    await _incomingNotif.showIncomingCall(
      caller: incomingCallerDisplay,
      extension: ext.isEmpty ? '—' : ext,
      callId: activeCallId,
      sessionId: sessionId,
    );
  }

  void _onIncomingNotificationAction(Map<String, dynamic> action) {
    unawaited(_handleIncomingAction(action));
  }

  Future<void> _consumePendingIncomingAction() async {
    final pending = await _incomingNotif.consumePendingAction();
    if (pending != null) {
      await _handleIncomingAction(pending);
    }
  }

  Future<void> _handleIncomingAction(Map<String, dynamic> action) async {
    final kind = '${action['kind'] ?? ''}';
    if (kind != 'softphone_incoming') return;
    final act = '${action['action'] ?? ''}';
    final callId = int.tryParse('${action['call_id'] ?? activeCall?['id'] ?? ''}');
    await softphoneLaunchAppToForeground();
    await _reclaimSoftphoneWsFromFgs();
    if (act == softphoneActionDecline) {
      try {
        await rejectIncoming();
      } catch (_) {}
      return;
    }
    // answer or notification body tap
    if (callId != null) {
      try {
        if (state == SoftphoneConnectionState.ringing || act == softphoneActionAnswer) {
          await answer(callId);
        }
      } catch (e) {
        error = '$e';
        notifyListeners();
      }
    } else {
      unawaited(_resolveIncomingCallId().then((_) async {
        final id = activeCallId;
        if (id != null && act == softphoneActionAnswer) {
          try {
            await answer(id);
          } catch (_) {}
        }
      }));
    }
  }

  void _onFgsSoftphoneMessage(Map<String, dynamic> msg) {
    final type = '${msg['type'] ?? ''}';
    if (type == 'incoming_ring' || type.startsWith('bridge.') || type == 'auth_ok') {
      // وقتی UI WS ندارد، رویدادهای FGS را اعمال کن
      if (_ws == null || _ws?.isConnected != true) {
        _onWsJson(msg);
      } else if (type == 'incoming_ring') {
        // UI هنوز WS دارد؛ فقط اگر هنوز ringing نشده
        if (state != SoftphoneConnectionState.ringing) {
          _onWsJson(msg);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wantOnline = false;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    _silenceFallback?.cancel();
    unawaited(_stopRingtone());
    unawaited(_incomingNotif.cancelIncomingCall());
    _ws?.disconnect();
    unawaited(_media?.stop() ?? Future.value());
    super.dispose();
  }
}

/// نگه‌دارنده سراسری Engine برای Phone Bar و صفحه Softphone.
class SoftphoneEngineStore {
  SoftphoneEngineStore._();
  static final SoftphoneEngineStore instance = SoftphoneEngineStore._();

  SoftphoneEngine? _engine;
  int? _businessId;

  SoftphoneEngine obtain({required int businessId, required AuthStore authStore}) {
    if (_engine != null && _businessId == businessId) return _engine!;
    _engine?.dispose();
    _engine = SoftphoneEngine(businessId: businessId, authStore: authStore);
    _businessId = businessId;
    return _engine!;
  }

  SoftphoneEngine? get engine => _engine;

  Future<void> disposeForBusiness(int businessId) async {
    if (_businessId != businessId) return;
    await _engine?.unregister();
    _engine?.dispose();
    _engine = null;
    _businessId = null;
  }
}
