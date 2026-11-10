import 'package:flutter/material.dart';

class CrmSavedViewBar extends StatelessWidget {
  const CrmSavedViewBar({
    super.key,
    required this.views,
    required this.canSave,
    required this.onSave,
    required this.onApply,
    required this.onDelete,
    this.activeId,
  });

  final List<Map<String, dynamic>> views;
  final int? activeId;
  final bool canSave;
  final VoidCallback onSave;
  final ValueChanged<Map<String, dynamic>> onApply;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (canSave)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ActionChip(
                avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('ذخیره نما'),
                onPressed: onSave,
              ),
            ),
          for (final view in views)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: InputChip(
                label: Text(view['name']?.toString() ?? ''),
                avatar: Icon(
                  view['is_shared'] == true ? Icons.group_outlined : Icons.bookmark_outline,
                  size: 18,
                ),
                selected: activeId != null && activeId == (view['id'] as num?)?.toInt(),
                selectedColor: cs.secondaryContainer,
                onSelected: (_) => onApply(view),
                onDeleted: view['is_owner'] == true ? () => onDelete((view['id'] as num).toInt()) : null,
                deleteIcon: const Icon(Icons.close, size: 16),
                tooltip: view['is_shared'] == true ? 'نما مشترک' : 'نمای شخصی',
              ),
            ),
        ],
      ),
    );
  }
}
