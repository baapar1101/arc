import 'package:hesabix_ui/theme/glass.dart';
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
  final ok = await showGlassDialog<bool>(
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

/// انتخاب کالا از لیست محدود (مثل موجودی ون) بدون DropdownButton تا کلیک موس در دیالوگ کار کند.
Future<T?> showDistributionChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T item) labelOf,
  bool Function(T item)? enabledOf,
  bool Function(T item)? selectedOf,
}) async {
  final t = AppLocalizations.of(context);
  return showGlassDialog<T>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          height: items.isEmpty ? 120 : 360,
          child: items.isEmpty
              ? Center(child: Text(t.distributionSelectProduct))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final enabled = enabledOf?.call(item) ?? true;
                    final selected = selectedOf?.call(item) ?? false;
                    return ListTile(
                      enabled: enabled,
                      selected: selected,
                      title: Text(labelOf(item), maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: enabled ? () => Navigator.pop(ctx, item) : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
        ],
      );
    },
  );
}

/// فیلد انتخاب از لیست محدود؛ به‌جای DropdownButtonFormField در شیت/دیالوگ پخش مویرگی.
class DistributionChoiceField<T> extends StatelessWidget {
  const DistributionChoiceField({
    super.key,
    required this.label,
    required this.items,
    required this.labelOf,
    required this.onSelected,
    this.selectedLabel,
    this.enabledOf,
    this.selectedOf,
    this.emptyText,
  });

  final String label;
  final List<T> items;
  final String Function(T item) labelOf;
  final ValueChanged<T> onSelected;
  final String? selectedLabel;
  final bool Function(T item)? enabledOf;
  final bool Function(T item)? selectedOf;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return InkWell(
      onTap: items.isEmpty
          ? null
          : () async {
              final picked = await showDistributionChoiceDialog<T>(
                context: context,
                title: label,
                items: items,
                labelOf: labelOf,
                enabledOf: enabledOf,
                selectedOf: selectedOf,
              );
              if (picked != null) onSelected(picked);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          items.isEmpty ? (emptyText ?? t.distributionSelectProduct) : (selectedLabel ?? t.distributionSelectProduct),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
