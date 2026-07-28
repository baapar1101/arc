/// No-op system notifications (web / unsupported platforms).
class SystemNotificationsService {
  Future<void> initialize({
    void Function(Map<String, dynamic> item)? onNotificationTap,
  }) async {}

  Future<bool> ensurePermission() async => false;

  Future<void> showInAppNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    bool playSound = true,
    bool appIsJalali = true,
    bool enrichContent = true,
  }) async {}

  Future<Map<String, dynamic>?> consumeLaunchPayload() async => null;

  Future<void> cancelAll() async {}
}

SystemNotificationsService createSystemNotificationsService() => SystemNotificationsService();
