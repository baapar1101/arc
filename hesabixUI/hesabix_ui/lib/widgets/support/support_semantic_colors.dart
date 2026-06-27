import 'package:flutter/material.dart';

/// Theme-aware semantic colors for support / ticketing UI.
class SupportSemanticColors {
  final Color slaOk;
  final Color slaWarning;
  final Color slaBreached;
  final Color internalNoteBg;
  final Color internalNoteBorder;
  final Color internalNoteFg;
  final Color pinnedRequestBg;
  final Color pinnedRequestBorder;
  final Color composerBg;
  final Color composerBorder;
  final Color agentBubbleBg;
  final Color customerBubbleBg;
  final Color selectedRowBg;

  const SupportSemanticColors({
    required this.slaOk,
    required this.slaWarning,
    required this.slaBreached,
    required this.internalNoteBg,
    required this.internalNoteBorder,
    required this.internalNoteFg,
    required this.pinnedRequestBg,
    required this.pinnedRequestBorder,
    required this.composerBg,
    required this.composerBorder,
    required this.agentBubbleBg,
    required this.customerBubbleBg,
    required this.selectedRowBg,
  });

  factory SupportSemanticColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SupportSemanticColors(
      slaOk: Colors.green.shade600,
      slaWarning: Colors.orange.shade700,
      slaBreached: scheme.error,
      internalNoteBg: isDark ? const Color(0xFF3D3200) : const Color(0xFFFFF8E1),
      internalNoteBorder: isDark ? Colors.amber.shade700 : Colors.amber.shade300,
      internalNoteFg: isDark ? Colors.amber.shade100 : Colors.amber.shade900,
      pinnedRequestBg: scheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.5 : 0.65),
      pinnedRequestBorder: scheme.outlineVariant,
      composerBg: scheme.surfaceContainerLow,
      composerBorder: scheme.outlineVariant,
      agentBubbleBg: isDark ? scheme.primaryContainer : scheme.primaryContainer.withValues(alpha: 0.35),
      customerBubbleBg: scheme.surfaceContainerHighest,
      selectedRowBg: scheme.primaryContainer.withValues(alpha: isDark ? 0.45 : 0.55),
    );
  }

  Color slaColorFor(String status) => switch (status) {
        'breached' => slaBreached,
        'warning' => slaWarning,
        _ => slaOk,
      };
}
