import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/android_notification_keepalive_platform.dart';
import '../../core/android_notification_prefs.dart';
import '../system_notifications/android_notification_content_builder.dart';
import 'hesabix_notification_keepalive_task_handler.dart';

/// Starts/stops Android foreground keep-alive for the notifications WebSocket.
class AndroidNotificationKeepAliveService {
  AndroidNotificationKeepAliveService();

  bool _initialized = false;
  void Function(Map<String, dynamic> msg)? _onMessage;

  static const NotificationIcon notificationIcon = NotificationIcon(
    metaDataName: 'com.hesabix.notificationIcon',
  );

  Future<void> ensureInitialized() async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (_initialized) return;

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'hesabix_keepalive',
        channelName: 'دریافت اعلان‌های حسابیکس',
        channelDescription: 'سرویس پس‌زمینه برای دریافت اعلان‌ها وقتی برنامه بسته است',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Refresh keep-alive text (clock/date) about once a minute.
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  void _onTaskData(Object data) {
    try {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final kind = '${map['kind'] ?? ''}';
        final type = '${map['type'] ?? ''}';
        if (kind == 'softphone' ||
            type.startsWith('softphone') ||
            map['softphone'] == true ||
            type == 'incoming_ring' ||
            type == 'auth_ok' ||
            type.startsWith('bridge.') ||
            type == 'softphone_ws_done' ||
            type == 'softphone_ws_error') {
          _onSoftphoneMessage?.call(map);
          return;
        }
        _onMessage?.call(map);
      }
    } catch (e) {
      debugPrint('KeepAlive task data error: $e');
    }
  }

  void setOnNotificationMessage(void Function(Map<String, dynamic> msg)? handler) {
    _onMessage = handler;
  }

  void setOnSoftphoneMessage(void Function(Map<String, dynamic> msg)? handler) {
    _onSoftphoneMessage = handler;
  }

  void Function(Map<String, dynamic> msg)? _onSoftphoneMessage;

  Future<bool> isRunning() async {
    if (!supportsAndroidNotificationKeepAlive) return false;
    await ensureInitialized();
    return FlutterForegroundTask.isRunningService;
  }

  /// Softphone online: ensure FGS runs and can hold softphone WS when UI is backgrounded/killed.
  Future<void> enableSoftphonePresence({
    required String apiKey,
    required int businessId,
    required String sessionId,
    required String mediaTicket,
    required String extension,
    required String apiBaseUrl,
    bool appIsJalali = true,
    bool uiHoldingWs = true,
  }) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (apiKey.isEmpty || sessionId.isEmpty || mediaTicket.isEmpty) return;
    await ensureInitialized();

    final notif = await Permission.notification.status;
    if (!notif.isGranted) {
      await Permission.notification.request();
    }

    await FlutterForegroundTask.saveData(key: 'apiKey', value: apiKey);
    await FlutterForegroundTask.saveData(key: 'appIsJalali', value: appIsJalali);
    await FlutterForegroundTask.saveData(key: 'softphoneDesired', value: true);
    await FlutterForegroundTask.saveData(key: 'softphoneUiHoldingWs', value: uiHoldingWs);
    await FlutterForegroundTask.saveData(key: 'softphoneBusinessId', value: businessId);
    await FlutterForegroundTask.saveData(key: 'softphoneSessionId', value: sessionId);
    await FlutterForegroundTask.saveData(key: 'softphoneMediaTicket', value: mediaTicket);
    await FlutterForegroundTask.saveData(key: 'softphoneExtension', value: extension);
    await FlutterForegroundTask.saveData(key: 'softphoneApiBaseUrl', value: apiBaseUrl);

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceTypes: const [
          ForegroundServiceTypes.dataSync,
          ForegroundServiceTypes.microphone,
        ],
        notificationTitle: 'Softphone آنلاین',
        notificationText: extension.isEmpty ? 'آماده دریافت تماس' : 'داخلی $extension · آماده دریافت تماس',
        notificationIcon: notificationIcon,
        notificationInitialRoute: '/',
        callback: hesabixNotificationKeepAliveCallback,
      );
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Softphone آنلاین',
        notificationText: extension.isEmpty ? 'آماده دریافت تماس' : 'داخلی $extension · آماده دریافت تماس',
        notificationIcon: notificationIcon,
      );
    }

    FlutterForegroundTask.sendDataToTask(<String, dynamic>{
      'type': 'softphoneEnable',
      'apiKey': apiKey,
      'businessId': businessId,
      'sessionId': sessionId,
      'mediaTicket': mediaTicket,
      'extension': extension,
      'apiBaseUrl': apiBaseUrl,
      'uiHoldingWs': uiHoldingWs,
    });
  }

  Future<void> setSoftphoneUiHoldingWs(bool holding) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    await FlutterForegroundTask.saveData(key: 'softphoneUiHoldingWs', value: holding);
    if (await isRunning()) {
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'type': 'softphoneUiHoldingWs',
        'value': holding,
      });
    }
  }

  Future<void> disableSoftphonePresence({bool stopIfOnlySoftphone = false}) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    await FlutterForegroundTask.saveData(key: 'softphoneDesired', value: false);
    if (await isRunning()) {
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{'type': 'softphoneDisable'});
    }
    // Keep notification keep-alive if user enabled it; only softphone stops.
    if (stopIfOnlySoftphone) {
      final enabled = await AndroidNotificationPrefs.isKeepAliveEnabled();
      if (!enabled && await isRunning()) {
        await stop();
      } else if (await isRunning()) {
        await refreshStatusNotification();
      }
    }
  }

  Future<void> start({
    required String apiKey,
    required bool appIsJalali,
    bool uiAttached = false,
  }) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (apiKey.isEmpty) return;
    final enabled = await AndroidNotificationPrefs.isKeepAliveEnabled();
    if (!enabled) return;

    await ensureInitialized();
    final notif = await Permission.notification.status;
    if (!notif.isGranted) {
      await Permission.notification.request();
    }

    // Default uiAttached=false so a killed/restarted FGS still shows tray until
    // the UI isolate explicitly confirms it is resumed.
    await FlutterForegroundTask.saveData(key: 'apiKey', value: apiKey);
    await FlutterForegroundTask.saveData(key: 'uiAttached', value: uiAttached);
    await FlutterForegroundTask.saveData(key: 'appIsJalali', value: appIsJalali);

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'type': 'apiKey',
        'value': apiKey,
      });
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'type': 'appIsJalali',
        'value': appIsJalali,
      });
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'type': 'uiAttached',
        'value': uiAttached,
      });
      await refreshStatusNotification();
      return;
    }

    final status = await AndroidNotificationContentBuilder.buildKeepAlive(appIsJalali: appIsJalali);
    await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: status.title,
      notificationText: status.body,
      notificationIcon: notificationIcon,
      notificationInitialRoute: '/user/profile/notifications',
      callback: hesabixNotificationKeepAliveCallback,
    );
  }

  Future<void> stop() async {
    if (!supportsAndroidNotificationKeepAlive) return;
    await ensureInitialized();
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> updateUiAttached(bool attached) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (!await isRunning()) return;
    await FlutterForegroundTask.saveData(key: 'uiAttached', value: attached);
    FlutterForegroundTask.sendDataToTask(<String, dynamic>{
      'type': 'uiAttached',
      'value': attached,
    });
  }

  Future<void> updateApiKey(String apiKey) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (apiKey.isEmpty) return;
    await FlutterForegroundTask.saveData(key: 'apiKey', value: apiKey);
    if (await isRunning()) {
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'type': 'apiKey',
        'value': apiKey,
      });
    }
  }

  /// Rebuild keep-alive title/body from personalization prefs (date/time/brand).
  Future<void> refreshStatusNotification({bool appIsJalali = true}) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (!await isRunning()) return;
    try {
      final status = await AndroidNotificationContentBuilder.buildKeepAlive(appIsJalali: appIsJalali);
      await FlutterForegroundTask.updateService(
        notificationTitle: status.title,
        notificationText: status.body,
        notificationIcon: notificationIcon,
      );
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'type': 'prefsChanged',
      });
    } catch (e) {
      debugPrint('KeepAlive refreshStatusNotification error: $e');
    }
  }
}

AndroidNotificationKeepAliveService createAndroidNotificationKeepAliveService() =>
    AndroidNotificationKeepAliveService();
