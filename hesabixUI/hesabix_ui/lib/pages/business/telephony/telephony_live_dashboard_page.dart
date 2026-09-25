import 'package:hesabix_ui/theme/glass.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../services/telephony/telephony_api.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// داشبورد لحظه‌ای مرکز تماس (BLF + تماس‌های فعال).
class TelephonyLiveDashboardPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonyLiveDashboardPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<TelephonyLiveDashboardPage> createState() => _TelephonyLiveDashboardPageState();
}

class _TelephonyLiveDashboardPageState extends State<TelephonyLiveDashboardPage> {
  final _api = TelephonyApi();
  Map<String, dynamic>? _snap;
  Timer? _timer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = await _api.liveSnapshot(widget.businessId);
      if (mounted) {
        setState(() {
          _snap = data;
          _loading = false;
          _error = null;
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

  Color _presenceColor(String s, ColorScheme scheme) {
    switch (s) {
      case 'idle':
        return const Color(0xFF159947);
      case 'ringing':
        return const Color(0xFFD97706);
      case 'busy':
        return scheme.primary;
      default:
        return scheme.outline;
    }
  }

  Future<void> _control(int callId, String action, {String? target}) async {
    try {
      await _api.controlCall(widget.businessId, callId, action: action, target: target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('دستور $action ارسال شد')));
      }
      _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kpis = _snap?['kpis'] as Map? ?? {};
    final blf = (_snap?['blf'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final active = (_snap?['active_calls'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final queues = (_snap?['queues'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد زنده تماس'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading && _snap == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _snap == null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withValues(alpha: 0.14),
                              scheme.surfaceContainerLow,
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('مرکز تماس — لحظه‌ای', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text('به‌روزرسانی هر ۳ ثانیه', style: TextStyle(color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _MiniKpi('فعال', '${kpis['active'] ?? 0}', scheme.primary),
                                _MiniKpi('در انتظار', '${kpis['waiting'] ?? 0}', const Color(0xFFD97706)),
                                _MiniKpi('در مکالمه', '${kpis['talking'] ?? 0}', const Color(0xFF159947)),
                                _MiniKpi('از دست‌رفته امروز', '${kpis['missed_today'] ?? 0}', scheme.error),
                                _MiniKpi('اپراتور آنلاین', '${kpis['operators_online'] ?? 0}', scheme.tertiary),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('وضعیت داخلی‌ها (BLF)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: blf.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: wide ? 6 : (MediaQuery.sizeOf(context).width > 600 ? 4 : 2),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.35,
                        ),
                        itemBuilder: (context, i) {
                          final e = blf[i];
                          final presence = '${e['presence_status'] ?? 'unknown'}';
                          final color = _presenceColor(presence, scheme);
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: color.withValues(alpha: 0.35)),
                              color: color.withValues(alpha: 0.08),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                    const SizedBox(width: 8),
                                    Text('${e['extension']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ],
                                ),
                                const Spacer(),
                                Text('${e['display_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(presence, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      Text('تماس‌های فعال', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (active.isEmpty)
                        Text('تماسی در جریان نیست', style: TextStyle(color: scheme.onSurfaceVariant))
                      else
                        ...active.map((c) {
                          final id = int.tryParse('${c['id']}') ?? 0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              title: Text('${c['from_number_normalized'] ?? c['from_number_raw'] ?? ''} → ${c['extension'] ?? ''}'),
                              subtitle: Text('${c['direction']} · ${c['status']}'),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'نگه داشتن',
                                    onPressed: () => _control(id, 'hold'),
                                    icon: const Icon(Icons.pause_circle_outline),
                                  ),
                                  IconButton(
                                    tooltip: 'ادامه',
                                    onPressed: () => _control(id, 'resume'),
                                    icon: const Icon(Icons.play_circle_outline),
                                  ),
                                  IconButton(
                                    tooltip: 'قطع',
                                    onPressed: () => _control(id, 'hangup'),
                                    icon: Icon(Icons.call_end, color: scheme.error),
                                  ),
                                  IconButton(
                                    tooltip: 'انتقال',
                                    onPressed: () async {
                                      final ctrl = TextEditingController();
                                      final ok = await showGlassDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('انتقال تماس'),
                                          content: TextField(
                                            controller: ctrl,
                                            decoration: const InputDecoration(labelText: 'داخلی مقصد'),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('انتقال')),
                                          ],
                                        ),
                                      );
                                      if (ok == true && ctrl.text.trim().isNotEmpty) {
                                        await _control(id, 'transfer', target: ctrl.text.trim());
                                      }
                                    },
                                    icon: const Icon(Icons.call_split_rounded),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      if (queues.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('صف‌ها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ...queues.map(
                          (q) => ListTile(
                            leading: const Icon(Icons.queue_rounded),
                            title: Text('${q['name']} (${q['queue_code']})'),
                            subtitle: Text('انتظار: ${q['waiting']} · مکالمه: ${q['talking']}'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniKpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
