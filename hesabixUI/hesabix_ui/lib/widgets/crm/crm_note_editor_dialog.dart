// ignore_for_file: use_build_context_synchronously
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/errors/api_error.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_lead_picker_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

/// نمایش دیالوگ ایجاد/ویرایش یادداشت CRM با تب‌ها، کارت‌های بخش و UX بهبود یافته.
Future<void> showCrmNoteEditorDialog(
  BuildContext context, {
  required int businessId,
  required AuthStore authStore,
  required CalendarController calendarController,
  required List<dynamic> noteTypes,
  required Map<String, dynamic>? existing,
  required DateTime? presetDay,
  required VoidCallback onSaved,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => CrmNoteEditorDialog(
      businessId: businessId,
      authStore: authStore,
      calendarController: calendarController,
      noteTypes: noteTypes,
      existing: existing,
      presetDay: presetDay,
      onSaved: onSaved,
    ),
  );
}

class CrmNoteEditorDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final List<dynamic> noteTypes;
  final Map<String, dynamic>? existing;
  final DateTime? presetDay;
  final VoidCallback onSaved;

  const CrmNoteEditorDialog({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    required this.noteTypes,
    required this.existing,
    required this.presetDay,
    required this.onSaved,
  });

  @override
  State<CrmNoteEditorDialog> createState() => _CrmNoteEditorDialogState();
}

class _CrmNoteEditorDialogState extends State<CrmNoteEditorDialog> with SingleTickerProviderStateMixin {
  final CrmService _crm = CrmService(apiClient: ApiClient());
  final BusinessDashboardService _membersSvc = BusinessDashboardService(ApiClient());

  late TabController _tabController;
  late bool _isEdit;
  late List<dynamic> _noteTypesList;

  int? _typeId;
  String _visibility = 'business_public';
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  DateTime? _occursOn;
  DateTime? _startAt;
  DateTime? _endAt;
  int? _leadId;
  String _leadLabel = '';
  final Set<int> _sharedIds = {};
  List<Map<String, dynamic>> _members = [];
  bool _saving = false;
  List<dynamic> _comments = [];
  List<dynamic> _audit = [];
  final _commentCtrl = TextEditingController();
  final ScrollController _commentScroll = ScrollController();

  String _schedulingModeForType(int? tid) {
    for (final raw in _noteTypesList) {
      if (raw is Map && (raw['id'] as num?)?.toInt() == tid) {
        return (raw['scheduling_mode'] ?? 'day_only').toString();
      }
    }
    return 'day_only';
  }

  @override
  void initState() {
    super.initState();
    _noteTypesList = List<dynamic>.from(widget.noteTypes);
    final e = widget.existing;
    _isEdit = e != null && (e['id'] as num?) != null;
    _tabController = TabController(length: _isEdit ? 3 : 1, vsync: this);

    if (e != null) {
      _typeId = (e['note_type_id'] as num?)?.toInt();
      _visibility = (e['visibility'] ?? 'business_public').toString();
      _titleCtrl.text = (e['title'] ?? '').toString();
      _bodyCtrl.text = (e['body'] ?? '').toString();
      final rawDay = (e['occurs_on_raw'] ?? '').toString();
      _occursOn = rawDay.length >= 10 ? HesabixDateUtils.parseFromAPI(rawDay.substring(0, 10)) : null;
      final sRaw = (e['starts_at_raw'] ?? e['starts_at'] ?? '').toString();
      _startAt = DateTime.tryParse(sRaw);
      final eRaw = (e['ends_at_raw'] ?? e['ends_at'] ?? '').toString();
      _endAt = DateTime.tryParse(eRaw);
      _leadId = (e['lead_id'] as num?)?.toInt();
      if (_leadId != null) {
        final cn = (e['lead_code'] ?? '').toString();
        final nm = (e['lead_name'] ?? '').toString();
        _leadLabel = cn.isNotEmpty ? '$cn — $nm' : nm;
      }
      final sh = e['shared_user_ids'];
      if (sh is List) {
        for (final x in sh) {
          if (x is int) _sharedIds.add(x);
          if (x is num) _sharedIds.add(x.toInt());
        }
      }
      _loadThread();
    } else {
      _occursOn = widget.presetDay != null
          ? DateTime(widget.presetDay!.year, widget.presetDay!.month, widget.presetDay!.day)
          : DateTime.now();
      if (_noteTypesList.isNotEmpty && _noteTypesList.first is Map) {
        _typeId = ((_noteTypesList.first as Map)['id'] as num?)?.toInt();
      }
    }
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final res = await _membersSvc.getMembers(widget.businessId);
      if (!mounted) return;
      setState(() {
        _members = res.items.map((e) => {'user_id': e.userId, 'name': '${e.firstName} ${e.lastName}'.trim()}).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadThread() async {
    final id = (widget.existing?['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final com = await _crm.listCrmNoteComments(businessId: widget.businessId, noteId: id);
      final au = await _crm.listCrmNoteAudit(businessId: widget.businessId, noteId: id);
      if (!mounted) return;
      setState(() {
        _comments = com;
        _audit = au;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _commentCtrl.dispose();
    _commentScroll.dispose();
    super.dispose();
  }

  String _normalizeNoteTypeCode(String raw) {
    var s = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  Future<DateTime?> _pickMeetingDateTime({DateTime? initial}) async {
    final isJ = widget.calendarController.isJalali;
    final base = initial ?? DateTime.now();
    DateTime? day;
    if (isJ) {
      final p = await showJalaliDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (p == null || !mounted) return null;
      day = DateTime(p.year, p.month, p.day);
    } else {
      final p = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        locale: const Locale('en', 'GB'),
      );
      if (p == null || !mounted) return null;
      day = DateTime(p.year, p.month, p.day);
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? day),
    );
    if (time == null || !mounted) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _pickDate() async {
    final isJ = widget.calendarController.isJalali;
    DateTime? p;
    if (isJ) {
      p = await showJalaliDatePicker(
        context: context,
        initialDate: _occursOn ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
    } else {
      p = await showDatePicker(
        context: context,
        initialDate: _occursOn ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        locale: const Locale('en', 'GB'),
      );
    }
    if (p != null && mounted) setState(() => _occursOn = DateTime(p!.year, p.month, p.day));
  }

  Future<void> _openCreateNoteType() async {
    if (!widget.authStore.canWriteSection('crm')) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CrmNoteTypeCreateDialog(t: AppLocalizations.of(context)),
    );
    if (payload == null || !mounted) return;
    var maxSort = 0;
    for (final raw in _noteTypesList) {
      if (raw is Map && raw['sort_order'] is num) {
        final s = (raw['sort_order'] as num).toInt();
        if (s > maxSort) maxSort = s;
      }
    }
    payload['sort_order'] = maxSort + 10;
    try {
      final res = await _crm.createCrmNoteType(businessId: widget.businessId, body: payload);
      final list = await _crm.listCrmNoteTypes(businessId: widget.businessId);
      if (!mounted) return;
      final newId = (res['id'] as num?)?.toInt();
      setState(() {
        _noteTypesList = list;
        if (newId != null) {
          _typeId = newId;
          if (_schedulingModeForType(newId) == 'meeting' && _startAt == null && _occursOn != null) {
            _startAt = DateTime(_occursOn!.year, _occursOn!.month, _occursOn!.day, 9);
          }
        }
      });
      SnackBarHelper.show(context, message: AppLocalizations.of(context).crmNotesNoteTypeCreated);
    } on DioException catch (e) {
      String msg = '${AppLocalizations.of(context).crmNotesErrorSaving}';
      if (e.error is ApiErrorDetails) {
        msg = (e.error! as ApiErrorDetails).message ?? msg;
      } else if (e.message != null) {
        msg = e.message!;
      }
      if (mounted) SnackBarHelper.show(context, message: msg, isError: true);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: '${AppLocalizations.of(context).crmNotesErrorSaving}: $e', isError: true);
      }
    }
  }

  Future<void> _pickLead() async {
    final chosen = await showCrmLeadPickerDialog(context, businessId: widget.businessId);
    if (chosen != null && mounted) {
      setState(() {
        _leadId = (chosen['id'] as num?)?.toInt();
        _leadLabel = '${chosen['code'] ?? ''} — ${chosen['name'] ?? ''}';
      });
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final mode = _schedulingModeForType(_typeId);
    if (_typeId == null) {
      SnackBarHelper.show(context, message: t.crmNotesType, isError: true);
      _tabController.animateTo(0);
      return;
    }
    if (_bodyCtrl.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: t.crmNotesBody, isError: true);
      _tabController.animateTo(0);
      return;
    }
    if (mode == 'day_only' && _occursOn == null) {
      SnackBarHelper.show(context, message: t.crmNotesDayNotes, isError: true);
      _tabController.animateTo(0);
      return;
    }
    if (_visibility == 'shared' && _sharedIds.isEmpty) {
      SnackBarHelper.show(context, message: t.crmNotesSharedUsers, isError: true);
      _tabController.animateTo(0);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'note_type_id': _typeId,
        'visibility': _visibility,
        'title': _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        if (mode == 'day_only' && _occursOn != null) 'occurs_on': HesabixDateUtils.formatForApiDate(_occursOn!),
        if (mode == 'meeting' && _startAt != null) 'starts_at': _startAt!.toIso8601String(),
        if (mode == 'meeting' && _endAt != null) 'ends_at': _endAt!.toIso8601String(),
        if (_leadId != null) 'lead_id': _leadId,
        if (_visibility == 'shared') 'shared_user_ids': _sharedIds.toList(),
      };
      final existingId = (widget.existing?['id'] as num?)?.toInt();
      if (existingId == null) {
        await _crm.createCrmNote(businessId: widget.businessId, body: body);
      } else {
        final patch = Map<String, dynamic>.from(body);
        final hadLead = (widget.existing?['lead_id'] as num?) != null;
        if (hadLead && _leadId == null) {
          patch['clear_lead'] = true;
        }
        await _crm.updateCrmNote(businessId: widget.businessId, noteId: existingId, body: patch);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: '${t.crmNotesErrorSaving}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final id = (widget.existing?['id'] as num?)?.toInt();
    if (id == null) return;
    final hasComments = _comments.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.crmNotesDeleteConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.crmNotesDeleteConfirmMessage),
            if (hasComments) ...[
              const SizedBox(height: 12),
              Text(
                t.crmNotesDeleteWarnComments,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.crmNotesClose)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.crmNotesDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _crm.deleteCrmNote(businessId: widget.businessId, noteId: id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      SnackBarHelper.show(context, message: '$e', isError: true);
    }
  }

  Future<void> _sendComment() async {
    final id = (widget.existing?['id'] as num?)?.toInt();
    if (id == null) return;
    final txt = _commentCtrl.text.trim();
    if (txt.isEmpty) return;
    try {
      await _crm.addCrmNoteComment(businessId: widget.businessId, noteId: id, body: txt);
      _commentCtrl.clear();
      await _loadThread();
      if (!mounted) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_commentScroll.hasClients) {
          _commentScroll.animateTo(
            _commentScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      SnackBarHelper.show(context, message: '$e', isError: true);
    }
  }

  String _formatCommentTime(Map<String, dynamic> m) {
    final raw = (m['created_at_raw'] ?? m['created_at'] ?? '').toString();
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      return HesabixDateUtils.formatDateTime(dt, widget.calendarController.isJalali);
    }
    return '';
  }

  String _avatarInitial(String name) {
    final s = name.trim();
    if (s.isEmpty) return '?';
    final it = s.runes.iterator;
    return it.moveNext() ? String.fromCharCode(it.current) : '?';
  }

  Widget _buildVisibilityControl(AppLocalizations t, ThemeData theme, bool canWrite) {
    final disabled = !canWrite;
    final seg = IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? 0.6 : 1,
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'private',
              label: Text(t.crmNotesVisibilityShortPrivate),
              icon: const Icon(Icons.lock_outline, size: 18),
            ),
            ButtonSegment(
              value: 'business_public',
              label: Text(t.crmNotesVisibilityShortBusiness),
              icon: const Icon(Icons.groups_2_outlined, size: 18),
            ),
            ButtonSegment(
              value: 'shared',
              label: Text(t.crmNotesVisibilityShortShared),
              icon: const Icon(Icons.person_search_outlined, size: 18),
            ),
          ],
          selected: {_visibility},
          emptySelectionAllowed: false,
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            if (!canWrite || s.isEmpty) return;
            setState(() => _visibility = s.first);
          },
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 420) {
          return DropdownButtonFormField<String>(
            value: _visibility,
            decoration: InputDecoration(
              labelText: t.crmNotesVisibilityLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'private',
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.crmNotesVisibilityShortPrivate)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 'business_public',
                child: Row(
                  children: [
                    const Icon(Icons.groups_2_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.crmNotesVisibilityShortBusiness)),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 'shared',
                child: Row(
                  children: [
                    const Icon(Icons.person_search_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.crmNotesVisibilityShortShared)),
                  ],
                ),
              ),
            ],
            onChanged: disabled
                ? null
                : (v) {
                    if (v != null) setState(() => _visibility = v);
                  },
          );
        }
        return seg;
      },
    );
  }

  Widget _buildCommentBubble(ThemeData theme, Map<String, dynamic> m) {
    final body = m['body']?.toString() ?? '';
    final who = m['created_by_name']?.toString() ?? '';
    final when = _formatCommentTime(m);
    final authorId = (m['created_by_user_id'] as num?)?.toInt();
    final selfId = widget.authStore.currentUserId;
    final mine = selfId != null && authorId == selfId;
    final cs = theme.colorScheme;
    final initial = _avatarInitial(who);
    final bubbleBg = mine ? cs.primaryContainer : cs.surfaceContainerHighest;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.secondaryContainer,
                  child: Text(initial, style: theme.textTheme.labelLarge),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: mine ? WrapAlignment.end : WrapAlignment.start,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (who.isNotEmpty)
                          Text(
                            who,
                            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        if (when.isNotEmpty)
                          Text(when, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: bubbleBg,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(mine ? 12 : 4),
                          bottomRight: Radius.circular(mine ? 4 : 12),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: SelectableText(body, style: theme.textTheme.bodyMedium),
                      ),
                    ),
                  ],
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primaryContainer,
                  child: Text(initial, style: theme.textTheme.labelLarge),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _auditActionLabel(AppLocalizations t, String code) {
    switch (code) {
      case 'CREATED':
        return t.crmNoteAuditCreated;
      case 'UPDATED':
        return t.crmNoteAuditUpdated;
      case 'VISIBILITY_CHANGED':
        return t.crmNoteAuditVisibility;
      case 'ACL_ADDED':
      case 'ACL_REMOVED':
        return t.crmNoteAuditAcl;
      case 'SOFT_DELETED':
        return t.crmNoteAuditSoftDeleted;
      case 'COMMENT_CREATED':
        return t.crmNoteAuditCommentCreated;
      case 'COMMENT_DELETED':
        return t.crmNoteAuditCommentDeleted;
      default:
        return t.crmNoteAuditOther;
    }
  }

  String _formatAuditTime(Map<String, dynamic> m) {
    final raw = m['occurred_at_raw']?.toString();
    if (raw != null && raw.isNotEmpty) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) {
        return HesabixDateUtils.formatDateTime(dt, widget.calendarController.isJalali);
      }
    }
    return (m['occurred_at'] ?? '').toString();
  }

  Widget _buildDetailsTab(AppLocalizations t, ThemeData theme, bool canWrite) {
    final mode = _schedulingModeForType(_typeId);
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CrmSectionCard(
            title: t.crmNotesType,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _typeId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    isExpanded: true,
                    items: _noteTypesList.map((raw) {
                      if (raw is! Map) return null;
                      final m = Map<String, dynamic>.from(raw);
                      final tid = (m['id'] as num?)?.toInt();
                      final label = (m['title'] ?? m['code'] ?? '').toString();
                      return DropdownMenuItem(value: tid, child: Text(label));
                    }).whereType<DropdownMenuItem<int>>().toList(),
                    onChanged: canWrite
                        ? (v) => setState(() {
                              _typeId = v;
                              if (_schedulingModeForType(v) == 'meeting' && _startAt == null && _occursOn != null) {
                                _startAt = DateTime(_occursOn!.year, _occursOn!.month, _occursOn!.day, 9);
                              }
                            })
                        : null,
                  ),
                ),
                if (canWrite) ...[
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: t.crmNotesAddNoteType,
                    onPressed: _openCreateNoteType,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CrmSectionCard(
            title: t.crmNotesVisibilityLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildVisibilityControl(t, theme, canWrite),
                const SizedBox(height: 8),
                Text(
                  _visibility == 'private'
                      ? t.crmNotesVisibilityHintPrivate
                      : _visibility == 'business_public'
                          ? t.crmNotesVisibilityHintBusiness
                          : t.crmNotesVisibilityHintShared,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (_visibility == 'shared') ...[
                  const SizedBox(height: 12),
                  Text(t.crmNotesSharedPickHint, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _members.map((u) {
                      final uid = u['user_id'] as int;
                      final selfId = widget.authStore.currentUserId;
                      if (selfId != null && uid == selfId) return const SizedBox.shrink();
                      final sel = _sharedIds.contains(uid);
                      return FilterChip(
                        label: Text((u['name'] ?? '$uid').toString()),
                        selected: sel,
                        onSelected: canWrite
                            ? (b) => setState(() {
                                  if (b) {
                                    _sharedIds.add(uid);
                                  } else {
                                    _sharedIds.remove(uid);
                                  }
                                })
                            : null,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CrmSectionCard(
            title: t.crmNotesDayNotes,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mode == 'day_only') ...[
                  Text(
                    _occursOn == null ? '—' : HesabixDateUtils.formatForDisplay(_occursOn!, widget.calendarController.isJalali),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: canWrite ? _pickDate : null,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(t.crmNotesEventDateButton),
                    ),
                  ),
                ],
                if (mode == 'meeting') ...[
                  Text(t.crmNotesMeetingStart, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    _startAt == null ? '—' : HesabixDateUtils.formatDateTime(_startAt, widget.calendarController.isJalali),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: !canWrite
                          ? null
                          : () async {
                              final dt = await _pickMeetingDateTime(initial: _startAt ?? DateTime.now());
                              if (dt == null || !mounted) return;
                              setState(() {
                                _startAt = dt;
                                _occursOn = DateTime(dt.year, dt.month, dt.day);
                              });
                            },
                      icon: const Icon(Icons.schedule),
                      label: Text(t.crmNotesPickDateTime),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(t.crmNotesMeetingEnd, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    _endAt == null ? '—' : HesabixDateUtils.formatDateTime(_endAt, widget.calendarController.isJalali),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: !canWrite
                          ? null
                          : () async {
                              final dt = await _pickMeetingDateTime(initial: _endAt ?? _startAt ?? DateTime.now());
                              if (dt == null || !mounted) return;
                              setState(() => _endAt = dt);
                            },
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(t.crmNotesPickDateTime),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CrmSectionCard(
            title: t.crmNotesBody,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: t.crmNotesTitleOptional,
                    border: const OutlineInputBorder(),
                  ),
                  readOnly: !canWrite,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyCtrl,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  minLines: 8,
                  maxLines: 14,
                  readOnly: !canWrite,
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: cs.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ExpansionTile(
            initiallyExpanded: _leadId != null,
            leading: Icon(Icons.person_search_outlined, color: cs.primary),
            title: Text(t.crmNotesLeadOptional),
            subtitle: Text(
              _leadLabel.isNotEmpty ? _leadLabel : t.crmNotesEditorMoreOptions,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_leadId != null && _leadLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InputChip(
                          label: Text(_leadLabel),
                          onDeleted: canWrite ? () => setState(() { _leadId = null; _leadLabel = ''; }) : null,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: canWrite ? _pickLead : null,
                        icon: const Icon(Icons.search),
                        label: Text(t.crmNotesSearchLeads),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommentsTab(AppLocalizations t, ThemeData theme, bool canWrite) {
    final id = (widget.existing?['id'] as num?)?.toInt();
    final commentsOn = widget.existing?['comments_enabled'] == true;
    if (id == null) return const SizedBox.shrink();
    if (!commentsOn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.crmNotesCommentsDisabledTab, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _comments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          t.crmNotesNoComments,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _commentScroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: _comments.length,
                  itemBuilder: (context, i) {
                    final m = Map<String, dynamic>.from(_comments[i] as Map);
                    return _buildCommentBubble(theme, m);
                  },
                ),
        ),
        if (canWrite)
          Material(
            elevation: 2,
            shadowColor: theme.shadowColor.withValues(alpha: 0.12),
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + MediaQuery.paddingOf(context).bottom),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        labelText: t.crmNotesCommentInputLabel,
                        hintText: t.crmNotesCommentHint,
                        border: const OutlineInputBorder(),
                        filled: true,
                      ),
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: t.crmNotesSendComment,
                    child: FilledButton(
                      onPressed: _sendComment,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAuditTab(AppLocalizations t, ThemeData theme) {
    if (_audit.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t.crmNotesAuditEmpty)));
    }
    final show = _audit.take(15).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          t.crmNotesAuditRecentLimit(show.length),
          style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ...show.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final action = (m['action'] ?? '').toString();
          final title = _auditActionLabel(t, action);
          final when = _formatAuditTime(m);
          final sub = (m['payload_text'] ?? '').toString();
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (when.isNotEmpty) Text(when, style: theme.textTheme.labelSmall),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final id = (widget.existing?['id'] as num?)?.toInt();
    final canWrite = widget.authStore.canWriteSection('crm');
    final maxW = math.min(640.0, media.size.width - 24);
    final maxH = media.size.height * 0.9;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: maxW,
        height: maxH,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          id == null ? t.crmNotesAdd : t.crmNotesEdit,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        tooltip: t.crmNotesClose,
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                if (_isEdit)
                  TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(text: t.crmNoteTabDetails),
                      Tab(text: t.crmNoteTabComments),
                      Tab(text: t.crmNoteTabAudit),
                    ],
                  ),
                Expanded(
                  child: _isEdit
                      ? TabBarView(
                          controller: _tabController,
                          children: [
                            _buildDetailsTab(t, theme, canWrite),
                            _buildCommentsTab(t, theme, canWrite),
                            _buildAuditTab(t, theme),
                          ],
                        )
                      : _buildDetailsTab(t, theme, canWrite),
                ),
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        if (id != null && canWrite)
                          TextButton(
                            onPressed: _saving ? null : _delete,
                            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                            child: Text(t.crmNotesDelete),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: _saving ? null : () => Navigator.pop(context),
                          child: Text(t.crmNotesClose),
                        ),
                        const SizedBox(width: 8),
                        if (canWrite)
                          FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(t.crmNotesSave),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_saving)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: theme.colorScheme.surface.withValues(alpha: 0.55),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            if (_saving)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// دیالوگ ایجاد نوع یادداشت با اعتبارسنجی فیلدها
class _CrmNoteTypeCreateDialog extends StatefulWidget {
  final AppLocalizations t;

  const _CrmNoteTypeCreateDialog({required this.t});

  @override
  State<_CrmNoteTypeCreateDialog> createState() => _CrmNoteTypeCreateDialogState();
}

class _CrmNoteTypeCreateDialogState extends State<_CrmNoteTypeCreateDialog> {
  final _code = TextEditingController();
  final _fa = TextEditingController();
  final _en = TextEditingController();
  String _sched = 'day_only';
  bool _allowComments = true;
  String? _codeError;
  String? _faError;
  String? _enError;

  @override
  void dispose() {
    _code.dispose();
    _fa.dispose();
    _en.dispose();
    super.dispose();
  }

  String _norm(String raw) {
    var s = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  bool _validate() {
    final t = widget.t;
    _codeError = null;
    _faError = null;
    _enError = null;
    final c = _norm(_code.text);
    if (c.isEmpty) {
      _codeError = t.crmNotesNoteTypeCode;
    }
    if (_fa.text.trim().isEmpty) {
      _faError = t.crmNotesNoteTypeTitleFa;
    }
    if (_en.text.trim().isEmpty) {
      _enError = t.crmNotesNoteTypeTitleEn;
    }
    setState(() {});
    return _codeError == null && _faError == null && _enError == null;
  }

  String _preview() {
    final loc = Localizations.localeOf(context).languageCode;
    if (loc.startsWith('fa')) {
      return _fa.text.trim().isEmpty ? '—' : _fa.text.trim();
    }
    return _en.text.trim().isEmpty ? '—' : _en.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(t.crmNotesAddNoteType),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.crmNotesNoteTypeSectionIdentity, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                decoration: InputDecoration(
                  labelText: t.crmNotesNoteTypeCode,
                  helperText: t.crmNotesNoteTypeCodeHelper,
                  errorText: _codeError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _codeError = null),
              ),
              const SizedBox(height: 16),
              Text(t.crmNotesNoteTypeSectionTitles, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _fa,
                decoration: InputDecoration(
                  labelText: t.crmNotesNoteTypeTitleFa,
                  errorText: _faError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _faError = null),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _en,
                decoration: InputDecoration(
                  labelText: t.crmNotesNoteTypeTitleEn,
                  errorText: _enError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _enError = null),
              ),
              const SizedBox(height: 8),
              Text('${t.crmNotesNoteTypePreview}: ${_preview()}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text(t.crmNotesNoteTypeSectionBehavior, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _sched,
                decoration: InputDecoration(
                  labelText: t.crmNotesNoteTypeScheduling,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'day_only', child: Text(t.crmNotesNoteTypeDayOnly)),
                  DropdownMenuItem(value: 'meeting', child: Text(t.crmNotesNoteTypeMeeting)),
                ],
                onChanged: (v) => setState(() => _sched = v ?? 'day_only'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.crmNotesNoteTypeAllowComments),
                subtitle: Text(t.crmNotesNoteTypeAllowCommentsHint, style: theme.textTheme.bodySmall),
                value: _allowComments,
                onChanged: (v) => setState(() => _allowComments = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.crmNotesClose)),
        FilledButton(
          onPressed: () {
            if (!_validate()) return;
            Navigator.pop(context, <String, dynamic>{
              'code': _norm(_code.text),
              'title_i18n': {'fa': _fa.text.trim(), 'en': _en.text.trim()},
              'scheduling_mode': _sched,
              'allow_comments': _allowComments,
            });
          },
          child: Text(t.crmNotesSave),
        ),
      ],
    );
  }
}
