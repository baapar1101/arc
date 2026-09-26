import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/project_model.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/project_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class TaskMilestoneSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;
  final Future<TaskModel?> Function(Map<String, dynamic> data) onUpdate;

  const TaskMilestoneSection({
    super.key,
    required this.businessId,
    required this.task,
    required this.onUpdate,
  });

  @override
  State<TaskMilestoneSection> createState() => _TaskMilestoneSectionState();
}

class _TaskMilestoneSectionState extends State<TaskMilestoneSection> {
  late final ProjectService _service;
  List<ProjectMilestoneModel> _items = const [];
  bool _loading = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = ProjectService(ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskMilestoneSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.projectId != widget.task.projectId) {
      _load();
    }
  }

  Future<void> _load() async {
    final projectId = widget.task.projectId;
    if (projectId == null) {
      if (mounted) setState(() => _items = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listMilestones(
        businessId: widget.businessId,
        projectId: projectId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _change(int value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onUpdate({
        'milestone_id': value == 0 ? null : value,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.task.projectId == null) {
      return Text(
        'برای تخصیص مایلستون ابتدا پروژه را انتخاب کنید.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Milestone',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else
          DropdownButtonFormField<int>(
            value: widget.task.milestoneId ?? 0,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'مایلستون',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: 0,
                child: Text('بدون مایلستون'),
              ),
              ..._items.map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(
                    item.targetAt == null
                        ? item.title
                        : '${item.title} · ${DateFormat('yyyy/MM/dd').format(item.targetAt!.toLocal())}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: _busy ? null : (value) => _change(value ?? 0),
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
