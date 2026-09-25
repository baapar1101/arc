import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';

import '../../services/hscript_report_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

Future<Map<String, dynamic>?> showHScriptVersionsSheet({
  required BuildContext context,
  required int businessId,
  required int reportId,
  required HScriptReportService service,
}) {
  return showGlassModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _VersionsSheet(
      businessId: businessId,
      reportId: reportId,
      service: service,
    ),
  );
}

class _VersionsSheet extends StatefulWidget {
  const _VersionsSheet({
    required this.businessId,
    required this.reportId,
    required this.service,
  });

  final int businessId;
  final int reportId;
  final HScriptReportService service;

  @override
  State<_VersionsSheet> createState() => _VersionsSheetState();
}

class _VersionsSheetState extends State<_VersionsSheet> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = const [];
  int? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.service.listVersions(
        businessId: widget.businessId,
        reportId: widget.reportId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _preview(int versionId) async {
    setState(() {
      _busy = true;
      _expandedId = versionId;
    });
    try {
      final detail = await widget.service.getVersion(
        businessId: widget.businessId,
        reportId: widget.reportId,
        versionId: versionId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _items = _items.map((e) {
          if ((e['id'] as num?)?.toInt() == versionId) {
            return {...e, 'source_code': detail['source_code']};
          }
          return e;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بازگردانی نسخه'),
        content: Text(
          'نسخه ${item['version_no']} روی گزارش فعلی اعمال شود؟\n'
          'تاریخچه حفظ می‌شود و در صورت انتشار، گزارش به پیش‌نویس برمی‌گردد.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بازگردانی')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final restored = await widget.service.restoreVersion(
        businessId: widget.businessId,
        reportId: widget.reportId,
        versionId: id,
      );
      if (!mounted) return;
      Navigator.pop(context, restored);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('تاریخچه نسخه‌ها', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: 'بازنشانی',
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                            'هنوز نسخه‌ای ثبت نشده است.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final id = (item['id'] as num?)?.toInt();
                            final expanded = id != null && _expandedId == id;
                            final code = item['source_code']?.toString() ?? item['source_preview']?.toString() ?? '';
                            return Material(
                              color: cs.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: cs.primaryContainer,
                                          child: Text(
                                            '${item['version_no'] ?? '?'}',
                                            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['changelog']?.toString().isNotEmpty == true
                                                    ? item['changelog'].toString()
                                                    : 'نسخه ${item['version_no']}',
                                              ),
                                              Text(
                                                item['created_at']?.toString() ?? '',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _busy || id == null ? null : () => _preview(id),
                                          child: Text(expanded ? 'جزئیات' : 'مشاهده'),
                                        ),
                                        FilledButton.tonal(
                                          onPressed: _busy ? null : () => _restore(item),
                                          child: const Text('بازگردانی'),
                                        ),
                                      ],
                                    ),
                                    if (expanded && code.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        constraints: const BoxConstraints(maxHeight: 220),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: SingleChildScrollView(
                                          child: Text(
                                            code,
                                            textDirection: TextDirection.ltr,
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11.5,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
