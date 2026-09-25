import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/crm_service.dart';

/// انتخاب چند برچسب برای سرنخ/فرصت فروش. برچسب‌ها از سرور بارگذاری می‌شوند.
class CrmTagSelector extends StatefulWidget {
  final int businessId;
  final CrmService crmService;
  final List<int> initialTagIds;
  final ValueChanged<List<int>> onChanged;

  const CrmTagSelector({
    super.key,
    required this.businessId,
    required this.crmService,
    required this.initialTagIds,
    required this.onChanged,
  });

  @override
  State<CrmTagSelector> createState() => _CrmTagSelectorState();
}

class _CrmTagSelectorState extends State<CrmTagSelector> {
  List<Map<String, dynamic>> _tags = [];
  late Set<int> _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTagIds.toSet();
    _load();
  }

  Future<void> _load() async {
    try {
      final tags = await widget.crmService.listTags(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _tags = tags;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color? _colorFor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_tags.isEmpty) {
      return Text('برچسبی تعریف نشده است.', style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _tags.map((t) {
        final id = (t['id'] as num?)?.toInt();
        if (id == null) return const SizedBox.shrink();
        final selected = _selected.contains(id);
        final col = _colorFor(t['color']?.toString());
        return FilterChip(
          label: Text(t['name']?.toString() ?? ''),
          selected: selected,
          showCheckmark: true,
          backgroundColor: col?.withValues(alpha: 0.12),
          selectedColor: (col ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.25),
          side: col != null ? BorderSide(color: col.withValues(alpha: 0.5)) : null,
          onSelected: (v) {
            setState(() {
              if (v) {
                _selected.add(id);
              } else {
                _selected.remove(id);
              }
            });
            widget.onChanged(_selected.toList());
          },
        );
      }).toList(),
    );
  }
}
