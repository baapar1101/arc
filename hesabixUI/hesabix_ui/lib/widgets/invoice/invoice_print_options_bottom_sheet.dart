import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// نتیجهٔ تأیید در برگهٔ پایین تنظیمات چاپ فاکتور (هم‌تراز با پارامترهای query در API PDF).
class InvoicePrintOptionsResult {
  final String? paperSize;
  final String orientation;
  final bool showStamp;
  final int? templateId;

  const InvoicePrintOptionsResult({
    this.paperSize,
    required this.orientation,
    required this.showStamp,
    this.templateId,
  });
}

/// برگهٔ پایین برای انتخاب سایز، جهت، مهر و قالب چاپ قبل از دانلود PDF فاکتور.
Future<InvoicePrintOptionsResult?> showInvoicePrintOptionsBottomSheet({
  required BuildContext context,
  required List<Map<String, dynamic>> templates,
  required bool loadingTemplates,
  String? initialPaperSize,
  String initialOrientation = 'landscape',
  bool initialShowStamp = true,
  int? initialTemplateId,
}) {
  return showModalBottomSheet<InvoicePrintOptionsResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      return _InvoicePrintOptionsSheet(
        templates: templates,
        loadingTemplates: loadingTemplates,
        initialPaperSize: initialPaperSize,
        initialOrientation: initialOrientation,
        initialShowStamp: initialShowStamp,
        initialTemplateId: initialTemplateId,
      );
    },
  );
}

class _InvoicePrintOptionsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  final bool loadingTemplates;
  final String? initialPaperSize;
  final String initialOrientation;
  final bool initialShowStamp;
  final int? initialTemplateId;

  const _InvoicePrintOptionsSheet({
    required this.templates,
    required this.loadingTemplates,
    required this.initialPaperSize,
    required this.initialOrientation,
    required this.initialShowStamp,
    required this.initialTemplateId,
  });

  @override
  State<_InvoicePrintOptionsSheet> createState() => _InvoicePrintOptionsSheetState();
}

class _InvoicePrintOptionsSheetState extends State<_InvoicePrintOptionsSheet> {
  late String? _paperSize;
  late String _orientation;
  late bool _showStamp;
  late int? _templateId;

  @override
  void initState() {
    super.initState();
    _paperSize = widget.initialPaperSize;
    _orientation = widget.initialOrientation;
    _showStamp = widget.initialShowStamp;
    _templateId = widget.initialTemplateId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.print_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.printPdf,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                value: _paperSize,
                decoration: const InputDecoration(
                  labelText: 'سایز کاغذ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('پیش‌فرض'),
                  ),
                  DropdownMenuItem(value: 'A4', child: Text('A4')),
                  DropdownMenuItem(value: 'A5', child: Text('A5')),
                  DropdownMenuItem(value: 'A6', child: Text('A6')),
                  DropdownMenuItem(value: '80mm', child: Text('80mm (فیش)')),
                ],
                onChanged: (v) => setState(() => _paperSize = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _orientation,
                decoration: const InputDecoration(
                  labelText: 'جهت چاپ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'portrait', child: Text('عمودی (Portrait)')),
                  DropdownMenuItem(value: 'landscape', child: Text('افقی (Landscape)')),
                ],
                onChanged: (v) => setState(() => _orientation = v ?? 'landscape'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('نمایش مهر و امضا'),
                subtitle: const Text('در صورت غیرفعال بودن، مهر و امضا در PDF نمایش داده نمی‌شود'),
                value: _showStamp,
                onChanged: (v) => setState(() => _showStamp = v),
              ),
              const SizedBox(height: 8),
              if (widget.loadingTemplates)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                DropdownButtonFormField<int?>(
                  value: _templateId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.printTemplate,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(t.noCustomTemplate),
                    ),
                    ...widget.templates.map((tpl) {
                      final id = (tpl['id'] as num).toInt();
                      final name = (tpl['name'] ?? 'Template').toString();
                      final isDefault = tpl['is_default'] == true;
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Row(
                          children: [
                            if (isDefault) const Icon(Icons.star, size: 16),
                            if (isDefault) const SizedBox(width: 4),
                            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() => _templateId = v),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          InvoicePrintOptionsResult(
                            paperSize: _paperSize,
                            orientation: _orientation,
                            showStamp: _showStamp,
                            templateId: _templateId,
                          ),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(t.printPdf),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
