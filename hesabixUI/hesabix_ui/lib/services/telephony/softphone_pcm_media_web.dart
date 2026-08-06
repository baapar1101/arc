import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../voice/voice_web_capture.dart';
import 'softphone_pcm_media_stub.dart';

export 'softphone_pcm_media_stub.dart';

class WebSoftphonePcmMedia implements SoftphonePcmMedia {
  WebSoftphonePcmMedia({this.sampleRate = 8000, this.numChannels = 1});

  final int sampleRate;
  final int numChannels;

  web.AudioContext? _ctx;
  VoiceWebCapture? _capture;
  bool _ready = false;
  bool _mic = false;

  final List<Int16List> _playQueue = <Int16List>[];
  static const int _maxQueueSize = 60;
  bool _playPumpActive = false;
  double _playHeadTime = 0.0;

  @override
  bool get isReady => _ready;

  @override
  bool get isMicActive => _mic;

  @override
  Future<void> start() async {
    if (_ready) return;
    _ctx = web.AudioContext();
    try {
      await _ctx!.resume().toDart;
    } catch (_) {}
    _playHeadTime = _ctx!.currentTime;
    _ready = true;
  }

  @override
  Future<void> startMic(void Function(Uint8List pcm) onFrame) async {
    if (!_ready || _mic) return;
    final ctx = _ctx;
    if (ctx == null) throw StateError('AudioContext آماده نیست');
    _capture = VoiceWebCapture(
      onPcmFrame: (pcm) {
        if (pcm.isNotEmpty) onFrame(pcm);
      },
    );
    await _capture!.start(ctx, sampleRate);
    _mic = true;
  }

  @override
  Future<void> stopMic() async {
    if (!_mic) return;
    _mic = false;
    try {
      await _capture?.stop();
    } catch (_) {}
    _capture = null;
  }

  @override
  void playPcm(List<int> pcm) {
    if (!_ready || _ctx == null || pcm.isEmpty) return;
    final bytes = Uint8List.fromList(pcm);
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
      final audioBuffer = ctx.createBuffer(1, float32.length, sampleRate);
      audioBuffer.copyToChannel(float32.toJS, 0);
      final src = ctx.createBufferSource();
      src.buffer = audioBuffer;
      src.connect(ctx.destination);
      final now = ctx.currentTime;
      if (_playHeadTime < now) _playHeadTime = now;
      src.start(_playHeadTime);
      _playHeadTime += float32.length / sampleRate;
    }
    _playPumpActive = false;
  }

  @override
  Future<void> stop() async {
    await stopMic();
    _playQueue.clear();
    _playPumpActive = false;
    try {
      await _ctx?.close().toDart;
    } catch (_) {}
    _ctx = null;
    _ready = false;
  }
}

SoftphonePcmMedia createSoftphonePcmMedia({
  int sampleRate = 8000,
  int numChannels = 1,
}) =>
    WebSoftphonePcmMedia(sampleRate: sampleRate, numChannels: numChannels);
