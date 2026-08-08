import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../services/telephony/softphone_engine.dart';
import '../../services/telephony/telephony_session_controller.dart';
import 'telephony_dialer_sheet.dart';
import 'telephony_post_call_sheet.dart';
import 'telephony_screen_pop.dart';

/// نوار تلفن داخل BusinessShell (بدون Screen Pop — Pop جداگانه Overlay می‌شود).
class TelephonyPhoneBarHost extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final bool pluginActive;

  const TelephonyPhoneBarHost({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.pluginActive,
  });

  @override
  State<TelephonyPhoneBarHost> createState() => _TelephonyPhoneBarHostState();
}

class _TelephonyPhoneBarHostState extends State<TelephonyPhoneBarHost> with SingleTickerProviderStateMixin {
  late final TelephonySessionController _session;
  SoftphoneEngine? _softphone;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _session = TelephonySessionStore.instance.controller;
    TelephonySessionStore.instance.ensureWs();
    _session.bindBusiness(widget.businessId, pluginActive: widget.pluginActive);
    _session.addListener(_onSession);
    _softphone = SoftphoneEngineStore.instance.obtain(
      businessId: widget.businessId,
      authStore: widget.authStore,
    );
    _softphone!.addListener(_onSoftphone);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  }

  @override
  void didUpdateWidget(covariant TelephonyPhoneBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || oldWidget.pluginActive != widget.pluginActive) {
      _session.bindBusiness(widget.businessId, pluginActive: widget.pluginActive);
      _softphone?.removeListener(_onSoftphone);
      _softphone = SoftphoneEngineStore.instance.obtain(
        businessId: widget.businessId,
        authStore: widget.authStore,
      );
      _softphone?.addListener(_onSoftphone);
    }
  }

  void _onSoftphone() {
    if (!mounted) return;
    final ringing = _softphone?.state == SoftphoneConnectionState.ringing;
    if (ringing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!ringing &&
        _session.presenceLabel != 'ringing' &&
        _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    setState(() {});
  }

  void _onSession() {
    if (!mounted) return;
    final ringing = _session.presenceLabel == 'ringing' ||
        _softphone?.state == SoftphoneConnectionState.ringing;
    if (ringing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!ringing && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    if (_session.pendingPostCall && _session.takePendingPostCall()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showTelephonyPostCallSheet(context, session: _session);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _softphone?.removeListener(_onSoftphone);
    _pulse.dispose();
    super.dispose();
  }

  Color _statusColor(ColorScheme scheme) {
    final sf = _softphone?.state;
    if (sf == SoftphoneConnectionState.ringing) return const Color(0xFFD97706);
    if (sf == SoftphoneConnectionState.inCall) return scheme.primary;
    if (sf == SoftphoneConnectionState.registered) return const Color(0xFF059669);
    if (sf == SoftphoneConnectionState.error || sf == SoftphoneConnectionState.reconnecting) {
      return scheme.error;
    }
    switch (_session.presenceLabel) {
      case 'ringing':
        return const Color(0xFFD97706);
      case 'in_call':
        return scheme.primary;
      case 'offline':
        return scheme.outline;
      case 'no_extension':
        return scheme.error.withValues(alpha: 0.75);
      default:
        return const Color(0xFF159947);
    }
  }

  String _statusText() {
    final sf = _softphone?.state;
    if (sf == SoftphoneConnectionState.connecting) return 'Softphone در حال اتصال';
    if (sf == SoftphoneConnectionState.registered) return 'Softphone آماده';
    if (sf == SoftphoneConnectionState.ringing) {
      final from = _softphone?.incomingCallerDisplay;
      return from == null || from.isEmpty ? 'Softphone: زنگ' : 'زنگ از $from';
    }
    if (sf == SoftphoneConnectionState.inCall) return 'Softphone: مکالمه';
    if (sf == SoftphoneConnectionState.reconnecting) return 'Softphone: اتصال مجدد';
    if (sf == SoftphoneConnectionState.error) return 'Softphone: خطا';
    switch (_session.presenceLabel) {
      case 'ringing':
        return 'زنگ می‌خورد';
      case 'in_call':
        return 'در مکالمه';
      case 'offline':
        return 'قطع از مرکز تلفن';
      case 'no_extension':
        return 'بدون داخلی';
      default:
        return 'آزاد';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pluginActive) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final statusColor = _statusColor(scheme);
    final ringing = _session.presenceLabel == 'ringing' ||
        _softphone?.state == SoftphoneConnectionState.ringing;
    final inCall = _session.presenceLabel == 'in_call' ||
        _softphone?.state == SoftphoneConnectionState.inCall;
    final softReady = _softphone?.isReady == true;

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.fromLTRB(compact ? 8 : 12, 8, compact ? 8 : 12, 4),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 8 : 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              (ringing || inCall)
                  ? statusColor.withValues(alpha: 0.12)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.95),
              scheme.surfaceContainerLow.withValues(alpha: 0.98),
            ],
          ),
          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: ringing ? 0.2 : 0.06),
              blurRadius: ringing ? 18 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final scale = ringing ? 0.85 + (_pulse.value * 0.3) : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: statusColor.withValues(alpha: 0.45), blurRadius: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  if (_session.presenceLabel == 'no_extension') {
                    context.go(context.businessPanelUrl(widget.businessId, 'settings/telephony'));
                    return;
                  }
                  context.go(context.businessPanelUrl(widget.businessId, 'telephony/softphone'));
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مرکز تماس',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((_session.primaryExtension ?? '').isNotEmpty) 'داخلی ${_session.primaryExtension}',
                        _statusText(),
                        if (_session.presenceLabel == 'no_extension') 'تنظیم داخلی',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _session.presenceLabel == 'no_extension' ? scheme.error : scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (inCall || ringing) ...[
              if (ringing && _softphone?.activeCallId != null)
                IconButton(
                  tooltip: 'پاسخ Softphone',
                  onPressed: () async {
                    final id = _softphone!.activeCallId!;
                    await _softphone!.answer(id);
                  },
                  icon: Icon(Icons.call_rounded, color: scheme.primary),
                ),
              if (ringing)
                IconButton(
                  tooltip: 'رد تماس',
                  onPressed: () => _softphone?.rejectIncoming(),
                  icon: Icon(Icons.call_end_rounded, color: scheme.error),
                ),
              if (!ringing)
                IconButton(
                  tooltip: _softphone?.muted == true ? 'رفع بی‌صدایی' : 'بی‌صدا',
                  onPressed: softReady ? () => _softphone!.setMuted(!(_softphone!.muted)) : null,
                  icon: Icon(
                    _softphone?.muted == true ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (!ringing)
                IconButton(
                  tooltip: 'قطع',
                  onPressed: softReady ? () => _softphone!.hangup() : () => _session.hangupActiveCall(),
                  icon: Icon(Icons.call_end_rounded, color: scheme.error),
                ),
            ] else ...[
              IconButton(
                tooltip: softReady ? 'Softphone آنلاین است' : 'Softphone',
                onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/softphone')),
                icon: Icon(
                  Icons.headset_mic_rounded,
                  color: softReady ? const Color(0xFF059669) : scheme.primary,
                ),
              ),
              if (_session.missedToday > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: InkWell(
                    onTap: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/calls')),
                    child: Badge(
                      label: Text('${_session.missedToday}'),
                      child: Icon(Icons.call_missed_outgoing_rounded, color: scheme.error, size: 22),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'شماره‌گیر',
                onPressed: () => showTelephonyDialerSheet(
                  context,
                  businessId: widget.businessId,
                  session: _session,
                ),
                icon: Icon(Icons.dialpad_rounded, color: scheme.primary),
              ),
              if (!compact)
                IconButton(
                  tooltip: 'تاریخچه',
                  onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'telephony/calls')),
                  icon: Icon(Icons.history_rounded, color: scheme.onSurfaceVariant),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// لایه شناور Screen Pop روی کل محتوای shell.
class TelephonyScreenPopLayer extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;
  final bool pluginActive;

  const TelephonyScreenPopLayer({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.pluginActive,
  });

  @override
  Widget build(BuildContext context) {
    if (!pluginActive) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: TelephonySessionStore.instance.controller,
      builder: (context, _) {
        final session = TelephonySessionStore.instance.controller;
        if (!session.screenPopVisible || session.screenPop == null) {
          return const SizedBox.shrink();
        }
        final wide = MediaQuery.sizeOf(context).width >= 900;
        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    final st = '${session.activeCall?['status'] ?? ''}';
                    if (st != 'ringing' && st != 'answered') {
                      session.closeScreenPop();
                    }
                  },
                  child: ColoredBox(color: Colors.black.withValues(alpha: wide ? 0.08 : 0.18)),
                ),
              ),
              TelephonyScreenPopOverlay(
                businessId: businessId,
                session: session,
                authStore: authStore,
              ),
            ],
          ),
        );
      },
    );
  }
}
