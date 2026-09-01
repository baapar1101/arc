import 'package:flutter/material.dart';

import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/locale_controller.dart';
import '../core/calendar_controller.dart';
import '../widgets/language_switcher.dart';
import '../widgets/calendar_switcher.dart';
import '../widgets/theme_mode_switcher.dart';
import '../widgets/theme_palette_switcher.dart';
import '../theme/theme_controller.dart';

class HomePage extends StatelessWidget {
  final LocaleController localeController;
  final CalendarController calendarController;
  final ThemeController themeController;
  const HomePage({super.key, required this.localeController, required this.calendarController, required this.themeController});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.appTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: CalendarSwitcher(controller: calendarController),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: LanguageSwitcher(controller: localeController),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ThemePaletteSwitcher(controller: themeController),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ThemeModeSwitcher(controller: themeController),
          ),
        ],
      ),
      body: Center(child: Text(t.homeWelcome)),
    );
  }
}
