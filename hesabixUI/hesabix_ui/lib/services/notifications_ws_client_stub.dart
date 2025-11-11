abstract class NotificationsWsClient {
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage});
  void disconnect();
}

NotificationsWsClient createNotificationsWsClient() => _NoopWsClient();

class _NoopWsClient implements NotificationsWsClient {
  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage}) {}
  @override
  void disconnect() {}
}


