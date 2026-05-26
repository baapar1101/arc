import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_chat_composer.dart';
import 'ai_chat_design.dart';
import 'ai_chat_message_body.dart';

typedef MessageActionCallback = void Function(AIChatMessage message);

class AIChatThreadView extends StatelessWidget {
  final List<AIChatMessage> messages;
  final String? streamingContent;
  final List<AIToolActivity> streamingToolActivities;
  final DateTime? streamingTimestamp;
  final bool messagesLoading;
  final bool sending;
  final bool disabled;
  final bool voiceStarting;
  final bool voiceActive;
  final bool voiceRecording;
  final bool showScrollToBottom;
  final bool isGenerating;
  final ScrollController scrollController;
  final TextEditingController messageController;
  final FocusNode focusNode;
  final String Function(DateTime?) formatTime;
  final VoidCallback onSend;
  final VoidCallback? onMic;
  final VoidCallback? onStopVoice;
  final VoidCallback? onStopGenerating;
  final VoidCallback? onAttach;
  final VoidCallback onScrollToBottom;
  final MessageActionCallback onMessageLongPress;

  const AIChatThreadView({
    super.key,
    required this.messages,
    required this.streamingContent,
    this.streamingToolActivities = const [],
    required this.streamingTimestamp,
    required this.messagesLoading,
    required this.sending,
    required this.disabled,
    required this.voiceStarting,
    required this.voiceActive,
    required this.voiceRecording,
    required this.showScrollToBottom,
    required this.isGenerating,
    required this.scrollController,
    required this.messageController,
    required this.focusNode,
    required this.formatTime,
    required this.onSend,
    this.onMic,
    this.onStopVoice,
    this.onStopGenerating,
    this.onAttach,
    required this.onScrollToBottom,
    required this.onMessageLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              if (messagesLoading)
                const Center(child: CircularProgressIndicator(strokeWidth: 2))
              else
                ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: messages.length + (streamingContent != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < messages.length) {
                      return _MessageRow(
                        message: messages[index],
                        formatTime: formatTime,
                        onLongPress: () => onMessageLongPress(messages[index]),
                      );
                    }
                    return _StreamingRow(
                      content: streamingContent ?? '',
                      toolActivities: streamingToolActivities,
                      formatTime: formatTime(streamingTimestamp),
                    );
                  },
                ),
              if (showScrollToBottom)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Center(
                    child: _ScrollFab(onPressed: onScrollToBottom),
                  ),
                ),
            ],
          ),
        ),
        AIChatComposer(
          controller: messageController,
          focusNode: focusNode,
          placement: AIChatComposerPlacement.bottom,
          sending: sending,
          disabled: disabled,
          voiceStarting: voiceStarting,
          voiceActive: voiceActive,
          voiceRecording: voiceRecording,
          onSend: onSend,
          onMic: onMic,
          onStopVoice: onStopVoice,
          onStopGenerating: isGenerating ? onStopGenerating : null,
          onAttach: onAttach,
        ),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  final AIChatMessage message;
  final String Function(DateTime?) formatTime;
  final VoidCallback onLongPress;

  const _MessageRow({
    required this.message,
    required this.formatTime,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.role == MessageRole.user;
    final timeText = formatTime(message.createdAt);
    final compact = AIChatDesign.isCompactWidth(context);

    if (isUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? double.infinity : AIChatDesign.contentMaxWidth * 0.82,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AIChatMessageBody(
                      content: message.content,
                      isUser: true,
                      functionCalls: message.functionCalls,
                      functionResults: message.functionResults,
                    ),
                    if (timeText.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        timeText,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AssistantAvatar(scheme: scheme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AIChatMessageBody(
                    content: message.content,
                    isUser: false,
                    functionCalls: message.functionCalls,
                    functionResults: message.functionResults,
                  ),
                  if (timeText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      timeText,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreamingRow extends StatelessWidget {
  final String content;
  final List<AIToolActivity> toolActivities;
  final String formatTime;

  const _StreamingRow({
    required this.content,
    this.toolActivities = const [],
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AssistantAvatar(scheme: scheme),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (toolActivities.isNotEmpty)
                  AIChatToolActivityList(activities: toolActivities),
                if (content.isNotEmpty)
                  AIChatMessageBody(
                    content: content,
                    isUser: false,
                  )
                else if (toolActivities.isEmpty)
                  Text(
                    '...',
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'در حال نوشتن',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantAvatar extends StatelessWidget {
  final ColorScheme scheme;

  const _AssistantAvatar({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.onPrimary),
    );
  }
}

class _ScrollFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _ScrollFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(24),
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              SizedBox(width: 4),
              Text('پایین'),
            ],
          ),
        ),
      ),
    );
  }
}
