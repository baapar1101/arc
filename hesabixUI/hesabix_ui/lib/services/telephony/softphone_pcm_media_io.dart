import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import 'softphone_pcm_media_stub.dart';
import 'softphone_pcm_media_windows.dart';

export 'softphone_pcm_media_stub.dart';

class IoSoftphonePcmMedia implements SoftphonePcmMedia {
  IoSoftphonePcmMedia({this.sampleRate = 8000, this.numChannels = 1});

  final int sampleRate;
  final int numChannels;

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamController<Uint8List>? _micCtrl;
  StreamSubscription<Uint8List>? _micSub;
  bool _ready = false;
  bool _mic = false;
  static const int _bufferSize = 4096;

  @override
  bool get isReady => _ready;

  @override
  bool get isMicActive => _mic;

  @override
  Future<void> start() async {
    if (_ready) return;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      throw StateError('دسترسی میکروفون داده نشد');
    }
    await _player.openPlayer();
    await _recorder.openRecorder();
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: numChannels,
      sampleRate: sampleRate,
      bufferSize: _bufferSize,
    );
    _ready = true;
  }

  @override
  Future<void> startMic(void Function(Uint8List pcm) onFrame) async {
    if (!_ready || _mic) return;
    try {
      await _micCtrl?.close();
    } catch (_) {}
    _micCtrl = StreamController<Uint8List>();
    _micSub = _micCtrl!.stream.listen((chunk) {
      if (chunk.isEmpty) return;
      onFrame(chunk);
    });
    await _recorder.startRecorder(
      toStream: _micCtrl!.sink,
      codec: Codec.pcm16,
      numChannels: numChannels,
      sampleRate: sampleRate,
      bufferSize: _bufferSize,
    );
    _mic = true;
  }

  @override
  Future<void> stopMic() async {
    if (!_mic) return;
    try {
      await _recorder.stopRecorder();
    } catch (_) {}
    _mic = false;
    try {
      await _micSub?.cancel();
    } catch (_) {}
    _micSub = null;
    try {
      await _micCtrl?.close();
    } catch (_) {}
    _micCtrl = null;
  }

  @override
  void playPcm(List<int> pcm) {
    if (!_ready || pcm.isEmpty) return;
    try {
      _player.uint8ListSink?.add(Uint8List.fromList(pcm));
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    await stopMic();
    if (_ready) {
      try {
        await _player.stopPlayer();
      } catch (_) {}
      try {
        await _recorder.closeRecorder();
      } catch (_) {}
      try {
        await _player.closePlayer();
      } catch (_) {}
    }
    _ready = false;
  }
}

SoftphonePcmMedia createSoftphonePcmMedia({
  int sampleRate = 8000,
  int numChannels = 1,
}) {
  // flutter_sound's Windows plugin is a stub (channel "taudio" only) and
  // throws MissingPluginException on openPlayer — use WinMM instead.
  if (Platform.isWindows) {
    return WindowsSoftphonePcmMedia(
      sampleRate: sampleRate,
      numChannels: numChannels,
    );
  }
  return IoSoftphonePcmMedia(sampleRate: sampleRate, numChannels: numChannels);
}
