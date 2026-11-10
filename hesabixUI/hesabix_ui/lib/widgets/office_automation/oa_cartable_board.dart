import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'oa_ui.dart';

class OaCartableBoard extends StatelessWidget {
  final Map<String, dynamic> columns;
  final bool canRefer;
  final int? selectedLetterId;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final void Function(Map<String, dynamic> item, String target) onMove;

  const OaCartableBoard({
    super.key,
    required this.columns,
    required this.canRefer,
    required this.selectedLetterId,
    required this.onOpen,
    required this.onMove,
  });

  static const _order = ['pending', 'seen', 'done', 'returned'];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      children: [
        for (final key in _order)
          _Column(
            title: _title(t, key),
            status: key,
            items: _items(key),
            total: _total(key),
            canRefer: canRefer,
            selectedLetterId: selectedLetterId,
            onOpen: onOpen,
            onMove: onMove,
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _items(String key) {
    final raw = columns[key];
    if (raw is! Map) return const [];
    final items = raw['items'];
    if (items is! List) return const [];
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  int _total(String key) {
    final raw = columns[key];
    if (raw is! Map) return 0;
    return (raw['total'] as num?)?.toInt() ?? _items(key).length;
  }

  String _title(AppLocalizations t, String key) {
    switch (key) {
      case 'pending':
        return t.oaColumnPending;
      case 'seen':
        return t.oaColumnSeen;
      case 'done':
        return t.oaColumnDone;
      case 'returned':
        return t.oaColumnReturned;
      default:
        return key;
    }
  }
}

class _Column extends StatelessWidget {
  final String title;
  final String status;
  final List<Map<String, dynamic>> items;
  final int total;
  final bool canRefer;
  final int? selectedLetterId;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final void Function(Map<String, dynamic> item, String target) onMove;

  const _Column({
    required this.title,
    required this.status,
    required this.items,
    required this.total,
    required this.canRefer,
    required this.selectedLetterId,
    required this.onOpen,
    required this.onMove,
  });

  bool get _droppable => canRefer && (status == 'done' || status == 'returned');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300,
      child: DragTarget<Map<String, dynamic>>(
        onWillAcceptWithDetails: (details) {
          if (!_droppable) return false;
          final current = '${details.data['referral_status'] ?? ''}';
          return current == 'pending' || current == 'seen';
        },
        onAcceptWithDetails: (details) => onMove(details.data, status),
        builder: (context, candidate, rejected) {
          final hot = candidate.isNotEmpty;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: hot ? cs.primaryContainer.withValues(alpha: 0.45) : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: hot ? cs.primary : cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: cs.surface,
                          child: Text('$total', style: const TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                  if (hot)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(t.oaDropHere, style: Theme.of(context).textTheme.labelMedium),
                    ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(child: Text(t.oaEmptyFolder, style: Theme.of(context).textTheme.bodySmall))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = items[index];
                              return _Card(
                                row: row,
                                selected: oaId(row['id']) == selectedLetterId,
                                draggable: canRefer && (row['referral_status'] == 'pending' || row['referral_status'] == 'seen'),
                                onOpen: () => onOpen(row),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool selected;
  final bool draggable;
  final VoidCallback onOpen;

  const _Card({required this.row, required this.selected, required this.draggable, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final subject = '${row['subject'] ?? ''}';
    final number = '${row['secretariat_number'] ?? ''}';
    final urgency = '${row['urgency'] ?? 'normal'}';
    final confidentiality = '${row['confidentiality'] ?? 'normal'}';
    final card = Material(
      color: selected ? cs.secondaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (number.isNotEmpty) OaStatusChip(label: number, icon: Icons.tag),
                  if (urgency != 'normal')
                    OaStatusChip(label: oaUrgencyLabel(t, urgency), color: oaUrgencyColor(cs, urgency)),
                  if (confidentiality != 'normal')
                    OaStatusChip(
                      label: oaConfidentialityLabel(t, confidentiality),
                      icon: Icons.lock_outline,
                      color: cs.error,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!draggable) return card;
    return Draggable<Map<String, dynamic>>(
      data: row,
      feedback: SizedBox(width: 260, child: Opacity(opacity: 0.9, child: card)),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class OaCartablePreview extends StatefulWidget {
  final Map<String, dynamic>? letter;
  final bool loading;
  final bool canRefer;
  final bool canCompose;
  final String? referralStatus;
  final VoidCallback onClose;
  final VoidCallback onOpenFull;
  final VoidCallback? onComplete;
  final VoidCallback? onReturn;
  final Future<void> Function(List<int> bytes, String filename)? onDropFile;

  const OaCartablePreview({
    super.key,
    required this.letter,
    required this.loading,
    required this.canRefer,
    required this.canCompose,
    required this.referralStatus,
    required this.onClose,
    required this.onOpenFull,
    this.onComplete,
    this.onReturn,
    this.onDropFile,
  });

  @override
  State<OaCartablePreview> createState() => _OaCartablePreviewState();
}

class _OaCartablePreviewState extends State<OaCartablePreview> {
  bool _dropping = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final letter = widget.letter;
    final open = widget.referralStatus == 'pending' || widget.referralStatus == 'seen';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
          child: Row(
            children: [
              Expanded(child: Text(t.view, style: Theme.of(context).textTheme.titleSmall)),
              IconButton(tooltip: t.close, icon: const Icon(Icons.close), onPressed: widget.onClose),
            ],
          ),
        ),
        Expanded(
          child: widget.loading
              ? const Center(child: CircularProgressIndicator())
              : letter == null
                  ? Center(child: Text(t.oaEmptyFolder))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Text('${letter['subject'] ?? ''}', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if ('${letter['secretariat_number'] ?? ''}'.isNotEmpty)
                              OaStatusChip(label: '${letter['secretariat_number']}', icon: Icons.tag),
                            OaStatusChip(label: oaStatusLabel(t, '${letter['status'] ?? ''}')),
                            if ('${letter['confidentiality'] ?? 'normal'}' != 'normal')
                              OaStatusChip(
                                label: oaConfidentialityLabel(t, '${letter['confidentiality']}'),
                                icon: Icons.lock_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${letter['body'] ?? ''}',
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: widget.onOpenFull,
                              icon: const Icon(Icons.open_in_new),
                              label: Text(t.oaOpenLetter),
                            ),
                            if (widget.canRefer && open && widget.onComplete != null)
                              FilledButton.icon(onPressed: widget.onComplete, icon: const Icon(Icons.done), label: Text(t.oaComplete)),
                            if (widget.canRefer && open && widget.onReturn != null)
                              OutlinedButton.icon(onPressed: widget.onReturn, icon: const Icon(Icons.undo), label: Text(t.oaReturn)),
                          ],
                        ),
                        if (widget.canCompose) ...[
                          const SizedBox(height: 16),
                          Text(t.oaDropAttachment, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
        ),
      ],
    );
    if (!widget.canCompose || widget.onDropFile == null) return body;
    return DropTarget(
      onDragEntered: (_) {
        if (mounted) setState(() => _dropping = true);
      },
      onDragExited: (_) {
        if (mounted) setState(() => _dropping = false);
      },
      onDragDone: (detail) async {
        if (mounted) setState(() => _dropping = false);
        for (final file in detail.files) {
          final bytes = await file.readAsBytes();
          await widget.onDropFile!(bytes, file.name);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        foregroundDecoration: _dropping
            ? BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: body,
      ),
    );
  }
}
