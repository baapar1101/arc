import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

import 'bytes_export_filename.dart';
import 'bytes_export_impl.dart' as impl;
import 'bytes_export_types.dart';

export 'bytes_export_filename.dart';
export 'bytes_export_types.dart';

/// Single cross-platform entry point for exporting / downloading binary files.
///
/// Use this everywhere instead of `kIsWeb` + `saveBytesAsFileWeb` /
/// `package:file_saver` / local `FileSaver` helpers.
///
/// - **Web**: browser download
/// - **Android / iOS**: native Save-As picker ([BytesExportMode.save]) or share sheet
/// - **Desktop**: Save-As when available, otherwise Downloads folder
class BytesExportService {
  BytesExportService._();

  /// Export [bytes] as [filename].
  ///
  /// [mimeType] is inferred from the extension when omitted.
  static Future<BytesExportResult> export({
    required List<int> bytes,
    required String filename,
    String? mimeType,
    BytesExportMode mode = BytesExportMode.save,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Cannot export empty bytes');
    }
    final safeName = filename.trim().isEmpty ? 'download.bin' : filename.trim();
    final parts = BytesExportFilename.split(safeName);
    final normalized = BytesExportFilename.ensureExtension(safeName, parts.extension);
    final resolvedMime = BytesExportFilename.mimeTypeForExtension(
      parts.extension,
      override: mimeType,
    );
    final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    return impl.exportBytesImpl(
      bytes: u8,
      filename: normalized,
      mimeType: resolvedMime,
      mode: mode,
    );
  }

  /// Convenience: filename from response `Content-Disposition` when present.
  static Future<BytesExportResult> exportResponse({
    required Response<dynamic> response,
    required String fallbackBaseName,
    required String fallbackExt,
    String? mimeType,
    BytesExportMode mode = BytesExportMode.save,
  }) async {
    final data = response.data;
    if (data == null) {
      throw StateError('Empty export response');
    }
    final List<int> bytes;
    if (data is Uint8List) {
      bytes = data;
    } else if (data is List<int>) {
      bytes = data;
    } else {
      throw StateError('Unsupported export response type: ${data.runtimeType}');
    }
    final filename = BytesExportFilename.fromResponse(
      response,
      fallbackBaseName: fallbackBaseName,
      fallbackExt: fallbackExt,
    );
    return export(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType ??
          BytesExportFilename.mimeTypeForExtension(fallbackExt),
      mode: mode,
    );
  }

  /// Shows a localized success snackbar; silent on cancel.
  static void showFeedback(
    BuildContext context,
    BytesExportResult result, {
    String? successOverride,
  }) {
    if (!context.mounted || result.isCancelled) return;
    final t = AppLocalizations.of(context);
    final message = successOverride ?? _defaultMessage(t, result);
    SnackBarHelper.showSuccess(context, message: message);
  }

  static String _defaultMessage(AppLocalizations t, BytesExportResult result) {
    switch (result.outcome) {
      case BytesExportOutcome.downloaded:
        return t.exportDownloadStarted;
      case BytesExportOutcome.saved:
        final path = result.path;
        if (path != null &&
            path.isNotEmpty &&
            !path.startsWith('content:') &&
            path.length < 120 &&
            (path.startsWith('/') || path.contains(r'\'))) {
          return t.exportFileSavedToPath(path);
        }
        return t.exportFileSaved;
      case BytesExportOutcome.shared:
        return t.exportFileShared;
      case BytesExportOutcome.cancelled:
        return t.exportSuccess;
    }
  }
}
