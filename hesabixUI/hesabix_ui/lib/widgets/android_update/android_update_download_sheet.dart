import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../services/android_update/android_apk_download_coordinator.dart';
import '../../services/android_update/android_update_models.dart';

enum AndroidUpdateDownloadSheetResult {
  completed,
  background,
  cancelled,
  failed,
}

String formatAndroidUpdateBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Polished download experience with optional background continuation.
Future<AndroidUpdateDownloadSheetResult> showAndroidUpdateDownloadSheet({
  required BuildContext context,
  required AndroidRemoteRelease release,
  required Future<String> Function({
    void Function(AndroidUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) startDownload,
}) {
  return showModalBottomSheet<AndroidUpdateDownloadSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => _AndroidUpdateDownloadSheet(
      release: release,
      startDownload: startDownload,
    ),
  ).then((value) => value ?? AndroidUpdateDownloadSheetResult.cancelled);
}

class _AndroidUpdateDownloadSheet extends StatefulWidget {
  const _AndroidUpdateDownloadSheet({
    required this.release,
    required this.startDownload,
  });

  final AndroidRemoteRelease release;
  final Future<String> Function({
    void Function(AndroidUpdateDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) startDownload;

  @override
  State<_AndroidUpdateDownloadSheet> createState() =>
      _AndroidUpdateDownloadSheetState();
}

class _AndroidUpdateDownloadSheetState extends State<_AndroidUpdateDownloadSheet> {
  AndroidUpdateDownloadProgress? _progress;
  var _cancelled = false;
  var _backgroundRequested = false;
  var _started = false;
  var _failedMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginDownload());
  }

  Future<void> _beginDownload() async {
    if (_started) return;
    _started = true;

    try {
      final path = await widget.startDownload(
        onProgress: (progress) {
          if (!mounted || _cancelled) return;
          setState(() => _progress = progress);
        },
        isCancelled: () => _cancelled,
      );

      if (!mounted) return;
      if (_backgroundRequested) {
        Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.background);
        return;
      }

      Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.completed);
      // Path is handled by caller via coordinator; keep for analyzer.
      assert(path.isNotEmpty);
    } on AndroidUpdateCancelledException {
      if (!mounted) return;
      if (_backgroundRequested) {
        Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.background);
        return;
      }
      Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.cancelled);
    } catch (e) {
      if (!mounted) return;
      if (_backgroundRequested) {
        Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.background);
        return;
      }
      setState(() => _failedMessage = e.toString());
      Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.failed);
    }
  }

  Future<void> _onCancel() async {
    setState(() => _cancelled = true);
    await AndroidApkDownloadCoordinator.instance.cancelDownload();
    if (!mounted) return;
    Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.cancelled);
  }

  void _onContinueInBackground() {
    setState(() => _backgroundRequested = true);
    Navigator.of(context).pop(AndroidUpdateDownloadSheetResult.background);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final progress = _progress;
    final fraction = progress?.fraction;
    final percent = progress?.percent ?? 0;
    final totalBytes = widget.release.apk.size;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.secondaryContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(
              Icons.system_update_alt_rounded,
              size: 36,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t.androidUpdateDownloadingSheetTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              widget.release.version.toString(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      progress == null ? '—' : '$percent%',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (progress != null && totalBytes > 0)
                      Text(
                        '${formatAndroidUpdateBytes(progress.received)} / ${formatAndroidUpdateBytes(totalBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.androidUpdateDownloadingBackgroundHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_failedMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _failedMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _onContinueInBackground,
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(t.androidUpdateContinueInBackground),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _onCancel,
            child: Text(t.cancel),
          ),
        ],
      ),
    );
  }
}
