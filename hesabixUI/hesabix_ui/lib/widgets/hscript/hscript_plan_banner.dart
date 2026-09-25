import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/business_nav.dart';
import '../../services/hscript_report_service.dart';

/// بنر ارتقا وقتی افزونه HScript فعال نیست (سقف رایگان).
class HScriptPlanBanner extends StatefulWidget {
  const HScriptPlanBanner({
    super.key,
    required this.businessId,
    required this.service,
  });

  final int businessId;
  final HScriptReportService service;

  @override
  State<HScriptPlanBanner> createState() => _HScriptPlanBannerState();
}

class _HScriptPlanBannerState extends State<HScriptPlanBanner> {
  Map<String, dynamic>? _plan;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plan = await widget.service.getPlanStatus(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (_) {
      // بنر اختیاری است؛ خطا را نادیده می‌گیریم
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _plan == null) return const SizedBox.shrink();
    if (_plan!['plugin_active'] == true) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final maxReports = _plan!['max_saved_reports'];
    final used = _plan!['saved_reports_count'];
    final hint = _plan!['upgrade_hint']?.toString() ??
        'برای سقف بالاتر، افزونه گزارش‌ساز اسکریپتی را فعال کنید.';

    return Material(
      color: cs.secondaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.workspace_premium_outlined, color: cs.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$hint'
                '${maxReports != null ? ' (گزارش‌ها: ${used ?? 0}/$maxReports)' : ''}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSecondaryContainer,
                    ),
              ),
            ),
            TextButton(
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'plugin-marketplace'),
              ),
              child: const Text('بازار افزونه‌ها'),
            ),
            IconButton(
              tooltip: 'بستن',
              onPressed: () => setState(() => _dismissed = true),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
