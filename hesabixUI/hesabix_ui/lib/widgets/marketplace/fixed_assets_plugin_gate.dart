import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';
import 'plugin_marketplace_utils.dart';

/// نمایش محتوا فقط وقتی افزونه کنترل اموال برای کسب‌وکار فعال است.
class FixedAssetsPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const FixedAssetsPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<FixedAssetsPluginGate> createState() => _FixedAssetsPluginGateState();
}

class _FixedAssetsPluginGateState extends State<FixedAssetsPluginGate> {
  static const String _pluginCode = 'fixed_assets';

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
      final active = marketplacePluginLicenseActive(row);
      if (mounted) {
        setState(() {
          _active = active;
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
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_active) {
      return Scaffold(
        appBar: AppBar(title: Text(t.fixedAssetsMenu)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  t.fixedAssetsPluginNotActive,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'plugin-marketplace')),
                  icon: const Icon(Icons.storefront_outlined),
                  label: Text(t.pluginMarketplace),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
