import 'dart:async';

import 'package:flutter/services.dart';

/// زنگ ورودی روی موبایل/دسکتاپ — هشدار سیستم + ویبره.
class SoftphoneRingtone {
  Timer? _cadence;
  bool _playing = false;

  bool get isPlaying => _playing;

  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    await _burst();
    _cadence?.cancel();
    _cadence = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (_playing) unawaited(_burst());
    });
  }

  Future<void> _burst() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  Future<void> stop() async {
    _playing = false;
    _cadence?.cancel();
    _cadence = null;
  }
}

SoftphoneRingtone createPlatformSoftphoneRingtone() => SoftphoneRingtone();
