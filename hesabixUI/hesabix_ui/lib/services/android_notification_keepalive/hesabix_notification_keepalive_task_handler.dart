import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../notifications_ws_client.dart';
import '../system_notifications/android_notification_content_builder.dart';
import '../system_notifications/system_notifications_service.dart';
import '../system_notifications/notification_payload_codec.dart';
import '../telephony/softphone_incoming_notifications.dart';
import '../telephony/softphone_ws_client.dart';

/// Background isolate entry for [FlutterForegroundTask].
@pragma('vm:entry-point')
void hesabixNotificationKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(HesabixNotificationKeepAliveTaskHandler());
}

class HesabixNotificationKeepAliveTaskHandler extends TaskHandler {
  NotificationsWsClient? _ws;
  SoftphoneWsClient? _softphoneWs;
  final SystemNotificationsService _sys = createSystemNotificationsService();
  final SoftphoneIncomingNotifications _softphoneNotif = createSoftphoneIncomingNotifications();
  // Default false: if UI process is dead/killed, still show tray notifications.
  bool _uiAttached = false;
  bool _appIsJalali = true;
  String? _apiKey;

  bool _softphoneDesired = false;
  bool _softphoneUiHoldingWs = true;
  int? _softphoneBusinessId;
  String? _softphoneSessionId;
  String? _softphoneMediaTicket;
  String? _softphoneExtension;
  String? _softphoneApiBaseUrl;

  static const NotificationIcon _notificationIcon = NotificationIcon(
    metaDataName: 'com.hesabix.notificationIcon',
  );

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _sys.initialize();
    await _softphoneNotif.initialize();
    _apiKey = await FlutterForegroundTask.getData<String>(key: 'apiKey');
    // Prefer false when missing so a restarted FGS does not suppress trays forever.
    _uiAttached = (await FlutterForegroundTask.getData<bool>(key: 'uiAttached')) ?? false;
    _appIsJalali = (await FlutterForegroundTask.getData<bool>(key: 'appIsJalali')) ?? true;
    _softphoneDesired = (await FlutterForegroundTask.getData<bool>(key: 'softphoneDesired')) ?? false;
    _softphoneUiHoldingWs = (await FlutterForegroundTask.getData<bool>(key: 'softphoneUiHoldingWs')) ?? true;
    _softphoneBusinessId = await FlutterForegroundTask.getData<int>(key: 'softphoneBusinessId');
    _softphoneSessionId = await FlutterForegroundTask.getData<String>(key: 'softphoneSessionId');
    _softphoneMediaTicket = await FlutterForegroundTask.getData<String>(key: 'softphoneMediaTicket');
    _softphoneExtension = await FlutterForegroundTask.getData<String>(key: 'softphoneExtension');
    _softphoneApiBaseUrl = await FlutterForegroundTask.getData<String>(key: 'softphoneApiBaseUrl');
    await _refreshKeepAliveNotification(timestamp);
    await _connectWs();
    await _syncSoftphoneWs();
  }

  Future<void> _connectWs() async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return;
    try {
      _ws?.disconnect();
    } catch (_) {}
    _ws = createNotificationsWsClient();
    _ws!.connect(
      apiKey: key,
      onMessage: (msg) async {
        try {
          if ('${msg['type'] ?? ''}' != 'notification') return;
          // Forward to UI isolate (badge / snackbar when attached).
          FlutterForegroundTask.sendDataToMain(msg);

          // Always show content tray from FGS. If the UI process dies without a
          // clean lifecycle update, a stale uiAttached=true must not silence us.
          // Same notification id on the UI fallback path replaces rather than duplicates.
          await _showTray(msg);
        } catch (e, st) {
          debugPrint('KeepAlive notification handling error: $e\n$st');
        }
      },
    );
  }

  Future<void> _syncSoftphoneWs() async {
    if (!_softphoneDesired || _softphoneUiHoldingWs) {
      _disconnectSoftphoneWs();
      return;
    }
    final apiKey = _apiKey;
    final sid = _softphoneSessionId;
    final ticket = _softphoneMediaTicket;
    final businessId = _softphoneBusinessId;
    if (apiKey == null || apiKey.isEmpty || sid == null || ticket == null || businessId == null) {
      return;
    }
    if (_softphoneWs?.isConnected == true) return;

    try {
      _softphoneWs?.disconnect();
    } catch (_) {}
    _softphoneWs = createSoftphoneWsClient();
    _softphoneWs!.connect(
      apiKey: apiKey,
      businessId: businessId,
      sessionId: sid,
      mediaTicket: ticket,
      onJson: (msg) {
        final type = '${msg['type'] ?? ''}';
        FlutterForegroundTask.sendDataToMain({...msg, 'softphone': true});
        if (type == 'incoming_ring') {
          unawaited(_onSoftphoneIncomingRing(msg));
        } else if (type == 'bridge.ended' || type == 'bridge.failed') {
          unawaited(_softphoneNotif.cancelIncomingCall());
        }
      },
      onPcm: (_, __) {
        // Presence-only in FGS; media stays on UI SoftphoneEngine after reclaim.
      },
      onError: (e) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'softphone_ws_error',
          'softphone': true,
          'error': '$e',
        });
      },
      onDone: () {
        FlutterForegroundTask.sendDataToMain({
          'type': 'softphone_ws_done',
          'softphone': true,
        });
        // Auto-reconnect presence while desired and UI not holding WS.
        if (_softphoneDesired && !_softphoneUiHoldingWs) {
          Future<void>.delayed(const Duration(seconds: 2), _syncSoftphoneWs);
        }
      },
    );
  }

  void _disconnectSoftphoneWs() {
    try {
      _softphoneWs?.disconnect();
    } catch (_) {}
    _softphoneWs = null;
  }

  Future<void> _onSoftphoneIncomingRing(Map<String, dynamic> msg) async {
    final caller = '${msg['from'] ?? ''}'.trim();
    final ext = '${msg['extension'] ?? _softphoneExtension ?? ''}'.trim();
    final callId = int.tryParse('${msg['call_id'] ?? ''}');
    await _softphoneNotif.showIncomingCall(
      caller: caller.isEmpty ? 'شماره ناشناس' : caller,
      extension: ext.isEmpty ? '—' : ext,
      callId: callId,
      sessionId: _softphoneSessionId,
    );
    try {
      FlutterForegroundTask.launchApp('/');
    } catch (e) {
      debugPrint('Softphone launchApp failed: $e');
    }
  }

  Future<void> _showTray(Map<String, dynamic> msg) async {
    final title = '${msg['title'] ?? 'پیام'}';
    final body = '${msg['body'] ?? ''}';
    final aid = msg['announcement_id'];
    final int? annId = aid is int ? aid : int.tryParse('$aid');
    final payload = NotificationPayloadCodec.fromStringMap(<String, dynamic>{
      ...msg,
      if (annId != null) 'id': annId,
      'title': title,
      'body': body,
    });
    await _sys.showInAppNotification(
      title: title,
      body: body,
      payload: payload,
      playSound: true,
      appIsJalali: _appIsJalali,
      enrichContent: true,
      // Background isolate must not call permission dialogs.
      requestPermission: false,
    );
  }

  Future<void> _refreshKeepAliveNotification([DateTime? now]) async {
    try {
      if (_softphoneDesired) {
        final ext = (_softphoneExtension ?? '').trim();
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Softphone آنلاین',
          notificationText: ext.isEmpty ? 'آماده دریافت تماس' : 'داخلی $ext · آماده دریافت تماس',
          notificationIcon: _notificationIcon,
        );
        return;
      }
      final built = await AndroidNotificationContentBuilder.buildKeepAlive(
        appIsJalali: _appIsJalali,
        now: now ?? DateTime.now(),
      );
      await FlutterForegroundTask.updateService(
        notificationTitle: built.title,
        notificationText: built.body,
        notificationIcon: _notificationIcon,
      );
    } catch (e, st) {
      debugPrint('KeepAlive status notification update error: $e\n$st');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Refresh personalized clock/date on the persistent FGS notification.
    unawaited(_refreshKeepAliveNotification(timestamp));
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      _ws?.disconnect();
    } catch (_) {}
    _ws = null;
    _disconnectSoftphoneWs();
  }

  @override
  void onReceiveData(Object data) {
    try {
      Map<String, dynamic>? map;
      if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      }
      if (map == null) return;
      final type = '${map['type'] ?? ''}';
      if (type == 'uiAttached') {
        _uiAttached = map['value'] == true;
        FlutterForegroundTask.saveData(key: 'uiAttached', value: _uiAttached);
      } else if (type == 'apiKey') {
        final key = map['value']?.toString();
        if (key != null && key.isNotEmpty && key != _apiKey) {
          _apiKey = key;
          FlutterForegroundTask.saveData(key: 'apiKey', value: key);
          _connectWs();
        }
      } else if (type == 'appIsJalali') {
        _appIsJalali = map['value'] == true;
        FlutterForegroundTask.saveData(key: 'appIsJalali', value: _appIsJalali);
        unawaited(_refreshKeepAliveNotification());
      } else if (type == 'prefsChanged' || type == 'refreshStatus') {
        unawaited(_refreshKeepAliveNotification());
      } else if (type == 'reconnect') {
        _connectWs();
      } else if (type == 'softphoneEnable') {
        _softphoneDesired = true;
        _apiKey = '${map['apiKey'] ?? _apiKey ?? ''}';
        _softphoneBusinessId = int.tryParse('${map['businessId']}') ?? _softphoneBusinessId;
        _softphoneSessionId = '${map['sessionId'] ?? ''}';
        _softphoneMediaTicket = '${map['mediaTicket'] ?? ''}';
        _softphoneExtension = '${map['extension'] ?? ''}';
        _softphoneApiBaseUrl = '${map['apiBaseUrl'] ?? ''}';
        _softphoneUiHoldingWs = map['uiHoldingWs'] != false;
        FlutterForegroundTask.saveData(key: 'softphoneDesired', value: true);
        FlutterForegroundTask.saveData(key: 'softphoneUiHoldingWs', value: _softphoneUiHoldingWs);
        if (_apiKey != null) FlutterForegroundTask.saveData(key: 'apiKey', value: _apiKey!);
        if (_softphoneBusinessId != null) {
          FlutterForegroundTask.saveData(key: 'softphoneBusinessId', value: _softphoneBusinessId!);
        }
        FlutterForegroundTask.saveData(key: 'softphoneSessionId', value: _softphoneSessionId);
        FlutterForegroundTask.saveData(key: 'softphoneMediaTicket', value: _softphoneMediaTicket);
        FlutterForegroundTask.saveData(key: 'softphoneExtension', value: _softphoneExtension);
        FlutterForegroundTask.saveData(key: 'softphoneApiBaseUrl', value: _softphoneApiBaseUrl);
        unawaited(_refreshKeepAliveNotification());
        unawaited(_syncSoftphoneWs());
      } else if (type == 'softphoneUiHoldingWs') {
        _softphoneUiHoldingWs = map['value'] == true;
        FlutterForegroundTask.saveData(key: 'softphoneUiHoldingWs', value: _softphoneUiHoldingWs);
        unawaited(_syncSoftphoneWs());
      } else if (type == 'softphoneDisable') {
        _softphoneDesired = false;
        FlutterForegroundTask.saveData(key: 'softphoneDesired', value: false);
        _disconnectSoftphoneWs();
        unawaited(_softphoneNotif.cancelIncomingCall());
        unawaited(_refreshKeepAliveNotification());
      } else if (type == 'softphoneAnswer') {
        final callId = int.tryParse('${map['call_id'] ?? ''}');
        if (callId != null) unawaited(_httpSoftphoneAnswer(callId));
      } else if (type == 'softphoneDecline') {
        unawaited(_httpSoftphoneHangup());
        unawaited(_softphoneNotif.cancelIncomingCall());
      }
    } catch (e, st) {
      debugPrint('KeepAlive onReceiveData error: $e\n$st');
    }
  }

  Future<void> _httpSoftphoneAnswer(int callId) async {
    final base = (_softphoneApiBaseUrl ?? '').replaceAll(RegExp(r'/+$'), '');
    final apiKey = _apiKey;
    final sid = _softphoneSessionId;
    final businessId = _softphoneBusinessId;
    if (base.isEmpty || apiKey == null || sid == null || businessId == null) return;
    try {
      final uri = Uri.parse('$base/api/v1/telephony/business/$businessId/softphone/calls/$callId/answer');
      final client = HttpClient();
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'ApiKey $apiKey');
      req.add(utf8.encode(jsonEncode({'session_id': sid})));
      final res = await req.close();
      await res.drain<void>();
      client.close(force: true);
      await _softphoneNotif.cancelIncomingCall();
      try {
        FlutterForegroundTask.launchApp('/');
      } catch (_) {}
    } catch (e) {
      debugPrint('FGS softphone answer failed: $e');
    }
  }

  Future<void> _httpSoftphoneHangup() async {
    final base = (_softphoneApiBaseUrl ?? '').replaceAll(RegExp(r'/+$'), '');
    final apiKey = _apiKey;
    final sid = _softphoneSessionId;
    final businessId = _softphoneBusinessId;
    if (base.isEmpty || apiKey == null || sid == null || businessId == null) return;
    try {
      // Best-effort: hangup_media via softphone WS if present.
      _softphoneWs?.sendJson({'type': 'hangup_media', 'reason': 'user_reject', 'session_id': sid});
      final client = HttpClient();
      client.close(force: true);
    } catch (e) {
      debugPrint('FGS softphone decline failed: $e');
    }
  }
}
