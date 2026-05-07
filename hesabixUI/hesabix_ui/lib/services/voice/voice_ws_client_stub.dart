abstract class VoiceWsClient {
  Future<void> connect({
    required String apiKey,
    required void Function(Map<String, dynamic> event) onEvent,
    required void Function(List<int> pcmFrame) onAudioFrame,
    void Function(Object error)? onError,
    void Function()? onDone,
  });

  void sendJson(Map<String, dynamic> payload);

  void sendBytes(List<int> bytes);

  void disconnect();

  bool get isConnected;

  /// پیاده‌سازی‌های وب/موبایل پس از وصل‌شدن WS؛ روی سکوهای دیگر تهی است.
  void enableReconnect();
}

VoiceWsClient createVoiceWsClient() => _NoopVoiceWsClient();

class _NoopVoiceWsClient implements VoiceWsClient {
  @override
  Future<void> connect({
    required String apiKey,
    required void Function(Map<String, dynamic> event) onEvent,
    required void Function(List<int> pcmFrame) onAudioFrame,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    onError?.call('Voice WebSocket is not supported on this platform.');
  }

  @override
  void disconnect() {}

  @override
  bool get isConnected => false;

  @override
  void sendBytes(List<int> bytes) {}

  @override
  void sendJson(Map<String, dynamic> payload) {}

  @override
  void enableReconnect() {}
}


