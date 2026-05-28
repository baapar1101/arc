import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';

/// نمایش محتوا فقط وقتی افزونه پخش مویرگی برای کسب‌وکار فعال است.
class DistributionPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const DistributionPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<DistributionPluginGate> createState() => _DistributionPluginGateState();
}

class _DistributionPluginGateState extends State<DistributionPluginGate> {
  static const String _pluginCode = 'distribution';

  final MarketplaceService _marketplace = MarketplaceService();
  bool _loading = true;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plugins = await _marketplace.listBusinessPlugins(businessId: widget.businessId);
      final row = plugins.cast<Map>().firstWhere(
        (p) => p['plugin_code'] == _pluginCode,
        orElse: () => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _active = row['is_active'] == true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _active = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_active) {
      return widget.child;
    }

    final t = AppLocalizations.of(context);
    final marketplacePath = context.businessPanelUrl(widget.businessId, 'plugin-marketplace');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.distributionPluginInactiveTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.distributionPluginInactiveMessage,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      const returnTo = 'distribution';
                      final sep = marketplacePath.contains('?') ? '&' : '?';
                      context.push('$marketplacePath${sep}returnTo=${Uri.encodeComponent(returnTo)}');
                    },
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(t.distributionPluginGoToMarketplace),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
