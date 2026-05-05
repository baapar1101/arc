import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import '../config/app_config.dart';
import 'notifications_ws_client_stub.dart';
export 'notifications_ws_client_stub.dart';

class WebNotificationsWsClient implements NotificationsWsClient {
  web.WebSocket? _ws;
  String? _apiKey;
  void Function(Map<String, dynamic>)? _onMessage;
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
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onMessage}) {
    _apiKey = apiKey;
    _onMessage = onMessage;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    // قطع اتصال قبلی بدون غیرفعال‌سازی reconnect
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    
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
        _scheduleReconnect();
      }, onError: (error) {
        // مدیریت خطاهای listener
        _ws = null;
        _scheduleReconnect();
      });
      
      _ws!.onMessage.listen((web.MessageEvent e) {
        try {
          final data = e.data;
          if (data is JSString) {
            final jsonStr = data.toDart;
            final Map<String, dynamic> msg = jsonDecode(jsonStr) as Map<String, dynamic>;
            _onMessage?.call(msg);
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
        _scheduleReconnect();
      }, onError: (error) {
        _ws = null;
        _scheduleReconnect();
      });
    } catch (_) {
      // Silently ignore connection errors - WebSocket is optional
      _ws = null;
      _scheduleReconnect();
    }
  }

  @override
  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }
}

NotificationsWsClient createNotificationsWsClient() => WebNotificationsWsClient();


