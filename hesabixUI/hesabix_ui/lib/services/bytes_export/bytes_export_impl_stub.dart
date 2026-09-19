import 'dart:typed_data';

import 'bytes_export_types.dart';

Future<BytesExportResult> exportBytesImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required BytesExportMode mode,
}) async {
  throw UnsupportedError('File export is not supported on this platform.');
}
