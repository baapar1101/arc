import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:share_plus/share_plus.dart';

import 'bytes_export_filename.dart';
import 'bytes_export_types.dart';

Future<BytesExportResult> exportBytesImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required BytesExportMode mode,
}) async {
  if (mode == BytesExportMode.share) {
    try {
      final result = await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: mimeType,
            name: filename,
          ),
        ],
        subject: filename,
      );
      if (result.status == ShareResultStatus.dismissed) {
        return BytesExportResult(
          outcome: BytesExportOutcome.cancelled,
          filename: filename,
        );
      }
      return BytesExportResult(
        outcome: BytesExportOutcome.shared,
        filename: filename,
      );
    } catch (_) {
      // Share unsupported (e.g. some desktop targets) → Save-As / Downloads.
      return _save(bytes: bytes, filename: filename, mimeType: mimeType);
    }
  }

  return _save(bytes: bytes, filename: filename, mimeType: mimeType);
}

Future<BytesExportResult> _save({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final parts = BytesExportFilename.split(filename);
  final baseName = parts.baseName;
  final ext = parts.extension;
  final mime = _toFileSaverMime(ext, mimeType);

  if (_supportsSaveAs) {
    try {
      // Windows native saveAs only opens the dialog and returns the path;
      // bytes must be written in Dart (file_saver windows/file_saver_plugin.cpp).
      // Windows also expects ext with a leading dot for the default filename/filter.
      final saveAsExt = Platform.isWindows ? '.$ext' : ext;
      final path = await FileSaver.instance.saveAs(
        name: baseName,
        bytes: bytes,
        ext: saveAsExt,
        mimeType: mime.mimeType,
        customMimeType: mime.customMimeType,
      );
      if (path == null || path.isEmpty) {
        return BytesExportResult(
          outcome: BytesExportOutcome.cancelled,
          filename: filename,
        );
      }
      if (_looksLikeSaveError(path)) {
        throw Exception(path);
      }
      final savedPath = Platform.isWindows
          ? await _writeBytesToPath(bytes: bytes, path: path, ext: ext)
          : path;
      return BytesExportResult(
        outcome: BytesExportOutcome.saved,
        filename: filename,
        path: savedPath,
      );
    } on UnimplementedError {
      // Fall through to Downloads-style saveFile.
    }
  }

  final path = await FileSaver.instance.saveFile(
    name: baseName,
    bytes: bytes,
    ext: ext,
    mimeType: mime.mimeType,
    customMimeType: mime.customMimeType,
  );
  if (_looksLikeSaveError(path)) {
    throw Exception(path);
  }
  return BytesExportResult(
    outcome: BytesExportOutcome.saved,
    filename: filename,
    path: path,
  );
}

bool get _supportsSaveAs {
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows) {
    return true;
  }
  return false;
}

Future<String> _writeBytesToPath({
  required Uint8List bytes,
  required String path,
  required String ext,
}) async {
  var target = path;
  if (ext.isNotEmpty) {
    final dotted = ext.startsWith('.') ? ext : '.$ext';
    if (!target.toLowerCase().endsWith(dotted.toLowerCase())) {
      target = '$target$dotted';
    }
  }
  final file = File(target);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

bool _looksLikeSaveError(String path) {
  final lower = path.toLowerCase();
  return lower.startsWith('error') ||
      lower.contains('something went wrong') ||
      lower.contains('please report the issue');
}

({MimeType mimeType, String? customMimeType}) _toFileSaverMime(
  String extension,
  String mimeType,
) {
  switch (extension.toLowerCase()) {
    case 'pdf':
      return (mimeType: MimeType.pdf, customMimeType: null);
    case 'xlsx':
      return (mimeType: MimeType.microsoftExcel, customMimeType: null);
    case 'csv':
      return (mimeType: MimeType.csv, customMimeType: null);
    case 'zip':
      return (mimeType: MimeType.zip, customMimeType: null);
    case 'json':
      return (mimeType: MimeType.json, customMimeType: null);
    case 'txt':
      return (mimeType: MimeType.text, customMimeType: null);
    case 'png':
      return (mimeType: MimeType.png, customMimeType: null);
    case 'jpg':
    case 'jpeg':
      return (mimeType: MimeType.jpeg, customMimeType: null);
    default:
      return (mimeType: MimeType.custom, customMimeType: mimeType);
  }
}
