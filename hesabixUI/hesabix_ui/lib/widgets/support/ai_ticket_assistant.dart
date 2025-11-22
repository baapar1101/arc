import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
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
  String? _error;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _aiService = AIService(api);
  }

  Future<void> _suggestReply() async {
    setState(() {
      _suggesting = true;
      _error = null;
      _suggestedReply = null;
    });

    try {
      final result = await _aiService.suggestTicketReply(
        ticketId: widget.ticketId,
        context: widget.ticketContext,
      );

      final data = result['data'] as Map<String, dynamic>?;
      final suggestedText = data?['suggested_reply'] as String? ??
          data?['message'] as String? ??
          result['message'] as String? ??
          'پیشنهادی دریافت نشد';

      setState(() {
        _suggestedReply = suggestedText;
        _suggesting = false;
      });

      // پیشنهاد تنها هنگام فشردن دکمهٔ «استفاده از این پاسخ» به فیلد منتقل می‌شود
    } catch (e) {
      setState(() {
        _error = '$e';
        _suggesting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در دریافت پیشنهاد: $e')),
        );
      }
    }
  }

  Future<void> _autoReply() async {
    if (await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('پاسخ خودکار'),
            content: const Text(
              'آیا می‌خواهید AI به صورت خودکار به این تیکت پاسخ دهد؟',
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('پاسخ با موفقیت ارسال شد')),
          );
        }
      } catch (e) {
        setState(() {
          _error = '$e';
          _autoReplying = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطا در ارسال پاسخ: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final suggestButton = OutlinedButton.icon(
      onPressed: _suggesting ? null : _suggestReply,
      icon: _suggesting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.lightbulb_outline),
      label: const Text('پیشنهاد پاسخ'),
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
      label: const Text('پاسخ خودکار'),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            'کمک هوش مصنوعی',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isExpanded
                                ? 'دستیار فعال است. پیشنهاد یا پاسخ خودکار دریافت کنید.'
                                : 'برای نمایش دستیار و دکمه‌های AI ضربه بزنید.',
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
                    if (_suggestedReply != null) ...[
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
                                  'پیشنهاد AI',
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
                                label: const Text('استفاده از این پاسخ'),
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

