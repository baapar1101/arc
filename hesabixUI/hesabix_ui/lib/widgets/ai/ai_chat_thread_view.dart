import 'package:flutter/material.dart';

import '../../services/voice/voice_phase.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_chat_composer.dart';
import 'ai_chat_design.dart';
import 'ai_conversation_nav_sheet.dart';
import 'ai_conversation_rail.dart';
import 'ai_reasoning_panel.dart';
import 'ai_chat_l10n.dart';
import 'ai_chat_message_body.dart';
import 'ai_chat_message_actions.dart';
import 'ai_chat_context_bar.dart';
typedef MessageActionCallback = void Function(AIChatMessage message);

class AIChatThreadView extends StatelessWidget {
  final List<AIChatMessage> messages;
  final String? streamingContent;
  final List<AIToolActivity> streamingToolActivities;
  final List<AIAgentTraceStep> streamingTraceSteps;
  final String? streamingStatusPhase;
  final String? streamingStatusStep;
  final int? streamingIteration;
  final int? streamingMaxIterations;
  final int? streamingElapsedSeconds;
  final DateTime? streamingTimestamp;
  final bool messagesLoading;
  final bool sending;
  final bool disabled;
  final bool voiceStarting;
  final bool voiceActive;
  final VoicePhase voicePhase;
  final Map<String, dynamic>? voiceStatusEvent;
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
  final Map<int, int> messageFeedbackRatings;
  final void Function(String text) onCopyMessage;
  final void Function(AIChatMessage message, int rating) onFeedback;
  final VoidCallback? onRegenerateLast;
  final int? lastAssistantMessageId;
  final double? contextUsageRatio;
  final double? contextUsagePercent;
  final bool contextHistorySummarized;
  final List<GlobalKey>? messageKeys;
  final int? businessId;
  final bool suppressApprovalToolChips;

  const AIChatThreadView({
    super.key,
    this.businessId,
    this.suppressApprovalToolChips = false,
    required this.messages,
    required this.streamingContent,
    this.streamingToolActivities = const [],
    this.streamingTraceSteps = const [],
    this.streamingStatusPhase,
    this.streamingStatusStep,
    this.streamingIteration,
    this.streamingMaxIterations,
    this.streamingElapsedSeconds,
    required this.streamingTimestamp,
    required this.messagesLoading,
    required this.sending,
    required this.disabled,
    required this.voiceStarting,
    required this.voiceActive,
    this.voicePhase = VoicePhase.idle,
    this.voiceStatusEvent,
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
    this.messageFeedbackRatings = const {},
    required this.onCopyMessage,
    required this.onFeedback,
    this.onRegenerateLast,
    this.lastAssistantMessageId,
    this.contextUsageRatio,
    this.contextUsagePercent,
    this.contextHistorySummarized = false,
    this.messageKeys,
  });

  Widget _buildMessageList(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        AIChatDesign.showConversationRail(context) ? 40 : 16,
        8,
      ),
      itemCount: messages.length +
          ((streamingContent != null || streamingTraceSteps.isNotEmpty) ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final rowKey =
              messageKeys != null && index < messageKeys!.length
                  ? messageKeys![index]
                  : null;
          return KeyedSubtree(
            key: rowKey,
            child: _MessageRow(
              businessId: businessId,
              suppressApprovalToolChips: suppressApprovalToolChips,
              message: messages[index],
              formatTime: formatTime,
              onLongPress: () => onMessageLongPress(messages[index]),
              onCopy: () => onCopyMessage(messages[index].content),
              onFeedback: messages[index].id != null
                  ? (r) => onFeedback(messages[index], r)
                  : null,
              feedbackRating: messages[index].id != null
                  ? messageFeedbackRatings[messages[index].id!]
                  : null,
              onRegenerate: messages[index].id != null &&
                      messages[index].id == lastAssistantMessageId &&
                      messages[index].role == MessageRole.assistant
                  ? onRegenerateLast
                  : null,
            ),
          );
        }
        return _StreamingRow(
          businessId: businessId,
          suppressApprovalToolChips: suppressApprovalToolChips,
          content: streamingContent ?? '',
          toolActivities: streamingToolActivities,
          traceSteps: streamingTraceSteps,
          statusPhase: streamingStatusPhase,
          statusStep: streamingStatusStep,
          iteration: streamingIteration,
          maxIterations: streamingMaxIterations,
          elapsedSeconds: streamingElapsedSeconds,
          formatTime: formatTime(streamingTimestamp),
        );
      },
    );
  }

  Widget _buildMessageStack(BuildContext context) {
    if (messagesLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final canSync = messageKeys != null &&
        messageKeys!.length == messages.length &&
        messages.isNotEmpty;

    Widget stackContent(int activeIndex, void Function(int) jumpToIndex) {
      return Stack(
        children: [
          _buildMessageList(context),
          if (showScrollToBottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(child: _ScrollFab(onPressed: onScrollToBottom)),
            ),
          if (AIChatDesign.showConversationRail(context) && canSync)
            AIConversationRail(
              messages: messages,
              scrollController: scrollController,
              messageKeys: messageKeys!,
              activeIndex: activeIndex,
              onJumpToIndex: jumpToIndex,
            ),
          if (AIChatDesign.showConversationNavFab(context) &&
              canSync &&
              messages.length >= 2)
            AIConversationNavFab(
              messageCount: messages.length,
              activeIndex: activeIndex,
              onTap: () => showAIConversationNavSheet(
                context: context,
                messages: messages,
                messageKeys: messageKeys!,
                activeIndex: activeIndex,
                onJumpToIndex: jumpToIndex,
              ),
            ),
        ],
      );
    }

    if (!canSync) {
      return stackContent(0, (_) {});
    }

    return AIConversationScrollScope(
      scrollController: scrollController,
      messageKeys: messageKeys!,
      messageCount: messages.length,
      builder: (ctx, activeIndex, jumpToIndex) =>
          stackContent(activeIndex, jumpToIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildMessageStack(context),
        ),
        AIChatContextBar(
          usageRatio: contextUsageRatio,
          usagePercent: contextUsagePercent,
          historySummarized: contextHistorySummarized,
        ),
        AIChatComposer(
          controller: messageController,
          focusNode: focusNode,
          placement: AIChatComposerPlacement.bottom,
          sending: sending,
          disabled: disabled,
          voiceStarting: voiceStarting,
          voiceActive: voiceActive,
          voicePhase: voicePhase,
          voiceStatusEvent: voiceStatusEvent,
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
  final int? businessId;
  final bool suppressApprovalToolChips;
  final AIChatMessage message;
  final String Function(DateTime?) formatTime;
  final VoidCallback onLongPress;
  final VoidCallback onCopy;
  final ValueChanged<int>? onFeedback;
  final int? feedbackRating;
  final VoidCallback? onRegenerate;

  const _MessageRow({
    this.businessId,
    this.suppressApprovalToolChips = false,
    required this.message,
    required this.formatTime,
    required this.onLongPress,
    required this.onCopy,
    this.onFeedback,
    this.feedbackRating,
    this.onRegenerate,
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
                      suppressApprovalToolChips: suppressApprovalToolChips,
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    decoration: AIChatDesign.elevatedCard(
                      theme,
                      alpha: theme.brightness == Brightness.dark ? 0.42 : 0.66,
                    ).copyWith(
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: AIChatMessageBody(
                      content: message.content,
                      isUser: false,
                      businessId: businessId,
                      functionCalls: message.functionCalls,
                      functionResults: message.functionResults,
                      suppressApprovalToolChips: suppressApprovalToolChips,
                    ),
                  ),
                  AIChatMessageActions(
                    onCopy: onCopy,
                    onRegenerate: onRegenerate,
                    onFeedback: onFeedback,
                    currentRating: feedbackRating,
                  ),
                  if (timeText.isNotEmpty) ...[
                    const SizedBox(height: 4),
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
  final int? businessId;
  final bool suppressApprovalToolChips;
  final String content;
  final List<AIToolActivity> toolActivities;
  final List<AIAgentTraceStep> traceSteps;
  final String? statusPhase;
  final String? statusStep;
  final int? iteration;
  final int? maxIterations;
  final int? elapsedSeconds;
  final String formatTime;

  const _StreamingRow({
    this.businessId,
    this.suppressApprovalToolChips = false,
    required this.content,
    this.toolActivities = const [],
    this.traceSteps = const [],
    this.statusPhase,
    this.statusStep,
    this.iteration,
    this.maxIterations,
    this.elapsedSeconds,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final statusLabel = statusPhase != null
        ? aiStreamStatusLabel(
            l10n,
            phase: statusPhase!,
            step: statusStep,
            iteration: iteration,
            maxIterations: maxIterations,
          )
        : l10n.aiStatusThinking;
    final showStatusLine =
        content.isEmpty && toolActivities.isEmpty && traceSteps.isEmpty;

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
                if (traceSteps.isNotEmpty) ...[
                  AIReasoningPanel(
                    steps: traceSteps,
                    initiallyExpanded: true,
                  ),
                  const SizedBox(height: 10),
                ],
                if (toolActivities.isNotEmpty && traceSteps.isEmpty)
                  AIChatToolActivityList(
                    activities: toolActivities,
                    hideApprovalPending: suppressApprovalToolChips,
                  ),
                if (content.isNotEmpty)
                  _StreamingAnswerCard(
                    businessId: businessId,
                    content: content,
                    theme: theme,
                    scheme: scheme,
                    showReasoningAbove: traceSteps.isNotEmpty,
                  )
                else if (showStatusLine)
                  _StreamingStatusPulse(
                    label: statusLabel,
                    theme: theme,
                    scheme: scheme,
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
                    Expanded(
                      child: Text(
                        content.isNotEmpty
                            ? l10n.aiStatusWriting
                            : statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (elapsedSeconds != null && elapsedSeconds! > 0)
                      Text(
                        l10n.aiStatusElapsed(elapsedSeconds!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
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

/// کارت پاسخ نهایی در حالت استریم (جدا از پنل استدلال).
class _StreamingAnswerCard extends StatelessWidget {
  final int? businessId;
  final String content;
  final ThemeData theme;
  final ColorScheme scheme;
  final bool showReasoningAbove;

  const _StreamingAnswerCard({
    this.businessId,
    required this.content,
    required this.theme,
    required this.scheme,
    required this.showReasoningAbove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showReasoningAbove) const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              l10n.aiAnswerPanelTitle,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: AIChatDesign.elevatedCard(
            theme,
            alpha: theme.brightness == Brightness.dark ? 0.42 : 0.66,
            accent: scheme.primary,
          ).copyWith(
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AIChatMessageBody(
            content: content,
            isUser: false,
            businessId: businessId,
            suppressAnswerLabel: true,
          ),
        ),
      ],
    );
  }
}

class _StreamingStatusPulse extends StatefulWidget {
  final String label;
  final ThemeData theme;
  final ColorScheme scheme;

  const _StreamingStatusPulse({
    required this.label,
    required this.theme,
    required this.scheme,
  });

  @override
  State<_StreamingStatusPulse> createState() => _StreamingStatusPulseState();
}

class _StreamingStatusPulseState extends State<_StreamingStatusPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Text(
        widget.label,
        style: widget.theme.textTheme.bodyLarge?.copyWith(
          height: 1.65,
          color: widget.scheme.onSurfaceVariant,
        ),
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
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primary,
            scheme.tertiary.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(Icons.auto_awesome_rounded, size: 19, color: scheme.onPrimary),
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
