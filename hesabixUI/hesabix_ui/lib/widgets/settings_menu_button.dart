import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'calendar_switcher.dart';
import 'language_switcher.dart';
import 'theme_mode_switcher.dart';
import '../core/locale_controller.dart';
import '../core/calendar_controller.dart';
import '../theme/theme_controller.dart';

class SettingsMenuButton extends StatelessWidget {
  final LocaleController? localeController;
  final CalendarController? calendarController;
  final ThemeController? themeController;

  const SettingsMenuButton({
    super.key,
    this.localeController,
    this.calendarController,
    this.themeController,
  });

  void _showSettingsDialog(BuildContext context) {
    final t = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (calendarController != null) ...[
              Row(
                children: [
                  Text(t.calendar),
                  const Spacer(),
                  CalendarSwitcher(controller: calendarController!),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (localeController != null) ...[
              Row(
                children: [
                  Text(t.language),
                  const Spacer(),
                  LanguageSwitcher(controller: localeController!),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (themeController != null) ...[
              Row(
                children: [
                  Text(t.theme),
                  const Spacer(),
                  ThemeModeSwitcher(controller: themeController!),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return IconButton(
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurface,
        child: const Icon(Icons.settings, size: 18),
      ),
      onPressed: () => _showSettingsDialog(context),
      tooltip: AppLocalizations.of(context).settings,
    );
  }
}
