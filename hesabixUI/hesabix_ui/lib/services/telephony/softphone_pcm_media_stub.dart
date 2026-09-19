import 'dart:typed_data';

/// رابط مشترک پخش/ضبط PCM16LE برای Softphone Relay (8kHz mono).
abstract class SoftphonePcmMedia {
  Future<void> start();

  Future<void> startMic(void Function(Uint8List pcm) onFrame);

  Future<void> stopMic();

  void playPcm(List<int> pcm);

  Future<void> stop();

  bool get isReady;

  bool get isMicActive;
}

SoftphonePcmMedia createSoftphonePcmMedia({
  int sampleRate = 8000,
  int numChannels = 1,
}) =>
    throw UnsupportedError('Softphone PCM media unsupported on this platform');
