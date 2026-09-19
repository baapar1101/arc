import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_ui_helpers.dart';

class DistributionCustomer360Card extends StatefulWidget {
  const DistributionCustomer360Card({
    super.key,
    required this.businessId,
    required this.personId,
    required this.service,
    this.navProvider = 'neshan',
    this.onAddSuggested,
  });

  final int businessId;
  final int personId;
  final DistributionService service;
  final String navProvider;
  final VoidCallback? onAddSuggested;

  @override
  State<DistributionCustomer360Card> createState() => _DistributionCustomer360CardState();
}

class _DistributionCustomer360CardState extends State<DistributionCustomer360Card> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.service.getCustomer360(
        businessId: widget.businessId,
        personId: widget.personId,
      );
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted) setState(() => _data = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final credit = d['credit'] is Map ? Map<String, dynamic>.from(d['credit'] as Map) : <String, dynamic>{};
    final blocked = credit['blocked'] == true;
    final last = d['last_visit'] is Map ? Map<String, dynamic>.from(d['last_visit'] as Map) : null;
    final must = d['must_sell'] is List ? d['must_sell'] as List : const [];
    final lat = double.tryParse('${d['latitude']}');
    final lng = double.tryParse('${d['longitude']}');
    final phone = d['mobile']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.distributionCustomer360Title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(d['person_name']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
            if ((d['address'] ?? '').toString().isNotEmpty)
              Text(d['address'].toString(), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(blocked ? Icons.block : Icons.account_balance_wallet_outlined, size: 16),
                  label: Text(
                    '${t.distributionCreditAvailable}: ${credit['available_credit'] ?? '—'}',
                  ),
                  backgroundColor: blocked
                      ? SemanticColorResolver.negative(context).withValues(alpha: 0.12)
                      : cs.surfaceContainerHighest,
                ),
                if (last != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${t.distributionLastVisit}: ${last['outcome'] ?? last['status'] ?? '—'}'),
                  ),
                if (must.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.star_outline, size: 16),
                    label: Text('${t.distributionMustSell}: ${must.length}'),
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
                    onPressed: () => openDistributionMapsNavigation(lat, lng, provider: widget.navProvider),
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: Text(t.distributionNavigate),
                  ),
                if (widget.onAddSuggested != null)
                  TextButton.icon(
                    onPressed: widget.onAddSuggested,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(t.distributionAddSuggested),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
