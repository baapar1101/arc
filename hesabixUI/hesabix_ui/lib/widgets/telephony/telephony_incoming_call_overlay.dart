import 'package:flutter/material.dart';

import '../../core/auth_store.dart';
import '../../services/telephony/softphone_engine.dart';

/// Overlay سراسری تماس ورودی Softphone — روی هر صفحهٔ BusinessShell.
class TelephonyIncomingCallOverlay extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final bool pluginActive;

  const TelephonyIncomingCallOverlay({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.pluginActive,
  });

  @override
  State<TelephonyIncomingCallOverlay> createState() => _TelephonyIncomingCallOverlayState();
}

class _TelephonyIncomingCallOverlayState extends State<TelephonyIncomingCallOverlay>
    with SingleTickerProviderStateMixin {
  SoftphoneEngine? _engine;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _bindEngine();
  }

  @override
  void didUpdateWidget(covariant TelephonyIncomingCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId || oldWidget.pluginActive != widget.pluginActive) {
      _engine?.removeListener(_onEngine);
      _bindEngine();
    }
  }

  void _bindEngine() {
    if (!widget.pluginActive) {
      _engine = null;
      return;
    }
    _engine = SoftphoneEngineStore.instance.obtain(
      businessId: widget.businessId,
      authStore: widget.authStore,
    );
    _engine!.addListener(_onEngine);
  }

  void _onEngine() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _engine?.removeListener(_onEngine);
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _answer() async {
    final engine = _engine;
    final id = engine?.activeCallId;
    if (engine == null || id == null) return;
    try {
      await engine.answer(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('پاسخ تماس ناموفق: $e')),
      );
    }
  }

  Future<void> _reject() async {
    try {
      await _engine?.rejectIncoming();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pluginActive) return const SizedBox.shrink();
    final engine = _engine;
    if (engine == null || engine.state != SoftphoneConnectionState.ringing) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final String caller = engine.incomingCallerDisplay;
    final canAnswer = engine.activeCallId != null;

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: SafeArea(
          child: Align(
            alignment: wide ? Alignment.center : Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final glow = 0.12 + (_pulse.value * 0.18);
                return Container(
                  width: wide ? 420 : double.infinity,
                  margin: EdgeInsets.fromLTRB(wide ? 0 : 16, 16, wide ? 0 : 16, wide ? 0 : 24),
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0F3D2E),
                        scheme.surface.withValues(alpha: 0.98),
                      ],
                    ),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.45)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: glow),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تماس ورودی Softphone',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFF6EE7B7),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                  ),
                  const SizedBox(height: 18),
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.06).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF059669).withValues(alpha: 0.2),
                        border: Border.all(color: const Color(0xFF34D399), width: 2),
                      ),
                      child: const Icon(Icons.call_rounded, size: 40, color: Color(0xFF34D399)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    caller,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'در حال زنگ خوردن…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: _reject,
                          icon: const Icon(Icons.call_end_rounded),
                          label: const Text('رد'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          onPressed: canAnswer ? _answer : null,
                          icon: const Icon(Icons.call_rounded),
                          label: Text(canAnswer ? 'پاسخ' : '…'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
