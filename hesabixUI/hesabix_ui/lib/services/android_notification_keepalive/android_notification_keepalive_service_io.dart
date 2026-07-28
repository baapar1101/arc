import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/android_notification_keepalive_platform.dart';
import '../../core/android_notification_prefs.dart';
import 'hesabix_notification_keepalive_task_handler.dart';

/// Starts/stops Android foreground keep-alive for the notifications WebSocket.
class AndroidNotificationKeepAliveService {
  AndroidNotificationKeepAliveService();

  bool _initialized = false;
  void Function(Map<String, dynamic> msg)? _onMessage;

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
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
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
        _onMessage?.call(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('KeepAlive task data error: $e');
    }
  }

  void setOnNotificationMessage(void Function(Map<String, dynamic> msg)? handler) {
    _onMessage = handler;
  }

  Future<bool> isRunning() async {
    if (!supportsAndroidNotificationKeepAlive) return false;
    await ensureInitialized();
    return FlutterForegroundTask.isRunningService;
  }

  Future<void> start({required String apiKey, required bool appIsJalali}) async {
    if (!supportsAndroidNotificationKeepAlive) return;
    if (apiKey.isEmpty) return;
    final enabled = await AndroidNotificationPrefs.isKeepAliveEnabled();
    if (!enabled) return;

    await ensureInitialized();
    final notif = await Permission.notification.status;
    if (!notif.isGranted) {
      await Permission.notification.request();
    }

    await FlutterForegroundTask.saveData(key: 'apiKey', value: apiKey);
    await FlutterForegroundTask.saveData(key: 'uiAttached', value: true);
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
      return;
    }

    await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'حسابیکس · دریافت اعلان‌ها',
      notificationText: 'اتصال پس‌زمینه فعال است. برای توقف از تنظیمات ناتیفیکیشن استفاده کنید.',
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
}

AndroidNotificationKeepAliveService createAndroidNotificationKeepAliveService() =>
    AndroidNotificationKeepAliveService();
