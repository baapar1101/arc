import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../core/api_client.dart';
import 'voice_web_capture.dart';
import 'voice_ws_client.dart';

/// VoiceChatController برای وب — پردازش صوت کاملاً محلی در مرورگر/سرور خودتان.
class VoiceChatController {
  VoiceChatController({
    required this.sessionId,
    required this.collectDataOptIn,
    required this.onEvent,
    required this.onError,
    this.modelCode,
    this.executionMode,
    this.sttCode,
    this.ttsCode,
  });

  final int sessionId;
  final bool collectDataOptIn;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(String message) onError;
  final String? modelCode;
  final String? executionMode;
  final String? sttCode;
  final String? ttsCode;

  final VoiceWsClient _ws = createVoiceWsClient();

  bool _started = false;
  bool _recording = false;
  VoiceWebCapture? _capture;

  static const int _targetSampleRate = 16000;

  web.AudioContext? _ctx;

  final List<Int16List> _playQueue = <Int16List>[];
  static const int _maxQueueSize = 50;
  bool _playPumpActive = false;
  double _playHeadTime = 0.0;

  bool get isActive => _started;
  bool get isRecording => _recording;

  Future<void> start() async {
    if (_started) return;

    final authStore = ApiClient.getAuthStore();
    final apiKey = authStore?.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      onError('کلید API موجود نیست.');
      return;
    }

    _ctx = web.AudioContext();
    try {
      await _ctx!.resume().toDart;
    } catch (_) {}
    _playHeadTime = _ctx!.currentTime;

    final startPayload = <String, dynamic>{
      'type': 'start',
      'session_id': sessionId,
      'collect_data': collectDataOptIn,
      'audio_transport': 'binary',
      'input_codec': 'pcm',
      if (modelCode != null && modelCode!.isNotEmpty) 'model_code': modelCode,
      if (executionMode != null && executionMode!.isNotEmpty)
        'execution_mode': executionMode,
      if (sttCode != null && sttCode!.isNotEmpty) 'stt_code': sttCode,
      if (ttsCode != null && ttsCode!.isNotEmpty) 'tts_code': ttsCode,
    };
    _ws.setSessionStartPayload(startPayload);

    await _ws.connect(
      apiKey: apiKey,
      onEvent: (event) => onEvent(event),
      onAudioFrame: _enqueuePcmForPlayback,
      onError: (e) => onError(e.toString()),
      onDone: () => onError('اتصال صوت قطع شد.'),
      onReconnected: () => onEvent({'type': 'reconnected'}),
      preferBinaryDownlink: true,
    );

    _ws.enableReconnect();
    _ws.sendJson(startPayload);

    _started = true;
  }

  Future<void> startRecording() async {
    if (!_started || _recording) return;
    if (_ctx == null) {
      onError('AudioContext آماده نیست.');
      return;
    }

    _ws.sendJson({'type': 'barge_in'});

    try {
      _capture = VoiceWebCapture(
        onPcmFrame: (pcm) {
          if (pcm.isNotEmpty) {
            _ws.sendBytes(pcm);
          }
        },
      );
      final mode = await _capture!.start(_ctx!, _targetSampleRate);
      if (mode == VoiceWebCaptureMode.webmOpus) {
        onEvent({'type': 'capture_mode', 'mode': 'webm_opus'});
      } else {
        onEvent({'type': 'capture_mode', 'mode': 'pcm_worklet'});
      }
      _recording = true;
    } catch (e) {
      onError('خطا در دسترسی به میکروفون: $e');
    }
  }

  void bargeIn() {
    if (!_started) return;
    _ws.sendJson({'type': 'barge_in'});
  }

  Future<void> stopRecording() async {
    if (!_recording) return;
    _recording = false;
    try {
      await _capture?.stop();
    } catch (_) {}
    _capture = null;
  }

  Future<void> stop() async {
    if (!_started) return;
    _ws.sendJson({'type': 'stop'});
    _ws.disableReconnect();
    _ws.disconnect();
    await stopRecording();
    _playQueue.clear();
    _playPumpActive = false;
    try {
      await _ctx?.close().toDart;
    } catch (_) {}
    _ctx = null;
    _started = false;
  }

  Future<void> dispose() async {
    try {
      await stop();
    } catch (_) {}
  }

  void _enqueuePcmForPlayback(List<int> pcmBytes) {
    if (_ctx == null || pcmBytes.isEmpty) return;
    final bytes = Uint8List.fromList(pcmBytes);
    final pcm16 = bytes.buffer.asInt16List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 2,
    );

    if (_playQueue.length >= _maxQueueSize) {
      _playQueue.removeRange(0, _playQueue.length - _maxQueueSize + 1);
    }

    _playQueue.add(Int16List.fromList(pcm16));
    _pumpPlayback();
  }

  void _pumpPlayback() {
    if (_playPumpActive) return;
    final ctx = _ctx;
    if (ctx == null) return;
    _playPumpActive = true;

    while (_playQueue.isNotEmpty) {
      final chunk = _playQueue.removeAt(0);
      final float32 = Float32List(chunk.length);
      for (var i = 0; i < chunk.length; i++) {
        float32[i] = (chunk[i] / 32768.0).clamp(-1.0, 1.0);
      }

      final audioBuffer = ctx.createBuffer(1, float32.length, _targetSampleRate);
      audioBuffer.copyToChannel(float32.toJS, 0);

      final src = ctx.createBufferSource();
      src.buffer = audioBuffer;
      src.connect(ctx.destination);

      final now = ctx.currentTime;
      if (_playHeadTime < now) _playHeadTime = now;
      src.start(_playHeadTime);
      _playHeadTime += float32.length / _targetSampleRate;
    }

    _playPumpActive = false;
  }
}
