import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../config/app_config.dart';
import 'notifications_ws_client_stub.dart';
export 'notifications_ws_client_stub.dart';

class WebNotificationsWsClient implements NotificationsWsClient {
  web.WebSocket? _ws;
  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage}) {
    try {
      final apiBase = AppConfig.apiBaseUrl; // e.g. http://localhost:8000
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/notifications?api_key=$apiKey';
      _ws = web.WebSocket(url);
      
      // Handle connection errors silently
      _ws!.onError.listen((web.Event _) {
        // Connection failed, silently ignore
        _ws = null;
      });
      
      _ws!.onMessage.listen((web.MessageEvent e) {
        try {
          final data = e.data;
          if (data is JSString) {
            final jsonStr = data.toDart;
            final Map<String, dynamic> msg = jsonDecode(jsonStr) as Map<String, dynamic>;
            onMessage?.call(msg);
          }
        } catch (_) {
          // Ignore message parsing errors
        }
      });
      
      // Handle close events
      _ws!.onClose.listen((web.CloseEvent _) {
        _ws = null;
      });
    } catch (_) {
      // Silently ignore connection errors - WebSocket is optional
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


