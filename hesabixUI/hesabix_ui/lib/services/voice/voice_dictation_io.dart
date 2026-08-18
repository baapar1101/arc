import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceDictationController {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  StreamController<Uint8List>? _controller;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  bool _open = false;

  Future<void> start({required void Function(List<int> pcmChunk) onPcm}) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      throw Exception('دسترسی میکروفون داده نشد');
    }
    if (!_open) {
      await _recorder.openRecorder();
      _open = true;
    }
    _buffer.clear();
    _controller = StreamController<Uint8List>();
    _controller!.stream.listen((chunk) {
      if (chunk.isEmpty) return;
      _buffer.add(chunk);
      onPcm(chunk);
    });
    await _recorder.startRecorder(
      toStream: _controller!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
      bufferSize: 8192,
    );
  }

  Future<List<int>> stop() async {
    try {
      await _recorder.stopRecorder();
    } catch (_) {}
    try {
      await _controller?.close();
    } catch (_) {}
    _controller = null;
    return _buffer.takeBytes();
  }

  Future<void> dispose() async {
    await stop();
    if (_open) {
      try {
        await _recorder.closeRecorder();
      } catch (_) {}
      _open = false;
    }
  }
}
