import 'package:flutter/material.dart';
import 'ai_chat_design.dart';

class AIChatSuggestion {
  final String label;
  final String prompt;
  final IconData icon;

  const AIChatSuggestion({
    required this.label,
    required this.prompt,
    required this.icon,
  });

  factory AIChatSuggestion.fromApi(Map<String, dynamic> json) {
    return AIChatSuggestion(
      label: json['label'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      icon: _iconFromApiName(json['icon'] as String?),
    );
  }

  static IconData _iconFromApiName(String? name) {
    switch (name) {
      case 'dashboard':
        return Icons.dashboard_outlined;
      case 'receipt':
        return Icons.receipt_long_outlined;
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'people':
        return Icons.people_outline_rounded;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'psychology':
        return Icons.psychology_outlined;
      case 'track_changes':
        return Icons.track_changes_outlined;
      case 'menu_book':
        return Icons.menu_book_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }
}

/// پیشنهادهای شروع گفتگو (ثابت — قابل گسترش از API در آینده).
const List<AIChatSuggestion> kDefaultAIChatSuggestions = [
  AIChatSuggestion(
    label: 'خلاصه فروش امروز',
    prompt: 'خلاصه‌ای از فروش و درآمد امروز کسب‌وکارم بده.',
    icon: Icons.trending_up_rounded,
  ),
  AIChatSuggestion(
    label: 'وضعیت موجودی انبار',
    prompt: 'وضعیت کلی موجودی انبار و کالاهای کم‌موجود را بررسی کن.',
    icon: Icons.inventory_2_outlined,
  ),
  AIChatSuggestion(
    label: 'راهنمای ثبت فاکتور',
    prompt: 'گام‌به‌گام نحوه ثبت فاکتور فروش در حسابیکس را توضیح بده.',
    icon: Icons.receipt_long_outlined,
  ),
  AIChatSuggestion(
    label: 'تحلیل بدهکاران',
    prompt: 'لیست بدهکاران مهم و پیشنهاد پیگیری را ارائه کن.',
    icon: Icons.people_outline_rounded,
  ),
  AIChatSuggestion(
    label: 'گزارش سود و زیان',
    prompt: 'چطور گزارش سود و زیان دوره جاری را بخوانم و تفسیر کنم؟',
    icon: Icons.pie_chart_outline_rounded,
  ),
  AIChatSuggestion(
    label: 'کمک در حسابداری',
    prompt: 'در ثبت سند حسابداری و انتخاب حساب‌ها راهنمایی‌ام کن.',
    icon: Icons.account_balance_outlined,
  ),
];

class AIChatSuggestionChips extends StatelessWidget {
  final List<AIChatSuggestion> suggestions;
  final ValueChanged<AIChatSuggestion> onSelected;
  final bool enabled;

  const AIChatSuggestionChips({
    super.key,
    this.suggestions = kDefaultAIChatSuggestions,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final compact = AIChatDesign.isCompactWidth(context);

    return Wrap(
      alignment: compact ? WrapAlignment.start : WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in suggestions)
          _SuggestionChip(
            suggestion: s,
            enabled: enabled,
            onTap: () => onSelected(s),
          ),
      ],
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  final AIChatSuggestion suggestion;
  final bool enabled;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.suggestion,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          borderRadius: BorderRadius.circular(AIChatDesign.chipRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: AIChatDesign.chipDecoration(theme).copyWith(
              color: _hovered && widget.enabled
                  ? scheme.primaryContainer.withValues(alpha: 0.55)
                  : null,
              border: Border.all(
                color: _hovered && widget.enabled
                    ? scheme.primary.withValues(alpha: 0.35)
                    : scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.suggestion.icon,
                    size: 16,
                    color: widget.enabled
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.suggestion.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: widget.enabled
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
