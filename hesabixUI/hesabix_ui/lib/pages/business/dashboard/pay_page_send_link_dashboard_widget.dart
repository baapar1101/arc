import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/pages/business/pay_page_send_link_dialog.dart';

class PayPageSendLinkDashboardBody extends StatelessWidget {
  final int businessId;
  final dynamic data;

  const PayPageSendLinkDashboardBody({
    super.key,
    required this.businessId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final payload = (data is Map<String, dynamic>)
        ? data as Map<String, dynamic>
        : (data is Map ? Map<String, dynamic>.from(data as Map) : const <String, dynamic>{});
    if (payload['error'] != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${payload['error']}', textAlign: TextAlign.center),
        ),
      );
    }
    final enabled = payload['is_enabled'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            enabled ? t.payPageSendLinkHint : t.payPageSendLinkDisabled,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: enabled
                ? () => showPayPageSendLinkDialog(
                      context: context,
                      businessId: businessId,
                      settings: payload,
                    )
                : null,
            icon: const Icon(Icons.send),
            label: Text(t.payPageSendLink),
          ),
        ],
      ),
    );
  }
}
