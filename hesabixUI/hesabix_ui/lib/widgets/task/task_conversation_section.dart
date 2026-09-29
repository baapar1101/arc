import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/task_model.dart';
import 'package:hesabix_ui/services/task_service.dart';
import 'package:hesabix_ui/services/in_app_notifications_hub.dart';
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
  List<TaskAssigneeOption> _mentionOptions = const [];
  final Set<int> _selectedMentionIds = <int>{};
  bool _loading = true;
  bool _posting = false;
  bool _mutating = false;
  String? _error;
  Timer? _realtimeRefreshTimer;
  final Set<String> _recentRealtimeEventIds = <String>{};

  @override
  void initState() {
    super.initState();
    _service = TaskService(ApiClient());
    InAppNotificationsHub.instance.addRawMessageListener(_onRealtimeMessage);
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskConversationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _commentController.clear();
      _selectedMentionIds.clear();
      _load();
    }
  }

  @override
  void dispose() {
    InAppNotificationsHub.instance.removeRawMessageListener(_onRealtimeMessage);
    _realtimeRefreshTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  void _onRealtimeMessage(Map<String, dynamic> message) {
    if ('${message['type'] ?? ''}' != 'task.realtime') return;
    final businessId = (message['business_id'] as num?)?.toInt();
    final taskId = (message['task_id'] as num?)?.toInt();
    if (businessId != widget.businessId || taskId != widget.task.id) return;

    final eventId = message['event_id']?.toString();
    if (eventId != null && eventId.isNotEmpty) {
      if (!_recentRealtimeEventIds.add(eventId)) return;
      if (_recentRealtimeEventIds.length > 128) {
        _recentRealtimeEventIds.clear();
        _recentRealtimeEventIds.add(eventId);
      }
    }

    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = Timer(
      const Duration(milliseconds: 180),
      () {
        if (mounted) unawaited(_load(silent: true));
      },
    );
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
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
        _service.listAssignees(widget.businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _comments = results[0] as List<TaskCommentModel>;
        _activity = results[1] as List<TaskActivityModel>;
        _mentionOptions = results[2] as List<TaskAssigneeOption>;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || silent) return;
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
        mentionUserIds: _selectedMentionIds.toList(),
      );
      if (!mounted) return;
      _commentController.clear();
      _selectedMentionIds.clear();
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
    final mentionIds = comment.mentions.map((e) => e.userId).toSet();
    final result = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('ویرایش نظر'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'متن نظر',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...mentionIds.map(
                        (userId) => InputChip(
                          avatar: const Icon(Icons.alternate_email, size: 16),
                          label: Text(_mentionName(userId)),
                          onDeleted: () =>
                              setInner(() => mentionIds.remove(userId)),
                        ),
                      ),
                      PopupMenuButton<int>(
                        tooltip: 'Mention user',
                        enabled: mentionIds.length < 25,
                        onSelected: (userId) =>
                            setInner(() => mentionIds.add(userId)),
                        itemBuilder: (_) => _mentionOptions
                            .where((user) => !mentionIds.contains(user.userId))
                            .map(
                              (user) => PopupMenuItem<int>(
                                value: user.userId,
                                child: Text(user.name),
                              ),
                            )
                            .toList(),
                        child: const Chip(
                          avatar: Icon(Icons.alternate_email, size: 16),
                          label: Text('Mention'),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                final body = controller.text.trim();
                if (body.isEmpty) return;
                Navigator.pop(ctx, {
                  'body': body,
                  'mention_user_ids': mentionIds.toList(),
                });
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return;
    final nextBody = result['body']?.toString().trim() ?? '';
    if (nextBody.isEmpty) return;
    final nextMentionIds = ((result['mention_user_ids'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();

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
        mentionUserIds: nextMentionIds,
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
      case 'task_mentioned':
        return 'از کاربر در نظر نام برد';
      default:
        return event.eventType.replaceAll('_', ' ');
    }
  }

  String _mentionName(int userId) {
    for (final user in _mentionOptions) {
      if (user.userId == userId) return '@${user.name}';
    }
    for (final comment in _comments) {
      for (final mention in comment.mentions) {
        if (mention.userId == userId) {
          return '@${mention.userName ?? 'User $userId'}';
        }
      }
    }
    return '@User $userId';
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
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._selectedMentionIds.map(
              (userId) => InputChip(
                avatar: const Icon(Icons.alternate_email, size: 16),
                label: Text(_mentionName(userId)),
                onDeleted: _posting
                    ? null
                    : () => setState(
                          () => _selectedMentionIds.remove(userId),
                        ),
              ),
            ),
            PopupMenuButton<int>(
              tooltip: 'Mention user',
              enabled: !_posting && _selectedMentionIds.length < 25,
              onSelected: (userId) =>
                  setState(() => _selectedMentionIds.add(userId)),
              itemBuilder: (_) => _mentionOptions
                  .where(
                    (user) => !_selectedMentionIds.contains(user.userId),
                  )
                  .map(
                    (user) => PopupMenuItem<int>(
                      value: user.userId,
                      child: Text(user.name),
                    ),
                  )
                  .toList(),
              child: const Chip(
                avatar: Icon(Icons.alternate_email, size: 16),
                label: Text('Mention'),
              ),
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
                            if (comment.mentions.isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: comment.mentions
                                    .map(
                                      (mention) => Chip(
                                        visualDensity: VisualDensity.compact,
                                        avatar: const Icon(
                                          Icons.alternate_email,
                                          size: 14,
                                        ),
                                        label: Text(
                                          '@${mention.userName ?? 'User ${mention.userId}'}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
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
