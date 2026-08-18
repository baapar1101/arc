import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'voice_web_capture.dart';

class VoiceDictationController {
  VoiceWebCapture? _capture;
  web.AudioContext? _ctx;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  Future<void> start({required void Function(List<int> pcmChunk) onPcm}) async {
    _buffer.clear();
    _ctx = web.AudioContext();
    try {
      await _ctx!.resume().toDart;
    } catch (_) {}
    _capture = VoiceWebCapture(
      onPcmFrame: (pcm) {
        if (pcm.isEmpty) return;
        _buffer.add(pcm);
        onPcm(pcm);
      },
    );
    await _capture!.start(_ctx!, 16000);
  }

  Future<List<int>> stop() async {
    try {
      await _capture?.stop();
    } catch (_) {}
    _capture = null;
    try {
      await _ctx?.close().toDart;
    } catch (_) {}
    _ctx = null;
    return _buffer.takeBytes();
  }

  Future<void> dispose() async {
    await stop();
  }
}
