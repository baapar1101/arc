import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/support_models.dart';
import 'package:hesabix_ui/utils/support_ticket_clipboard.dart';
import 'package:hesabix_ui/widgets/support/support_semantic_colors.dart';

/// Pinned initial ticket request — collapsed by default for operators to save thread space.
class TicketPinnedRequest extends StatelessWidget {
  final SupportTicket ticket;
  final bool isOperator;
  final bool initiallyExpanded;

  const TicketPinnedRequest({
    super.key,
    required this.ticket,
    this.isOperator = false,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = SupportSemanticColors.of(context);
    final description = ticket.description.trim();
    if (description.isEmpty) return const SizedBox.shrink();

    final preview = description.length > 90 ? '${description.substring(0, 90)}…' : description;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colors.pinnedRequestBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.pinnedRequestBorder),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(Icons.push_pin_outlined, size: 16, color: theme.colorScheme.primary),
          title: Text(
            l10n.ticketTitle,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOperator)
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  tooltip: l10n.supportTicketCopyRequest,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => copySupportTextToClipboard(context, description),
                ),
              if (ticket.category != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Text(
                    ticket.category!.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Icon(Icons.expand_more, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: isOperator
                  ? SelectableText(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    )
                  : Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
