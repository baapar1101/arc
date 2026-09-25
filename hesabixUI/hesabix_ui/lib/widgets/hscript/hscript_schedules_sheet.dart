import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';

import '../../services/hscript_report_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

Future<void> showHScriptSchedulesSheet({
  required BuildContext context,
  required int businessId,
  required int reportId,
  required String reportTitle,
  required HScriptReportService service,
}) {
  return showGlassModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _SchedulesSheet(
      businessId: businessId,
      reportId: reportId,
      reportTitle: reportTitle,
      service: service,
    ),
  );
}

class _SchedulesSheet extends StatefulWidget {
  const _SchedulesSheet({
    required this.businessId,
    required this.reportId,
    required this.reportTitle,
    required this.service,
  });

  final int businessId;
  final int reportId;
  final String reportTitle;
  final HScriptReportService service;

  @override
  State<_SchedulesSheet> createState() => _SchedulesSheetState();
}

class _SchedulesSheetState extends State<_SchedulesSheet> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.service.listSchedules(
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

  Future<void> _createOrEdit({Map<String, dynamic>? existing}) async {
    final result = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ScheduleEditorDialog(
        reportTitle: widget.reportTitle,
        initial: existing,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (existing == null) {
        await widget.service.createSchedule(
          businessId: widget.businessId,
          reportId: widget.reportId,
          payload: result,
        );
      } else {
        final id = (existing['id'] as num?)?.toInt();
        if (id != null) {
          await widget.service.updateSchedule(
            businessId: widget.businessId,
            scheduleId: id,
            payload: result,
          );
        }
      }
      if (!mounted) return;
      SnackBarHelper.show(context, message: existing == null ? 'زمان‌بندی ایجاد شد' : 'زمان‌بندی به‌روز شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف زمان‌بندی'),
        content: Text('«${item['title'] ?? ''}» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.service.deleteSchedule(businessId: widget.businessId, scheduleId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'حذف شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runNow(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await widget.service.runScheduleNow(businessId: widget.businessId, scheduleId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'اجرای فوری انجام شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('زمان‌بندی تحویل', style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          widget.reportTitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _createOrEdit(),
                    icon: const Icon(Icons.add),
                    label: const Text('جدید'),
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
                            'هنوز زمان‌بندی‌ای نیست.\nمثلاً هر روز ساعت ۸ صبح PDF بفرستید.',
                            textAlign: TextAlign.center,
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
                            final enabled = item['enabled'] == true;
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
                                        Icon(
                                          enabled ? Icons.schedule : Icons.schedule_outlined,
                                          color: enabled ? cs.primary : cs.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item['title']?.toString() ?? 'بدون عنوان',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (v) {
                                            if (v == 'edit') _createOrEdit(existing: item);
                                            if (v == 'run') _runNow(item);
                                            if (v == 'delete') _delete(item);
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                            PopupMenuItem(value: 'run', child: Text('اجرای فوری')),
                                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _summary(item),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                    if (item['last_run_status'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'آخرین اجرا: ${item['last_run_status']} · ${item['last_run_message'] ?? ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall,
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

  String _summary(Map<String, dynamic> item) {
    final mode = item['schedule_mode']?.toString() ?? 'simple';
    final fmt = item['output_format']?.toString() ?? 'pdf';
    final channels = (item['channels'] is List) ? (item['channels'] as List).join('+') : 'inapp';
    if (mode == 'cron') {
      return 'cron: ${item['cron_expression'] ?? '—'} · خروجی $fmt · $channels';
    }
    final repeat = item['simple_repeat']?.toString() ?? 'daily';
    final time = item['simple_time']?.toString() ?? '08:00';
    return '$repeat ساعت $time · خروجی $fmt · $channels';
  }
}

class _ScheduleEditorDialog extends StatefulWidget {
  const _ScheduleEditorDialog({required this.reportTitle, this.initial});

  final String reportTitle;
  final Map<String, dynamic>? initial;

  @override
  State<_ScheduleEditorDialog> createState() => _ScheduleEditorDialogState();
}

class _ScheduleEditorDialogState extends State<_ScheduleEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _timeCtrl;
  late final TextEditingController _cronCtrl;
  bool _enabled = true;
  String _mode = 'simple';
  String _repeat = 'daily';
  String _format = 'pdf';
  bool _channelInapp = true;
  bool _channelEmail = false;
  int _weekday = 0;
  int _interval = 1;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _titleCtrl = TextEditingController(text: i?['title']?.toString() ?? 'زمان‌بندی ${widget.reportTitle}');
    _timeCtrl = TextEditingController(text: i?['simple_time']?.toString() ?? '08:00');
    _cronCtrl = TextEditingController(text: i?['cron_expression']?.toString() ?? '0 8 * * *');
    _enabled = i?['enabled'] != false;
    _mode = i?['schedule_mode']?.toString() ?? 'simple';
    _repeat = i?['simple_repeat']?.toString() ?? 'daily';
    _format = i?['output_format']?.toString() ?? 'pdf';
    _weekday = (i?['simple_weekday'] as num?)?.toInt() ?? 0;
    _interval = (i?['simple_interval'] as num?)?.toInt() ?? 1;
    final channels = (i?['channels'] is List) ? (i!['channels'] as List).map((e) => e.toString()).toList() : ['inapp'];
    _channelInapp = channels.contains('inapp');
    _channelEmail = channels.contains('email');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _timeCtrl.dispose();
    _cronCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final channels = <String>[
      if (_channelInapp) 'inapp',
      if (_channelEmail) 'email',
    ];
    if (channels.isEmpty) channels.add('inapp');
    Navigator.pop(context, {
      'title': _titleCtrl.text.trim(),
      'enabled': _enabled,
      'schedule_mode': _mode,
      'simple_repeat': _repeat,
      'simple_time': _timeCtrl.text.trim(),
      'simple_weekday': _weekday,
      'simple_interval': _interval,
      'cron_expression': _cronCtrl.text.trim(),
      'timezone': 'Asia/Tehran',
      'output_format': _format,
      'channels': channels,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'زمان‌بندی جدید' : 'ویرایش زمان‌بندی'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'عنوان', border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('فعال'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'simple', label: Text('ساده')),
                  ButtonSegment(value: 'cron', label: Text('کرون')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 12),
              if (_mode == 'simple') ...[
                DropdownButtonFormField<String>(
                  value: _repeat,
                  decoration: const InputDecoration(labelText: 'تکرار', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('روزانه')),
                    DropdownMenuItem(value: 'weekly', child: Text('هفتگی')),
                    DropdownMenuItem(value: 'every_hours', child: Text('هر چند ساعت')),
                  ],
                  onChanged: (v) => setState(() => _repeat = v ?? 'daily'),
                ),
                const SizedBox(height: 10),
                if (_repeat != 'every_hours')
                  TextField(
                    controller: _timeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ساعت (HH:MM)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (_repeat == 'weekly') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: _weekday,
                    decoration: const InputDecoration(labelText: 'روز هفته', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('یکشنبه')),
                      DropdownMenuItem(value: 1, child: Text('دوشنبه')),
                      DropdownMenuItem(value: 2, child: Text('سه‌شنبه')),
                      DropdownMenuItem(value: 3, child: Text('چهارشنبه')),
                      DropdownMenuItem(value: 4, child: Text('پنجشنبه')),
                      DropdownMenuItem(value: 5, child: Text('جمعه')),
                      DropdownMenuItem(value: 6, child: Text('شنبه')),
                    ],
                    onChanged: (v) => setState(() => _weekday = v ?? 0),
                  ),
                ],
                if (_repeat == 'every_hours') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: _interval,
                    decoration: const InputDecoration(labelText: 'هر چند ساعت', border: OutlineInputBorder()),
                    items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setState(() => _interval = v ?? 1),
                  ),
                ],
              ] else
                TextField(
                  controller: _cronCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عبارت cron',
                    hintText: '0 8 * * *',
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _format,
                decoration: const InputDecoration(labelText: 'خروجی', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                  DropdownMenuItem(value: 'excel', child: Text('Excel')),
                  DropdownMenuItem(value: 'none', child: Text('فقط اعلان')),
                ],
                onChanged: (v) => setState(() => _format = v ?? 'pdf'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('اعلان داخل برنامه'),
                value: _channelInapp,
                onChanged: (v) => setState(() => _channelInapp = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ایمیل (در صورت تنظیم SMTP)'),
                value: _channelEmail,
                onChanged: (v) => setState(() => _channelEmail = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _submit, child: const Text('ذخیره')),
      ],
    );
  }
}
