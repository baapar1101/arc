import 'package:dio/dio.dart';

/// Shared filename / MIME helpers for [BytesExportService].
class BytesExportFilename {
  BytesExportFilename._();

  /// Split `report.pdf` → (`report`, `pdf`).
  static ({String baseName, String extension}) split(String filename) {
    final trimmed = filename.trim();
    final safe = trimmed.isEmpty ? 'download' : trimmed;
    final lastDot = safe.lastIndexOf('.');
    if (lastDot <= 0 || lastDot >= safe.length - 1) {
      return (baseName: safe, extension: 'bin');
    }
    return (
      baseName: safe.substring(0, lastDot),
      extension: safe.substring(lastDot + 1).toLowerCase(),
    );
  }

  /// Ensure [filename] ends with [extension] (without leading dot).
  static String ensureExtension(String filename, String extension) {
    final ext = extension.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
    if (ext.isEmpty) return filename.trim().isEmpty ? 'download' : filename.trim();
    final name = filename.trim().isEmpty ? 'download' : filename.trim();
    if (name.toLowerCase().endsWith('.$ext')) return name;
    return '$name.$ext';
  }

  static String mimeTypeForExtension(String extension, {String? override}) {
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }
    switch (extension.replaceFirst(RegExp(r'^\.'), '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'csv':
        return 'text/csv';
      case 'zip':
        return 'application/zip';
      case 'json':
        return 'application/json';
      case 'txt':
        return 'text/plain';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'sql':
        return 'application/sql';
      case 'gz':
        return 'application/gzip';
      default:
        return 'application/octet-stream';
    }
  }

  /// Prefer `Content-Disposition` filename; otherwise [fallbackBaseName].[fallbackExt].
  static String fromResponse(
    Response<dynamic>? response, {
    required String fallbackBaseName,
    required String fallbackExt,
  }) {
    final header = response?.headers.value('content-disposition');
    if (header != null && header.isNotEmpty) {
      try {
        final parts = header.split(';').map((s) => s.trim());
        for (final p in parts) {
          final lower = p.toLowerCase();
          if (lower.startsWith('filename*=')) {
            // RFC 5987: filename*=UTF-8''encoded
            var value = p.substring(p.indexOf('=') + 1).trim();
            final idx = value.toLowerCase().indexOf("''");
            if (idx >= 0 && idx + 2 < value.length) {
              value = Uri.decodeFull(value.substring(idx + 2));
            }
            value = value.replaceAll('"', '');
            if (value.isNotEmpty) {
              return ensureExtension(value, fallbackExt);
            }
          } else if (lower.startsWith('filename=')) {
            var name = p.substring('filename='.length).trim();
            if (name.startsWith('"') && name.endsWith('"') && name.length >= 2) {
              name = name.substring(1, name.length - 1);
            }
            if (name.isNotEmpty) {
              return ensureExtension(name, fallbackExt);
            }
          }
        }
      } catch (_) {}
    }
    return ensureExtension(fallbackBaseName, fallbackExt);
  }
}
