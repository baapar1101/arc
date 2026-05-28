import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_models.dart';
/// bottom sheet ناوبری پیام‌ها (موبایل / عرض کم).
Future<void> showAIConversationNavSheet({
  required BuildContext context,
  required List<AIChatMessage> messages,
  required List<GlobalKey> messageKeys,
  required int activeIndex,
  required void Function(int index) onJumpToIndex,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: scheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.62;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.forum_outlined, color: scheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.aiConversationNavTitle(messages.length),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isUser = msg.role == MessageRole.user;
                  final isActive = index == activeIndex;
                  final preview = _messagePreview(msg.content);
                  final hasError = msg.content.contains('خطا در دریافت');

                  final accent = hasError
                      ? scheme.error
                      : isUser
                          ? scheme.secondary
                          : scheme.primary;

                  return Material(
                    color: isActive
                        ? accent.withValues(alpha: 0.12)
                        : scheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(ctx);
                        onJumpToIndex(index);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? accent
                                    : accent.withValues(alpha: 0.5),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              isUser
                                  ? Icons.person_outline
                                  : Icons.smart_toy_outlined,
                              size: 20,
                              color: accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isUser
                                        ? l10n.aiConversationNavUser
                                        : l10n.aiConversationNavAssistant,
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    preview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isActive)
                              Icon(
                                Icons.my_location,
                                size: 18,
                                color: accent,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _messagePreview(String content) {
  final t = content.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '…';
  if (t.length <= 72) return t;
  return '${t.substring(0, 72)}…';
}

/// دکمهٔ شناور باز کردن فهرست پیام‌ها (موبایل).
class AIConversationNavFab extends StatelessWidget {
  final int messageCount;
  final int activeIndex;
  final VoidCallback onTap;

  const AIConversationNavFab({
    super.key,
    required this.messageCount,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Positioned(
      top: 8,
      right: isRtl ? 10 : null,
      left: isRtl ? null : 10,
      child: Material(
        elevation: 2,
        shadowColor: scheme.shadow.withValues(alpha: 0.2),
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.linear_scale, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '${activeIndex + 1}/$messageCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
