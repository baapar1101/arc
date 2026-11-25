import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'distribution_field_helpers.dart';
import 'distribution_ui_helpers.dart';

/// کارت یک توقف برنامه روز در تب میدانی.
class DistributionPlanStopCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;
  final String kind;
  final bool isNext;
  final bool canOperate;
  final bool canManage;
  final Map<String, dynamic>? activeVisit;
  final String navProvider;
  final VoidCallback? onStartVisit;
  final VoidCallback? onCompleteVisit;
  final VoidCallback? onSetPersonLocation;

  const DistributionPlanStopCard({
    super.key,
    required this.item,
    required this.index,
    required this.kind,
    required this.isNext,
    required this.canOperate,
    required this.canManage,
    required this.activeVisit,
    required this.navProvider,
    this.onStartVisit,
    this.onCompleteVisit,
    this.onSetPersonLocation,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final lat = double.tryParse('${item['latitude']}');
    final lng = double.tryParse('${item['longitude']}');
    final phone = item['person_mobile']?.toString();
    final kindLabel = kind == 'done'
        ? t.distributionStopDone
        : kind == 'current'
            ? t.distributionStopCurrent
            : t.distributionStopPending;
    final kindColor = kind == 'done'
        ? cs.primary
        : kind == 'current'
            ? cs.tertiary
            : cs.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        elevation: isNext && kind == 'pending' ? 1 : 0,
        color: kind == 'current'
            ? cs.tertiaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: kindColor.withValues(alpha: 0.15),
                    foregroundColor: kindColor,
                    child: Text('${item['sort_order'] ?? index + 1}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['person_name'] ?? item['person_id']}',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${item['route_code'] ?? ''} · ${item['route_name'] ?? ''}',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (item['carried_over'] == true)
                          Text(
                            t.distributionCarriedOver,
                            style: theme.textTheme.labelSmall?.copyWith(color: cs.tertiary),
                          ),
                        if (item['customer_class'] != null || item['frequency'] != null)
                          Text(
                            [
                              if (item['customer_class'] != null)
                                distributionClassLabel(t, item['customer_class']?.toString()),
                              if (item['frequency'] != null)
                                distributionFrequencyLabel(t, item['frequency']?.toString()),
                            ].join(' · '),
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(kindLabel, style: TextStyle(color: kindColor, fontSize: 12)),
                    side: BorderSide(color: kindColor.withValues(alpha: 0.4)),
                    backgroundColor: kindColor.withValues(alpha: 0.08),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  if (phone != null && phone.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => openDistributionPhoneDialer(phone),
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: Text(t.distributionCallCustomer),
                    ),
                  if (lat != null && lng != null)
                    TextButton.icon(
                      onPressed: () => openDistributionMapsNavigation(lat, lng, provider: navProvider),
                      icon: const Icon(Icons.navigation_outlined, size: 18),
                      label: Text(t.distributionNavigate),
                    ),
                  if (canManage)
                    TextButton.icon(
                      onPressed: onSetPersonLocation,
                      icon: Icon(
                        item['latitude'] != null
                            ? Icons.edit_location_alt
                            : Icons.add_location_alt_outlined,
                        size: 18,
                      ),
                      label: Text(t.distributionSetPersonLocation),
                    ),
                ],
              ),
              if (canOperate && activeVisit == null && kind != 'done') ...[
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: onStartVisit,
                  child: Text(t.distributionStartVisit),
                ),
              ],
              if (canOperate && kind == 'current' && activeVisit != null) ...[
                const SizedBox(height: 4),
                FilledButton.tonal(
                  onPressed: onCompleteVisit,
                  child: Text(t.distributionCompleteVisitCta),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
