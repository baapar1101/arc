/// No-op keep-alive controller (web / non-Android).
class AndroidNotificationKeepAliveService {
  Future<void> ensureInitialized() async {}

  Future<bool> isRunning() async => false;

  Future<void> start({
    required String apiKey,
    required bool appIsJalali,
    bool uiAttached = false,
  }) async {}

  Future<void> stop() async {}

  Future<void> updateUiAttached(bool attached) async {}

  Future<void> updateApiKey(String apiKey) async {}

  Future<void> refreshStatusNotification({bool appIsJalali = true}) async {}

  void setOnNotificationMessage(void Function(Map<String, dynamic> msg)? handler) {}
}

AndroidNotificationKeepAliveService createAndroidNotificationKeepAliveService() =>
    AndroidNotificationKeepAliveService();
