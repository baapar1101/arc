import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show WebSocket, MessageEvent;
import '../config/app_config.dart';
import 'notifications_ws_client_stub.dart';
export 'notifications_ws_client_stub.dart';

class WebNotificationsWsClient implements NotificationsWsClient {
  html.WebSocket? _ws;
  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage}) {
    try {
      final apiBase = AppConfig.apiBaseUrl; // e.g. http://localhost:8000
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/notifications?api_key=$apiKey';
      _ws = html.WebSocket(url);
      _ws!.onMessage.listen((html.MessageEvent e) {
        try {
          final data = e.data;
          if (data is String) {
            final Map<String, dynamic> msg = jsonDecode(data) as Map<String, dynamic>;
            onMessage?.call(msg);
          }
        } catch (_) {}
      });
    } catch (_) {
      _ws = null;
    }
  }

  @override
  void disconnect() {
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}

NotificationsWsClient createNotificationsWsClient() => WebNotificationsWsClient();


