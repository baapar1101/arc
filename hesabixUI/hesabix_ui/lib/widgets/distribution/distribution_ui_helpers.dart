import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'package:url_launcher/url_launcher.dart';

/// برچسب فارسی/انگلیسی وضعیت ویزیت.
String distributionVisitStatusLabel(AppLocalizations t, String? status) {
  switch (status) {
    case 'in_progress':
      return t.distributionStatusInProgress;
    case 'completed':
      return t.distributionStatusCompleted;
    case 'cancelled':
      return t.distributionStatusCancelled;
    default:
      return status?.isNotEmpty == true ? status! : t.distributionStatusUnknown;
  }
}

String distributionReturnStatusLabel(AppLocalizations t, String? status) {
  switch (status) {
    case 'pending':
      return t.distributionReturnPending;
    case 'approved':
      return t.distributionReturnApproved;
    case 'rejected':
      return t.distributionReturnRejected;
    default:
      return status?.isNotEmpty == true ? status! : t.distributionStatusUnknown;
  }
}

String distributionOutcomeLabel(AppLocalizations t, String? outcome) {
  switch (outcome) {
    case 'order':
      return t.distributionOutcomeOrder;
    case 'no_order':
      return t.distributionOutcomeNoOrder;
    default:
      return outcome?.isNotEmpty == true ? outcome! : '—';
  }
}

String distributionSettlementStatusLabel(AppLocalizations t, String? status) {
  switch (status) {
    case 'confirmed':
      return t.distributionSettlementConfirmed;
    case 'draft':
      return t.distributionSaveDraft;
    default:
      return status?.isNotEmpty == true ? status! : '—';
  }
}

String distributionPeriodTypeLabel(AppLocalizations t, String? period) {
  switch (period) {
    case 'day':
      return t.distributionTargetPeriodDay;
    case 'month':
      return t.distributionTargetPeriodMonth;
    default:
      return period ?? '—';
  }
}

Color distributionStatusColor(BuildContext context, String? status) {
  final cs = Theme.of(context).colorScheme;
  switch (status) {
    case 'in_progress':
    case 'pending':
    case 'draft':
      return cs.tertiary;
    case 'completed':
    case 'approved':
    case 'confirmed':
    case 'order':
      return cs.primary;
    case 'cancelled':
    case 'rejected':
    case 'no_order':
      return cs.error;
    default:
      return cs.outline;
  }
}

Widget distributionStatusChip(BuildContext context, AppLocalizations t, String? status, {bool isReturn = false}) {
  final label = isReturn
      ? distributionReturnStatusLabel(t, status)
      : distributionVisitStatusLabel(t, status);
  final color = distributionStatusColor(context, status);
  return Chip(
    visualDensity: VisualDensity.compact,
    label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    side: BorderSide(color: color.withValues(alpha: 0.45)),
    backgroundColor: color.withValues(alpha: 0.08),
    padding: EdgeInsets.zero,
    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
  );
}

Future<void> openDistributionMapsNavigation(double lat, double lng) async {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

String distributionPresenceLabel(AppLocalizations t, String? presence) {
  switch (presence) {
    case 'online':
      return t.distributionPresenceOnline;
    case 'recent':
      return t.distributionPresenceRecent;
    case 'stale':
      return t.distributionPresenceStale;
    case 'offline':
      return t.distributionPresenceOffline;
    default:
      return t.distributionPresenceNone;
  }
}

Color distributionPresenceColor(BuildContext context, String? presence) {
  switch (presence) {
    case 'online':
      return SemanticColorResolver.positive(context);
    case 'recent':
      return SemanticColorResolver.info(context);
    case 'stale':
      return SemanticColorResolver.warning(context);
    case 'offline':
      return Theme.of(context).colorScheme.outline;
    default:
      return Theme.of(context).colorScheme.outlineVariant;
  }
}

IconData distributionPresenceIcon(String? presence) {
  switch (presence) {
    case 'online':
      return Icons.sensors;
    case 'recent':
      return Icons.schedule;
    case 'stale':
      return Icons.history;
    case 'offline':
      return Icons.sensors_off;
    default:
      return Icons.location_off_outlined;
  }
}

Future<void> openDistributionPhoneDialer(String? phone) async {
  final p = (phone ?? '').trim();
  if (p.isEmpty) return;
  final uri = Uri(scheme: 'tel', path: p);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

/// کارت خالی‌حالت با CTA اختیاری.
Widget distributionEmptyState({
  required BuildContext context,
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? action,
}) {
  final theme = Theme.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    ),
  );
}
