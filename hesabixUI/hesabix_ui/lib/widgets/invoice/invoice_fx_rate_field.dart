import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

String invoiceFxFormatRowLabel(AppLocalizations t, Map<String, dynamic> e) {
  final rawRate = e['rate'];
  final rate = rawRate == null ? '—' : formatFxRateForDisplay(rawRate);
  var eff = e['effective_at']?.toString() ?? '';
  if (eff.isEmpty) {
    eff = '—';
  } else if (eff.length > 24) {
    eff = '${eff.substring(0, 24)}…';
  }
  final id = (e['id'] as num?)?.toInt();
  final idPart = id != null ? ' (#$id)' : '';
  return t.invoiceFxRateRow(rate, eff, idPart);
}

/// انتخاب نرخ تسعیر دستی (با جست‌وجو در فهرست)؛ `null` یعنی خودکار.
class InvoiceFxRateField extends StatefulWidget {
  const InvoiceFxRateField({
    super.key,
    required this.show,
    required this.loading,
    required this.manualRateId,
    required this.rateRows,
    this.onChanged,
  });

  final bool show;
  final bool loading;
  final int? manualRateId;
  final List<Map<String, dynamic>> rateRows;
  final ValueChanged<int?>? onChanged;

  @override
  State<InvoiceFxRateField> createState() => _InvoiceFxRateFieldState();
}

class _InvoiceFxRateFieldState extends State<InvoiceFxRateField> {
  String _summaryLabel(AppLocalizations t) {
    if (widget.manualRateId == null) {
      return t.invoiceFxRateAuto;
    }
    for (final e in widget.rateRows) {
      if ((e['id'] as num?)?.toInt() == widget.manualRateId) {
        return invoiceFxFormatRowLabel(t, Map<String, dynamic>.from(e));
      }
    }
    return t.invoiceFxRateStoredOnDocument;
  }

  List<Map<String, dynamic>> _rowsWithOrphan(AppLocalizations t) {
    final rows = <Map<String, dynamic>>[...widget.rateRows];
    final mid = widget.manualRateId;
    if (mid != null && !rows.any((e) => (e['id'] as num?)?.toInt() == mid)) {
      rows.insert(0, {
        'id': mid,
        'rate': '—',
        'effective_at': t.invoiceFxRateStoredOnDocument,
      });
    }
    return rows;
  }

  Future<void> _openPicker() async {
    if (widget.onChanged == null) return;
    final t = AppLocalizations.of(context);
    final searchCtrl = TextEditingController();
    final rows = _rowsWithOrphan(t);
    final selected = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            final q = searchCtrl.text.trim().toLowerCase();
            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        t.invoiceFxRateFieldLabel,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        onChanged: (_) => setModal(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: '${t.search}…',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Scrollbar(
                        child: ListView(
                          children: [
                            ListTile(
                              title: Text(t.invoiceFxRateAuto),
                              leading: const Icon(Icons.auto_fix_high),
                              onTap: () => Navigator.of(ctx).pop(-1), // sentin
                            ),
                            const Divider(height: 1),
                            ...() {
                              final out = <Widget>[];
                              for (final e in rows) {
                                final label = invoiceFxFormatRowLabel(
                                  t,
                                  Map<String, dynamic>.from(e),
                                );
                                if (q.isNotEmpty && !label.toLowerCase().contains(q)) {
                                  continue;
                                }
                                final id = (e['id'] as num).toInt();
                                out.add(
                                  ListTile(
                                    title: Text(
                                      label,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => Navigator.of(ctx).pop(id),
                                  ),
                                );
                              }
                              if (out.isEmpty) {
                                return [
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: Text(
                                        t.noDataFound,
                                        style: Theme.of(ctx).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                                ];
                              }
                              return out;
                            }(),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(t.cancel),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    if (selected == null) return;
    if (selected == -1) {
      widget.onChanged?.call(null);
    } else {
      widget.onChanged?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.loading) const LinearProgressIndicator(),
        SizedBox(
          height: 56,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: t.invoiceFxRateFieldLabel,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: InkWell(
              onTap: widget.loading ? null : _openPicker,
              child: Row(
                children: [
                  if (widget.loading) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _summaryLabel(t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ),
        if (!widget.loading)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
            child: Text(
              t.invoiceFxRateHelper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
      ],
    );
  }
}
