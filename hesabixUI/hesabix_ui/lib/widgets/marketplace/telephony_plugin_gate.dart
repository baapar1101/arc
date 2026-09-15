import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/business_nav.dart';
import '../../services/marketplace_service.dart';

/// نمایش محتوا فقط وقتی افزونه استریسک/ایزابل فعال است.
class TelephonyPluginGate extends StatefulWidget {
  final int businessId;
  final Widget child;

  const TelephonyPluginGate({
    super.key,
    required this.businessId,
    required this.child,
  });

  @override
  State<TelephonyPluginGate> createState() => _TelephonyPluginGateState();
}

class _TelephonyPluginGateState extends State<TelephonyPluginGate> {
  static const String _pluginCode = 'asterisk_issabel_connector';

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
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_active) {
      return Scaffold(
        appBar: AppBar(title: const Text('مرکز تماس')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.18),
                          scheme.tertiary.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                    child: Icon(Icons.phone_in_talk_rounded, size: 40, color: scheme.primary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'افزونه اتصال به استریسک و ایزابل فعال نیست',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'برای Screen Pop، Click-to-Call و تاریخچه تماس، این افزونه را از بازار افزونه‌ها فعال کنید.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'plugin-marketplace')),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('بازار افزونه‌ها'),
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
