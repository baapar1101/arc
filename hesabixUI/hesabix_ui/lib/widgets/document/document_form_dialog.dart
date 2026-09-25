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
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/constants/frequent_description_scope.dart';
import 'package:hesabix_ui/widgets/inputs/frequent_description_text_field.dart';

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
  bool _dirty = false;

  // سال مالی جاری (الزامی)
  bool _loadingFiscalYear = false;
  int? _currentFiscalYearId;
  String? _currentFiscalYearTitle;
  DateTime? _currentFiscalYearStart;
  DateTime? _currentFiscalYearEnd;
  String? _fiscalYearError;

  @override
  void initState() {
    super.initState();
    _service = DocumentService(widget.apiClient);
    _currencyId = widget.currencyId; // اگر null باشد، CurrencyPickerWidget ارز پیش‌فرض را از API انتخاب می‌کند
    _documentDate = widget.initialDocumentDate ?? DateTime.now();

    _codeController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _loadCurrentFiscalYear();

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

  void _markDirty() {
    if (_dirty) return;
    if (!mounted) return;
    setState(() => _dirty = true);
  }

  Future<void> _loadCurrentFiscalYear() async {
    if (!mounted) return;
    setState(() {
      _loadingFiscalYear = true;
      _fiscalYearError = null;
    });
    try {
      final res = await widget.apiClient.get('/business/${widget.businessId}/fiscal-years/current');
      final data = (res.data is Map) ? (res.data['data'] as dynamic) : null;
      if (data == null) {
        throw Exception('سال مالی جاری یافت نشد');
      }
      final id = data['id'] as int?;
      final title = data['title'] as String?;
      final startRaw = data['start_date_raw'] ?? data['start_date'];
      final endRaw = data['end_date_raw'] ?? data['end_date'];
      DateTime? start;
      DateTime? end;
      try {
        if (startRaw != null) start = DateTime.parse(startRaw.toString());
      } catch (_) {}
      try {
        if (endRaw != null) end = DateTime.parse(endRaw.toString());
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _currentFiscalYearId = id;
        _currentFiscalYearTitle = title;
        _currentFiscalYearStart = start;
        _currentFiscalYearEnd = end;
        _loadingFiscalYear = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fiscalYearError = ErrorExtractor.forContext(e, context);
        _loadingFiscalYear = false;
      });
    }
  }

  bool get _isBalanced {
    double debit = 0;
    double credit = 0;
    for (final l in _lines) {
      debit += l.debit;
      credit += l.credit;
    }
    return (debit - credit).abs() < 0.01;
  }

  String? _validateBeforeSave() {
    if (_loadingFiscalYear) return 'در حال دریافت سال مالی جاری...';
    if (_currentFiscalYearId == null) return 'سال مالی جاری یافت نشد';
    if (_fiscalYearError != null) return 'خطا در دریافت سال مالی جاری';
    if (_documentDate == null) return 'تاریخ سند الزامی است';
    if (_currentFiscalYearStart != null && _documentDate!.isBefore(_currentFiscalYearStart!)) {
      return 'تاریخ سند خارج از بازه سال مالی جاری است';
    }
    if (_currentFiscalYearEnd != null && _documentDate!.isAfter(_currentFiscalYearEnd!)) {
      return 'تاریخ سند خارج از بازه سال مالی جاری است';
    }
    if (_currencyId == null) return 'انتخاب ارز الزامی است';
    if (_lines.length < 2) return 'سند باید حداقل 2 سطر داشته باشد';
    for (int i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (l.account == null) return 'سطر ${i + 1} باید حساب داشته باشد';
      if (l.debit == 0 && l.credit == 0) return 'سطر ${i + 1} باید بدهکار یا بستانکار داشته باشد';
      if (l.debit > 0 && l.credit > 0) return 'سطر ${i + 1} نمی‌تواند همزمان بدهکار و بستانکار داشته باشد';
    }
    if (!_isBalanced) return 'سند متوازن نیست';
    return null;
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

  Future<bool> _confirmDiscardChanges() async {
    if (!_dirty || _isSaving) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خروج بدون ذخیره؟'),
        content: const Text('تغییرات شما ذخیره نشده است. آیا می‌خواهید خارج شوید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ادامه ویرایش')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _handleClose() async {
    final ok = await _confirmDiscardChanges();
    if (!ok) return;
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  /// ذخیره سند
  Future<void> _saveDocument() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final preError = _validateBeforeSave();
    if (preError != null) {
      SnackBarHelper.show(context, message: preError);
      return;
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
        _dirty = false;
        Navigator.of(context).pop(true); // بازگشت با موفقیت
        SnackBarHelper.showSuccess(context, message: widget.document == null
                ? 'سند با موفقیت ایجاد شد'
                : 'سند با موفقیت ویرایش شد');
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
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
      fiscalYearIdOverride: _currentFiscalYearId,
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
      fiscalYearIdOverride: _currentFiscalYearId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditMode = widget.document != null;

    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    final content = Column(
      children: [
        _buildHeader(theme, isEditMode, isMobile),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 12 : 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeaderSection(theme, isMobile),
                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 18),
                        DocumentLinesEditor(
                          businessId: widget.businessId,
                          initialLines: _lines,
                          onChanged: (lines) {
                            setState(() {
                              _lines = lines;
                              _dirty = true;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        _buildFooter(theme),
      ],
    );

    if (isMobile) {
      return PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          await _handleClose();
        },
        child: Dialog.fullscreen(
          child: SafeArea(child: content),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleClose();
      },
      child: Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.95,
          constraints: const BoxConstraints(maxWidth: 1400),
          child: content,
        ),
      ),
    );
  }

  /// ساخت هدر دیالوگ
  Widget _buildHeader(ThemeData theme, bool isEditMode, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
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
            onPressed: _handleClose,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }

  /// ساخت بخش اطلاعات هدر سند
  Widget _buildHeaderSection(ThemeData theme, bool isMobile) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 20),
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
            _buildFiscalYearBanner(theme),
            const SizedBox(height: 12),
            if (isMobile) _buildHeaderFieldsMobile(theme) else _buildHeaderFieldsDesktop(theme),
            const SizedBox(height: 16),

            // توضیحات سند
            FrequentDescriptionTextField(
              businessId: widget.businessId,
              scope: FrequentDescriptionScope.document,
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

  Widget _buildFiscalYearBanner(ThemeData theme) {
    final title = _currentFiscalYearTitle ?? '-';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: _loadingFiscalYear
                ? const Text('در حال دریافت سال مالی جاری...')
                : Text(
                    'سال مالی جاری: $title — ثبت سند فقط در سال مالی جاری مجاز است',
                    style: theme.textTheme.bodySmall,
                  ),
          ),
          if (_fiscalYearError != null) ...[
            const SizedBox(width: 8),
            Tooltip(message: _fiscalYearError!, child: Icon(Icons.error_outline, color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderFieldsDesktop(ThemeData theme) {
    return Row(
      children: [
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
        Expanded(
          flex: 2,
          child: DateInputField(
            calendarController: widget.calendarController,
            value: _documentDate,
            onChanged: (date) {
              setState(() => _documentDate = date);
              _markDirty();
            },
            labelText: 'تاریخ سند',
            hintText: 'انتخاب تاریخ',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: CurrencyPickerWidget(
            businessId: widget.businessId,
            selectedCurrencyId: _currencyId,
            onChanged: (value) {
              setState(() => _currencyId = value);
              _markDirty();
            },
            label: 'ارز',
            hintText: 'انتخاب ارز',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ProjectSelectorWidget(
            businessId: widget.businessId,
            apiClient: widget.apiClient,
            selectedProjectId: _projectId,
            onChanged: (projectId) {
              setState(() => _projectId = projectId);
              _markDirty();
            },
            allowNull: true,
            labelText: 'پروژه',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 1,
          child: CheckboxListTile(
            title: const Text('پیش‌نویس'),
            value: _isProforma,
            onChanged: (value) {
              setState(() => _isProforma = value ?? false);
              _markDirty();
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderFieldsMobile(ThemeData theme) {
    return Column(
      children: [
        TextFormField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'شماره سند',
            hintText: 'خودکار',
            border: OutlineInputBorder(),
            helperText: 'اختیاری - اگر خالی باشد خودکار تولید می‌شود',
          ),
        ),
        const SizedBox(height: 12),
        DateInputField(
          calendarController: widget.calendarController,
          value: _documentDate,
          onChanged: (date) {
            setState(() => _documentDate = date);
            _markDirty();
          },
          labelText: 'تاریخ سند',
          hintText: 'انتخاب تاریخ',
        ),
        const SizedBox(height: 12),
        CurrencyPickerWidget(
          businessId: widget.businessId,
          selectedCurrencyId: _currencyId,
          onChanged: (value) {
            setState(() => _currencyId = value);
            _markDirty();
          },
          label: 'ارز',
          hintText: 'انتخاب ارز',
        ),
        const SizedBox(height: 12),
        ProjectSelectorWidget(
          businessId: widget.businessId,
          apiClient: widget.apiClient,
          selectedProjectId: _projectId,
          onChanged: (projectId) {
            setState(() => _projectId = projectId);
            _markDirty();
          },
          allowNull: true,
          labelText: 'پروژه',
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          title: const Text('پیش‌نویس'),
          value: _isProforma,
          onChanged: (value) {
            setState(() => _isProforma = value ?? false);
            _markDirty();
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// ساخت فوتر دیالوگ
  Widget _buildFooter(ThemeData theme) {
    final validationError = _validateBeforeSave();
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
            onPressed: _isSaving ? null : _handleClose,
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
            onPressed: (_isSaving || validationError != null) ? null : _saveDocument,
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

