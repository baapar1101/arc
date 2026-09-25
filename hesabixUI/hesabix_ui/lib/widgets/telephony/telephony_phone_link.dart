import 'package:flutter/material.dart';

import '../../services/telephony/telephony_session_controller.dart';

/// لینک شماره‌گیری کنار فیلد تلفن در CRM / اشخاص.
class TelephonyPhoneLink extends StatelessWidget {
  final int businessId;
  final String number;
  final int? personId;
  final int? leadId;
  final bool enabled;

  const TelephonyPhoneLink({
    super.key,
    required this.businessId,
    required this.number,
    this.personId,
    this.leadId,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || number.trim().isEmpty) {
      return SelectableText(number);
    }
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: SelectableText(number)),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'تماس',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.phone_forwarded_rounded, color: scheme.primary, size: 20),
          onPressed: () async {
            final session = TelephonySessionStore.instance.controller;
            session.bindBusiness(businessId, pluginActive: true);
            try {
              await session.clickToCall(
                destination: number,
                personId: personId,
                leadId: leadId,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('در حال برقراری تماس…')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
        ),
      ],
    );
  }
}
