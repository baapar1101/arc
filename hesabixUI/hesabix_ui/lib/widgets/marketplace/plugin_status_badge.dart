import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'plugin_marketplace_utils.dart';

enum PluginLicenseVisualState { none, active, trial, trialExpired, expired, inactive }

PluginLicenseVisualState licenseVisualState(Map<String, dynamic>? status) {
  if (status == null || status.isEmpty) return PluginLicenseVisualState.none;
  final isTrial = status['is_trial'] == true;
  final trialDays = status['trial_remaining_days'] as int?;
  if (isTrial) {
    if (trialDays != null && trialDays > 0) return PluginLicenseVisualState.trial;
    return PluginLicenseVisualState.trialExpired;
  }
  if (status['is_active'] == true) return PluginLicenseVisualState.active;
  if (status['is_expired'] == true) return PluginLicenseVisualState.expired;
  return PluginLicenseVisualState.inactive;
}

class PluginStatusBadge extends StatelessWidget {
  final Map<String, dynamic>? pluginStatus;
  final bool compact;
  final bool showTrialProgress;
  /// مدت کل trial از تعریف افزونه (برای نوار پیشرفت)
  final int? totalTrialDays;

  const PluginStatusBadge({
    super.key,
    required this.pluginStatus,
    this.compact = false,
    this.showTrialProgress = true,
    this.totalTrialDays,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = licenseVisualState(pluginStatus);
    if (state == PluginLicenseVisualState.none) return const SizedBox.shrink();

    late Color bg;
    late Color fg;
    late IconData icon;
    late String label;

    switch (state) {
      case PluginLicenseVisualState.active:
        bg = cs.primaryContainer.withValues(alpha: 0.65);
        fg = cs.onPrimaryContainer;
        icon = Icons.check_circle_outline;
        label = t.pluginMarketplaceStatusActive;
        break;
      case PluginLicenseVisualState.trial:
        bg = cs.tertiaryContainer.withValues(alpha: 0.7);
        fg = cs.onTertiaryContainer;
        icon = Icons.hourglass_top_outlined;
        final days = pluginStatus?['trial_remaining_days'] as int? ?? 0;
        label = t.pluginMarketplaceStatusTrialDays(days);
        break;
      case PluginLicenseVisualState.trialExpired:
        bg = cs.errorContainer.withValues(alpha: 0.55);
        fg = cs.onErrorContainer;
        icon = Icons.hourglass_disabled_outlined;
        label = t.pluginMarketplaceStatusTrialExpired;
        break;
      case PluginLicenseVisualState.expired:
        bg = cs.errorContainer.withValues(alpha: 0.45);
        fg = cs.onErrorContainer;
        icon = Icons.event_busy_outlined;
        label = t.pluginMarketplaceStatusExpired;
        break;
      case PluginLicenseVisualState.inactive:
        bg = cs.surfaceContainerHighest.withValues(alpha: 0.8);
        fg = cs.onSurfaceVariant;
        icon = Icons.pause_circle_outline;
        label = t.pluginMarketplaceStatusInactive;
        break;
      case PluginLicenseVisualState.none:
        return const SizedBox.shrink();
    }

    final remaining = pluginStatus?['trial_remaining_days'] as int?;
    final totalTrial = totalTrialDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 14 : 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (showTrialProgress &&
            state == PluginLicenseVisualState.trial &&
            remaining != null &&
            totalTrial != null &&
            totalTrial > 0) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (remaining / totalTrial).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
        if (pluginStatus?['ends_at'] != null &&
            state != PluginLicenseVisualState.none &&
            !compact) ...[
          const SizedBox(height: 4),
          Text(
            t.pluginMarketplaceExpiresAt(
              formatPluginEndsAt(pluginStatus!['ends_at']),
            ),
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// نوار وضعیت رنگی بالای کارت
class PluginStatusStrip extends StatelessWidget {
  final Map<String, dynamic>? pluginStatus;

  const PluginStatusStrip({super.key, required this.pluginStatus});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = licenseVisualState(pluginStatus);
    if (state == PluginLicenseVisualState.none) return const SizedBox.shrink();

    Color color;
    switch (state) {
      case PluginLicenseVisualState.active:
        color = cs.primary;
        break;
      case PluginLicenseVisualState.trial:
        color = cs.tertiary;
        break;
      case PluginLicenseVisualState.trialExpired:
      case PluginLicenseVisualState.expired:
        color = cs.error;
        break;
      case PluginLicenseVisualState.inactive:
        color = cs.outline;
        break;
      case PluginLicenseVisualState.none:
        return const SizedBox.shrink();
    }

    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
    );
  }
}
