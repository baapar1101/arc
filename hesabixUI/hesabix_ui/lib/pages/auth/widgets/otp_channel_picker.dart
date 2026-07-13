import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// انتخاب کانال OTP — کارت‌های قابل کلیک به‌جای RadioListTile.
class OtpChannelPicker extends StatelessWidget {
  final List<String> channels;
  final Map<String, bool> channelOnServer;
  final String? selected;
  final bool loading;
  final ValueChanged<String> onSelected;

  const OtpChannelPicker({
    super.key,
    required this.channels,
    required this.channelOnServer,
    required this.selected,
    required this.loading,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final names = {
      'sms': t.otpChannelSms,
      'email': t.otpChannelEmail,
      'telegram': t.otpChannelTelegram,
      'bale': 'بله',
    };
    final icons = {
      'sms': Icons.sms_outlined,
      'email': Icons.email_outlined,
      'telegram': Icons.telegram,
      'bale': Icons.chat_bubble_outline,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.otpChannelSelectionTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: channels.map((channel) {
            final enabled = channelOnServer[channel] == true && !loading;
            final isSelected = selected == channel;
            final color = isSelected ? scheme.primary : scheme.outlineVariant;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? () => onSelected(channel) : null,
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 100,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primaryContainer.withValues(alpha: 0.5)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: color,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icons[channel] ?? Icons.send,
                        color: enabled ? (isSelected ? scheme.primary : scheme.onSurfaceVariant) : scheme.outline,
                        size: 26,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        names[channel] ?? channel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: enabled ? scheme.onSurface : scheme.outline,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            ),
                      ),
                      if (!enabled)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            t.authChannelUnavailable,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.outline,
                                  fontSize: 10,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
