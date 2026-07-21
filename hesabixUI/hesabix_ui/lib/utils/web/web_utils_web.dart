import 'dart:js_interop';
import 'dart:typed_data';

import 'package:hesabix_ui/core/app_init_progress.dart';
import 'package:web/web.dart' as web;

@JS('window.__hesabixSignalAppReady')
external void _hesabixSignalAppReady();

@JS('window.__hesabixLoaderUI.setInitProgress')
external void _setWebInitProgress(
  JSNumber percent,
  JSNumber currentStep,
  JSNumber totalSteps,
  JSString? statusKey,
);

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

/// به‌روزرسانی لودر HTML در فاز init داخل Flutter (۹۶–۱۰۰٪).
void notifyWebInitProgress({
  required double initProgress,
  required int currentStep,
  required int totalSteps,
  String? statusKey,
}) {
  try {
    final percent = AppInitPhase.webPercentFromInitProgress(initProgress);
    _setWebInitProgress(
      percent.toJS,
      currentStep.toJS,
      totalSteps.toJS,
      (statusKey ?? '').toJS,
    );
  } catch (_) {}
}

/// پنهان کردن لودر HTML پس از آماده‌شدن Flutter.
void notifyWebAppReady() {
  try {
    _hesabixSignalAppReady();
  } catch (_) {}
}
