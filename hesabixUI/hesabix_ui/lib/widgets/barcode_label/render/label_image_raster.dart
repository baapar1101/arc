import 'dart:typed_data';
import 'dart:ui' as ui;

/// رستر تک‌رنگ برای ^GFA در ZPL — فقط Flutter (وب/اندروید/ویندوز).
class LabelImageRaster {
  LabelImageRaster._();

  static Future<List<int>?> toZplGfaBytes(
    Uint8List imageBytes, {
    required int widthPx,
    required int heightPx,
  }) async {
    if (widthPx < 1 || heightPx < 1) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: widthPx,
        targetHeight: heightPx,
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (data == null) return null;
      final bytesPerRow = (widthPx + 7) ~/ 8;
      final out = List<int>.filled(bytesPerRow * heightPx, 0);
      for (var y = 0; y < heightPx; y++) {
        for (var x = 0; x < widthPx; x++) {
          final i = (y * widthPx + x) * 4;
          final r = data.getUint8(i);
          final g = data.getUint8(i + 1);
          final b = data.getUint8(i + 2);
          final lum = (0.299 * r + 0.587 * g + 0.114 * b).round();
          if (lum < 128) {
            final byteIndex = y * bytesPerRow + (x ~/ 8);
            final bit = 7 - (x % 8);
            out[byteIndex] |= 1 << bit;
          }
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }
}
