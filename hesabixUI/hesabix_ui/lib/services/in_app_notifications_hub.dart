import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../core/api_client.dart';
import '../core/android_system_notifications_platform.dart';
import '../utils/announcement_navigation.dart';
import 'announcements_service.dart';
import 'in_app_notification_preferences_controller.dart';
import 'notification_alert_sound_player.dart';
import 'notification_tap_navigation.dart';
import 'notifications_ws_client.dart';
import 'system_notifications/system_notifications_service.dart';

/// Single owner of the in-app notifications WebSocket + Android system tray.
///
/// Delivery is realtime WebSocket while the app process is alive (no Google/Firebase
/// push). Android tray display and tap→deep-link are handled locally.
///
/// Shells subscribe via [addListener]; they must not open their own WS.
class InAppNotificationsHub extends ChangeNotifier {
  InAppNotificationsHub._();

  static final InAppNotificationsHub instance = InAppNotificationsHub._();

  final SystemNotificationsService _system = createSystemNotificationsService();

  NotificationsWsClient? _ws;
  String? _connectedApiKey;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _bootstrapped = false;

  final List<Map<String, dynamic>> notifications = <Map<String, dynamic>>[];
  int unreadCount = 0;

  /// Fired for foreground in-app SnackBar (UI layer).
  final List<void Function(Map<String, dynamic> item)> _foregroundAlertListeners =
      <void Function(Map<String, dynamic> item)>[];

  final LinkedHashSet<String> _recentDedupKeys = LinkedHashSet<String>();

  /// Only fully-resumed counts as foreground (inactive/paused → system tray).
  bool get isForeground => _lifecycle == AppLifecycleState.resumed;

  void addForegroundAlertListener(void Function(Map<String, dynamic> item) listener) {
    _foregroundAlertListeners.add(listener);
  }

  void removeForegroundAlertListener(void Function(Map<String, dynamic> item) listener) {
    _foregroundAlertListeners.remove(listener);
  }

  void setLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    await InAppNotificationPreferencesController.instance.refreshFromApi().catchError((_) {});

    if (supportsAndroidSystemNotifications) {
      await _system.initialize(
        onNotificationTap: (item) {
          NotificationTapNavigation.instance.enqueue(item);
        },
      );
      // Ask early so background tray works as soon as the user leaves the app.
      unawaited(_system.ensurePermission());
      final launch = await _system.consumeLaunchPayload();
      if (launch != null) {
        NotificationTapNavigation.instance.enqueue(launch);
      }
    }
  }

  Future<void> startForApiKey(String apiKey) async {
    if (apiKey.isEmpty) return;
    await bootstrap();
    if (_connectedApiKey == apiKey && _ws != null) return;

    await stop(clearUi: false);
    _connectedApiKey = apiKey;
    await refreshFromApi();

    _ws = createNotificationsWsClient();
    _ws!.connect(
      apiKey: apiKey,
      onMessage: (msg) {
        try {
          if ('${msg['type'] ?? ''}' != 'notification') return;
          final title = '${msg['title'] ?? 'پیام'}';
          final body = '${msg['body'] ?? ''}';
          final level = '${msg['level'] ?? 'info'}';
          final dynamic aid = msg['announcement_id'];
          final int? annId = aid is int ? aid : int.tryParse('$aid');
          final deepLink = msg['deep_link']?.toString();
          final eventKey = msg['event_key']?.toString();
          final ticketId = msg['ticket_id'];
          _ingestNotification(
            AnnouncementNavigation.normalizeItem(<String, dynamic>{
              'title': title,
              'body': body,
              'level': level,
              if (annId != null) 'id': annId,
              if (deepLink != null && deepLink.isNotEmpty) 'deep_link': deepLink,
              if (eventKey != null && eventKey.isNotEmpty) 'event_key': eventKey,
              if (ticketId != null) 'ticket_id': ticketId,
              'is_read': false,
            }),
          );
        } catch (_) {}
      },
    );
  }

  Future<void> stop({bool clearUi = true}) async {
    try {
      _ws?.disconnect();
    } catch (_) {}
    _ws = null;
    _connectedApiKey = null;
    if (clearUi) {
      notifications.clear();
      unreadCount = 0;
      notifyListeners();
    }
  }

  Future<void> onLogout() async {
    await _system.cancelAll();
    NotificationTapNavigation.instance.clear();
    await stop(clearUi: true);
  }

  Future<void> refreshFromApi() async {
    try {
      final data = await AnnouncementsService(ApiClient()).listAnnouncements(
        page: 1,
        limit: 5,
        onlyUnread: true,
      );
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final total = (data['total'] is int)
          ? data['total'] as int
          : (int.tryParse('${data['total']}') ?? items.length);
      notifications
        ..clear()
        ..addAll(items.map(AnnouncementNavigation.normalizeItem));
      unreadCount = total.clamp(0, 99);
      notifyListeners();
    } catch (_) {}
  }

  void markLocallyRead(int announcementId) {
    notifications.removeWhere(
      (e) => AnnouncementNavigation.parseAnnouncementId(e['id']) == announcementId,
    );
    unreadCount = (unreadCount - 1).clamp(0, 99);
    notifyListeners();
  }

  void clearLocal() {
    notifications.clear();
    unreadCount = 0;
    notifyListeners();
  }

  void _ingestNotification(Map<String, dynamic> raw) {
    final prefs = InAppNotificationPreferencesController.instance;
    final item = AnnouncementNavigation.normalizeItem(raw);
    final dedupKey = _dedupKey(item);
    if (_recentDedupKeys.contains(dedupKey)) return;
    _recentDedupKeys.add(dedupKey);
    while (_recentDedupKeys.length > 200) {
      _recentDedupKeys.remove(_recentDedupKeys.first);
    }

    // Always keep list/badge in sync (including DND).
    notifications.insert(0, item);
    if (notifications.length > 30) {
      notifications.removeRange(30, notifications.length);
    }
    unreadCount = (unreadCount + 1).clamp(0, 99);
    notifyListeners();

    if (prefs.mode == InAppAlertMode.doNotDisturb) {
      return;
    }

    final playSound = prefs.mode == InAppAlertMode.normal && prefs.soundEnabled;
    final title = '${item['title'] ?? 'پیام'}';
    final body = '${item['body'] ?? ''}';

    if (isForeground) {
      if (playSound) {
        unawaited(NotificationAlertSoundPlayer.playForSoundAssetId(prefs.soundAssetId));
      }
      for (final listener in List<void Function(Map<String, dynamic>)>.from(_foregroundAlertListeners)) {
        try {
          listener(item);
        } catch (_) {}
      }
      return;
    }

    // App not in foreground: Android system tray (tap → deep link).
    if (supportsAndroidSystemNotifications) {
      unawaited(
        _system.showInAppNotification(
          title: title,
          body: body,
          payload: item,
          playSound: playSound,
        ),
      );
    }
  }

  String _dedupKey(Map<String, dynamic> item) {
    final id = AnnouncementNavigation.parseAnnouncementId(item['id']);
    if (id != null) return 'a:$id';
    return 't:${item['ticket_id']}|${item['event_key']}|${item['title']}|${item['body']}';
  }
}
