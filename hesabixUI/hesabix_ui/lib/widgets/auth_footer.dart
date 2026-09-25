import 'package:flutter/material.dart';

import '../core/locale_controller.dart';
import '../core/calendar_controller.dart';
import '../theme/theme_controller.dart';
import 'language_switcher.dart';
import 'calendar_switcher.dart';
import 'theme_mode_switcher.dart';

class AuthFooter extends StatelessWidget {
  final LocaleController localeController;
  final CalendarController calendarController;
  final ThemeController? themeController;
  const AuthFooter({super.key, required this.localeController, required this.calendarController, this.themeController});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CalendarSwitcher(controller: calendarController),
          const SizedBox(width: 4),
          if (themeController != null) ...[
            ThemeModeSwitcher(controller: themeController!),
            const SizedBox(width: 4),
          ],
          LanguageSwitcher(controller: localeController),
        ],
      ),
    );
  }
}


