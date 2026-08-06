import 'sms_bank_models.dart';

/// No-op SMS bank assistant for web / non-IO platforms.
class SmsBankAssistantService {
  SmsBankAssistantService();

  Future<void> initialize({
    void Function(SmsBankEvent event)? onEvent,
  }) async {}

  void setOnEvent(void Function(SmsBankEvent event)? onEvent) {}

  Future<SmsBankSettings> getSettings() async => const SmsBankSettings();

  Future<void> saveSettings(SmsBankSettings settings) async {}

  Future<List<SmsBankPattern>> getPatterns({int? businessId}) async => const [];

  Future<void> savePatterns(List<SmsBankPattern> patterns) async {}

  Future<void> savePatternsForBusiness(int businessId, List<SmsBankPattern> patterns) async {}

  Future<void> ensureSeedPatternsForBusiness({
    required int businessId,
    String? businessName,
  }) async {}

  Future<List<SmsBankPattern>> getMatchablePatterns(SmsBankSettings settings) async =>
      const [];

  Future<void> updateEvent(SmsBankEvent event) async {}

  Future<bool> ensureSmsPermission({bool requestIfNeeded = true}) async => false;

  Future<bool> hasSmsPermission() async => false;

  Future<void> syncNativeConfig() async {}

  Future<List<SmsBankEvent>> drainPendingEvents({bool onlyPending = true}) async =>
      const [];

  Future<List<SmsBankEvent>> listEvents() async => const [];

  Future<void> updateEventStatus(String eventId, SmsBankEventStatus status) async {}

  Future<SmsBankEvent?> getEvent(String id) async => null;

  Future<SmsBankMatchResult> testMatch({
    required String body,
    required String sender,
    List<SmsBankPattern>? patterns,
    int? preferredBusinessId,
  }) async =>
      SmsBankMatchResult.none;

  Future<SmsBankEvent?> processIncomingSms({
    required String sender,
    required String body,
    DateTime? receivedAt,
    bool notify = false,
    int? preferredBusinessId,
  }) async =>
      null;

  Future<SmsBankEvent?> takePendingEvent(String id) async => null;

  Future<String?> peekLaunchEventId() async => null;

  Future<void> clearLaunchEventId() async {}

  Future<String?> consumeLaunchEventId() async => null;
}

SmsBankAssistantService createSmsBankAssistantService() => SmsBankAssistantService();
