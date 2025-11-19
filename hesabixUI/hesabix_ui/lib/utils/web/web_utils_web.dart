import 'dart:convert';
import 'package:web/web.dart' as web;

Future<void> saveBytesAsFileWeb(
  List<int> bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) async {
  final safeName = filename.isEmpty ? 'download.bin' : filename;
  final dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = safeName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
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

