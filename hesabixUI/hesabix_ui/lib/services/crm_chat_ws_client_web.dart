import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

// ignore_for_file: deprecated_member_use_from_same_package — dartify برای هر دو dart2js / wasm
import 'dart:js_util' as js_util show dartify;

import '../config/app_config.dart';
import 'crm_chat_ws_client_stub.dart';
export 'crm_chat_ws_client_stub.dart';

const Duration _kCrmWsAuthTimeout = Duration(seconds: 17);

String? _messageEventDataAsUtf16Text(web.MessageEvent e) {
  final raw = e.data;
  if (raw == null) return null;
  try {
    final boxed = js_util.dartify(raw as Object);
    if (boxed is String && boxed.isNotEmpty) {
      return boxed;
    }
  } catch (_) {
    /* مسیر بعدی */
  }
  try {
    if (raw.isA<JSString>()) {
      return (raw as JSString).toDart;
    }
  } catch (_) {}
  return null;
}

class WebCrmChatWs implements CrmChatWsClient {
  web.WebSocket? _ws;
  void Function(Map<String, dynamic>)? _onMessage;
  void Function()? _onDisconnected;
  final Set<int> _subscribed = {};
  bool _authed = false;

  StreamSubscription<web.CloseEvent>? _closeListen;

  @override
  bool get isAuthenticated => _authed;

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
        _ws?.close();
      } catch (_) {}
      completeHandshake(false);
    });

    web.WebSocket sock;
    try {
      sock = web.WebSocket(url);
      _ws = sock;
    } catch (_) {
      completeHandshake(false);
      await handshake.future;
      _ws = null;
      _resetSession();
      return false;
    }

    sock.onOpen.listen((web.Event _) {
      try {
        _sendJson(<String, Object?>{
          'type': 'auth',
          'role': 'agent',
          'api_key': apiKey,
          'business_id': businessId,
        });
      } catch (_) {
        try {
          sock.close();
        } catch (_) {}
      }
    });

    sock.onMessage.listen((web.MessageEvent e) {
      try {
        final text = _messageEventDataAsUtf16Text(e);
        if (text == null || text.isEmpty) return;
        final msg = jsonDecode(text);
        if (msg is! Map<String, dynamic>) return;
        if (msg['type'] == 'auth_ok') {
          _authed = true;
          _flushSubscribeQueue();
          completeHandshake(true);
        }
        _onMessage?.call(msg);
      } catch (_) {}
    });

    sock.onError.listen((web.Event _) {
      final okSession = _authed;
      try {
        sock.close();
      } catch (_) {}
      _ws = null;
      completeHandshake(false);
      _resetSession();
      if (okSession) {
        _onDisconnected?.call();
      }
    });

    _closeListen = sock.onClose.listen((web.CloseEvent _) {
      final okSession = _authed;
      _closeListen?.cancel();
      _closeListen = null;
      _ws = null;
      completeHandshake(false);
      _resetSession();
      if (okSession) {
        _onDisconnected?.call();
      }
    });

    final authedOk = await handshake.future;
    handshakeTimer?.cancel();
    handshakeTimer = null;

    if (!authedOk) {
      try {
        sock.close();
      } catch (_) {}
      _ws = null;
      await _closeListen?.cancel();
      _closeListen = null;
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
      _closeListen?.cancel();
      _closeListen = null;
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _resetSession();
    _onMessage = null;
    _onDisconnected = null;
  }
}

CrmChatWsClient createCrmChatWsClient() => WebCrmChatWs();
