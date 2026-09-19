import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';

/// نمایش محتوا فقط وقتی افزونه طراحی برچسب بارکد فعال است.
class BarcodeLabelPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const BarcodeLabelPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<BarcodeLabelPluginGate> createState() => _BarcodeLabelPluginGateState();
}

class _BarcodeLabelPluginGateState extends State<BarcodeLabelPluginGate> {
  static const String _pluginCode = 'barcode_label_studio';

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
      final active = row['is_active'] == true ||
          row['is_active'] == 1 ||
          (row['is_trial'] == true && row['is_expired'] != true);
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
        appBar: AppBar(title: Text(t.barcodeLabelsMenu)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t.barcodeLabelPluginNotActive,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t.barcodeLabelPluginNotActiveHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.go(
                      context.businessPanelUrl(widget.businessId, 'plugin-marketplace'),
                    ),
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(t.pluginMarketplace),
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
