import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// دیالوگ انتخاب اندازه بوم خالی قبل از ورود به استودیو.
class LabelBlankCanvasDialog extends StatefulWidget {
  const LabelBlankCanvasDialog({super.key});

  static Future<LabelBlankCanvasResult?> show(BuildContext context) {
    return showGlassDialog<LabelBlankCanvasResult>(
      context: context,
      builder: (_) => const LabelBlankCanvasDialog(),
    );
  }

  @override
  State<LabelBlankCanvasDialog> createState() => _LabelBlankCanvasDialogState();
}

class LabelBlankCanvasResult {
  final double widthMm;
  final double heightMm;
  final bool rollMode;

  const LabelBlankCanvasResult({
    required this.widthMm,
    required this.heightMm,
    this.rollMode = false,
  });
}

class _LabelBlankCanvasDialogState extends State<LabelBlankCanvasDialog> {
  final _wCtrl = TextEditingController(text: '50');
  final _hCtrl = TextEditingController(text: '30');
  bool _rollMode = false;

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final w = double.tryParse(_wCtrl.text.replaceAll(',', '.'));
    final h = double.tryParse(_hCtrl.text.replaceAll(',', '.'));
    if (w == null || h == null || w < 10 || h < 5 || w > 500 || h > 500) return;
    Navigator.pop(
      context,
      LabelBlankCanvasResult(widthMm: w, heightMm: h, rollMode: _rollMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.barcodeLabelBlankCanvasDialogTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.barcodeLabelBlankCanvasDialogHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wCtrl,
                    decoration: InputDecoration(
                      labelText: t.barcodeLabelCanvasWidth,
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hCtrl,
                    decoration: InputDecoration(
                      labelText: t.barcodeLabelCanvasHeight,
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.barcodeLabelPrintLayoutRoll),
              subtitle: Text(t.barcodeLabelRollModeHint),
              value: _rollMode,
              onChanged: (v) => setState(() => _rollMode = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.barcodeLabelStartDesign)),
      ],
    );
  }
}
