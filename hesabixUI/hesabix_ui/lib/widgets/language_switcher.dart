import 'package:flutter/material.dart';

import '../core/locale_controller.dart';

class LanguageSwitcher extends StatelessWidget {
  final LocaleController controller;
  const LanguageSwitcher({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool isFa = controller.locale.languageCode == 'fa';
    final String label = isFa ? 'فا' : 'EN';

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
        radius: 14,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}


