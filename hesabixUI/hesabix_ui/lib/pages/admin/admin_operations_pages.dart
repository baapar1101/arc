import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

import '../../services/admin_operations_service.dart';
import '../../theme/tokens/extensions.dart';
import 'admin_compact_scaffold.dart';

AdminOperationsService _ops() => AdminOperationsService(ApiClient());

class AdminOperationsHomePage extends StatefulWidget {
  const AdminOperationsHomePage({super.key});

  @override
  State<AdminOperationsHomePage> createState() => _AdminOperationsHomePageState();
}

class _AdminOperationsHomePageState extends State<AdminOperationsHomePage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _ops().home();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.settingsHub;
    final outbox = _data['outbox'] as Map? ?? {};
    final auth = _data['auth_24h'] as Map? ?? {};
    final storage = _data['storage'] as Map? ?? {};
    final businesses = _data['businesses'] as Map? ?? {};
    final jobs = _data['scheduled_jobs'] as Map? ?? {};
    final support = _data['support_billing'] as Map? ?? {};
    final superAdmin = ApiClient.getAuthStore()?.isSuperAdmin == true;
    final fileCount = storage['files'];
    final cards = [
      _Stat(
        adminTx(context, 'صف آماده ارسال', 'Ready to send'),
        '${outbox['retry_due_now'] ?? '—'}',
        route: superAdmin ? '/user/profile/system-settings/notification-outbox' : null,
      ),
      _Stat(
        adminTx(context, 'اعلان در انتظار', 'Pending notifications'),
        '${outbox['pending'] ?? '—'}',
        route: superAdmin ? '/user/profile/system-settings/notification-outbox' : null,
      ),
      _Stat(
        adminTx(context, 'شکست ورود ۲۴ ساعت', 'Failed sign-ins, 24h'),
        '${auth['failed_logins'] ?? '—'}',
        route: '/user/profile/system-settings/reports-failed-logins',
      ),
      _Stat(
        adminTx(context, 'حجم فایل‌ها', 'Stored files'),
        '${_bytes(storage['bytes'])}${fileCount == null ? '' : ' · $fileCount'}',
        route: '/user/profile/system-settings/reports-storage',
      ),
      _Stat(
        adminTx(context, 'درآمد پشتیبانی ۳۰ روز', 'Support revenue, 30 days'),
        '${support['revenue'] ?? '—'}',
        route: '/user/profile/system-settings/reports-support-revenue',
      ),
      _Stat(
        adminTx(context, 'کسب‌وکار کم‌فعال ۹۰ روز', 'Quiet businesses, 90 days'),
        '${businesses['inactive_90d'] ?? '—'}',
        route: '/user/profile/system-settings/reports-inactive-businesses',
      ),
      _Stat(
        adminTx(context, 'کرون ورک‌فلو فعال', 'Active workflow cron jobs'),
        '${jobs['workflow_cron'] ?? '—'}',
        route: '/user/profile/system-settings/schedules',
      ),
      _Stat(
        adminTx(context, 'ارزیابی AI زمان‌بندی‌شده', 'Scheduled AI evaluation'),
        jobs['ai_eval_enabled'] == true
            ? adminTx(context, 'روشن', 'On')
            : adminTx(context, 'خاموش', 'Off'),
        route: '/user/profile/system-settings/ai-eval',
      ),
    ];
    return AdminCompactScaffold(
      title: adminTx(context, 'خانه عملیاتی', 'Operations home'),
      subtitle: adminTx(context, 'صف، ورود، ذخیره‌سازی و کارهای زمان‌بندی‌شده', 'Queue, sign-in, storage, and schedules'),
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: ListView(
          padding: hub.pagePadding,
          children: [
            for (final card in cards) _statTile(context, card),
            SizedBox(height: hub.listTitleGap),
            Text(
              adminTx(context, 'ادامه', 'More'),
              style: hub.listTitleStyle(Theme.of(context).textTheme, color: Theme.of(context).colorScheme.onSurface),
            ),
            _statTile(
              context,
              _Stat(
                adminTx(context, 'لاگ کارهای مدیر', 'Admin audit log'),
                adminTx(context, 'پیکربندی، بکاپ، هدیه، استرداد و صف', 'Configuration, backup, gifts, refunds, and the queue'),
                route: '/user/profile/system-settings/audit-log',
              ),
            ),
            _statTile(
              context,
              _Stat(
                adminTx(context, 'کیف‌پول‌ها', 'Wallets'),
                adminTx(context, 'مانده و استرداد', 'Balances and refunds'),
                route: '/user/profile/system-settings/wallets',
              ),
            ),
            _statTile(
              context,
              _Stat(
                adminTx(context, 'اجرای HScript', 'HScript runs'),
                adminTx(context, 'ممیزی گزارش‌های سفارشی', 'Custom report audit'),
                route: '/user/profile/system-settings/hscript-runs',
              ),
            ),
            _statTile(
              context,
              _Stat(
                adminTx(context, 'انقضای لایسنس', 'License expiry'),
                adminTx(context, '۳۰ روز آینده و سررسیدشدهٔ فعال', 'Next 30 days and overdue active licenses'),
                route: '/user/profile/system-settings/license-expiry',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({super.key});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _ops().auditLogs();
      final raw = data['items'];
      if (!mounted) return;
      setState(() {
        _items = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminCompactScaffold(
      title: adminTx(context, 'لاگ کارهای مدیر', 'Admin audit log'),
      subtitle: adminTx(context, 'پیکربندی، بکاپ، هدیه، استرداد، اسکریپت و صف اعلان', 'Configuration, backup, gifts, refunds, scripts, and the queue'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _recordList(
          context,
          _items,
          titleOf: (item) => _auditActionLabel(context, '${item['action'] ?? ''}'),
          subtitleOf: (item) => _auditSubtitle(context, item),
        ),
      ),
    );
  }
}

class AdminSchedulesPage extends StatefulWidget {
  const AdminSchedulesPage({super.key});

  @override
  State<AdminSchedulesPage> createState() => _AdminSchedulesPageState();
}

class _AdminSchedulesPageState extends State<AdminSchedulesPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _ops().schedules();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = _data['ai_eval'] as Map? ?? {};
    final workflows = (_data['workflows'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return AdminCompactScaffold(
      title: adminTx(context, 'کارهای زمان‌بندی‌شده', 'Scheduled jobs'),
      subtitle: adminTx(context, 'کرون ورک‌فلو و ارزیابی AI', 'Workflow cron and AI evaluation'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: ListView(
          padding: context.settingsHub.pagePadding,
          children: [
            _statTile(
              context,
              _Stat(
                adminTx(context, 'ارزیابی AI', 'AI evaluation'),
                ai['enabled'] == true
                    ? '${ai['cron_expression'] ?? '—'} · ${ai['timezone'] ?? ''}'
                    : adminTx(context, 'خاموش', 'Off'),
                route: '/user/profile/system-settings/ai-eval',
              ),
            ),
            Text(
              adminTx(context, 'ورک‌فلوهای زمان‌بندی‌شده', 'Scheduled workflows'),
              style: context.settingsHub.listTitleStyle(
                Theme.of(context).textTheme,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            _recordList(
              context,
              workflows,
              titleOf: (item) => adminTx(
                context,
                '${item['name'] ?? 'ورک‌فلو'} · کسب‌وکار ${item['business_id']}',
                '${item['name'] ?? 'Workflow'} · business ${item['business_id']}',
              ),
              subtitleOf: (item) => '${item['cron'] ?? '—'} · ${item['timezone'] ?? ''}',
              shrink: true,
            ),
          ],
        ),
      ),
    );
  }
}

class AdminWalletsPage extends StatefulWidget {
  const AdminWalletsPage({super.key});

  @override
  State<AdminWalletsPage> createState() => _AdminWalletsPageState();
}

class _AdminWalletsPageState extends State<AdminWalletsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _ops().wallets();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refund(Map<String, dynamic> wallet) async {
    final txController = TextEditingController();
    final confirmController = TextEditingController();
    final reasonController = TextEditingController();
    final businessId = int.tryParse('${wallet['business_id']}') ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var phraseError = '';
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(adminTx(context, 'استرداد کسب‌وکار $businessId', 'Refund business $businessId')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: txController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'شناسه تراکنش', 'Transaction id'),
                    ),
                  ),
                  TextField(
                    controller: reasonController,
                    decoration: InputDecoration(labelText: adminTx(context, 'دلیل', 'Reason')),
                  ),
                  TextField(
                    controller: confirmController,
                    decoration: InputDecoration(
                      labelText: adminTx(context, 'عبارت تأیید: استرداد یا REFUND', 'Type استرداد or REFUND'),
                      errorText: phraseError.isEmpty ? null : phraseError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(adminTx(context, 'انصراف', 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final phrase = confirmController.text.trim();
                    final txId = int.tryParse(txController.text.trim());
                    if (txId == null || txId <= 0) {
                      setLocal(() {
                        phraseError = adminTx(context, 'شناسه تراکنش نامعتبر است', 'Invalid transaction id');
                      });
                      return;
                    }
                    if (phrase != 'استرداد' && phrase != 'REFUND') {
                      setLocal(() {
                        phraseError = adminTx(
                          context,
                          'عبارت تأیید باید استرداد یا REFUND باشد',
                          'Confirmation must be استرداد or REFUND',
                        );
                      });
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: Text(adminTx(context, 'ثبت', 'Submit')),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) {
      txController.dispose();
      confirmController.dispose();
      reasonController.dispose();
      return;
    }
    try {
      await _ops().refund(
        businessId: businessId,
        transactionId: int.parse(txController.text.trim()),
        confirmation: confirmController.text.trim(),
        reason: reasonController.text.trim(),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: adminTx(context, 'استرداد ثبت شد', 'Refund recorded'),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      txController.dispose();
      confirmController.dispose();
      reasonController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminCompactScaffold(
      title: adminTx(context, 'کیف‌پول‌ها', 'Wallets'),
      subtitle: adminTx(context, 'مانده کسب‌وکارها و استرداد مدیریتی', 'Business balances and admin refunds'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: ListView.builder(
          padding: context.settingsHub.pagePadding,
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            return ListTile(
              dense: true,
              title: Text(
                adminTx(
                  context,
                  '${item['business_name'] ?? adminTx(context, 'کسب‌وکار', 'Business')} · ${item['business_id']}',
                  '${item['business_name'] ?? 'Business'} · ${item['business_id']}',
                ),
                style: context.settingsHub.cardTitleStyle(
                  Theme.of(context).textTheme,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                adminTx(
                  context,
                  'آزاد ${item['available_balance']} · بلوکه ${item['pending_balance']} · ${item['status']}',
                  'Available ${item['available_balance']} · Pending ${item['pending_balance']} · ${item['status']}',
                ),
                style: context.settingsHub.cardSubtitleStyle(
                  Theme.of(context).textTheme,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              trailing: ApiClient.getAuthStore()?.isSuperAdmin == true
                  ? TextButton(
                      onPressed: () => _refund(item),
                      child: Text(adminTx(context, 'استرداد', 'Refund')),
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class AdminHscriptRunsPage extends StatefulWidget {
  const AdminHscriptRunsPage({super.key});

  @override
  State<AdminHscriptRunsPage> createState() => _AdminHscriptRunsPageState();
}

class _AdminHscriptRunsPageState extends State<AdminHscriptRunsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _ops().hscriptRuns();
      final raw = data['items'];
      if (!mounted) return;
      setState(() {
        _items = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminCompactScaffold(
      title: adminTx(context, 'اجرای HScript', 'HScript runs'),
      subtitle: adminTx(context, 'همه کسب‌وکارها', 'All businesses'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _recordList(
          context,
          _items,
          titleOf: (item) => adminTx(
            context,
            'کسب‌وکار ${item['business_id']} · گزارش ${item['report_id']} · ${item['status']}',
            'Business ${item['business_id']} · report ${item['report_id']} · ${item['status']}',
          ),
          subtitleOf: (item) =>
              '${item['created_at'] ?? ''} · ${item['duration_ms'] ?? '—'} ms · ${item['error_message'] ?? ''}',
        ),
      ),
    );
  }
}

class AdminLicenseExpiryPage extends StatefulWidget {
  const AdminLicenseExpiryPage({super.key});

  @override
  State<AdminLicenseExpiryPage> createState() => _AdminLicenseExpiryPageState();
}

class _AdminLicenseExpiryPageState extends State<AdminLicenseExpiryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _ops().expiringLicenses();
      final raw = data['items'];
      if (!mounted) return;
      setState(() {
        _items = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminCompactScaffold(
      title: adminTx(context, 'انقضای لایسنس افزونه', 'Plugin license expiry'),
      subtitle: adminTx(context, '۳۰ روز آینده، تازه‌منقضی، و لایسنس فعالِ سررسیدشده', 'Next 30 days, recently expired, and overdue licenses still marked active'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _recordList(
          context,
          _items,
          titleOf: (item) => '${item['plugin_name'] ?? item['plugin_code']} · ${item['business_name']}',
          subtitleOf: (item) =>
              '${item['status']} · ${item['ends_at'] ?? '—'}'
              '${item['expired'] == true ? adminTx(context, ' · منقضی', ' · expired') : ''}',
        ),
      ),
    );
  }
}

class AdminSystemReportPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<Map<String, dynamic>> Function(AdminOperationsService ops) load;

  const AdminSystemReportPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.load,
  });

  @override
  State<AdminSystemReportPage> createState() => _AdminSystemReportPageState();
}

class _AdminSystemReportPageState extends State<AdminSystemReportPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load(_ops());
      if (!mounted) return;
      setState(() => _data = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scalars = <_Stat>[];
    final lists = <({String key, List<Map<String, dynamic>> rows, int total})>[];
    _data.forEach((key, value) {
      if (value is List) {
        final rows = value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (rows.isNotEmpty) {
          lists.add((
            key: key,
            rows: rows.length > 20 ? rows.sublist(0, 20) : rows,
            total: rows.length,
          ));
        }
        return;
      }
      if (value is Map) {
        final flat = value.entries.every((e) => e.value is! Map && e.value is! List);
        if (flat) {
          for (final entry in value.entries) {
            scalars.add(_Stat('$key.${entry.key}', _formatStatValue('$key.${entry.key}', entry.value)));
          }
        }
        return;
      }
      if (value == null) return;
      scalars.add(_Stat(key, _formatStatValue(key, value)));
    });
    return AdminCompactScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      backFallback: '/user/profile/system-settings/reports',
      actions: [IconButton(onPressed: _load, tooltip: adminTx(context, 'بازخوانی', 'Refresh'), icon: const Icon(Icons.refresh, size: 20))],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: ListView(
          padding: context.settingsHub.pagePadding,
          children: [
            for (final stat in scalars)
              _statTile(context, _Stat(_reportLabel(context, stat.label), stat.value)),
            for (final group in lists) ...[
              SizedBox(height: context.settingsHub.listTitleGap),
              Text(
                _reportLabel(context, group.key),
                style: context.settingsHub.listTitleStyle(
                  Theme.of(context).textTheme,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              _recordList(
                context,
                group.rows,
                titleOf: (item) => item.values.take(2).map((v) => '$v').join(' · '),
                subtitleOf: (item) => item.entries
                    .map((e) => '${_reportLabel(context, e.key)}: ${_formatStatValue(e.key, e.value)}')
                    .join(' · '),
                shrink: true,
              ),
              if (group.total > group.rows.length)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    adminTx(
                      context,
                      '${group.rows.length} از ${group.total}',
                      '${group.rows.length} of ${group.total}',
                    ),
                    style: context.settingsHub.cardSubtitleStyle(
                      Theme.of(context).textTheme,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class NotificationOutboxAdminPage extends StatefulWidget {
  const NotificationOutboxAdminPage({super.key});

  @override
  State<NotificationOutboxAdminPage> createState() => _NotificationOutboxAdminPageState();
}

class _NotificationOutboxAdminPageState extends State<NotificationOutboxAdminPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  final _phrase = TextEditingController();
  final _eventKey = TextEditingController();
  final _note = TextEditingController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phrase.dispose();
    _eventKey.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _ops().outboxSummary();
      if (!mounted) return;
      setState(() => _summary = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abandon() async {
    final expected = '${_summary['abandon_confirm_phrase'] ?? ''}'.trim();
    final typed = _phrase.text.trim();
    if (expected.isEmpty || typed != expected) {
      SnackBarHelper.showError(
        context,
        message: adminTx(
          context,
          'عبارت تأیید باید دقیقاً همان عبارت سرور باشد.',
          'Type the server confirmation phrase exactly.',
        ),
      );
      return;
    }
    setState(() => _running = true);
    try {
      final result = await _ops().abandonOutbox(
        confirmPhrase: _phrase.text.trim(),
        eventKey: _eventKey.text.trim(),
        adminNote: _note.text.trim(),
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: '${adminTx(context, 'رها شد', 'Abandoned')}: ${result['abandoned_count'] ?? result}');
      _phrase.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrase = '${_summary['abandon_confirm_phrase'] ?? ''}';
    final retry = _summary['retry_queue'] as Map? ?? {};
    final pending = _summary['pending'] as Map? ?? {};
    return AdminCompactScaffold(
      title: adminTx(context, 'صف اعلان', 'Notification queue'),
      subtitle: adminTx(context, 'فقط مدیر کل؛ رها کردن صف با عبارت تأیید', 'Super admin only; abandon requires the confirmation phrase'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      body: AdminLoadBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: ListView(
          padding: context.settingsHub.pagePadding,
          children: [
            _statTile(
              context,
              _Stat(adminTx(context, 'آماده ارسال مجدد', 'Ready to retry'), '${retry['failed_due_now'] ?? '—'}'),
            ),
            _statTile(
              context,
              _Stat(adminTx(context, 'در انتظار', 'Pending'), '${pending['all_channels'] ?? '—'}'),
            ),
            Text(
              adminTx(context, 'عبارت تأیید سرور: $phrase', 'Server confirmation phrase: $phrase'),
              style: context.settingsHub.cardSubtitleStyle(
                Theme.of(context).textTheme,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phrase,
              decoration: InputDecoration(
                labelText: adminTx(context, 'عبارت تأیید', 'Confirmation phrase'),
                isDense: true,
              ),
            ),
            TextField(
              controller: _eventKey,
              decoration: InputDecoration(
                labelText: adminTx(context, 'کلید رویداد (اختیاری)', 'Event key (optional)'),
                isDense: true,
              ),
            ),
            TextField(
              controller: _note,
              decoration: InputDecoration(
                labelText: adminTx(context, 'یادداشت', 'Note'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _running ? null : _abandon,
              child: Text(
                _running
                    ? adminTx(context, 'در حال اجرا', 'Working')
                    : adminTx(context, 'رها کردن ردیف‌های مطابق فیلتر', 'Abandon matching rows'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AiOpsMetricsBanner extends StatefulWidget {
  const AiOpsMetricsBanner({super.key});

  @override
  State<AiOpsMetricsBanner> createState() => _AiOpsMetricsBannerState();
}

class _AiOpsMetricsBannerState extends State<AiOpsMetricsBanner> {
  String _text = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _ops().aiOpsMetrics();
      if (!mounted) return;
      setState(() {
        _text = adminTx(
          context,
          'ناهماهنگی زبان تفکر: ${data['reasoning_language_mismatch'] ?? 0} · خطای ابزار: ${data['tool_error'] ?? 0}',
          'Reasoning language mismatch: ${data['reasoning_language_mismatch'] ?? 0} · Tool errors: ${data['tool_error'] ?? 0}',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _text = ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _text.isEmpty
        ? adminTx(context, 'در حال خواندن…', 'Loading…')
        : _text;
    return _statTile(context, _Stat(adminTx(context, 'متریک این فرآیند', 'This process'), value));
  }
}

class _Stat {
  final String label;
  final String value;
  final String? route;
  const _Stat(this.label, this.value, {this.route});
}

Widget _statTile(BuildContext context, _Stat stat) {
  final theme = Theme.of(context);
  final hub = context.settingsHub;
  final rtl = Directionality.of(context) == TextDirection.rtl;
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    onTap: stat.route == null ? null : () => context.push(stat.route!),
    title: Text(stat.label, style: hub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface)),
    subtitle: Text(stat.value, style: hub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
    trailing: stat.route == null
        ? null
        : Icon(rtl ? Icons.chevron_left : Icons.chevron_right, size: 18),
  );
}

Widget _recordList(
  BuildContext context,
  List<Map<String, dynamic>> items, {
  required String Function(Map<String, dynamic>) titleOf,
  required String Function(Map<String, dynamic>) subtitleOf,
  bool shrink = false,
}) {
  if (items.isEmpty) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(adminTx(context, 'موردی نیست', 'Nothing to show')),
    );
  }
  final list = ListView.separated(
    shrinkWrap: shrink,
    physics: shrink ? const NeverScrollableScrollPhysics() : null,
    itemCount: items.length,
    separatorBuilder: (_, __) => const Divider(height: 1),
    itemBuilder: (context, index) {
      final item = items[index];
      final hub = context.settingsHub;
      final theme = Theme.of(context);
      return ListTile(
        dense: true,
        title: Text(
          titleOf(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: hub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
        ),
        subtitle: Text(
          subtitleOf(item),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: hub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurface.withValues(alpha: 0.65)),
        ),
      );
    },
  );
  if (shrink) return list;
  return list;
}

String _formatStatValue(String key, Object? value) {
  if (key == 'bytes' || key.endsWith('.bytes') || key == 'total_bytes') {
    return _bytes(value);
  }
  return '${value ?? '—'}';
}

String _auditSubtitle(BuildContext context, Map<String, dynamic> item) {
  final who = item['actor_name'] ?? item['actor_user_id'] ?? '—';
  final base = '${item['created_at'] ?? ''} · $who · ${item['summary'] ?? ''}';
  final meta = item['metadata'];
  if (meta is! Map) return base;
  final fields = meta['fields'];
  final names = fields is List
      ? fields.map((e) => '$e').where((e) => e.isNotEmpty).join(', ')
      : '';
  final keyChanged = meta['api_key_changed'] == true
      ? adminTx(context, 'کلید عوض شد', 'key changed')
      : '';
  final extra = [names, keyChanged].where((part) => part.isNotEmpty).join(' · ');
  if (extra.isEmpty) return base;
  return '$base · $extra';
}

String _auditActionLabel(BuildContext context, String action) {
  final en = Localizations.localeOf(context).languageCode == 'en';
  const fa = {
    'system_configuration.update': 'به‌روزرسانی پیکربندی',
    'database.backup': 'بکاپ دیتابیس',
    'database.restore': 'ریستور دیتابیس',
    'wallet.gift': 'شارژ هدیه',
    'wallet.refund': 'استرداد کیف‌پول',
    'admin_script.run': 'اجرای اسکریپت',
    'legacy_import.run': 'ایمپورت دیتابیس قدیمی',
    'notifications.outbox_abandon': 'رها کردن صف اعلان',
    'notifications.channels_update': 'به‌روزرسانی کانال اعلان',
    'ai.credential_update': 'به‌روزرسانی اعتبارنامه هوش مصنوعی',
  };
  const enLabels = {
    'system_configuration.update': 'Configuration update',
    'database.backup': 'Database backup',
    'database.restore': 'Database restore',
    'wallet.gift': 'Gift balance',
    'wallet.refund': 'Wallet refund',
    'admin_script.run': 'Script run',
    'legacy_import.run': 'Legacy import',
    'notifications.outbox_abandon': 'Notification queue abandon',
    'notifications.channels_update': 'Notification channel update',
    'ai.credential_update': 'AI credential update',
  };
  final table = en ? enLabels : fa;
  return table[action] ?? action;
}

String _reportLabel(BuildContext context, String key) {
  final en = Localizations.localeOf(context).languageCode == 'en';
  const fa = {
    'revenue': 'درآمد',
    'paid_count': 'پرداخت‌شده',
    'failed_count': 'ناموفق',
    'awaiting_payment_count': 'در انتظار پرداخت',
    'success_rate_pct': 'نرخ موفقیت',
    'active_subscriptions': 'اشتراک فعال',
    'active_only': 'فقط فعال',
    'grace_subscriptions': 'مهلت',
    'expiring_in_7_days': 'انقضا تا ۷ روز',
    'approximate_mrr': 'درآمد ماهانه تقریبی',
    'total_bytes': 'حجم کل',
    'period_hours': 'بازه (ساعت)',
    'days': 'روز',
    'date_from': 'از تاریخ',
    'date_to': 'تا تاریخ',
    'items': 'ردیف‌ها',
    'recent': 'رویدادهای اخیر',
    'revenue_by_plan': 'درآمد به تفکیک پلن',
    'revenue_by_gateway': 'درآمد به تفکیک درگاه',
    'subscriptions_by_plan': 'اشتراک به تفکیک پلن',
    'timeseries': 'روند روزانه',
    'by_type': 'به تفکیک نوع',
  };
  const enLabels = {
    'revenue': 'Revenue',
    'paid_count': 'Paid',
    'failed_count': 'Failed',
    'awaiting_payment_count': 'Awaiting payment',
    'success_rate_pct': 'Success rate',
    'active_subscriptions': 'Active subscriptions',
    'active_only': 'Active only',
    'grace_subscriptions': 'Grace',
    'expiring_in_7_days': 'Expiring in 7 days',
    'approximate_mrr': 'Approximate MRR',
    'total_bytes': 'Total size',
    'period_hours': 'Window (hours)',
    'days': 'Days',
    'date_from': 'From',
    'date_to': 'To',
    'items': 'Rows',
    'recent': 'Recent events',
    'revenue_by_plan': 'Revenue by plan',
    'revenue_by_gateway': 'Revenue by gateway',
    'subscriptions_by_plan': 'Subscriptions by plan',
    'timeseries': 'Daily trend',
    'by_type': 'By type',
  };
  final table = en ? enLabels : fa;
  if (key.contains('.')) {
    final parts = key.split('.');
    return parts.map((part) => table[part] ?? part).join(' · ');
  }
  return table[key] ?? key;
}

String _bytes(Object? value) {
  if (value == null) return '—';
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  if (n == null) return '—';
  if (n >= 1024 * 1024 * 1024) return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (n >= 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (n >= 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${n.toStringAsFixed(0)} B';
}
