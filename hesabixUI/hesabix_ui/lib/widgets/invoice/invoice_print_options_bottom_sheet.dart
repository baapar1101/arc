import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/constants/invoice_print_paper.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// نتیجهٔ تأیید در برگهٔ پایین تنظیمات چاپ فاکتور (هم‌تراز با پارامترهای query در API PDF).
class InvoicePrintOptionsResult {
  final String? paperSize;
  final String orientation;
  final bool showStamp;
  final bool showShareQr;
  final int? templateId;

  const InvoicePrintOptionsResult({
    this.paperSize,
    required this.orientation,
    required this.showStamp,
    this.showShareQr = false,
    this.templateId,
  });
}

/// برگهٔ پایین برای انتخاب سایز، جهت، مهر و قالب چاپ قبل از دانلود PDF فاکتور.
Future<InvoicePrintOptionsResult?> showInvoicePrintOptionsBottomSheet({
  required BuildContext context,
  required List<Map<String, dynamic>> templates,
  List<Map<String, dynamic>> receiptTemplates = const [],
  required bool loadingTemplates,
  String? initialPaperSize,
  String initialOrientation = 'landscape',
  bool initialShowStamp = true,
  bool allowShareQrOption = true,
  bool initialShowShareQr = false,
  int? initialTemplateId,
}) {
  return showGlassModalBottomSheet<InvoicePrintOptionsResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      return _InvoicePrintOptionsSheet(
        templates: templates,
        receiptTemplates: receiptTemplates,
        loadingTemplates: loadingTemplates,
        initialPaperSize: initialPaperSize,
        initialOrientation: initialOrientation,
        initialShowStamp: initialShowStamp,
        allowShareQrOption: allowShareQrOption,
        initialShowShareQr: initialShowShareQr,
        initialTemplateId: initialTemplateId,
      );
    },
  );
}

class _InvoicePrintOptionsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> receiptTemplates;
  final bool loadingTemplates;
  final String? initialPaperSize;
  final String initialOrientation;
  final bool initialShowStamp;
  final bool allowShareQrOption;
  final bool initialShowShareQr;
  final int? initialTemplateId;

  const _InvoicePrintOptionsSheet({
    required this.templates,
    required this.receiptTemplates,
    required this.loadingTemplates,
    required this.initialPaperSize,
    required this.initialOrientation,
    required this.initialShowStamp,
    required this.allowShareQrOption,
    required this.initialShowShareQr,
    required this.initialTemplateId,
  });

  @override
  State<_InvoicePrintOptionsSheet> createState() => _InvoicePrintOptionsSheetState();
}

class _InvoicePrintOptionsSheetState extends State<_InvoicePrintOptionsSheet> {
  late String? _paperSize;
  late String _orientation;
  late bool _showStamp;
  late bool _showShareQr;
  late int? _templateId;

  @override
  void initState() {
    super.initState();
    _paperSize = widget.initialPaperSize;
    _orientation = invoicePrintOrientationForPaper(widget.initialPaperSize, widget.initialOrientation);
    _showStamp = widget.initialShowStamp;
    _showShareQr = widget.initialShowShareQr;
    _templateId = widget.initialTemplateId;
    final ids = _visibleTemplates.map((tpl) => (tpl['id'] as num?)?.toInt()).whereType<int>().toSet();
    if (_templateId != null && !ids.contains(_templateId)) {
      _templateId = null;
    }
  }

  bool get _isReceipt => isInvoiceReceiptPaper(_paperSize);

  List<Map<String, dynamic>> get _visibleTemplates =>
      _isReceipt ? widget.receiptTemplates : widget.templates;

  void _onPaperSizeChanged(String? v) {
    setState(() {
      _paperSize = v;
      _orientation = invoicePrintOrientationForPaper(v, _orientation);
      final ids = _visibleTemplates.map((tpl) => (tpl['id'] as num?)?.toInt()).whereType<int>().toSet();
      if (_templateId != null && !ids.contains(_templateId)) {
        _templateId = null;
      }
    });
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
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('پیش‌فرض'),
                  ),
                  ...kInvoicePrintPaperOptions.map(
                    (o) => DropdownMenuItem<String?>(
                      value: o.value,
                      child: Text(o.labelFa),
                    ),
                  ),
                ],
                onChanged: _onPaperSizeChanged,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _orientation,
                decoration: InputDecoration(
                  labelText: 'جهت چاپ',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: _isReceipt ? 'فیش پرینتر همیشه عمودی چاپ می‌شود' : null,
                ),
                items: const [
                  DropdownMenuItem(value: 'portrait', child: Text('عمودی (Portrait)')),
                  DropdownMenuItem(value: 'landscape', child: Text('افقی (Landscape)')),
                ],
                onChanged: _isReceipt
                    ? null
                    : (v) => setState(() => _orientation = v ?? 'landscape'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('نمایش مهر و امضا'),
                subtitle: const Text('در صورت غیرفعال بودن، مهر و امضا در PDF نمایش داده نمی‌شود'),
                value: _showStamp,
                onChanged: (v) => setState(() => _showStamp = v),
              ),
              if (widget.allowShareQrOption) ...[
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('QR نمایش آنلاین / اعتبارسنجی'),
                  subtitle: const Text('در صورت فعال بودن، کد QR بالای فاکتور درج می‌شود'),
                  value: _showShareQr,
                  onChanged: (v) => setState(() => _showShareQr = v),
                ),
              ],
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
                    ..._visibleTemplates.map((tpl) {
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
                            showShareQr: widget.allowShareQrOption ? _showShareQr : false,
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
