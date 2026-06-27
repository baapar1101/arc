import 'dart:convert';
import 'dart:io';
import 'dart:async';

import '../config/app_config.dart';
import 'support_realtime_service_stub.dart';
export 'support_realtime_service_stub.dart';

class IoSupportRealtimeService implements SupportRealtimeService {
  WebSocket? _socket;
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
  void connect({required String apiKey, void Function(Map<String, dynamic>)? onEvent}) async {
    _apiKey = apiKey;
    _onEvent = onEvent;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    final apiBase = AppConfig.apiBaseUrl;
    final wsBase = apiBase.startsWith('https://')
        ? apiBase.replaceFirst('https://', 'wss://')
        : apiBase.replaceFirst('http://', 'ws://');
    final url = '$wsBase/ws/support/tickets';
    try {
      _socket = await WebSocket.connect(url);
      _socket!.add(jsonEncode(<String, String>{'type': 'auth', 'api_key': apiKey}));
      _socket!.listen((dynamic data) {
        try {
          final msg = data is String ? jsonDecode(data) as Map<String, dynamic> : <String, dynamic>{};
          _onEvent?.call(msg);
        } catch (_) {}
      }, onDone: () {
        _socket = null;
        _scheduleReconnect();
      }, onError: (_) {
        _socket = null;
        _scheduleReconnect();
      });
    } catch (_) {
      _socket = null;
      _scheduleReconnect();
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _socket?.add(jsonEncode(msg));
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
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

SupportRealtimeService createSupportRealtimeService() => IoSupportRealtimeService();
