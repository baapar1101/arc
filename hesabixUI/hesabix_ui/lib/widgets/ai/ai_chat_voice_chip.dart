import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_voice_models.dart';

/// انتخاب فشردهٔ موتور STT یا صدای TTS داخل composer.
class AIChatVoicePickChip extends StatelessWidget {
  final String kind;
  final List<AIVoiceModelItem> items;
  final String? selectedCode;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final bool compact;

  const AIChatVoicePickChip({
    super.key,
    required this.kind,
    required this.items,
    required this.selectedCode,
    this.enabled = true,
    this.onChanged,
    this.compact = true,
  });

  bool get _isStt => kind == 'stt';

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tooltip = _isStt ? l10n.aiVoicePickStt : l10n.aiVoicePickTts;

    return PopupMenuButton<String>(
      tooltip: tooltip,
      enabled: enabled && onChanged != null && items.length > 1,
      onSelected: onChanged,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 4 : 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isStt ? Icons.graphic_eq_rounded : Icons.record_voice_over_outlined,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _currentLabel(),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (items.length > 1)
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem(
            value: item.code,
            child: Row(
              children: [
                if (item.isCloud)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Icon(
                      Icons.cloud_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ),
                Expanded(
                  child: Text(
                    item.displayName,
                    style: TextStyle(
                      fontWeight:
                          item.code == selectedCode ? FontWeight.w700 : null,
                    ),
                  ),
                ),
                if (item.dummy)
                  Text(
                    'dummy',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _currentLabel() {
    for (final item in items) {
      if (item.code == selectedCode) return item.displayName;
    }
    return items.first.displayName;
  }
}
