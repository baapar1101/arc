import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../config/app_config.dart';
import 'support_realtime_service_stub.dart';
export 'support_realtime_service_stub.dart';

class WebSupportRealtimeService implements SupportRealtimeService {
  web.WebSocket? _ws;
  void Function(Map<String, dynamic>)? _onEvent;
  String? _apiKey;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;

  void _scheduleReconnect() {
    if (_manualDisconnect) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      final key = _apiKey;
      if (key == null || key.isEmpty || _manualDisconnect) return;
      connect(apiKey: key, onEvent: _onEvent);
    });
  }

  @override
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onEvent}) {
    _apiKey = apiKey;
    _onEvent = onEvent;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;

    try {
      final apiBase = AppConfig.apiBaseUrl;
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/support/tickets';
      _ws = web.WebSocket(url);
      _ws!.onOpen.listen((_) {
        _ws!.send(jsonEncode(<String, String>{'type': 'auth', 'api_key': apiKey}).toJS);
      });
      _ws!.onMessage.listen((web.MessageEvent e) {
        try {
          final data = e.data;
          if (data is JSString) {
            final msg = jsonDecode(data.toDart) as Map<String, dynamic>;
            _onEvent?.call(msg);
          }
        } catch (_) {}
      });
      _ws!.onClose.listen((_) {
        _ws = null;
        _scheduleReconnect();
      });
      _ws!.onError.listen((_) {
        _ws = null;
        _scheduleReconnect();
      });
    } catch (_) {
      _ws = null;
      _scheduleReconnect();
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _ws?.send(jsonEncode(msg).toJS);
    } catch (_) {}
  }

  @override
  void subscribeTicket(int ticketId) {
    _send({'type': 'subscribe', 'ticket_id': ticketId});
  }

  @override
  void unsubscribeTicket(int ticketId) {
    _send({'type': 'unsubscribe', 'ticket_id': ticketId});
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

SupportRealtimeService createSupportRealtimeService() => WebSupportRealtimeService();
