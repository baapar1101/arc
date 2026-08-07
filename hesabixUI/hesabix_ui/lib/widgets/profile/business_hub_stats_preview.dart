import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';
import 'business_hub_stats_cache.dart';

class BusinessHubStatsPreview extends StatelessWidget {
  final BusinessStatistics? stats;
  final bool loading;
  final bool compact;

  const BusinessHubStatsPreview({
    super.key,
    this.stats,
    this.loading = false,
    this.compact = false,
  });

  static String _fmt(num value) {
    if (value.abs() >= 1e9) {
      return NumberFormat.compact(locale: 'fa').format(value);
    }
    return NumberFormat('#,##0', 'fa').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Text(
              t.businessesHubStatsLoading,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (stats == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          t.businessesHubStatsUnavailable,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final s = stats!;
    final items = [
      _StatItem(Icons.trending_up_rounded, t.businessesHubStatsSales, _fmt(s.totalSales), Colors.green),
      _StatItem(Icons.shopping_cart_outlined, t.businessesHubStatsPurchases, _fmt(s.totalPurchases), Colors.blue),
      _StatItem(Icons.people_outline_rounded, t.businessesHubStatsMembers, '${s.activeMembers}', Colors.purple),
      _StatItem(Icons.receipt_long_outlined, t.businessesHubStatsTransactions, '${s.recentTransactions}', Colors.orange),
    ];

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: items.map((e) => _compactChip(context, e)).toList(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: items
              .map(
                (e) => Expanded(
                  child: _statCell(context, e),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _statCell(BuildContext context, _StatItem item) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(item.icon, size: 18, color: item.color.shade700),
        const SizedBox(height: 4),
        Text(
          item.value,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _compactChip(BuildContext context, _StatItem item) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 14, color: item.color.shade700),
          const SizedBox(width: 4),
          Text(item.value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(width: 4),
          Text(item.label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final MaterialColor color;

  const _StatItem(this.icon, this.label, this.value, this.color);
}

/// محتوای bottom sheet آمار برای موبایل.
class BusinessHubStatsSheet extends StatefulWidget {
  final String businessName;
  final int businessId;
  final BusinessDashboardService service;

  const BusinessHubStatsSheet({
    super.key,
    required this.businessName,
    required this.businessId,
    required this.service,
  });

  static Future<void> show(
    BuildContext context, {
    required String businessName,
    required int businessId,
    required BusinessDashboardService service,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: BusinessHubStatsSheet(
            businessName: businessName,
            businessId: businessId,
            service: service,
          ),
        ),
      ),
    );
  }

  @override
  State<BusinessHubStatsSheet> createState() => _BusinessHubStatsSheetState();
}

class _BusinessHubStatsSheetState extends State<BusinessHubStatsSheet> {
  BusinessStatistics? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await BusinessHubStatsCache.load(widget.businessId, widget.service);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.businessesHubStatsTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          widget.businessName,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        BusinessHubStatsPreview(stats: _stats, loading: _loading),
        const SizedBox(height: 8),
      ],
    );
  }
}
