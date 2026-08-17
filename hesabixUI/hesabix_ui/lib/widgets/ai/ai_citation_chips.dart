import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/business_nav.dart';
import '../../models/ai_stream_event.dart';
import 'ai_chat_l10n.dart';

/// منبع استناد پایدار از نتایج ابزار (RAG-02).
class AICitationSource {
  final Object? id;
  final String? name;
  final String? entity;
  final String? type;
  final Object? amount;
  final String? source;

  const AICitationSource({
    this.id,
    this.name,
    this.entity,
    this.type,
    this.amount,
    this.source,
  });

  factory AICitationSource.fromJson(Map<String, dynamic> json) {
    return AICitationSource(
      id: json['id'],
      name: json['name']?.toString(),
      entity: json['entity']?.toString(),
      type: json['type']?.toString(),
      amount: json['amount'] ?? json['total'] ?? json['balance'],
      source: json['source']?.toString(),
    );
  }

  String get label {
    final parts = <String>[];
    if (name != null && name!.trim().isNotEmpty) {
      parts.add(name!.trim());
    }
    if (id != null) {
      parts.add('#$id');
    }
    if (parts.isEmpty && type != null) {
      parts.add(type!);
    }
    return parts.isEmpty ? (source ?? '') : parts.join(' ');
  }

  /// مسیر نسبی پنل کسب‌وکار؛ null یعنی فقط کپی.
  String? get relativePath {
    final rawId = id?.toString().trim();
    if (rawId == null || rawId.isEmpty) return null;
    final kind = (entity ?? type ?? source ?? '').toLowerCase();
    bool hit(List<String> keys) => keys.any(kind.contains);
    if (hit(const ['invoice', 'فاکتور'])) return 'invoice/$rawId/edit';
    if (hit(const ['person', 'customer', 'مشتری'])) {
      return 'crm/customer-360/$rawId';
    }
    if (hit(const ['lead', 'سرنخ'])) return 'crm/leads/$rawId';
    if (hit(const ['deal', 'فرصت'])) return 'crm/deals/$rawId';
    if (hit(const ['workflow'])) return 'workflows/$rawId/edit';
    if (hit(const ['warehouse'])) return 'warehouse-docs/$rawId';
    return null;
  }
}

bool contentHasMoneyishClaim(String content) {
  final text = content.trim();
  if (text.isEmpty) return false;
  return RegExp(
    r'(ریال|تومان|میلیون|میلیارد|درصد|٪)|[\d۰-۹]{1,3}(?:[٬,][\d۰-۹]{3}){2,}',
  ).hasMatch(text);
}

List<AICitationSource> extractCitationSourcesFromResults(Object? functionResults) {
  if (functionResults is! Map) return const [];
  final stored = functionResults[kAgentCitationsStorageKey];
  if (stored is List && stored.isNotEmpty) {
    return stored
        .whereType<Map>()
        .map((e) => AICitationSource.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.label.isNotEmpty)
        .toList();
  }
  return const [];
}

String? ungroundedNumericWarning(String content, List<AICitationSource> sources) {
  if (sources.isNotEmpty) return null;
  if (!contentHasMoneyishClaim(content)) return null;
  return 'ungrounded';
}

/// chipهای منبع زیر پاسخ دستیار؛ در صورت داشتن مسیر، ناوبری می‌کند.
class AICitationChips extends StatelessWidget {
  final int? businessId;
  final Object? functionResults;
  final String assistantContent;

  const AICitationChips({
    super.key,
    required this.businessId,
    this.functionResults,
    required this.assistantContent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sources = extractCitationSourcesFromResults(functionResults);
    final warning = ungroundedNumericWarning(assistantContent, sources);
    if (sources.isEmpty && warning == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sources.isNotEmpty) ...[
            Text(
              aiCitationSourcesLabel(l10n),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sources.take(8).map((src) {
                final path = src.relativePath;
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    path != null ? Icons.open_in_new : Icons.copy,
                    size: 14,
                  ),
                  label: Text(src.label, overflow: TextOverflow.ellipsis),
                  onPressed: () => _onTap(context, src, path),
                );
              }).toList(),
            ),
          ],
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                aiCitationUngroundedWarning(l10n),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onTap(BuildContext context, AICitationSource src, String? path) {
    if (path != null && businessId != null) {
      context.go(context.businessPanelUrl(businessId!, path));
      return;
    }
    final text = src.label;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
  }
}
