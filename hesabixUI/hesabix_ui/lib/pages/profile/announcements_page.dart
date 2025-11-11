import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/announcements_service.dart';
import '../../utils/date_formatters.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late final AnnouncementsService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  int _page = 1;
  int _limit = 10;
  int _totalPages = 1;
  bool _onlyUnread = false;

  @override
  void initState() {
    super.initState();
    _service = AnnouncementsService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final data = await _service.listAnnouncements(page: _page, limit: _limit, onlyUnread: _onlyUnread);
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
            Text('خطا در بارگذاری اعلان‌ها:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('تلاش مجدد')),
          ],
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined),
                    const SizedBox(width: 8),
                    Text('اعلان‌های سیستمی', style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
              FilterChip(
                label: const Text('فقط خوانده‌نشده'),
                selected: _onlyUnread,
                onSelected: (v) async {
                  setState(() {
                    _onlyUnread = v;
                    _page = 1;
                  });
                  await _load();
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('بازخوانی')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _items.isEmpty
                ? Center(child: Text('اعلانی یافت نشد', style: Theme.of(context).textTheme.bodyMedium))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final it = _items[index];
                      final id = it['id'];
                      final title = '${it['title'] ?? '-'}';
                      final body = '${it['body'] ?? ''}';
                      final level = '${it['level'] ?? 'info'}';
                      final isRead = (it['is_read'] ?? false) == true;
                      final pinned = (it['is_pinned'] ?? false) == true;
                      final time = '${it['updated_at'] ?? it['time'] ?? ''}';
                      final Color lvlColor = switch (level) {
                        'critical' => Colors.red,
                        'warning' => Colors.orange,
                        _ => Theme.of(context).colorScheme.primary,
                      };
                      return Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                          border: Border(left: BorderSide(color: lvlColor, width: 3)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: lvlColor.withOpacity(0.12), shape: BoxShape.circle),
                              child: Icon(pinned ? Icons.push_pin : Icons.notifications, color: pinned ? cs.primary : lvlColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (!isRead)
                                        Container(width: 8, height: 8, margin: const EdgeInsetsDirectional.only(end: 8), decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
                                      Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: lvlColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(level, style: TextStyle(color: lvlColor, fontSize: 12)),
                                      ),
                                      const SizedBox(width: 8),
                                      if (time.isNotEmpty)
                                        Text(DateFormatters.formatServerDateTime(time), style: Theme.of(context).textTheme.labelSmall),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: () async {
                                          final annId = (id is int) ? id : int.tryParse('$id');
                                          if (annId == null) return;
                                          await _service.markRead(annId);
                                          await _load();
                                        },
                                        icon: const Icon(Icons.done_all, size: 16),
                                        label: const Text('خوانده شد'),
                                      ),
                                      const SizedBox(width: 4),
                                      TextButton.icon(
                                        onPressed: () async {
                                          final annId = (id is int) ? id : int.tryParse('$id');
                                          if (annId == null) return;
                                          await _service.dismiss(annId);
                                          await _load();
                                        },
                                        icon: const Icon(Icons.close, size: 16),
                                        label: const Text('پنهان'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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


