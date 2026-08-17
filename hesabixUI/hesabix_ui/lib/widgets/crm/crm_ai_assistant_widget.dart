import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_l10n.dart';
import 'package:hesabix_ui/widgets/ai/ai_citation_chips.dart';

/// ویجت دستیار AI برای خلاصه سرنخ یا فرصت فروش
class CrmAIAssistantWidget extends StatefulWidget {
  final int businessId;
  final CrmService crmService;
  final int? leadId;
  final int? dealId;

  const CrmAIAssistantWidget({
    super.key,
    required this.businessId,
    required this.crmService,
    this.leadId,
    this.dealId,
  }) : assert(leadId != null || dealId != null, 'حداقل leadId یا dealId الزامی است');

  @override
  State<CrmAIAssistantWidget> createState() => _CrmAIAssistantWidgetState();
}

class _CrmAIAssistantWidgetState extends State<CrmAIAssistantWidget> {
  bool _loading = false;
  String? _summary;
  List<String> _toolsUsed = const [];
  List<Map<String, dynamic>> _citations = const [];
  bool _expanded = false;

  Future<void> _fetchSummary() async {
    if (widget.leadId == null && widget.dealId == null) return;
    setState(() {
      _loading = true;
      _summary = null;
      _toolsUsed = const [];
      _citations = const [];
    });
    try {
      dynamic data;
      if (widget.leadId != null) {
        data = await widget.crmService.aiSummarizeLead(
          businessId: widget.businessId,
          leadId: widget.leadId!,
        );
      } else {
        data = await widget.crmService.aiSummarizeDeal(
          businessId: widget.businessId,
          dealId: widget.dealId!,
        );
      }
      if (!mounted) return;
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final summary = map['summary']?.toString();
      final toolsRaw = map['tools_used'];
      final citesRaw = map['citations'];
      setState(() {
        _summary = summary;
        _toolsUsed = toolsRaw is List
            ? toolsRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
            : const [];
        _citations = citesRaw is List
            ? citesRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : const [];
        _loading = false;
        _expanded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'دستیار هوشمند',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_summary != null)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _loading ? null : _fetchSummary,
                    icon: _loading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_loading ? 'در حال پردازش...' : 'خلاصه و پیشنهاد'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && _summary != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _summary!,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (_toolsUsed.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        l10n.aiReasoningToolsUsedTitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _toolsUsed
                            .take(8)
                            .map(
                              (name) => Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  aiToolLabel(l10n, name),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    AICitationChips(
                      businessId: widget.businessId,
                      functionResults: {
                        kAgentCitationsStorageKey: _citations,
                      },
                      assistantContent: _summary!,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
