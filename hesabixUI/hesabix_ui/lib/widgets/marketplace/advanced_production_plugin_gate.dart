import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';
import 'plugin_marketplace_utils.dart';

class AdvancedProductionPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const AdvancedProductionPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<AdvancedProductionPluginGate> createState() =>
      _AdvancedProductionPluginGateState();
}

class _AdvancedProductionPluginGateState
    extends State<AdvancedProductionPluginGate> {
  static const String pluginCode = 'advanced_production';
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
        (p) => p['plugin_code'] == pluginCode,
        orElse: () => <String, dynamic>{},
      );
      if (!mounted) return;
      setState(() {
        _active = marketplacePluginLicenseActive(row);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _active = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_active) {
      return Scaffold(
        appBar: AppBar(title: Text(t.advancedProductionMenu)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.factory_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t.advancedProductionPluginRequired,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.advancedProductionPluginRequiredBody,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.go(
                      context.businessPanelUrl(
                        widget.businessId,
                        'plugin-marketplace',
                      ),
                    ),
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(t.advancedProductionOpenMarketplace),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
