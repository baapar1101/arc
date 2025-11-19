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
  late final ScrollController _scrollController;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  int _page = 1;
  final int _limit = 20;
  bool _onlyUnread = true; // پیش‌فرض: فقط خوانده‌نشده
  bool _hasMore = true;
  final Set<int> _busyAnnIds = <int>{};

  @override
  void initState() {
    super.initState();
    _service = AnnouncementsService(ApiClient());
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (_loading) return;
    try {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _items = [];
        _hasMore = true;
      });
      final data = await _service.listAnnouncements(page: 1, limit: _limit, onlyUnread: _onlyUnread);
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final totalPages = (data['total_pages'] as int?) ?? 1;
      setState(() {
        _items = items;
        _hasMore = _page < totalPages;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    try {
      setState(() => _loadingMore = true);
      final nextPage = _page + 1;
      final data = await _service.listAnnouncements(page: nextPage, limit: _limit, onlyUnread: _onlyUnread);
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final totalPages = (data['total_pages'] as int?) ?? 1;
      setState(() {
        _items.addAll(items);
        _page = nextPage;
        _hasMore = _page < totalPages;
        _loadingMore = false;
      });
    } catch (e) {
      setState(() => _loadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری: $e')),
        );
      }
    }
  }

  Future<void> _markAsRead(int annId) async {
    if (_busyAnnIds.contains(annId)) return;
    setState(() => _busyAnnIds.add(annId));
    try {
      await _service.markRead(annId);
      setState(() {
        _items.removeWhere((e) => (e['id'] is int ? e['id'] == annId : int.tryParse('${e['id']}') == annId));
        if (_onlyUnread && _items.isEmpty && _hasMore) {
          _loadMore();
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('به‌عنوان خوانده‌شده علامت خورد')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyAnnIds.remove(annId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (_loading && _items.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _items.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: cs.error),
              const SizedBox(height: 16),
              Text(
                'خطا در بارگذاری اعلان‌ها',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // AppBar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: cs.surface,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.notifications_active, color: cs.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'اعلان‌های سیستمی',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilterChip(
                  label: const Text('فقط خوانده‌نشده'),
                  selected: _onlyUnread,
                  onSelected: (v) async {
                    setState(() {
                      _onlyUnread = v;
                    });
                    await _loadInitial();
                  },
                  avatar: Icon(
                    _onlyUnread ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 18,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'بازخوانی',
                icon: const Icon(Icons.refresh),
                onPressed: _loadInitial,
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Content
          if (_items.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 80,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'اعلانی یافت نشد',
                      style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _items.length) {
                      // Loading indicator for more items
                      if (_loadingMore) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (_hasMore) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'همه اعلان‌ها نمایش داده شد',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      );
                    }

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
                      _ => cs.primary,
                    };

                    IconData levelIcon = switch (level) {
                      'critical' => Icons.error_outline,
                      'warning' => Icons.warning_amber_rounded,
                      _ => Icons.info_outline,
                    };

                    final int? annId = (id is int) ? id : int.tryParse('$id');
                    final bool busy = annId != null && _busyAnnIds.contains(annId);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border(
                          left: BorderSide(color: lvlColor, width: 4),
                          top: pinned ? BorderSide(color: cs.primary.withValues(alpha: 0.3), width: 2) : BorderSide.none,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            // می‌توان در آینده دیالوگ جزئیات اضافه کرد
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Icon
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: lvlColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Icon(
                                          pinned ? Icons.push_pin : levelIcon,
                                          color: pinned ? cs.primary : lvlColor,
                                          size: 24,
                                        ),
                                      ),
                                      if (pinned)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: cs.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Content
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Title row
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (!isRead)
                                            Container(
                                              width: 10,
                                              height: 10,
                                              margin: const EdgeInsetsDirectional.only(end: 8, top: 4),
                                              decoration: BoxDecoration(
                                                color: cs.primary,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: theme.textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: isRead ? cs.onSurfaceVariant : cs.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // Body
                                      Text(
                                        body,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          height: 1.5,
                                        ),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      // Footer
                                      Row(
                                        children: [
                                          // Level badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: lvlColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(levelIcon, size: 14, color: lvlColor),
                                                const SizedBox(width: 4),
                                                Text(
                                                  level,
                                                  style: TextStyle(
                                                    color: lvlColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Time
                                          if (time.isNotEmpty)
                                            Text(
                                              DateFormatters.formatServerDateTime(time),
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          const Spacer(),
                                          // Mark as read button
                                          if (annId != null)
                                            TextButton.icon(
                                              onPressed: busy ? null : () => _markAsRead(annId),
                                              icon: busy
                                                  ? const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : const Icon(Icons.done_all, size: 18),
                                              label: const Text('خوانده شد'),
                                              style: TextButton.styleFrom(
                                                foregroundColor: cs.primary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: _items.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
