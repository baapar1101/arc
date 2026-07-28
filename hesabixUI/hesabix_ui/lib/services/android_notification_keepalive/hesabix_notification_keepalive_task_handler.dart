import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../notifications_ws_client.dart';
import '../system_notifications/android_notification_content_builder.dart';
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
  // Default false: if UI process is dead/killed, still show tray notifications.
  bool _uiAttached = false;
  bool _appIsJalali = true;
  String? _apiKey;

  static const NotificationIcon _notificationIcon = NotificationIcon(
    metaDataName: 'com.hesabix.notificationIcon',
  );

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _sys.initialize();
    _apiKey = await FlutterForegroundTask.getData<String>(key: 'apiKey');
    // Prefer false when missing so a restarted FGS does not suppress trays forever.
    _uiAttached = (await FlutterForegroundTask.getData<bool>(key: 'uiAttached')) ?? false;
    _appIsJalali = (await FlutterForegroundTask.getData<bool>(key: 'appIsJalali')) ?? true;
    await _refreshKeepAliveNotification(timestamp);
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
      }
    } catch (e, st) {
      debugPrint('KeepAlive onReceiveData error: $e\n$st');
    }
  }
}
