import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

import '../core/api_client.dart';
import '../core/android_notification_keepalive_platform.dart';
import '../core/android_notification_prefs.dart';
import '../core/android_system_notifications_platform.dart';
import '../utils/announcement_navigation.dart';
import 'android_notification_keepalive/android_notification_keepalive_service.dart';
import 'announcements_service.dart';
import 'in_app_notification_preferences_controller.dart';
import 'notification_alert_sound_player.dart';
import 'notification_tap_navigation.dart';
import 'notifications_ws_client.dart';
import 'system_notifications/system_notifications_service.dart';

/// Single owner of in-app notifications (WS / Android keep-alive / tray).
class InAppNotificationsHub extends ChangeNotifier {
  InAppNotificationsHub._();

  static final InAppNotificationsHub instance = InAppNotificationsHub._();

  final SystemNotificationsService _system = createSystemNotificationsService();
  final AndroidNotificationKeepAliveService _keepAlive = createAndroidNotificationKeepAliveService();

  NotificationsWsClient? _ws;
  String? _connectedApiKey;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _bootstrapped = false;
  bool _appIsJalali = true;
  bool _usingKeepAlive = false;

  final List<Map<String, dynamic>> notifications = <Map<String, dynamic>>[];
  int unreadCount = 0;

  final List<void Function(Map<String, dynamic> item)> _foregroundAlertListeners =
      <void Function(Map<String, dynamic> item)>[];

  final List<void Function(Map<String, dynamic> msg)> _rawMessageListeners =
      <void Function(Map<String, dynamic> msg)>[];

  final LinkedHashSet<String> _recentDedupKeys = LinkedHashSet<String>();

  bool get isForeground => _lifecycle == AppLifecycleState.resumed;

  void addForegroundAlertListener(void Function(Map<String, dynamic> item) listener) {
    _foregroundAlertListeners.add(listener);
  }

  void removeForegroundAlertListener(void Function(Map<String, dynamic> item) listener) {
    _foregroundAlertListeners.remove(listener);
  }

  /// رویدادهای خام WebSocket (مثلاً telephony.*) برای ماژول‌های تخصصی.
  void addRawMessageListener(void Function(Map<String, dynamic> msg) listener) {
    _rawMessageListeners.add(listener);
  }

  void removeRawMessageListener(void Function(Map<String, dynamic> msg) listener) {
    _rawMessageListeners.remove(listener);
  }

  void _dispatchRawMessage(Map<String, dynamic> msg) {
    for (final listener in List<void Function(Map<String, dynamic>)>.from(_rawMessageListeners)) {
      try {
        listener(msg);
      } catch (_) {}
    }
  }

  void setAppIsJalali(bool value) {
    _appIsJalali = value;
  }

  void setLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (supportsAndroidNotificationKeepAlive && _usingKeepAlive) {
      unawaited(_keepAlive.updateUiAttached(state == AppLifecycleState.resumed));
    }
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
      unawaited(_system.ensurePermission());
      final launch = await _system.consumeLaunchPayload();
      if (launch != null) {
        NotificationTapNavigation.instance.enqueue(launch);
      }
    }

    if (supportsAndroidNotificationKeepAlive) {
      await _keepAlive.ensureInitialized();
      _keepAlive.setOnNotificationMessage((msg) {
        _dispatchRawMessage(msg);
        if ('${msg['type'] ?? ''}' == 'notification') {
          _ingestNotification(msg);
        }
      });
    }
  }

  Future<void> startForApiKey(String apiKey) async {
    if (apiKey.isEmpty) return;
    await bootstrap();
    if (_connectedApiKey == apiKey && (_ws != null || _usingKeepAlive)) return;

    await stop(clearUi: false);
    _connectedApiKey = apiKey;
    await refreshFromApi();

    final keepAliveWanted =
        supportsAndroidNotificationKeepAlive && await AndroidNotificationPrefs.isKeepAliveEnabled();

    if (keepAliveWanted) {
      try {
        await _keepAlive.start(
          apiKey: apiKey,
          appIsJalali: _appIsJalali,
          uiAttached: isForeground,
        );
        final running = await _keepAlive.isRunning();
        if (running) {
          _usingKeepAlive = true;
          await _keepAlive.updateUiAttached(isForeground);
          // همچنان WebSocket داخل‌پردازه‌ای برای رویدادهای telephony.* لازم است
          // (keep-alive اندروید فقط اعلان‌های عمومی را پوشش می‌دهد).
          _ws = createNotificationsWsClient();
          _ws!.connect(
            apiKey: apiKey,
            onMessage: (msg) {
              try {
                _dispatchRawMessage(msg);
                if ('${msg['type'] ?? ''}' != 'notification') return;
                // اعلان‌ها از keep-alive می‌آیند؛ از دوباره‌کاری جلوگیری می‌کنیم
              } catch (_) {}
            },
          );
          return;
        }
      } catch (_) {}
      // Fall back to in-process WebSocket if FGS failed to start.
    }

    _usingKeepAlive = false;
    _ws = createNotificationsWsClient();
    _ws!.connect(
      apiKey: apiKey,
      onMessage: (msg) {
        try {
          _dispatchRawMessage(msg);
          if ('${msg['type'] ?? ''}' != 'notification') return;
          _ingestNotification(msg);
        } catch (_) {}
      },
    );
  }

  /// Call after user toggles keep-alive in settings.
  Future<void> reloadDeliveryMode() async {
    final key = _connectedApiKey;
    if (key == null || key.isEmpty) return;
    await stop(clearUi: false);
    _connectedApiKey = null;
    await startForApiKey(key);
  }

  Future<void> stop({bool clearUi = true}) async {
    try {
      _ws?.disconnect();
    } catch (_) {}
    _ws = null;
    if (_usingKeepAlive || supportsAndroidNotificationKeepAlive) {
      try {
        await _keepAlive.stop();
      } catch (_) {}
    }
    _usingKeepAlive = false;
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
    final title = '${raw['title'] ?? 'پیام'}';
    final body = '${raw['body'] ?? ''}';
    final level = '${raw['level'] ?? 'info'}';
    final dynamic aid = raw['announcement_id'] ?? raw['id'];
    final int? annId = aid is int ? aid : int.tryParse('$aid');
    final deepLink = raw['deep_link']?.toString();
    final eventKey = raw['event_key']?.toString();
    final ticketId = raw['ticket_id'];

    final item = AnnouncementNavigation.normalizeItem(<String, dynamic>{
      'title': title,
      'body': body,
      'level': level,
      if (annId != null) 'id': annId,
      if (deepLink != null && deepLink.isNotEmpty) 'deep_link': deepLink,
      if (eventKey != null && eventKey.isNotEmpty) 'event_key': eventKey,
      if (ticketId != null) 'ticket_id': ticketId,
      'is_read': false,
    });

    final dedupKey = _dedupKey(item);
    if (_recentDedupKeys.contains(dedupKey)) return;
    _recentDedupKeys.add(dedupKey);
    while (_recentDedupKeys.length > 200) {
      _recentDedupKeys.remove(_recentDedupKeys.first);
    }

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

    // Background: always attempt tray from the UI isolate as a fallback.
    // Keep-alive FGS also shows when uiAttached=false; same notification id replaces
    // rather than duplicating. Skipping here previously caused silence when FGS still
    // thought the UI was attached (stale uiAttached after background/kill).
    if (supportsAndroidSystemNotifications) {
      unawaited(
        _system.showInAppNotification(
          title: title,
          body: body,
          payload: item,
          playSound: playSound,
          appIsJalali: _appIsJalali,
          enrichContent: true,
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
