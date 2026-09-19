import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/ai/ai_channel_assist_stream.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_l10n.dart';
import '../../utils/snackbar_helper.dart';

/// Widget برای کمک AI در پاسخ به تیکت‌های پشتیبانی
class AITicketAssistant extends StatefulWidget {
  final int ticketId;
  final String? ticketContext;
  final Function(String suggestedReply)? onReplySuggested;
  final Function(String autoReply)? onAutoReply;

  const AITicketAssistant({
    super.key,
    required this.ticketId,
    this.ticketContext,
    this.onReplySuggested,
    this.onAutoReply,
  });

  @override
  State<AITicketAssistant> createState() => _AITicketAssistantState();
}

class _AITicketAssistantState extends State<AITicketAssistant>
    with TickerProviderStateMixin {
  late final AIService _aiService;
  bool _suggesting = false;
  bool _autoReplying = false;
  String? _suggestedReply;
  String? _phase;
  String? _error;
  bool _isExpanded = false;
  CancelToken? _suggestCancel;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
  }

  @override
  void dispose() {
    _suggestCancel?.cancel('disposed');
    super.dispose();
  }

  Future<void> _suggestReply() async {
    _suggestCancel?.cancel('replaced');
    final token = CancelToken();
    _suggestCancel = token;
    setState(() {
      _suggesting = true;
      _error = null;
      _suggestedReply = '';
      _phase = 'connecting';
    });

    try {
      final outcome = await consumeChannelAssistStream(
        _aiService.streamTicketSuggestReply(
          ticketId: widget.ticketId,
          context: widget.ticketContext,
          cancelToken: token,
        ),
        onProgress: (progress) {
          if (!mounted || token.isCancelled) return;
          setState(() {
            _suggestedReply = progress.text;
            _phase = progress.phase;
          });
        },
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _suggestedReply =
            outcome.text.isNotEmpty ? outcome.text : _suggestedReply;
        _suggesting = false;
        _phase = null;
        _error = outcome.error;
      });
    } catch (e) {
      if (token.isCancelled) return;
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _suggesting = false;
        _phase = null;
      });
      SnackBarHelper.show(
        context,
        message: AppLocalizations.of(context).aiTicketSuggestFailed(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  Future<void> _autoReply() async {
    if (await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context).aiTicketAutoReplyConfirmTitle),
            content: Text(
              AppLocalizations.of(context).aiTicketAutoReplyConfirmBody,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('لغو'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('تأیید'),
              ),
            ],
          ),
        ) ??
        false) {
      setState(() {
        _autoReplying = true;
        _error = null;
      });

      try {
        final result = await _aiService.autoReplyTicket(
          ticketId: widget.ticketId,
          context: widget.ticketContext,
        );

        final data = result['data'] as Map<String, dynamic>?;
        final replyText = data?['content'] as String? ??
            data?['suggested_reply'] as String? ??
            result['message'] as String? ??
            'پاسخی ارسال نشد';

        setState(() {
          _autoReplying = false;
        });

        if (widget.onAutoReply != null) {
          widget.onAutoReply!(replyText);
        }

        if (mounted) {
          SnackBarHelper.show(context, message: 'پاسخ با موفقیت ارسال شد');
        }
      } catch (e) {
        setState(() {
          _error = ErrorExtractor.forContext(e, context);
          _autoReplying = false;
        });
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: 'خطا در ارسال پاسخ: ${ErrorExtractor.forContext(e, context)}',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final suggestButton = OutlinedButton.icon(
      onPressed: _suggesting ? null : _suggestReply,
      icon: _suggesting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.lightbulb_outline),
      label: Text(
        _suggesting && _phase != null
            ? aiStreamStatusLabel(l10n, phase: _phase!)
            : l10n.aiTicketSuggestReply,
      ),
    );

    final autoReplyButton = FilledButton.icon(
      onPressed: _autoReplying ? null : _autoReply,
      icon: _autoReplying
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.send),
      label: Text(l10n.aiTicketAutoReply),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.aiTicketAssistantTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isExpanded
                                ? l10n.aiTicketAssistantHintExpanded
                                : l10n.aiTicketAssistantHintCollapsed,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 480) {
                          return Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: suggestButton,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: autoReplyButton,
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: suggestButton),
                            const SizedBox(width: 12),
                            Expanded(child: autoReplyButton),
                          ],
                        );
                      },
                    ),
                    if (_suggestedReply != null &&
                        _suggestedReply!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.aiTicketSuggestionLabel,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: Scrollbar(
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  child: Text(
                                    _suggestedReply!,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: () {
                                  if (widget.onReplySuggested != null) {
                                    widget.onReplySuggested!(_suggestedReply!);
                                  }
                                },
                                icon: const Icon(Icons.content_paste_go),
                                label: Text(l10n.aiTicketUseSuggestion),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 18,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

