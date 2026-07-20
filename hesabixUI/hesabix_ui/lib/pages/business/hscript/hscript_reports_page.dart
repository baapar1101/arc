import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../services/hscript_report_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/hscript/hscript_plan_banner.dart';
import '../../../widgets/permission/access_denied_page.dart';

/// فهرست گزارش‌های سفارشی HScript.
class HScriptReportsPage extends StatefulWidget {
  const HScriptReportsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  final int businessId;
  final AuthStore authStore;

  @override
  State<HScriptReportsPage> createState() => _HScriptReportsPageState();
}

class _HScriptReportsPageState extends State<HScriptReportsPage> {
  late final HScriptReportService _service;
  bool _loading = true;
  String? _statusFilter;
  List<Map<String, dynamic>> _items = const [];

  bool get _canView => widget.authStore.hasBusinessPermission('reports', 'view');

  @override
  void initState() {
    super.initState();
    _service = HScriptReportService(ApiClient());
    if (_canView) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _service.listReports(
        businessId: widget.businessId,
        status: _statusFilter,
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

  void _openStudio({int? reportId}) {
    final tail = reportId == null ? 'hscript/studio/new' : 'hscript/studio/$reportId';
    context.go(context.businessPanelUrl(widget.businessId, tail));
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف گزارش'),
        content: Text('گزارش «${item['title'] ?? ''}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteReport(businessId: widget.businessId, reportId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'گزارش حذف شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AccessDeniedPage();
    }
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: businessSubpageBackLeading(context, widget.businessId),
        title: const Text('گزارش‌ساز اسکریپتی (HScript)'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openStudio(),
        icon: const Icon(Icons.add),
        label: const Text('گزارش جدید'),
      ),
      body: Column(
        children: [
          HScriptPlanBanner(businessId: widget.businessId, service: _service),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('همه'),
                  selected: _statusFilter == null,
                  onSelected: (_) {
                    setState(() => _statusFilter = null);
                    _load();
                  },
                ),
                for (final s in const ['draft', 'published', 'archived'])
                  FilterChip(
                    label: Text(_statusLabel(s)),
                    selected: _statusFilter == s,
                    onSelected: (_) {
                      setState(() => _statusFilter = s);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'هنوز گزارشی ساخته نشده است.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final status = item['status']?.toString() ?? 'draft';
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: cs.primaryContainer,
                                child: Icon(Icons.code, color: cs.onPrimaryContainer),
                              ),
                              title: Text(item['title']?.toString() ?? 'بدون عنوان'),
                              subtitle: Text('${item['slug'] ?? ''} · ${_statusLabel(status)}'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  final id = (item['id'] as num?)?.toInt();
                                  if (id == null) return;
                                  if (v == 'edit') _openStudio(reportId: id);
                                  if (v == 'delete') _delete(item);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('ویرایش / اجرا')),
                                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                                ],
                              ),
                              onTap: () {
                                final id = (item['id'] as num?)?.toInt();
                                if (id != null) _openStudio(reportId: id);
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'published':
        return 'منتشرشده';
      case 'archived':
        return 'بایگانی';
      case 'draft':
      default:
        return 'پیش‌نویس';
    }
  }
}
