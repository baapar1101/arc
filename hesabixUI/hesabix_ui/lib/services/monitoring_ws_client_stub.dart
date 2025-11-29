import 'dart:async';

abstract class MonitoringWebSocketClient {
  Stream<Map<String, dynamic>>? get stream;
  bool get isConnected;
  
  Future<void> connect();
  Future<void> disconnect();
}

class MonitoringWebSocketClientStub implements MonitoringWebSocketClient {
  @override
  Stream<Map<String, dynamic>>? get stream => null;

  @override
  bool get isConnected => false;

  @override
  Future<void> connect() async {
    throw UnimplementedError('WebSocket not available on this platform');
  }

  @override
  Future<void> disconnect() async {}
}

MonitoringWebSocketClient createMonitoringWebSocketClient() => MonitoringWebSocketClientStub();

