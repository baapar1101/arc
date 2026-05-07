import 'package:flutter/material.dart';

import '../services/in_app_notification_preferences_controller.dart';
import '../services/notification_alert_sound_player.dart';
import '../utils/notification_sound_catalog.dart';
import 'in_app_notification_strings.dart';

/// بخش تنظیم حالت هشدار و انتخاب صدا برای ناتیفیکیشن درون‌برنامه‌ای.
class InAppNotificationBehaviorSection extends StatelessWidget {
  const InAppNotificationBehaviorSection({
    super.key,
    required this.enabled,
    required this.alertMode,
    required this.soundEnabled,
    required this.soundAssetId,
    required this.onAlertModeChanged,
    required this.onSoundEnabledChanged,
    required this.onSoundAssetChanged,
  });

  final bool enabled;
  final InAppAlertMode alertMode;
  final bool soundEnabled;
  final String soundAssetId;
  final ValueChanged<InAppAlertMode> onAlertModeChanged;
  final ValueChanged<bool> onSoundEnabledChanged;
  final ValueChanged<String> onSoundAssetChanged;

  String _soundLabel(BuildContext context, String id) {
    if (id == NotificationSoundCatalog.defaultId) {
      return InAppNotificationStrings.soundOptionDefault(context);
    }
    final m = RegExp(r'^s_(\d+)$').firstMatch(id);
    final n = m != null ? int.tryParse(m.group(1)!) : null;
    if (n != null) {
      return InAppNotificationStrings.soundOptionIndex(context, n);
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!enabled) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          InAppNotificationStrings.behaviorSectionTitle(context),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          InAppNotificationStrings.behaviorSectionSubtitle(context),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        SegmentedButton<InAppAlertMode>(
          segments: [
            ButtonSegment<InAppAlertMode>(
              value: InAppAlertMode.normal,
              label: Text(InAppNotificationStrings.modeNormal(context)),
              tooltip: InAppNotificationStrings.modeNormalHint(context),
            ),
            ButtonSegment<InAppAlertMode>(
              value: InAppAlertMode.silent,
              label: Text(InAppNotificationStrings.modeSilent(context)),
              tooltip: InAppNotificationStrings.modeSilentHint(context),
            ),
            ButtonSegment<InAppAlertMode>(
              value: InAppAlertMode.doNotDisturb,
              label: Text(InAppNotificationStrings.modeDnd(context)),
              tooltip: InAppNotificationStrings.modeDndHint(context),
            ),
          ],
          selected: {alertMode},
          onSelectionChanged: (set) {
            if (set.isEmpty) return;
            onAlertModeChanged(set.first);
          },
        ),
        if (alertMode == InAppAlertMode.normal) ...[
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(InAppNotificationStrings.soundToggle(context)),
            value: soundEnabled,
            onChanged: onSoundEnabledChanged,
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: soundAssetId,
                  decoration: InputDecoration(
                    labelText: InAppNotificationStrings.soundPickerLabel(context),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final id in NotificationSoundCatalog.selectableIds)
                      DropdownMenuItem(value: id, child: Text(_soundLabel(context, id))),
                  ],
                  onChanged: (v) {
                    if (v != null) onSoundAssetChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: InAppNotificationStrings.previewTooltip(context),
                onPressed: () => NotificationAlertSoundPlayer.previewSoundAssetId(soundAssetId),
                icon: const Icon(Icons.volume_up_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            InAppNotificationStrings.webSoundHint(context),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
