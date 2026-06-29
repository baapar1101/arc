import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';

/// نمایش محتوا فقط وقتی افزونه حقوق و دستمزد برای کسب‌وکار فعال است.
class PayrollPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const PayrollPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<PayrollPluginGate> createState() => _PayrollPluginGateState();
}

class _PayrollPluginGateState extends State<PayrollPluginGate> {
  static const String _pluginCode = 'payroll';

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
    final t = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_active) {
      return Scaffold(
        appBar: AppBar(title: Text(t.payrollMenu)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  t.payrollPluginNotActive,
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
