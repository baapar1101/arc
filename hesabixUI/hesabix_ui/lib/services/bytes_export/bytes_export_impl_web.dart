import 'dart:typed_data';

import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;

import 'bytes_export_types.dart';

Future<BytesExportResult> exportBytesImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required BytesExportMode mode,
}) async {
  await web_utils.saveBytesAsFileWeb(
    bytes,
    filename,
    mimeType: mimeType,
  );
  return BytesExportResult(
    outcome: BytesExportOutcome.downloaded,
    filename: filename,
  );
}
