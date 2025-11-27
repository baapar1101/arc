import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/session_service.dart';
import '../../utils/snackbar_helper.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  final SessionService _sessionService = SessionService(ApiClient());
  List<SessionInfo> _sessions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final sessions = await _sessionService.listSessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در بارگذاری سشن‌ها: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _revokeSession(SessionInfo session) async {
    if (session.isCurrent) {
      SnackBarHelper.showError(context, message: 'نمی‌توانید session فعلی را حذف کنید');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Expanded(child: Text('حذف سشن')),
          ],
        ),
        content: Text('آیا از حذف session "${session.deviceName}" اطمینان دارید؟\nاین عمل غیرقابل بازگشت است.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _sessionService.revokeSession(session.id);
        _loadSessions();
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'Session با موفقیت حذف شد');
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, message: 'خطا در حذف session: $e');
        }
      }
    }
  }

  Future<void> _revokeOtherSessions() async {
    final otherSessions = _sessions.where((s) => !s.isCurrent).toList();
    if (otherSessions.isEmpty) {
      SnackBarHelper.showInfo(context, message: 'هیچ session دیگری وجود ندارد');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Expanded(child: Text('خروج از همه دستگاه‌ها')),
          ],
        ),
        content: Text(
          'آیا از حذف ${otherSessions.length} session دیگر اطمینان دارید؟\n'
          'این عمل باعث خروج از تمام دستگاه‌های دیگر می‌شود.\n'
          'Session فعلی شما حفظ خواهد شد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('حذف همه'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final deletedCount = await _sessionService.revokeOtherSessions();
        _loadSessions();
        if (mounted) {
          SnackBarHelper.showSuccess(
            context,
            message: '$deletedCount session حذف شد',
          );
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, message: 'خطا در حذف sessions: $e');
        }
      }
    }
  }

  IconData _getDeviceIcon(SessionInfo session) {
    if (session.deviceType == 'mobile') {
      return Icons.smartphone;
    } else if (session.deviceType == 'tablet') {
      return Icons.tablet;
    } else {
      return Icons.computer;
    }
  }

  Color _getDeviceColor(SessionInfo session) {
    if (session.deviceType == 'mobile') {
      return Colors.blue;
    } else if (session.deviceType == 'tablet') {
      return Colors.purple;
    } else {
      return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سشن‌های ورود'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSessions,
              child: _sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.devices_outlined,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'هیچ session فعالی وجود ندارد',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // دکمه حذف همه
                        if (_sessions.any((s) => !s.isCurrent))
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: FilledButton.icon(
                              onPressed: _revokeOtherSessions,
                              icon: const Icon(Icons.logout),
                              label: const Text('خروج از همه دستگاه‌ها'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                              ),
                            ),
                          ),
                        // لیست sessions
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _sessions.length,
                            itemBuilder: (context, index) {
                              final session = _sessions[index];
                              return _SessionCard(
                                session: session,
                                theme: theme,
                                colorScheme: colorScheme,
                                deviceIcon: _getDeviceIcon(session),
                                deviceColor: _getDeviceColor(session),
                                onRevoke: session.isCurrent ? null : () => _revokeSession(session),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SessionInfo session;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final IconData deviceIcon;
  final Color deviceColor;
  final VoidCallback? onRevoke;

  const _SessionCard({
    required this.session,
    required this.theme,
    required this.colorScheme,
    required this.deviceIcon,
    required this.deviceColor,
    this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: session.isCurrent
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: deviceColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(deviceIcon, color: deviceColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.deviceName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (session.isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'این دستگاه',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (session.browser != null || session.os != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              if (session.browser != null) session.browser,
                              if (session.os != null) session.os,
                            ].join(' • '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (onRevoke != null)
                  IconButton(
                    onPressed: onRevoke,
                    icon: const Icon(Icons.delete_outline),
                    color: colorScheme.error,
                    tooltip: 'حذف',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: colorScheme.outline.withOpacity(0.1)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'آخرین استفاده: ${session.lastUsedRelative}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (session.ip != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.language, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'IP: ${session.ip}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'ایجاد شده: ${_formatDate(session.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'امروز';
    } else if (diff.inDays == 1) {
      return 'دیروز';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} روز پیش';
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks هفته پیش';
    } else {
      final months = (diff.inDays / 30).floor();
      return '$months ماه پیش';
    }
  }
}

