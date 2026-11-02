import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../services/office_automation_service.dart';
import 'oa_searchable_field.dart';

String oaPositionLabel(Map<String, dynamic> p) {
  final title = (p['title'] ?? p['code'] ?? '').toString();
  final unit = (p['org_unit_title'] ?? '').toString();
  final holder = (p['holder_name'] ?? '').toString();
  final parts = [title, if (unit.isNotEmpty) unit, if (holder.isNotEmpty) holder];
  return parts.join(' · ');
}

OaSearchItem oaPositionItem(Map<String, dynamic> p) {
  final id = oaId(p['id']);
  return OaSearchItem(
    id: '${id ?? ''}',
    title: (p['title'] ?? p['code'] ?? '').toString(),
    subtitle: [
      p['org_unit_title'] ?? p['code'] ?? '',
      if ((p['holder_name'] ?? '').toString().isNotEmpty) p['holder_name'],
    ].where((e) => e.toString().isNotEmpty).join(' · '),
    icon: p['is_secretariat'] == true ? Icons.verified_outlined : Icons.badge_outlined,
    payload: p,
  );
}

String oaKindLabel(AppLocalizations t, String kind) {
  switch (kind) {
    case 'incoming':
      return t.oaKindIncoming;
    case 'outgoing':
      return t.oaKindOutgoing;
    default:
      return t.oaKindInternal;
  }
}

String oaStatusLabel(AppLocalizations t, String status) {
  switch (status) {
    case 'draft':
      return t.oaDrafts;
    case 'registered':
      return t.oaRegister;
    case 'in_circulation':
      return t.oaInCirculation;
    case 'closed':
      return t.oaClosed;
    case 'archived':
      return t.oaArchive;
    default:
      return status;
  }
}

String oaUrgencyLabel(AppLocalizations t, String value) {
  switch (value) {
    case 'urgent':
      return t.oaUrgencyUrgent;
    case 'immediate':
      return t.oaUrgencyImmediate;
    default:
      return t.oaUrgencyNormal;
  }
}

Color oaUrgencyColor(ColorScheme cs, String value) {
  switch (value) {
    case 'urgent':
      return cs.tertiary;
    case 'immediate':
      return cs.error;
    default:
      return cs.primary;
  }
}

class OaStatusChip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  const OaStatusChip({super.key, required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.primary;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: icon == null ? null : Icon(icon, size: 16, color: fg),
      label: Text(label),
      side: BorderSide(color: fg.withValues(alpha: 0.35)),
      backgroundColor: fg.withValues(alpha: 0.08),
    );
  }
}

class OaSectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;

  const OaSectionCard({
    super.key,
    this.title,
    required this.child,
    this.actions,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || (actions ?? const []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    if (title != null)
                      Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                    ...?actions,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class OaPositionPicker extends StatelessWidget {
  final int businessId;
  final String label;
  final int? valueId;
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final bool enabled;
  final bool includeInactive;
  final OfficeAutomationService? service;

  const OaPositionPicker({
    super.key,
    required this.businessId,
    required this.label,
    required this.onChanged,
    this.valueId,
    this.value,
    this.enabled = true,
    this.includeInactive = false,
    this.service,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final svc = service ?? OfficeAutomationService();
    final selected = value ?? (valueId == null ? null : {'id': valueId});
    return OaSearchableField(
      label: label,
      hint: t.oaSearchPosition,
      searchHint: t.oaSearchPositionHint,
      emptyText: t.oaNoSearchResults,
      enabled: enabled,
      prefixIcon: Icons.badge_outlined,
      value: selected == null || oaId(selected['id']) == null
          ? null
          : oaPositionItem({
              ...selected,
              'title': selected['title'] ?? selected['code'] ?? t.oaPositions,
            }),
      onChanged: (item) {
        if (item == null) {
          onChanged(null);
          return;
        }
        final payload = item.payload;
        onChanged(payload is Map<String, dynamic> ? payload : {'id': int.tryParse(item.id), 'title': item.title});
      },
      onSearch: (q) async {
        final rows = await svc.listPositions(
          businessId: businessId,
          includeInactive: includeInactive,
          q: q,
          limit: 40,
        );
        return [for (final p in rows) if (oaId(p['id']) != null) oaPositionItem(p)];
      },
    );
  }
}

class OaLetterPicker extends StatelessWidget {
  final int businessId;
  final String label;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final OfficeAutomationService? service;

  const OaLetterPicker({
    super.key,
    required this.businessId,
    required this.label,
    required this.onChanged,
    this.service,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final svc = service ?? OfficeAutomationService();
    return OaSearchableField(
      label: label,
      hint: t.oaSearchLetter,
      emptyText: t.oaNoSearchResults,
      prefixIcon: Icons.mail_outline,
      onChanged: (item) {
        final payload = item?.payload;
        onChanged(payload is Map<String, dynamic> ? payload : null);
      },
      onSearch: (q) async {
        final rows = await svc.searchLetters(businessId: businessId, q: q, limit: 20);
        return [
          for (final row in rows)
            OaSearchItem(
              id: '${row['id']}',
              title: (row['subject'] ?? '').toString(),
              subtitle: [row['secretariat_number'] ?? '', row['id']].where((e) => '$e'.isNotEmpty).join(' · '),
              icon: Icons.mail_outline,
              payload: row,
            ),
        ];
      },
    );
  }
}
