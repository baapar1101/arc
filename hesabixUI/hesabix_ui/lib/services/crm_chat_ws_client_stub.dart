/// کلاینت WebSocket عامل چت CRM — پیاده‌سازی پیش‌فرض (بدون اتصال).
abstract class CrmChatWsClient {
  /// بازگشت [true] فقط پس از دریافت پیام معتبر [auth_ok] از سرور.
  Future<bool> connect({
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
  Future<bool> connect({
    required String apiKey,
    required int businessId,
    required void Function(Map<String, dynamic> message) onMessage,
    void Function()? onDisconnected,
  }) async =>
      false;

  @override
  void subscribeConversation(int conversationId) {}

  @override
  void sendTyping(int conversationId, {required bool active}) {}

  @override
  void disconnect() {}
}
