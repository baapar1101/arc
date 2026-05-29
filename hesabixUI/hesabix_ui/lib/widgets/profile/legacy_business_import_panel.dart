import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/profile/legacy_import_wizard.dart';

/// کارت ورود به ویزارد انتقال از نسخه قدیم حسابیکس.
class LegacyBusinessImportPanel extends StatefulWidget {
  final bool isLoading;
  final ValueChanged<bool>? onLoadingChanged;

  const LegacyBusinessImportPanel({
    super.key,
    this.isLoading = false,
    this.onLoadingChanged,
  });

  @override
  State<LegacyBusinessImportPanel> createState() =>
      _LegacyBusinessImportPanelState();
}

class _LegacyBusinessImportPanelState extends State<LegacyBusinessImportPanel> {
  bool _wizardOpen = false;

  Future<void> _openWizard() async {
    if (widget.isLoading || _wizardOpen) return;
    setState(() => _wizardOpen = true);
    widget.onLoadingChanged?.call(true);
    try {
      await LegacyImportWizard.show(context);
    } finally {
      if (mounted) {
        setState(() => _wizardOpen = false);
        widget.onLoadingChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isLoading || _wizardOpen;
    return Stack(
      children: [
        Card(
          elevation: 2,
          child: InkWell(
            onTap: disabled ? null : _openWizard,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_sync,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'انتقال از حسابیکس قبلی',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ویزارد انتقال با پیش‌نمایش، پیشرفت زنده و گزارش نتیجه',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7),
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (_wizardOpen)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_wizardOpen)
          Positioned.fill(
            child: AbsorbPointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
