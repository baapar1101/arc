import 'package:flutter/material.dart';

class ReportTemplateStudioGallery extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String? selectedFamilyId;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const ReportTemplateStudioGallery({
    super.key,
    required this.items,
    required this.selectedFamilyId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('قالبی برای این کاربرد یافت نشد.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final id = (item['id'] ?? '').toString();
        final selected = id == selectedFamilyId;
        final accent = _parseColor((item['preview_accent'] ?? '#366092').toString());
        final tags = ((item['tags'] as List?) ?? const []).map((e) => e.toString()).toList();
        return Material(
          elevation: selected ? 4 : 1,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(item),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? accent : Theme.of(context).dividerColor,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 96,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 12,
                          right: 12,
                          left: 12,
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 30,
                          right: 12,
                          left: 12,
                          child: Column(
                            children: List.generate(
                              3,
                              (i) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (selected)
                          const Positioned(
                            top: 8,
                            left: 8,
                            child: Icon(Icons.check_circle, color: Colors.green, size: 22),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['label_fa'] ?? id).toString(),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Text(
                              (item['description_fa'] ?? '').toString(),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (tags.isNotEmpty)
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: tags
                                  .map(
                                    (t) => Chip(
                                      label: Text(t, style: const TextStyle(fontSize: 11)),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _parseColor(String raw) {
    final s = raw.trim();
    if (s.startsWith('#') && (s.length == 7 || s.length == 4)) {
      try {
        if (s.length == 7) {
          return Color(int.parse(s.substring(1), radix: 16) + 0xFF000000);
        }
        final r = s[1];
        final g = s[2];
        final b = s[3];
        return Color(int.parse('$r$r$g$g$b$b', radix: 16) + 0xFF000000);
      } catch (_) {}
    }
    return const Color(0xFF366092);
  }
}
