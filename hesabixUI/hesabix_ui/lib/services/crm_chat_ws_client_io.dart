import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'crm_chat_ws_client_stub.dart';
export 'crm_chat_ws_client_stub.dart';

class IoCrmChatWs implements CrmChatWsClient {
  WebSocket? _socket;
  void Function(Map<String, dynamic>)? _onMessage;
  void Function()? _onDisconnected;
  final Set<int> _subscribed = {};
  bool _authed = false;

  void _resetSession() {
    _authed = false;
    _subscribed.clear();
  }

  void _sendJson(Map<String, Object?> payload) {
    final s = _socket;
    if (s == null) return;
    try {
      s.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _flushSubscribeQueue() {
    if (!_authed) return;
    for (final id in _subscribed) {
      _sendJson(<String, Object?>{'type': 'subscribe', 'conversation_id': id});
    }
  }

  @override
  Future<void> connect({
    required String apiKey,
    required int businessId,
    required void Function(Map<String, dynamic> message) onMessage,
    void Function()? onDisconnected,
  }) async {
    disconnect();
    _onMessage = onMessage;
    _onDisconnected = onDisconnected;
    _resetSession();

    final apiBase = AppConfig.apiBaseUrl;
    final wsBase = apiBase.startsWith('https://')
        ? apiBase.replaceFirst('https://', 'wss://')
        : apiBase.replaceFirst('http://', 'ws://');
    final url = '$wsBase/ws/crm-chat';

    try {
      _socket = await WebSocket.connect(url);
      _sendJson(<String, Object?>{
        'type': 'auth',
        'role': 'agent',
        'api_key': apiKey,
        'business_id': businessId,
      });
      _socket!.listen(
        (dynamic data) {
          try {
            if (data is! String) return;
            final msg = jsonDecode(data) as Map<String, dynamic>;
            if (msg['type'] == 'auth_ok') {
              _authed = true;
              _flushSubscribeQueue();
            }
            _onMessage?.call(msg);
          } catch (_) {}
        },
        onDone: () {
          _socket = null;
          _resetSession();
          _onDisconnected?.call();
        },
        onError: (_) {
          try {
            _socket?.close();
          } catch (_) {}
          _socket = null;
          _resetSession();
          _onDisconnected?.call();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _socket = null;
      _resetSession();
      _onDisconnected?.call();
    }
  }

  @override
  void subscribeConversation(int conversationId) {
    _subscribed.add(conversationId);
    if (_authed) {
      _sendJson(<String, Object?>{'type': 'subscribe', 'conversation_id': conversationId});
    }
  }

  @override
  void sendTyping(int conversationId, {required bool active}) {
    if (!_authed) return;
    _sendJson(<String, Object?>{
      'type': 'typing',
      'conversation_id': conversationId,
      'active': active,
    });
  }

  @override
  void disconnect() {
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _resetSession();
    _onMessage = null;
    _onDisconnected = null;
  }
}

CrmChatWsClient createCrmChatWsClient() => IoCrmChatWs();
