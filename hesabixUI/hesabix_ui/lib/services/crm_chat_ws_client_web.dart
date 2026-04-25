import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../config/app_config.dart';
import 'crm_chat_ws_client_stub.dart';
export 'crm_chat_ws_client_stub.dart';

class WebCrmChatWs implements CrmChatWsClient {
  web.WebSocket? _ws;
  void Function(Map<String, dynamic>)? _onMessage;
  void Function()? _onDisconnected;
  final Set<int> _subscribed = {};
  bool _authed = false;

  void _resetSession() {
    _authed = false;
    _subscribed.clear();
  }

  void _sendJson(Map<String, Object?> payload) {
    final s = _ws;
    if (s == null) return;
    try {
      s.send(jsonEncode(payload).toJS);
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
      _ws = web.WebSocket(url);
      _ws!.onOpen.listen((web.Event _) {
        _sendJson(<String, Object?>{
          'type': 'auth',
          'role': 'agent',
          'api_key': apiKey,
          'business_id': businessId,
        });
      });
      _ws!.onMessage.listen((web.MessageEvent e) {
        try {
          final data = e.data;
          if (data is JSString) { // ignore: invalid_runtime_check_with_js_interop_types
            final msg = jsonDecode(data.toDart) as Map<String, dynamic>;
            if (msg['type'] == 'auth_ok') {
              _authed = true;
              _flushSubscribeQueue();
            }
            _onMessage?.call(msg);
          }
        } catch (_) {}
      });
      _ws!.onError.listen((web.Event _) {
        _ws = null;
        _resetSession();
        _onDisconnected?.call();
      });
      _ws!.onClose.listen((web.CloseEvent _) {
        _ws = null;
        _resetSession();
        _onDisconnected?.call();
      });
    } catch (_) {
      _ws = null;
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
  void disconnect() {
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _resetSession();
    _onMessage = null;
    _onDisconnected = null;
  }
}

CrmChatWsClient createCrmChatWsClient() => WebCrmChatWs();
