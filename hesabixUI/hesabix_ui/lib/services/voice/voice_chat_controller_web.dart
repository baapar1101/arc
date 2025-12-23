import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/api_client.dart';
import 'voice_ws_client.dart';

/// VoiceChatController برای وب (بدون flutter_sound):
/// - ضبط: getUserMedia + ScriptProcessor (پایدارتر برای MVP) + resample به 16kHz + PCM16
/// - پخش: AudioContext + queue + schedule
///
/// نکته: شروع AudioContext و getUserMedia باید با gesture کاربر باشد (کلیک دکمه).
class VoiceChatController {
  VoiceChatController({
    required this.sessionId,
    required this.collectDataOptIn,
    required this.onEvent,
    required this.onError,
  });

  final int sessionId;
  final bool collectDataOptIn;
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(String message) onError;

  final VoiceWsClient _ws = createVoiceWsClient();

  bool _started = false;
  bool _recording = false;

  static const int _targetSampleRate = 16000;
  static const int _channels = 1;

  web.AudioContext? _ctx;
  web.MediaStream? _mediaStream;
  web.MediaStreamAudioSourceNode? _micSource;
  web.ScriptProcessorNode? _processor;

  // playback queue with max size limit
  final List<Int16List> _playQueue = <Int16List>[];
  static const int _maxQueueSize = 50; // Maximum number of chunks in queue
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

    // AudioContext (must be user-gesture initiated)
    _ctx = web.AudioContext();
    try {
      await _ctx!.resume().toDart;
    } catch (_) {}
    _playHeadTime = _ctx!.currentTime;

    // connect WS
    await _ws.connect(
      apiKey: apiKey,
      onEvent: (event) => onEvent(event),
      onAudioFrame: (pcm) {
        // server sends PCM16 @ 16kHz (binary or base64-decoded by ws client)
        _enqueuePcmForPlayback(pcm);
      },
      onError: (e) => onError(e.toString()),
      onDone: () => onError('اتصال صوت قطع شد.'),
    );
    
    // Enable reconnection for web client
    if (_ws is VoiceWsClientWeb) {
      (_ws as dynamic).enableReconnect();
    }

    // request base64 transport for web
    _ws.sendJson({
      'type': 'start',
      'session_id': sessionId,
      'collect_data': collectDataOptIn,
      'audio_transport': 'base64',
    });

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
      final nav = web.window.navigator;
      final devices = nav.mediaDevices;
      if (devices == null) {
        onError('این مرورگر از mediaDevices پشتیبانی نمی‌کند.');
        return;
      }

      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );
      final stream = await devices.getUserMedia(constraints).toDart;
      _mediaStream = stream;

      _micSource = _ctx!.createMediaStreamSource(stream);
      // ScriptProcessorNode (deprecated but still widely supported; good MVP)
      _processor = _ctx!.createScriptProcessor(4096, _channels, _channels);

      final inputRate = _ctx!.sampleRate.toDouble();
      _processor!.onaudioprocess = (web.AudioProcessingEvent ev) {
        try {
          final buffer = ev.inputBuffer;
          final chan0 = buffer.getChannelData(0);
          final float32 = _jsFloat32ToDart(chan0);
          final resampled = _resampleFloat32(float32, inputRate, _targetSampleRate.toDouble());
          final pcm16 = _floatToPcm16(resampled);
          if (pcm16.isNotEmpty) {
            _ws.sendBytes(pcm16.buffer.asUint8List());
          }
        } catch (_) {}
      }.toJS;

      _micSource!.connect(_processor!);
      // must connect to destination for some browsers to fire onaudioprocess
      _processor!.connect(_ctx!.destination);

      _recording = true;
    } catch (e) {
      onError('خطا در دسترسی به میکروفون: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_recording) return;
    _recording = false;

    try {
      _processor?.disconnect();
    } catch (_) {}
    try {
      _micSource?.disconnect();
    } catch (_) {}
    _processor = null;
    _micSource = null;

    try {
      final tracks = _mediaStream?.getTracks();
      if (tracks != null) {
        for (final t in tracks.toDart) {
          try {
            t.stop();
          } catch (_) {}
        }
      }
    } catch (_) {}
    _mediaStream = null;
  }

  Future<void> stop() async {
    if (!_started) return;
    _ws.sendJson({'type': 'stop'});
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

  // ===== Playback =====
  void _enqueuePcmForPlayback(List<int> pcmBytes) {
    if (_ctx == null) return;
    if (pcmBytes.isEmpty) return;
    final bytes = Uint8List.fromList(pcmBytes);
    final pcm16 = bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
    
    // Limit queue size to prevent memory issues
    if (_playQueue.length >= _maxQueueSize) {
      // Remove oldest items if queue is full
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

    // schedule a few buffers ahead
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

      // اگر playhead عقب افتاده، از الآن شروع کن
      final now = ctx.currentTime;
      if (_playHeadTime < now) _playHeadTime = now;
      src.start(_playHeadTime);
      _playHeadTime += float32.length / _targetSampleRate;
    }

    _playPumpActive = false;
  }

  // ===== DSP helpers =====
  static Float32List _jsFloat32ToDart(JSFloat32Array arr) {
    // JSFloat32Array -> Dart Float32List
    return arr.toDart;
  }

  static Float32List _resampleFloat32(Float32List input, double inRate, double outRate) {
    if (input.isEmpty) return Float32List(0);
    if ((inRate - outRate).abs() < 1e-6) return input;

    final ratio = inRate / outRate;
    final outLen = (input.length / ratio).floor();
    if (outLen <= 0) return Float32List(0);

    final out = Float32List(outLen);
    for (var i = 0; i < outLen; i++) {
      final srcIndex = i * ratio;
      final i0 = srcIndex.floor();
      final i1 = math.min(i0 + 1, input.length - 1);
      final frac = srcIndex - i0;
      out[i] = (input[i0] * (1.0 - frac)) + (input[i1] * frac);
    }
    return out;
  }

  static Int16List _floatToPcm16(Float32List input) {
    final out = Int16List(input.length);
    for (var i = 0; i < input.length; i++) {
      final v = input[i].clamp(-1.0, 1.0);
      out[i] = (v * 32767.0).round();
    }
    return out;
  }
}


