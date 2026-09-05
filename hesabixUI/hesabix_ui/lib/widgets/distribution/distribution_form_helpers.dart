import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/person_model.dart';

/// کد ترتیبی مثل T-01، R-02، VAN-03.
String nextDistributionCode(String prefix, Iterable<dynamic> rows) {
  var maxN = 0;
  final re = RegExp('^${RegExp.escape(prefix)}-?(\\d+)\$', caseSensitive: false);
  for (final raw in rows) {
    final code = raw is Map ? '${raw['code'] ?? ''}' : raw.toString();
    final m = re.firstMatch(code.trim());
    if (m != null) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > maxN) maxN = n;
    }
  }
  return '$prefix-${(maxN + 1).toString().padLeft(2, '0')}';
}

Person distributionPersonStub({
  required int businessId,
  required int id,
  required String name,
}) {
  final now = DateTime.now();
  return Person(
    id: id,
    businessId: businessId,
    aliasName: name,
    personTypes: const [PersonType.customer],
    createdAt: now,
    updatedAt: now,
  );
}

String distributionEntityLabel(Map<String, dynamic> row) {
  final name = '${row['name'] ?? ''}'.trim();
  if (name.isNotEmpty) return name;
  final code = '${row['code'] ?? ''}'.trim();
  if (code.isNotEmpty) return code;
  return '#${row['id'] ?? ''}';
}

Widget distributionFormColumn({required List<Widget> children}) {
  return SizedBox(
    width: 420,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    ),
  );
}

Future<bool> confirmDistributionDelete({
  required BuildContext context,
  required String title,
  required String message,
  String? confirmLabel,
}) async {
  final t = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? t.delete),
        ),
      ],
    ),
  );
  return ok == true;
}
