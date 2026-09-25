import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../models/ai_stream_event.dart';
import 'ai_chat_l10n.dart';

class AIActivatedSkill {
  final String slug;
  final String? description;

  const AIActivatedSkill({required this.slug, this.description});

  factory AIActivatedSkill.fromJson(Map<String, dynamic> json) {
    return AIActivatedSkill(
      slug: (json['slug'] ?? json['skill_slug'] ?? '').toString(),
      description: json['description']?.toString(),
    );
  }
}

List<AIActivatedSkill> extractActivatedSkillsFromResults(Object? functionResults) {
  if (functionResults is! Map) return const [];
  final raw = functionResults[kActivatedSkillsStorageKey];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => AIActivatedSkill.fromJson(Map<String, dynamic>.from(e)))
      .where((s) => s.slug.isNotEmpty)
      .toList();
}

/// chip مهارت‌هایی که برای این پاسخ فعال شدند (SKL-01).
class AIActivatedSkillChips extends StatelessWidget {
  final Object? functionResults;

  const AIActivatedSkillChips({super.key, this.functionResults});

  @override
  Widget build(BuildContext context) {
    final skills = extractActivatedSkillsFromResults(functionResults);
    if (skills.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            aiActivatedSkillsLabel(l10n),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final skill in skills.take(3))
            Tooltip(
              message: skill.description ?? skill.slug,
              child: Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.auto_awesome, size: 14),
                label: Text(skill.slug, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
      ),
    );
  }
}
