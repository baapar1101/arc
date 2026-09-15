import 'package:flutter/material.dart';
import 'package:hesabix_ui/config/brand_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../utils/responsive_helper.dart';
import 'new_business_paths_panel.dart';
import 'new_business_shared.dart';

class NewBusinessIntentView extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onCreateManually;
  final VoidCallback onImportBackup;
  final VoidCallback onImportLegacy;
  final bool showLegacyImport;

  const NewBusinessIntentView({
    super.key,
    required this.isLoading,
    required this.onCreateManually,
    required this.onImportBackup,
    required this.onImportLegacy,
    this.showLegacyImport = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isDesktop = ResponsiveHelper.isDesktop(context);
    final isTablet = ResponsiveHelper.isTablet(context);

    return NewBusinessFormShell(
      maxWidth: isDesktop ? 880 : (isTablet ? 640 : null),
      child: NewBusinessPathsPanel(
        isLoading: isLoading,
        onCreateManually: onCreateManually,
        onImportBackup: onImportBackup,
        onImportLegacy: onImportLegacy,
        showLegacyImport: showLegacyImport,
        title: t.newBusinessIntentTitle,
        subtitle: t.branded(t.newBusinessIntentSubtitle),
      ),
    );
  }
}
