import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';

/// Visual SLA indicator for support tickets.
class SlaIndicator extends StatelessWidget {
  final String slaStatus;
  final bool compact;

  const SlaIndicator({super.key, required this.slaStatus, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = SupportSemanticColors.of(context);
    final (color, label, icon) = switch (slaStatus) {
      'breached' => (colors.slaBreached, 'نقض SLA', Icons.error_outline),
      'warning' => (colors.slaWarning, 'نزدیک SLA', Icons.schedule),
      _ => (colors.slaOk, 'در SLA', Icons.check_circle_outline),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

BorderSide? slaRowBorderSide(BuildContext context, String slaStatus) {
  final colors = SupportSemanticColors.of(context);
  return switch (slaStatus) {
    'breached' => BorderSide(color: colors.slaBreached, width: 3),
    'warning' => BorderSide(color: colors.slaWarning, width: 3),
    _ => null,
  };
}

String computeSlaStatus({
  required bool slaBreached,
  DateTime? resolutionDueAt,
  DateTime? firstResponseDueAt,
  DateTime? firstRespondedAt,
  DateTime? closedAt,
}) {
  if (slaBreached) return 'breached';
  if (closedAt != null) return 'ok';
  final due = resolutionDueAt ?? (firstRespondedAt == null ? firstResponseDueAt : null);
  if (due != null) {
    final remaining = due.difference(DateTime.now());
    if (remaining.isNegative) return 'breached';
    if (remaining.inMinutes <= 30) return 'warning';
  }
  return 'ok';
}

DateTime? _parseRowDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Map) {
    final raw = value['date'] ?? value['datetime'] ?? value['iso'];
    if (raw != null) return DateTime.tryParse(raw.toString());
  }
  return DateTime.tryParse(value.toString());
}

String slaStatusFromRow(Map<String, dynamic> row) {
  return computeSlaStatus(
    slaBreached: row['sla_breached'] == true,
    resolutionDueAt: _parseRowDate(row['resolution_due_at_raw'] ?? row['resolution_due_at']),
    firstResponseDueAt: _parseRowDate(row['first_response_due_at_raw'] ?? row['first_response_due_at']),
    firstRespondedAt: _parseRowDate(row['first_responded_at_raw'] ?? row['first_responded_at']),
    closedAt: _parseRowDate(row['closed_at_raw'] ?? row['closed_at']),
  );
}

Color? slaRowBackgroundColor(BuildContext context, Map<String, dynamic> row) {
  final colors = SupportSemanticColors.of(context);
  return switch (slaStatusFromRow(row)) {
    'breached' => colors.slaBreached.withValues(alpha: 0.10),
    'warning' => colors.slaWarning.withValues(alpha: 0.10),
    _ => null,
  };
}

String slaStatusLabel(String status) {
  return switch (status) {
    'breached' => 'نقض SLA',
    'warning' => 'نزدیک SLA',
    _ => 'در SLA',
  };
}
