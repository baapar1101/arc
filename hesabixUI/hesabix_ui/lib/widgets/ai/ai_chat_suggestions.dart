import 'package:flutter/material.dart';
import 'package:hesabix_ui/config/brand_config.dart';
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

/// پیشنهادهای شروع گفتگو — هم‌راستا با کلیدهای insight در API.
const List<AIChatSuggestion> kDefaultAIChatSuggestions = [
  AIChatSuggestion(
    label: 'خلاصه وضعیت امروز',
    prompt: 'با توجه به داده‌های لحظه‌ای و toolها، خلاصه وضعیت مالی امروز کسب‌وکارم را بده.',
    icon: Icons.dashboard_outlined,
  ),
  AIChatSuggestion(
    label: 'هشدار موجودی',
    prompt: 'کالاهای کم‌موجود را با get_inventory_status لیست کن و پیشنهاد سفارش مجدد بده.',
    icon: Icons.inventory_2_outlined,
  ),
  AIChatSuggestion(
    label: 'راهنمای ثبت فاکتور',
    prompt: 'گام‌به‌گام نحوه ثبت فاکتور فروش در حسابیکس را توضیح بده.',
    icon: Icons.receipt_long_outlined,
  ),
  AIChatSuggestion(
    label: 'پیگیری بدهکاران',
    prompt: 'مهم‌ترین بدهکاران را با get_debtors_report و aging بده و پیشنهاد پیگیری بده.',
    icon: Icons.people_outline_rounded,
  ),
  AIChatSuggestion(
    label: 'گزارش سود و زیان',
    prompt: 'گزارش سود و زیان دوره جاری را با get_report(pnl_period) بخوان و به زبان ساده تفسیر کن.',
    icon: Icons.pie_chart_outline_rounded,
  ),
  AIChatSuggestion(
    label: 'کمک در حسابداری',
    prompt: 'در ثبت سند حسابداری، انتخاب حساب‌ها و تفاوت سند با فاکتور در حسابیکس راهنمایی‌ام کن.',
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
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in suggestions)
          _SuggestionChip(
            suggestion: s,
            enabled: enabled,
            onTap: () => onSelected(
              AIChatSuggestion(
                label: s.label,
                prompt: BrandConfig.rebrand(s.prompt),
                icon: s.icon,
              ),
            ),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: AIChatDesign.chipDecoration(theme).copyWith(
              color: _hovered && widget.enabled
                  ? scheme.surfaceContainerHigh
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border.all(
                color: _hovered && widget.enabled
                    ? scheme.outlineVariant.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              widget.suggestion.label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: widget.enabled
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
