import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../person/file_picker_bridge.dart';
import '../../services/invoice_service.dart';
import '../data_table/helpers/file_saver.dart';

class InvoiceImportDialog extends StatefulWidget {
  final int businessId;

  const InvoiceImportDialog({super.key, required this.businessId});

  @override
  State<InvoiceImportDialog> createState() => _InvoiceImportDialogState();
}

class _InvoiceImportDialogState extends State<InvoiceImportDialog> {
  final TextEditingController _pathCtrl = TextEditingController();
  bool _dryRun = true;
  bool _loading = false;
  Map<String, dynamic>? _result;
  PickedFileData? _selectedFile;
  bool _isInitialized = false;
  final InvoiceService _invoiceService = InvoiceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (!_isInitialized) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.loading)),
        );
      }
      return;
    }

    try {
      final picked = await FilePickerBridge.pickExcel();
      if (picked != null) {
        setState(() {
          _selectedFile = picked;
          _pathCtrl.text = picked.name;
        });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.pickFileError}: $e')),
        );
      }
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      setState(() => _loading = true);
      final bytes = await _invoiceService.downloadImportTemplate(
        businessId: widget.businessId,
      );
      String filename = 'invoices_import_template.xlsx';
      await FileSaver.saveBytes(bytes, filename);
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.templateDownloaded}: $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.templateDownloadError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => const _ImportHelpDialog(),
    );
  }

  Future<void> _runImport({required bool dryRun}) async {
    if (_selectedFile == null) {
      await _pickFile();
      if (_selectedFile == null) return;
    }
    final filename = _selectedFile!.name;
    final bytes = _selectedFile!.bytes;

    try {
      setState(() {
        _loading = true;
        _result = null;
      });
      
      final result = await _invoiceService.importInvoicesFromExcel(
        businessId: widget.businessId,
        fileBytes: bytes,
        filename: filename,
        dryRun: dryRun,
      );
      
      setState(() {
        _result = {'data': result};
      });
      
      if (!dryRun) {
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.importError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(t.importFromExcel),
          ),
          Tooltip(
            message: 'راهنمای استفاده از ایمپورت فاکتورها',
            child: IconButton(
              onPressed: _loading ? null : _showHelp,
              icon: const Icon(Icons.help_outline),
              tooltip: 'راهنما',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pathCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: t.selectedFile,
                    hintText: t.noFileSelected,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_loading || !_isInitialized) ? null : _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(t.chooseFile),
              ),
            ]),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _dryRun,
                  onChanged: (v) => setState(() => _dryRun = v ?? true),
                ),
                Text(t.dryRunValidateOnly),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _downloadTemplate,
                  icon: const Icon(Icons.download),
                  label: Text(t.downloadTemplate),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _runImport(dryRun: _dryRun),
                  icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                  label: Text(_dryRun ? t.reviewDryRun : t.import),
                ),
                const SizedBox(width: 8),
                if (_dryRun)
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : () async {
                      setState(() => _dryRun = false);
                      await _runImport(dryRun: false);
                    },
                    icon: const Icon(Icons.cloud_upload),
                    label: Text(t.importReal),
                  ),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text('${t.result}:', style: Theme.of(context).textTheme.titleSmall),
              ),
              const SizedBox(height: 8),
              _ResultSummary(result: _result!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: Text(t.close),
        ),
      ],
    );
  }
}

class _ResultSummary extends StatelessWidget {
  final Map<String, dynamic> result;
  const _ResultSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final data = result['data'] as Map<String, dynamic>?;
    final summary = (data?['summary'] as Map<String, dynamic>?) ?? {};
    final errors = (data?['errors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _chip(t.total, summary['total']),
            _chip(t.valid, summary['valid']),
            _chip(t.invalid, summary['invalid']),
            _chip('ایجاد شده', summary['created']),
            _chip(t.dryRun, summary['dry_run'] == true ? t.yes : t.no),
          ],
        ),
        const SizedBox(height: 8),
        if (errors.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.builder(
              itemCount: errors.length,
              itemBuilder: (context, i) {
                final e = errors[i];
                final invoiceNumber = e['invoice_number'] ?? '';
                final row = e['row'] ?? '';
                final errorList = (e['errors'] as List?)?.cast<String>() ?? [];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text('فاکتور: $invoiceNumber (ردیف: $row)'),
                  subtitle: Text(errorList.join(', ')),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _chip(String label, Object? value) {
    return Chip(label: Text('$label: ${value ?? '-'}'));
  }
}

class _ImportHelpDialog extends StatelessWidget {
  const _ImportHelpDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, size: 28),
                const SizedBox(width: 12),
                Text(
                  'راهنمای استفاده از ایمپورت فاکتورها',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      context,
                      '📋 ساختار فایل Excel',
                      [
                        'فایل Excel تمپلیت دارای یک Sheet است که در آن هر ردیف = یک ردیف فاکتور است.',
                        '',
                        'نکته مهم:',
                        '• ردیف‌هایی که invoice_number یکسان دارند، متعلق به یک فاکتور هستند',
                        '• برای هر فاکتور می‌توانید چند ردیف (چند کالا/خدمت) وارد کنید',
                        '• اطلاعات هدر فاکتور (مثل نوع فاکتور، تاریخ، مشتری) باید فقط در ردیف اول هر فاکتور وارد شوند',
                        '• در ردیف‌های بعدی همان فاکتور، ستون‌های هدر می‌توانند خالی باشند',
                        '• فقط invoice_number و اطلاعات ردیف (product_code, quantity, ...) در همه ردیف‌ها باید وارد شوند',
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      '📊 ستون‌های الزامی',
                      [
                        'ستون‌های هدر فاکتور (فقط در ردیف اول):',
                        '• invoice_number: شماره فاکتور (برای گروه‌بندی)',
                        '• invoice_type: نوع فاکتور (sales, purchase, sales_return, purchase_return, direct_consumption, production, waste)',
                        '• document_date: تاریخ فاکتور (YYYY-MM-DD)',
                        '• currency_code: کد ارز (IRR, USD, ...)',
                        '• person_code: کد مشتری/تامین‌کننده (برای sales/purchase الزامی است)',
                        '',
                        'ستون‌های ردیف فاکتور (در همه ردیف‌ها):',
                        '• product_code: کد کالا/خدمت',
                        '• quantity: تعداد',
                        '• unit_price: قیمت واحد',
                        '',
                        'ستون‌های اختیاری:',
                        '• is_proforma: پیش‌فاکتور (TRUE/FALSE)',
                        '• description: توضیحات فاکتور',
                        '• seller_code: کد فروشنده/بازاریاب',
                        '• due_date: تاریخ سررسید',
                        '• post_inventory: ثبت انبار (TRUE/FALSE)',
                        '• unit: واحد (main/secondary)',
                        '• discount_type: نوع تخفیف (percent/amount)',
                        '• discount_value: مقدار تخفیف',
                        '• tax_rate: نرخ مالیات (درصد)',
                        '• line_description: توضیحات ردیف',
                        '• movement: جهت حرکت (in/out - فقط برای فاکتور تولید)',
                        '• warehouse_code: کد انبار',
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      '📝 مثال عملی',
                      [
                        'مثال: فاکتور فروش با 2 کالا',
                        '',
                        'ردیف 1:',
                        'INV-001 | sales | 2024-01-15 | IRR | FALSE | فاکتور فروش | CUST-001 | | 2024-02-15 | TRUE | P1001 | 10 | main | 100000 | amount | 5000 | 9',
                        '',
                        'ردیف 2 (ستون‌های هدر خالی):',
                        'INV-001 | | | | | | | | | | P1002 | 5 | main | 200000 | percent | 10 | 9',
                        '',
                        'نکته: در ردیف دوم، فقط invoice_number و اطلاعات ردیف وارد شده است.',
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      '✅ مراحل استفاده',
                      [
                        '1. دانلود تمپلیت: روی دکمه "دانلود تمپلیت" کلیک کنید',
                        '2. پر کردن فایل:',
                        '   • برای هر فاکتور، یک invoice_number یکتا انتخاب کنید',
                        '   • در ردیف اول، اطلاعات هدر را کامل وارد کنید',
                        '   • در ردیف‌های بعدی، فقط invoice_number و اطلاعات ردیف را وارد کنید',
                        '3. بررسی: روی "بررسی (Dry Run)" کلیک کنید تا خطاها را ببینید',
                        '4. ایمپورت: پس از رفع خطاها، روی "ایمپورت واقعی" کلیک کنید',
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      '⚠️ نکات مهم',
                      [
                        '• کدهای محصول، مشتری، ارز و انبار باید قبلاً در سیستم ثبت شده باشند',
                        '• فرمت تاریخ: YYYY-MM-DD یا YYYY/MM/DD',
                        '• برای فاکتور تولید، movement الزامی است (in/out)',
                        '• برای فاکتورهای sales/purchase، person_code الزامی است',
                        '• در ردیف‌های بعدی هر فاکتور، ستون‌های هدر می‌توانند خالی باشند',
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                label: const Text('بستن'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 12),
        ...items.map((item) {
          if (item.isEmpty) {
            return const SizedBox(height: 8);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.startsWith('•'))
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Text('•', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  )
                else if (item.startsWith('  '))
                  const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    item.startsWith('•') ? item.substring(1).trim() : item,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

