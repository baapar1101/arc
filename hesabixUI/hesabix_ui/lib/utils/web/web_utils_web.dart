import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// آدرس object URL برای استفاده در iframe یا پنجره جدید؛ بعد از استفاده [revokeBlobUrl] را صدا بزنید.
String createObjectUrlFromBytes(
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) {
  final u8 = Uint8List.fromList(bytes);
  final jsU8 = u8.toJS;
  final parts = <JSAny>[jsU8 as JSAny].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mimeType));
  return web.URL.createObjectURL(blob);
}

void revokeBlobUrl(String url) {
  if (url.isEmpty) return;
  web.URL.revokeObjectURL(url);
}

Future<void> saveBytesAsFileWeb(
  List<int> bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) async {
  final safeName = filename.isEmpty ? 'download.bin' : filename;
  final dataUrl = createObjectUrlFromBytes(bytes, mimeType: mimeType);
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = safeName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  revokeBlobUrl(dataUrl);
}

void openUrlInNewTabWeb(String url) {
  if (url.isEmpty) return;
  web.window.open(url, '_blank');
}

String? getLocalStorageValue(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void setLocalStorageValue(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

