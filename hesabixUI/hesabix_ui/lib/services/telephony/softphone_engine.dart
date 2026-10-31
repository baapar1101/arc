import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/app_config.dart';
import '../../config/brand_config.dart';
import '../../core/android_notification_keepalive_platform.dart';
import '../../core/auth_store.dart';
import '../../core/windows_update_platform.dart';
import '../android_notification_keepalive/android_notification_keepalive_service.dart';
import '../errors/api_error.dart';
import '../windows_desktop/windows_desktop_shell.dart';
import 'softphone_android_launch.dart';
import 'softphone_background_presence.dart';
import 'softphone_incoming_notifications.dart';
import 'softphone_pcm_media.dart';
import 'softphone_ringtone.dart';
import 'softphone_ws_client.dart';
import 'telephony_api.dart';
import 'telephony_l10n.dart';

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
/// اندروید: با Foreground Service زنده می‌ماند؛ heartbeat REST داخل FGS است و
/// بعد از بوت اگر قبلاً آنلاین بوده دوباره وصل می‌شود.
/// ویندوز: بستن پنجره به سینی سیستم می‌رود، WS زنده می‌ماند و تماس ورودی
/// ناتیفیکیشن + جلو آمدن پنجره دارد.
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
    if (supportsWindowsDesktopUpdate) {
      WindowsDesktopShell.install();
      WindowsDesktopShell.onTrayShow = () async {
        await _onAppResumed();
      };
      WindowsDesktopShell.onIncomingClicked = () async {
        await _onAppResumed();
      };
      WindowsDesktopShell.onTrayExit = () async {
        await unregister();
        await WindowsDesktopShell.quit();
      };
    }
    unawaited(_restoreAndroidPresence());
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
  final BytesBuilder _outPcmBuf = BytesBuilder(copy: false);
  static const int _pcmFrameBytes = 320; // 20ms @ 8kHz mono PCM16
  DateTime? _lastMicFrameAt;

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

  /// Close-to-tray / FGS should keep the session when the operator is online.
  bool get wantsBackgroundPresence =>
      _wantOnline && sessionId != null && sessionId!.isNotEmpty;

  String get statusDetail {
    final parts = <String>[];
    final t = telephonyL10n();
    if (mediaReady) parts.add(t.telephonyAudioReady);
    if (_micLive) parts.add(t.telephonyMicrophone);
    if (bridgeActive) parts.add(t.telephonyBridgeActive);
    if (muted) parts.add(t.telephonyMute);
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
      error = telephonyL10n().telephonyApiKeyMissing;
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
        error = telephonyL10n().telephonyMediaFailed('$e');
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
        throw StateError(telephonyL10n().telephonyIncompleteSession);
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
        await _runHeartbeat();
      });

      await _enableAndroidPresence(uiHoldingWs: true);
      await _enableWindowsPresence();
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
        unawaited(_showIncomingNotification());
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
          _lastMicFrameAt = DateTime.now();
          _emitOutgoingPcm(sid, chunk);
        });
        _micLive = true;
      }
    } catch (e) {
      // اگر میکروفون بالا نیامد، سکوت بفرست تا پل Asterisk قطع نشود
      error = telephonyL10n().telephonyMicFallback('$e');
      _startSilenceFallback();
      notifyListeners();
      return;
    }

    // اگر فریم میکروفون دیر رسید، برای چند ثانیه اول سکوت هم بفرست تا AudioSocket زنده بماند
    _startSilenceFallback(onlyWhenNoMicFrames: true);
    notifyListeners();
  }

  void _emitOutgoingPcm(String sid, List<int> chunk) {
    if (chunk.isEmpty) return;
    _outPcmBuf.add(chunk);
    var data = _outPcmBuf.toBytes();
    _outPcmBuf.clear();
    var offset = 0;
    while (offset + _pcmFrameBytes <= data.length) {
      final frame = data.sublist(offset, offset + _pcmFrameBytes);
      _ws?.sendPcm(sid, frame);
      outgoingPcmFrames += 1;
      offset += _pcmFrameBytes;
    }
    if (offset < data.length) {
      _outPcmBuf.add(data.sublist(offset));
    }
    if (outgoingPcmFrames % 50 == 0) notifyListeners();
  }

  void _startSilenceFallback({bool onlyWhenNoMicFrames = false}) {
    _silenceFallback?.cancel();
    final silence = List<int>.filled(_pcmFrameBytes, 0); // 20ms @ 8kHz
    _silenceFallback = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!bridgeActive || muted) return;
      final sid = sessionId;
      final ws = _ws;
      if (sid == null || ws == null || !ws.isConnected) return;
      if (onlyWhenNoMicFrames && _micLive) {
        final last = _lastMicFrameAt;
        if (last != null && DateTime.now().difference(last).inMilliseconds < 80) {
          return;
        }
      }
      ws.sendPcm(sid, silence);
      outgoingPcmFrames += 1;
    });
  }

  Future<void> _stopLiveMedia() async {
    _silenceFallback?.cancel();
    _silenceFallback = null;
    _outPcmBuf.clear();
    _lastMicFrameAt = null;
    try {
      await _media?.stopMic();
    } catch (_) {}
    _micLive = false;
  }

  Future<void> dial(String destination, {int? personId, int? leadId}) async {
    final sid = sessionId;
    if (sid == null) throw StateError(telephonyL10n().telephonyGoOnlineFirst);
    if (!isReady || _ws == null || !_ws!.isConnected) {
      throw StateError(telephonyL10n().telephonyChannelNotConnected);
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
    if (sid == null) throw StateError(telephonyL10n().telephonyNoSession);
    if (_ws == null || !_ws!.isConnected) {
      // ممکن است WS در FGS باشد — اول reclaim کن
      await _reclaimSoftphoneWsFromFgs();
      if (_ws == null || !_ws!.isConnected) {
        throw StateError(telephonyL10n().telephonyChannelNotConnected);
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
    final channel = '${activeCall?['channel'] ?? ''}'.trim();
    await _stopRingtone();
    await _incomingNotif.cancelIncomingCall();
    _ws?.sendJson({
      'type': 'hangup_media',
      'reason': 'user_hangup',
      if (sid != null) 'session_id': sid,
      if (callId != null) 'call_id': callId,
      if (channel.isNotEmpty) 'channel': channel,
    });
    if (callId != null) {
      try {
        await _api.controlCall(
          businessId,
          callId,
          action: 'hangup',
          extra: {
            if (sid != null) 'session_id': sid,
            if (channel.isNotEmpty) 'channel': channel,
          },
        );
      } catch (_) {}
    }
    bridgeActive = false;
    _outPcmBuf.clear();
    _lastMicFrameAt = null;
    await _stopLiveMedia();
    activeCall = null;
    state = SoftphoneConnectionState.registered;
    notifyListeners();
  }

  String get incomingCallerDisplay {
    final from = '${activeCall?['from'] ?? ''}'.trim();
    if (from.isNotEmpty && from != 'null') return from;
    return telephonyL10n().telephonyUnknownNumber;
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
    await _disableWindowsPresence();
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
        if (supportsAndroidNotificationKeepAlive) {
          unawaited(_onAppBackgrounded(forceHandoff: true));
        }
        break;
    }
  }

  Future<void> _onAppResumed() async {
    await _keepAlive.updateUiAttached(true);
    await _restoreAndroidPresence();
    await _reclaimSoftphoneWsFromFgs();
    await _consumePendingIncomingAction();
  }

  Future<void> _restoreAndroidPresence() async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (sessionId != null && sessionId!.isNotEmpty && mediaTicket != null && mediaTicket!.isNotEmpty) {
      return;
    }
    final snap = await _keepAlive.loadSoftphonePresence();
    if (snap == null) return;
    final snapBusinessId = int.tryParse('${snap['businessId'] ?? ''}');
    if (snapBusinessId != null && snapBusinessId != businessId) return;
    final sid = '${snap['sessionId'] ?? ''}'.trim();
    final ticket = '${snap['mediaTicket'] ?? ''}'.trim();
    if (sid.isEmpty || ticket.isEmpty) return;
    sessionId = sid;
    mediaTicket = ticket;
    _wantOnline = true;
    if (state == SoftphoneConnectionState.idle || state == SoftphoneConnectionState.ended) {
      state = SoftphoneConnectionState.reconnecting;
    }
    notifyListeners();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 45), (_) async {
      await _runHeartbeat();
    });
    await _enableAndroidPresence(uiHoldingWs: true);
    await _reclaimSoftphoneWsFromFgs();
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

  Future<void> _showIncomingNotification() async {
    final ext = '${activeCall?['extension'] ?? session?['extension'] ?? health?['extension'] ?? ''}'.trim();
    final extension = ext.isEmpty ? '—' : ext;
    if (supportsSoftphoneIncomingNotifications) {
      await _incomingNotif.showIncomingCall(
        caller: incomingCallerDisplay,
        extension: extension,
        callId: activeCallId,
        sessionId: sessionId,
      );
    }
    if (supportsWindowsDesktopUpdate) {
      await WindowsDesktopShell.showIncomingCall(
        title: telephonyL10n().telephonyIncomingExt(extension),
        body: incomingCallerDisplay.isEmpty ? telephonyL10n().telephonyUnknownNumber : incomingCallerDisplay,
      );
    }
  }

  String get windowsTrayTooltip {
    final ext = '${session?['extension'] ?? health?['extension'] ?? ''}'.trim();
    return ext.isEmpty ? telephonyL10n().telephonySoftphoneOnlineTooltip : telephonyL10n().telephonySoftphoneExt(ext);
  }

  Future<void> _enableWindowsPresence() async {
    if (!supportsWindowsDesktopUpdate) return;
    await WindowsDesktopShell.setTray(
      visible: true,
      tooltip: windowsTrayTooltip,
      showLabel: telephonyL10n().branded(telephonyL10n().telephonyShowHesabix),
      exitLabel: telephonyL10n().telephonyExit,
    );
  }

  Future<void> _disableWindowsPresence() async {
    if (!supportsWindowsDesktopUpdate) return;
    await WindowsDesktopShell.setTray(visible: false);
  }

  Future<void> _runHeartbeat() async {
    final sid = sessionId;
    if (sid == null || !_wantOnline) return;
    try {
      session = await _api.softphoneHeartbeat(businessId, sid);
    } catch (e) {
      if (_wantOnline && isSoftphoneSessionGoneCode(_apiErrorCode(e))) {
        try {
          await register();
        } catch (_) {}
      }
    }
  }

  String? _apiErrorCode(Object error) {
    if (error is DioException && error.error is ApiErrorDetails) {
      return (error.error as ApiErrorDetails).code;
    }
    if (error is ApiErrorDetails) return error.code;
    return null;
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
    await _restoreAndroidPresence();
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
    if (type == 'softphone_session_replaced') {
      final sid = '${msg['session_id'] ?? ''}'.trim();
      final ticket = '${msg['media_ticket'] ?? ''}'.trim();
      if (sid.isEmpty || ticket.isEmpty) return;
      sessionId = sid;
      mediaTicket = ticket;
      if (msg['session'] is Map) {
        session = Map<String, dynamic>.from(msg['session'] as Map);
      }
      notifyListeners();
      if (_wantOnline && _uiHoldingWs) {
        unawaited(_reclaimSoftphoneWsFromFgs());
      }
      return;
    }
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
    if (supportsWindowsDesktopUpdate) {
      WindowsDesktopShell.onTrayShow = null;
      WindowsDesktopShell.onIncomingClicked = null;
      WindowsDesktopShell.onTrayExit = null;
    }
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
