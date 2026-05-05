import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../utils/notification_sound_catalog.dart';

/// پخش کوتاه صدای هشدار با [flutter_sound] و دارایی‌های `assets/sounds/`.
class NotificationAlertSoundPlayer {
  NotificationAlertSoundPlayer._();

  static final FlutterSoundPlayer _player = FlutterSoundPlayer();
  static bool _opened = false;

  static Future<void> _ensureOpen() async {
    if (_opened) return;
    await _player.openPlayer();
    _opened = true;
  }

  static Future<void> playForSoundAssetId(String soundAssetId) async {
    final path = NotificationSoundCatalog.assetBundlePath(soundAssetId);
    try {
      await _ensureOpen();
      final bd = await rootBundle.load(path);
      await _player.startPlayer(
        fromDataBuffer: bd.buffer.asUint8List(),
        codec: Codec.mp3,
      );
    } catch (_) {
      try {
        await _ensureOpen();
        await _player.startPlayer(fromURI: path, codec: Codec.mp3);
      } catch (_) {}
    }
  }

  static Future<void> previewSoundAssetId(String soundAssetId) => playForSoundAssetId(soundAssetId);
}
