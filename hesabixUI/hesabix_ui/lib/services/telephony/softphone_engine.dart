import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/auth_store.dart';
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
class SoftphoneEngine extends ChangeNotifier {
  SoftphoneEngine({
    required this.businessId,
    required this.authStore,
    TelephonyApi? api,
  }) : _api = api ?? TelephonyApi();

  final int businessId;
  final AuthStore authStore;
  final TelephonyApi _api;

  SoftphoneWsClient? _ws;
  SoftphonePcmMedia? _media;
  SoftphoneRingtone? _ringtone;
  Timer? _heartbeat;
  Timer? _silenceFallback;
  bool _micLive = false;

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
      await _media!.start();
      mediaReady = true;

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
        },
        onDone: () {
          if (state != SoftphoneConnectionState.ended && state != SoftphoneConnectionState.idle) {
            state = SoftphoneConnectionState.reconnecting;
            notifyListeners();
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
      throw StateError('کانال Softphone وصل نیست؛ دوباره آنلاین شوید');
    }
    await _stopRingtone();
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

  String? get incomingCallerDisplay {
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
    _heartbeat?.cancel();
    _heartbeat = null;
    await _stopRingtone();
    await _stopLiveMedia();
    final sid = sessionId;
    _ws?.disconnect();
    _ws = null;
    try {
      await _media?.stop();
    } catch (_) {}
    _media = null;
    mediaReady = false;
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
  void dispose() {
    _heartbeat?.cancel();
    _silenceFallback?.cancel();
    unawaited(_stopRingtone());
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
