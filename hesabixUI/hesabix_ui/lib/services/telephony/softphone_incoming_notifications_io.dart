import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

const String softphoneCallChannelId = 'hesabix_softphone_incoming';
const String softphoneCallChannelName = 'تماس ورودی Softphone';
const String softphoneCallChannelDescription =
    'اعلان تمام‌صفحه تماس ورودی وقتی Softphone آنلاین است';
const int softphoneIncomingNotificationId = 9100500;
const String softphoneActionAnswer = 'softphone_answer';
const String softphoneActionDecline = 'softphone_decline';

/// Pending action when user taps Answer/Decline from tray / full-screen intent.
Map<String, dynamic>? _pendingSoftphoneAction;
void Function(Map<String, dynamic> action)? _softphoneActionHandler;

@pragma('vm:entry-point')
void softphoneNotificationActionBackground(NotificationResponse response) {
  final action = _decodeSoftphoneAction(response);
  if (action == null) return;
  _pendingSoftphoneAction = action;
}

Map<String, dynamic>? _decodeSoftphoneAction(NotificationResponse response) {
  final raw = response.payload;
  if (raw == null || raw.isEmpty) return null;
  try {
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final out = Map<String, dynamic>.from(map);
    final id = response.actionId;
    if (id == softphoneActionAnswer || id == softphoneActionDecline) {
      out['action'] = id;
    } else {
      out['action'] = softphoneActionAnswer; // tap body → open/answer UI
    }
    out['kind'] = 'softphone_incoming';
    return out;
  } catch (_) {
    return null;
  }
}

/// Android Call-style / full-screen incoming Softphone notification.
class SoftphoneIncomingNotifications {
  SoftphoneIncomingNotifications();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize({
    void Function(Map<String, dynamic> action)? onAction,
  }) async {
    if (!supportsSoftphoneIncomingNotifications) return;
    _softphoneActionHandler = onAction;
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_hesabix');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        final action = _decodeSoftphoneAction(response);
        if (action == null) return;
        final handler = _softphoneActionHandler;
        if (handler != null) {
          handler(action);
        } else {
          _pendingSoftphoneAction = action;
        }
      },
      onDidReceiveBackgroundNotificationResponse: softphoneNotificationActionBackground,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        softphoneCallChannelId,
        softphoneCallChannelName,
        description: softphoneCallChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch?.notificationResponse != null) {
      final action = _decodeSoftphoneAction(launch!.notificationResponse!);
      if (action != null) {
        _pendingSoftphoneAction = action;
      }
    }

    _initialized = true;
  }

  Future<void> showIncomingCall({
    required String caller,
    required String extension,
    int? callId,
    String? sessionId,
  }) async {
    if (!supportsSoftphoneIncomingNotifications) return;
    if (!_initialized) await initialize(onAction: _softphoneActionHandler);

    final notif = await Permission.notification.status;
    if (!notif.isGranted) {
      await Permission.notification.request();
    }

    final payload = jsonEncode(<String, dynamic>{
      'kind': 'softphone_incoming',
      'caller': caller,
      'extension': extension,
      if (callId != null) 'call_id': callId,
      if (sessionId != null) 'session_id': sessionId,
    });

    final title = 'تماس ورودی · داخلی $extension';
    final body = caller.isEmpty ? 'شماره ناشناس' : caller;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        softphoneCallChannelId,
        softphoneCallChannelName,
        channelDescription: softphoneCallChannelDescription,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
        ticker: title,
        icon: '@drawable/ic_stat_hesabix',
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            softphoneActionAnswer,
            'پاسخ',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            softphoneActionDecline,
            'رد',
            cancelNotification: true,
          ),
        ],
      ),
    );

    await _plugin.show(
      id: softphoneIncomingNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> cancelIncomingCall() async {
    if (!supportsSoftphoneIncomingNotifications) return;
    try {
      await _plugin.cancel(softphoneIncomingNotificationId);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> consumePendingAction() async {
    final a = _pendingSoftphoneAction;
    _pendingSoftphoneAction = null;
    return a;
  }
}

SoftphoneIncomingNotifications createSoftphoneIncomingNotifications() => SoftphoneIncomingNotifications();

bool get supportsSoftphoneIncomingNotifications =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
