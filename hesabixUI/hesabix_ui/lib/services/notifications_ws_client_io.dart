import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';
import 'notifications_ws_client_stub.dart';
export 'notifications_ws_client_stub.dart';

class IoNotificationsWsClient implements NotificationsWsClient {
  WebSocket? _socket;
  void Function(Map<String, dynamic>)? _onMessage;

  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage}) async {
    _onMessage = onMessage;
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
      }, onError: (Object _) {
        _socket = null;
      });
    } catch (_) {
      _socket = null;
    }
  }

  @override
  void disconnect() {
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

NotificationsWsClient createNotificationsWsClient() => IoNotificationsWsClient();


