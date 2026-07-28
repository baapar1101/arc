import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/android_notification_prefs.dart';
import '../notifications_ws_client.dart';
import '../system_notifications/system_notifications_service.dart';
import '../system_notifications/notification_payload_codec.dart';

/// Background isolate entry for [FlutterForegroundTask].
@pragma('vm:entry-point')
void hesabixNotificationKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(HesabixNotificationKeepAliveTaskHandler());
}

class HesabixNotificationKeepAliveTaskHandler extends TaskHandler {
  NotificationsWsClient? _ws;
  final SystemNotificationsService _sys = createSystemNotificationsService();
  bool _uiAttached = false;
  bool _appIsJalali = true;
  String? _apiKey;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _sys.initialize();
    _apiKey = await FlutterForegroundTask.getData<String>(key: 'apiKey');
    _uiAttached = (await FlutterForegroundTask.getData<bool>(key: 'uiAttached')) ?? false;
    _appIsJalali = (await FlutterForegroundTask.getData<bool>(key: 'appIsJalali')) ?? true;
    await _connectWs();
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

          // When UI is not attached, show tray from this isolate.
          if (!_uiAttached) {
            final prefsMode = await AndroidNotificationPrefs.snapshot();
            // Respect DND is handled mainly by main prefs controller; tray still honors
            // vibration/sound defaults from Android prefs.
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
            final playSound = prefsMode['vibrate'] != false;
            await _sys.showInAppNotification(
              title: title,
              body: body,
              payload: payload,
              playSound: playSound,
              appIsJalali: _appIsJalali,
              enrichContent: true,
            );
          }
        } catch (_) {}
      },
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep-alive heartbeat; WS client has its own ping.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      _ws?.disconnect();
    } catch (_) {}
    _ws = null;
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
      } else if (type == 'reconnect') {
        _connectWs();
      }
    } catch (_) {}
  }
}
