import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_chat_design.dart';

/// بنر راهنمای یک‌بار مصرف برای دستورات سریع و ورودی صوتی.
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(AIChatDesign.cardRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: scheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'نکته‌های سریع',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'با / دستورات آماده را ببینید، از میکروفون برای گفت‌وگوی صوتی استفاده کنید، و برای ثبت یا ویرایش همیشه تأیید جداگانه می‌گیرید.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'بستن',
                onPressed: _dismiss,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
