import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../utils/notification_sound_catalog.dart';
import 'notifications_service.dart';

/// حالت هشدار درون‌برنامه‌ای (هم‌ارز رشته‌های API).
enum InAppAlertMode {
  normal,
  silent,
  doNotDisturb,
}

InAppAlertMode inAppAlertModeFromApi(String? raw) {
  switch ('${raw ?? 'normal'}'.trim()) {
    case 'silent':
      return InAppAlertMode.silent;
    case 'do_not_disturb':
      return InAppAlertMode.doNotDisturb;
    default:
      return InAppAlertMode.normal;
  }
}

String inAppAlertModeToApi(InAppAlertMode mode) {
  switch (mode) {
    case InAppAlertMode.silent:
      return 'silent';
    case InAppAlertMode.doNotDisturb:
      return 'do_not_disturb';
    case InAppAlertMode.normal:
      return 'normal';
  }
}

/// کش ترجیحات هشدار in-app برای زنگوله و صفحات تنظیمات.
class InAppNotificationPreferencesController extends ChangeNotifier {
  InAppNotificationPreferencesController._();

  static final InAppNotificationPreferencesController instance = InAppNotificationPreferencesController._();

  final NotificationsService _svc = NotificationsService(ApiClient());

  InAppAlertMode mode = InAppAlertMode.normal;
  bool soundEnabled = true;
  String soundAssetId = NotificationSoundCatalog.defaultId;

  void applyFromSettingsMap(Map<String, dynamic> s) {
    mode = inAppAlertModeFromApi(s['inapp_alert_mode']?.toString());
    soundEnabled = (s['inapp_sound_enabled'] ?? true) == true;
    soundAssetId = '${s['inapp_sound_asset_id'] ?? NotificationSoundCatalog.defaultId}';
    notifyListeners();
  }

  Future<void> refreshFromApi() async {
    final s = await _svc.getSettings();
    applyFromSettingsMap(s);
  }
}
