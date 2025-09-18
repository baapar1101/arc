import 'package:flutter/material.dart';

import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/locale_controller.dart';
import '../core/calendar_controller.dart';
import '../widgets/language_switcher.dart';
import '../widgets/calendar_switcher.dart';
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
          _ThemeMenu(controller: themeController),
        ],
      ),
      body: Center(child: Text(t.homeWelcome)),
    );
  }
}

class _ThemeMenu extends StatelessWidget {
  final ThemeController controller;
  const _ThemeMenu({required this.controller});
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemeMode>(
      icon: const Icon(Icons.color_lens_outlined),
      initialValue: controller.mode,
      onSelected: (mode) => controller.setMode(mode),
      itemBuilder: (context) => const [
        PopupMenuItem(value: ThemeMode.system, child: Text('System')),
        PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
        PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
      ],
    );
  }
}


