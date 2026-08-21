import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/widgets/ai/ai_channel_assist_stream.dart';
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
  late final AIService _aiService;
  bool _loading = false;
  String? _summary;
  String? _phase;
  List<String> _toolsUsed = const [];
  List<Map<String, dynamic>> _citations = const [];
  bool _expanded = false;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _aiService = AIService(ApiClient());
  }

  @override
  void dispose() {
    _cancel?.cancel('disposed');
    super.dispose();
  }

  Future<void> _fetchSummary() async {
    if (widget.leadId == null && widget.dealId == null) return;
    _cancel?.cancel('replaced');
    final token = CancelToken();
    _cancel = token;
    setState(() {
      _loading = true;
      _summary = '';
      _phase = 'connecting';
      _toolsUsed = const [];
      _citations = const [];
      _expanded = true;
    });
    try {
      final stream = widget.leadId != null
          ? _aiService.streamCrmSummarizeLead(
              businessId: widget.businessId,
              leadId: widget.leadId!,
              cancelToken: token,
            )
          : _aiService.streamCrmSummarizeDeal(
              businessId: widget.businessId,
              dealId: widget.dealId!,
              cancelToken: token,
            );
      final outcome = await consumeChannelAssistStream(
        stream,
        onProgress: (progress) {
          if (!mounted || token.isCancelled) return;
          setState(() {
            _summary = progress.text;
            _phase = progress.phase;
            _toolsUsed = progress.toolsUsed;
          });
        },
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _summary = outcome.text.isNotEmpty ? outcome.text : _summary;
        _toolsUsed = outcome.toolsUsed.isNotEmpty ? outcome.toolsUsed : _toolsUsed;
        _citations = outcome.citations;
        _loading = false;
        _phase = null;
      });
      if (outcome.error != null && outcome.error!.trim().isNotEmpty) {
        SnackBarHelper.show(
          context,
          message: outcome.error!,
          isError: true,
        );
      }
    } catch (e) {
      if (token.isCancelled) return;
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  void _stop() {
    _cancel?.cancel('stop');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _phase = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasBody = (_summary != null && _summary!.isNotEmpty) || _loading;
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
                      l10n.aiCrmAssistantTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (hasBody)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 8),
                  if (_loading)
                    OutlinedButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop, size: 18),
                      label: Text(l10n.aiCrmStopAction),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _fetchSummary,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(l10n.aiCrmSummarizeAction),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && hasBody)
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
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                              Text(
                                aiStreamStatusLabel(
                                  l10n,
                                  phase: _phase ?? 'thinking',
                                ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_summary != null && _summary!.isNotEmpty)
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
                    if (_summary != null && _summary!.isNotEmpty)
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
