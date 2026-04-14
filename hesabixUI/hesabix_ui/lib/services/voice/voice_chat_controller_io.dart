import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import 'voice_ws_client.dart';

/// کنترلر Voice Chat (Android/iOS/Desktop):
/// - اتصال WS
/// - ضبط PCM16 و ارسال فریم‌ها
/// - دریافت PCM و پخش استریم
/// - ارسال پیام‌های start/barge_in/stop
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
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  StreamController<Uint8List>? _recorderStreamController;
  bool _started = false;
  bool _recording = false;
  bool _playing = false;

  static const int _sampleRate = 16000;
  static const int _numChannels = 1;
  static const int _bufferSize = 8192;

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

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      onError('دسترسی میکروفون داده نشد.');
      return;
    }

    await _player.openPlayer();
    await _recorder.openRecorder();

    // پخش استریم PCM (flutter_sound >= 9.30 نیاز به bufferSize + interleaved دارد)
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: _numChannels,
      sampleRate: _sampleRate,
      bufferSize: _bufferSize,
    );
    _playing = true;

    await _ws.connect(
      apiKey: apiKey,
      onEvent: (event) => onEvent(event),
      onAudioFrame: (pcm) {
        try {
          if (!_playing) return;
          _player.uint8ListSink?.add(Uint8List.fromList(pcm));
        } catch (_) {}
      },
      onError: (e) => onError(e.toString()),
      onDone: () => onError('اتصال صوت قطع شد.'),
    );
    
    // Enable reconnection for IO client
    if (_ws is VoiceWsClientIO) {
      (_ws as dynamic).enableReconnect();
    }

    _ws.sendJson({
      'type': 'start',
      'session_id': sessionId,
      'collect_data': collectDataOptIn,
    });

    _started = true;
  }

  Future<void> startRecording() async {
    if (!_started || _recording) return;

    _ws.sendJson({'type': 'barge_in'});

    try {
      await _recorderStreamController?.close();
    } catch (_) {}
    _recorderStreamController = StreamController<Uint8List>();

    _recorderStreamController!.stream.listen((chunk) {
      if (chunk.isEmpty) return;
      _ws.sendBytes(chunk);
    });

    await _recorder.startRecorder(
      toStream: _recorderStreamController!.sink,
      codec: Codec.pcm16,
      numChannels: _numChannels,
      sampleRate: _sampleRate,
      bufferSize: _bufferSize,
    );
    _recording = true;
  }

  Future<void> stopRecording() async {
    if (!_recording) return;
    try {
      await _recorder.stopRecorder();
    } catch (_) {}
    _recording = false;
    try {
      await _recorderStreamController?.close();
    } catch (_) {}
    _recorderStreamController = null;
  }

  Future<void> stop() async {
    if (!_started) return;
    _ws.sendJson({'type': 'stop'});
    _ws.disconnect();
    await stopRecording();
    await _stopPlayer();
    await _recorder.closeRecorder();
    await _player.closePlayer();
    _started = false;
  }

  Future<void> _stopPlayer() async {
    if (!_playing) return;
    try {
      await _player.stopPlayer();
    } catch (_) {}
    _playing = false;
  }

  Future<void> dispose() async {
    try {
      await stop();
    } catch (_) {}
  }
}


