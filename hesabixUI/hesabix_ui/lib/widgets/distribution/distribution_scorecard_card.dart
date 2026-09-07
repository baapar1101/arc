import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

class DistributionScorecardCard extends StatelessWidget {
  const DistributionScorecardCard({super.key, required this.kpi});

  final Map<String, dynamic> kpi;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final score = kpi['scorecard_score'];
    String fmt(dynamic v) => v == null ? '—' : '$v';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.distributionScorecard, style: Theme.of(context).textTheme.titleMedium)),
                CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    score == null ? '—' : '${(score is num) ? score.round() : score}',
                    style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(t.distributionTimeInStore, fmt(kpi['time_in_store_avg_minutes'])),
                _chip(t.distributionLinesPerInvoice, fmt(kpi['lines_per_invoice'])),
                _chip(t.distributionMissedVisits, fmt(kpi['missed_visits'])),
                _chip(t.distributionPerfectStore, fmt(kpi['perfect_store_avg'])),
                if (kpi['coverage_percent'] != null) _chip(t.distributionKpiCoverage, fmt(kpi['coverage_percent'])),
                if (kpi['strike_rate_percent'] != null) _chip(t.distributionKpiStrike, fmt(kpi['strike_rate_percent'])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }
}
