import 'package:flutter/material.dart';

import '../../../core/date_utils.dart' as Hd;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/distribution/distribution_field_helpers.dart';
import '../../../widgets/distribution/distribution_ui_helpers.dart';

class DistributionVisitsTab extends StatelessWidget {
  final AppLocalizations t;
  final bool jalali;
  final bool loading;
  final bool canOperate;
  final Map<String, dynamic>? visitListPayload;
  final Future<void> Function() onRefresh;
  final VoidCallback onGoToField;
  final void Function(int visitId, int? personId) onCompleteVisit;

  const DistributionVisitsTab({
    super.key,
    required this.t,
    required this.jalali,
    required this.loading,
    required this.canOperate,
    required this.visitListPayload,
    required this.onRefresh,
    required this.onGoToField,
    required this.onCompleteVisit,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final items = (visitListPayload?['items'] as List?) ?? [];
    if (items.isEmpty) {
      return distributionEmptyState(
        context: context,
        icon: Icons.place_outlined,
        title: t.distributionEmptyVisits,
        subtitle: t.distributionEmptyVisitsHint,
        action: FilledButton.tonal(
          onPressed: onGoToField,
          child: Text(t.distributionGoToField),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final v = Map<String, dynamic>.from(items[i] as Map);
          final status = v['status']?.toString();
          return Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: ListTile(
              leading: Icon(
                status == 'completed'
                    ? Icons.check_circle
                    : status == 'cancelled'
                        ? Icons.cancel
                        : Icons.timelapse,
                color: distributionStatusColor(context, status),
              ),
              title: Text(v['person_name']?.toString() ?? '${v['person_id']}'),
              subtitle: Text(
                '${distributionOutcomeLabel(t, v['outcome']?.toString())}\n'
                '${Hd.HesabixDateUtils.formatDateTime(distributionParseDt(v['started_at']), jalali)}',
              ),
              isThreeLine: true,
              trailing: status == 'in_progress' && canOperate
                  ? FilledButton(
                      onPressed: () => onCompleteVisit(
                        int.parse('${v['id']}'),
                        int.tryParse('${v['person_id']}'),
                      ),
                      child: Text(t.distributionCompleteVisitCta),
                    )
                  : distributionStatusChip(context, t, status),
            ),
          );
        },
      ),
    );
  }
}
