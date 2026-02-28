import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';

import '../core/auth_store.dart';
import '../core/api_client.dart';
import '../services/announcements_service.dart';
import '../services/notifications_ws_client.dart';
import '../utils/snackbar_helper.dart';

/// دکمهٔ زنگولهٔ اعلانات با badge و دیالوگ مرکز اعلان.
/// در پنل کاربر و پنل کسب‌وکار قابل استفاده است.
class NotificationBellButton extends StatefulWidget {
  final AuthStore authStore;
  final Color? iconColor;

  const NotificationBellButton({
    super.key,
    required this.authStore,
    this.iconColor,
  });

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  NotificationsWsClient? _ws;
  final List<Map<String, dynamic>> _notifications = <Map<String, dynamic>>[];
  int _unreadCount = 0;
  final Set<int> _busyAnnIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadInitialNotifications();
    final apiKey = widget.authStore.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      _ws = createNotificationsWsClient();
      _ws!.connect(
        apiKey: apiKey,
        onMessage: (msg) {
          try {
            final type = '${msg['type'] ?? ''}';
            if (type == 'notification') {
              final title = '${msg['title'] ?? 'پیام'}';
              final body = '${msg['body'] ?? ''}';
              if (!mounted) return;
              setState(() {
                _notifications.insert(0, <String, dynamic>{
                  'title': title,
                  'body': body,
                  'level': '${msg['level'] ?? 'info'}',
                });
                _unreadCount = (_unreadCount + 1).clamp(0, 99);
              });
              if (mounted) {
                ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text('$title: $body'), duration: const Duration(seconds: 4)));
              }
            }
          } catch (_) {}
        },
      );
    }
  }

  @override
  void dispose() {
    try {
      _ws?.disconnect();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadInitialNotifications() async {
    try {
      final annSvc = AnnouncementsService(ApiClient());
      final data = await annSvc.listAnnouncements(page: 1, limit: 5, onlyUnread: true);
      final items = (data['items'] as List? ?? const <dynamic>[])
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final total = (data['total'] is int) ? data['total'] as int : (int.tryParse('${data['total']}') ?? items.length);
      if (!mounted) return;
      setState(() {
        _notifications.clear();
        for (final it in items) {
          _notifications.add(<String, dynamic>{
            'title': '${it['title'] ?? 'اعلان'}',
            'body': '${it['body'] ?? ''}',
            'level': '${it['level'] ?? 'info'}',
            'id': it['id'],
          });
        }
        _unreadCount = total.clamp(0, 99);
      });
    } catch (_) {}
  }

  void _openNotificationCenter() {
    setState(() {
      _unreadCount = 0;
    });
    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final items = _notifications.take(10).toList();
            final ColorScheme cs = Theme.of(context).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.primary.withValues(alpha: 0.8)]),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('مرکز اعلان‌ها', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      tooltip: 'بستن',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              content: LayoutBuilder(
                builder: (ctx, _) {
                  final double dialogWidth = math.min(MediaQuery.of(ctx).size.width - 96, 900);
                  return ConstrainedBox(
                    constraints: BoxConstraints(minWidth: dialogWidth, maxWidth: dialogWidth, maxHeight: 420),
                    child: items.isEmpty
                        ? const SizedBox(height: 140, child: Center(child: Text('اعلانی وجود ندارد')))
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemBuilder: (_, i) {
                              final it = items[i];
                              final level = '${it['level'] ?? 'info'}';
                              IconData icon;
                              Color levelColor;
                              switch (level) {
                                case 'warning':
                                  icon = Icons.warning_amber_rounded;
                                  levelColor = Colors.orange;
                                  break;
                                case 'critical':
                                  icon = Icons.error_outline;
                                  levelColor = Colors.red;
                                  break;
                                default:
                                  icon = Icons.notifications_none;
                                  levelColor = cs.primary;
                              }
                              final int? annId = it['id'] is int ? it['id'] as int : int.tryParse('${it['id']}');
                              final bool busy = annId != null && _busyAnnIds.contains(annId);
                              return Container(
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                                  border: Border(left: BorderSide(color: levelColor, width: 3)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(color: levelColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                                      child: Icon(icon, color: levelColor),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${it['title'] ?? 'اعلان'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text('${it['body'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: levelColor.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(level, style: TextStyle(color: levelColor, fontSize: 11)),
                                              ),
                                              const Spacer(),
                                              TextButton.icon(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  context.go('/user/profile/announcements');
                                                },
                                                icon: const Icon(Icons.open_in_new, size: 16),
                                                label: const Text('جزئیات'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (annId != null)
                                      IconButton(
                                        tooltip: 'خوانده شد',
                                        icon: busy
                                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.done_all, size: 20),
                                        onPressed: busy ? null : () async => _markNotificationRead(annId, dialogSetState: dialogSetState),
                                      ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemCount: items.length,
                          ),
                  );
                },
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('بستن'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/user/profile/announcements');
                  },
                  icon: const Icon(Icons.notifications, size: 18),
                  label: const Text('مشاهده همه اعلان‌ها'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _markNotificationRead(int id, {StateSetter? dialogSetState}) async {
    void refreshDialog() {
      if (dialogSetState != null) {
        dialogSetState(() {});
      }
    }
    setState(() => _busyAnnIds.add(id));
    refreshDialog();
    try {
      await AnnouncementsService(ApiClient()).markRead(id);
      if (!mounted) return;
      setState(() {
        _notifications.removeWhere((e) => (e['id'] is int ? e['id'] == id : int.tryParse('${e['id']}') == id));
      });
      refreshDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('به‌عنوان خوانده‌شده علامت خورد')));
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _busyAnnIds.remove(id));
      } else {
        _busyAnnIds.remove(id);
      }
      refreshDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.iconColor ?? Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: 'اعلان‌ها',
            onPressed: _openNotificationCenter,
            icon: const Icon(Icons.notifications_none),
            color: color,
          ),
          if (_unreadCount > 0)
            Positioned(
              right: 4,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  _unreadCount > 99 ? '99+' : '$_unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
