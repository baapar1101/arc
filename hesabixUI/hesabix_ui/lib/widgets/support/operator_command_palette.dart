import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/widgets/support/operator_inbox_list.dart';

/// Slim command palette focused on power actions (open by ID, bulk ops, views).
class OperatorCommandPalette extends StatefulWidget {
  final void Function(OperatorInboxView view)? onSelectView;
  final VoidCallback? onRefresh;
  final VoidCallback? onAssignToMe;
  final VoidCallback? onMarkResolved;
  final void Function(int ticketId)? onOpenTicket;

  const OperatorCommandPalette({
    super.key,
    this.onSelectView,
    this.onRefresh,
    this.onAssignToMe,
    this.onMarkResolved,
    this.onOpenTicket,
  });

  static Future<void> show(BuildContext context, OperatorCommandPalette palette) {
    return showDialog(
      context: context,
      builder: (_) => palette,
    );
  }

  @override
  State<OperatorCommandPalette> createState() => _OperatorCommandPaletteState();
}

class _OperatorCommandPaletteState extends State<OperatorCommandPalette> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Cmd> get _all => [
        _Cmd('باز کردن تیکت با شماره…', Icons.tag, _promptTicketId),
        _Cmd('بروزرسانی لیست', Icons.refresh, () {
          Navigator.pop(context);
          widget.onRefresh?.call();
        }),
        _Cmd('تخصیص به من', Icons.person_add, () {
          Navigator.pop(context);
          widget.onAssignToMe?.call();
        }),
        _Cmd('علامت حل‌شده', Icons.check_circle_outline, () {
          Navigator.pop(context);
          widget.onMarkResolved?.call();
        }),
        for (final v in OperatorInboxView.values)
          _Cmd('نمای: ${v.label}', v.icon, () {
            Navigator.pop(context);
            widget.onSelectView?.call(v);
          }),
      ];

  List<_Cmd> get _filtered {
    if (_query.isEmpty) return _all;
    return _all.where((c) => c.label.contains(_query)).toList();
  }

  Future<void> _promptTicketId() async {
    final controller = TextEditingController();
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('باز کردن تیکت'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'شماره تیکت'),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const Text('باز کردن'),
          ),
        ],
      ),
    );
    if (id != null && id > 0 && mounted) {
      Navigator.pop(context);
      widget.onOpenTicket?.call(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            Navigator.pop(context);
            return null;
          }),
        },
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.bolt_outlined),
                      hintText: 'دستور سریع… (Ctrl+K)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final cmd = _filtered[i];
                      return ListTile(
                        leading: Icon(cmd.icon),
                        title: Text(cmd.label),
                        onTap: cmd.run,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Esc بستن', style: theme.textTheme.labelSmall),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cmd {
  final String label;
  final IconData icon;
  final VoidCallback run;

  _Cmd(this.label, this.icon, this.run);
}
