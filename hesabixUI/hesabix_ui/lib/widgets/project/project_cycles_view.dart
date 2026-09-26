import 'package:flutter/material.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class ProjectCyclesView extends StatefulWidget {
  final int businessId;
  final int projectId;
  final List<ProjectCycleModel> cycles;
  final ProjectService service;
  final ValueChanged<List<ProjectCycleModel>> onChanged;

  const ProjectCyclesView({
    super.key,
    required this.businessId,
    required this.projectId,
    required this.cycles,
    required this.service,
    required this.onChanged,
  });

  @override
  State<ProjectCyclesView> createState() => _ProjectCyclesViewState();
}

class _ProjectCyclesViewState extends State<ProjectCyclesView> {
  late List<ProjectCycleModel> _items;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = List<ProjectCycleModel>.from(widget.cycles);
  }

  @override
  void didUpdateWidget(covariant ProjectCyclesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cycles, widget.cycles)) {
      _items = List<ProjectCycleModel>.from(widget.cycles);
    }
  }

  void _emit(List<ProjectCycleModel> items) {
    setState(() => _items = items);
    widget.onChanged(items);
  }

  Future<void> _reload() async {
    final items = await widget.service.listCycles(
      businessId: widget.businessId,
      projectId: widget.projectId,
    );
    if (mounted) _emit(items);
  }

  Future<void> _edit([ProjectCycleModel? cycle]) async {
    if (_busy) return;
    final data = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CycleEditorDialog(cycle: cycle),
    );
    if (data == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = cycle == null
          ? await widget.service.createCycle(
              businessId: widget.businessId,
              projectId: widget.projectId,
              data: data,
            )
          : await widget.service.updateCycle(
              businessId: widget.businessId,
              projectId: widget.projectId,
              cycleId: cycle.id,
              data: data,
            );
      final next = List<ProjectCycleModel>.from(_items);
      final index = next.indexWhere((item) => item.id == saved.id);
      if (index >= 0) {
        next[index] = saved;
      } else {
        next.insert(0, saved);
      }
      _emit(next);
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ProjectCycleModel cycle) async {
    if (_busy) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف Cycle'),
        content: Text('«${cycle.name}» حذف شود؟'),
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
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.deleteCycle(
        businessId: widget.businessId,
        projectId: widget.projectId,
        cycleId: cycle.id,
      );
      _emit(_items.where((item) => item.id != cycle.id).toList());
    } catch (e) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Planned';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          GlassSurface(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cycles / Sprints',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Cycle جدید'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            const GlassSurface(
              padding: EdgeInsets.all(40),
              child: Center(child: Text('هنوز Cycle تعریف نشده است.')),
            )
          else
            ..._items.map(
              (cycle) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: GlassSurface(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.autorenew_rounded),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              cycle.name,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Chip(label: Text(_statusLabel(cycle.status))),
                          PopupMenuButton<String>(
                            enabled: !_busy,
                            onSelected: (value) {
                              if (value == 'edit') _edit(cycle);
                              if (value == 'delete') _delete(cycle);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                              PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                        ],
                      ),
                      if (cycle.goal?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text(cycle.goal!),
                      ],
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (cycle.startAt != null)
                            Chip(
                              label: Text(
                                'شروع ${DateFormat('yyyy/MM/dd').format(cycle.startAt!.toLocal())}',
                              ),
                            ),
                          if (cycle.endAt != null)
                            Chip(
                              label: Text(
                                'پایان ${DateFormat('yyyy/MM/dd').format(cycle.endAt!.toLocal())}',
                              ),
                            ),
                          Chip(
                            label: Text(
                              '${cycle.taskCompleted}/${cycle.taskTotal} کار',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      LinearProgressIndicator(
                        value: (cycle.progressPercent / 100).clamp(0.0, 1.0),
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

class _CycleEditorDialog extends StatefulWidget {
  final ProjectCycleModel? cycle;
  const _CycleEditorDialog({this.cycle});

  @override
  State<_CycleEditorDialog> createState() => _CycleEditorDialogState();
}

class _CycleEditorDialogState extends State<_CycleEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _goal;
  late String _status;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.cycle?.name ?? '');
    _goal = TextEditingController(text: widget.cycle?.goal ?? '');
    _status = widget.cycle?.status ?? 'planned';
    _start = widget.cycle?.startAt?.toLocal();
    _end = widget.cycle?.endAt?.toLocal();
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? value) => showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
      );

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, {
      'name': name,
      'goal': _goal.text.trim().isEmpty ? null : _goal.text.trim(),
      'status': _status,
      'start_at': _start == null
          ? null
          : DateTime(_start!.year, _start!.month, _start!.day, 9)
              .toUtc()
              .toIso8601String(),
      'end_at': _end == null
          ? null
          : DateTime(_end!.year, _end!.month, _end!.day, 17)
              .toUtc()
              .toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.cycle == null ? 'Cycle جدید' : 'ویرایش Cycle'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'نام'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _goal,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'هدف',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'وضعیت'),
                  items: const [
                    DropdownMenuItem(value: 'planned', child: Text('Planned')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'planned'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final value = await _pick(_start);
                          if (value != null) setState(() => _start = value);
                        },
                        child: Text(
                          _start == null
                              ? 'شروع'
                              : DateFormat('yyyy/MM/dd').format(_start!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final value = await _pick(_end);
                          if (value != null) setState(() => _end = value);
                        },
                        child: Text(
                          _end == null
                              ? 'پایان'
                              : DateFormat('yyyy/MM/dd').format(_end!),
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
          FilledButton(onPressed: _submit, child: const Text('ذخیره')),
        ],
      );
}
