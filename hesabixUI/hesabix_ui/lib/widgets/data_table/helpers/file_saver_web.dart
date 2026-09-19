import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';

/// Legacy helper — prefer [BytesExportService] directly in new code.
class FileSaver {
  static Future<String?> saveBytes(List<int> bytes, String filename) async {
    final result = await BytesExportService.export(
      bytes: bytes,
      filename: filename,
    );
    if (result.isCancelled) return null;
    return result.path ?? result.filename;
  }
}
