import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_design.dart';

/// بنر تأیید عملیات نوشتنی پیشنهادی توسط دستیار AI.
class AIWriteApprovalBanner extends StatelessWidget {
  final List<Map<String, dynamic>> pendingOps;
  final bool loading;
  final bool canConfirm;
  final String? blockedReason;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const AIWriteApprovalBanner({
    super.key,
    required this.pendingOps,
    required this.loading,
    this.canConfirm = true,
    this.blockedReason,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final accent = scheme.primary;
    final surface = isDark ? scheme.surfaceContainerHigh : scheme.surface;
    final borderGradient = LinearGradient(
      colors: [
        accent.withValues(alpha: 0.55),
        scheme.tertiary.withValues(alpha: 0.45),
      ],
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AIChatDesign.cardRadius),
        gradient: borderGradient,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AIChatDesign.cardRadius - 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.18),
                          scheme.tertiary.withValues(alpha: 0.14),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.verified_user_rounded,
                      color: accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تأیید عملیات',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          pendingOps.length <= 1
                              ? 'دستیار می‌خواهد تغییری در داده‌های کسب‌وکار شما ثبت کند. قبل از اجرا، جزئیات را بررسی کنید.'
                              : '${pendingOps.length} عملیات در صف اجرا منتظر تأیید شماست.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!canConfirm && blockedReason != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: scheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          blockedReason!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onErrorContainer,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (pendingOps.isNotEmpty)
              ...pendingOps.map(
                (op) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: WriteApprovalOpCard(op: op),
                ),
              )
            else if (canConfirm)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: _SecurityNote(scheme: scheme, theme: theme),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: loading ? null : onDismiss,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Text(
                        'رد کردن',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: (loading || !canConfirm) ? null : onConfirm,
                      icon: loading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline_rounded, size: 20),
                      label: Text(
                        loading ? 'در حال ارسال…' : 'تأیید و اجرا',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: accent,
                        foregroundColor: scheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (pendingOps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: _SecurityNote(scheme: scheme, theme: theme),
              ),
          ],
        ),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  final ColorScheme scheme;
  final ThemeData theme;

  const _SecurityNote({required this.scheme, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: scheme.outline,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'فقط همان عملیاتی اجرا می‌شود که در این پیشنهاد آمده؛ تغییر پارامترها بدون تأیید مجدد ممکن نیست.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// کارت نمایش یک عملیات در انتظار تأیید.
class WriteApprovalOpCard extends StatefulWidget {
  final Map<String, dynamic> op;

  const WriteApprovalOpCard({super.key, required this.op});

  @override
  State<WriteApprovalOpCard> createState() => _WriteApprovalOpCardState();
}

class _WriteApprovalOpCardState extends State<WriteApprovalOpCard> {
  bool _expanded = false;

  static const _hiddenKeys = {'error', 'status', 'message'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = widget.op['label'] as String? ??
        widget.op['function'] as String? ??
        'عملیات';
    final rawArgs = widget.op['arguments'];
    final args = rawArgs is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawArgs)
        : rawArgs is Map
            ? Map<String, dynamic>.from(rawArgs)
            : <String, dynamic>{};
    final displayArgs = Map<String, dynamic>.from(args)
      ..removeWhere((k, v) => _hiddenKeys.contains(k) || v == null || '$v'.isEmpty);
    final previewEntries = displayArgs.entries.take(3).toList();
    final hasMore = displayArgs.length > 3;

    return Material(
      color: scheme.surfaceContainerLowest.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.5 : 0.85,
      ),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: displayArgs.isEmpty ? null : () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.edit_note_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (displayArgs.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 20,
                      color: scheme.outline,
                    ),
                ],
              ),
              if (!_expanded && previewEntries.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...previewEntries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${_formatArgKey(e.key)}: ${_formatArgValue(e.value)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'و ${displayArgs.length - 3} فیلد دیگر…',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
              if (_expanded && displayArgs.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...displayArgs.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            _formatArgKey(e.key),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatArgValue(e.value),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatArgKey(String key) {
    const labels = {
      'name': 'نام',
      'type': 'نوع',
      'amount': 'مبلغ',
      'total': 'جمع',
      'description': 'توضیحات',
      'date': 'تاریخ',
      'person_id': 'شناسه شخص',
      'product_id': 'شناسه کالا',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  String _formatArgValue(dynamic value) {
    if (value is Map || value is List) {
      return value.toString();
    }
    return value.toString();
  }
}
