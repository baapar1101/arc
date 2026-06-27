abstract class SupportRealtimeService {
  void connect({
    required String apiKey,
    void Function(Map<String, dynamic>)? onEvent,
  });
  void subscribeTicket(int ticketId);
  void unsubscribeTicket(int ticketId);
  void disconnect();
}

SupportRealtimeService createSupportRealtimeService() => _NoopSupportRealtime();

class _NoopSupportRealtime implements SupportRealtimeService {
  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onEvent}) {}

  @override
  void disconnect() {}

  @override
  void subscribeTicket(int ticketId) {}

  @override
  void unsubscribeTicket(int ticketId) {}
}
