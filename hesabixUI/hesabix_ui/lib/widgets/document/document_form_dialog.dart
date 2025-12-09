import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/services/account_service.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/document/document_line_editor.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import '../../utils/snackbar_helper.dart';

/// دیالوگ ایجاد یا ویرایش سند حسابداری دستی
class DocumentFormDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;
  final DocumentModel? document; // null = ایجاد جدید, not null = ویرایش
  final int? fiscalYearId;
  final int? currencyId;
  final List<DocumentLineEdit>? initialLines; // خطوط اولیه (مثلاً پیشنویس تولید)
  final String? initialDescription;
  final DateTime? initialDocumentDate;

  const DocumentFormDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
    this.document,
    this.fiscalYearId,
    this.currencyId,
    this.initialLines,
    this.initialDescription,
    this.initialDocumentDate,
  });

  @override
  State<DocumentFormDialog> createState() => _DocumentFormDialogState();
}

class _DocumentFormDialogState extends State<DocumentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late DocumentService _service;

  // کنترلرها
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  // مقادیر فرم
  DateTime? _documentDate;
  int? _currencyId;
  int? _projectId;
  bool _isProforma = false;
  List<DocumentLineEdit> _lines = [];

  // وضعیت
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _service = DocumentService(widget.apiClient);
    _currencyId = widget.currencyId; // اگر null باشد، CurrencyPickerWidget ارز پیش‌فرض را از API انتخاب می‌کند
    _documentDate = widget.initialDocumentDate ?? DateTime.now();

    // اگر حالت ویرایش است، مقادیر را بارگذاری کن
    if (widget.document != null) {
      _loadDocumentData();
    } else {
      // اگر خطوط اولیه ارسال شده باشد (مثل پیشنویس تولید) از آن استفاده کن
      if (widget.initialLines != null && widget.initialLines!.isNotEmpty) {
        _lines = widget.initialLines!.map((e) => e.copy()).toList();
        if (widget.initialDescription != null && widget.initialDescription!.isNotEmpty) {
          _descriptionController.text = widget.initialDescription!;
        }
      } else {
        // خط خالی برای شروع
        _lines = [
          DocumentLineEdit(),
          DocumentLineEdit(),
        ];
      }
    }
  }

  /// بارگذاری اطلاعات سند برای ویرایش
  Future<void> _loadDocumentData() async {
    final doc = widget.document!;
    
    _codeController.text = doc.code;
    _descriptionController.text = doc.description ?? '';
    _documentDate = doc.documentDate;
    _currencyId = doc.currencyId;
    _projectId = doc.projectId;
    _isProforma = doc.isProforma;

    // تبدیل سطرهای سند به DocumentLineEdit
    if (doc.lines != null && doc.lines!.isNotEmpty) {
      // بارگذاری Account برای هر سطر
      final accountService = AccountService(client: widget.apiClient);
      final loadedLines = <DocumentLineEdit>[];
      
      setState(() {
        _isLoading = true;
      });
      
      try {
        for (final line in doc.lines!) {
          Account? account;
          try {
            // بارگذاری حساب از API
            if (line.accountId != null) {
              final accountData = await accountService.getAccount(
                businessId: widget.businessId,
                accountId: line.accountId!,
              );
              account = Account.fromJson(accountData);
            }
          } catch (e) {
            // در صورت خطا، یک حساب خالی با ID می‌سازیم
            account = Account(
              id: line.accountId,
              businessId: widget.businessId,
              code: 'خطا',
              name: 'خطا در بارگذاری',
              accountType: 'asset',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }
          
          loadedLines.add(DocumentLineEdit(
            account: account,
            detail: {
              if (line.personId != null) 'person_id': line.personId,
              if (line.productId != null) 'product_id': line.productId,
              if (line.bankAccountId != null) 'bank_account_id': line.bankAccountId,
              if (line.cashRegisterId != null) 'cash_register_id': line.cashRegisterId,
              if (line.pettyCashId != null) 'petty_cash_id': line.pettyCashId,
              if (line.checkId != null) 'check_id': line.checkId,
            },
            debit: line.debit,
            credit: line.credit,
            description: line.description,
            quantity: line.quantity,
          ));
        }
        
        if (mounted) {
          setState(() {
            _lines = loadedLines;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _lines = [
              DocumentLineEdit(),
              DocumentLineEdit(),
            ];
            _isLoading = false;
          });
        }
      }
    } else {
      _lines = [
        DocumentLineEdit(),
        DocumentLineEdit(),
      ];
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// ذخیره سند
  Future<void> _saveDocument() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // بررسی تاریخ
    if (_documentDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تاریخ سند الزامی است')),
      );
      return;
    }

    // بررسی ارز انتخابی
    if (_currencyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('انتخاب ارز الزامی است')),
      );
      return;
    }

    // بررسی حداقل 2 سطر
    if (_lines.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سند باید حداقل 2 سطر داشته باشد')),
      );
      return;
    }

    // بررسی اینکه تمام سطرها حساب داشته باشند
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].account == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('سطر ${i + 1} باید حساب داشته باشد')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      if (widget.document == null) {
        // ایجاد سند جدید
        await _createDocument();
      } else {
        // ویرایش سند
        await _updateDocument();
      }

      if (mounted) {
        Navigator.of(context).pop(true); // بازگشت با موفقیت
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.document == null
                ? 'سند با موفقیت ایجاد شد'
                : 'سند با موفقیت ویرایش شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// ایجاد سند جدید
  Future<void> _createDocument() async {
    final request = CreateManualDocumentRequest(
      code: _codeController.text.isEmpty ? null : _codeController.text,
      documentDate: _documentDate!,
      fiscalYearId: widget.fiscalYearId,
      currencyId: _currencyId!,
      isProforma: _isProforma,
      description: _descriptionController.text.isEmpty
          ? null
          : _descriptionController.text,
      lines: _lines.map((line) => line.toRequest()).toList(),
      projectId: _projectId,
    );

    await _service.createManualDocument(
      businessId: widget.businessId,
      request: request,
    );
  }

  /// ویرایش سند
  Future<void> _updateDocument() async {
    final request = UpdateManualDocumentRequest(
      code: _codeController.text.isEmpty ? null : _codeController.text,
      documentDate: _documentDate,
      currencyId: _currencyId,
      isProforma: _isProforma,
      description: _descriptionController.text.isEmpty
          ? null
          : _descriptionController.text,
      lines: _lines.map((line) => line.toRequest()).toList(),
      projectId: _projectId,
    );

    await _service.updateManualDocument(
      documentId: widget.document!.id,
      request: request,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditMode = widget.document != null;

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.95,
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          children: [
            // هدر
            _buildHeader(theme, isEditMode),

            // محتوای فرم
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // بخش اطلاعات هدر سند
                            _buildHeaderSection(theme),

                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 24),

                            // بخش سطرهای سند
                            DocumentLinesEditor(
                              businessId: widget.businessId,
                              initialLines: _lines,
                              onChanged: (lines) {
                                setState(() {
                                  _lines = lines;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // فوتر (دکمه‌های ذخیره و انصراف)
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  /// ساخت هدر دیالوگ
  Widget _buildHeader(ThemeData theme, bool isEditMode) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Row(
        children: [
          Icon(
            isEditMode ? Icons.edit_document : Icons.add_box,
            size: 28,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditMode ? 'ویرایش سند حسابداری' : 'ایجاد سند حسابداری جدید',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }

  /// ساخت بخش اطلاعات هدر سند
  Widget _buildHeaderSection(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات سند',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // شماره سند
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'شماره سند',
                      hintText: 'خودکار',
                      border: OutlineInputBorder(),
                      helperText: 'اختیاری - اگر خالی باشد خودکار تولید می‌شود',
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // تاریخ سند
                Expanded(
                  flex: 2,
                  child: DateInputField(
                    calendarController: widget.calendarController,
                    value: _documentDate,
                    onChanged: (date) {
                      setState(() {
                        _documentDate = date;
                      });
                    },
                    labelText: 'تاریخ سند',
                    hintText: 'انتخاب تاریخ',
                  ),
                ),
                const SizedBox(width: 16),

                // ارز (لیست ارزهای کسب‌وکار با انتخاب خودکار ارز پیش‌فرض)
                Expanded(
                  flex: 2,
                  child: CurrencyPickerWidget(
                    businessId: widget.businessId,
                    selectedCurrencyId: _currencyId,
                    onChanged: (value) {
                      setState(() {
                        _currencyId = value;
                      });
                    },
                    label: 'ارز',
                    hintText: 'انتخاب ارز',
                  ),
                ),
                const SizedBox(width: 16),

                // پروژه
                Expanded(
                  flex: 2,
                  child: ProjectSelectorWidget(
                    businessId: widget.businessId,
                    apiClient: widget.apiClient,
                    selectedProjectId: _projectId,
                    onChanged: (projectId) {
                      setState(() {
                        _projectId = projectId;
                      });
                    },
                    allowNull: true,
                    labelText: 'پروژه',
                  ),
                ),
                const SizedBox(width: 16),

                // چک‌باکس پیش‌فاکتور
                Expanded(
                  flex: 1,
                  child: CheckboxListTile(
                    title: const Text('پیش‌فاکتور'),
                    value: _isProforma,
                    onChanged: (value) {
                      setState(() {
                        _isProforma = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // توضیحات سند
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'توضیحات سند',
                hintText: 'توضیحات کلی در مورد این سند...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت فوتر دیالوگ
  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // دکمه انصراف
          SizedBox(
            height: 48,
            child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('انصراف'),
            ),
          ),
          const SizedBox(width: 12),

          // دکمه ذخیره
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveDocument,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
              label: Text(_isSaving ? 'در حال ذخیره...' : 'ذخیره سند'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

