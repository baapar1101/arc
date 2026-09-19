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

  void setOnSoftphoneMessage(void Function(Map<String, dynamic> msg)? handler) {}

  Future<void> enableSoftphonePresence({
    required String apiKey,
    required int businessId,
    required String sessionId,
    required String mediaTicket,
    required String extension,
    required String apiBaseUrl,
    bool appIsJalali = true,
    bool uiHoldingWs = true,
  }) async {}

  Future<void> setSoftphoneUiHoldingWs(bool holding) async {}

  Future<void> disableSoftphonePresence({bool stopIfOnlySoftphone = false}) async {}
}

AndroidNotificationKeepAliveService createAndroidNotificationKeepAliveService() =>
    AndroidNotificationKeepAliveService();
