import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';

/// محتوا فقط وقتی افزونه تدارکات برای کسب‌وکار فعال است نشان داده می‌شود.
class ProcurementPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const ProcurementPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<ProcurementPluginGate> createState() => _ProcurementPluginGateState();
}

class _ProcurementPluginGateState extends State<ProcurementPluginGate> {
  static const String _pluginCode = 'procurement';

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
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_active) {
      return Scaffold(
        appBar: AppBar(title: Text(fa ? 'تدارکات' : 'Procurement')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  fa ? 'افزونه مدیریت خرید و تدارکات برای این کسب‌وکار فعال نیست.' : 'The procurement plugin is not active for this business.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'plugin-marketplace')),
                  child: Text(fa ? 'بازار افزونه‌ها' : 'Plugin marketplace'),
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
