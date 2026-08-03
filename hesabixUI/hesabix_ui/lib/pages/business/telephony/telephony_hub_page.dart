import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../services/telephony/telephony_api.dart';
import '../../widgets/telephony/telephony_dialer_sheet.dart';
import '../../widgets/telephony/telephony_recording_player.dart';
import '../../services/telephony/telephony_session_controller.dart';

class TelephonyHubPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonyHubPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<TelephonyHubPage> createState() => _TelephonyHubPageState();
}

class _TelephonyHubPageState extends State<TelephonyHubPage> {
  final _api = TelephonyApi();
  Map<String, dynamic>? _dashboard;
  bool _loading = true;
  String? _error;

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
      final data = await _api.getDashboard(widget.businessId);
      if (mounted) {
        setState(() {
          _dashboard = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = _dashboard?['today'] as Map? ?? {};
    final pbx = (_dashboard?['pbx_connections'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      scheme.primary.withValues(alpha: 0.16),
                      scheme.tertiary.withValues(alpha: 0.10),
                      scheme.surfaceContainerLow,
                    ],
                  ),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.phone_in_talk_rounded, color: scheme.primary, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'مرکز تماس',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اتصال Issabel/Asterisk · Screen Pop · Click-to-Call',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: () => showTelephonyDialerSheet(
                            context,
                            businessId: widget.businessId,
                            session: TelephonySessionStore.instance.controller
                              ..bindBusiness(widget.businessId, pluginActive: true),
                          ),
                          icon: const Icon(Icons.dialpad_rounded),
                          label: const Text('شماره‌گیر'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/calls')),
                          icon: const Icon(Icons.history_rounded),
                          label: const Text('تاریخچه'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/live')),
                          icon: const Icon(Icons.monitor_heart_outlined),
                          label: const Text('زنده'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/reports')),
                          icon: const Icon(Icons.insights_outlined),
                          label: const Text('گزارش'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.go(context.businessPanelUrl(widget.businessId, 'settings/telephony')),
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('تنظیمات'),
                        ),
                        TextButton.icon(
                          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/softphone')),
                          icon: const Icon(Icons.headset_mic_outlined),
                          label: const Text('Softphone'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                  ),
                  delegate: SliverChildListDelegate([
                    _KpiTile(label: 'ورودی امروز', value: '${today['inbound'] ?? 0}', icon: Icons.call_received_rounded, color: scheme.primary),
                    _KpiTile(label: 'خروجی امروز', value: '${today['outbound'] ?? 0}', icon: Icons.call_made_rounded, color: scheme.tertiary),
                    _KpiTile(label: 'پاسخ‌داده‌شده', value: '${today['answered'] ?? 0}', icon: Icons.call_rounded, color: const Color(0xFF159947)),
                    _KpiTile(label: 'از دست‌رفته', value: '${today['missed'] ?? 0}', icon: Icons.call_missed_rounded, color: scheme.error),
                    _KpiTile(label: 'تماس فعال', value: '${_dashboard?['active_calls'] ?? 0}', icon: Icons.graphic_eq_rounded, color: const Color(0xFFD97706)),
                    _KpiTile(label: 'از دست‌رفته من', value: '${today['my_missed'] ?? 0}', icon: Icons.person_off_outlined, color: scheme.secondary),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text('وضعیت مراکز تلفن', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
              if (pbx.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      ),
                      child: Column(
                        children: [
                          const Text('هنوز مرکز تلفنی متصل نشده است.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () =>
                                context.go(context.businessPanelUrl(widget.businessId, 'settings/telephony')),
                            child: const Text('اتصال Issabel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final row = pbx[i];
                      final online = '${row['status']}' == 'online';
                      return ListTile(
                        leading: Icon(
                          Icons.dns_rounded,
                          color: online ? const Color(0xFF159947) : scheme.outline,
                        ),
                        title: Text('${row['name']}'),
                        subtitle: Text('${row['pbx_type']} · ${row['status']}'),
                        trailing: online
                            ? const Chip(label: Text('آنلاین'), visualDensity: VisualDensity.compact)
                            : const Chip(label: Text('آفلاین'), visualDensity: VisualDensity.compact),
                      );
                    },
                    childCount: pbx.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface,
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class TelephonyCallsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonyCallsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<TelephonyCallsPage> createState() => _TelephonyCallsPageState();
}

class _TelephonyCallsPageState extends State<TelephonyCallsPage> {
  final _api = TelephonyApi();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _filterStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.listCalls(
        widget.businessId,
        status: _filterStatus,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      final items = (data['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'missed':
        return scheme.error;
      case 'completed':
      case 'answered':
        return const Color(0xFF159947);
      case 'ringing':
        return const Color(0xFFD97706);
      default:
        return scheme.outline;
    }
  }

  String _statusFa(String status) {
    switch (status) {
      case 'missed':
        return 'از دست‌رفته';
      case 'completed':
        return 'پایان‌یافته';
      case 'answered':
        return 'پاسخ داده شد';
      case 'ringing':
        return 'زنگ';
      case 'busy':
        return 'اشغال';
      case 'failed':
        return 'ناموفق';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تاریخچه تماس‌ها')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'جستجوی شماره یا یادداشت',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final e in [
                  (null, 'همه'),
                  ('missed', 'از دست‌رفته'),
                  ('completed', 'موفق'),
                  ('ringing', 'فعال'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(e.$2),
                      selected: _filterStatus == e.$1,
                      onSelected: (_) {
                        setState(() => _filterStatus = e.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = _items[i];
                        final status = '${c['status'] ?? ''}';
                        final dir = '${c['direction'] ?? ''}';
                        final peer = dir == 'inbound'
                            ? (c['from_number_normalized'] ?? c['from_number_raw'])
                            : (c['to_number_normalized'] ?? c['to_number_raw']);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(status, scheme).withValues(alpha: 0.15),
                            child: Icon(
                              dir == 'inbound' ? Icons.call_received_rounded : Icons.call_made_rounded,
                              color: _statusColor(status, scheme),
                            ),
                          ),
                          title: Text('$peer'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_statusFa(status)} · داخلی ${c['extension'] ?? '—'} · ${c['duration_sec'] ?? 0} ثانیه',
                              ),
                              if ('${c['recording_status']}' == 'available')
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: TelephonyRecordingPlayer(
                                    businessId: widget.businessId,
                                    callId: int.parse('${c['id']}'),
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: '${c['recording_status']}' == 'available',
                          trailing: Text('${c['started_at'] ?? ''}'.split('T').first),
                          onTap: () async {
                            final note = TextEditingController(text: '${c['note'] ?? ''}');
                            final category = TextEditingController(text: '${c['category'] ?? ''}');
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('جزئیات تماس'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: note,
                                      minLines: 3,
                                      maxLines: 5,
                                      decoration: const InputDecoration(labelText: 'یادداشت'),
                                    ),
                                    TextField(
                                      controller: category,
                                      decoration: const InputDecoration(
                                        labelText: 'دسته‌بندی (فروش/پشتیبانی/مالی)',
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بستن')),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('ذخیره'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _api.patchCall(widget.businessId, int.parse('${c['id']}'), {
                                'note': note.text,
                                'category': category.text.trim().isEmpty ? null : category.text.trim(),
                              });
                              _load();
                            }
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class TelephonySettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonySettingsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<TelephonySettingsPage> createState() => _TelephonySettingsPageState();
}

class _TelephonySettingsPageState extends State<TelephonySettingsPage> {
  final _api = TelephonyApi();
  List<Map<String, dynamic>> _pbx = [];
  List<Map<String, dynamic>> _extensions = [];
  List<Map<String, dynamic>> _userExt = [];
  Map<String, dynamic>? _settings;
  bool _loading = true;
  String? _freshToken;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await _api.getSettings(widget.businessId);
      final pbx = await _api.listPbx(widget.businessId);
      final ext = await _api.listExtensions(widget.businessId);
      final ue = await _api.listUserExtensions(widget.businessId);
      if (mounted) {
        setState(() {
          _settings = settings;
          _pbx = pbx;
          _extensions = ext;
          _userExt = ue;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _addPbx() async {
    final nameCtrl = TextEditingController(text: 'مرکز تلفن اصلی');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('افزودن مرکز تلفن'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ایجاد')),
        ],
      ),
    );
    if (ok != true) return;
    final created = await _api.createPbx(widget.businessId, {
      'name': nameCtrl.text.trim(),
      'pbx_type': 'issabel',
    });
    setState(() => _freshToken = created['connector_token']?.toString());
    await _load();
  }

  Future<void> _addExtension() async {
    if (_pbx.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ابتدا مرکز تلفن بسازید')));
      return;
    }
    final extCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final pbxId = _pbx.first['id'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('افزودن داخلی'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: extCtrl, decoration: const InputDecoration(labelText: 'شماره داخلی')),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام نمایشی')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    await _api.upsertExtension(widget.businessId, {
      'pbx_id': pbxId,
      'extension': extCtrl.text.trim(),
      'display_name': nameCtrl.text.trim(),
    });
    await _load();
  }

  Future<void> _mapMe() async {
    if (_extensions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ابتدا داخلی تعریف کنید')));
      return;
    }
    final userId = widget.authStore.currentUserId;
    if (userId == null) return;
    final ext = _extensions.first;
    await _api.upsertUserExtension(widget.businessId, {
      'user_id': userId,
      'extension_id': ext['id'],
      'is_primary': true,
      'receive_screen_pop': true,
      'can_click_to_call': true,
    });
    await _load();
    TelephonySessionStore.instance.controller.refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('داخلی به حساب شما وصل شد')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات مرکز تماس')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPbx,
        icon: const Icon(Icons.add_rounded),
        label: const Text('مرکز تلفن'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_freshToken != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('توکن Connector (فقط یک‌بار نمایش داده می‌شود)', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SelectableText(_freshToken!, style: const TextStyle(fontFamily: 'monospace')),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _freshToken!));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کپی شد')));
                            }
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('کپی توکن'),
                        ),
                      ],
                    ),
                  ),
                Text('مراحل راه‌اندازی', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('۱) مرکز تلفن بسازید و توکن را کپی کنید\n۲) Connector را روی Issabel نصب کنید\n۳) داخلی‌ها را تعریف و به کاربران وصل کنید'),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Screen Pop'),
                  subtitle: const Text('نمایش اطلاعات تماس‌گیرنده هنگام زنگ'),
                  value: _settings?['screen_pop_enabled'] == true,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'screen_pop_enabled': v});
                    _load();
                  },
                ),
                SwitchListTile(
                  title: const Text('ساخت خودکار فعالیت CRM'),
                  subtitle: const Text('ثبت فعالیت تماس پس از پایان مکالمه'),
                  value: _settings?['auto_create_activity'] != false,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'auto_create_activity': v});
                    _load();
                  },
                ),
                SwitchListTile(
                  title: const Text('فرم اجباری پس از تماس'),
                  subtitle: const Text('اپراتور باید نتیجه تماس را ثبت کند'),
                  value: _settings?['post_call_form_required'] == true,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'post_call_form_required': v});
                    _load();
                  },
                ),
                SwitchListTile(
                  title: const Text('وظیفه برای تماس از دست‌رفته'),
                  subtitle: const Text('ساخت تسک پیگیری پس از تماس بی‌پاسخ'),
                  value: _settings?['missed_call_create_task'] == true,
                  onChanged: (v) async {
                    await _api.updateSettings(widget.businessId, {'missed_call_create_task': v});
                    _load();
                  },
                ),
                if (_settings?['missed_call_create_task'] == true)
                  ListTile(
                    title: const Text('مهلت پیگیری (دقیقه)'),
                    subtitle: Text('${_settings?['missed_call_task_due_minutes'] ?? 60} دقیقه'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'کاهش',
                          onPressed: () async {
                            final cur = int.tryParse('${_settings?['missed_call_task_due_minutes']}') ?? 60;
                            final next = (cur - 15).clamp(15, 480);
                            await _api.updateSettings(widget.businessId, {'missed_call_task_due_minutes': next});
                            _load();
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'افزایش',
                          onPressed: () async {
                            final cur = int.tryParse('${_settings?['missed_call_task_due_minutes']}') ?? 60;
                            final next = (cur + 15).clamp(15, 480);
                            await _api.updateSettings(widget.businessId, {'missed_call_task_due_minutes': next});
                            _load();
                          },
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  title: const Text('دسترسی به ضبط مکالمه'),
                  subtitle: Text(
                    '${_settings?['recording_access_mode']}' == 'all_operators'
                        ? 'همه اپراتورها'
                        : 'بر اساس مجوز listen_recordings',
                  ),
                  trailing: DropdownButton<String>(
                    value: '${_settings?['recording_access_mode'] ?? 'permission_based'}',
                    items: const [
                      DropdownMenuItem(value: 'permission_based', child: Text('مجوزمحور')),
                      DropdownMenuItem(value: 'all_operators', child: Text('همه')),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await _api.updateSettings(widget.businessId, {'recording_access_mode': v});
                      _load();
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('مراکز تلفن'),
                  trailing: TextButton(onPressed: _addPbx, child: const Text('افزودن')),
                ),
                ..._pbx.map(
                  (p) => ListTile(
                    leading: Icon(
                      Icons.cloud_done_outlined,
                      color: '${p['status']}' == 'online' ? const Color(0xFF159947) : scheme.outline,
                    ),
                    title: Text('${p['name']}'),
                    subtitle: Text('${p['status']} · ${p['connector_token_prefix'] ?? ''}…'),
                    trailing: TextButton(
                      onPressed: () async {
                        final r = await _api.rotateToken(widget.businessId, int.parse('${p['id']}'));
                        setState(() => _freshToken = r['connector_token']?.toString());
                        await _load();
                      },
                      child: const Text('توکن جدید'),
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('داخلی‌ها'),
                  trailing: TextButton(onPressed: _addExtension, child: const Text('افزودن')),
                ),
                ..._extensions.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text('${e['extension']}'),
                    subtitle: Text('${e['display_name'] ?? ''}'),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('نگاشت کاربر ↔ داخلی'),
                  trailing: TextButton(onPressed: _mapMe, child: const Text('وصل کردن من')),
                ),
                ..._userExt.map(
                  (e) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text('کاربر ${e['user_id']} → داخلی ${e['extension']}'),
                    subtitle: Text(e['is_primary'] == true ? 'اصلی' : 'فرعی'),
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('عملیات و سلامت'),
                  subtitle: const Text('متریک‌ها و صف خطاهای Connector'),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        final metrics = await _api.opsMetrics(widget.businessId);
                        final dlq = await _api.deadLetters(widget.businessId);
                        if (!mounted) return;
                        await showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (ctx) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: SizedBox(
                                height: MediaQuery.sizeOf(ctx).height * 0.7,
                                child: ListView(
                                  children: [
                                    Text('متریک‌ها', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    Text('${metrics['metrics']}'),
                                    Text('DLQ باز: ${metrics['open_dlq']}'),
                                    const Divider(),
                                    Text('Dead letters', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    ...dlq.map(
                                      (d) => ListTile(
                                        title: Text('${d['error_message']}'),
                                        subtitle: Text('${d['created_at']}'),
                                        trailing: TextButton(
                                          onPressed: () async {
                                            await _api.resolveDeadLetter(widget.businessId, int.parse('${d['id']}'));
                                            Navigator.pop(ctx);
                                          },
                                          child: const Text('حل شد'),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: const Text('مشاهده'),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}
