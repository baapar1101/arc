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
    // قطع اتصال قبلی در صورت وجود
    disconnect();
    
    try {
      final apiBase = AppConfig.apiBaseUrl; // e.g. http://localhost:8000
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/notifications';

      _ws = web.WebSocket(url);

      // احراز هویت در اولین فریم متنی (TLS)؛ api_key در URL قرار نمی‌گیرد.
      _ws!.onOpen.listen((web.Event _) {
        _ws!.send(jsonEncode(<String, String>{'type': 'auth', 'api_key': apiKey}).toJS);
      });
      
      // Handle connection errors silently
      _ws!.onError.listen((web.Event event) {
        // Connection failed, silently ignore
        // در محیط production، این خطا را log نمی‌کنیم تا console شلوغ نشود
        _ws = null;
      }, onError: (error) {
        // مدیریت خطاهای listener
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
      }, onError: (error) {
        // مدیریت خطاهای دریافت پیام
      });
      
      // Handle close events
      _ws!.onClose.listen((web.CloseEvent event) {
        _ws = null;
      }, onError: (error) {
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


