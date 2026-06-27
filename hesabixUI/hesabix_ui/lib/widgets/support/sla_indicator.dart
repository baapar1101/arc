import 'package:flutter/material.dart';

/// Visual SLA indicator for support tickets.
class SlaIndicator extends StatelessWidget {
  final String slaStatus;

  const SlaIndicator({super.key, required this.slaStatus});

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (slaStatus) {
      'breached' => (Colors.red, 'SLA نقض', Icons.error_outline),
      'warning' => (Colors.orange, 'نزدیک SLA', Icons.schedule),
      _ => (Colors.green, 'SLA OK', Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

BorderSide? slaRowBorderSide(String slaStatus) {
  return switch (slaStatus) {
    'breached' => const BorderSide(color: Colors.red, width: 3),
    'warning' => const BorderSide(color: Colors.orange, width: 3),
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

Color? slaRowBackgroundColor(Map<String, dynamic> row) {
  return switch (slaStatusFromRow(row)) {
    'breached' => Colors.red.withValues(alpha: 0.10),
    'warning' => Colors.orange.withValues(alpha: 0.10),
    _ => null,
  };
}

String slaStatusLabel(String status) {
  return switch (status) {
    'breached' => 'نقض SLA',
    'warning' => 'نزدیک SLA',
    _ => 'SLA OK',
  };
}
