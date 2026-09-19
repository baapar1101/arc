import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';

class VoiceTtsPlayer {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _open = false;
  bool _playing = false;
  Completer<void>? _done;

  bool get isPlaying => _playing;

  Future<void> playWav(List<int> wavBytes) async {
    await stop();
    if (!_open) {
      await _player.openPlayer();
      _open = true;
    }
    final done = Completer<void>();
    _done = done;
    _playing = true;
    await _player.startPlayer(
      fromDataBuffer: Uint8List.fromList(wavBytes),
      codec: Codec.pcm16WAV,
      whenFinished: () {
        _playing = false;
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
  }

  Future<void> stop() async {
    if (!_playing && !_open) {
      _completeDone();
      return;
    }
    try {
      await _player.stopPlayer();
    } catch (_) {}
    _playing = false;
    _completeDone();
  }

  void _completeDone() {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> dispose() async {
    await stop();
    if (_open) {
      try {
        await _player.closePlayer();
      } catch (_) {}
      _open = false;
    }
  }
}
