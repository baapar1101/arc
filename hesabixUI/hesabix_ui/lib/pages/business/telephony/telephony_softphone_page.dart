import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../services/telephony/telephony_session_controller.dart';
import '../../widgets/telephony/telephony_dialer_sheet.dart';

/// اسکفولد Softphone وب (فاز ۵) — فعلاً Click-to-Call توصیه می‌شود.
/// برای فعال‌سازی کامل، وابستگی `sip_ua` / WebRTC روی PBX لازم است.
class TelephonySoftphonePage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const TelephonySoftphonePage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = TelephonySessionStore.instance.controller
      ..bindBusiness(businessId, pluginActive: true);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.22),
                        scheme.tertiary.withValues(alpha: 0.14),
                      ],
                    ),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Icon(Icons.headset_mic_rounded, size: 46, color: scheme.primary),
                ),
                const SizedBox(height: 22),
                Text(
                  'Softphone داخل اپ',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  'در نسخه فعلی تماس از طریق Click-to-Call روی داخلی SIP شما برقرار می‌شود. '
                  'Softphone مبتنی بر WebRTC در فاز پیشرفته فعال خواهد شد و نیاز به تنظیم PJSIP/WebRTC روی Issabel دارد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.55),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => showTelephonyDialerSheet(
                        context,
                        businessId: businessId,
                        session: session,
                      ),
                      icon: const Icon(Icons.dialpad_rounded),
                      label: const Text('شماره‌گیر Click-to-Call'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go(context.businessPanelUrl(businessId, 'telephony')),
                      icon: const Icon(Icons.phone_in_talk_outlined),
                      label: const Text('مرکز تماس'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
