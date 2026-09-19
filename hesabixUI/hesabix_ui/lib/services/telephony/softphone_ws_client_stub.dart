abstract class SoftphoneWsClient {
  void connect({
    required String apiKey,
    required int businessId,
    required String sessionId,
    required String mediaTicket,
    void Function(Map<String, dynamic> msg)? onJson,
    void Function(List<int> pcm, String sessionId)? onPcm,
    void Function(Object error)? onError,
    void Function()? onDone,
  });

  void sendJson(Map<String, dynamic> msg);

  void sendPcm(String sessionId, List<int> pcm);

  void disconnect();

  bool get isConnected;
}

SoftphoneWsClient createSoftphoneWsClient() => throw UnsupportedError('Softphone WS unsupported');
