import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../services/telephony/softphone_engine.dart';
import '../../../services/telephony/telephony_session_controller.dart';
import '../../../widgets/telephony/telephony_dialer_sheet.dart';

/// Softphone سازمانی — حالت Relay از طریق Connector (بدون expose کردن PBX).
class TelephonySoftphonePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonySoftphonePage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<TelephonySoftphonePage> createState() => _TelephonySoftphonePageState();
}

class _TelephonySoftphonePageState extends State<TelephonySoftphonePage> {
  late final SoftphoneEngine _engine;
  final _destCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _engine = SoftphoneEngineStore.instance.obtain(
      businessId: widget.businessId,
      authStore: widget.authStore,
    );
    _engine.addListener(_onEngine);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _engine.refreshHealth();
    });
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngine);
    // Engine سراسری است؛ dispose نمی‌شود تا Phone Bar هم بتواند استفاده کند.
    _destCtrl.dispose();
    super.dispose();
  }

  String _stateLabel(SoftphoneConnectionState s) {
    switch (s) {
      case SoftphoneConnectionState.idle:
        return 'آفلاین';
      case SoftphoneConnectionState.connecting:
        return 'در حال اتصال…';
      case SoftphoneConnectionState.registered:
        return 'آماده پاسخگویی';
      case SoftphoneConnectionState.ringing:
        return 'زنگ';
      case SoftphoneConnectionState.inCall:
        return 'در حال مکالمه';
      case SoftphoneConnectionState.reconnecting:
        return 'اتصال مجدد…';
      case SoftphoneConnectionState.error:
        return 'خطا';
      case SoftphoneConnectionState.ended:
        return 'پایان سشن';
    }
  }

  Color _stateColor(ColorScheme scheme, SoftphoneConnectionState s) {
    switch (s) {
      case SoftphoneConnectionState.registered:
        return const Color(0xFF059669);
      case SoftphoneConnectionState.ringing:
        return const Color(0xFFD97706);
      case SoftphoneConnectionState.inCall:
        return scheme.primary;
      case SoftphoneConnectionState.error:
        return scheme.error;
      case SoftphoneConnectionState.reconnecting:
      case SoftphoneConnectionState.connecting:
        return const Color(0xFF2563EB);
      default:
        return scheme.outline;
    }
  }

  Future<void> _toggleOnline() async {
    if (_engine.isReady || _engine.state == SoftphoneConnectionState.connecting) {
      await _engine.unregister();
    } else {
      await _engine.register(mode: 'relay');
    }
  }

  Future<void> _dial() async {
    final dest = _destCtrl.text.trim();
    if (dest.isEmpty) return;
    try {
      await _engine.dial(dest);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final health = _engine.health;
    final tunnelOk = health?['tunnel'] is Map && (health!['tunnel'] as Map)['online'] == true;
    final endpointMode = '${health?['endpoint_mode'] ?? ''}';
    final extension = '${health?['extension'] ?? ''}';

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _stateColor(scheme, _engine.state).withValues(alpha: 0.14),
                      border: Border.all(color: _stateColor(scheme, _engine.state).withValues(alpha: 0.45)),
                    ),
                    child: Icon(Icons.headset_mic_rounded, size: 34, color: _stateColor(scheme, _engine.state)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Softphone حسابیکس',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _stateLabel(_engine.state),
                          style: TextStyle(
                            color: _stateColor(scheme, _engine.state),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _engine.statusDetail,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'رسانه از طریق افزونه Connector (Relay) منتقل می‌شود؛ نیازی به باز کردن پورت PBX به اینترنت نیست. '
                'میکروفون و پخش روی همین صفحه فعال می‌شود.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.55),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(scheme, 'داخلی', extension.isEmpty ? '—' : extension),
                  _chip(scheme, 'حالت', endpointMode.isEmpty ? '—' : endpointMode),
                  _chip(scheme, 'تونل رسانه', tunnelOk ? 'آنلاین' : 'قطع'),
                  _chip(scheme, 'پل صوت', _engine.bridgeActive ? 'فعال' : 'غیرفعال'),
                  _chip(scheme, 'صوت محلی', _engine.mediaReady ? 'آماده' : 'خاموش'),
                ],
              ),
              if (_engine.error != null) ...[
                const SizedBox(height: 12),
                Material(
                  color: scheme.errorContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_engine.error!, style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _toggleOnline,
                icon: Icon(
                  _engine.isReady || _engine.state == SoftphoneConnectionState.connecting
                      ? Icons.phonelink_erase_rounded
                      : Icons.power_settings_new_rounded,
                ),
                label: Text(
                  _engine.isReady || _engine.state == SoftphoneConnectionState.connecting
                      ? 'قطع Softphone'
                      : 'آنلاین شدن (Relay)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _destCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'شماره مقصد',
                        hintText: '09xxxxxxxxx',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _dial(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: _engine.isReady ? _dial : null,
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('تماس'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_engine.state == SoftphoneConnectionState.ringing ||
                  _engine.state == SoftphoneConnectionState.inCall) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_engine.state == SoftphoneConnectionState.ringing &&
                        int.tryParse('${_engine.activeCall?['id'] ?? ''}') != null)
                      FilledButton.icon(
                        onPressed: () async {
                          final id = int.parse('${_engine.activeCall!['id']}');
                          await _engine.answer(id);
                        },
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('پاسخ'),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: () => _engine.setMuted(!_engine.muted),
                      icon: Icon(_engine.muted ? Icons.mic_off_rounded : Icons.mic_rounded),
                      label: Text(_engine.muted ? 'بی‌صدا' : 'میکروفون'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: scheme.error),
                      onPressed: () => _engine.hangup(),
                      icon: const Icon(Icons.call_end_rounded),
                      label: const Text('قطع'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: '123456789*0#'.split('').map((d) {
                    return ActionChip(
                      label: Text(d),
                      onPressed: () => _engine.sendDtmf(d),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'فریم رسانه: ورود ${_engine.incomingPcmFrames} / خروج ${_engine.outgoingPcmFrames}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () {
                  final session = TelephonySessionStore.instance.controller
                    ..bindBusiness(widget.businessId, pluginActive: true);
                  showTelephonyDialerSheet(
                    context,
                    businessId: widget.businessId,
                    session: session,
                  );
                },
                icon: const Icon(Icons.dialpad_rounded),
                label: const Text('شماره‌گیر Click-to-Call (حالت Desk)'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    context.go(context.businessPanelUrl(widget.businessId, 'settings/telephony')),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('تنظیم حالت داخلی / Softphone'),
              ),
              TextButton.icon(
                onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony')),
                icon: const Icon(Icons.phone_in_talk_outlined),
                label: const Text('بازگشت به مرکز تماس'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(ColorScheme scheme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
