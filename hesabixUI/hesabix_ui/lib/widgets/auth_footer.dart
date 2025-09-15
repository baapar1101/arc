import 'package:flutter/material.dart';

import '../core/locale_controller.dart';
import '../theme/theme_controller.dart';
import 'language_switcher.dart';
import 'theme_mode_switcher.dart';

class AuthFooter extends StatelessWidget {
  final LocaleController localeController;
  final ThemeController? themeController;
  const AuthFooter({super.key, required this.localeController, this.themeController});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (themeController != null) ...[
            ThemeModeSwitcher(controller: themeController!),
            const SizedBox(width: 8),
          ],
          LanguageSwitcher(controller: localeController),
        ],
      ),
    );
  }
}


