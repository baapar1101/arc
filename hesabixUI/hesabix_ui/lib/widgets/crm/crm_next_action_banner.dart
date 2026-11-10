import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// مسیر رکوردی که اقدام بعدی به آن اشاره می‌کند.
String? crmNextActionPath(int businessId, Map<String, dynamic> action) {
  final entityType = action['entity_type']?.toString();
  final entityId = (action['entity_id'] as num?)?.toInt();
  final dealId = (action['deal_id'] as num?)?.toInt();
  final leadId = (action['lead_id'] as num?)?.toInt();
  final personId = (action['person_id'] as num?)?.toInt();
  final base = '/business/$businessId/crm';
  if (entityType == 'activity' && entityId != null) return '$base/activities?activityId=$entityId';
  if (entityType == 'document' && entityId != null) return '/business/$businessId/invoice/$entityId/edit';
  if (entityType == 'note' && entityId != null) return '$base/notes-calendar?noteId=$entityId';
  if (entityType == 'lead' && entityId != null) return '$base/leads/$entityId';
  if (entityType == 'deal' && entityId != null) return '$base/deals/$entityId';
  if (dealId != null) return '$base/deals/$dealId';
  if (leadId != null) return '$base/leads/$leadId';
  if (personId != null) return '$base/customer-360?personId=$personId';
  return null;
}

/// اقدام بعدی که سرور با قاعده محاسبه کرده است.
class CrmNextActionBanner extends StatelessWidget {
  const CrmNextActionBanner({super.key, required this.action, required this.businessId});

  final Map<String, dynamic>? action;
  final int businessId;

  @override
  Widget build(BuildContext context) {
    final data = action;
    final title = data?['title']?.toString() ?? '';
    if (title.isEmpty || data == null) return const SizedBox.shrink();
    final reason = data['reason']?.toString() ?? '';
    final path = crmNextActionPath(businessId, data);
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: path == null ? null : () => context.go(path),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.flag_outlined, color: cs.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSecondaryContainer),
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(reason, style: TextStyle(color: cs.onSecondaryContainer)),
                    ],
                  ],
                ),
              ),
              if (path != null) Icon(Icons.chevron_left, color: cs.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

class CrmLinkedDocumentsCard extends StatelessWidget {
  const CrmLinkedDocumentsCard({super.key, required this.documents, this.businessId});

  final List<dynamic> documents;
  final int? businessId;

  static const _roles = {
    'proforma': 'پیش‌فاکتور',
    'invoice': 'فاکتور',
    'receipt': 'رسید',
  };

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اسناد مرتبط', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final raw in documents)
              if (raw is Map)
                Builder(
                  builder: (context) {
                    final docType = raw['document_type']?.toString() ?? '';
                    final docId = (raw['document_id'] as num?)?.toInt();
                    final canOpen = businessId != null && docId != null && docType.startsWith('invoice');
                    return InkWell(
                      onTap: canOpen
                          ? () => context.go('/business/$businessId/invoice/$docId/edit')
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_roles[raw['role']?.toString()] ?? raw['role'] ?? 'سند'} ${raw['code'] ?? raw['document_id'] ?? ''}',
                              ),
                            ),
                            if (canOpen) Icon(Icons.chevron_left, size: 18, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}
