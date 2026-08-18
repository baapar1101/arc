import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/utils/hscript_code_extract.dart';

/// کدام ردیف‌های شیت اقدامات برای این پیام دیده می‌شوند (UX-01).
class AIChatMessageSheetFlags {
  final bool applyHScript;
  final bool userEdit;
  final bool assistantEdit;
  final bool fork;
  final bool assistantFeedback;
  final bool readAloud;

  const AIChatMessageSheetFlags({
    required this.applyHScript,
    required this.userEdit,
    required this.assistantEdit,
    required this.fork,
    required this.assistantFeedback,
    required this.readAloud,
  });

  factory AIChatMessageSheetFlags.fromMessage(
    AIChatMessage message, {
    required bool canApplyHScript,
  }) {
    final isUser = message.role == MessageRole.user;
    final isAssistant = message.role == MessageRole.assistant;
    return AIChatMessageSheetFlags(
      applyHScript:
          canApplyHScript && HScriptCodeExtract.extract(message.content) != null,
      userEdit: isUser,
      assistantEdit: isAssistant,
      fork: message.id != null,
      assistantFeedback: isAssistant && message.id != null,
      readAloud: isAssistant && message.content.trim().isNotEmpty,
    );
  }
}

Future<void> showAIChatMessageActionSheet({
  required BuildContext context,
  required AIChatMessage message,
  required bool canApplyHScript,
  required VoidCallback onCopy,
  required VoidCallback onShare,
  VoidCallback? onApplyHScript,
  VoidCallback? onEditUserResend,
  VoidCallback? onEditAssistantText,
  VoidCallback? onEditAssistantRegenerate,
  VoidCallback? onFork,
  VoidCallback? onFeedbackUp,
  VoidCallback? onFeedbackDown,
  VoidCallback? onRegenerate,
  VoidCallback? onSpeak,
}) {
  final flags = AIChatMessageSheetFlags.fromMessage(
    message,
    canApplyHScript: canApplyHScript,
  );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      void closeThen(VoidCallback action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(l10n.aiActionCopy),
                onTap: () => closeThen(onCopy),
              ),
              if (flags.applyHScript && onApplyHScript != null)
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: Text(l10n.aiActionApplyHScript),
                  onTap: () => closeThen(onApplyHScript),
                ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(l10n.aiActionShare),
                onTap: () => closeThen(onShare),
              ),
              if (flags.readAloud && onSpeak != null)
                ListTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: Text(l10n.aiVoiceReadAloud),
                  onTap: () => closeThen(onSpeak),
                ),
              if (flags.userEdit && onEditUserResend != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.aiActionEditResend),
                  onTap: () => closeThen(onEditUserResend),
                ),
              if (flags.assistantEdit) ...[
                if (onEditAssistantText != null)
                  ListTile(
                    leading: const Icon(Icons.edit_note_outlined),
                    title: Text(l10n.aiActionEditAssistantText),
                    onTap: () => closeThen(onEditAssistantText),
                  ),
                if (onEditAssistantRegenerate != null)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: Text(l10n.aiActionEditAndRegenerate),
                    onTap: () => closeThen(onEditAssistantRegenerate),
                  ),
              ],
              if (flags.fork && onFork != null)
                ListTile(
                  leading: const Icon(Icons.call_split_rounded),
                  title: Text(l10n.aiActionFork),
                  onTap: () => closeThen(onFork),
                ),
              if (flags.assistantFeedback) ...[
                if (onFeedbackUp != null)
                  ListTile(
                    leading: const Icon(Icons.thumb_up_outlined),
                    title: Text(l10n.aiActionThumbsUp),
                    onTap: () => closeThen(onFeedbackUp),
                  ),
                if (onFeedbackDown != null)
                  ListTile(
                    leading: const Icon(Icons.thumb_down_outlined),
                    title: Text(l10n.aiActionThumbsDown),
                    onTap: () => closeThen(onFeedbackDown),
                  ),
                if (onRegenerate != null)
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: Text(l10n.aiActionRegenerate),
                    onTap: () => closeThen(onRegenerate),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
