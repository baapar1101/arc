import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/distribution/distribution_ui_helpers.dart';

class DistributionReturnsTab extends StatelessWidget {
  final AppLocalizations t;
  final bool loading;
  final bool pendingOnly;
  final bool canApproveReturns;
  final List<dynamic> returns;
  final ValueChanged<bool> onPendingOnlyChanged;
  final Future<void> Function() onRefresh;
  final void Function(int id, String status) onResolve;

  const DistributionReturnsTab({
    super.key,
    required this.t,
    required this.loading,
    required this.pendingOnly,
    required this.canApproveReturns,
    required this.returns,
    required this.onPendingOnlyChanged,
    required this.onRefresh,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final filtered = pendingOnly
        ? returns.where((r) => Map<String, dynamic>.from(r as Map)['status'] == 'pending').toList()
        : returns;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(t.distributionFilterPending), icon: const Icon(Icons.hourglass_top)),
                  ButtonSegment(value: false, label: Text(t.distributionFilterAll), icon: const Icon(Icons.list)),
                ],
                selected: {pendingOnly},
                onSelectionChanged: (s) => onPendingOnlyChanged(s.first),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: distributionEmptyState(
                context: context,
                icon: Icons.assignment_return_outlined,
                title: t.distributionEmptyReturns,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final r = Map<String, dynamic>.from(filtered[i] as Map);
                  final lines = (r['lines'] as List?) ?? [];
                  final pending = r['status'] == 'pending';
                  return Card(
                    elevation: 0,
                    child: ExpansionTile(
                      leading: Icon(
                        pending ? Icons.hourglass_top : Icons.assignment_return,
                        color: distributionStatusColor(context, r['status']?.toString()),
                      ),
                      title: Text('#${r['id']} · ${r['person_name'] ?? '${t.distributionSelectPerson} ${r['person_id']}'}'),
                      subtitle: Text('${distributionReturnStatusLabel(t, r['status']?.toString())} · ${lines.length} ${t.distributionReturnAddLine}'),
                      trailing: pending && canApproveReturns
                          ? null
                          : distributionStatusChip(context, t, r['status']?.toString(), isReturn: true),
                      children: [
                        ...lines.map((ln) {
                          final m = Map<String, dynamic>.from(ln as Map);
                          return ListTile(
                            dense: true,
                            title: Text(m['product_name']?.toString() ?? 'product ${m['product_id']}'),
                            subtitle: Text('× ${m['quantity']} ${m['reason'] ?? ''}'),
                          );
                        }),
                        if (pending && canApproveReturns)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => onResolve(int.parse('${r['id']}'), 'rejected'),
                                    child: Text(t.distributionRejectReturn),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => onResolve(int.parse('${r['id']}'), 'approved'),
                                    child: Text(t.distributionApproveReturn),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
