import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/android_notification_prefs.dart';
import '../../core/android_system_notifications_platform.dart';
import 'android_notification_content_builder.dart';
import 'notification_payload_codec.dart';

const String _kAndroidChannelId = 'hesabix_inapp_v2';
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

    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_hesabix');
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

  Future<bool> ensurePermission({bool requestIfNeeded = true}) async {
    if (!supportsAndroidSystemNotifications) return false;
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await androidPlugin?.areNotificationsEnabled();
    if (enabled == true) return true;
    if (!requestIfNeeded) return false;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  /// Shows a tray notification; enriches title/body from [AndroidNotificationPrefs].
  Future<void> showInAppNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    bool playSound = true,
    bool appIsJalali = true,
    bool enrichContent = true,
    bool requestPermission = true,
  }) async {
    if (!supportsAndroidSystemNotifications) return;
    if (!_initialized) {
      await initialize(onNotificationTap: _onTap);
    }
    final allowed = await ensurePermission(requestIfNeeded: requestPermission);
    if (!allowed) return;

    var showTitle = title;
    var showBody = body;
    if (enrichContent) {
      try {
        final built = await AndroidNotificationContentBuilder.build(
          item: <String, dynamic>{
            ...payload,
            'title': title,
            'body': body,
          },
          appIsJalali: appIsJalali,
        );
        showTitle = built.title;
        showBody = built.body;
      } catch (_) {
        // Prefer plain title/body over failing the whole notification.
      }
    }

    var accent = AndroidNotificationPrefs.defaultAccentColor;
    var led = true;
    var vibrate = true;
    try {
      accent = await AndroidNotificationPrefs.getAccentColor();
      led = await AndroidNotificationPrefs.getLedEnabled();
      vibrate = await AndroidNotificationPrefs.getVibrate();
    } catch (_) {}
    final color = Color(accent);

    final id = _notificationIdFor(payload);
    final largeIconName = AndroidNotificationContentBuilder.largeIconDrawableForTheme();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kAndroidChannelId,
        _kAndroidChannelName,
        channelDescription: _kAndroidChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: playSound,
        enableVibration: vibrate && playSound,
        enableLights: led,
        color: color,
        ledColor: led ? color : null,
        ledOnMs: led ? 800 : null,
        ledOffMs: led ? 400 : null,
        icon: '@drawable/${AndroidNotificationContentBuilder.smallIconDrawable}',
        largeIcon: DrawableResourceAndroidBitmap(largeIconName),
        styleInformation: BigTextStyleInformation(showBody, contentTitle: showTitle),
        ticker: showTitle,
      ),
    );

    await _plugin.show(
      id: id,
      title: showTitle,
      body: showBody,
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
