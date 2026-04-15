import 'package:flutter/material.dart';

/// کارت یکدست برای گروه‌بندی فیلدهای فرم‌های CRM.
class CrmSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const CrmSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
