import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.support, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${t.support} - sample page'),
        ],
      ),
    );
  }
}


