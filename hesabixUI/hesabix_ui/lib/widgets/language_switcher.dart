import 'package:flutter/material.dart';

import '../core/locale_controller.dart';

class LanguageSwitcher extends StatelessWidget {
  final LocaleController controller;
  /// وقتی در نوار [AppBar] فشرده استفاده می‌شود (هم‌عرض CombinedUserMenuButton.denseToolbar).
  final bool toolbarCompact;
  const LanguageSwitcher({super.key, required this.controller, this.toolbarCompact = false});

  @override
  Widget build(BuildContext context) {
    final bool isFa = controller.locale.languageCode == 'fa';
    final String label = isFa ? 'فا' : 'EN';
    final double r = toolbarCompact ? 12 : 14;
    final double fz = toolbarCompact ? 11 : 12;

    return PopupMenuButton<Locale>(
      tooltip: 'Language',
      itemBuilder: (context) => <PopupMenuEntry<Locale>>[
        PopupMenuItem(
          value: const Locale('fa','IR'),
          child: const Text('فارسی'),
        ),
        PopupMenuItem(
          value: const Locale('en','US'),
          child: const Text('English'),
        ),
      ],
      onSelected: (loc) => controller.setLocale(loc),
      child: CircleAvatar(
        radius: r,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Text(label, style: TextStyle(fontSize: fz, fontWeight: FontWeight.w600)),
      ),
    );
  }
}


