import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/voice/voice_pcm_wav.dart';

void main() {
  test('pcm16ToWav writes a valid 16 kHz mono header', () {
    final pcm = Uint8List.fromList(List<int>.filled(320, 0));
    final wav = pcm16ToWav(pcm);
    expect(wav.length, 44 + pcm.length);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    final dataLen = wav.buffer.asByteData().getUint32(40, Endian.little);
    expect(dataLen, pcm.length);
  });
}
