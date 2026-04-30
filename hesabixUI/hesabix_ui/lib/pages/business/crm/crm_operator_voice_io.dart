import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import 'crm_operator_voice_api.dart';

class _IoVoice implements OperatorVoiceController {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  String? _path;
  bool _opened = false;
  bool _recording = false;

  @override
  Future<bool> ensureReady() async {
    final p = await Permission.microphone.request();
    return p.isGranted;
  }

  @override
  Future<void> dispose() async {
    try {
      if (_recording) {
        await _recorder.stopRecorder();
      }
    } catch (_) {}
    try {
      await _recorder.closeRecorder();
    } catch (_) {}
    _opened = false;
    _recording = false;
    _path = null;
  }

  @override
  Future<bool> startRecording() async {
    if (!_opened) {
      await _recorder.openRecorder();
      _opened = true;
    }
    if (_recording) {
      return true;
    }
    final millis = DateTime.now().millisecondsSinceEpoch;
    final path = '${Directory.systemTemp.path}/crm_chat_voice_$millis.aac';
    _path = path;
    await _recorder.startRecorder(
      toFile: _path,
      codec: Codec.aacADTS,
      bitRate: 128000,
    );
    _recording = true;
    return true;
  }

  @override
  Future<(Uint8List bytes, String filename)?> stopAndRead() async {
    if (!_recording) return null;
    _recording = false;
    try {
      await _recorder.stopRecorder();
    } catch (_) {}
    final path = _path;
    _path = null;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;
    final fname = path.split(RegExp(r'[/\\]')).last;
    try {
      await f.delete();
    } catch (_) {}
    return (Uint8List.fromList(bytes), fname);
  }
}

OperatorVoiceController createOperatorVoiceController() => _IoVoice();
