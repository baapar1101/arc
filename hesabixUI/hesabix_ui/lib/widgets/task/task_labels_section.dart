import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class TaskLabelsSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;
  final Future<TaskModel?> Function(Map<String, dynamic> data) onUpdate;

  const TaskLabelsSection({
    super.key,
    required this.businessId,
    required this.task,
    required this.onUpdate,
  });

  @override
  State<TaskLabelsSection> createState() => _TaskLabelsSectionState();
}

class _TaskLabelsSectionState extends State<TaskLabelsSection> {
  late final TaskService _service;
  List<TaskLabelModel> _labels = const [];
  late Set<int> _selected;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _selected = widget.task.labels.map((e) => e.id).toSet();
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskLabelsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.updatedAt != widget.task.updatedAt) {
      _selected = widget.task.labels.map((e) => e.id).toSet();
      if (oldWidget.task.id != widget.task.id) _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final labels = await _service.listLabels(widget.businessId);
      if (!mounted) return;
      setState(() {
        _labels = labels;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorExtractor.forContext(e, context);
      });
    }
  }

  Future<void> _toggle(int id, bool selected) async {
    if (_saving) return;
    final next = Set<int>.from(_selected);
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    setState(() {
      _saving = true;
      _error = null;
      _selected = next;
    });
    try {
      final updated = await widget.onUpdate({'label_ids': next.toList()});
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _selected = widget.task.labels.map((e) => e.id).toSet();
        });
      } else {
        setState(() {
          _selected = updated.labels.map((e) => e.id).toSet();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selected = widget.task.labels.map((e) => e.id).toSet();
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createLabel() async {
    final controller = TextEditingController();
    final name = await showGlassDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('برچسب جدید'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'نام برچسب'),
            onSubmitted: (value) =>
                Navigator.pop(ctx, value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final label = await _service.createLabel(
        businessId: widget.businessId,
        name: name,
      );
      if (!mounted) return;
      setState(() => _labels = [..._labels, label]);
      await _toggle(label.id, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    }
  }

  Color _parseColor(String? raw, Color fallback) {
    if (raw == null || raw.isEmpty) return fallback;
    var hex = raw.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final value = int.tryParse(hex, radix: 16);
    return value == null ? fallback : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Labels',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'برچسب جدید',
              onPressed: _saving ? null : _createLabel,
              icon: const Icon(Icons.add_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_labels.isEmpty)
          Text(
            'برچسبی تعریف نشده است.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _labels.map((label) {
              final color = _parseColor(label.color, scheme.primary);
              return FilterChip(
                selected: _selected.contains(label.id),
                label: Text(label.name),
                avatar: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                onSelected:
                    _saving ? null : (value) => _toggle(label.id, value),
              );
            }).toList(),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          GlassSurface(
            padding: const EdgeInsets.all(9),
            borderRadius: BorderRadius.circular(9),
            child: Text(
              _error!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}
