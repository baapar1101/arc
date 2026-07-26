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
import '../../../widgets/hscript/hscript_schedules_sheet.dart';
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

  bool get _canView => widget.authStore.canViewHScript();
  bool get _canWrite => widget.authStore.canWriteHScript();
  bool get _canPublish => widget.authStore.canPublishHScript();
  bool get _canSchedule => widget.authStore.canScheduleHScript();

  @override
  void initState() {
    super.initState();
    _service = HScriptReportService(ApiClient());
    if (_canView) {
      // Dual-mode: بدون write فقط منتشرشده‌ها
      if (!_canWrite) _statusFilter = 'published';
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

  void _openRun(int reportId) {
    context.go(context.businessPanelUrl(widget.businessId, 'hscript/run/$reportId'));
  }

  void _openItem(Map<String, dynamic> item) {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final status = item['status']?.toString() ?? 'draft';
    if (_canWrite) {
      _openStudio(reportId: id);
    } else if (status == 'published') {
      _openRun(id);
    }
  }

  Future<void> _openSchedule(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    if (item['status']?.toString() != 'published') {
      SnackBarHelper.showError(context, message: 'فقط گزارش منتشرشده قابل زمان‌بندی است');
      return;
    }
    await showHScriptSchedulesSheet(
      context: context,
      businessId: widget.businessId,
      reportId: id,
      reportTitle: item['title']?.toString() ?? 'گزارش',
      service: _service,
    );
  }

  Future<void> _archive(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بایگانی گزارش'),
        content: Text('گزارش «${item['title'] ?? ''}» بایگانی شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بایگانی')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.archiveReport(businessId: widget.businessId, reportId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'گزارش بایگانی شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
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
        title: Text(_canWrite ? 'گزارش‌ساز اسکریپتی (HScript)' : 'گزارش‌های اسکریپتی'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openStudio(),
              icon: const Icon(Icons.add),
              label: const Text('گزارش جدید'),
            )
          : null,
      body: Column(
        children: [
          HScriptPlanBanner(businessId: widget.businessId, service: _service),
          if (!_canWrite)
            Material(
              color: cs.secondaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'حالت اجرا: فقط گزارش‌های منتشرشده را با پارامتر اجرا می‌کنید.',
                        style: TextStyle(color: cs.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_canWrite)
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
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.dashboard_customize_outlined, size: 48, color: cs.primary),
                              const SizedBox(height: 12),
                              Text(
                                _canWrite ? 'هنوز گزارشی ساخته نشده است' : 'گزارش منتشرشده‌ای نیست',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (_canWrite) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'با یک دستورپخت آماده شروع کنید یا گزارش جدید بسازید.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => _openStudio(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('شروع در استودیو'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, _canWrite ? 88 : 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final status = item['status']?.toString() ?? 'draft';
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: cs.primaryContainer,
                                child: Icon(
                                  _canWrite ? Icons.code : Icons.play_arrow,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                              title: Text(item['title']?.toString() ?? 'بدون عنوان'),
                              subtitle: Text('${item['slug'] ?? ''} · ${_statusLabel(status)}'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  final id = (item['id'] as num?)?.toInt();
                                  if (id == null) return;
                                  if (v == 'edit') _openStudio(reportId: id);
                                  if (v == 'run') _openRun(id);
                                  if (v == 'schedule') _openSchedule(item);
                                  if (v == 'archive') _archive(item);
                                  if (v == 'delete') _delete(item);
                                },
                                itemBuilder: (_) => [
                                  if (_canWrite)
                                    const PopupMenuItem(value: 'edit', child: Text('ویرایش در استودیو')),
                                  if (status == 'published')
                                    const PopupMenuItem(value: 'run', child: Text('اجرا')),
                                  if (_canSchedule && status == 'published')
                                    const PopupMenuItem(value: 'schedule', child: Text('زمان‌بندی')),
                                  if (_canPublish && status != 'archived')
                                    const PopupMenuItem(value: 'archive', child: Text('بایگانی')),
                                  if (_canWrite)
                                    const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                ],
                              ),
                              onTap: () => _openItem(item),
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
