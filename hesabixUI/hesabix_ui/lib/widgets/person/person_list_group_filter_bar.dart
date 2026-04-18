import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../models/person_group_model.dart';

/// نوار فیلتر گروه بالای لیست اشخاص — هم‌سبک فیلتر دسته در لیست کالاها؛ پیش‌فرض «همه» بدون اعمال فیلتر.
class PersonListGroupFilterBar extends StatelessWidget {
  final List<PersonGroup> groups;
  final bool loading;
  final int? selectedGroupId;
  final ValueChanged<int?> onGroupChanged;

  const PersonListGroupFilterBar({
    super.key,
    required this.groups,
    required this.loading,
    required this.selectedGroupId,
    required this.onGroupChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    if (!loading && groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.65),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(minHeight: 3),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.group_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  t.personGroup,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: false,
                    thickness: 4,
                    radius: const Radius.circular(4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      primary: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: FilterChip(
                              label: Text(t.all),
                              selected: selectedGroupId == null,
                              onSelected: (_) => onGroupChanged(null),
                              showCheckmark: false,
                              avatar: Icon(
                                Icons.layers_outlined,
                                size: 18,
                                color: selectedGroupId == null
                                    ? theme.colorScheme.onSecondaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final g in groups)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: FilterChip(
                                label: Text(
                                  g.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                selected: selectedGroupId == g.id,
                                onSelected: (_) => onGroupChanged(g.id),
                                showCheckmark: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
