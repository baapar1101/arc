import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../voice/voice_web_capture.dart';
import 'softphone_pcm_media_stub.dart';
import 'telephony_l10n.dart';

export 'softphone_pcm_media_stub.dart';

/// پخش PCM با jitter buffer کوتاه (هدف ~۶۰ms، سقف ~۱۴۰ms).
///
/// پیاده‌سازی قبلی هر فریم را پشت‌سرهم در آینده زمان‌بندی می‌کرد و صف تا
/// ۶۰ فریم (~۱.۲s) رشد می‌کرد — علت اصلی تأخیر و بریدگی صدا.
class WebSoftphonePcmMedia implements SoftphonePcmMedia {
  WebSoftphonePcmMedia({this.sampleRate = 8000, this.numChannels = 1});

  final int sampleRate;
  final int numChannels;

  static const int _frameMs = 20;
  static const int _targetMs = 60;
  static const int _maxMs = 140;

  web.AudioContext? _ctx;
  VoiceWebCapture? _capture;
  bool _ready = false;
  bool _mic = false;
  bool _primed = false;
  Timer? _pump;

  final List<int> _samples = <int>[];
  double _playHeadTime = 0.0;

  int get _frameSamples => (sampleRate * _frameMs) ~/ 1000;
  int get _targetSamples => (sampleRate * _targetMs) ~/ 1000;
  int get _maxSamples => (sampleRate * _maxMs) ~/ 1000;

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
    _pump ??= Timer.periodic(const Duration(milliseconds: 20), (_) => _pumpPlayback());
    _ready = true;
  }

  @override
  Future<void> startMic(void Function(Uint8List pcm) onFrame) async {
    if (!_ready || _mic) return;
    final ctx = _ctx;
    if (ctx == null) throw StateError(telephonyL10n().telephonyAudioContextMissing);
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
    _samples.addAll(_asPcm16(pcm));
    if (_samples.length > _maxSamples) {
      _samples.removeRange(0, _samples.length - _targetSamples);
      _playHeadTime = _ctx!.currentTime + (_targetMs / 1000.0);
    }
    if (!_primed) {
      if (_samples.length < _targetSamples) return;
      _primed = true;
      _playHeadTime = _ctx!.currentTime + (_frameMs / 1000.0);
    }
    _pumpPlayback();
  }

  void _pumpPlayback() {
    final ctx = _ctx;
    if (ctx == null || !_primed) return;
    final now = ctx.currentTime;
    if (_playHeadTime < now - 0.04) {
      // underrun — دوباره از هدف کوچک شروع کن
      if (_samples.length < _frameSamples) {
        _primed = false;
        return;
      }
      _playHeadTime = now + (_frameMs / 1000.0);
    }
    while (_samples.length >= _frameSamples) {
      if (_playHeadTime - now > (_maxMs / 1000.0)) break;
      final frame = Int16List.fromList(_samples.sublist(0, _frameSamples));
      _samples.removeRange(0, _frameSamples);
      _scheduleFrame(ctx, frame);
    }
  }

  void _scheduleFrame(web.AudioContext ctx, Int16List chunk) {
    final float32 = Float32List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      float32[i] = (chunk[i] / 32768.0).clamp(-1.0, 1.0);
    }
    final audioBuffer = ctx.createBuffer(1, float32.length, sampleRate);
    audioBuffer.copyToChannel(float32.toJS, 0);
    final src = ctx.createBufferSource();
    src.buffer = audioBuffer;
    src.connect(ctx.destination);
    src.start(_playHeadTime);
    _playHeadTime += float32.length / sampleRate;
  }

  Int16List _asPcm16(List<int> pcm) {
    final bytes = Uint8List.fromList(pcm);
    final even = bytes.length - (bytes.length % 2);
    if (even <= 0) return Int16List(0);
    return Int16List.view(bytes.buffer, bytes.offsetInBytes, even ~/ 2);
  }

  @override
  Future<void> stop() async {
    await stopMic();
    _pump?.cancel();
    _pump = null;
    _samples.clear();
    _primed = false;
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
