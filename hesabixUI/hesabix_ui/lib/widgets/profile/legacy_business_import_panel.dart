import 'package:flutter/material.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/profile/legacy_import_wizard.dart';
import 'package:hesabix_ui/widgets/profile/new_business/new_business_shared.dart';

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
    final t = AppLocalizations.of(context);
    final disabled = widget.isLoading || _wizardOpen;

    return Stack(
      children: [
        NewBusinessChoiceCard(
          icon: Icons.cloud_sync_rounded,
          title: t.branded(t.newBusinessImportLegacyTitle),
          subtitle: t.branded(t.newBusinessImportLegacySubtitle),
          onTap: disabled ? null : _openWizard,
        ),
        if (_wizardOpen)
          Positioned.fill(
            child: AbsorbPointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
