import 'package:flutter/material.dart';

import '../../models/ai_models.dart';
import '../../services/voice/voice_phase.dart';
import 'ai_chat_composer.dart';
import 'ai_chat_design.dart';
import 'ai_chat_suggestions.dart';
import 'ai_error_recovery_banner.dart';

class AIChatHomeView extends StatelessWidget {
  final TextEditingController messageController;
  final FocusNode focusNode;
  final bool sending;
  final bool disabled;
  final bool voiceStarting;
  final bool voiceActive;
  final VoicePhase voicePhase;
  final Map<String, dynamic>? voiceStatusEvent;
  final bool canUseAi;
  final String? blockReason;
  final VoidCallback onSend;
  final VoidCallback? onMic;
  final VoidCallback? onStopVoice;
  final ValueChanged<AIChatSuggestion> onSuggestionSelected;
  final List<AIChatSuggestion> suggestions;
  final List<Map<String, dynamic>> proactiveAlerts;
  final ValueChanged<String>? onAlertAction;
  final VoidCallback? onUpgradePlan;
  final List<AIModelCatalogItem> availableModels;
  final String? selectedModelCode;
  final bool modelsLoading;
  final ValueChanged<String?>? onModelChanged;
  final String? modelPricingHint;
  final String? creditWarningMessage;
  final VoidCallback? onCreditUpgrade;

  const AIChatHomeView({
    super.key,
    required this.messageController,
    required this.focusNode,
    required this.sending,
    required this.disabled,
    required this.voiceStarting,
    required this.voiceActive,
    this.voicePhase = VoicePhase.idle,
    this.voiceStatusEvent,
    required this.canUseAi,
    this.blockReason,
    required this.onSend,
    this.onMic,
    this.onStopVoice,
    required this.onSuggestionSelected,
    this.suggestions = kDefaultAIChatSuggestions,
    this.proactiveAlerts = const [],
    this.onAlertAction,
    this.onUpgradePlan,
    this.availableModels = const [],
    this.selectedModelCode,
    this.modelsLoading = false,
    this.onModelChanged,
    this.modelPricingHint,
    this.creditWarningMessage,
    this.onCreditUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = AIChatDesign.isCompactWidth(context);
    final visibleSuggestions = suggestions
        .take(AIChatDesign.homeSuggestionLimit)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 24,
            vertical: compact ? 32 : 56,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AIChatDesign.contentMaxWidth),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'امروز چه کمکی از دستم برمی‌آید؟',
                      textAlign: TextAlign.center,
                      style: AIChatDesign.greetingStyle(theme),
                    ),
                    if (proactiveAlerts.isNotEmpty && canUseAi) ...[
                      SizedBox(height: compact ? 16 : 20),
                      _ProactiveAlertsSummary(
                        alerts: proactiveAlerts,
                        onAction: onAlertAction,
                      ),
                    ],
                    SizedBox(height: compact ? 24 : 32),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AIChatComposer(
                              controller: messageController,
                              focusNode: focusNode,
                              placement: AIChatComposerPlacement.center,
                              sending: sending,
                              disabled: disabled || !canUseAi,
                              voiceStarting: voiceStarting,
                              voiceActive: voiceActive,
                              voicePhase: voicePhase,
                              voiceStatusEvent: voiceStatusEvent,
                              onSend: onSend,
                              onMic: canUseAi ? onMic : null,
                              onStopVoice: onStopVoice,
                              availableModels: availableModels,
                              selectedModelCode: selectedModelCode,
                              modelsLoading: modelsLoading,
                              onModelChanged: onModelChanged,
                              modelPricingHint: modelPricingHint,
                            ),
                            if (creditWarningMessage != null) ...[
                              const SizedBox(height: 8),
                              AIChatCreditHint(
                                message: creditWarningMessage!,
                                onUpgrade: onCreditUpgrade,
                              ),
                            ],
                          ],
                        ),
                        if (!canUseAi && blockReason != null)
                          _ComposerBlockOverlay(
                            message: blockReason!,
                            onUpgrade: onUpgradePlan,
                          ),
                      ],
                    ),
                    if (visibleSuggestions.isNotEmpty && canUseAi) ...[
                      SizedBox(height: compact ? 18 : 24),
                      AIChatSuggestionChips(
                        suggestions: visibleSuggestions,
                        enabled: canUseAi && !disabled,
                        onSelected: onSuggestionSelected,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProactiveAlertsSummary extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final ValueChanged<String>? onAction;

  const _ProactiveAlertsSummary({
    required this.alerts,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = alerts.length;
    final first = alerts.first;
    final actionPrompt = first['action_prompt'] as String?;
    final title = first['title'] as String? ?? '';

    return InkWell(
      onTap: actionPrompt != null && onAction != null
          ? () => onAction!(actionPrompt)
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 16,
              color: scheme.tertiary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                count == 1
                    ? title
                    : '$count هشدار مالی · $title',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (actionPrompt != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_left_rounded, size: 18, color: scheme.outline),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerBlockOverlay extends StatelessWidget {
  final String message;
  final VoidCallback? onUpgrade;

  const _ComposerBlockOverlay({
    required this.message,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Positioned.fill(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(AIChatDesign.composerRadius),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, color: scheme.error, size: 28),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (onUpgrade != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: onUpgrade,
                    child: const Text('مشاهده پلن‌ها'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
