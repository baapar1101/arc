import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class ThemeModeSwitcher extends StatelessWidget {
  final ThemeController controller;
  const ThemeModeSwitcher({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final icon = switch (controller.mode) {
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.light => Icons.light_mode,
      _ => Icons.brightness_auto,
    };

    return PopupMenuButton<ThemeMode>(
      tooltip: t.theme,
      itemBuilder: (context) => <PopupMenuEntry<ThemeMode>>[
        PopupMenuItem(value: ThemeMode.system, child: Text(t.system)),
        PopupMenuItem(value: ThemeMode.light, child: Text(t.light)),
        PopupMenuItem(value: ThemeMode.dark, child: Text(t.dark)),
      ],
      onSelected: (mode) => controller.setMode(mode),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Icon(icon, size: 16),
      ),
    );
  }
}


