import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../l10n/app_localizations.dart';
import '../../services/telephony/softphone_engine.dart';
import '../../services/telephony/telephony_session_controller.dart';
import 'telephony_dialer_sheet.dart';
import 'telephony_post_call_sheet.dart';
import 'telephony_screen_pop.dart';

Color _telephonyStatusColor({
  required ColorScheme scheme,
  required TelephonySessionController session,
  SoftphoneEngine? softphone,
}) {
  final sf = softphone?.state;
  if (sf == SoftphoneConnectionState.ringing) return const Color(0xFFD97706);
  if (sf == SoftphoneConnectionState.inCall) return scheme.primary;
  if (sf == SoftphoneConnectionState.registered) return const Color(0xFF059669);
  if (sf == SoftphoneConnectionState.error ||
      sf == SoftphoneConnectionState.reconnecting) {
    return scheme.error;
  }
  switch (session.presenceLabel) {
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

String _telephonyStatusText({
  required AppLocalizations t,
  required TelephonySessionController session,
  SoftphoneEngine? softphone,
}) {
  final sf = softphone?.state;
  if (sf == SoftphoneConnectionState.connecting) return t.telephonyBarConnecting;
  if (sf == SoftphoneConnectionState.registered) return t.telephonyBarReady;
  if (sf == SoftphoneConnectionState.ringing) {
    final from = softphone?.incomingCallerDisplay;
    return from == null || from.isEmpty ? t.telephonyBarRinging : t.telephonyRingFrom(from);
  }
  if (sf == SoftphoneConnectionState.inCall) return t.telephonyBarInCall;
  if (sf == SoftphoneConnectionState.reconnecting) return t.telephonyBarReconnecting;
  if (sf == SoftphoneConnectionState.error) return t.telephonyBarError;
  switch (session.presenceLabel) {
    case 'ringing':
      return t.telephonyPresenceRinging;
    case 'in_call':
      return t.telephonyPresenceTalking;
    case 'offline':
      return t.telephonyPresenceOffline;
    case 'no_extension':
      return t.telephonyPresenceNoExt;
    default:
      return t.telephonyPresenceIdle;
  }
}

bool _telephonyIsRinging(TelephonySessionController session, SoftphoneEngine? softphone) {
  return session.presenceLabel == 'ringing' ||
      softphone?.state == SoftphoneConnectionState.ringing;
}

bool _telephonyIsInCall(TelephonySessionController session, SoftphoneEngine? softphone) {
  return session.presenceLabel == 'in_call' ||
      softphone?.state == SoftphoneConnectionState.inCall;
}

/// آیکن فشردهٔ مرکز تماس در نوار بالای BusinessShell.
class TelephonyPhoneBarHost extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final bool pluginActive;
  final Color? iconColor;

  const TelephonyPhoneBarHost({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.pluginActive,
    this.iconColor,
  });

  @override
  State<TelephonyPhoneBarHost> createState() => _TelephonyPhoneBarHostState();
}

class _TelephonyPhoneBarHostState extends State<TelephonyPhoneBarHost>
    with SingleTickerProviderStateMixin {
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
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.pluginActive != widget.pluginActive) {
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
    final ringing = _telephonyIsRinging(_session, _softphone);
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

  Future<void> _openMenu() async {
    final hostContext = context;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (dialogContext) {
        return _TelephonyToolbarMenu(
          businessId: widget.businessId,
          authStore: widget.authStore,
          onClose: () => Navigator.of(dialogContext).pop(),
          onNavigate: (path) {
            Navigator.of(dialogContext).pop();
            hostContext.go(hostContext.businessPanelUrl(widget.businessId, path));
          },
          onDialer: () {
            Navigator.of(dialogContext).pop();
            showTelephonyDialerSheet(
              hostContext,
              businessId: widget.businessId,
              session: _session,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pluginActive) return const SizedBox.shrink();

    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fg = widget.iconColor ?? scheme.onSurface;
    final statusColor = _telephonyStatusColor(
      scheme: scheme,
      session: _session,
      softphone: _softphone,
    );
    final ringing = _telephonyIsRinging(_session, _softphone);
    final inCall = _telephonyIsInCall(_session, _softphone);
    final missed = _session.missedToday;
    final status = _telephonyStatusText(
      t: t,
      session: _session,
      softphone: _softphone,
    );
    final tooltip = [
      t.telephonyMenu,
      if ((_session.primaryExtension ?? '').isNotEmpty)
        t.telephonyExtensionValue(_session.primaryExtension!),
      status,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              minimumSize: const Size(38, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _openMenu,
            icon: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final scale = ringing ? 0.88 + (_pulse.value * 0.22) : 1.0;
                return Transform.scale(scale: scale, child: child);
              },
              child: SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      inCall || ringing
                          ? Icons.headset_mic_rounded
                          : Icons.headset_mic_outlined,
                      size: 21,
                      color: fg,
                    ),
                    PositionedDirectional(
                      top: -1,
                      end: -1,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: ringing ? 0.55 : 0.35),
                              blurRadius: ringing ? 6 : 3,
                            ),
                          ],
                          border: Border.all(
                            color: fg.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (missed > 0)
            Positioned(
              right: 4,
              top: 6,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    missed > 99 ? '99+' : '$missed',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TelephonyToolbarMenu extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final VoidCallback onClose;
  final ValueChanged<String> onNavigate;
  final VoidCallback onDialer;

  const _TelephonyToolbarMenu({
    required this.businessId,
    required this.authStore,
    required this.onClose,
    required this.onNavigate,
    required this.onDialer,
  });

  @override
  State<_TelephonyToolbarMenu> createState() => _TelephonyToolbarMenuState();
}

class _TelephonyToolbarMenuState extends State<_TelephonyToolbarMenu> {
  late final TelephonySessionController _session;
  SoftphoneEngine? _softphone;

  @override
  void initState() {
    super.initState();
    _session = TelephonySessionStore.instance.controller;
    _session.addListener(_onChanged);
    _softphone = SoftphoneEngineStore.instance.obtain(
      businessId: widget.businessId,
      authStore: widget.authStore,
    );
    _softphone?.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onChanged);
    _softphone?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _telephonyStatusColor(
      scheme: scheme,
      session: _session,
      softphone: _softphone,
    );
    final ringing = _telephonyIsRinging(_session, _softphone);
    final inCall = _telephonyIsInCall(_session, _softphone);
    final softReady = _softphone?.isReady == true;
    final status = _telephonyStatusText(
      t: t,
      session: _session,
      softphone: _softphone,
    );
    final extension = _session.primaryExtension ?? '';
    final subtitle = [
      if (extension.isNotEmpty) t.telephonyExtensionValue(extension),
      status,
      if (_session.presenceLabel == 'no_extension') t.telephonyConfigureExtension,
    ].where((e) => e.isNotEmpty).join(' · ');

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: AlignmentDirectional.topEnd,
      insetPadding: const EdgeInsets.fromLTRB(12, 52, 12, 12),
      child: Material(
        color: scheme.surface,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            if (_session.presenceLabel == 'no_extension') {
                              widget.onNavigate('telephony');
                              return;
                            }
                            widget.onNavigate('telephony/softphone');
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.telephonyMenu,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _session.presenceLabel == 'no_extension'
                                          ? scheme.error
                                          : scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: t.close,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (inCall || ringing)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
                      child: Row(
                        children: [
                          if (ringing && _softphone?.activeCallId != null)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final id = _softphone!.activeCallId!;
                                  await _softphone!.answer(id);
                                },
                                icon: const Icon(Icons.call_rounded, size: 18),
                                label: Text(t.telephonyAnswerSoftphone),
                              ),
                            ),
                          if (ringing) ...[
                            if (_softphone?.activeCallId != null) const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  foregroundColor: scheme.error,
                                ),
                                onPressed: () => _softphone?.rejectIncoming(),
                                icon: const Icon(Icons.call_end_rounded, size: 18),
                                label: Text(t.telephonyDeclineCall),
                              ),
                            ),
                          ],
                          if (!ringing) ...[
                            IconButton(
                              tooltip: _softphone?.muted == true
                                  ? t.telephonyUnmute
                                  : t.telephonyMute,
                              onPressed: softReady
                                  ? () => _softphone!.setMuted(!(_softphone!.muted))
                                  : null,
                              icon: Icon(
                                _softphone?.muted == true
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  foregroundColor: scheme.error,
                                ),
                                onPressed: softReady
                                    ? () => _softphone!.hangup()
                                    : () => _session.hangupActiveCall(),
                                icon: const Icon(Icons.call_end_rounded, size: 18),
                                label: Text(t.telephonyHangup),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: Icon(
                              Icons.headset_mic_rounded,
                              size: 18,
                              color: softReady ? const Color(0xFF059669) : scheme.primary,
                            ),
                            label: Text(t.telephonySoftphoneTitle),
                            onPressed: () => widget.onNavigate('telephony/softphone'),
                          ),
                          ActionChip(
                            avatar: Icon(Icons.dialpad_rounded, size: 18, color: scheme.primary),
                            label: Text(t.telephonyDialer),
                            onPressed: widget.onDialer,
                          ),
                          ActionChip(
                            avatar: Badge(
                              isLabelVisible: _session.missedToday > 0,
                              label: Text('${_session.missedToday}'),
                              child: Icon(
                                Icons.history_rounded,
                                size: 18,
                                color: _session.missedToday > 0
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                            label: Text(t.history),
                            onPressed: () => widget.onNavigate('telephony/calls'),
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
