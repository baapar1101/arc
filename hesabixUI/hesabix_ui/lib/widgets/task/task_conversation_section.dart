import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/theme/glass.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:intl/intl.dart';

class TaskConversationSection extends StatefulWidget {
  final int businessId;
  final TaskModel task;

  const TaskConversationSection({
    super.key,
    required this.businessId,
    required this.task,
  });

  @override
  State<TaskConversationSection> createState() =>
      _TaskConversationSectionState();
}

class _TaskConversationSectionState extends State<TaskConversationSection> {
  late final TaskService _service;
  final TextEditingController _commentController = TextEditingController();
  List<TaskCommentModel> _comments = const [];
  List<TaskActivityModel> _activity = const [];
  bool _loading = true;
  bool _posting = false;
  bool _mutating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskConversationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _commentController.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _service.listComments(
          businessId: widget.businessId,
          taskId: widget.task.id,
        ),
        _service.listActivity(
          businessId: widget.businessId,
          taskId: widget.task.id,
          limit: 50,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _comments = results[0] as List<TaskCommentModel>;
        _activity = results[1] as List<TaskActivityModel>;
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

  Future<void> _addComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _posting) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await _service.addComment(
        businessId: widget.businessId,
        taskId: widget.task.id,
        body: body,
      );
      if (!mounted) return;
      _commentController.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _editComment(TaskCommentModel comment) async {
    if (_mutating) return;
    final controller = TextEditingController(text: comment.body);
    final nextBody = await showGlassDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش نظر'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'متن نظر',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nextBody == null || nextBody.isEmpty) return;

    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      await _service.updateComment(
        businessId: widget.businessId,
        taskId: widget.task.id,
        commentId: comment.id,
        body: nextBody,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deleteComment(TaskCommentModel comment) async {
    if (_mutating) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف نظر'),
        content: const Text('این نظر حذف شود؟'),
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
      _mutating = true;
      _error = null;
    });
    try {
      await _service.deleteComment(
        businessId: widget.businessId,
        taskId: widget.task.id,
        commentId: comment.id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
      });
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  String _eventLabel(TaskActivityModel event) {
    switch (event.eventType) {
      case 'task_created':
        return 'کار را ایجاد کرد';
      case 'task_updated':
        final keys = event.eventData.keys.toList();
        return keys.isEmpty
            ? 'کار را ویرایش کرد'
            : 'تغییر داد: ${keys.join('، ')}';
      case 'assignees_changed':
        return 'مسئولان را تغییر داد';
      case 'task_completed':
        return 'کار را تکمیل کرد';
      case 'task_reopened':
        return 'کار را دوباره باز کرد';
      case 'task_moved':
        return 'کار را در برد جابه‌جا کرد';
      case 'subtask_created':
        return 'یک زیرکار ایجاد کرد';
      case 'task_relation_added':
        return 'یک رابطه اضافه کرد';
      case 'task_relation_removed':
        return 'یک رابطه را حذف کرد';
      case 'comment_added':
        return 'نظر اضافه کرد';
      case 'comment_edited':
        return 'نظر را ویرایش کرد';
      case 'comment_deleted':
        return 'نظر را حذف کرد';
      default:
        return event.eventType.replaceAll('_', ' ');
    }
  }

  String _time(DateTime? value) {
    if (value == null) return '';
    return DateFormat('yyyy/MM/dd HH:mm').format(value.toLocal());
  }

  String _initial(String? name) {
    final value = (name ?? '').trim();
    return value.isEmpty ? '?' : value.characters.first;
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
                'Comments & Activity',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'بروزرسانی',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                minLines: 2,
                maxLines: 5,
                enabled: !_posting,
                decoration: const InputDecoration(
                  labelText: 'نظر جدید',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'ارسال نظر',
              onPressed: _posting ? null : _addComment,
              icon: _posting
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          if (_comments.isEmpty)
            Text(
              'هنوز نظری ثبت نشده است.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._comments.map(
              (comment) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: .28),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .42),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 15,
                        child: Text(_initial(comment.authorName)),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    comment.authorName ?? 'کاربر',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  _time(comment.createdAt),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(comment.body),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'عملیات نظر',
                        enabled: !_mutating,
                        onSelected: (value) {
                          if (value == 'edit') _editComment(comment);
                          if (value == 'delete') _deleteComment(comment);
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
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Activity',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (_activity.isEmpty)
            Text(
              'فعالیتی ثبت نشده است.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._activity.map(
              (event) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .72),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodySmall,
                          children: [
                            TextSpan(
                              text: event.actorName ?? 'سیستم',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: ' · ${_eventLabel(event)}'),
                            if (event.createdAt != null)
                              TextSpan(
                                text: ' · ${_time(event.createdAt)}',
                                style: TextStyle(color: scheme.outline),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          GlassSurface(
            padding: const EdgeInsets.all(10),
            borderRadius: BorderRadius.circular(10),
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
