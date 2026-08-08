import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// زنگ ورودی وب با دو اسیلاتور (ring cadence).
class SoftphoneRingtone {
  web.AudioContext? _ctx;
  Timer? _cadence;
  bool _playing = false;

  bool get isPlaying => _playing;

  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    _ctx ??= web.AudioContext();
    try {
      await _ctx!.resume().toDart;
    } catch (_) {}
    _burst();
    _cadence?.cancel();
    _cadence = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (_playing) _burst();
    });
  }

  void _burst() {
    final ctx = _ctx;
    if (ctx == null) return;
    final now = ctx.currentTime;
    for (final freq in <double>[440, 480]) {
      final osc = ctx.createOscillator();
      final gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.exponentialRampToValueAtTime(0.09, now + 0.02);
      gain.gain.setValueAtTime(0.09, now + 0.85);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.05);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 1.1);
    }
  }

  Future<void> stop() async {
    _playing = false;
    _cadence?.cancel();
    _cadence = null;
  }
}

SoftphoneRingtone createPlatformSoftphoneRingtone() => SoftphoneRingtone();
