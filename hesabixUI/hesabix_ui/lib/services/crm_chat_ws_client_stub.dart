/// کلاینت WebSocket عامل چت CRM — پیاده‌سازی پیش‌فرض (بدون اتصال).
abstract class CrmChatWsClient {
  Future<void> connect({
    required String apiKey,
    required int businessId,
    required void Function(Map<String, dynamic> message) onMessage,
    void Function()? onDisconnected,
  });

  void subscribeConversation(int conversationId);
  void sendTyping(int conversationId, {required bool active});
  void disconnect();
}

CrmChatWsClient createCrmChatWsClient() => _NoopCrmChatWs();

class _NoopCrmChatWs implements CrmChatWsClient {
  @override
  Future<void> connect({
    required String apiKey,
    required int businessId,
    required void Function(Map<String, dynamic> message) onMessage,
    void Function()? onDisconnected,
  }) async {}

  @override
  void subscribeConversation(int conversationId) {}

  @override
  void sendTyping(int conversationId, {required bool active}) {}

  @override
  void disconnect() {}
}
