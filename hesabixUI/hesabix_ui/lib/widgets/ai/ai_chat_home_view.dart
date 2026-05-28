import 'package:flutter/material.dart';

import '../../services/voice/voice_phase.dart';
import 'ai_chat_composer.dart';
import 'ai_chat_design.dart';
import 'ai_chat_suggestions.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = AIChatDesign.isCompactWidth(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 20 : 32,
            vertical: compact ? 24 : 48,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AIChatDesign.contentMaxWidth),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _HeroIcon(isDark: isDark, scheme: scheme),
                    SizedBox(height: compact ? 20 : 28),
                    Text(
                      'امروز چه چیزی را در کسب‌وکارتان بررسی کنیم؟',
                      textAlign: TextAlign.center,
                      style: AIChatDesign.greetingStyle(theme),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'از فروش و موجودی تا مالیات، بدهکاران و جریان نقدی؛ پاسخ‌ها را با داده‌های همین کسب‌وکار تحلیل می‌کنم.',
                      textAlign: TextAlign.center,
                      style: AIChatDesign.subtitleStyle(theme),
                    ),
                    if (!canUseAi && blockReason != null) ...[
                      SizedBox(height: compact ? 20 : 28),
                      _BlockedBanner(
                        message: blockReason!,
                        onUpgrade: onUpgradePlan,
                      ),
                    ],
                    if (proactiveAlerts.isNotEmpty && canUseAi) ...[
                      SizedBox(height: compact ? 20 : 28),
                      ...proactiveAlerts.take(3).map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _ProactiveAlertCard(
                                alert: a,
                                onAction: onAlertAction,
                              ),
                            ),
                          ),
                    ],
                    SizedBox(height: compact ? 24 : 36),
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
                    ),
                    SizedBox(height: compact ? 22 : 28),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'شروع سریع',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AIChatSuggestionChips(
                      suggestions: suggestions,
                      enabled: canUseAi && !disabled,
                      onSelected: onSuggestionSelected,
                    ),
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

class _HeroIcon extends StatelessWidget {
  final bool isDark;
  final ColorScheme scheme;

  const _HeroIcon({required this.isDark, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.9),
            scheme.tertiary.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: isDark ? 0.35 : 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 36,
        color: scheme.onPrimary,
      ),
    );
  }
}

class _ProactiveAlertCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final ValueChanged<String>? onAction;

  const _ProactiveAlertCard({required this.alert, this.onAction});

  Color _levelColor(ColorScheme scheme) {
    switch (alert['level'] as String? ?? 'info') {
      case 'warning':
        return scheme.tertiary;
      case 'success':
        return scheme.primary;
      case 'error':
        return scheme.error;
      default:
        return scheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _levelColor(scheme);
    final title = alert['title'] as String? ?? '';
    final message = alert['message'] as String? ?? '';
    final actionPrompt = alert['action_prompt'] as String?;

    return Material(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: actionPrompt != null && onAction != null
            ? () => onAction!(actionPrompt)
            : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.notifications_active_outlined, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    if (message.isNotEmpty && message != title)
                      Text(message, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (actionPrompt != null)
                Icon(Icons.chevron_left_rounded, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onUpgrade;

  const _BlockedBanner({required this.message, this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer),
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
    );
  }
}
