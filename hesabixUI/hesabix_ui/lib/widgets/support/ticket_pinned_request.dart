import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/utils/support_ticket_clipboard.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';

/// Pinned initial ticket request shown at top of conversation thread.
class TicketPinnedRequest extends StatelessWidget {
  final SupportTicket ticket;
  final bool isOperator;

  const TicketPinnedRequest({
    super.key,
    required this.ticket,
    this.isOperator = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = SupportSemanticColors.of(context);
    final description = ticket.description.trim();
    if (description.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.pinnedRequestBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.pinnedRequestBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                l10n.ticketTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (isOperator)
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: l10n.supportTicketCopyRequest,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => copySupportTextToClipboard(context, description),
                ),
              if (ticket.category != null)
                Chip(
                  label: Text(ticket.category!.name),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 8),
          isOperator
              ? SelectableText(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                )
              : Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
        ],
      ),
    );
  }
}
