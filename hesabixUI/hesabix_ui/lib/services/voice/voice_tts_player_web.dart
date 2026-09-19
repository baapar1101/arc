import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class VoiceTtsPlayer {
  web.HTMLAudioElement? _audio;
  String? _objectUrl;
  bool _playing = false;
  Completer<void>? _done;

  bool get isPlaying => _playing;

  Future<void> playWav(List<int> wavBytes) async {
    await stop();
    final bytes = Uint8List.fromList(wavBytes);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'audio/wav'),
    );
    _objectUrl = web.URL.createObjectURL(blob);
    final audio = web.HTMLAudioElement()..src = _objectUrl!;
    _audio = audio;
    final done = Completer<void>();
    _done = done;
    _playing = true;
    audio.onEnded.listen((_) {
      _playing = false;
      if (!done.isCompleted) done.complete();
    });
    audio.onError.listen((_) {
      _playing = false;
      if (!done.isCompleted) {
        done.completeError(StateError('audio playback failed'));
      }
    });
    try {
      await audio.play().toDart;
    } catch (e) {
      _playing = false;
      _completeDone();
      rethrow;
    }
    await done.future;
  }

  Future<void> stop() async {
    try {
      _audio?.pause();
      _audio?.remove();
    } catch (_) {}
    _audio = null;
    if (_objectUrl != null) {
      try {
        web.URL.revokeObjectURL(_objectUrl!);
      } catch (_) {}
      _objectUrl = null;
    }
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
  }
}
