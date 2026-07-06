import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/response_template.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';
import 'package:hesabix_ui/widgets/support/ticket_attachment_picker.dart';
import 'package:hesabix_ui/models/support_models.dart';

enum TicketComposeMode { publicReply, internalNote }

/// Reply / internal-note composer with tab switching.
class TicketComposer extends StatelessWidget {
  final TextEditingController messageController;
  final bool isOperator;
  final bool canCompose;
  final bool isSending;
  final bool isUploadingAttachment;
  final TicketComposeMode mode;
  final List<SupportAttachment> pendingAttachments;
  final List<ResponseTemplate> templates;
  final ValueChanged<TicketComposeMode> onModeChanged;
  final VoidCallback onSend;
  final VoidCallback onPickAttachment;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback? onShowTemplates;
  final void Function(ResponseTemplate template)? onApplyTemplate;
  final bool compact;

  const TicketComposer({
    super.key,
    required this.messageController,
    required this.isOperator,
    required this.canCompose,
    required this.isSending,
    required this.isUploadingAttachment,
    required this.mode,
    required this.pendingAttachments,
    required this.templates,
    required this.onModeChanged,
    required this.onSend,
    required this.onPickAttachment,
    required this.onRemoveAttachment,
    this.onShowTemplates,
    this.onApplyTemplate,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!canCompose) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = SupportSemanticColors.of(context);
    final isInternal = mode == TicketComposeMode.internalNote;

    return Container(
      decoration: BoxDecoration(
        color: isInternal ? colors.internalNoteBg : colors.composerBg,
        border: Border(top: BorderSide(color: colors.composerBorder)),
      ),
      padding: EdgeInsets.fromLTRB(compact ? 8 : 12, compact ? 6 : 8, compact ? 8 : 12, compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isOperator)
            SegmentedButton<TicketComposeMode>(
              segments: [
                ButtonSegment(
                  value: TicketComposeMode.publicReply,
                  icon: Icon(Icons.reply_outlined, size: compact ? 16 : 18),
                  label: compact ? const SizedBox.shrink() : const Text('پاسخ عمومی'),
                ),
                ButtonSegment(
                  value: TicketComposeMode.internalNote,
                  icon: Icon(Icons.lock_outline, size: compact ? 16 : 18),
                  label: compact ? const SizedBox.shrink() : const Text('یادداشت داخلی'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onModeChanged(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          if (isInternal && !compact)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                'فقط اپراتورها می‌بینند — مشتری این پیام را دریافت نمی‌کند.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.internalNoteFg),
              ),
            ),
          if (isOperator && templates.isNotEmpty && !compact) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...templates.take(5).map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ActionChip(
                            label: Text(t.name, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            onPressed: onApplyTemplate == null ? null : () => onApplyTemplate!(t),
                          ),
                        ),
                      ),
                  if (onShowTemplates != null)
                    IconButton(
                      icon: const Icon(Icons.more_horiz, size: 20),
                      tooltip: 'همه قالب‌ها',
                      onPressed: onShowTemplates,
                    ),
                ],
              ),
            ),
          ],
          TicketAttachmentPicker(
            pendingAttachments: pendingAttachments,
            isUploading: isUploadingAttachment,
            onPick: onPickAttachment,
            onRemove: onRemoveAttachment,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isOperator && onShowTemplates != null)
                IconButton(
                  icon: const Icon(Icons.description_outlined),
                  tooltip: 'قالب‌های پاسخ',
                  onPressed: onShowTemplates,
                ),
              Expanded(
                child: TextField(
                  controller: messageController,
                  decoration: InputDecoration(
                    hintText: isInternal
                        ? 'یادداشت داخلی…'
                        : isOperator
                            ? l10n.writeYourResponse
                            : l10n.writeYourMessage,
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  minLines: 1,
                  maxLines: compact ? 4 : 6,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: isSending ? null : onSend,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 10 : 12),
                  minimumSize: Size(compact ? 44 : 64, compact ? 40 : 48),
                ),
                child: isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(isInternal ? Icons.lock : Icons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
