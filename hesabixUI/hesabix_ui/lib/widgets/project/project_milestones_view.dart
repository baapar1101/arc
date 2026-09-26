import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class ProjectMilestonesView extends StatefulWidget {
  final int businessId;
  final int projectId;
  final List<ProjectMilestoneModel> milestones;
  final ProjectService service;
  final ValueChanged<List<ProjectMilestoneModel>> onChanged;

  const ProjectMilestonesView({
    super.key,
    required this.businessId,
    required this.projectId,
    required this.milestones,
    required this.service,
    required this.onChanged,
  });

  @override
  State<ProjectMilestonesView> createState() => _ProjectMilestonesViewState();
}

class _ProjectMilestonesViewState extends State<ProjectMilestonesView> {
  late List<ProjectMilestoneModel> _items;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = List<ProjectMilestoneModel>.from(widget.milestones);
  }

  @override
  void didUpdateWidget(covariant ProjectMilestonesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.milestones, widget.milestones)) {
      _items = List<ProjectMilestoneModel>.from(widget.milestones);
    }
  }

  void _emit(List<ProjectMilestoneModel> next) {
    setState(() => _items = next);
    widget.onChanged(next);
  }

  Future<void> _edit([ProjectMilestoneModel? milestone]) async {
    if (_busy) return;
    final data = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MilestoneEditorDialog(milestone: milestone),
    );
    if (data == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = milestone == null
          ? await widget.service.createMilestone(
              businessId: widget.businessId,
              projectId: widget.projectId,
              data: data,
            )
          : await widget.service.updateMilestone(
              businessId: widget.businessId,
              projectId: widget.projectId,
              milestoneId: milestone.id,
              data: data,
            );
      final next = List<ProjectMilestoneModel>.from(_items);
      final index = next.indexWhere((e) => e.id == saved.id);
      if (index >= 0) {
        next[index] = saved;
      } else {
        next.add(saved);
      }
      next.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        final at = a.targetAt;
        final bt = b.targetAt;
        if (at == null && bt == null) return a.id.compareTo(b.id);
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
      _emit(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ProjectMilestoneModel milestone) async {
    if (_busy) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف مایلستون'),
        content: Text('«${milestone.title}» حذف شود؟ تخصیص کارها پاک می‌شود.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.deleteMilestone(
        businessId: widget.businessId,
        projectId: widget.projectId,
        milestoneId: milestone.id,
      );
      _emit(_items.where((e) => e.id != milestone.id).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'تکمیل‌شده';
      case 'cancelled':
        return 'لغوشده';
      default:
        return 'باز';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async {
        final items = await widget.service.listMilestones(
          businessId: widget.businessId,
          projectId: widget.projectId,
        );
        if (mounted) _emit(items);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Milestones',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('مایلستون جدید'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            GlassSurface(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.flag_circle_outlined,
                    size: 46,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 10),
                  const Text('هنوز مایلستونی برای این پروژه تعریف نشده است.'),
                ],
              ),
            )
          else
            ..._items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: GlassSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            item.status == 'completed'
                                ? Icons.flag_circle_rounded
                                : Icons.outlined_flag_rounded,
                            color: item.status == 'completed'
                                ? scheme.primary
                                : scheme.outline,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Chip(label: Text(_statusLabel(item.status))),
                          PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (value) {
                              if (value == 'edit') _edit(item);
                              if (value == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('ویرایش'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('حذف'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (item.description?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 7),
                        Text(item.description!),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          if (item.startAt != null)
                            Chip(
                              avatar: const Icon(
                                Icons.play_circle_outline,
                                size: 17,
                              ),
                              label: Text(
                                DateFormat('yyyy/MM/dd')
                                    .format(item.startAt!.toLocal()),
                              ),
                            ),
                          if (item.targetAt != null)
                            Chip(
                              avatar: const Icon(
                                Icons.event_available_outlined,
                                size: 17,
                              ),
                              label: Text(
                                DateFormat('yyyy/MM/dd')
                                    .format(item.targetAt!.toLocal()),
                              ),
                            ),
                          Chip(
                            avatar: const Icon(Icons.task_alt, size: 17),
                            label: Text(
                              '${item.taskCompleted}/${item.taskTotal}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: (item.progressPercent / 100)
                            .clamp(0.0, 1.0),
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}

class _MilestoneEditorDialog extends StatefulWidget {
  final ProjectMilestoneModel? milestone;
  const _MilestoneEditorDialog({this.milestone});

  @override
  State<_MilestoneEditorDialog> createState() =>
      _MilestoneEditorDialogState();
}

class _MilestoneEditorDialogState extends State<_MilestoneEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _status;
  DateTime? _start;
  DateTime? _target;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.milestone?.title ?? '');
    _description =
        TextEditingController(text: widget.milestone?.description ?? '');
    _status = widget.milestone?.status ?? 'open';
    _start = widget.milestone?.startAt?.toLocal();
    _target = widget.milestone?.targetAt?.toLocal();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) {
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(context, {
      'title': title,
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      'status': _status,
      'start_at': _start == null
          ? null
          : DateTime(
              _start!.year,
              _start!.month,
              _start!.day,
              9,
            ).toUtc().toIso8601String(),
      'target_at': _target == null
          ? null
          : DateTime(
              _target!.year,
              _target!.month,
              _target!.day,
              17,
            ).toUtc().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          widget.milestone == null ? 'مایلستون جدید' : 'ویرایش مایلستون',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'عنوان'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'وضعیت'),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('باز')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('تکمیل‌شده'),
                    ),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('لغوشده'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'open'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final value = await _pick(_start);
                          if (value != null) setState(() => _start = value);
                        },
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(
                          _start == null
                              ? 'شروع'
                              : DateFormat('yyyy/MM/dd').format(_start!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final value = await _pick(_target);
                          if (value != null) setState(() => _target = value);
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _target == null
                              ? 'هدف'
                              : DateFormat('yyyy/MM/dd').format(_target!),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('ذخیره'),
          ),
        ],
      );
}
