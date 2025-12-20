import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> saveBytesAsFileWeb(
  List<int> bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) async {
  final safeName = filename.isEmpty ? 'download.bin' : filename;
  // Use Blob + ObjectURL to avoid data: URL limits and large base64 payloads.
  final u8 = Uint8List.fromList(bytes);
  final jsU8 = u8.toJS; // JSUint8Array
  final parts = <JSAny>[jsU8 as JSAny].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mimeType));
  final dataUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = safeName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(dataUrl);
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

