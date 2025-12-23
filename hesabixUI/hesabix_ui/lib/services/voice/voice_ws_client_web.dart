import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../config/app_config.dart';
import 'voice_ws_client_stub.dart';
export 'voice_ws_client_stub.dart';

class VoiceWsClientWeb implements VoiceWsClient {
  web.WebSocket? _ws;
  bool _connected = false;

  void Function(Map<String, dynamic>)? _onEvent;
  void Function(List<int>)? _onAudioFrame;
  void Function(Object error)? _onError;
  void Function()? _onDone;

  @override
  bool get isConnected => _connected && _ws != null;

  @override
  Future<void> connect({
    required String apiKey,
    required void Function(Map<String, dynamic> event) onEvent,
    required void Function(List<int> pcmFrame) onAudioFrame,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    disconnect();
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

      _ws = web.WebSocket(url);
      _ws!.binaryType = 'arraybuffer';

      _ws!.onOpen.listen((_) => _connected = true);
      _ws!.onClose.listen((_) {
        _connected = false;
        _onDone?.call();
        disconnect();
      });
      _ws!.onError.listen((_) {
        _connected = false;
        _onError?.call('WebSocket error');
        disconnect();
      });
      _ws!.onMessage.listen((web.MessageEvent e) {
        final data = e.data;
        try {
          if (data is JSString) {
            final msg = jsonDecode(data.toDart);
            if (msg is Map<String, dynamic>) {
              // اگر صوت به صورت base64 ارسال شود، اینجا decode و به audio callback پاس می‌دهیم
              if (msg['type'] == 'assistant_audio' && msg['audio_b64'] is String) {
                final b64 = msg['audio_b64'] as String;
                final bytes = base64Decode(b64);
                _onAudioFrame?.call(bytes);
              } else {
                _onEvent?.call(msg);
              }
            }
            return;
          }
          // Web binary: ArrayBuffer -> Uint8List (js_interop)
          // فعلاً مسیر اصلی وب با base64 است. اگر باینری هم آمد، نادیده می‌گیریم.
        } catch (_) {}
      });
    } catch (e) {
      _onError?.call(e);
      disconnect();
    }
  }

  @override
  void sendBytes(List<int> bytes) {
    if (!isConnected) return;
    try {
      // برای ساده‌سازی و سازگاری، صوت را در وب base64 و به صورت JSON می‌فرستیم
      final b64 = base64Encode(bytes);
      sendJson({'type': 'audio', 'audio_b64': b64});
    } catch (_) {}
  }

  @override
  void sendJson(Map<String, dynamic> payload) {
    if (!isConnected) return;
    try {
      _ws!.send(jsonEncode(payload).toJS);
    } catch (_) {}
  }

  @override
  void disconnect() {
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _connected = false;
  }
}

VoiceWsClient createVoiceWsClient() => VoiceWsClientWeb();


