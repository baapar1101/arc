import 'dart:convert';
import 'dart:io';

import '../../config/app_config.dart';
import 'voice_ws_client_stub.dart';
export 'voice_ws_client_stub.dart';

class VoiceWsClientIO implements VoiceWsClient {
  WebSocket? _socket;
  bool _connecting = false;

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
    _onEvent = onEvent;
    _onAudioFrame = onAudioFrame;
    _onError = onError;
    _onDone = onDone;

    try {
      final apiBase = AppConfig.apiBaseUrl;
      final wsBase = apiBase.startsWith('https://')
          ? apiBase.replaceFirst('https://', 'wss://')
          : apiBase.replaceFirst('http://', 'ws://');
      final url = '$wsBase/ws/ai/voice?api_key=$apiKey';

      _socket = await WebSocket.connect(url);
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
          disconnect();
        },
        onDone: () {
          _onDone?.call();
          disconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _onError?.call(e);
      disconnect();
    } finally {
      _connecting = false;
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
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _connecting = false;
  }
}

VoiceWsClient createVoiceWsClient() => VoiceWsClientIO();


