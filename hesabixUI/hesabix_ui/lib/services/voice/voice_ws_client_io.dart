import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/app_config.dart';
import 'voice_ws_client_stub.dart';
export 'voice_ws_client_stub.dart';

class VoiceWsClientIO implements VoiceWsClient {
  WebSocket? _socket;
  bool _connecting = false;
  bool _shouldReconnect = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  Timer? _reconnectTimer;
  String? _storedApiKey;

  void Function(Map<String, dynamic>)? _onEvent;
  void Function(List<int>)? _onAudioFrame;
  void Function(Object error)? _onError;
  void Function()? _onDone;

  @override
  bool get isConnected => _socket != null && _socket!.readyState == WebSocket.open;

  @override
  Future<void> connect({
    required String apiKey,
    required void Function(Map<String, dynamic> event) onEvent,
    required void Function(List<int> pcmFrame) onAudioFrame,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    if (_connecting || isConnected) return;
    _connecting = true;
    _storedApiKey = apiKey;
    _onEvent = onEvent;
    _onAudioFrame = onAudioFrame;
    _onError = onError;
    _onDone = onDone;
    _reconnectAttempts = 0;

    try {
      final apiBase = AppConfig.apiBaseUrl;
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/ai/voice';

      _socket = await WebSocket.connect(url);
      _socket!.add(jsonEncode(<String, String>{'type': 'auth', 'api_key': apiKey}));
      _reconnectAttempts = 0; // Reset on successful connection
      _socket!.listen(
        (dynamic data) {
          try {
            if (data is String) {
              final decoded = jsonDecode(data);
              if (decoded is Map<String, dynamic>) {
                _onEvent?.call(decoded);
              }
              return;
            }
            if (data is List<int>) {
              _onAudioFrame?.call(data);
            }
          } catch (e) {
            // ignore malformed frames
          }
        },
        onError: (Object e) {
          _onError?.call(e);
          _handleDisconnection();
        },
        onDone: () {
          _onDone?.call();
          _handleDisconnection();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _onError?.call(e);
      _handleDisconnection();
    } finally {
      _connecting = false;
    }
  }

  void _handleDisconnection() {
    final wasConnected = _socket != null;
    _socket = null;
    _connecting = false;
    
    if (_shouldReconnect && wasConnected && _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      _reconnectTimer = Timer(_reconnectDelay * _reconnectAttempts, () {
        if (_shouldReconnect && !isConnected && !_connecting && _storedApiKey != null) {
          // Retry connection with stored callbacks
          if (_onEvent != null && _onAudioFrame != null) {
            connect(
              apiKey: _storedApiKey!,
              onEvent: _onEvent!,
              onAudioFrame: _onAudioFrame!,
              onError: _onError,
              onDone: _onDone,
            );
          }
        }
      });
    }
  }

  @override
  void sendJson(Map<String, dynamic> payload) {
    if (!isConnected) return;
    try {
      _socket!.add(jsonEncode(payload));
    } catch (_) {}
  }

  @override
  void sendBytes(List<int> bytes) {
    if (!isConnected) return;
    try {
      _socket!.add(bytes);
    } catch (_) {}
  }

  @override
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _storedApiKey = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _connecting = false;
  }

  @override
  void enableReconnect() {
    _shouldReconnect = true;
    _reconnectAttempts = 0;
  }

  void disableReconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
}

VoiceWsClient createVoiceWsClient() => VoiceWsClientIO();


