String createObjectUrlFromBytes(
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('Blob URLs are only supported on web.');
}

void revokeBlobUrl(String url) {}

Future<void> saveBytesAsFileWeb(
  List<int> bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('File download is only supported on web.');
}

void openUrlInNewTabWeb(String url) {
  throw UnsupportedError('Opening URLs in new tab is only supported on web.');
}

String? getLocalStorageValue(String key) => null;

void setLocalStorageValue(String key, String value) {}

