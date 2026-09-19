/// Stub — بدون پخش واقعی.
class SoftphoneRingtone {
  bool _playing = false;
  bool get isPlaying => _playing;
  Future<void> start() async => _playing = true;
  Future<void> stop() async => _playing = false;
}

SoftphoneRingtone createPlatformSoftphoneRingtone() => SoftphoneRingtone();
