import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../models/bank_account_model.dart';
import '../../services/bank_account_service.dart';
import 'currency_picker_widget.dart';

class BankAccountFormDialog extends StatefulWidget {
  final int businessId;
  final BankAccount? account; // null برای افزودن، مقدار برای ویرایش
  final VoidCallback? onSuccess;

  const BankAccountFormDialog({
    super.key,
    required this.businessId,
    this.account,
    this.onSuccess,
  });

  @override
  State<BankAccountFormDialog> createState() => _BankAccountFormDialogState();
}

class _BankAccountFormDialogState extends State<BankAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _bankAccountService = BankAccountService();
  bool _isLoading = false;

  // Code (unique) controls
  final _codeController = TextEditingController();
  bool _autoGenerateCode = true;

  // Controllers for basic info
  final _nameController = TextEditingController();
  final _branchController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _shebaNumberController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _posNumberController = TextEditingController();
  final _paymentIdController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isActive = true;
  bool _isDefault = false;
  int? _currencyId; // TODO: wired later to currency picker

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  void _initializeForm() {
    if (widget.account != null) {
      final account = widget.account!;
      if (account.code != null) {
        _codeController.text = account.code!;
        _autoGenerateCode = false;
      }
      _nameController.text = account.name;
      _branchController.text = account.branch ?? '';
      _accountNumberController.text = account.accountNumber ?? '';
      _shebaNumberController.text = account.shebaNumber ?? '';
      _cardNumberController.text = account.cardNumber ?? '';
      _ownerNameController.text = account.ownerName ?? '';
      _posNumberController.text = account.posNumber ?? '';
      _paymentIdController.text = account.paymentId ?? '';
      _descriptionController.text = account.description ?? '';
      _isActive = account.isActive;
      _isDefault = account.isDefault;
      _currencyId = account.currencyId;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _branchController.dispose();
    _accountNumberController.dispose();
    _shebaNumberController.dispose();
    _cardNumberController.dispose();
    _ownerNameController.dispose();
    _posNumberController.dispose();
    _paymentIdController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveBankAccount() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_currencyId == null) {
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.currency),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final accountData = {
        'code': _autoGenerateCode ? null : _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
        'name': _nameController.text.trim(),
        'branch': _branchController.text.trim().isEmpty ? null : _branchController.text.trim(),
        'account_number': _accountNumberController.text.trim().isEmpty ? null : _accountNumberController.text.trim(),
        'sheba_number': _shebaNumberController.text.trim().isEmpty ? null : _shebaNumberController.text.trim(),
        'card_number': _cardNumberController.text.trim().isEmpty ? null : _cardNumberController.text.trim(),
        'owner_name': _ownerNameController.text.trim().isEmpty ? null : _ownerNameController.text.trim(),
        'pos_number': _posNumberController.text.trim().isEmpty ? null : _posNumberController.text.trim(),
        'payment_id': _paymentIdController.text.trim().isEmpty ? null : _paymentIdController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'is_active': _isActive,
        'is_default': _isDefault,
        'currency_id': _currencyId,
      };

      if (widget.account == null) {
        // Create new bank account
        await _bankAccountService.create(
          businessId: widget.businessId,
          payload: accountData,
        );
      } else {
        // Update existing bank account
        await _bankAccountService.update(
          id: widget.account!.id!,
          payload: accountData,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        widget.onSuccess?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.account == null 
              ? 'حساب بانکی با موفقیت ایجاد شد'
              : 'حساب بانکی با موفقیت به‌روزرسانی شد'),
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
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isEditing = widget.account != null;

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Icon(
                  isEditing ? Icons.edit : Icons.add,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  isEditing ? t.editBankAccount : t.addBankAccount,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),

            // Form with tabs
            Expanded(
              child: Form(
                key: _formKey,
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(text: t.title),
                          Tab(text: t.personBankInfo),
                          Tab(text: t.settings),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          children: [
                            SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: _buildBasicInfoFields(t),
                              ),
                            ),
                            SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: _buildBankingInfoFields(t),
                              ),
                            ),
                            SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: _buildSettingsFields(t),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Actions
            const Divider(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: Text(t.cancel),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveBankAccount,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isEditing ? t.update : t.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildBasicInfoFields(AppLocalizations t) {
    return Column(
      children: [
        _buildSectionHeader(t.title),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _codeController,
                readOnly: _autoGenerateCode,
                decoration: InputDecoration(
                  labelText: t.code,
                  hintText: t.uniqueCodeNumeric,
                  suffixIcon: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: ToggleButtons(
                      isSelected: [_autoGenerateCode, !_autoGenerateCode],
                      borderRadius: BorderRadius.circular(6),
                      constraints: const BoxConstraints(minHeight: 32, minWidth: 64),
                      onPressed: (index) {
                        setState(() {
                          _autoGenerateCode = (index == 0);
                        });
                      },
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(t.automatic),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(t.manual),
                        ),
                      ],
                    ),
                  ),
                ),
                keyboardType: TextInputType.text,
                validator: (value) {
                  if (!_autoGenerateCode) {
                    if (value == null || value.trim().isEmpty) {
                      return t.personCodeRequired;
                    }
                    if (value.trim().length < 3) {
                      return t.passwordMinLength; // fallback generic
                    }
                    if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
                      return t.codeMustBeNumeric;
                    }
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Currency picker
        CurrencyPickerWidget(
          businessId: widget.businessId,
          selectedCurrencyId: _currencyId,
          onChanged: (value) {
            setState(() {
              _currencyId = value;
            });
          },
          label: t.currency,
          hintText: t.currency,
        ),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: t.title,
            hintText: t.title,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'نام حساب الزامی است';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: t.description,
            hintText: t.description,
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildBankingInfoFields(AppLocalizations t) {
    return Column(
      children: [
        _buildSectionHeader(t.personBankInfo),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _branchController,
                decoration: InputDecoration(
                  labelText: (t.localeName == 'fa') ? 'شعبه' : 'Branch',
                  hintText: (t.localeName == 'fa') ? 'شعبه' : 'Branch',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _ownerNameController,
                decoration: InputDecoration(
                  labelText: t.owner,
                  hintText: t.owner,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _accountNumberController,
                decoration: InputDecoration(
                  labelText: t.accountNumber,
                  hintText: t.accountNumber,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _cardNumberController,
                decoration: InputDecoration(
                  labelText: t.cardNumber,
                  hintText: t.cardNumber,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _shebaNumberController,
          decoration: InputDecoration(
            labelText: t.shebaNumber,
            hintText: t.shebaNumber,
          ),
          keyboardType: TextInputType.text,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
            LengthLimitingTextInputFormatter(24),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _posNumberController,
                decoration: InputDecoration(
                  labelText: (t.localeName == 'fa') ? 'شماره پوز' : 'POS Number',
                  hintText: (t.localeName == 'fa') ? 'شماره پوز' : 'POS Number',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _paymentIdController,
                decoration: InputDecoration(
                  labelText: t.personPaymentId,
                  hintText: t.personPaymentId,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsFields(AppLocalizations t) {
    return Column(
      children: [
        _buildSectionHeader(t.settings),
        const SizedBox(height: 16),
        SwitchListTile(
          title: Text(t.active),
          subtitle: Text(t.active),
          value: _isActive,
          onChanged: (value) {
            setState(() {
              _isActive = value;
            });
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text(t.isDefault),
          subtitle: Text(t.defaultConfiguration),
          value: _isDefault,
          onChanged: (value) {
            setState(() {
              _isDefault = value;
            });
          },
        ),
      ],
    );
  }
}


