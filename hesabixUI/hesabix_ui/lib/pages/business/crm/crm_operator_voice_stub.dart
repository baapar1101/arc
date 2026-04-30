import 'dart:typed_data';

import 'crm_operator_voice_api.dart';

class _NoopVoice implements OperatorVoiceController {
  @override
  Future<void> dispose() async {}

  @override
  Future<bool> ensureReady() async => false;

  @override
  Future<bool> startRecording() async => false;

  @override
  Future<(Uint8List bytes, String filename)?> stopAndRead() async => null;
}

OperatorVoiceController createOperatorVoiceController() => _NoopVoice();
