class VoiceDictationController {
  Future<void> start({required void Function(List<int> pcmChunk) onPcm}) async {
    throw UnsupportedError('دیکته روی این پلتفرم پشتیبانی نمی‌شود');
  }

  Future<List<int>> stop() async => const [];
  Future<void> dispose() async {}
}
