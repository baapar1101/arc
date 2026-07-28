import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/android_system_notifications_platform.dart';
import 'notification_payload_codec.dart';

const String _kAndroidChannelId = 'hesabix_inapp';
const String _kAndroidChannelName = 'اعلان‌های حسابیکس';
const String _kAndroidChannelDescription = 'اعلان‌های درون‌برنامه‌ای حسابیکس';

/// Android system-tray notifications via flutter_local_notifications.
class SystemNotificationsService {
  SystemNotificationsService();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  void Function(Map<String, dynamic> item)? _onTap;
  bool _initialized = false;
  Map<String, dynamic>? _launchPayload;

  Future<void> initialize({
    void Function(Map<String, dynamic> item)? onNotificationTap,
  }) async {
    if (!supportsAndroidSystemNotifications) return;
    _onTap = onNotificationTap;
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kAndroidChannelId,
        _kAndroidChannelName,
        description: _kAndroidChannelDescription,
        importance: Importance.high,
      ),
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = NotificationPayloadCodec.decode(launch!.notificationResponse?.payload);
      if (payload != null) {
        _launchPayload = payload;
      }
    }

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    final item = NotificationPayloadCodec.decode(response.payload);
    if (item == null) return;
    _onTap?.call(item);
  }

  Future<bool> ensurePermission() async {
    if (!supportsAndroidSystemNotifications) return false;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  Future<void> showInAppNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    bool playSound = true,
  }) async {
    if (!supportsAndroidSystemNotifications) return;
    if (!_initialized) {
      await initialize(onNotificationTap: _onTap);
    }
    final allowed = await ensurePermission();
    if (!allowed) return;

    final id = _notificationIdFor(payload);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kAndroidChannelId,
        _kAndroidChannelName,
        channelDescription: _kAndroidChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: playSound,
        enableVibration: playSound,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
    );

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: NotificationPayloadCodec.encode(payload),
    );
  }

  Future<Map<String, dynamic>?> consumeLaunchPayload() async {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<void> cancelAll() async {
    if (!supportsAndroidSystemNotifications) return;
    await _plugin.cancelAll();
  }

  int _notificationIdFor(Map<String, dynamic> payload) {
    final annId = payload['id'] ?? payload['announcement_id'];
    if (annId is int) return annId & 0x7fffffff;
    final parsed = int.tryParse('$annId');
    if (parsed != null) return parsed & 0x7fffffff;
    return Object.hashAll([
          payload['deep_link'],
          payload['ticket_id'],
          payload['event_key'],
          payload['title'],
          payload['body'],
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ]).abs() &
        0x7fffffff;
  }
}

SystemNotificationsService createSystemNotificationsService() => SystemNotificationsService();
