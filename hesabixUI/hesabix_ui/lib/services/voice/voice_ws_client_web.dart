import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../config/app_config.dart';
import 'voice_ws_client_stub.dart';
export 'voice_ws_client_stub.dart';

class VoiceWsClientWeb implements VoiceWsClient {
  web.WebSocket? _ws;
  bool _connected = false;
  bool _shouldReconnect = false;
  bool _preferBinaryDownlink = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  Timer? _reconnectTimer;
  String? _storedApiKey;
  Map<String, dynamic>? _sessionStartPayload;
  Completer<void>? _openCompleter;

  void Function(Map<String, dynamic>)? _onEvent;
  void Function(List<int>)? _onAudioFrame;
  void Function(Object error)? _onError;
  void Function()? _onDone;
  void Function()? _onReconnected;

  @override
  bool get isConnected => _connected && _ws != null;

  @override
  Future<void> connect({
    required String apiKey,
    required void Function(Map<String, dynamic> event) onEvent,
    required void Function(List<int> pcmFrame) onAudioFrame,
    void Function(Object error)? onError,
    void Function()? onDone,
    void Function()? onReconnected,
    bool preferBinaryDownlink = true,
  }) async {
    final savedStart = _sessionStartPayload;
    _tearDownSocket();
    _sessionStartPayload = savedStart;
    _storedApiKey = apiKey;
    _onEvent = onEvent;
    _onAudioFrame = onAudioFrame;
    _onError = onError;
    _onDone = onDone;
    _onReconnected = onReconnected;
    _preferBinaryDownlink = preferBinaryDownlink;
    _reconnectAttempts = 0;
    final restoring = _sessionStartPayload != null;

    try {
      final apiBase = AppConfig.apiBaseUrl;
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/ai/voice';

      final openCompleter = Completer<void>();
      _openCompleter = openCompleter;
      _ws = web.WebSocket(url);
      _ws!.binaryType = 'arraybuffer';

      _ws!.onOpen.listen((_) {
        _ws!.send(jsonEncode(<String, String>{'type': 'auth', 'api_key': apiKey}).toJS);
        _connected = true;
        _reconnectAttempts = 0;
        if (restoring && _sessionStartPayload != null) {
          sendJson(_sessionStartPayload!);
          _onReconnected?.call();
        }
        if (_openCompleter == openCompleter && !openCompleter.isCompleted) {
          openCompleter.complete();
        }
      });
      _ws!.onClose.listen((_) {
        final wasConnected = _connected;
        _connected = false;
        _onDone?.call();
        if (_openCompleter == openCompleter && !openCompleter.isCompleted) {
          openCompleter.completeError(StateError('WebSocket closed before open'));
        }
        _handleDisconnection(wasConnected);
      });
      _ws!.onError.listen((_) {
        final wasConnected = _connected;
        _connected = false;
        _onError?.call('WebSocket error');
        if (_openCompleter == openCompleter && !openCompleter.isCompleted) {
          openCompleter.completeError(StateError('WebSocket error'));
        }
        _handleDisconnection(wasConnected);
      });
      _ws!.onMessage.listen((web.MessageEvent e) {
        final data = e.data;
        try {
          if (data.isA<JSString>()) {
            final msg = jsonDecode((data as JSString).toDart);
            if (msg is Map<String, dynamic>) {
              if (msg['type'] == 'assistant_audio' && msg['audio_b64'] is String) {
                final bytes = base64Decode(msg['audio_b64'] as String);
                _onAudioFrame?.call(bytes);
              } else {
                _onEvent?.call(msg);
              }
            }
            return;
          }
          if (_preferBinaryDownlink && data.isA<JSArrayBuffer>()) {
            final buffer = (data as JSArrayBuffer).toDart;
            _onAudioFrame?.call(buffer.asUint8List());
          }
        } catch (_) {}
      });

      try {
        await openCompleter.future.timeout(const Duration(seconds: 5));
      } catch (e) {
        _onError?.call('خطا در اتصال صوت: $e');
        disconnect();
        rethrow;
      }
    } catch (e) {
      _onError?.call(e);
      disconnect();
    }
  }

  @override
  void sendBytes(List<int> bytes) {
    if (!isConnected) return;
    try {
      final u8 = Uint8List.fromList(bytes);
      _ws!.send(u8.toJS);
    } catch (_) {}
  }

  @override
  void sendWebmChunk(List<int> bytes) {
    if (!isConnected || bytes.isEmpty) return;
    try {
      sendJson({
        'type': 'audio_webm',
        'data_b64': base64Encode(bytes),
      });
    } catch (_) {}
  }

  @override
  void sendJson(Map<String, dynamic> payload) {
    if (!isConnected) return;
    try {
      _ws!.send(jsonEncode(payload).toJS);
    } catch (_) {}
  }

  void _handleDisconnection(bool wasConnected) {
    _ws = null;
    _connected = false;

    if (_shouldReconnect && wasConnected && _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      _reconnectTimer = Timer(_reconnectDelay * _reconnectAttempts, () {
        if (_shouldReconnect && !isConnected && _storedApiKey != null) {
          if (_onEvent != null && _onAudioFrame != null) {
            connect(
              apiKey: _storedApiKey!,
              onEvent: _onEvent!,
              onAudioFrame: _onAudioFrame!,
              onError: _onError,
              onDone: _onDone,
              onReconnected: _onReconnected,
              preferBinaryDownlink: _preferBinaryDownlink,
            );
          }
        }
      });
    }
  }

  @override
  void setSessionStartPayload(Map<String, dynamic> payload) {
    _sessionStartPayload = Map<String, dynamic>.from(payload);
  }

  void _tearDownSocket() {
    _openCompleter = null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _connected = false;
  }

  @override
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _storedApiKey = null;
    _sessionStartPayload = null;
    _tearDownSocket();
  }

  @override
  void enableReconnect() {
    _shouldReconnect = true;
    _reconnectAttempts = 0;
  }

  @override
  void disableReconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
}

VoiceWsClient createVoiceWsClient() => VoiceWsClientWeb();
