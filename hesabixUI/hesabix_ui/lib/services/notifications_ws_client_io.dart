import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../config/app_config.dart';
import 'notifications_ws_client_stub.dart';
export 'notifications_ws_client_stub.dart';

class IoNotificationsWsClient implements NotificationsWsClient {
  WebSocket? _socket;
  void Function(Map<String, dynamic>)? _onMessage;
  String? _apiKey;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      final key = _apiKey;
      if (key == null || key.isEmpty || _manualDisconnect) return;
      connect(apiKey: key, onMessage: _onMessage);
    });
  }

  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage}) async {
    _apiKey = apiKey;
    _onMessage = onMessage;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    final apiBase = AppConfig.apiBaseUrl; // e.g. http://localhost:8000
    final wsBase = apiBase.startsWith('https://')
        ? apiBase.replaceFirst('https://', 'wss://')
        : apiBase.replaceFirst('http://', 'ws://');
    final url = '$wsBase/ws/notifications';
    try {
      _socket = await WebSocket.connect(url);
      _socket!.add(jsonEncode(<String, String>{'type': 'auth', 'api_key': apiKey}));
      _socket!.listen((dynamic data) {
        try {
          final Map<String, dynamic> msg = data is String ? jsonDecode(data) as Map<String, dynamic> : <String, dynamic>{};
          if (_onMessage != null) _onMessage!(msg);
        } catch (_) {}
      }, onDone: () {
        _socket = null;
        _scheduleReconnect();
      }, onError: (Object _) {
        _socket = null;
        _scheduleReconnect();
      });
    } catch (_) {
      _socket = null;
      _scheduleReconnect();
    }
  }

  @override
  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

NotificationsWsClient createNotificationsWsClient() => IoNotificationsWsClient();


