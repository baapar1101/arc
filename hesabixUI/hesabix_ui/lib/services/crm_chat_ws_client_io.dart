import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'crm_chat_ws_client_stub.dart';
export 'crm_chat_ws_client_stub.dart';

/// هم‌نام با `DEFAULT_WS_AUTH_TIMEOUT_SEC` سرور؛ کمی حاشیه برای تأخیر شبکه.
const Duration _kCrmWsAuthTimeout = Duration(seconds: 17);

class IoCrmChatWs implements CrmChatWsClient {
  WebSocket? _socket;
  void Function(Map<String, dynamic>)? _onMessage;
  void Function()? _onDisconnected;
  final Set<int> _subscribed = {};
  bool _authed = false;

  @override
  bool get isAuthenticated => _authed;

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
  Future<bool> connect({
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

    final handshake = Completer<bool>();
    Timer? handshakeTimer;

    void completeHandshake(bool ok) {
      handshakeTimer?.cancel();
      handshakeTimer = null;
      if (!handshake.isCompleted) {
        handshake.complete(ok);
      }
    }

    handshakeTimer = Timer(_kCrmWsAuthTimeout, () {
      try {
        _socket?.close();
      } catch (_) {}
      completeHandshake(false);
    });

    WebSocket socket;
    try {
      socket = await WebSocket.connect(url);
      _socket = socket;
      _sendJson(<String, Object?>{
        'type': 'auth',
        'role': 'agent',
        'api_key': apiKey,
        'business_id': businessId,
      });
    } catch (_) {
      completeHandshake(false);
      await handshake.future;
      _socket = null;
      _resetSession();
      return false;
    }

    socket.listen(
      (dynamic data) {
        try {
          if (data is! String) return;
          final msg = jsonDecode(data) as Map<String, dynamic>;
          if (msg['type'] == 'auth_ok') {
            _authed = true;
            _flushSubscribeQueue();
            completeHandshake(true);
          }
          _onMessage?.call(msg);
        } catch (_) {}
      },
      onDone: () {
        final okSession = _authed;
        _socket = null;
        completeHandshake(false);
        _resetSession();
        if (okSession) {
          _onDisconnected?.call();
        }
      },
      onError: (_) {
        final okSession = _authed;
        try {
          _socket?.close();
        } catch (_) {}
        _socket = null;
        completeHandshake(false);
        _resetSession();
        if (okSession) {
          _onDisconnected?.call();
        }
      },
      cancelOnError: false,
    );

    final authOk = await handshake.future;
    if (!authOk) {
      try {
        await socket.close();
      } catch (_) {}
      _socket = null;
      _resetSession();
      return false;
    }
    return true;
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
