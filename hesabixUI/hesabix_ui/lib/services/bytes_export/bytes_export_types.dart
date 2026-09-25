/// How the bytes should be delivered to the user.
enum BytesExportMode {
  /// Web: browser download. Mobile: native Save-As picker.
  /// Desktop: Save-As when available, otherwise Downloads folder.
  save,

  /// Web: browser download. Mobile/desktop: system share sheet when available,
  /// otherwise falls back to [save].
  share,
}

/// Outcome of a [BytesExportService.export] call.
enum BytesExportOutcome {
  /// Browser download started (web).
  downloaded,

  /// User saved via Save-As / Downloads path.
  saved,

  /// User opened the share sheet.
  shared,

  /// User dismissed Save-As / share without completing.
  cancelled,
}

class BytesExportResult {
  const BytesExportResult({
    required this.outcome,
    required this.filename,
    this.path,
  });

  final BytesExportOutcome outcome;
  final String filename;

  /// Local filesystem path when available (mobile/desktop save).
  final String? path;

  bool get isSuccess =>
      outcome == BytesExportOutcome.downloaded ||
      outcome == BytesExportOutcome.saved ||
      outcome == BytesExportOutcome.shared;

  bool get isCancelled => outcome == BytesExportOutcome.cancelled;
}
