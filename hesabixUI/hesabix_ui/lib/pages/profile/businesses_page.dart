import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class BusinessesPage extends StatelessWidget {
  const BusinessesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.businesses, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${t.businesses} - sample page'),
        ],
      ),
    );
  }
}


