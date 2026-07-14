import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as date_utils;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/support_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/support_ticket_clipboard.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/file_saver.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';

class MessageBubble extends StatelessWidget {
  final SupportMessage message;
  final CalendarController? calendarController;
  final bool isCurrentUser;
  final bool isOperator;

  const MessageBubble({
    super.key,
    required this.message,
    this.calendarController,
    this.isCurrentUser = false,
    this.isOperator = false,
  });

  bool get _alignEnd {
    if (message.isInternal) return true;
    final fromUser = message.isFromUser;
    return isOperator ? !fromUser : fromUser;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = SupportSemanticColors.of(context);
    final alignEnd = _alignEnd;
    final isInternal = message.isInternal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!alignEnd) ...[
            _Avatar(message: message, theme: theme),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _bubbleColor(theme, colors, alignEnd, isInternal),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(alignEnd ? 14 : 4),
                  bottomRight: Radius.circular(alignEnd ? 4 : 14),
                ),
                border: Border.all(color: _borderColor(theme, colors, alignEnd, isInternal)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isInternal)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, size: 12, color: colors.internalNoteFg),
                          const SizedBox(width: 4),
                          Text(
                            'یادداشت داخلی',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colors.internalNoteFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.sender != null && !message.isFromUser) ...[
                    Text(
                      message.sender!.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (message.content.isNotEmpty)
                    GestureDetector(
                      onLongPress: isOperator ? () => _copyMessage(context, l10n) : null,
                      child: isOperator
                          ? SelectableText(
                              message.content,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: _textColor(theme, colors, alignEnd, isInternal),
                              ),
                            )
                          : Text(
                              message.content,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: _textColor(theme, colors, alignEnd, isInternal),
                              ),
                            ),
                    ),
                  if (message.attachments != null && message.attachments!.isNotEmpty) ...[
                    if (message.content.isNotEmpty) const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: message.attachments!.map((a) {
                        return ActionChip(
                          avatar: Icon(Icons.attach_file, size: 16, color: _textColor(theme, colors, alignEnd, isInternal)),
                          label: Text(
                            a.originalName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: _textColor(theme, colors, alignEnd, isInternal)),
                          ),
                          onPressed: () => _downloadAttachment(context, a),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTime(message.createdAt, l10n),
                        style: TextStyle(
                          fontSize: 11,
                          color: _textColor(theme, colors, alignEnd, isInternal).withValues(alpha: 0.65),
                        ),
                      ),
                      if (isOperator && message.content.trim().isNotEmpty)
                        _CopyMessageButton(
                          tooltip: l10n.supportTicketCopyMessage,
                          color: _textColor(theme, colors, alignEnd, isInternal).withValues(alpha: 0.75),
                          onCopy: () => _copyMessage(context, l10n),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (alignEnd) ...[
            const SizedBox(width: 8),
            _Avatar(message: message, theme: theme),
          ],
        ],
      ),
    );
  }

  Color _bubbleColor(ThemeData theme, SupportSemanticColors colors, bool alignEnd, bool isInternal) {
    if (isInternal) return colors.internalNoteBg;
    if (alignEnd && !isOperator) return theme.colorScheme.primary;
    if (alignEnd && isOperator) return colors.agentBubbleBg;
    return colors.customerBubbleBg;
  }

  Color _borderColor(ThemeData theme, SupportSemanticColors colors, bool alignEnd, bool isInternal) {
    if (isInternal) return colors.internalNoteBorder;
    if (alignEnd && !isOperator) return theme.colorScheme.primary.withValues(alpha: 0.25);
    return theme.colorScheme.outlineVariant;
  }

  Color _textColor(ThemeData theme, SupportSemanticColors colors, bool alignEnd, bool isInternal) {
    if (isInternal) return colors.internalNoteFg;
    if (alignEnd && !isOperator) return theme.colorScheme.onPrimary;
    return theme.colorScheme.onSurface;
  }

  Future<void> _copyMessage(BuildContext context, AppLocalizations l10n) async {
    final text = formatSupportMessageForClipboard(
      message: message,
      formatDateTime: (date) {
        final isJalali = calendarController?.isJalali ?? true;
        return date_utils.HesabixDateUtils.formatDateTime(date, isJalali);
      },
    );
    await copySupportTextToClipboard(context, text);
  }

  Future<void> _downloadAttachment(BuildContext context, SupportAttachment attachment) async {
    try {
      final bytes = await SupportService(ApiClient()).downloadAttachment(
        attachment.id,
        isOperator: isOperator,
      );
      await FileSaver.saveBytes(bytes, attachment.originalName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${attachment.originalName} دانلود شد')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorExtractor.forContext(e, context)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime, AppLocalizations l10n) {
    final localDateTime = dateTime.isUtc ? dateTime.toLocal() : dateTime;
    final difference = DateTime.now().difference(localDateTime);
    if (difference.isNegative) return l10n.justNow;
    if (difference.inDays > 0 || difference.inHours >= 24) {
      final isJalali = calendarController?.isJalali ?? true;
      return date_utils.HesabixDateUtils.formatDateTime(localDateTime, isJalali);
    }
    if (difference.inHours > 0) return l10n.hoursAgo(difference.inHours.toString());
    if (difference.inMinutes > 0) return l10n.minutesAgo(difference.inMinutes.toString());
    return l10n.justNow;
  }
}

class _CopyMessageButton extends StatelessWidget {
  final String tooltip;
  final Color color;
  final VoidCallback onCopy;

  const _CopyMessageButton({
    required this.tooltip,
    required this.color,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Tooltip(
            message: tooltip,
            child: Icon(Icons.copy_outlined, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final SupportMessage message;
  final ThemeData theme;

  const _Avatar({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    final bg = message.isFromOperator
        ? theme.colorScheme.secondary
        : message.isFromSystem
            ? theme.colorScheme.outline
            : theme.colorScheme.primary;
    final icon = message.isFromOperator
        ? Icons.support_agent
        : message.isFromSystem
            ? Icons.settings
            : Icons.person;
    return CircleAvatar(
      radius: 16,
      backgroundColor: bg,
      child: Icon(icon, size: 16, color: theme.colorScheme.onPrimary),
    );
  }
}
