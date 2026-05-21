import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';

/// نمایش محتوا فقط وقتی افزونه مودیان برای کسب‌وکار فعال است.
class MoadianPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const MoadianPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<MoadianPluginGate> createState() => _MoadianPluginGateState();
}

class _MoadianPluginGateState extends State<MoadianPluginGate> {
  static const String _pluginCode = 'moadian_tax_integration';

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
      final plugins = await _marketplace.listBusinessPlugins(
        businessId: widget.businessId,
      );
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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.moadianPluginInactiveTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t.moadianPluginInactiveMessage,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      const returnTo = 'tax-workspace';
                      final sep = marketplacePath.contains('?') ? '&' : '?';
                      context.push('$marketplacePath${sep}returnTo=${Uri.encodeComponent(returnTo)}');
                    },
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(t.moadianPluginGoToMarketplace),
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
