import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/ai_models.dart';

import 'ai_chat_design.dart';

/// انتخاب فشردهٔ مدل AI — داخل composer یا toolbar.
class AIChatModelChip extends StatelessWidget {
  final List<AIModelCatalogItem> models;
  final String? selectedCode;
  final bool loading;
  final bool enabled;
  final ValueChanged<String?>? onChanged;
  final String? pricingHint;

  const AIChatModelChip({
    super.key,
    required this.models,
    required this.selectedCode,
    this.loading = false,
    this.enabled = true,
    this.onChanged,
    this.pricingHint,
  });

  String _label(AIModelCatalogItem m) {
    final hint = m.pricingHint;
    if (hint != null && hint.isNotEmpty) return '${m.displayName} · $hint';
    return m.displayName;
  }

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopupMenuButton<String>(
      tooltip: 'انتخاب مدل هوش مصنوعی',
      enabled: enabled && !loading && onChanged != null,
      onSelected: onChanged,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: AIChatDesign.chipDecoration(theme),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              )
            else
              Icon(Icons.hub_outlined, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _currentLabel(),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
      itemBuilder: (context) => [
        for (final m in models)
          PopupMenuItem(
            value: m.code,
            child: Text(
              _label(m),
              style: TextStyle(
                fontWeight: m.code == selectedCode ? FontWeight.w700 : null,
              ),
            ),
          ),
        if (pricingHint != null && pricingHint!.isNotEmpty)
          PopupMenuItem(
            enabled: false,
            child: Text(
              pricingHint!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  String _currentLabel() {
    for (final m in models) {
      if (m.code == selectedCode) return m.displayName;
    }
    return 'مدل';
  }
}
