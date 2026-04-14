import 'package:flutter/material.dart';
import 'calendar_switcher.dart';
import 'language_switcher.dart';
import 'theme_mode_switcher.dart';
import 'logout_button.dart';
import '../core/auth_store.dart';
import '../core/locale_controller.dart';
import '../core/calendar_controller.dart';
import '../theme/theme_controller.dart';

class UserMenuButton extends StatelessWidget {
  final AuthStore authStore;
  final LocaleController? localeController;
  final CalendarController? calendarController;
  final ThemeController? themeController;

  const UserMenuButton({
    super.key,
    required this.authStore,
    this.localeController,
    this.calendarController,
    this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (calendarController != null) ...[
          CalendarSwitcher(controller: calendarController!),
          const SizedBox(width: 8),
        ],
        if (localeController != null) ...[
          LanguageSwitcher(controller: localeController!),
          const SizedBox(width: 8),
        ],
        if (themeController != null) ...[
          ThemeModeSwitcher(controller: themeController!),
          const SizedBox(width: 8),
        ],
        LogoutButton(authStore: authStore),
      ],
    );
  }
}