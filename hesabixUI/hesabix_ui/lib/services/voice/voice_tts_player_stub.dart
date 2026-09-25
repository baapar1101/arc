class VoiceTtsPlayer {
  Future<void> playWav(List<int> wavBytes) async {
    throw UnsupportedError('پخش صدا روی این پلتفرم پشتیبانی نمی‌شود');
  }

  Future<void> stop() async {}
  Future<void> dispose() async {}
  bool get isPlaying => false;
}
