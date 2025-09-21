import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class MessageBubble extends StatelessWidget {
  final SupportMessage message;
  final CalendarController? calendarController;
  final bool isCurrentUser;

  const MessageBubble({
    super.key,
    required this.message,
    this.calendarController,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isUser = message.isFromUser;
    final isOperator = message.isFromOperator;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: _getSenderColor(theme),
              child: Icon(
                isOperator ? Icons.support_agent : Icons.settings,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _getBubbleColor(theme, isUser),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: _getBorderColor(theme, isUser),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && message.sender != null) ...[
                    Text(
                      message.sender!.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getSenderTextColor(theme, isUser),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: _getTextColor(theme, isUser),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.createdAt, l10n),
                        style: TextStyle(
                          fontSize: 11,
                          color: _getTimeColor(theme, isUser),
                        ),
                      ),
                      if (message.isInternal) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.lock,
                          size: 12,
                          color: _getTimeColor(theme, isUser),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(
                Icons.person,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getSenderColor(ThemeData theme) {
    if (message.isFromOperator) {
      return Colors.blue;
    } else if (message.isFromSystem) {
      return Colors.grey;
    }
    return theme.colorScheme.primary;
  }

  Color _getBubbleColor(ThemeData theme, bool isUser) {
    if (isUser) {
      return theme.colorScheme.primary;
    } else {
      return theme.colorScheme.surface;
    }
  }

  Color _getBorderColor(ThemeData theme, bool isUser) {
    if (isUser) {
      return theme.colorScheme.primary.withOpacity(0.3);
    } else {
      return theme.colorScheme.outline.withOpacity(0.3);
    }
  }

  Color _getTextColor(ThemeData theme, bool isUser) {
    if (isUser) {
      return Colors.white;
    } else {
      return theme.colorScheme.onSurface;
    }
  }

  Color _getSenderTextColor(ThemeData theme, bool isUser) {
    if (isUser) {
      return Colors.white.withOpacity(0.8);
    } else {
      return theme.colorScheme.primary;
    }
  }

  Color _getTimeColor(ThemeData theme, bool isUser) {
    if (isUser) {
      return Colors.white.withOpacity(0.7);
    } else {
      return theme.colorScheme.onSurface.withOpacity(0.6);
    }
  }

  String _formatTime(DateTime dateTime, AppLocalizations l10n) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    // If the difference is negative (future time), show just now
    if (difference.isNegative) {
      return l10n.justNow;
    }

    if (difference.inDays > 0) {
      return l10n.daysAgo(difference.inDays.toString());
    } else if (difference.inHours > 0) {
      return l10n.hoursAgo(difference.inHours.toString());
    } else if (difference.inMinutes > 0) {
      return l10n.minutesAgo(difference.inMinutes.toString());
    } else if (difference.inSeconds > 10) {
      return l10n.justNow;
    } else {
      return l10n.justNow;
    }
  }
}
