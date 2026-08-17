import 'package:flutter/material.dart';

import '../../models/ai_models.dart';
import '../../services/voice/voice_phase.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_chat_composer.dart';
import 'ai_chat_design.dart';
import 'ai_reasoning_panel.dart';
import 'ai_chat_l10n.dart';
import 'ai_chat_message_body.dart';
import 'ai_chat_message_actions.dart';
import 'ai_chat_context_bar.dart';
import 'ai_error_recovery_banner.dart';
import 'ai_write_approval_banner.dart';
import 'ai_execution_mode.dart';
typedef MessageActionCallback = void Function(AIChatMessage message);

class AIChatThreadView extends StatelessWidget {
  final List<AIChatMessage> messages;
  final String? streamingContent;
  final List<AIToolActivity> streamingToolActivities;
  final List<AIAgentTraceStep> streamingTraceSteps;
  final AISessionTodoSnapshot? streamingTodoSnapshot;
  final String? streamingStatusPhase;
  final String? streamingStatusStep;
  final int? streamingIteration;
  final int? streamingMaxIterations;
  final int? streamingElapsedSeconds;
  final AIStreamAgentBudget? streamingAgentBudget;
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
  final List<AIModelCatalogItem> availableModels;
  final String? selectedModelCode;
  final bool modelsLoading;
  final ValueChanged<String?>? onModelChanged;
  final String? modelPricingHint;
  final String? streamErrorMessage;
  final bool streamErrorRecoverable;
  final VoidCallback? onRetryStreamError;
  final VoidCallback? onDismissStreamError;
  final String? continueRunId;
  final VoidCallback? onContinueRun;
  final VoidCallback? onDismissContinueRun;
  final String? continueRunHint;
  final bool showWriteApproval;
  final List<Map<String, dynamic>> writeApprovalOps;
  final bool writeApprovalLoading;
  final bool canConfirmWriteApproval;
  final String? writeApprovalBlockedReason;
  final VoidCallback? onConfirmWriteApproval;
  final VoidCallback? onDismissWriteApproval;
  final String? creditWarningMessage;
  final VoidCallback? onCreditUpgrade;
  final String executionMode;
  final ValueChanged<String>? onExecutionModeChanged;
  final void Function(AISessionTodoItem item, String status)? onTodoStatus;

  const AIChatThreadView({
    super.key,
    this.businessId,
    this.suppressApprovalToolChips = false,
    required this.messages,
    required this.streamingContent,
    this.streamingToolActivities = const [],
    this.streamingTraceSteps = const [],
    this.streamingTodoSnapshot,
    this.streamingStatusPhase,
    this.streamingStatusStep,
    this.streamingIteration,
    this.streamingMaxIterations,
    this.streamingElapsedSeconds,
    this.streamingAgentBudget,
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
    this.availableModels = const [],
    this.selectedModelCode,
    this.modelsLoading = false,
    this.onModelChanged,
    this.modelPricingHint,
    this.streamErrorMessage,
    this.streamErrorRecoverable = false,
    this.onRetryStreamError,
    this.onDismissStreamError,
    this.continueRunId,
    this.onContinueRun,
    this.onDismissContinueRun,
    this.continueRunHint,
    this.showWriteApproval = false,
    this.writeApprovalOps = const [],
    this.writeApprovalLoading = false,
    this.canConfirmWriteApproval = true,
    this.writeApprovalBlockedReason,
    this.onConfirmWriteApproval,
    this.onDismissWriteApproval,
    this.creditWarningMessage,
    this.onCreditUpgrade,
    this.executionMode = AIExecutionMode.analyzer,
    this.onExecutionModeChanged,
    this.onTodoStatus,
  });

  Widget _buildMessageList(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: messages.length +
          ((streamingContent != null ||
                  streamingTraceSteps.isNotEmpty ||
                  (streamingTodoSnapshot != null &&
                      !streamingTodoSnapshot!.isEmpty))
              ? 1
              : 0),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final rowKey =
              messageKeys != null && index < messageKeys!.length
                  ? messageKeys![index]
                  : null;
          final message = messages[index];
          final prev = index > 0 ? messages[index - 1] : null;
          final showAvatar = message.role == MessageRole.assistant &&
              prev?.role != MessageRole.assistant;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AIChatDesign.contentMaxWidth,
              ),
              child: KeyedSubtree(
                key: rowKey,
                child: _MessageRow(
                  businessId: businessId,
                  suppressApprovalToolChips: suppressApprovalToolChips,
                  message: message,
                  showAvatar: showAvatar,
                  formatTime: formatTime,
                  onLongPress: () => onMessageLongPress(message),
                  onCopy: () => onCopyMessage(message.content),
                  onFeedback: message.id != null
                      ? (r) => onFeedback(message, r)
                      : null,
                  feedbackRating: message.id != null
                      ? messageFeedbackRatings[message.id!]
                      : null,
                  onRegenerate: message.id != null &&
                          message.id == lastAssistantMessageId &&
                          message.role == MessageRole.assistant
                      ? onRegenerateLast
                      : null,
                  onTodoStatus: message.role == MessageRole.assistant &&
                          message.id != null &&
                          message.id == lastAssistantMessageId
                      ? onTodoStatus
                      : null,
                ),
              ),
            ),
          );
        }
        return Align(
          key: const ValueKey('ai-streaming-row'),
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AIChatDesign.contentMaxWidth,
            ),
            child: _StreamingRow(
              showAvatar: messages.isEmpty ||
                  messages.last.role != MessageRole.assistant,
              businessId: businessId,
              suppressApprovalToolChips: suppressApprovalToolChips,
              content: streamingContent ?? '',
              toolActivities: streamingToolActivities,
              traceSteps: streamingTraceSteps,
              todoSnapshot: streamingTodoSnapshot,
              statusPhase: streamingStatusPhase,
              statusStep: streamingStatusStep,
              iteration: streamingIteration,
              maxIterations: streamingMaxIterations,
              elapsedSeconds: streamingElapsedSeconds,
              agentBudget: streamingAgentBudget,
              formatTime: formatTime(streamingTimestamp),
              onTodoStatus: onTodoStatus,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageStack(BuildContext context) {
    if (messagesLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

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
      ],
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
        if (streamErrorMessage != null)
          AIErrorRecoveryBanner(
            inline: true,
            message: streamErrorMessage!,
            recoverable: streamErrorRecoverable,
            onRetry: onRetryStreamError,
            onDismiss: onDismissStreamError,
          ),
        if (continueRunId != null && onContinueRun != null)
          AIContinueRunBanner(
            onContinue: onContinueRun!,
            onDismiss: onDismissContinueRun,
            loading: sending,
            hint: continueRunHint,
          ),
        if (showWriteApproval &&
            onConfirmWriteApproval != null &&
            onDismissWriteApproval != null)
          AIWriteApprovalBanner(
            inline: true,
            pendingOps: writeApprovalOps,
            loading: writeApprovalLoading,
            canConfirm: canConfirmWriteApproval,
            blockedReason: writeApprovalBlockedReason,
            onConfirm: onConfirmWriteApproval!,
            onDismiss: onDismissWriteApproval!,
          ),
        AIChatContextBar(
          usageRatio: contextUsageRatio,
          usagePercent: contextUsagePercent,
          historySummarized: contextHistorySummarized,
        ),
        if (creditWarningMessage != null)
          AIChatCreditHint(
            message: creditWarningMessage!,
            onUpgrade: onCreditUpgrade,
          ),
        if (AIExecutionMode.normalize(executionMode) == AIExecutionMode.autonomous)
          _AutonomousModeBanner(mode: executionMode),
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
          availableModels: availableModels,
          selectedModelCode: selectedModelCode,
          modelsLoading: modelsLoading,
          onModelChanged: onModelChanged,
          modelPricingHint: modelPricingHint,
          executionMode: executionMode,
          onExecutionModeChanged: onExecutionModeChanged,
        ),
      ],
    );
  }
}

class _AutonomousModeBanner extends StatelessWidget {
  final String mode;

  const _AutonomousModeBanner({required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AIExecutionMode.accentColor(context, mode);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AIChatDesign.contentMaxWidth),
          child: Material(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.bolt_outlined, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'حالت خودکار فعال است — تغییرات معمولی بدون تأیید اجرا می‌شوند.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final int? businessId;
  final bool suppressApprovalToolChips;
  final AIChatMessage message;
  final bool showAvatar;
  final String Function(DateTime?) formatTime;
  final VoidCallback onLongPress;
  final VoidCallback onCopy;
  final ValueChanged<int>? onFeedback;
  final int? feedbackRating;
  final VoidCallback? onRegenerate;
  final void Function(AISessionTodoItem item, String status)? onTodoStatus;

  const _MessageRow({
    this.businessId,
    this.suppressApprovalToolChips = false,
    required this.message,
    this.showAvatar = true,
    required this.formatTime,
    required this.onLongPress,
    required this.onCopy,
    this.onFeedback,
    this.feedbackRating,
    this.onRegenerate,
    this.onTodoStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isUser = message.role == MessageRole.user;
    final compact = AIChatDesign.isCompactWidth(context);

    if (isUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact
                  ? double.infinity
                  : AIChatDesign.contentMaxWidth * 0.82,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: AIChatMessageBody(
                  content: message.content,
                  isUser: true,
                  functionCalls: message.functionCalls,
                  functionResults: message.functionResults,
                  suppressApprovalToolChips: suppressApprovalToolChips,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: showAvatar ? _AssistantAvatar(scheme: scheme) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AIChatMessageBody(
                    content: message.content,
                    isUser: false,
                    businessId: businessId,
                    functionCalls: message.functionCalls,
                    functionResults: message.functionResults,
                    suppressApprovalToolChips: suppressApprovalToolChips,
                    onTodoStatus: onTodoStatus,
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: AIChatMessageActions(
                          onCopy: onCopy,
                          onRegenerate: onRegenerate,
                          onFeedback: onFeedback,
                          currentRating: feedbackRating,
                        ),
                      ),
                      if (!compact && message.createdAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatTime(message.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
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
  final bool showAvatar;
  final String content;
  final List<AIToolActivity> toolActivities;
  final List<AIAgentTraceStep> traceSteps;
  final AISessionTodoSnapshot? todoSnapshot;
  final String? statusPhase;
  final String? statusStep;
  final int? iteration;
  final int? maxIterations;
  final int? elapsedSeconds;
  final AIStreamAgentBudget? agentBudget;
  final String formatTime;
  final void Function(AISessionTodoItem item, String status)? onTodoStatus;

  const _StreamingRow({
    this.businessId,
    this.suppressApprovalToolChips = false,
    this.showAvatar = true,
    required this.content,
    this.toolActivities = const [],
    this.traceSteps = const [],
    this.todoSnapshot,
    this.statusPhase,
    this.statusStep,
    this.iteration,
    this.maxIterations,
    this.elapsedSeconds,
    this.agentBudget,
    required this.formatTime,
    this.onTodoStatus,
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
    final hasReasoningPanel = (todoSnapshot != null && !todoSnapshot!.isEmpty) ||
        traceSteps.isNotEmpty ||
        toolActivities.isNotEmpty ||
        agentBudget != null;
    final showStatusLine =
        content.isEmpty && statusPhase != 'writing';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: showAvatar ? _AssistantAvatar(scheme: scheme) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasReasoningPanel)
                  AIReasoningPanel(
                    steps: traceSteps,
                    toolActivities: suppressApprovalToolChips
                        ? toolActivities
                            .where((a) => !a.approvalRequired)
                            .toList()
                        : toolActivities,
                    agentBudget: agentBudget,
                    todoSnapshot: todoSnapshot,
                    compact: true,
                    keepExpanded: true,
                    initiallyExpanded: true,
                    onTodoStatus: onTodoStatus,
                  ),
                if (hasReasoningPanel && showStatusLine)
                  const SizedBox(height: 8),
                if (content.isNotEmpty)
                  AIChatMessageBody(
                    content: content,
                    isUser: false,
                    businessId: businessId,
                  )
                else if (showStatusLine)
                  _StreamingStatusPulse(
                    label: statusLabel,
                    elapsedSeconds: elapsedSeconds,
                    theme: theme,
                    scheme: scheme,
                  ),
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.aiStatusWriting,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingStatusPulse extends StatefulWidget {
  final String label;
  final int? elapsedSeconds;
  final ThemeData theme;
  final ColorScheme scheme;

  const _StreamingStatusPulse({
    required this.label,
    this.elapsedSeconds,
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
    final l10n = AppLocalizations.of(context);
    final elapsed = widget.elapsedSeconds;
    final displayLabel = elapsed != null && elapsed > 0
        ? '${widget.label} · ${l10n.aiStatusElapsed(elapsed)}'
        : widget.label;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Text(
        displayLabel,
        style: widget.theme.textTheme.bodyMedium?.copyWith(
          height: 1.5,
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
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.auto_awesome_rounded, size: 16, color: scheme.primary),
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
