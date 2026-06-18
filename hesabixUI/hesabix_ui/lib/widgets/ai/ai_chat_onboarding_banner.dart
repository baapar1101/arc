import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// راهنمای یک‌بار مصرف — یک خط کوچک به‌جای بنر بزرگ.
class AIChatOnboardingBanner extends StatefulWidget {
  final int? businessId;

  const AIChatOnboardingBanner({super.key, this.businessId});

  static Future<bool> isDismissed(int? businessId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey(businessId)) ?? false;
  }

  static String _prefsKey(int? businessId) =>
      'ai_chat_onboarding_dismissed_${businessId ?? 0}';

  @override
  State<AIChatOnboardingBanner> createState() => _AIChatOnboardingBannerState();
}

class _AIChatOnboardingBannerState extends State<AIChatOnboardingBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dismissed = await AIChatOnboardingBanner.isDismissed(widget.businessId);
    if (mounted) setState(() => _visible = !dismissed);
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      AIChatOnboardingBanner._prefsKey(widget.businessId),
      true,
    );
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: scheme.primary, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'با / دستورات سریع · میکروفون · تأیید قبل از ثبت',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'بستن',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: _dismiss,
            icon: Icon(Icons.close_rounded, size: 16, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
