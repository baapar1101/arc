import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// فرم کاربرپسند پارامترهای گزارش بر اساس schema سرور.
class HScriptParamsForm extends StatelessWidget {
  const HScriptParamsForm({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;

  void _set(String name, dynamic value) {
    final next = Map<String, dynamic>.from(values);
    if (value == null || (value is String && value.trim().isEmpty)) {
      next.remove(name);
    } else {
      next[name] = value;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          'پارامتری تعریف نشده. با `# @param name type "برچسب"` در ابتدای اسکریپت پارامتر بسازید.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: fields.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final field = fields[index];
        final name = field['name']?.toString() ?? '';
        final label = field['label']?.toString() ?? name;
        final type = field['type']?.toString() ?? 'string';
        final required = field['required'] == true;
        final current = values.containsKey(name) ? values[name] : field['value'] ?? field['default'];

        final title = required ? '$label *' : label;

        switch (type) {
          case 'boolean':
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              value: current == true,
              onChanged: (v) => _set(name, v),
            );
          case 'select':
            final options = (field['options'] is List)
                ? (field['options'] as List).map((e) => e.toString()).toList()
                : <String>[];
            final currentStr = current?.toString();
            return InputDecorator(
              decoration: InputDecoration(
                labelText: title,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: (currentStr != null && options.contains(currentStr)) ? currentStr : null,
                  hint: const Text('انتخاب…'),
                  items: [
                    for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
                  ],
                  onChanged: (v) => _set(name, v),
                ),
              ),
            );
          case 'integer':
          case 'number':
            return TextFormField(
              key: ValueKey('num-$name-$current'),
              initialValue: current?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: InputDecoration(
                labelText: title,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (raw) {
                final t = raw.trim();
                if (t.isEmpty) {
                  _set(name, null);
                  return;
                }
                if (type == 'integer') {
                  _set(name, int.tryParse(t) ?? t);
                } else {
                  _set(name, double.tryParse(t) ?? t);
                }
              },
            );
          case 'date':
            return _DateParamField(
              key: ValueKey('date-$name-$current'),
              label: title,
              value: current?.toString(),
              onChanged: (v) => _set(name, v),
            );
          case 'text':
            return TextFormField(
              key: ValueKey('text-$name-$current'),
              initialValue: current?.toString() ?? '',
              maxLines: 3,
              decoration: InputDecoration(
                labelText: title,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (v) => _set(name, v),
            );
          default:
            return TextFormField(
              key: ValueKey('str-$name-$current'),
              initialValue: current?.toString() ?? '',
              decoration: InputDecoration(
                labelText: title,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _set(name, v),
            );
        }
      },
    );
  }
}

class _DateParamField extends StatelessWidget {
  const _DateParamField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    DateTime initial = now;
    if (value != null && value!.isNotEmpty) {
      try {
        initial = DateTime.parse(value!);
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    onChanged(iso);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'پاک کردن',
            onPressed: value == null || value!.isEmpty ? null : () => onChanged(null),
            icon: const Icon(Icons.clear, size: 18),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.event, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(value?.isNotEmpty == true ? value! : 'انتخاب تاریخ')),
          ],
        ),
      ),
    );
  }
}
