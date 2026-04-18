import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/announcements_service.dart';
import '../../utils/date_formatters.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/jalali_date_picker.dart';

class AnnouncementsAdminPage extends StatefulWidget {
  const AnnouncementsAdminPage({super.key});

  @override
  State<AnnouncementsAdminPage> createState() => _AnnouncementsAdminPageState();
}

class _AnnouncementsAdminPageState extends State<AnnouncementsAdminPage> {
  late final AnnouncementsService _service;
  CalendarController? _calendarController;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  int _page = 1;
  final int _limit = 20;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _service = AnnouncementsService(ApiClient());
    _initControllers();
    _load();
  }

  Future<void> _initControllers() async {
    try {
      final cc = await CalendarController.load();
      if (mounted) setState(() => _calendarController = cc);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final data = await _service.adminList(page: _page, limit: _limit);
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _items = items;
        _totalPages = (data['total_pages'] as int?) ?? 1;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: initial?['title'] ?? '');
    final bodyCtrl = TextEditingController(text: initial?['body'] ?? '');
    String level = (initial?['level'] ?? 'info').toString();
    bool isPinned = (initial?['is_pinned'] ?? false) == true;
    bool isActive = (initial?['is_active'] ?? false) == true;
    DateTime? startsAt = initial?['starts_at'] != null ? DateTime.tryParse('${initial!['starts_at']}') : null;
    DateTime? endsAt = initial?['ends_at'] != null ? DateTime.tryParse('${initial!['ends_at']}') : null;

    Future<void> pickStarts() async {
      final now = DateTime.now();
      final picked = await _pickDate(context, startsAt ?? now);
      if (picked != null) {
        startsAt = picked;
        if (mounted) setState(() {});
      }
    }

    Future<void> pickEnds() async {
      final base = startsAt ?? DateTime.now();
      final picked = await _pickDate(context, endsAt ?? base);
      if (picked != null) {
        endsAt = picked;
        if (mounted) setState(() {});
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(initial == null ? 'ایجاد اعلان' : 'ویرایش اعلان'),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'عنوان'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'عنوان الزامی است' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: bodyCtrl,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'متن اعلان'),
                      validator: (v) => (v == null || v.trim().length < 10) ? 'حداقل ۱۰ کاراکتر' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: level,
                      decoration: const InputDecoration(labelText: 'سطح'),
                      items: const [
                        DropdownMenuItem(value: 'info', child: Text('اطلاع‌رسانی')),
                        DropdownMenuItem(value: 'warning', child: Text('هشدار')),
                        DropdownMenuItem(value: 'critical', child: Text('حیاتی')),
                      ],
                      onChanged: (v) => level = v ?? 'info',
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: isPinned,
                      onChanged: (v) => isPinned = v,
                      title: const Text('پین شود'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: isActive,
                      onChanged: (v) => isActive = v,
                      title: const Text('فعال'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickStarts,
                            icon: const Icon(Icons.play_arrow),
                            label: Text('شروع: ${startsAt != null ? DateFormatters.formatServerDateOnly(startsAt!.toIso8601String()) : '—'}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickEnds,
                            icon: const Icon(Icons.stop),
                            label: Text('پایان: ${endsAt != null ? DateFormatters.formatServerDateOnly(endsAt!.toIso8601String()) : '—'}'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                if (startsAt != null && endsAt != null && endsAt!.isBefore(startsAt!)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('تاریخ پایان نباید قبل از تاریخ شروع باشد')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      final body = <String, dynamic>{
        'title': titleCtrl.text.trim(),
        'body': bodyCtrl.text.trim(),
        'level': level,
        'is_pinned': isPinned,
        'is_active': isActive,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
      };
      if (initial == null) {
        await _service.adminCreate(body);
      } else {
        final id = int.tryParse('${initial['id']}');
        if (id != null) {
          await _service.adminUpdate(id, body);
        }
      }
      await _load();
    }
  }

  Future<DateTime?> _pickDate(BuildContext ctx, DateTime initial) async {
    if (!ctx.mounted) return null;
    final now = DateTime.now();
    return showAdaptiveDatePicker(
      context: ctx,
      calendarController: _calendarController,
      initialDate: initial,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: 'انتخاب تاریخ',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text('خطا در بارگذاری:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('تلاش مجدد')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('مدیریت اعلان‌ها', style: Theme.of(context).textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('ایجاد اعلان'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text('موردی یافت نشد', style: Theme.of(context).textTheme.bodyMedium))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final it = _items[index];
                      final id = it['id'];
                      final title = '${it['title'] ?? '-'}';
                      final level = '${it['level'] ?? 'info'}';
                      final isActive = (it['is_active'] ?? false) == true;
                      final isPinned = (it['is_pinned'] ?? false) == true;
                      final updatedAt = '${it['updated_at'] ?? ''}';
                      return ListTile(
                        leading: Icon(
                          isActive ? Icons.notifications_active : Icons.notifications_off,
                          color: isActive ? Theme.of(context).colorScheme.primary : null,
                        ),
                        title: Text(title),
                        subtitle: Row(
                          children: [
                            Chip(label: Text(level)),
                            const SizedBox(width: 8),
                            if (isPinned) const Chip(label: Text('Pinned')),
                            const SizedBox(width: 8),
                            if (updatedAt.isNotEmpty)
                              Text(DateFormatters.formatServerDateTime(updatedAt), style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              tooltip: 'ویرایش',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _openForm(initial: it),
                            ),
                            IconButton(
                              tooltip: isActive ? 'توقف' : 'انتشار',
                              icon: Icon(isActive ? Icons.pause : Icons.publish),
                              onPressed: () async {
                                final annId = (id is int) ? id : int.tryParse('$id');
                                if (annId == null) return;
                                await _service.adminPublish(annId, active: !isActive, pinned: isPinned);
                                await _load();
                              },
                            ),
                            IconButton(
                              tooltip: 'حذف',
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                final annId = (id is int) ? id : int.tryParse('$id');
                                if (annId == null) return;
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('حذف اعلان'),
                                    content: const Text('آیا از حذف این اعلان مطمئن هستید؟'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await _service.adminDelete(annId);
                                  await _load();
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('صفحه $_page از $_totalPages'),
              Row(
                children: [
                  IconButton(
                    onPressed: _page > 1
                        ? () async {
                            setState(() => _page -= 1);
                            await _load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    onPressed: _page < _totalPages
                        ? () async {
                            setState(() => _page += 1);
                            await _load();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}


